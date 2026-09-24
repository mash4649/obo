begin;

insert into public.accounts(id, auth_user_id, timezone)
values ('91111111-1111-4111-8111-111111111111', '91111111-1111-4111-8111-111111111111', 'Asia/Tokyo');
insert into public.consents(account_id, consent_type, version, status, adult_declared)
values ('91111111-1111-4111-8111-111111111111', 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);
select public.command_capture_text(
  '91111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy paper', 'PRIVATE',
  '91111111-1111-4111-8111-222222222222'
);

do $$
declare
  v_capture uuid;
  v_loop uuid;
  v_delivery uuid;
  v_second_loop uuid;
  v_second_delivery uuid;
  v_expired integer;
  v_claim record;
  v_receipt record;
  v_token text := 'ExpoPushToken[synthetic_token_1234567890]';
begin
  select id into v_capture from public.captures
    where account_id = '91111111-1111-4111-8111-111111111111';
  v_loop := public.command_record_interpretation(
    '91111111-1111-4111-8111-111111111111', v_capture,
    'Buy paper', 'Paper is bought', null, now() - interval '1 minute', null,
    'gpt-5.6-luna', 20, 15, 0.000022
  );
  perform public.command_ack_offload_receipt('91111111-1111-4111-8111-111111111111', v_loop, 1);
  update public.open_loops set next_evaluation_at = now() - interval '1 minute' where id = v_loop;
  perform 1 from private.evaluate_due_loops(now());
  select id into v_delivery from public.deliveries where loop_id = v_loop;
  if v_delivery is null or (select count(*) from public.deliveries where loop_id = v_loop) <> 1 then
    raise exception 'in-app delivery missing';
  end if;
  if (select count(*) from public.command_claim_push()) <> 0 then
    raise exception 'push claimed without opt-in';
  end if;

  perform public.command_register_push(
    '91111111-1111-4111-8111-111111111111',
    '91111111-1111-4111-8111-333333333333', v_token
  );
  select * into v_claim from public.command_claim_push();
  if v_claim.delivery_id <> v_delivery or v_claim.expo_token <> v_token or
     not public.command_push_still_allowed(v_delivery, v_claim.installation_id, v_token) then
    raise exception 'qualified push was not claimed';
  end if;
  if (select count(*) from public.command_claim_push()) <> 0 then
    raise exception 'duplicate push claim';
  end if;
  perform public.command_revoke_push(
    '91111111-1111-4111-8111-111111111111',
    '91111111-1111-4111-8111-333333333333'
  );
  if public.command_push_still_allowed(v_delivery, v_claim.installation_id, v_token) then
    raise exception 'opt-out left push eligible';
  end if;
  perform public.command_record_push_ticket(v_delivery, null);
  if (select state from private.push_attempts where delivery_id = v_delivery) <> 'RECEIPT_ERROR' or
     (select status from public.deliveries where id = v_delivery) <> 'PENDING' then
    raise exception 'provider failure lost in-app fallback';
  end if;

  perform public.command_register_push(
    '91111111-1111-4111-8111-111111111111',
    '91111111-1111-4111-8111-333333333333', v_token
  );
  insert into public.open_loops(
    account_id, capture_id, title, expected_state_text, effective_state, offload_ready_at, activated_at
  ) values (
    '91111111-1111-4111-8111-111111111111', v_capture, 'Second fixture', 'Paper is bought',
    'UNSATISFIED', now(), now()
  ) returning id into v_second_loop;
  insert into public.deliveries(
    loop_id, account_id, basis_revision, reason_code, scheduled_evaluation_at
  ) values (
    v_second_loop, '91111111-1111-4111-8111-111111111111', 1,
    'EXPECTED_STATE_UNSATISFIED', now()
  ) returning id into v_second_delivery;
  select * into v_claim from public.command_claim_push();
  if v_claim.delivery_id <> v_second_delivery then raise exception 'second claim failed'; end if;
  perform public.command_record_push_ticket(v_second_delivery, 'synthetic-ticket', now() - interval '16 minutes');
  select * into v_receipt from public.command_claim_push_receipt();
  if v_receipt.delivery_id <> v_second_delivery or v_receipt.ticket_id <> 'synthetic-ticket' or
     (select count(*) from public.command_claim_push_receipt()) <> 0 then
    raise exception 'receipt was not reconciled exactly once';
  end if;
  perform public.command_finish_push_receipt(v_second_delivery, false, true);
  if (select state from private.push_attempts where delivery_id = v_second_delivery) <> 'RECEIPT_ERROR' or
     (select status from private.device_installations where id = v_claim.installation_id) <> 'INVALID' or
     (select status from public.deliveries where id = v_second_delivery) <> 'PENDING' then
    raise exception 'DeviceNotRegistered did not invalidate while preserving In-app';
  end if;

  update private.push_attempts set state = 'CLAIMED', claimed_at = now() - interval '16 minutes'
    where delivery_id = v_second_delivery;
  v_expired := public.command_expire_push_claims();
  if v_expired <> 1 or
     (select state from private.push_attempts where delivery_id = v_second_delivery) <> 'RECEIPT_ERROR' then
    raise exception 'interrupted submission did not fail closed';
  end if;

  perform public.command_register_push(
    '91111111-1111-4111-8111-111111111111',
    '91111111-1111-4111-8111-333333333333', v_token
  );
  update public.open_loops set revision = 2 where id = v_loop;
  if (select status from public.deliveries where id = v_delivery) <> 'CANCELLED' or
     (select count(*) from public.command_claim_push()) <> 0 then
    raise exception 'stale delivery was not cancelled';
  end if;
  if public.command_push_still_allowed(v_delivery, v_claim.installation_id, v_token) then
    raise exception 'stale send was allowed';
  end if;
end;
$$;

rollback;
