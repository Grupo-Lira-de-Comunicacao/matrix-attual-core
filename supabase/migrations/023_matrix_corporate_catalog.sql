begin;

create table if not exists public.matrix_source_domains (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id) on delete cascade,
  domain_key text not null,
  name text not null,
  owner_system text not null,
  authority_scope text not null,
  description text,
  data_classes jsonb not null default '[]'::jsonb,
  source_reference text,
  status text not null default 'active' check (status in ('active','planned','retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, domain_key)
);

alter table public.matrix_source_domains enable row level security;
revoke all on public.matrix_source_domains from public, anon, authenticated;
grant select, insert, update on public.matrix_source_domains to service_role;

alter table public.matrix_entities
  add column if not exists slug text,
  add column if not exists code text,
  add column if not exists parent_entity_id uuid references public.matrix_entities(id) on delete set null,
  add column if not exists nucleus text,
  add column if not exists source_domain_id uuid references public.matrix_source_domains(id) on delete set null,
  add column if not exists responsible_ref text,
  add column if not exists canonical_url text,
  add column if not exists repository_ref text,
  add column if not exists short_description text,
  add column if not exists objective text,
  add column if not exists audience text,
  add column if not exists next_action text,
  add column if not exists history_notes text;

create unique index if not exists matrix_entities_tenant_slug_uidx on public.matrix_entities (tenant_id, slug);
create unique index if not exists matrix_entities_tenant_code_uidx on public.matrix_entities (tenant_id, code) where code is not null;
create index if not exists matrix_entities_parent_idx on public.matrix_entities (tenant_id, parent_entity_id, entity_type, status);
create index if not exists matrix_entities_source_domain_idx on public.matrix_entities (tenant_id, source_domain_id, entity_type);

comment on table public.matrix_source_domains is 'Source-of-truth registry by corporate domain; operational datasets remain in their owning systems.';
comment on column public.matrix_entities.slug is 'Stable catalog slug; UUID remains the technical primary key.';
comment on column public.matrix_entities.code is 'Optional human code such as BR-001; never a technical primary key.';

commit;
