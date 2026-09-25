begin;

do $$
declare
  v_account uuid := '93333333-3333-4333-8333-333333333333';
  v_due uuid;
  v_pending uuid;
  v_fresh uuid;
  v_now timestamptz := now();
begin
  if not exists (
    select 1 from cron.job where jobname = 'obo-expire-unacknowledged-raws'
      and schedule = '0 2 * * *'
      and command = 'select private.expire_unacknowledged_raws(now())' and active
  ) then raise exception 'daily Raw expiry job is unavailable'; end if;

  insert into public.accounts (id, auth_user_id, timezone)
  values (v_account, v_account, 'Asia/Tokyo');
  insert into public.consents (account_id, consent_type, version, status, adult_declared)
  values (v_account, 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);
  v_due := public.command_capture_text(v_account, 'SHOPPING', 'due item', 'PRIVATE',
    '93333333-3333-4333-8333-333333333331');
  v_pending := public.command_capture_text(v_account, 'SHOPPING', 'pending item', 'PRIVATE',
    '93333333-3333-4333-8333-333333333332');
  v_fresh := public.command_capture_text(v_account, 'SHOPPING', 'fresh item', 'PRIVATE',
    '93333333-3333-4333-8333-333333333333');

  update private.capture_raws set created_at = v_now - interval '6 days 1 minute'
    where capture_id in (v_due, v_pending);
  update private.capture_raws set created_at = v_now - interval '5 days 23 hours'
    where capture_id = v_fresh;
  update public.captures set status = 'DELETION_PENDING', external_ai_allowed = false
    where id = v_pending;

  perform private.expire_unacknowledged_raws(v_now);
  if (select status from public.captures where id = v_due) <> 'FAILED_SAFE' or
     (select external_ai_allowed from public.captures where id = v_due) or
     exists (select 1 from private.capture_raws where capture_id = v_due) or
     exists (select 1 from public.command_interpretation_source(v_account, v_due)) then
    raise exception 'due Raw remained processable';
  end if;
  if (select status from public.captures where id = v_pending) <> 'DELETED' or
     exists (select 1 from private.capture_raws where capture_id = v_pending) then
    raise exception 'pending Raw was not physically deleted';
  end if;
  if (select status from public.captures where id = v_fresh) <> 'STORED' or
     not exists (select 1 from private.capture_raws where capture_id = v_fresh) then
    raise exception 'fresh Raw expired early';
  end if;
  perform private.expire_unacknowledged_raws(v_now);
  if (select status from public.captures where id = v_fresh) <> 'STORED' or
     not exists (select 1 from private.capture_raws where capture_id = v_fresh) then
    raise exception 'expiry retry changed fresh Raw';
  end if;
end;
$$;

rollback;
