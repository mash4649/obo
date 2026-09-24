create or replace function private.expire_unacknowledged_raws(p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_count integer;
begin
  -- Daily scheduling needs one day of headroom to keep Raw below the seven-day limit.
  update public.captures c set
      status = case when c.status = 'DELETION_PENDING' then 'DELETED'::public.capture_status
                    else 'FAILED_SAFE'::public.capture_status end,
      external_ai_allowed = false, last_error_code = 'RAW_EXPIRED', updated_at = p_now
    from private.capture_raws r
    where r.capture_id = c.id and r.created_at <= p_now - interval '6 days'
      and c.status in ('STORED', 'PROCESSING', 'DELETION_PENDING');
  delete from private.capture_raws r using public.captures c
    where r.capture_id = c.id and r.created_at <= p_now - interval '6 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

select cron.schedule(
  'obo-expire-unacknowledged-raws',
  '0 2 * * *',
  'select private.expire_unacknowledged_raws(now())'
);
