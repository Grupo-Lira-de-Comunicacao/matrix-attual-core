create table if not exists public.matrix_processing_checkpoints (
  processor_key text primary key,
  last_processed_at timestamptz,
  last_event_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.matrix_dead_letter_events (
  id uuid primary key default gen_random_uuid(),
  original_event_id uuid,
  event_payload jsonb not null,
  failure_code text not null,
  failure_detail text,
  retry_count integer not null default 0 check (retry_count >= 0),
  first_failed_at timestamptz not null default now(),
  last_failed_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists idx_matrix_dlq_unresolved on public.matrix_dead_letter_events (last_failed_at desc) where resolved_at is null;
