create table if not exists public.matrix_consents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  person_id uuid references public.matrix_people(id),
  anonymous_profile_id uuid references public.matrix_anonymous_profiles(id),
  purpose text not null,
  channel text,
  status text not null check (status in ('granted','denied','withdrawn','not_required')),
  legal_basis text,
  source text not null,
  policy_version text,
  granted_at timestamptz,
  withdrawn_at timestamptz,
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (person_id is not null or anonymous_profile_id is not null)
);

create table if not exists public.matrix_consent_events (
  id uuid primary key default gen_random_uuid(),
  consent_id uuid not null references public.matrix_consents(id),
  action text not null,
  previous_status text,
  new_status text,
  occurred_at timestamptz not null default now(),
  actor_type text not null,
  actor_id text,
  correlation_id uuid,
  metadata jsonb not null default '{}'::jsonb
);
