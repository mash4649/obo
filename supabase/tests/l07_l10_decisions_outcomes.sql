begin;

insert into public.accounts (id, auth_user_id, timezone)
values ('81111111-1111-4111-8111-111111111111', '81111111-1111-4111-8111-111111111111', 'Asia/Tokyo');
insert into public.consents (account_id, consent_type, version, status, adult_declared)
values ('81111111-1111-4111-8111-111111111111', 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);

select public.command_capture_text(
  '81111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy paper', 'PRIVATE',
  '81111111-1111-4111-8111-222222222222'
);

do $$
declare
  v_capture uuid;
  v_loop uuid;
  v_decision text;
begin
  select id into v_capture from public.captures where account_id = '81111111-1111-4111-8111-111111111111';
  v_loop := public.command_record_interpretation(
    '81111111-1111-4111-8111-111111111111', v_capture,
    'Buy paper', 'Paper is bought', null, now() - interval '1 minute', null,
    'gpt-5.6-luna', 20, 15, 0.000022
  );

  select decision into v_decision from private.evaluate_due_loops(now()) where loop_id = v_loop;
  if v_decision is not null or exists (select 1 from public.deliveries where loop_id = v_loop) then
    raise exception 'unacknowledged loop was evaluated';
  end if;

  perform public.command_ack_offload_receipt('81111111-1111-4111-8111-111111111111', v_loop, 1);
  update public.open_loops set next_evaluation_at = now() - interval '1 minute' where id = v_loop;
  select decision into v_decision from private.evaluate_due_loops(now()) where loop_id = v_loop;
  if v_decision <> 'ACT' or (select count(*) from public.deliveries where loop_id = v_loop and status = 'PENDING') <> 1 then
    raise exception 'ACT did not create exactly one In-app delivery';
  end if;
  if exists (select 1 from public.deliveries where loop_id = v_loop and channel = 'PUSH') then
    raise exception 'Push was created without qualification';
  end if;

  if public.command_loop_action('81111111-1111-4111-8111-111111111111', v_loop, 'MARK_DONE') <> 'DONE' then
    raise exception 'user completion failed';
  end if;
  if (select count(*) from public.deliveries where loop_id = v_loop and status = 'CANCELLED') <> 1 then
    raise exception 'terminal loop left a pending delivery';
  end if;
  if (select count(*) from public.loop_events where loop_id = v_loop and event_type = 'SOC_RECORDED') <> 1 then
    raise exception 'valid SOC was not recorded';
  end if;
  if public.command_record_ownership('81111111-1111-4111-8111-111111111111', v_loop, 'OWNED') <> 'RECORDED' then
    raise exception 'ownership result was not recorded';
  end if;
  if (select eligible_loops from private.p1_metrics()) <> 1 or
     (select activated_loops from private.p1_metrics()) <> 1 or
     (select valid_socs from private.p1_metrics()) <> 1 or
     (select owned_socs from private.p1_metrics()) <> 1 then
    raise exception 'semantic metrics are incorrect';
  end if;
  v_decision := public.command_loop_action('81111111-1111-4111-8111-111111111111', v_loop, 'REOPEN_CONTEXT');
  if v_decision <> 'REOPENED' or
     (select revision from public.open_loops where id = v_loop) <> 2 then
    raise exception 'reopen did not preserve history in a new revision';
  end if;
  if (select activated_loops from private.p1_metrics()) <> 0 then
    raise exception 'old revision ACK counted as current activation';
  end if;
end;
$$;

do $$
declare
  v_capture uuid;
  v_silence uuid;
  v_defer uuid;
begin
  select id into v_capture from public.captures where account_id = '81111111-1111-4111-8111-111111111111';
  insert into public.open_loops (
    account_id, capture_id, title, expected_state_text, effective_state,
    next_evaluation_at, offload_ready_at, activated_at
  ) values (
    '81111111-1111-4111-8111-111111111111', v_capture, 'Satisfied fixture', 'Already done',
    'SATISFIED', now() - interval '1 minute', now(), now()
  ) returning id into v_silence;
  insert into public.open_loops (
    account_id, capture_id, title, expected_state_text, effective_state,
    next_evaluation_at, offload_ready_at, activated_at
  ) values (
    '81111111-1111-4111-8111-111111111111', v_capture, 'Unknown fixture', 'Still open',
    'UNKNOWN', now() - interval '1 minute', now(), now()
  ) returning id into v_defer;
  perform 1 from private.evaluate_due_loops(now());
  if not exists (select 1 from public.loop_events where loop_id = v_silence and event_type = 'DECISION_SILENCE') or
     not exists (select 1 from public.loop_events where loop_id = v_defer and event_type = 'DECISION_DEFER') or
     exists (select 1 from public.deliveries where loop_id in (v_silence, v_defer)) then
    raise exception 'SILENCE or DEFER created delivery';
  end if;
end;
$$;

do $$
declare
  v_capture uuid;
  v_loop uuid;
  v_processed integer;
begin
  select id into v_capture from public.captures where account_id = '81111111-1111-4111-8111-111111111111';
  for i in 1..26 loop
    insert into public.open_loops (
      account_id, capture_id, title, expected_state_text, effective_state,
      next_evaluation_at, offload_ready_at, activated_at
    ) values (
      '81111111-1111-4111-8111-111111111111', v_capture, 'Fixture', 'Fixture is done',
      'UNSATISFIED', now() - interval '1 minute', now(), now()
    ) returning id into v_loop;
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values (v_loop, '81111111-1111-4111-8111-111111111111', 'OFFLOAD_RECEIPT_ACKED', 'USER', 1);
  end loop;
  select count(*) into v_processed from private.evaluate_due_loops(now());
  if v_processed <> 25 or
     (select count(*) from public.deliveries where status = 'PENDING') <> 25 or
     (select count(*) from public.open_loops where next_evaluation_at <= now() and status = 'ACTIVE') <> 1 then
    raise exception 'bounded scheduler batch failed';
  end if;
end;
$$;

create sequence private.delivery_retry_fixture_seq;
create function private.fail_delivery_retry_fixture()
returns trigger language plpgsql as $$
begin
  perform nextval('private.delivery_retry_fixture_seq');
  raise exception 'fixture delivery failure';
end;
$$;
create trigger fail_delivery_retry_fixture before insert on public.deliveries
  for each row execute function private.fail_delivery_retry_fixture();

do $$
declare
  v_capture uuid;
  v_loop uuid;
  v_decision text;
begin
  select id into v_capture from public.captures where account_id = '81111111-1111-4111-8111-111111111111';
  insert into public.open_loops (
    account_id, capture_id, title, expected_state_text, effective_state,
    next_evaluation_at, offload_ready_at, activated_at
  ) values (
    '81111111-1111-4111-8111-111111111111', v_capture, 'Retry fixture', 'Still open',
    'UNSATISFIED', now() - interval '1 minute', now(), now()
  ) returning id into v_loop;
  insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
  values (v_loop, '81111111-1111-4111-8111-111111111111', 'OFFLOAD_RECEIPT_ACKED', 'USER', 1);
  update public.open_loops set next_evaluation_at = null where id <> v_loop;
  select decision into v_decision from private.evaluate_due_loops(now()) where loop_id = v_loop;
  if v_decision <> 'DEFER' or
     (select last_value from private.delivery_retry_fixture_seq) <> 2 or
     (select next_evaluation_at from public.open_loops where id = v_loop) < now() + interval '14 minutes' or
     exists (select 1 from public.deliveries where loop_id = v_loop) then
    raise exception 'retry exhaustion did not defer without delivery';
  end if;
end;
$$;

rollback;
