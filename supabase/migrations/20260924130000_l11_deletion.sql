create or replace function private.stop_account_work()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.status <> 'ACTIVE' then
    update public.captures set external_ai_allowed = false, updated_at = now()
      where account_id = new.id and external_ai_allowed;
    update public.open_loops set status = 'CLOSED', next_evaluation_at = null, updated_at = now()
      where account_id = new.id and status <> 'CLOSED';
    update public.deliveries set status = 'CANCELLED'
      where account_id = new.id and status = 'PENDING';
  end if;
  return new;
end;
$$;
create trigger stop_account_work
  after update of status on public.accounts
  for each row when (old.status is distinct from new.status)
  execute function private.stop_account_work();

drop policy "captures: owner can read" on public.captures;
create policy "captures: active owner can read" on public.captures for select to authenticated
  using (account_id = (select id from public.accounts where auth_user_id = (select auth.uid()) and status = 'ACTIVE'));
drop policy "open loops: owner can read" on public.open_loops;
create policy "open loops: active owner can read" on public.open_loops for select to authenticated
  using (account_id = (select id from public.accounts where auth_user_id = (select auth.uid()) and status = 'ACTIVE'));
drop policy "loop events: owner can read" on public.loop_events;
create policy "loop events: active owner can read" on public.loop_events for select to authenticated
  using (account_id = (select id from public.accounts where auth_user_id = (select auth.uid()) and status = 'ACTIVE'));
drop policy "deliveries: owner can read" on public.deliveries;
create policy "deliveries: active owner can read" on public.deliveries for select to authenticated
  using (account_id = (select id from public.accounts where auth_user_id = (select auth.uid()) and status = 'ACTIVE'));

create or replace function private.delete_raw_after_receipt()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_capture_id uuid;
begin
  select capture_id into v_capture_id from public.open_loops where id = new.loop_id;
  delete from private.capture_raws where capture_id = v_capture_id;
  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (new.account_id, 'SYSTEM', 'RAW_DELETED_AFTER_ACK', 'capture', v_capture_id);
  return new;
end;
$$;
create trigger delete_raw_after_receipt
  after insert on public.loop_events
  for each row when (new.event_type = 'OFFLOAD_RECEIPT_ACKED')
  execute function private.delete_raw_after_receipt();

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
  if v_capture.status in ('DELETION_PENDING', 'DELETED') then return v_capture.status::text; end if;
  select id into v_proof_id from private.recent_auth_proofs
    where id = p_proof_id and account_id = v_capture.account_id
      and auth_user_id = p_auth_user_id and session_id = p_session_id
      and action_kind = 'DELETE_RAW_CAPTURE' and used_at is null and expires_at > now()
    for update;
  if not found then raise exception 'recent auth proof is unavailable' using errcode = '42501'; end if;
  update private.recent_auth_proofs set used_at = now() where id = v_proof_id;
  update public.captures set status = 'DELETION_PENDING', external_ai_allowed = false, updated_at = now()
    where id = p_capture_id;
  update public.open_loops set status = 'CLOSED', next_evaluation_at = null, updated_at = now()
    where capture_id = p_capture_id and status <> 'CLOSED';
  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (v_capture.account_id, p_auth_user_id::text, 'RAW_DELETION_REQUESTED', 'capture', p_capture_id);
  return 'DELETION_PENDING';
end;
$$;

create or replace function public.command_finish_raw_deletion(p_capture_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_account_id uuid;
begin
  select account_id into v_account_id from public.captures
    where id = p_capture_id and status = 'DELETION_PENDING' for update;
  if not found then raise exception 'capture not pending' using errcode = '42501'; end if;
  delete from private.capture_raws where capture_id = p_capture_id;
  update public.captures set status = 'DELETED', updated_at = now() where id = p_capture_id;
  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (v_account_id, 'SYSTEM', 'RAW_DELETED', 'capture', p_capture_id);
  return 'DELETED';
end;
$$;

create or replace function public.command_begin_account_deletion(
  p_auth_user_id uuid, p_session_id text, p_proof_id uuid
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_account_id uuid;
  v_proof_id uuid;
  v_version text;
begin
  select id into v_account_id from public.accounts
    where auth_user_id = p_auth_user_id and status = 'ACTIVE' for update;
  if not found then raise exception 'account unavailable' using errcode = '42501'; end if;
  select id into v_proof_id from private.recent_auth_proofs
    where id = p_proof_id and account_id = v_account_id
      and auth_user_id = p_auth_user_id and session_id = p_session_id
      and action_kind = 'DELETE_ACCOUNT' and used_at is null and expires_at > now()
    for update;
  if not found then raise exception 'recent auth proof is unavailable' using errcode = '42501'; end if;
  select version into v_version from public.consents
    where account_id = v_account_id and consent_type = 'P1_CORE'
    order by occurred_at desc limit 1;
  if v_version is null then raise exception 'consent unavailable' using errcode = '42501'; end if;
  update private.recent_auth_proofs set used_at = now() where id = v_proof_id;
  update public.accounts set status = 'DELETION_PENDING' where id = v_account_id;
  insert into public.consents (account_id, consent_type, version, status, adult_declared)
  values (v_account_id, 'P1_CORE', v_version, 'WITHDRAWN', true);
  update public.captures set status = 'DELETION_PENDING', external_ai_allowed = false,
    updated_at = now() where account_id = v_account_id and status <> 'DELETED';
  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (v_account_id, p_auth_user_id::text, 'ACCOUNT_DELETION_REQUESTED', 'account', v_account_id);
  return 'DELETION_PENDING';
end;
$$;

create or replace function public.command_finish_account_deletion(p_auth_user_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_account_id uuid;
  v_before record;
  v_after record;
begin
  select id into v_account_id from public.accounts
    where auth_user_id = p_auth_user_id and status = 'DELETION_PENDING' for update;
  if not found then raise exception 'account not pending' using errcode = '42501'; end if;
  perform 1 from telemetry.deleted_account_totals where singleton for update;
  select * into v_before from private.p1_metrics();
  delete from telemetry.product_events where account_id = v_account_id;
  delete from public.deliveries where account_id = v_account_id;
  delete from public.loop_events where account_id = v_account_id;
  delete from public.open_loops where account_id = v_account_id;
  delete from private.capture_raws where account_id = v_account_id;
  delete from private.capture_idempotency where auth_user_id = p_auth_user_id;
  delete from public.captures where account_id = v_account_id;
  delete from public.consents where account_id = v_account_id;
  delete from private.recent_auth_proofs where account_id = v_account_id;
  delete from private.auth_challenges where account_id = v_account_id;
  delete from private.command_idempotency where auth_user_id = p_auth_user_id;
  delete from private.audit_events where account_id = v_account_id;
  delete from public.accounts where id = v_account_id;
  select * into v_after from private.p1_metrics();
  update telemetry.deleted_account_totals set
    eligible_loops = eligible_loops + v_before.eligible_loops - v_after.eligible_loops,
    activated_loops = activated_loops + v_before.activated_loops - v_after.activated_loops,
    valid_socs = valid_socs + v_before.valid_socs - v_after.valid_socs,
    owned_socs = owned_socs + v_before.owned_socs - v_after.owned_socs,
    ai_cost_usd = ai_cost_usd + v_before.ai_cost_usd - v_after.ai_cost_usd
    where singleton;
  return 'DELETED';
end;
$$;

create or replace function private.expire_unacknowledged_raws(p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from private.capture_raws r using public.captures c
    where r.capture_id = c.id and r.created_at <= p_now - interval '7 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.command_begin_raw_deletion(uuid, uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.command_finish_raw_deletion(uuid) from public, anon, authenticated;
revoke all on function public.command_begin_account_deletion(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.command_finish_account_deletion(uuid) from public, anon, authenticated;
revoke all on function private.expire_unacknowledged_raws(timestamptz) from public, anon, authenticated;
grant execute on function public.command_begin_raw_deletion(uuid, uuid, text, uuid) to service_role;
grant execute on function public.command_finish_raw_deletion(uuid) to service_role;
grant execute on function public.command_begin_account_deletion(uuid, text, uuid) to service_role;
grant execute on function public.command_finish_account_deletion(uuid) to service_role;
grant execute on function private.expire_unacknowledged_raws(timestamptz) to service_role;
