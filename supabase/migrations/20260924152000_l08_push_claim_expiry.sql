create or replace function public.command_expire_push_claims(p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path = ''
as $$
declare v_count integer;
begin
  update private.push_attempts set state = 'RECEIPT_ERROR'
    where (state = 'CLAIMED' and claimed_at <= p_now - interval '15 minutes')
       or (state = 'RECONCILING' and reconciled_at <= p_now - interval '15 minutes');
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.command_expire_push_claims(timestamptz) from public, anon, authenticated;
grant execute on function public.command_expire_push_claims(timestamptz) to service_role;
