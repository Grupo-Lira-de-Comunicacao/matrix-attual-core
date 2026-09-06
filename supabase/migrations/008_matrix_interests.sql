create table if not exists public.matrix_interest_scores (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  person_id uuid not null references public.matrix_people(id),
  topic_id uuid not null references public.matrix_topics(id),
  score numeric(10,4) not null default 0,
  confidence numeric(5,4) not null default 0 check (confidence >= 0 and confidence <= 1),
  signal_count integer not null default 0 check (signal_count >= 0),
  engine_version text not null,
  calculated_at timestamptz not null default now(),
  unique (tenant_id, person_id, topic_id)
);

create table if not exists public.matrix_interest_evidence (
  id uuid primary key default gen_random_uuid(),
  interest_score_id uuid not null references public.matrix_interest_scores(id) on delete cascade,
  event_id uuid not null references public.matrix_events(id),
  contribution numeric(10,4) not null,
  reason_code text not null,
  created_at timestamptz not null default now(),
  unique (interest_score_id, event_id, reason_code)
);
