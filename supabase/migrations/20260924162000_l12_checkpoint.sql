create table private.p1_exclusions (
  loop_id uuid primary key references public.open_loops(id) on delete cascade,
  reason_code text not null check (reason_code in ('SYNTHETIC', 'DUPLICATE', 'TECHNICAL', 'INELIGIBLE')),
  evidence_ref uuid not null,
  reviewed_by text not null check (char_length(reviewed_by) between 1 and 80),
  recorded_at timestamptz not null default now()
);
revoke all on private.p1_exclusions from public, anon, authenticated;

create table private.p1_incident_audits (
  id uuid primary key default extensions.gen_random_uuid(),
  evidence_ref uuid not null,
  reviewed_by text not null check (char_length(reviewed_by) between 1 and 80),
  reviewed_at timestamptz not null default now(),
  false_ack_count integer not null default 0 check (false_ack_count >= 0),
  stale_delivery_count integer not null default 0 check (stale_delivery_count >= 0),
  ai_only_completion_count integer not null default 0 check (ai_only_completion_count >= 0),
  cross_user_violation_count integer not null default 0 check (cross_user_violation_count >= 0),
  critical_trust_incident_count integer not null default 0 check (critical_trust_incident_count >= 0),
  focused_iterations integer not null default 0 check (focused_iterations >= 0),
  parallel_persisted boolean not null default false
);
revoke all on private.p1_incident_audits from public, anon, authenticated;

create or replace function private.p1_checkpoint(p_as_of timestamptz default now())
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_totals record;
  v_audit private.p1_incident_audits%rowtype;
  v_unclassified bigint;
  v_overlap bigint;
  v_deleted bigint;
  v_activation numeric;
  v_stale bigint;
  v_ai_only bigint;
  v_status text := 'HOLD';
  v_bottleneck text;
begin
  select count(*) as eligible, count(distinct account_id) as participants,
    count(*) filter (where activation_valid) as activated,
    count(*) filter (where matured) as matured,
    count(*) filter (where valid_soc) as valid_socs,
    count(distinct account_id) filter (where valid_soc) as soc_participants,
    count(*) filter (where matured and valid_soc and ownership_result = 'OWNED') as owned_matured,
    count(distinct account_id) filter (where matured and valid_soc and ownership_result = 'OWNED') as owned_participants,
    count(*) filter (where stale_pending_delivery) as stale_detected,
    count(*) filter (where ai_only_completion) as ai_only_detected,
    coalesce(sum(ai_cost_usd), 0) as ai_cost,
    coalesce(bool_and(eligible_at <= p_as_of - interval '7 days'
      and (activated_at is null or activated_at <= p_as_of - interval '7 days')), false) as windows_complete
    into v_totals from private.p1_loop_report(p_as_of);

  select count(*) into v_unclassified from public.open_loops l
    where l.offload_ready_at is not null
      and not exists (select 1 from private.p1_cohort_loops c where c.loop_id = l.id)
      and not exists (select 1 from private.p1_exclusions e where e.loop_id = l.id);
  select count(*) into v_overlap from private.p1_cohort_loops c
    join private.p1_exclusions e on e.loop_id = c.loop_id;
  select eligible_loops into v_deleted from telemetry.deleted_account_totals where singleton;
  select * into v_audit from private.p1_incident_audits
    where reviewed_at <= p_as_of order by reviewed_at desc, id desc limit 1;

  v_activation := v_totals.activated::numeric / nullif(v_totals.eligible, 0);
  v_stale := greatest(coalesce(v_audit.stale_delivery_count, 0), v_totals.stale_detected);
  v_ai_only := greatest(coalesce(v_audit.ai_only_completion_count, 0), v_totals.ai_only_detected);

  if v_audit.id is null then v_bottleneck := 'AUDIT_MISSING';
  elsif v_unclassified > 0 or v_overlap > 0 then v_bottleneck := 'ELIGIBILITY_REVIEW';
  elsif v_deleted > 0 then v_bottleneck := 'DELETION_RECONCILIATION';
  elsif v_totals.eligible < 10 or v_totals.participants < 5 or v_totals.matured < 5
      or not v_totals.windows_complete then v_bottleneck := 'OBSERVATION';
  elsif v_audit.critical_trust_incident_count > 0 or v_audit.false_ack_count > 0
      or v_stale > 0 or v_ai_only > 0 or v_audit.cross_user_violation_count > 0 then
    v_bottleneck := 'TRUST';
  elsif v_activation < 0.6 then v_bottleneck := 'ACTIVATION';
  elsif v_totals.soc_participants < 3 then v_bottleneck := 'SOC';
  elsif v_totals.owned_matured < 3 or v_totals.owned_participants < 2 then
    v_bottleneck := 'OWNERSHIP';
  else v_bottleneck := 'NONE';
  end if;

  if v_bottleneck = 'NONE' then
    v_status := 'PASS';
  elsif v_bottleneck in ('ACTIVATION', 'OWNERSHIP') and v_audit.focused_iterations >= 2
    and (v_activation < 0.35 or v_audit.parallel_persisted) then
    v_status := 'RECONSIDER';
  end if;

  return jsonb_build_object(
    'as_of', p_as_of,
    'status', v_status,
    'primary_bottleneck', v_bottleneck,
    'eligible_loops', v_totals.eligible,
    'participants', v_totals.participants,
    'matured_contexts', v_totals.matured,
    'activated_loops', v_totals.activated,
    'activation_rate', v_activation,
    'valid_socs', v_totals.valid_socs,
    'valid_soc_participants', v_totals.soc_participants,
    'owned_matured_contexts', v_totals.owned_matured,
    'owned_participants', v_totals.owned_participants,
    'ai_cost_usd', v_totals.ai_cost,
    'cost_per_valid_soc', v_totals.ai_cost / nullif(v_totals.valid_socs, 0),
    'false_ack_count', v_audit.false_ack_count,
    'stale_delivery_count', v_stale,
    'ai_only_completion_count', v_ai_only,
    'cross_user_violation_count', v_audit.cross_user_violation_count,
    'critical_trust_incident_count', v_audit.critical_trust_incident_count,
    'unclassified_candidates', v_unclassified,
    'overlapping_classifications', v_overlap,
    'deleted_evidence_pending', v_deleted,
    'windows_complete', v_totals.windows_complete,
    'audit_evidence_ref', v_audit.evidence_ref
  );
end;
$$;

revoke all on function private.p1_checkpoint(timestamptz) from public, anon, authenticated;
grant execute on function private.p1_checkpoint(timestamptz) to service_role;
