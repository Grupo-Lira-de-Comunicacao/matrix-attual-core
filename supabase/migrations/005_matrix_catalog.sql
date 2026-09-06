create table if not exists public.matrix_entities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid references public.matrix_projects(id),
  entity_type text not null,
  external_key text,
  name text not null,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.matrix_topics (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  key text not null,
  label text not null,
  parent_topic_id uuid references public.matrix_topics(id),
  status text not null default 'active',
  created_at timestamptz not null default now(),
  unique (tenant_id, key)
);

create table if not exists public.matrix_content (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  external_key text not null,
  content_type text not null,
  title text not null,
  description text,
  published_at timestamptz,
  city text,
  state text,
  language text not null default 'pt-BR',
  lifecycle text not null default 'current' check (lifecycle in ('breaking','current','evergreen')),
  commercial boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, external_key)
);

create table if not exists public.matrix_content_topics (
  content_id uuid not null references public.matrix_content(id) on delete cascade,
  topic_id uuid not null references public.matrix_topics(id),
  relevance numeric(5,4) not null default 1.0 check (relevance >= 0 and relevance <= 1),
  source text not null default 'manual',
  created_at timestamptz not null default now(),
  primary key (content_id, topic_id)
);
