create table if not exists public.matrix_segments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid references public.matrix_projects(id),
  key text not null,
  name text not null,
  definition jsonb not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, project_id, key)
);

create table if not exists public.matrix_segment_memberships (
  segment_id uuid not null references public.matrix_segments(id) on delete cascade,
  person_id uuid not null references public.matrix_people(id),
  score numeric(10,4),
  entered_at timestamptz not null default now(),
  expires_at timestamptz,
  primary key (segment_id, person_id)
);

create table if not exists public.matrix_campaigns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  name text not null,
  campaign_type text not null,
  status text not null default 'draft',
  segment_id uuid references public.matrix_segments(id),
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.matrix_campaign_memberships (
  campaign_id uuid not null references public.matrix_campaigns(id) on delete cascade,
  person_id uuid not null references public.matrix_people(id),
  status text not null default 'eligible',
  created_at timestamptz not null default now(),
  primary key (campaign_id, person_id)
);
