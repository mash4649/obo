alter table private.capture_idempotency
  drop constraint capture_idempotency_capture_id_fkey,
  add constraint capture_idempotency_capture_id_fkey
    foreign key (capture_id) references public.captures (id)
    deferrable initially deferred;
