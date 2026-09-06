-- Matrix Attual Core
-- Migration 002: tenants and projects

begin;

create table if not exists public.matrix_tenants (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  status text not null default 'active'
    check (status in ('active','suspended','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.matrix_projects (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_key text not null,
  name text not null,
  project_type text not null,
  status text not null default 'active',
  atlas_project_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, project_key)
);

commit;
