create table if not exists public.matrix_events (
  id uuid primary key,
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  person_id uuid references public.matrix_people(id),
  anonymous_profile_id uuid references public.matrix_anonymous_profiles(id),
  event_type text not null,
  object_type text,
  object_id text,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  session_id text,
  correlation_id uuid,
  source text not null,
  schema_version integer not null default 1 check (schema_version > 0),
  consent_snapshot jsonb not null default '{}'::jsonb,
  properties jsonb not null default '{}'::jsonb,
  context jsonb not null default '{}'::jsonb,
  idempotency_key text not null,
  processing_status text not null default 'pending' check (processing_status in ('pending','processed','failed','ignored')),
  created_at timestamptz not null default now(),
  unique (tenant_id, project_id, idempotency_key)
);

create index if not exists idx_matrix_events_person_time on public.matrix_events (person_id, occurred_at desc) where person_id is not null;
create index if not exists idx_matrix_events_anon_time on public.matrix_events (anonymous_profile_id, occurred_at desc) where anonymous_profile_id is not null;
create index if not exists idx_matrix_events_project_type_time on public.matrix_events (project_id, event_type, occurred_at desc);
create index if not exists idx_matrix_events_pending on public.matrix_events (received_at) where processing_status = 'pending';
create index if not exists idx_matrix_events_properties_gin on public.matrix_events using gin (properties);

create table if not exists public.matrix_event_invalidations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.matrix_events(id),
  reason text not null,
  actor_type text not null,
  actor_id text,
  correlation_id uuid,
  created_at timestamptz not null default now()
);
