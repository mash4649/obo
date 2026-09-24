create table private.p1_cohort_loops (
  loop_id uuid primary key references public.open_loops(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  eligible_at timestamptz not null,
  evidence_ref uuid not null,
  verified_by text not null check (char_length(verified_by) between 1 and 80),
  verified_at timestamptz not null default now()
);
create index p1_cohort_account_idx on private.p1_cohort_loops(account_id);
revoke all on private.p1_cohort_loops from public, anon, authenticated;

create or replace function private.tag_p1_eligible_loop(
  p_loop_id uuid, p_evidence_ref uuid, p_verified_by text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_loop public.open_loops%rowtype;
begin
  if p_evidence_ref is null or p_verified_by is null or char_length(p_verified_by) not between 1 and 80 then
    raise exception 'genuine-loop evidence required' using errcode = '22023';
  end if;
  select l.* into v_loop
    from public.open_loops l
    join public.accounts a on a.id = l.account_id
    join public.captures c on c.id = l.capture_id
    where l.id = p_loop_id and l.status = 'ACTIVE' and l.offload_ready_at is not null
      and l.confirmation_question is null and l.next_evaluation_at is not null
      and a.status = 'ACTIVE' and c.status = 'OFFLOAD_READY'
      and c.sensitivity_class = 'PRIVATE'
      and exists (select 1 from public.consents co where co.account_id = a.id
                  and co.consent_type = 'P1_CORE' and co.status = 'ACCEPTED'
                  and co.adult_declared
                  and co.id = (select last.id from public.consents last
                               where last.account_id = a.id and last.consent_type = 'P1_CORE'
                               order by last.occurred_at desc, last.id desc limit 1))
    for update of l;
  if not found then raise exception 'loop not eligible' using errcode = '42501'; end if;
  insert into private.p1_cohort_loops(loop_id, account_id, eligible_at, evidence_ref, verified_by)
    values (v_loop.id, v_loop.account_id, v_loop.offload_ready_at, p_evidence_ref, p_verified_by)
    on conflict (loop_id) do nothing;
end;
$$;

create or replace function private.p1_loop_report(p_as_of timestamptz default now())
returns table(
  loop_id uuid, account_id uuid, eligible_at timestamptz, current_revision integer,
  activated_at timestamptz, activation_valid boolean, matured boolean,
  valid_soc boolean, legitimate_retire boolean, matured_success boolean,
  ownership_result text, ai_cost_usd numeric, ai_only_completion boolean,
  stale_pending_delivery boolean
)
language sql security definer set search_path = ''
as $$
  with facts as (
    select cohort.loop_id, cohort.account_id, cohort.eligible_at,
      l.revision, l.activated_at, l.effective_state,
      exists (
        select 1 from public.loop_events e where e.loop_id = l.id
          and e.basis_revision = l.revision and e.event_type = 'OFFLOAD_RECEIPT_ACKED'
          and e.occurred_at >= cohort.eligible_at
          and e.occurred_at <= cohort.eligible_at + interval '7 days'
          and e.occurred_at <= p_as_of
      ) and l.activated_at is not null as activation_valid,
      exists (
        select 1 from public.loop_events e where e.loop_id = l.id
          and e.basis_revision = l.revision and e.event_type = 'SOC_RECORDED'
          and e.occurred_at <= p_as_of
      ) as soc_event,
      exists (
        select 1 from public.loop_events e where e.loop_id = l.id
          and e.basis_revision = l.revision and e.event_type = 'USER_MARKED_DONE'
          and e.actor_type = 'USER' and e.occurred_at <= p_as_of
      ) as user_done,
      exists (
        select 1 from public.loop_events e where e.loop_id = l.id
          and e.basis_revision = l.revision and e.event_type = 'CONTEXT_END_REQUESTED'
          and e.actor_type = 'USER' and e.payload->>'reason_code' = 'NO_LONGER_REQUIRED'
          and e.occurred_at <= p_as_of
      ) as user_retired,
      (select e.payload->>'result' from public.loop_events e
        where e.loop_id = l.id and e.basis_revision = l.revision
          and e.event_type = 'OWNERSHIP_MEASURED' and e.occurred_at <= p_as_of
        order by e.occurred_at desc limit 1) as ownership_result,
      coalesce((select sum((t.properties->>'cost_usd')::numeric)
                from telemetry.product_events t
                where t.loop_id = l.id and t.event_name = 'ai_call_recorded'
                  and t.occurred_at <= p_as_of), 0) as ai_cost_usd,
      exists (
        select 1 from public.deliveries d where d.loop_id = l.id
          and d.status = 'PENDING'
          and (d.basis_revision <> l.revision or l.status <> 'ACTIVE')
      ) as stale_pending_delivery
    from private.p1_cohort_loops cohort
    join public.open_loops l on l.id = cohort.loop_id
    where cohort.eligible_at <= p_as_of
  )
  select f.loop_id, f.account_id, f.eligible_at, f.revision, f.activated_at,
    f.activation_valid,
    f.activated_at is not null and f.activated_at <= p_as_of - interval '7 days',
    f.soc_event and f.user_done and f.effective_state = 'SATISFIED',
    f.user_retired and f.effective_state = 'NO_LONGER_REQUIRED',
    f.activated_at is not null and f.activated_at <= p_as_of - interval '7 days'
      and ((f.soc_event and f.user_done and f.effective_state = 'SATISFIED')
        or (f.user_retired and f.effective_state = 'NO_LONGER_REQUIRED')),
    f.ownership_result, f.ai_cost_usd, f.soc_event and not f.user_done,
    f.stale_pending_delivery
  from facts f;
$$;

revoke all on function private.tag_p1_eligible_loop(uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.p1_loop_report(timestamptz) from public, anon, authenticated;
grant execute on function private.tag_p1_eligible_loop(uuid, uuid, text) to service_role;
grant execute on function private.p1_loop_report(timestamptz) to service_role;
