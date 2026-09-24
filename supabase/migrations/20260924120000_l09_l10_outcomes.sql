create unique index loop_events_soc_once
  on public.loop_events (loop_id, basis_revision) where event_type = 'SOC_RECORDED';
create unique index loop_events_ownership_once
  on public.loop_events (loop_id, basis_revision) where event_type = 'OWNERSHIP_MEASURED';

create or replace function public.command_loop_action(p_auth_user_id uuid, p_loop_id uuid, p_action text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_loop public.open_loops%rowtype;
  v_has_ack boolean;
begin
  if p_action not in ('MARK_DONE', 'MARK_NOT_YET', 'END_CONTEXT', 'REOPEN_CONTEXT') then
    raise exception 'invalid loop action' using errcode = '22023';
  end if;
  select l.* into v_loop from public.open_loops l
    join public.accounts a on a.id = l.account_id
    where l.id = p_loop_id and a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
      and (select co.status from public.consents co where co.account_id = a.id and co.consent_type = 'P1_CORE'
           order by co.occurred_at desc limit 1) = 'ACCEPTED'
    for update of l;
  if not found then raise exception 'loop unavailable' using errcode = '42501'; end if;

  if p_action = 'REOPEN_CONTEXT' then
    if v_loop.status <> 'CLOSED' then return 'NO_CHANGE'; end if;
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values (p_loop_id, v_loop.account_id, 'CONTEXT_REOPENED', 'USER', v_loop.revision + 1);
    update public.open_loops set status = 'ACTIVE', effective_state = 'UNKNOWN',
      revision = revision + 1, activated_at = null, resolved_at = null, closed_at = null,
      next_evaluation_at = null, updated_at = now() where id = p_loop_id;
    return 'REOPENED';
  end if;

  if v_loop.status <> 'ACTIVE' then return 'NO_CHANGE'; end if;
  if p_action = 'END_CONTEXT' then
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision,
      payload)
    values (p_loop_id, v_loop.account_id, 'CONTEXT_END_REQUESTED', 'USER', v_loop.revision,
      '{"reason_code":"NO_LONGER_REQUIRED"}'::jsonb);
    update public.open_loops set status = 'CLOSED', effective_state = 'NO_LONGER_REQUIRED',
      next_evaluation_at = null, closed_at = now(), updated_at = now() where id = p_loop_id;
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values (p_loop_id, v_loop.account_id, 'CONTEXT_CLOSED', 'SYSTEM', v_loop.revision);
    return 'CLOSED';
  end if;

  v_has_ack := exists (select 1 from public.loop_events e
    where e.loop_id = p_loop_id and e.event_type = 'OFFLOAD_RECEIPT_ACKED'
      and e.basis_revision = v_loop.revision);
  if not v_has_ack or v_loop.activated_at is null then
    raise exception 'receipt acknowledgement required' using errcode = '42501';
  end if;

  if p_action = 'MARK_DONE' then
    if v_loop.effective_state = 'SATISFIED' then return 'NO_CHANGE'; end if;
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values (p_loop_id, v_loop.account_id, 'USER_MARKED_DONE', 'USER', v_loop.revision);
    update public.open_loops set status = 'CLOSED', effective_state = 'SATISFIED', resolved_at = now(),
      next_evaluation_at = null, updated_at = now() where id = p_loop_id;
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values (p_loop_id, v_loop.account_id, 'SOC_RECORDED', 'SYSTEM', v_loop.revision)
    on conflict do nothing;
    insert into telemetry.product_events (account_id, loop_id, event_name)
    values (v_loop.account_id, p_loop_id, 'soc_recorded');
    return 'DONE';
  end if;

  insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
  values (p_loop_id, v_loop.account_id, 'USER_MARKED_NOT_YET', 'USER', v_loop.revision);
  update public.open_loops set effective_state = 'UNSATISFIED', resolved_at = null,
    next_evaluation_at = now() + interval '1 day', updated_at = now() where id = p_loop_id;
  return 'NOT_YET';
end;
$$;

create or replace function public.command_record_ownership(
  p_auth_user_id uuid, p_loop_id uuid, p_result text
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_loop public.open_loops%rowtype;
begin
  if p_result not in ('OWNED', 'PARALLEL', 'UNKNOWN') then
    raise exception 'invalid ownership result' using errcode = '22023';
  end if;
  select l.* into v_loop from public.open_loops l
    join public.accounts a on a.id = l.account_id
    where l.id = p_loop_id and a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
      and exists (select 1 from public.loop_events e where e.loop_id = l.id
                  and e.basis_revision = l.revision and e.event_type = 'SOC_RECORDED')
    for update of l;
  if not found then raise exception 'SOC unavailable' using errcode = '42501'; end if;
  if exists (select 1 from public.loop_events e where e.loop_id = p_loop_id
             and e.basis_revision = v_loop.revision and e.event_type = 'OWNERSHIP_MEASURED') then
    return 'ALREADY_RECORDED';
  end if;
  insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision, payload)
  values (p_loop_id, v_loop.account_id, 'OWNERSHIP_MEASURED', 'USER', v_loop.revision,
    jsonb_build_object('result', p_result));
  insert into telemetry.product_events (account_id, loop_id, event_name, properties)
  values (v_loop.account_id, p_loop_id, 'ownership_measured', jsonb_build_object('result', p_result));
  return 'RECORDED';
end;
$$;

revoke all on function public.command_loop_action(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.command_record_ownership(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.command_loop_action(uuid, uuid, text) to service_role;
grant execute on function public.command_record_ownership(uuid, uuid, text) to service_role;

create table telemetry.deleted_account_totals (
  singleton boolean primary key default true check (singleton),
  eligible_loops bigint not null default 0,
  activated_loops bigint not null default 0,
  valid_socs bigint not null default 0,
  owned_socs bigint not null default 0,
  ai_cost_usd numeric not null default 0
);
insert into telemetry.deleted_account_totals (singleton) values (true);
alter table telemetry.deleted_account_totals enable row level security;
revoke all on telemetry.deleted_account_totals from public, anon, authenticated;

create or replace function private.p1_metrics()
returns table (
  eligible_loops bigint, activated_loops bigint, valid_socs bigint,
  owned_socs bigint, ai_cost_usd numeric, cost_per_eligible_capture numeric,
  cost_per_valid_soc numeric
)
language sql security definer set search_path = ''
as $$
  with eligible as (
    select l.id, l.revision, l.account_id, l.offload_ready_at
      from public.open_loops l where l.offload_ready_at is not null
  ), facts as (
    select e.id,
      exists (select 1 from public.loop_events a where a.loop_id = e.id
                and a.basis_revision = e.revision and a.event_type = 'OFFLOAD_RECEIPT_ACKED'
                and a.occurred_at <= e.offload_ready_at + interval '7 days') as activated,
      exists (select 1 from public.loop_events s where s.loop_id = e.id
                and s.basis_revision = e.revision and s.event_type = 'SOC_RECORDED') as soc,
      exists (select 1 from public.loop_events o where o.loop_id = e.id
                and o.basis_revision = e.revision and o.event_type = 'OWNERSHIP_MEASURED'
                and o.payload->>'result' = 'OWNED') as owned
      from eligible e
  ), totals as (
    select count(*) as eligible, count(*) filter (where activated) as activation,
      count(*) filter (where soc) as socs,
      count(*) filter (where soc and owned) as owned_socs from facts
  ), cost as (
    select coalesce(sum((properties->>'cost_usd')::numeric), 0) as usd
      from telemetry.product_events where event_name = 'ai_call_recorded'
  )
  select totals.eligible + deleted.eligible_loops,
    totals.activation + deleted.activated_loops,
    totals.socs + deleted.valid_socs,
    totals.owned_socs + deleted.owned_socs,
    cost.usd + deleted.ai_cost_usd,
    (cost.usd + deleted.ai_cost_usd) / nullif(totals.eligible + deleted.eligible_loops, 0),
    (cost.usd + deleted.ai_cost_usd) / nullif(totals.socs + deleted.valid_socs, 0)
    from totals cross join cost cross join telemetry.deleted_account_totals deleted;
$$;
revoke all on function private.p1_metrics() from public, anon, authenticated;
grant execute on function private.p1_metrics() to service_role;
