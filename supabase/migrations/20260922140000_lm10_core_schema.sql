create type public.capture_input_type as enum ('TEXT');
create type public.capture_status as enum (
  'STORED', 'PROCESSING', 'NEEDS_CONFIRMATION', 'OFFLOAD_READY',
  'FAILED_SAFE', 'DELETION_PENDING', 'DELETED'
);
create type public.sensitivity_class as enum ('PRIVATE', 'SENSITIVE', 'SECRET', 'UNCLASSIFIED');
create type public.open_loop_status as enum ('ACTIVE', 'ENDING', 'CLOSED');
create type public.effective_state as enum (
  'UNKNOWN', 'UNSATISFIED', 'SATISFIED', 'CONFLICT', 'NO_LONGER_REQUIRED'
);
create type public.loop_actor_type as enum ('USER', 'SYSTEM', 'AI_DERIVED');

create table public.captures (
  id uuid primary key default extensions.gen_random_uuid(),
  account_id uuid not null references public.accounts (id),
  input_type public.capture_input_type not null default 'TEXT',
  status public.capture_status not null default 'STORED',
  sensitivity_class public.sensitivity_class not null default 'UNCLASSIFIED',
  external_ai_allowed boolean not null default false,
  processing_attempt_count integer not null default 0 check (processing_attempt_count >= 0),
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, account_id),
  check (sensitivity_class = 'PRIVATE' or not external_ai_allowed)
);

create table private.capture_raws (
  capture_id uuid primary key,
  account_id uuid not null,
  raw_text text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (capture_id, account_id) references public.captures (id, account_id)
);

create table public.open_loops (
  id uuid primary key default extensions.gen_random_uuid(),
  account_id uuid not null references public.accounts (id),
  capture_id uuid not null,
  status public.open_loop_status not null default 'ACTIVE',
  title text not null,
  expected_state_text text not null,
  effective_state public.effective_state not null default 'UNKNOWN',
  due_at timestamptz,
  next_evaluation_at timestamptz,
  offload_ready_at timestamptz,
  activated_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, account_id),
  foreign key (capture_id, account_id) references public.captures (id, account_id)
);

create index open_loops_account_status_idx on public.open_loops (account_id, status);
create index open_loops_capture_idx on public.open_loops (capture_id);
create index open_loops_next_evaluation_idx on public.open_loops (next_evaluation_at) where status = 'ACTIVE';

create table public.loop_events (
  id uuid primary key default extensions.gen_random_uuid(),
  loop_id uuid not null,
  account_id uuid not null,
  event_type text not null,
  actor_type public.loop_actor_type not null,
  basis_revision integer not null check (basis_revision > 0),
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  foreign key (loop_id, account_id) references public.open_loops (id, account_id)
);

create index loop_events_loop_occurred_at_idx on public.loop_events (loop_id, occurred_at);

alter table public.captures enable row level security;
alter table public.open_loops enable row level security;
alter table public.loop_events enable row level security;
alter table private.capture_raws enable row level security;

revoke all on public.captures, public.open_loops, public.loop_events from anon, authenticated;
grant select on public.captures, public.open_loops, public.loop_events to authenticated;

create policy "captures: owner can read"
  on public.captures for select to authenticated
  using (account_id = (select id from public.accounts where auth_user_id = (select auth.uid())));

create policy "open loops: owner can read"
  on public.open_loops for select to authenticated
  using (account_id = (select id from public.accounts where auth_user_id = (select auth.uid())));

create policy "loop events: owner can read"
  on public.loop_events for select to authenticated
  using (account_id = (select id from public.accounts where auth_user_id = (select auth.uid())));

revoke all on private.capture_raws from public, anon, authenticated;
