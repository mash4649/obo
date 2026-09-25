drop function public.command_begin_raw_deletion(uuid, uuid, text, uuid);

create function public.command_begin_raw_deletion(
  p_auth_user_id uuid, p_capture_id uuid
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_capture public.captures%rowtype;
begin
  select c.* into v_capture from public.captures c
    join public.accounts a on a.id = c.account_id
    where c.id = p_capture_id and a.auth_user_id = p_auth_user_id and a.status = 'ACTIVE'
    for update of c;
  if not found then raise exception 'capture unavailable' using errcode = '42501'; end if;
  if v_capture.status = 'DELETED' or not exists (
    select 1 from private.capture_raws where capture_id = p_capture_id
  ) then return 'DELETED'; end if;
  if v_capture.status = 'DELETION_PENDING' then return 'DELETION_PENDING'; end if;

  update public.captures set
    status = 'DELETION_PENDING', external_ai_allowed = false, updated_at = now()
    where id = p_capture_id;
  insert into private.audit_events (account_id, actor_principal, action, target_type, target_id)
  values (v_capture.account_id, p_auth_user_id::text, 'RAW_DELETION_REQUESTED', 'capture', p_capture_id);
  return 'DELETION_PENDING';
end;
$$;

revoke all on function public.command_begin_raw_deletion(uuid, uuid) from public, anon, authenticated;
grant execute on function public.command_begin_raw_deletion(uuid, uuid) to service_role;
