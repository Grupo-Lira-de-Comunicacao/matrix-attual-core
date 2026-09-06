create table if not exists public.matrix_people (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  status text not null default 'active' check (status in ('active','merged','deleted','blocked')),
  display_name text,
  locale text not null default 'pt-BR',
  timezone text not null default 'America/Sao_Paulo',
  merged_into_person_id uuid references public.matrix_people(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.matrix_identities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  person_id uuid not null references public.matrix_people(id),
  identity_type text not null,
  normalized_hash text not null,
  encrypted_value text,
  verified boolean not null default false,
  source_project_id uuid references public.matrix_projects(id),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  unique (tenant_id, identity_type, normalized_hash)
);

create table if not exists public.matrix_anonymous_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  anonymous_key_hash text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz,
  unique (tenant_id, project_id, anonymous_key_hash)
);

create table if not exists public.matrix_identity_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  anonymous_profile_id uuid not null references public.matrix_anonymous_profiles(id),
  person_id uuid not null references public.matrix_people(id),
  link_reason text not null,
  confidence numeric(5,4) not null default 1.0 check (confidence >= 0 and confidence <= 1),
  created_at timestamptz not null default now(),
  unique (anonymous_profile_id, person_id)
);
