begin;

do $$
declare
  v_auth uuid;
  v_account uuid;
  v_capture uuid;
  v_loop uuid;
  v_count integer := 0;
  v_report jsonb;
begin
  for participant in 1..5 loop
    v_auth := extensions.gen_random_uuid();
    insert into public.accounts(auth_user_id, timezone)
      values (v_auth, 'Asia/Tokyo') returning id into v_account;
    insert into public.consents(account_id, consent_type, version, status, adult_declared)
      values (v_account, 'P1_CORE', 'p1-test-v1', 'ACCEPTED', true);
    for item in 1..2 loop
      v_count := v_count + 1;
      v_capture := public.command_capture_text(
        v_auth, 'SHOPPING', 'buy paper', 'PRIVATE', extensions.gen_random_uuid()
      );
      v_loop := public.command_record_interpretation(
        v_auth, v_capture, 'Buy paper', 'Paper is bought', null, now() + interval '1 day',
        null, 'gpt-5.6-luna', 20, 15, 0.000022
      );
      update public.open_loops set offload_ready_at = now() - interval '9 days',
        activated_at = now() - interval '8 days', effective_state = 'SATISFIED',
        status = 'CLOSED', next_evaluation_at = null where id = v_loop;
      insert into private.p1_cohort_loops(loop_id, account_id, eligible_at, evidence_ref, verified_by)
        values (v_loop, v_account, now() - interval '9 days',
          extensions.gen_random_uuid(), 'fixture');
      insert into public.loop_events(
        loop_id, account_id, event_type, actor_type, basis_revision, occurred_at
      ) values
        (v_loop, v_account, 'OFFLOAD_RECEIPT_ACKED', 'USER', 1, now() - interval '8 days'),
        (v_loop, v_account, 'USER_MARKED_DONE', 'USER', 1, now() - interval '8 days'),
        (v_loop, v_account, 'SOC_RECORDED', 'SYSTEM', 1, now() - interval '8 days');
      if v_count <= 3 then
        insert into public.loop_events(
          loop_id, account_id, event_type, actor_type, basis_revision, payload
        ) values (
          v_loop, v_account, 'OWNERSHIP_MEASURED', 'USER', 1, '{"result":"OWNED"}'::jsonb
        );
      end if;
    end loop;
  end loop;

  v_report := private.p1_checkpoint();
  if v_report->>'status' <> 'HOLD' or v_report->>'primary_bottleneck' <> 'AUDIT_MISSING' then
    raise exception 'missing incident audit was treated as zero';
  end if;
  insert into private.p1_incident_audits(evidence_ref, reviewed_by)
    values (extensions.gen_random_uuid(), 'fixture-reviewer');
  v_report := private.p1_checkpoint();
  if v_report->>'status' <> 'PASS' or (v_report->>'eligible_loops')::integer <> 10 or
     (v_report->>'participants')::integer <> 5 or
     (v_report->>'matured_contexts')::integer <> 10 or
     (v_report->>'owned_matured_contexts')::integer <> 3 then
    raise exception 'qualified checkpoint was not PASS: %', v_report;
  end if;

  update private.p1_incident_audits set false_ack_count = 1;
  v_report := private.p1_checkpoint();
  if v_report->>'status' <> 'HOLD' or v_report->>'primary_bottleneck' <> 'TRUST' then
    raise exception 'critical trust issue did not HOLD';
  end if;

  update private.p1_incident_audits set false_ack_count = 0, focused_iterations = 2;
  delete from public.loop_events where event_type = 'OFFLOAD_RECEIPT_ACKED'
    and loop_id in (select loop_id from private.p1_cohort_loops order by loop_id limit 7);
  v_report := private.p1_checkpoint();
  if v_report->>'status' <> 'RECONSIDER' or v_report->>'primary_bottleneck' <> 'ACTIVATION' then
    raise exception 'two low-activation iterations did not RECONSIDER: %', v_report;
  end if;
end;
$$;

rollback;
