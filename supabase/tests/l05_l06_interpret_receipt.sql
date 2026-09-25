begin;

insert into public.accounts (id, auth_user_id, timezone)
values ('71111111-1111-4111-8111-111111111111', '71111111-1111-4111-8111-111111111111', 'Asia/Tokyo');
insert into public.consents (account_id, consent_type, version, status, adult_declared)
values ('71111111-1111-4111-8111-111111111111', 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);

select public.command_capture_text(
  '71111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy paper', 'PRIVATE',
  '71111111-1111-4111-8111-222222222222'
);

do $$
declare
  v_capture uuid;
  v_loop uuid;
  v_revision integer;
begin
  select id into v_capture from public.captures where account_id = '71111111-1111-4111-8111-111111111111';
  if (select count(*) from public.command_interpretation_source('71111111-1111-4111-8111-111111111111', v_capture)) <> 1 then
    raise exception 'eligible capture was not available to the server';
  end if;

  v_loop := public.command_record_interpretation(
    '71111111-1111-4111-8111-111111111111', v_capture,
    'Buy paper', 'Paper is bought', null, '2026-10-01T09:00:00Z', null,
    'gpt-5.6-luna', 20, 15, 0.000022
  );
  if (select status from public.captures where id = v_capture) <> 'OFFLOAD_READY' then
    raise exception 'capture did not become OFFLOAD_READY';
  end if;
  if exists (select 1 from public.loop_events where loop_id = v_loop and event_type in ('SOC_RECORDED', 'USER_MARKED_DONE')) then
    raise exception 'AI created completion evidence';
  end if;
  if (select count(*) from telemetry.product_events where loop_id = v_loop and event_name = 'ai_call_recorded') <> 1 then
    raise exception 'AI call cost was not recorded';
  end if;

  if public.command_ack_offload_receipt('71111111-1111-4111-8111-111111111111', v_loop, 1) <> 'ACKED' then
    raise exception 'receipt acknowledgement failed';
  end if;
  if exists (select 1 from private.capture_raws where capture_id = v_capture) then
    raise exception 'acknowledged Raw was not deleted';
  end if;
  perform public.command_ack_offload_receipt('71111111-1111-4111-8111-111111111111', v_loop, 1);
  if (select count(*) from public.loop_events where loop_id = v_loop and event_type = 'OFFLOAD_RECEIPT_ACKED') <> 1 then
    raise exception 'duplicate receipt acknowledgement was created';
  end if;

  v_revision := public.command_correct_loop(
    '71111111-1111-4111-8111-111111111111', v_loop,
    'Recycled paper is bought', null, now() + interval '2 days'
  );
  if v_revision <> 2 or (select activated_at from public.open_loops where id = v_loop) is not null then
    raise exception 'correction did not invalidate activation';
  end if;
  if public.command_ack_offload_receipt('71111111-1111-4111-8111-111111111111', v_loop, 1) <> 'STALE' then
    raise exception 'stale receipt was accepted';
  end if;
  if (select count(*) from public.loop_events where loop_id = v_loop and event_type = 'USER_CORRECTION') <> 1 or
     (select count(*) from public.loop_events where loop_id = v_loop and event_type = 'OFFLOAD_RECEIPT_ACKED') <> 1 then
    raise exception 'append-only history was overwritten';
  end if;
end;
$$;

rollback;
