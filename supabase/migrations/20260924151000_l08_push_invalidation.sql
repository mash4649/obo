create or replace function public.command_invalidate_push_installation(p_installation_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update private.device_installations
    set status = 'INVALID', opted_in = false, updated_at = now()
    where id = p_installation_id;
end;
$$;
revoke all on function public.command_invalidate_push_installation(uuid) from public, anon, authenticated;
grant execute on function public.command_invalidate_push_installation(uuid) to service_role;
