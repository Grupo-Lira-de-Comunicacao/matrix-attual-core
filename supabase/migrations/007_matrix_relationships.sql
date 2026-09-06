create table if not exists public.matrix_relationships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid references public.matrix_projects(id),
  subject_type text not null,
  subject_id uuid not null,
  predicate text not null,
  object_type text not null,
  object_id uuid not null,
  weight numeric(8,4) not null default 1.0,
  confidence numeric(5,4) not null default 1.0 check (confidence >= 0 and confidence <= 1),
  source text not null,
  first_observed_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_matrix_relationships_subject on public.matrix_relationships (tenant_id, subject_type, subject_id, predicate);
create index if not exists idx_matrix_relationships_object on public.matrix_relationships (tenant_id, object_type, object_id, predicate);
