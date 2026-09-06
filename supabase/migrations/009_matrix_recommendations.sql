create table if not exists public.matrix_recommendations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  person_id uuid references public.matrix_people(id),
  anonymous_profile_id uuid references public.matrix_anonymous_profiles(id),
  recommendation_type text not null,
  engine_version text not null,
  status text not null default 'generated',
  confidence numeric(5,4) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  reason_code text not null,
  reason_text text not null,
  source_signals jsonb not null default '[]'::jsonb,
  generated_at timestamptz not null default now(),
  expires_at timestamptz,
  correlation_id uuid,
  check (person_id is not null or anonymous_profile_id is not null)
);

create table if not exists public.matrix_recommendation_items (
  recommendation_id uuid not null references public.matrix_recommendations(id) on delete cascade,
  rank integer not null check (rank > 0),
  object_type text not null,
  object_id uuid not null,
  score numeric(10,4) not null,
  reason_text text,
  metadata jsonb not null default '{}'::jsonb,
  primary key (recommendation_id, rank)
);

create table if not exists public.matrix_recommendation_feedback (
  id uuid primary key default gen_random_uuid(),
  recommendation_id uuid not null references public.matrix_recommendations(id) on delete cascade,
  person_id uuid references public.matrix_people(id),
  feedback_type text not null,
  event_id uuid references public.matrix_events(id),
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
