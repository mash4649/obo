begin;

insert into public.accounts (id, auth_user_id, timezone)
values ('61111111-1111-4111-8111-111111111111', '61111111-1111-4111-8111-111111111111', 'Asia/Tokyo');

insert into public.consents (account_id, consent_type, version, status, adult_declared)
values ('61111111-1111-4111-8111-111111111111', 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);

select public.command_capture_text(
  '61111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy paper', 'PRIVATE',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

select public.command_capture_text(
  '61111111-1111-4111-8111-111111111111', 'SHOPPING', 'buy paper', 'PRIVATE',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

do $$
begin
  if (select count(*) from public.captures where account_id = '61111111-1111-4111-8111-111111111111') <> 1 then
    raise exception 'duplicate capture was created';
  end if;

  if (select count(*) from private.capture_raws where account_id = '61111111-1111-4111-8111-111111111111') <> 1 then
    raise exception 'Raw was not stored atomically';
  end if;
end;
$$;

select public.command_capture_text(
  '61111111-1111-4111-8111-111111111111', 'GENERAL_ADMIN', 'password: synthetic', 'SECRET',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

do $$
begin
  if exists (
    select 1 from private.capture_raws r join public.captures c on c.id = r.capture_id
    where c.sensitivity_class = 'SECRET'
  ) then
    raise exception 'SECRET Raw was stored';
  end if;
end;
$$;

create function private.fail_capture_raw_test()
returns trigger
language plpgsql
as $$
begin
  if new.raw_text = 'force failure' then
    raise exception 'forced raw failure';
  end if;
  return new;
end;
$$;

create trigger fail_capture_raw_test
before insert on private.capture_raws
for each row execute function private.fail_capture_raw_test();

do $$
begin
  begin
    perform public.command_capture_text(
      '61111111-1111-4111-8111-111111111111', 'SCHEDULE', 'force failure', 'PRIVATE',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    );
    raise exception 'forced Raw failure unexpectedly succeeded';
  exception when others then
    if sqlerrm <> 'forced raw failure' then
      raise;
    end if;
  end;

  if exists (
    select 1 from private.capture_idempotency
    where auth_user_id = '61111111-1111-4111-8111-111111111111'
      and idempotency_key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  ) then
    raise exception 'failed capture left an idempotency record';
  end if;
end;
$$;

rollback;
