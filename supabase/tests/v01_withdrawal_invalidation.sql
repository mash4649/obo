begin;

insert into public.accounts(id, auth_user_id, timezone)
values ('b1111111-1111-4111-8111-111111111111', 'b1111111-1111-4111-8111-111111111111', 'Asia/Tokyo');
insert into public.consents(account_id, consent_type, version, status, adult_declared)
values ('b1111111-1111-4111-8111-111111111111', 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);

do $$
declare
  v_capture uuid;
  v_loop uuid;
  v_delivery uuid;
  v_claim record;
  v_proof uuid;
  v_old_token text := 'ExpoPushToken[synthetic_old_1234567890]';
  v_new_token text := 'ExpoPushToken[synthetic_new_1234567890]';
begin
  v_capture := public.command_capture_text(
    'b1111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy paper', 'PRIVATE',
    'b1111111-1111-4111-8111-222222222222'
  );
  v_loop := public.command_record_interpretation(
    'b1111111-1111-4111-8111-111111111111', v_capture,
    'Buy paper', 'Paper is bought', null, now() - interval '1 minute', null,
    'gpt-5.6-luna', 20, 15, 0.000022
  );
  perform public.command_ack_offload_receipt('b1111111-1111-4111-8111-111111111111', v_loop, 1);
  update public.open_loops set next_evaluation_at = now() - interval '1 minute' where id = v_loop;
  perform 1 from private.evaluate_due_loops();
  select id into v_delivery from public.deliveries where loop_id = v_loop;
  if v_delivery is null then raise exception 'In-app delivery missing'; end if;

  perform public.command_register_push(
    'b1111111-1111-4111-8111-111111111111',
    'b1111111-1111-4111-8111-333333333333', v_old_token
  );
  select * into v_claim from public.command_claim_push();
  perform public.command_register_push(
    'b1111111-1111-4111-8111-111111111111',
    'b1111111-1111-4111-8111-333333333333', v_new_token
  );
  if public.command_push_still_allowed(v_delivery, v_claim.installation_id, v_old_token) or
     not public.command_push_still_allowed(v_delivery, v_claim.installation_id, v_new_token) then
    raise exception 'old token survived token rotation';
  end if;

  insert into private.auth_challenges(
    account_id, auth_user_id, session_id, action_kind, expires_at
  ) values (
    'b1111111-1111-4111-8111-111111111111',
    'b1111111-1111-4111-8111-111111111111', 'fixture-session',
    'WITHDRAW_CONSENT', now() + interval '10 minutes'
  );
  v_proof := public.command_verify_recent_auth(
    'b1111111-1111-4111-8111-111111111111', 'fixture-session', 'WITHDRAW_CONSENT'
  );
  perform public.command_withdraw_p1_consent(
    'b1111111-1111-4111-8111-111111111111', 'fixture-session', v_proof,
    'b1111111-1111-4111-8111-444444444444'
  );
  if (select status from public.accounts where id = 'b1111111-1111-4111-8111-111111111111') <> 'DELETION_PENDING' or
     (select status from public.open_loops where id = v_loop) <> 'CLOSED' or
     (select status from public.deliveries where id = v_delivery) <> 'CANCELLED' or
     (select status from private.device_installations where id = v_claim.installation_id) <> 'INVALID' or
     (select external_ai_allowed from public.captures where id = v_capture) or
     public.command_push_still_allowed(v_delivery, v_claim.installation_id, v_new_token) or
     exists (select 1 from public.command_interpretation_source('b1111111-1111-4111-8111-111111111111', v_capture)) or
     exists (select 1 from private.evaluate_due_loops()) or
     (select count(*) from public.command_claim_push()) <> 0 then
    raise exception 'withdrawal left processing or delivery active';
  end if;
  if (select properties::text from telemetry.product_events where loop_id = v_loop
      and event_name = 'ai_call_recorded') ~ 'buy paper|ExpoPushToken' then
    raise exception 'telemetry contains Raw or token';
  end if;
  begin
    perform public.command_capture_text(
      'b1111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy more paper', 'PRIVATE',
      'b1111111-1111-4111-8111-555555555555'
    );
    raise exception 'capture succeeded after withdrawal';
  exception when insufficient_privilege then null;
  end;
end;
$$;

rollback;
