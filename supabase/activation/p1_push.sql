-- Run only after Expo credentials, authorized iOS device, and L08 release evidence are approved.
-- Vault secrets obo_project_url and obo_push_job_secret must match the deployed function.
create extension if not exists pg_net with schema extensions;

do $$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'obo_project_url') or
     not exists (select 1 from vault.decrypted_secrets where name = 'obo_push_job_secret') then
    raise exception 'P1 Push Vault secrets are missing';
  end if;
end;
$$;

select cron.schedule('obo-p1-push', '*/5 * * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'obo_project_url') || '/functions/v1/push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-job-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'obo_push_job_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
$job$);
