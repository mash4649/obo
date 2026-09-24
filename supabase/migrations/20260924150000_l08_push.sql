create table private.device_installations (
  id uuid primary key,
  account_id uuid not null references public.accounts(id) on delete cascade,
  expo_token text not null,
  permission_status text not null check (permission_status = 'AUTHORIZED'),
  opted_in boolean not null default true,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INVALID')),
  updated_at timestamptz not null default now()
);
create index device_installations_account_idx on private.device_installations(account_id, status, updated_at desc);
revoke all on private.device_installations from public, anon, authenticated;

create table private.push_attempts (
  delivery_id uuid primary key references public.deliveries(id) on delete cascade,
  installation_id uuid references private.device_installations(id) on delete set null,
  state text not null check (state in ('CLAIMED', 'TICKET', 'RECONCILING', 'RECEIPT_OK', 'RECEIPT_ERROR')),
  ticket_id text,
  claimed_at timestamptz not null default now(),
  ticket_at timestamptz,
  reconciled_at timestamptz
);
create index push_attempts_due_idx on private.push_attempts(state, ticket_at);
revoke all on private.push_attempts from public, anon, authenticated;

create or replace function public.command_register_push(
  p_auth_user_id uuid, p_installation_id uuid, p_expo_token text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_account_id uuid;
begin
  if p_expo_token !~ '^(Expo|Exponent)PushToken\[[A-Za-z0-9_-]{10,200}\]$' then
    raise exception 'invalid push token' using errcode = '22023';
  end if;
  select a.id into v_account_id
    from public.accounts a where a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
      and (select c.status from public.consents c where c.account_id = a.id
           and c.consent_type = 'P1_CORE' order by c.occurred_at desc limit 1) = 'ACCEPTED'
    for update;
  if not found then raise exception 'account unavailable' using errcode = '42501'; end if;
  insert into private.device_installations(id, account_id, expo_token, permission_status)
    values (p_installation_id, v_account_id, p_expo_token, 'AUTHORIZED')
    on conflict (id) do update set
      expo_token = excluded.expo_token, opted_in = true, status = 'ACTIVE', updated_at = now()
      where private.device_installations.account_id = v_account_id;
  if not found then raise exception 'installation unavailable' using errcode = '42501'; end if;
end;
$$;

create or replace function public.command_revoke_push(
  p_auth_user_id uuid, p_installation_id uuid
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update private.device_installations i set opted_in = false, status = 'INVALID', updated_at = now()
    from public.accounts a
    where i.id = p_installation_id and i.account_id = a.id and a.auth_user_id = p_auth_user_id;
end;
$$;

create or replace function private.invalidate_account_push()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.status <> 'ACTIVE' then
    update private.device_installations set opted_in = false, status = 'INVALID', updated_at = now()
      where account_id = new.id and status = 'ACTIVE';
  end if;
  return new;
end;
$$;
create trigger invalidate_account_push after update of status on public.accounts
  for each row when (old.status is distinct from new.status)
  execute function private.invalidate_account_push();

create or replace function public.command_claim_push(p_now timestamptz default now())
returns table(delivery_id uuid, installation_id uuid, expo_token text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_delivery_id uuid;
  v_installation_id uuid;
  v_token text;
begin
  select d.id, i.id, i.expo_token into v_delivery_id, v_installation_id, v_token
    from public.deliveries d
    join public.open_loops l on l.id = d.loop_id
    join public.accounts a on a.id = d.account_id
    join lateral (
      select i.id, i.expo_token from private.device_installations i
      where i.account_id = d.account_id and i.status = 'ACTIVE'
        and i.opted_in and i.permission_status = 'AUTHORIZED'
      order by i.updated_at desc, i.id limit 1
    ) i on true
    where d.channel = 'IN_APP' and d.status = 'PENDING'
      and l.status = 'ACTIVE' and l.effective_state = 'UNSATISFIED'
      and l.revision = d.basis_revision and a.status = 'ACTIVE'
      and (select c.status from public.consents c where c.account_id = a.id
           and c.consent_type = 'P1_CORE' order by c.occurred_at desc limit 1) = 'ACCEPTED'
      and not exists (select 1 from private.push_attempts p where p.delivery_id = d.id)
    order by d.created_at, d.id limit 1 for update of d skip locked;
  if not found then return; end if;
  insert into private.push_attempts(delivery_id, installation_id, state, claimed_at)
    values (v_delivery_id, v_installation_id, 'CLAIMED', p_now);
  return query select v_delivery_id, v_installation_id, v_token;
end;
$$;

create or replace function public.command_push_still_allowed(
  p_delivery_id uuid, p_installation_id uuid, p_expo_token text
) returns boolean
language sql security definer set search_path = ''
as $$
  select exists (
    select 1 from private.push_attempts p
      join public.deliveries d on d.id = p.delivery_id
      join public.open_loops l on l.id = d.loop_id
      join public.accounts a on a.id = d.account_id
      join private.device_installations i on i.id = p.installation_id
    where p.delivery_id = p_delivery_id and p.state = 'CLAIMED'
      and p.installation_id = p_installation_id and i.expo_token = p_expo_token
      and i.status = 'ACTIVE' and i.opted_in and i.permission_status = 'AUTHORIZED'
      and i.account_id = d.account_id and a.status = 'ACTIVE'
      and d.channel = 'IN_APP' and d.status = 'PENDING'
      and l.status = 'ACTIVE' and l.effective_state = 'UNSATISFIED'
      and l.revision = d.basis_revision
      and (select c.status from public.consents c where c.account_id = a.id
           and c.consent_type = 'P1_CORE' order by c.occurred_at desc limit 1) = 'ACCEPTED'
  );
$$;

create or replace function public.command_record_push_ticket(
  p_delivery_id uuid, p_ticket_id text, p_now timestamptz default now()
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update private.push_attempts set
    state = case when p_ticket_id is null then 'RECEIPT_ERROR' else 'TICKET' end,
    ticket_id = p_ticket_id, ticket_at = p_now
    where delivery_id = p_delivery_id and state = 'CLAIMED';
end;
$$;

create or replace function public.command_claim_push_receipt(p_now timestamptz default now())
returns table(delivery_id uuid, ticket_id text)
language plpgsql security definer set search_path = ''
as $$
begin
  return query
    update private.push_attempts p set state = 'RECONCILING', reconciled_at = p_now
    where p.delivery_id = (
      select q.delivery_id from private.push_attempts q
      where q.state = 'TICKET' and q.ticket_at <= p_now - interval '15 minutes'
      order by q.ticket_at, q.delivery_id limit 1 for update skip locked
    )
    returning p.delivery_id, p.ticket_id;
end;
$$;

create or replace function public.command_finish_push_receipt(
  p_delivery_id uuid, p_ok boolean, p_device_not_registered boolean
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_installation_id uuid;
begin
  update private.push_attempts set state = case when p_ok then 'RECEIPT_OK' else 'RECEIPT_ERROR' end
    where delivery_id = p_delivery_id and state = 'RECONCILING'
    returning installation_id into v_installation_id;
  if p_device_not_registered and v_installation_id is not null then
    update private.device_installations set status = 'INVALID', opted_in = false, updated_at = now()
      where id = v_installation_id;
  end if;
end;
$$;

revoke all on function public.command_register_push(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.command_revoke_push(uuid, uuid) from public, anon, authenticated;
revoke all on function public.command_claim_push(timestamptz) from public, anon, authenticated;
revoke all on function public.command_push_still_allowed(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.command_record_push_ticket(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.command_claim_push_receipt(timestamptz) from public, anon, authenticated;
revoke all on function public.command_finish_push_receipt(uuid, boolean, boolean) from public, anon, authenticated;
grant execute on function public.command_register_push(uuid, uuid, text) to service_role;
grant execute on function public.command_revoke_push(uuid, uuid) to service_role;
grant execute on function public.command_claim_push(timestamptz) to service_role;
grant execute on function public.command_push_still_allowed(uuid, uuid, text) to service_role;
grant execute on function public.command_record_push_ticket(uuid, text, timestamptz) to service_role;
grant execute on function public.command_claim_push_receipt(timestamptz) to service_role;
grant execute on function public.command_finish_push_receipt(uuid, boolean, boolean) to service_role;
