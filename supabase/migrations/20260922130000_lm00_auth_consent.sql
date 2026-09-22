create schema if not exists private;
create extension if not exists pgcrypto with schema extensions;

create type public.account_status as enum ('ACTIVE', 'DELETION_PENDING', 'DELETED');
create type public.consent_status as enum ('ACCEPTED', 'WITHDRAWN');

create table public.accounts (
  id uuid primary key default extensions.gen_random_uuid(),
  auth_user_id uuid unique not null,
  status public.account_status not null default 'ACTIVE',
  timezone text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.consents (
  id uuid primary key default extensions.gen_random_uuid(),
  account_id uuid not null references public.accounts (id),
  consent_type text not null,
  version text not null,
  status public.consent_status not null,
  adult_declared boolean not null check (adult_declared),
  occurred_at timestamptz not null default now()
);

create index consents_account_occurred_at_idx on public.consents (account_id, occurred_at desc);

create table private.audit_events (
  id uuid primary key default extensions.gen_random_uuid(),
  account_id uuid references public.accounts (id),
  actor_principal text not null,
  action text not null,
  target_type text not null,
  target_id uuid,
  occurred_at timestamptz not null default now()
);

create table private.auth_challenges (
  id uuid primary key default extensions.gen_random_uuid(),
  account_id uuid not null references public.accounts (id),
  auth_user_id uuid not null,
  session_id text not null,
  action_kind text not null check (action_kind in ('WITHDRAW_CONSENT', 'DELETE_RAW_CAPTURE', 'DELETE_ACCOUNT')),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index auth_challenges_lookup_idx
  on private.auth_challenges (auth_user_id, session_id, action_kind, created_at desc);

create table private.recent_auth_proofs (
  id uuid primary key default extensions.gen_random_uuid(),
  challenge_id uuid not null references private.auth_challenges (id),
  account_id uuid not null references public.accounts (id),
  auth_user_id uuid not null,
  session_id text not null,
  action_kind text not null check (action_kind in ('WITHDRAW_CONSENT', 'DELETE_RAW_CAPTURE', 'DELETE_ACCOUNT')),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table private.command_idempotency (
  auth_user_id uuid not null,
  command text not null check (command in ('ACCEPT_CONSENT', 'WITHDRAW_CONSENT')),
  idempotency_key uuid not null,
  request_hash text not null,
  result_account_id uuid not null references public.accounts (id),
  created_at timestamptz not null default now(),
  primary key (auth_user_id, command, idempotency_key)
);

alter table public.accounts enable row level security;
alter table public.consents enable row level security;
alter table private.audit_events enable row level security;
alter table private.auth_challenges enable row level security;
alter table private.recent_auth_proofs enable row level security;
alter table private.command_idempotency enable row level security;

revoke all on public.accounts, public.consents from anon, authenticated;
grant select on public.accounts, public.consents to authenticated;

create policy "accounts: owner can read"
  on public.accounts for select to authenticated
  using ((select auth.uid()) = auth_user_id);

create policy "consents: owner can read"
  on public.consents for select to authenticated
  using (
    account_id = (
      select id from public.accounts where auth_user_id = (select auth.uid())
    )
  );

revoke all on schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;

create or replace function public.command_accept_p1_consent(
  p_auth_user_id uuid,
  p_timezone text,
  p_consent_version text,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account_id uuid;
  v_status public.account_status;
  v_existing_hash text;
  v_existing_account_id uuid;
  v_request_hash text := md5(concat_ws(':', p_timezone, p_consent_version));
  v_latest_status public.consent_status;
  v_latest_version text;
begin
  if p_consent_version = '' or not exists (
    select 1 from pg_catalog.pg_timezone_names where name = p_timezone
  ) then
    raise exception 'invalid consent request' using errcode = '22023';
  end if;

  select id, status into v_account_id, v_status
    from public.accounts where auth_user_id = p_auth_user_id for update;

  if not found then
    insert into public.accounts (auth_user_id, timezone)
    values (p_auth_user_id, p_timezone)
    returning id, status into v_account_id, v_status;
  end if;

  if v_status <> 'ACTIVE' then
    raise exception 'account is unavailable' using errcode = '42501';
  end if;

  insert into private.command_idempotency (
    auth_user_id, command, idempotency_key, request_hash, result_account_id
  ) values (
    p_auth_user_id, 'ACCEPT_CONSENT', p_idempotency_key, v_request_hash, v_account_id
  ) on conflict do nothing;

  if not found then
    select request_hash, result_account_id into v_existing_hash, v_existing_account_id
      from private.command_idempotency
      where auth_user_id = p_auth_user_id
        and command = 'ACCEPT_CONSENT'
        and idempotency_key = p_idempotency_key;

    if v_existing_hash <> v_request_hash then
      raise exception 'idempotency key mismatch' using errcode = '22023';
    end if;

    return v_existing_account_id;
  end if;

  select status, version into v_latest_status, v_latest_version
    from public.consents
    where account_id = v_account_id and consent_type = 'P1_CORE'
    order by occurred_at desc
    limit 1;

  if v_latest_status is distinct from 'ACCEPTED' or v_latest_version is distinct from p_consent_version then
    insert into public.consents (account_id, consent_type, version, status, adult_declared)
    values (v_account_id, 'P1_CORE', p_consent_version, 'ACCEPTED', true);

    insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
    values (v_account_id, p_auth_user_id::text, 'ACCEPT_CONSENT', 'account', v_account_id);
  end if;

  return v_account_id;
end;
$$;

create or replace function public.command_start_recent_auth(
  p_auth_user_id uuid,
  p_session_id text,
  p_action_kind text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account_id uuid;
  v_challenge_id uuid;
  v_created_at timestamptz;
begin
  if p_action_kind not in ('WITHDRAW_CONSENT', 'DELETE_RAW_CAPTURE', 'DELETE_ACCOUNT') then
    raise exception 'invalid action' using errcode = '22023';
  end if;

  select id into v_account_id
    from public.accounts
    where auth_user_id = p_auth_user_id and status = 'ACTIVE';

  if not found then
    raise exception 'account is unavailable' using errcode = '42501';
  end if;

  select created_at into v_created_at
    from private.auth_challenges
    where auth_user_id = p_auth_user_id
      and session_id = p_session_id
      and action_kind = p_action_kind
      and used_at is null
    order by created_at desc
    limit 1;

  if v_created_at > now() - interval '60 seconds' then
    raise exception 'recent auth resend is not available' using errcode = '42901';
  end if;

  insert into private.auth_challenges (
    account_id, auth_user_id, session_id, action_kind, expires_at
  ) values (
    v_account_id, p_auth_user_id, p_session_id, p_action_kind, now() + interval '10 minutes'
  ) returning id into v_challenge_id;

  return v_challenge_id;
end;
$$;

create or replace function public.command_verify_recent_auth(
  p_auth_user_id uuid,
  p_session_id text,
  p_action_kind text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_challenge private.auth_challenges;
  v_proof_id uuid;
begin
  select * into v_challenge
    from private.auth_challenges
    where auth_user_id = p_auth_user_id
      and session_id = p_session_id
      and action_kind = p_action_kind
      and used_at is null
      and expires_at > now()
    order by created_at desc
    limit 1
    for update;

  if not found then
    raise exception 'recent auth challenge is unavailable' using errcode = '42501';
  end if;

  update private.auth_challenges set used_at = now() where id = v_challenge.id;

  insert into private.recent_auth_proofs (
    challenge_id, account_id, auth_user_id, session_id, action_kind, expires_at
  ) values (
    v_challenge.id, v_challenge.account_id, p_auth_user_id, p_session_id,
    p_action_kind, now() + interval '10 minutes'
  ) returning id into v_proof_id;

  return v_proof_id;
end;
$$;

create or replace function public.command_withdraw_p1_consent(
  p_auth_user_id uuid,
  p_session_id text,
  p_proof_id uuid,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account_id uuid;
  v_existing_hash text;
  v_existing_account_id uuid;
  v_proof private.recent_auth_proofs;
  v_version text;
  v_request_hash text := md5(p_proof_id::text);
begin
  select id into v_account_id
    from public.accounts where auth_user_id = p_auth_user_id for update;

  if not found then
    raise exception 'account is unavailable' using errcode = '42501';
  end if;

  insert into private.command_idempotency (
    auth_user_id, command, idempotency_key, request_hash, result_account_id
  ) values (
    p_auth_user_id, 'WITHDRAW_CONSENT', p_idempotency_key, v_request_hash, v_account_id
  ) on conflict do nothing;

  if not found then
    select request_hash, result_account_id into v_existing_hash, v_existing_account_id
      from private.command_idempotency
      where auth_user_id = p_auth_user_id
        and command = 'WITHDRAW_CONSENT'
        and idempotency_key = p_idempotency_key;

    if v_existing_hash <> v_request_hash then
      raise exception 'idempotency key mismatch' using errcode = '22023';
    end if;

    return v_existing_account_id;
  end if;

  select * into v_proof
    from private.recent_auth_proofs
    where id = p_proof_id
      and account_id = v_account_id
      and auth_user_id = p_auth_user_id
      and session_id = p_session_id
      and action_kind = 'WITHDRAW_CONSENT'
      and used_at is null
      and expires_at > now()
    for update;

  if not found then
    raise exception 'recent auth proof is unavailable' using errcode = '42501';
  end if;

  select version into v_version
    from public.consents
    where account_id = v_account_id and consent_type = 'P1_CORE'
    order by occurred_at desc
    limit 1;

  if v_version is null then
    raise exception 'active consent is unavailable' using errcode = '42501';
  end if;

  update private.recent_auth_proofs set used_at = now() where id = v_proof.id;
  update public.accounts set status = 'DELETION_PENDING' where id = v_account_id;
  insert into public.consents (account_id, consent_type, version, status, adult_declared)
  values (v_account_id, 'P1_CORE', v_version, 'WITHDRAWN', true);
  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (v_account_id, p_auth_user_id::text, 'WITHDRAW_CONSENT', 'account', v_account_id);

  return v_account_id;
end;
$$;

revoke all on function public.command_accept_p1_consent(uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public.command_start_recent_auth(uuid, text, text) from public, anon, authenticated;
revoke all on function public.command_verify_recent_auth(uuid, text, text) from public, anon, authenticated;
revoke all on function public.command_withdraw_p1_consent(uuid, text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.command_accept_p1_consent(uuid, text, text, uuid) to service_role;
grant execute on function public.command_start_recent_auth(uuid, text, text) to service_role;
grant execute on function public.command_verify_recent_auth(uuid, text, text) to service_role;
grant execute on function public.command_withdraw_p1_consent(uuid, text, uuid, uuid) to service_role;
