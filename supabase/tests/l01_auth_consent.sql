begin;

select public.command_accept_p1_consent(
  '11111111-1111-4111-8111-111111111111',
  'Asia/Tokyo',
  'p1-test-v1',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

select public.command_accept_p1_consent(
  '11111111-1111-4111-8111-111111111111',
  'Asia/Tokyo',
  'p1-test-v1',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

do $$
begin
  if (select count(*) from public.consents where account_id = (
    select id from public.accounts where auth_user_id = '11111111-1111-4111-8111-111111111111'
  )) <> 1 then
    raise exception 'consent history was not idempotent';
  end if;
end;
$$;

insert into private.auth_challenges (
  account_id, auth_user_id, session_id, action_kind, expires_at
) values (
  (select id from public.accounts where auth_user_id = '11111111-1111-4111-8111-111111111111'),
  '11111111-1111-4111-8111-111111111111', 'session-a', 'WITHDRAW_CONSENT', now() + interval '10 minutes'
);

select public.command_verify_recent_auth(
  '11111111-1111-4111-8111-111111111111', 'session-a', 'WITHDRAW_CONSENT'
);

select public.command_withdraw_p1_consent(
  '11111111-1111-4111-8111-111111111111',
  'session-a',
  (
    select id from private.recent_auth_proofs
    where auth_user_id = '11111111-1111-4111-8111-111111111111'
    order by created_at desc
    limit 1
  ),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

do $$
begin
  if not exists (
    select 1 from public.accounts
    where auth_user_id = '11111111-1111-4111-8111-111111111111' and status = 'DELETION_PENDING'
  ) then
    raise exception 'withdrawal did not place the account in DELETION_PENDING';
  end if;

  if (select count(*) from public.consents where account_id = (
    select id from public.accounts where auth_user_id = '11111111-1111-4111-8111-111111111111'
  )) <> 2 then
    raise exception 'withdrawal did not append consent history';
  end if;

  if not exists (
    select 1 from private.recent_auth_proofs
    where auth_user_id = '11111111-1111-4111-8111-111111111111' and used_at is not null
  ) then
    raise exception 'withdrawal did not consume the recent-auth proof';
  end if;
end;
$$;

insert into public.accounts (id, auth_user_id, timezone)
values ('22222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'Asia/Tokyo');

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);

do $$
begin
  if (select count(*) from public.accounts) <> 1 then
    raise exception 'RLS exposed another account';
  end if;

  begin
    insert into public.consents (account_id, consent_type, version, status, adult_declared)
    values ('22222222-2222-4222-8222-222222222222', 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);
    raise exception 'direct client consent insert unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform public.command_accept_p1_consent(
      '11111111-1111-4111-8111-111111111111', 'Asia/Tokyo', 'p1-test-v1', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    );
    raise exception 'client command function unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

rollback;
