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
    join public.captures c on c.id = l.capture_id
    where l.id = p_loop_id and l.offload_ready_at is not null
      and c.sensitivity_class = 'PRIVATE'
      and exists (select 1 from public.loop_events e where e.loop_id = l.id
                  and e.event_type = 'OFFLOAD_READY' and e.occurred_at <= l.offload_ready_at)
      and (select co.status from public.consents co where co.account_id = l.account_id
           and co.consent_type = 'P1_CORE' and co.occurred_at <= l.offload_ready_at
           order by co.occurred_at desc, co.id desc limit 1) = 'ACCEPTED'
    for update of l;
  if not found then raise exception 'loop not eligible' using errcode = '42501'; end if;
  insert into private.p1_cohort_loops(loop_id, account_id, eligible_at, evidence_ref, verified_by)
    values (v_loop.id, v_loop.account_id, v_loop.offload_ready_at, p_evidence_ref, p_verified_by)
    on conflict (loop_id) do nothing;
end;
$$;
