create or replace function public.command_begin_raw_deletion(
  p_auth_user_id uuid, p_capture_id uuid, p_session_id text, p_proof_id uuid
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_capture public.captures%rowtype;
  v_proof_id uuid;
begin
  select c.* into v_capture from public.captures c
    join public.accounts a on a.id = c.account_id
    where c.id = p_capture_id and a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
    for update of c;
  if not found then raise exception 'capture unavailable' using errcode = '42501'; end if;
  if v_capture.status = 'DELETED' or not exists (
    select 1 from private.capture_raws where capture_id = p_capture_id
  ) then return 'DELETED'; end if;
  if v_capture.status = 'DELETION_PENDING' then return 'DELETION_PENDING'; end if;

  select id into v_proof_id from private.recent_auth_proofs
    where id = p_proof_id and account_id = v_capture.account_id
      and auth_user_id = p_auth_user_id and session_id = p_session_id
      and action_kind = 'DELETE_RAW_CAPTURE' and used_at is null and expires_at > now()
    for update;
  if not found then raise exception 'recent auth proof is unavailable' using errcode = '42501'; end if;
  update private.recent_auth_proofs set used_at = now() where id = v_proof_id;

  update public.captures set
    status = 'DELETION_PENDING', external_ai_allowed = false, updated_at = now()
    where id = p_capture_id;
  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (v_capture.account_id, p_auth_user_id::text, 'RAW_DELETION_REQUESTED', 'capture', p_capture_id);
  return 'DELETION_PENDING';
end;
$$;

-- An offload receipt remains actionable after the owner deletes only Raw.
create or replace function public.command_ack_offload_receipt(
  p_auth_user_id uuid, p_loop_id uuid, p_basis_revision integer
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_loop public.open_loops%rowtype;
begin
  select l.* into v_loop from public.open_loops l
    join public.accounts a on a.id = l.account_id
    join public.captures c on c.id = l.capture_id
    where l.id = p_loop_id and a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
      and l.status = 'ACTIVE' and c.status in ('OFFLOAD_READY', 'DELETED')
      and (select co.status from public.consents co where co.account_id = a.id and co.consent_type = 'P1_CORE'
           order by co.occurred_at desc limit 1) = 'ACCEPTED'
    for update of l;
  if not found or v_loop.revision <> p_basis_revision or v_loop.offload_ready_at is null
     or v_loop.next_evaluation_at is null or v_loop.confirmation_question is not null then
    return 'STALE';
  end if;

  insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
  values (p_loop_id, v_loop.account_id, 'OFFLOAD_RECEIPT_ACKED', 'USER', p_basis_revision)
  on conflict do nothing;
  if v_loop.activated_at is null then
    update public.open_loops set activated_at = now(),
      effective_state = case when effective_state = 'UNKNOWN' then 'UNSATISFIED' else effective_state end,
      updated_at = now() where id = p_loop_id;
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values (p_loop_id, v_loop.account_id, 'TRACKING_OFFLOAD_ACTIVATED', 'SYSTEM', p_basis_revision);
    insert into telemetry.product_events (account_id, loop_id, event_name)
    values (v_loop.account_id, p_loop_id, 'tracking_offload_activated');
  end if;
  return 'ACKED';
end;
$$;

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
      and a.status = 'ACTIVE' and c.status in ('OFFLOAD_READY', 'DELETED')
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

create or replace function public.command_finish_raw_deletion(p_capture_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_capture public.captures%rowtype;
begin
  select * into v_capture from public.captures where id = p_capture_id for update;
  if not found or not exists (
    select 1 from private.audit_events
      where target_type = 'capture' and target_id = p_capture_id and action = 'RAW_DELETION_REQUESTED'
  ) then raise exception 'capture not pending' using errcode = '42501'; end if;
  delete from private.capture_raws where capture_id = p_capture_id;
  update public.captures set status = 'DELETED', updated_at = now() where id = p_capture_id;
  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (v_capture.account_id, 'SYSTEM', 'RAW_DELETED', 'capture', p_capture_id);
  return 'DELETED';
end;
$$;
