create table if not exists public.matrix_api_clients (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid references public.matrix_projects(id),
  client_name text not null,
  client_type text not null,
  status text not null default 'active',
  allowed_scopes text[] not null default '{}',
  rate_limit_profile text not null default 'standard',
  created_at timestamptz not null default now(),
  rotated_at timestamptz
);

create table if not exists public.matrix_audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.matrix_tenants(id),
  project_id uuid references public.matrix_projects(id),
  actor_type text not null,
  actor_id text,
  action text not null,
  target_type text,
  target_id text,
  result text not null,
  correlation_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_matrix_audit_time on public.matrix_audit_log (created_at desc);
create index if not exists idx_matrix_audit_correlation on public.matrix_audit_log (correlation_id) where correlation_id is not null;
