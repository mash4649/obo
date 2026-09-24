create extension if not exists pg_cron;

select cron.schedule(
  'obo-evaluate-due-loops',
  '*/5 * * * *',
  'select count(*) from private.evaluate_due_loops(now())'
);
