begin;

insert into public.accounts (id, auth_user_id, timezone)
values ('91111111-1111-4111-8111-111111111111', '91111111-1111-4111-8111-111111111111', 'Asia/Tokyo');
insert into public.accounts (id, auth_user_id, timezone)
values ('92222222-2222-4222-8222-222222222222', '92222222-2222-4222-8222-222222222222', 'Asia/Tokyo');
insert into public.consents (account_id, consent_type, version, status, adult_declared)
values ('91111111-1111-4111-8111-111111111111', 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);
select public.command_capture_text(
  '91111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy paper', 'PRIVATE',
  '91111111-1111-4111-8111-222222222222'
);

create function private.fail_raw_delete_fixture()
returns trigger language plpgsql as $$
begin
  raise exception 'fixture raw deletion failure';
end;
$$;

select public.command_capture_text(
  '91111111-1111-4111-8111-111111111111', 'GENERAL_ADMIN', 'renew library card', 'PRIVATE',
  '91111111-1111-4111-8111-333333333333'
);
do $$
declare
  v_capture uuid;
  v_loop uuid;
begin
  select c.id into v_capture from public.captures c
    where c.account_id = '91111111-1111-4111-8111-111111111111' and c.status = 'STORED';
  v_loop := public.command_record_interpretation(
    '91111111-1111-4111-8111-111111111111', v_capture,
    'Renew card', 'Card is renewed', null, now() + interval '1 day', null,
    'gpt-5.6-luna', 20, 15, 0.000022
  );
end;
$$;
create trigger fail_raw_delete_fixture before delete on private.capture_raws
  for each row execute function private.fail_raw_delete_fixture();

do $$
declare
  v_capture uuid;
  v_loop uuid;
  v_ack text;
begin
  select c.id, l.id into v_capture, v_loop from public.captures c
    join public.open_loops l on l.capture_id = c.id
    where c.account_id = '91111111-1111-4111-8111-111111111111'
      and c.status = 'OFFLOAD_READY' and l.status = 'ACTIVE';
  if v_capture is null or v_loop is null then raise exception 'active loop fixture unavailable'; end if;
  begin
    perform public.command_begin_raw_deletion('92222222-2222-4222-8222-222222222222', v_capture);
    raise exception 'cross-account Raw deletion was allowed';
  exception when sqlstate '42501' then null;
  end;
  perform public.command_begin_raw_deletion(
    '91111111-1111-4111-8111-111111111111', v_capture
  );
  if (select status from public.captures where id = v_capture) <> 'DELETION_PENDING' or
     exists (select 1 from public.command_interpretation_source('91111111-1111-4111-8111-111111111111', v_capture)) then
    raise exception 'pending deletion did not block processing';
  end if;
  begin
    perform public.command_finish_raw_deletion(v_capture);
    raise exception 'deletion failure was not raised';
  exception when others then
    if sqlerrm <> 'fixture raw deletion failure' then raise; end if;
  end;
  if (select status from public.captures where id = v_capture) <> 'DELETION_PENDING' then
    raise exception 'failed deletion lost pending status';
  end if;
  drop trigger fail_raw_delete_fixture on private.capture_raws;
  perform public.command_finish_raw_deletion(v_capture);
  if (select status from public.captures where id = v_capture) <> 'DELETED' or
     exists (select 1 from private.capture_raws where capture_id = v_capture) or
     (select status from public.open_loops where id = v_loop) <> 'ACTIVE' or
     not exists (select 1 from public.loop_events where loop_id = v_loop and event_type = 'OFFLOAD_READY') then
    raise exception 'Raw deletion removed tracking or left Raw behind';
  end if;
  v_ack := public.command_ack_offload_receipt('91111111-1111-4111-8111-111111111111', v_loop, 1);
  if v_ack <> 'ACKED' or
     (select activated_at from public.open_loops where id = v_loop) is null then
    raise exception 'receipt failed after Raw deletion';
  end if;
  perform public.command_loop_action('91111111-1111-4111-8111-111111111111', v_loop, 'MARK_DONE');
  perform public.command_record_ownership('91111111-1111-4111-8111-111111111111', v_loop, 'OWNED');
end;
$$;

select public.command_register_push(
  '91111111-1111-4111-8111-111111111111',
  '91111111-1111-4111-8111-444444444444',
  'ExpoPushToken[synthetic_token_1234567890]'
);

insert into private.auth_challenges (
  account_id, auth_user_id, session_id, action_kind, expires_at
) values (
  '91111111-1111-4111-8111-111111111111',
  '91111111-1111-4111-8111-111111111111', 'test-session', 'DELETE_ACCOUNT', now() + interval '10 minutes'
);
insert into private.recent_auth_proofs (
  challenge_id, account_id, auth_user_id, session_id, action_kind, expires_at
) select id, account_id, auth_user_id, session_id, action_kind, expires_at
  from private.auth_challenges where account_id = '91111111-1111-4111-8111-111111111111'
    and action_kind = 'DELETE_ACCOUNT';

do $$
declare
  v_proof uuid;
begin
  select id into v_proof from private.recent_auth_proofs
    where account_id = '91111111-1111-4111-8111-111111111111' and action_kind = 'DELETE_ACCOUNT';
  perform public.command_begin_account_deletion(
    '91111111-1111-4111-8111-111111111111', 'test-session', v_proof
  );
  if (select status from public.accounts where id = '91111111-1111-4111-8111-111111111111') <> 'DELETION_PENDING' then
    raise exception 'account access was not stopped';
  end if;
  perform public.command_finish_account_deletion('91111111-1111-4111-8111-111111111111');
  if exists (select 1 from public.accounts where id = '91111111-1111-4111-8111-111111111111') or
     exists (select 1 from public.captures where account_id = '91111111-1111-4111-8111-111111111111') or
     exists (select 1 from private.audit_events where account_id = '91111111-1111-4111-8111-111111111111') or
     exists (select 1 from private.device_installations where account_id = '91111111-1111-4111-8111-111111111111') then
    raise exception 'account-linked rows remain';
  end if;
  if (select eligible_loops from private.p1_metrics()) <> 1 or
     (select owned_socs from private.p1_metrics()) <> 1 then
    raise exception 'anonymous aggregate was lost during account deletion';
  end if;
end;
$$;

rollback;
