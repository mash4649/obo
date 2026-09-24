create schema if not exists telemetry;

create table telemetry.product_events (
  id uuid primary key default extensions.gen_random_uuid(),
  account_id uuid not null references public.accounts (id),
  loop_id uuid,
  event_name text not null,
  event_version integer not null default 1,
  occurred_at timestamptz not null default now(),
  properties jsonb not null default '{}'::jsonb,
  foreign key (loop_id, account_id) references public.open_loops (id, account_id)
);
alter table telemetry.product_events enable row level security;
revoke all on schema telemetry from public, anon, authenticated;
revoke all on telemetry.product_events from public, anon, authenticated;

create or replace function private.capture_telemetry()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into telemetry.product_events (account_id, event_name)
    values (new.account_id, 'capture_stored');
  elsif new.status = 'OFFLOAD_READY' and old.status <> 'OFFLOAD_READY' then
    insert into telemetry.product_events (account_id, loop_id, event_name)
    select new.account_id, l.id, 'offload_ready'
      from public.open_loops l where l.capture_id = new.id;
  end if;
  return new;
end;
$$;
create trigger capture_stored_telemetry after insert on public.captures
  for each row execute function private.capture_telemetry();
create trigger offload_ready_telemetry after update of status on public.captures
  for each row execute function private.capture_telemetry();

alter table public.open_loops add column confirmation_question text;

create unique index loop_events_receipt_ack_once
  on public.loop_events (loop_id, basis_revision)
  where event_type = 'OFFLOAD_RECEIPT_ACKED';

create or replace function public.command_interpretation_source(p_auth_user_id uuid, p_capture_id uuid)
returns table (scope public.capture_scope, raw_text text)
language plpgsql security definer set search_path = ''
as $$
begin
  return query
    select c.scope, r.raw_text
      from public.accounts a
      join public.captures c on c.account_id = a.id
      join private.capture_raws r on r.capture_id = c.id and r.deleted_at is null
      where a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
        and c.id = p_capture_id and c.status = 'STORED'
        and c.sensitivity_class = 'PRIVATE'
        and (select co.status from public.consents co
             where co.account_id = a.id and co.consent_type = 'P1_CORE'
             order by co.occurred_at desc limit 1) = 'ACCEPTED';
end;
$$;

create or replace function public.command_record_interpretation(
  p_auth_user_id uuid, p_capture_id uuid, p_title text, p_expected_state text,
  p_due_at timestamptz, p_next_evaluation_at timestamptz, p_question text,
  p_model text, p_input_tokens integer, p_output_tokens integer, p_cost_usd numeric
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_account_id uuid;
  v_loop_id uuid;
  v_revision integer;
begin
  if p_title is null or char_length(p_title) not between 1 and 100 or
     p_expected_state is null or char_length(p_expected_state) > 300 or
     (p_expected_state = '' and p_question is null) or
     (p_next_evaluation_at is null and p_question is null) or
     (p_question is not null and char_length(p_question) not between 1 and 200) or
     p_model is distinct from 'gpt-5.6-luna' or p_input_tokens is null or p_input_tokens not between 0 and 2500 or
     p_output_tokens is null or p_output_tokens not between 0 and 256 or
     p_cost_usd is null or p_cost_usd not between 0 and 0.002 then
    raise exception 'invalid interpretation' using errcode = '22023';
  end if;

  select a.id into v_account_id
    from public.accounts a
    join public.captures c on c.account_id = a.id
    where a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
      and c.id = p_capture_id and c.status = 'STORED' and c.sensitivity_class = 'PRIVATE'
      and exists (select 1 from private.capture_raws r where r.capture_id = c.id and r.deleted_at is null)
      and (select co.status from public.consents co where co.account_id = a.id and co.consent_type = 'P1_CORE'
           order by co.occurred_at desc limit 1) = 'ACCEPTED'
    for update of a, c;
  if not found then
    raise exception 'capture unavailable' using errcode = '42501';
  end if;

  insert into public.open_loops (
    account_id, capture_id, title, expected_state_text, due_at, next_evaluation_at,
    offload_ready_at, confirmation_question
  ) values (
    v_account_id, p_capture_id, p_title, p_expected_state, p_due_at, p_next_evaluation_at,
    case when p_question is null then now() else null end, p_question
  ) returning id, revision into v_loop_id, v_revision;

  update public.captures
    set status = case when p_question is null then 'OFFLOAD_READY'::public.capture_status else 'NEEDS_CONFIRMATION' end,
        external_ai_allowed = true, processing_attempt_count = processing_attempt_count + 1,
        updated_at = now()
    where id = p_capture_id;

  insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision, payload)
  values (v_loop_id, v_account_id, 'INTERPRETATION_CREATED', 'AI_DERIVED', v_revision,
    jsonb_build_object('expected_state', p_expected_state, 'due_at', p_due_at));
  if p_question is not null then
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision, payload)
    values (v_loop_id, v_account_id, 'CONFIRMATION_ASKED', 'SYSTEM', v_revision,
      jsonb_build_object('question', p_question));
  else
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values (v_loop_id, v_account_id, 'OFFLOAD_READY', 'SYSTEM', v_revision);
  end if;
  insert into telemetry.product_events (account_id, loop_id, event_name, properties)
  values (v_account_id, v_loop_id, 'ai_call_recorded',
    jsonb_build_object('model', p_model, 'input_tokens', p_input_tokens,
      'output_tokens', p_output_tokens, 'cost_usd', p_cost_usd));
  return v_loop_id;
end;
$$;

create or replace function public.command_correct_loop(
  p_auth_user_id uuid, p_loop_id uuid, p_expected_state text,
  p_due_at timestamptz, p_next_evaluation_at timestamptz
)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_loop public.open_loops%rowtype;
begin
  if p_expected_state is null or char_length(p_expected_state) not between 1 and 300 or
     p_next_evaluation_at is null or p_next_evaluation_at <= now() then
    raise exception 'invalid correction' using errcode = '22023';
  end if;
  select l.* into v_loop from public.open_loops l
    join public.accounts a on a.id = l.account_id
    where l.id = p_loop_id and a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
      and l.status = 'ACTIVE'
      and (select co.status from public.consents co where co.account_id = a.id and co.consent_type = 'P1_CORE'
           order by co.occurred_at desc limit 1) = 'ACCEPTED'
    for update of l;
  if not found then raise exception 'loop unavailable' using errcode = '42501'; end if;

  if v_loop.expected_state_text = p_expected_state and v_loop.due_at is not distinct from p_due_at
     and v_loop.next_evaluation_at is not distinct from p_next_evaluation_at
     and v_loop.confirmation_question is null then
    return v_loop.revision;
  end if;

  update public.open_loops set expected_state_text = p_expected_state, due_at = p_due_at,
    next_evaluation_at = p_next_evaluation_at, confirmation_question = null,
    offload_ready_at = coalesce(offload_ready_at, now()), revision = revision + 1,
    activated_at = null, effective_state = 'UNKNOWN', updated_at = now()
    where id = p_loop_id;
  update public.captures set status = 'OFFLOAD_READY', updated_at = now()
    where id = v_loop.capture_id and status = 'NEEDS_CONFIRMATION';
  insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision, payload)
  values (p_loop_id, v_loop.account_id, 'USER_CORRECTION', 'USER', v_loop.revision + 1,
    jsonb_build_object('expected_state', p_expected_state, 'due_at', p_due_at));
  insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
  values (p_loop_id, v_loop.account_id, 'OFFLOAD_READY', 'SYSTEM', v_loop.revision + 1);
  return v_loop.revision + 1;
end;
$$;

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
      and l.status = 'ACTIVE' and c.status = 'OFFLOAD_READY'
      and (select co.status from public.consents co where co.account_id = a.id and co.consent_type = 'P1_CORE'
           order by co.occurred_at desc limit 1) = 'ACCEPTED'
    for update of l;
  if not found or v_loop.revision <> p_basis_revision or v_loop.offload_ready_at is null
     or v_loop.next_evaluation_at is null then
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

revoke all on function public.command_interpretation_source(uuid, uuid) from public, anon, authenticated;
revoke all on function public.command_record_interpretation(uuid, uuid, text, text, timestamptz, timestamptz, text, text, integer, integer, numeric) from public, anon, authenticated;
revoke all on function public.command_correct_loop(uuid, uuid, text, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.command_ack_offload_receipt(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.command_interpretation_source(uuid, uuid) to service_role;
grant execute on function public.command_record_interpretation(uuid, uuid, text, text, timestamptz, timestamptz, text, text, integer, integer, numeric) to service_role;
grant execute on function public.command_correct_loop(uuid, uuid, text, timestamptz, timestamptz) to service_role;
grant execute on function public.command_ack_offload_receipt(uuid, uuid, integer) to service_role;
