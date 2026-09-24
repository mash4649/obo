create type public.delivery_status as enum ('PENDING', 'PROVIDER_ACCEPTED', 'RECEIPT_OK', 'RECEIPT_ERROR', 'CANCELLED');
create type public.delivery_channel as enum ('IN_APP', 'PUSH');

create table public.deliveries (
  id uuid primary key default extensions.gen_random_uuid(),
  loop_id uuid not null,
  account_id uuid not null,
  basis_revision integer not null check (basis_revision > 0),
  reason_code text not null,
  scheduled_evaluation_at timestamptz not null,
  channel public.delivery_channel not null default 'IN_APP',
  status public.delivery_status not null default 'PENDING',
  provider_message_id text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  receipt_at timestamptz,
  foreign key (loop_id, account_id) references public.open_loops (id, account_id),
  unique (loop_id, basis_revision, reason_code, scheduled_evaluation_at)
);
create index deliveries_account_status_idx on public.deliveries (account_id, status);
alter table public.deliveries enable row level security;
revoke all on public.deliveries from anon, authenticated;
grant select on public.deliveries to authenticated;
create policy "deliveries: owner can read"
  on public.deliveries for select to authenticated
  using (account_id = (select id from public.accounts where auth_user_id = (select auth.uid())));

create or replace function private.cancel_stale_deliveries()
returns trigger language plpgsql set search_path = ''
as $$
begin
  update public.deliveries set status = 'CANCELLED'
    where loop_id = new.id and status = 'PENDING'
      and (basis_revision <> new.revision or new.status <> 'ACTIVE'
           or new.effective_state <> 'UNSATISFIED');
  return new;
end;
$$;
create trigger cancel_stale_deliveries
  after update of revision, status, effective_state on public.open_loops
  for each row execute function private.cancel_stale_deliveries();

create or replace function private.evaluate_due_loops(p_now timestamptz default now())
returns table (loop_id uuid, decision text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_loop public.open_loops%rowtype;
  v_decision text;
  v_attempt integer;
begin
  for v_loop in
    select l.* from public.open_loops l
      where l.status = 'ACTIVE' and l.activated_at is not null and l.next_evaluation_at <= p_now
      order by l.next_evaluation_at, l.id
      limit 25
      for update of l skip locked
  loop
    for v_attempt in 1..2 loop
      begin
        if v_loop.effective_state in ('SATISFIED', 'NO_LONGER_REQUIRED') then
          v_decision := 'SILENCE';
        elsif v_loop.effective_state = 'UNSATISFIED'
          and exists (select 1 from public.loop_events e where e.loop_id = v_loop.id
                      and e.event_type = 'OFFLOAD_RECEIPT_ACKED' and e.basis_revision = v_loop.revision)
          and (select co.status from public.consents co where co.account_id = v_loop.account_id
               and co.consent_type = 'P1_CORE' order by co.occurred_at desc limit 1) = 'ACCEPTED'
          and (select a.status from public.accounts a where a.id = v_loop.account_id) = 'ACTIVE'
          and not exists (select 1 from public.deliveries d where d.loop_id = v_loop.id
                          and d.basis_revision = v_loop.revision and d.status = 'PENDING') then
          v_decision := 'ACT';
        else
          v_decision := 'DEFER';
        end if;

        insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision, payload)
        values (v_loop.id, v_loop.account_id, 'EVALUATED', 'SYSTEM', v_loop.revision,
          jsonb_build_object('scheduled_evaluation_at', v_loop.next_evaluation_at));
        insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision, payload)
        values (v_loop.id, v_loop.account_id, 'DECISION_' || v_decision, 'SYSTEM', v_loop.revision,
          jsonb_build_object('scheduled_evaluation_at', v_loop.next_evaluation_at));

        if v_decision = 'ACT' then
          insert into public.deliveries (loop_id, account_id, basis_revision, reason_code, scheduled_evaluation_at)
          values (v_loop.id, v_loop.account_id, v_loop.revision, 'EXPECTED_STATE_UNSATISFIED', v_loop.next_evaluation_at)
          on conflict do nothing;
          update public.open_loops set next_evaluation_at = null, updated_at = p_now where id = v_loop.id;
        elsif v_decision = 'SILENCE' then
          update public.open_loops set next_evaluation_at = null, updated_at = p_now where id = v_loop.id;
        else
          update public.open_loops set next_evaluation_at = p_now + interval '15 minutes', updated_at = p_now where id = v_loop.id;
        end if;
        exit;
      exception when others then
        if v_attempt = 1 then
          perform pg_catalog.pg_sleep(1 + pg_catalog.random() * 4);
        else
          v_decision := 'DEFER';
          insert into public.loop_events (loop_id, account_id, event_type, actor_type, basis_revision, payload)
          values (v_loop.id, v_loop.account_id, 'DECISION_DEFER', 'SYSTEM', v_loop.revision,
            '{"reason_code":"EVALUATION_ERROR"}'::jsonb);
          update public.open_loops set next_evaluation_at = p_now + interval '15 minutes', updated_at = p_now
            where id = v_loop.id;
        end if;
      end;
    end loop;
    loop_id := v_loop.id;
    decision := v_decision;
    return next;
  end loop;
end;
$$;

revoke all on function private.evaluate_due_loops(timestamptz) from public, anon, authenticated;
grant execute on function private.evaluate_due_loops(timestamptz) to service_role;
