create type public.capture_scope as enum ('SCHEDULE', 'HOUSEHOLD', 'SHOPPING', 'GENERAL_ADMIN');

alter table public.captures add column scope public.capture_scope not null;

create table private.capture_idempotency (
  auth_user_id uuid not null,
  idempotency_key uuid not null,
  capture_id uuid not null references public.captures (id),
  created_at timestamptz not null default now(),
  primary key (auth_user_id, idempotency_key)
);

alter table private.capture_idempotency enable row level security;
revoke all on private.capture_idempotency from public, anon, authenticated;

create or replace function public.command_capture_text(
  p_auth_user_id uuid,
  p_scope public.capture_scope,
  p_raw_text text,
  p_sensitivity_class public.sensitivity_class,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account_id uuid;
  v_capture_id uuid := extensions.gen_random_uuid();
  v_status public.capture_status := case when p_sensitivity_class = 'PRIVATE' then 'STORED' else 'FAILED_SAFE' end;
begin
  if char_length(pg_catalog.btrim(coalesce(p_raw_text, ''))) not between 1 and 2000 then
    raise exception 'invalid capture request' using errcode = '22023';
  end if;

  select id into v_account_id
    from public.accounts
    where auth_user_id = p_auth_user_id and status = 'ACTIVE';

  if not found or not exists (
    select 1 from public.consents
    where account_id = v_account_id and consent_type = 'P1_CORE'
    order by occurred_at desc
    limit 1
  ) then
    raise exception 'active consent is unavailable' using errcode = '42501';
  end if;

  if (select status from public.consents where account_id = v_account_id and consent_type = 'P1_CORE' order by occurred_at desc limit 1) <> 'ACCEPTED' then
    raise exception 'active consent is unavailable' using errcode = '42501';
  end if;

  insert into private.capture_idempotency (auth_user_id, idempotency_key, capture_id)
  values (p_auth_user_id, p_idempotency_key, v_capture_id)
  on conflict do nothing;

  if not found then
    select capture_id into v_capture_id
      from private.capture_idempotency
      where auth_user_id = p_auth_user_id and idempotency_key = p_idempotency_key;
    return v_capture_id;
  end if;

  insert into public.captures (id, account_id, scope, status, sensitivity_class, external_ai_allowed)
  values (v_capture_id, v_account_id, p_scope, v_status, p_sensitivity_class, false);

  if p_sensitivity_class <> 'SECRET' then
    insert into private.capture_raws (capture_id, account_id, raw_text)
    values (v_capture_id, v_account_id, pg_catalog.btrim(p_raw_text));
  end if;

  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (
    v_account_id,
    p_auth_user_id::text,
    case when p_sensitivity_class = 'SECRET' then 'CAPTURE_REJECTED' else 'CAPTURE_STORED' end,
    'capture',
    v_capture_id
  );

  return v_capture_id;
end;
$$;

revoke all on function public.command_capture_text(uuid, public.capture_scope, text, public.sensitivity_class, uuid) from public, anon, authenticated;
grant execute on function public.command_capture_text(uuid, public.capture_scope, text, public.sensitivity_class, uuid) to service_role;
