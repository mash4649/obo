begin;

insert into public.accounts(id, auth_user_id, timezone)
values ('a1111111-1111-4111-8111-111111111111', 'a1111111-1111-4111-8111-111111111111', 'Asia/Tokyo');
insert into public.consents(account_id, consent_type, version, status, adult_declared)
values ('a1111111-1111-4111-8111-111111111111', 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);

do $$
declare
  v_capture uuid;
  v_loop uuid;
  v_open_loop uuid;
  v_report record;
begin
  v_capture := public.command_capture_text(
    'a1111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy paper', 'PRIVATE',
    'a1111111-1111-4111-8111-222222222222'
  );
  v_loop := public.command_record_interpretation(
    'a1111111-1111-4111-8111-111111111111', v_capture,
    'Buy paper', 'Paper is bought', null, now() + interval '1 day', null,
    'gpt-5.6-luna', 20, 15, 0.000022
  );
  perform public.command_ack_offload_receipt('a1111111-1111-4111-8111-111111111111', v_loop, 1);
  perform public.command_loop_action('a1111111-1111-4111-8111-111111111111', v_loop, 'MARK_DONE');
  perform public.command_record_ownership('a1111111-1111-4111-8111-111111111111', v_loop, 'OWNED');
  perform private.tag_p1_eligible_loop(v_loop, 'a1111111-1111-4111-8111-333333333333', 'fixture');
  select * into v_report from private.p1_loop_report(now() + interval '8 days') where loop_id = v_loop;
  if not v_report.activation_valid or not v_report.matured or not v_report.valid_soc or
     not v_report.matured_success or v_report.ownership_result <> 'OWNED' or
     v_report.ai_only_completion or v_report.stale_pending_delivery then
    raise exception 'closed genuine loop was not reconstructed';
  end if;
  if (select matured from private.p1_loop_report(now()) where loop_id = v_loop) then
    raise exception 'immature context counted as matured';
  end if;

  v_capture := public.command_capture_text(
    'a1111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy envelopes', 'PRIVATE',
    'a1111111-1111-4111-8111-444444444444'
  );
  v_open_loop := public.command_record_interpretation(
    'a1111111-1111-4111-8111-111111111111', v_capture,
    'Buy envelopes', 'Envelopes are bought', null, now() + interval '1 day', null,
    'gpt-5.6-luna', 20, 15, 0.000022
  );
  perform private.tag_p1_eligible_loop(v_open_loop, 'a1111111-1111-4111-8111-555555555555', 'fixture');
  if (select count(*) from private.p1_loop_report()) <> 2 or
     (select activation_valid from private.p1_loop_report() where loop_id = v_open_loop) then
    raise exception 'unacknowledged eligible loop fell out of denominator';
  end if;
end;
$$;

rollback;
