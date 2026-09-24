begin;

insert into public.accounts (id, auth_user_id, timezone)
values
  ('31111111-1111-4111-8111-111111111111', '31111111-1111-4111-8111-111111111111', 'Asia/Tokyo'),
  ('32222222-2222-4222-8222-222222222222', '32222222-2222-4222-8222-222222222222', 'Asia/Tokyo');

insert into public.captures (id, account_id, scope, sensitivity_class, external_ai_allowed)
values
  ('41111111-1111-4111-8111-111111111111', '31111111-1111-4111-8111-111111111111', 'SHOPPING', 'PRIVATE', false),
  ('42222222-2222-4222-8222-222222222222', '32222222-2222-4222-8222-222222222222', 'SHOPPING', 'PRIVATE', false);

insert into private.capture_raws (capture_id, account_id, raw_text)
values ('41111111-1111-4111-8111-111111111111', '31111111-1111-4111-8111-111111111111', 'test raw');

insert into public.open_loops (id, account_id, capture_id, title, expected_state_text)
values
  ('51111111-1111-4111-8111-111111111111', '31111111-1111-4111-8111-111111111111', '41111111-1111-4111-8111-111111111111', 'own loop', 'done'),
  ('52222222-2222-4222-8222-222222222222', '32222222-2222-4222-8222-222222222222', '42222222-2222-4222-8222-222222222222', 'other loop', 'done');

insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
values
  ('51111111-1111-4111-8111-111111111111', '31111111-1111-4111-8111-111111111111', 'INTERPRETATION_CREATED', 'SYSTEM', 1),
  ('52222222-2222-4222-8222-222222222222', '32222222-2222-4222-8222-222222222222', 'INTERPRETATION_CREATED', 'SYSTEM', 1);

set local role authenticated;
select set_config('request.jwt.claim.sub', '31111111-1111-4111-8111-111111111111', true);

do $$
begin
  if (select count(*) from public.captures where id in ('41111111-1111-4111-8111-111111111111', '42222222-2222-4222-8222-222222222222')) <> 1 then
    raise exception 'capture RLS exposed another account';
  end if;

  if (select count(*) from public.open_loops where id in ('51111111-1111-4111-8111-111111111111', '52222222-2222-4222-8222-222222222222')) <> 1 then
    raise exception 'loop RLS exposed another account';
  end if;

  if (select count(*) from public.loop_events where loop_id in ('51111111-1111-4111-8111-111111111111', '52222222-2222-4222-8222-222222222222')) <> 1 then
    raise exception 'event RLS exposed another account';
  end if;

  begin
    update public.open_loops set activated_at = now()
      where id = '51111111-1111-4111-8111-111111111111';
    raise exception 'direct activation unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    update public.captures set status = 'DELETED'
      where id = '42222222-2222-4222-8222-222222222222';
    raise exception 'cross-account update unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    delete from public.open_loops where id = '52222222-2222-4222-8222-222222222222';
    raise exception 'cross-account delete unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values ('51111111-1111-4111-8111-111111111111', '31111111-1111-4111-8111-111111111111', 'SOC_RECORDED', 'USER', 1);
    raise exception 'direct SOC unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision)
    values ('51111111-1111-4111-8111-111111111111', '31111111-1111-4111-8111-111111111111', 'OWNERSHIP_MEASURED', 'USER', 1);
    raise exception 'direct ownership unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform raw_text from private.capture_raws;
    raise exception 'Raw client read unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

rollback;
