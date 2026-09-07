-- Matrix Attual Core
-- Migration 021: M4 explicit identity bridge, server-side consent and governed downstream eligibility

begin;

alter table public.matrix_identity_links
  add column if not exists project_id uuid references public.matrix_projects(id),
  add column if not exists link_status text not null default 'active',
  add column if not exists external_system text,
  add column if not exists external_ref_hash text,
  add column if not exists verified_at timestamptz,
  add column if not exists revoked_at timestamptz,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.matrix_identity_links link
set project_id = profile.project_id
from public.matrix_anonymous_profiles profile
where link.anonymous_profile_id = profile.id
  and link.project_id is null;

alter table public.matrix_identity_links
  drop constraint if exists matrix_identity_links_link_status_check;
alter table public.matrix_identity_links
  add constraint matrix_identity_links_link_status_check
  check (link_status in ('active','revoked','suppressed'));

create index if not exists idx_matrix_identity_links_person_active
  on public.matrix_identity_links (person_id, project_id, created_at desc)
  where link_status = 'active';

create unique index if not exists uq_matrix_identity_links_external_active
  on public.matrix_identity_links (tenant_id, project_id, external_system, external_ref_hash, person_id)
  where link_status = 'active' and external_system is not null and external_ref_hash is not null;

create table if not exists public.matrix_identity_bridge_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  person_id uuid not null references public.matrix_people(id),
  identity_id uuid not null references public.matrix_identities(id),
  external_system text not null check (external_system in ('attual_one')),
  external_ref_hash text not null,
  bridge_code_hash text not null unique,
  status text not null default 'pending' check (status in ('pending','consumed','revoked','expired')),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  correlation_id uuid
);

create index if not exists idx_matrix_bridge_pending
  on public.matrix_identity_bridge_tokens (project_id, status, expires_at)
  where status = 'pending';

create table if not exists public.matrix_person_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  person_id uuid not null references public.matrix_people(id),
  anonymous_profile_id uuid references public.matrix_anonymous_profiles(id),
  bridge_id uuid references public.matrix_identity_bridge_tokens(id),
  token_hash text not null unique,
  status text not null default 'active' check (status in ('active','revoked','expired')),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  correlation_id uuid
);

create index if not exists idx_matrix_person_sessions_active
  on public.matrix_person_sessions (person_id, project_id, expires_at desc)
  where status = 'active';

create table if not exists public.matrix_m4_context_promotions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  person_id uuid not null references public.matrix_people(id),
  anonymous_profile_id uuid not null references public.matrix_anonymous_profiles(id),
  source_recommendation_id uuid not null references public.matrix_recommendations(id) on delete cascade,
  promoted_recommendation_id uuid not null references public.matrix_recommendations(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (source_recommendation_id, person_id)
);

create index if not exists idx_matrix_m4_promotions_person
  on public.matrix_m4_context_promotions (person_id, created_at desc);

alter table public.matrix_identity_bridge_tokens enable row level security;
alter table public.matrix_person_sessions enable row level security;
alter table public.matrix_m4_context_promotions enable row level security;

revoke all on table public.matrix_identity_bridge_tokens from public, anon, authenticated;
revoke all on table public.matrix_person_sessions from public, anon, authenticated;
revoke all on table public.matrix_m4_context_promotions from public, anon, authenticated;

grant select, insert, update on table public.matrix_identity_bridge_tokens to service_role;
grant select, insert, update on table public.matrix_person_sessions to service_role;
grant select, insert on table public.matrix_m4_context_promotions to service_role;

grant select, insert, update on table public.matrix_people to service_role;
grant select, insert, update on table public.matrix_identities to service_role;
grant select, insert, update on table public.matrix_identity_links to service_role;
grant select, insert on table public.matrix_consents to service_role;
grant select, insert on table public.matrix_consent_events to service_role;
grant select, insert, update on table public.matrix_recommendations to service_role;
grant select, insert, update on table public.matrix_m3_decisions to service_role;

create index if not exists idx_matrix_consents_person_purpose_latest
  on public.matrix_consents (person_id, purpose, created_at desc)
  where person_id is not null;

create or replace function public.matrix_current_person_consent(
  p_person_id uuid,
  p_purpose text,
  p_now timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $consent$
  select coalesce((
    select c.status = 'granted'
      and coalesce((c.metadata ->> 'adult_confirmed')::boolean, false)
      and (c.expires_at is null or c.expires_at > p_now)
    from public.matrix_consents c
    where c.person_id = p_person_id
      and c.purpose = p_purpose
    order by c.created_at desc, c.id desc
    limit 1
  ), false);
$consent$;

revoke all on function public.matrix_current_person_consent(uuid,text,timestamptz)
  from public, anon, authenticated;
grant execute on function public.matrix_current_person_consent(uuid,text,timestamptz)
  to service_role;

create or replace function public.matrix_run_m4_control(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $m4$
declare
  v_source record;
  v_promoted_id uuid;
  v_promotions integer := 0;
  v_pending integer := 0;
  v_suppressed integer := 0;
begin
  update public.matrix_identity_bridge_tokens
  set status = 'expired'
  where status = 'pending' and expires_at <= p_now;

  update public.matrix_person_sessions
  set status = 'expired'
  where status = 'active' and expires_at <= p_now;

  update public.matrix_recommendations r
  set status = 'superseded',
      expires_at = least(coalesce(r.expires_at, p_now), p_now)
  where r.engine_version = 'm4-identity-bridge-v1'
    and r.status = 'shadow'
    and r.person_id is not null
    and (
      not public.matrix_current_person_consent(r.person_id, 'analytics', p_now)
      or not public.matrix_current_person_consent(r.person_id, 'personalization', p_now)
      or not exists (
        select 1
        from public.matrix_identity_links link
        where link.person_id = r.person_id
          and link.project_id = r.project_id
          and link.link_status = 'active'
          and link.external_system = 'attual_one'
      )
    );

  update public.matrix_m3_decisions d
  set decision_status = 'superseded'
  from public.matrix_recommendations r
  where r.id = d.recommendation_id
    and r.engine_version = 'm4-identity-bridge-v1'
    and r.status <> 'shadow'
    and d.decision_status = 'eligible';

  for v_source in
    select
      d.tenant_id,
      d.project_id,
      d.policy_version,
      d.top_topic_key,
      d.top_score,
      d.top_confidence,
      d.top_signal_count,
      d.expires_at as decision_expires_at,
      r.id as source_recommendation_id,
      r.anonymous_profile_id,
      r.confidence,
      r.reason_text,
      r.source_signals,
      r.expires_at as recommendation_expires_at,
      link.person_id
    from public.matrix_m3_decisions d
    join public.matrix_recommendations r on r.id = d.recommendation_id
    join public.matrix_identity_links link
      on link.anonymous_profile_id = r.anonymous_profile_id
     and link.project_id = r.project_id
     and link.link_status = 'active'
     and link.external_system = 'attual_one'
    where d.decision_status = 'eligible'
      and d.expires_at > p_now
      and r.status = 'shadow'
      and r.anonymous_profile_id is not null
      and public.matrix_current_person_consent(link.person_id, 'analytics', p_now)
      and public.matrix_current_person_consent(link.person_id, 'personalization', p_now)
      and not exists (
        select 1
        from public.matrix_m4_context_promotions promotion
        where promotion.source_recommendation_id = r.id
          and promotion.person_id = link.person_id
      )
  loop
    insert into public.matrix_recommendations (
      tenant_id, project_id, person_id, anonymous_profile_id,
      recommendation_type, engine_version, status, confidence,
      reason_code, reason_text, source_signals, generated_at, expires_at
    ) values (
      v_source.tenant_id,
      v_source.project_id,
      v_source.person_id,
      null,
      'topic_affinity_shadow',
      'm4-identity-bridge-v1',
      'shadow',
      v_source.confidence,
      'm4_explicit_identity_promotion',
      v_source.reason_text,
      v_source.source_signals,
      p_now,
      least(coalesce(v_source.recommendation_expires_at, p_now + interval '24 hours'), p_now + interval '24 hours')
    ) returning id into v_promoted_id;

    insert into public.matrix_m4_context_promotions (
      tenant_id, project_id, person_id, anonymous_profile_id,
      source_recommendation_id, promoted_recommendation_id, created_at
    ) values (
      v_source.tenant_id,
      v_source.project_id,
      v_source.person_id,
      v_source.anonymous_profile_id,
      v_source.source_recommendation_id,
      v_promoted_id,
      p_now
    );

    insert into public.matrix_m3_decisions (
      tenant_id, project_id, recommendation_id, person_id, anonymous_profile_id,
      policy_version, decision_status, top_topic_key, top_score, top_confidence,
      top_signal_count, reason_code, evaluated_at, expires_at
    ) values (
      v_source.tenant_id,
      v_source.project_id,
      v_promoted_id,
      v_source.person_id,
      null,
      v_source.policy_version,
      'eligible',
      v_source.top_topic_key,
      v_source.top_score,
      v_source.top_confidence,
      v_source.top_signal_count,
      'm4_explicit_identity_quality_inherited',
      p_now,
      least(v_source.decision_expires_at, p_now + interval '24 hours')
    );

    v_promotions := v_promotions + 1;
  end loop;

  with suppressed as (
    update public.matrix_m3_action_outbox outbox
    set status = 'suppressed', updated_at = p_now
    where outbox.destination = 'attual_one'
      and outbox.status in ('pending','failed','processing')
      and (
        not public.matrix_current_person_consent(outbox.person_id, 'analytics', p_now)
        or not public.matrix_current_person_consent(outbox.person_id, 'personalization', p_now)
        or not exists (
          select 1 from public.matrix_identity_links link
          where link.person_id = outbox.person_id
            and link.project_id = outbox.project_id
            and link.link_status = 'active'
            and link.external_system = 'attual_one'
        )
      )
    returning outbox.id
  ) select count(*)::integer into v_suppressed from suppressed;

  insert into public.matrix_m3_action_outbox (
    tenant_id, project_id, decision_id, person_id, destination, action_type,
    idempotency_key, payload, status, attempts, available_at, expires_at, created_at, updated_at
  )
  select
    d.tenant_id,
    d.project_id,
    d.id,
    d.person_id,
    'attual_one',
    'qualified_interest_signal',
    'm4:' || d.id::text || ':attual_one',
    jsonb_build_object(
      'signal_key', 'm4:' || d.id::text || ':attual_one',
      'matrix_person_id', d.person_id,
      'topic_key', d.top_topic_key,
      'score', d.top_score,
      'confidence', d.top_confidence,
      'signal_count', d.top_signal_count,
      'policy_version', d.policy_version,
      'purpose', 'personalization',
      'marketing_allowed', false,
      'external_action_allowed', false,
      'source_system', 'matrix-attual',
      'target_system', 'attual-one',
      'occurred_at', p_now
    ),
    'pending',
    0,
    p_now,
    least(d.expires_at, p_now + interval '7 days'),
    p_now,
    p_now
  from public.matrix_m3_decisions d
  join public.matrix_recommendations r on r.id = d.recommendation_id
  where d.person_id is not null
    and d.decision_status = 'eligible'
    and d.expires_at > p_now
    and r.engine_version = 'm4-identity-bridge-v1'
    and r.status = 'shadow'
    and public.matrix_current_person_consent(d.person_id, 'analytics', p_now)
    and public.matrix_current_person_consent(d.person_id, 'personalization', p_now)
    and exists (
      select 1 from public.matrix_identity_links link
      where link.person_id = d.person_id
        and link.project_id = d.project_id
        and link.link_status = 'active'
        and link.external_system = 'attual_one'
    )
  on conflict (idempotency_key) do update
  set payload = excluded.payload,
      available_at = excluded.available_at,
      expires_at = excluded.expires_at,
      updated_at = p_now,
      status = case
        when public.matrix_m3_action_outbox.status = 'delivered' then 'delivered'
        else 'pending'
      end;

  get diagnostics v_pending = row_count;

  update public.matrix_m3_action_outbox
  set status = 'suppressed', updated_at = p_now
  where destination = 'n8n'
    and status <> 'delivered';

  insert into public.matrix_audit_log (
    actor_type, actor_id, action, target_type, result, metadata, created_at
  ) values (
    'system', 'matrix-m4-control', 'm4.control.run', 'matrix_identity_downstream', 'ok',
    jsonb_build_object(
      'engine_version', 'm4-identity-bridge-v1',
      'promotions_created', v_promotions,
      'attual_one_rows_touched', v_pending,
      'rows_suppressed_after_withdrawal_or_unlink', v_suppressed,
      'marketing_enabled', false,
      'n8n_external_actions_enabled', false,
      'hidden_identity_stitching', false
    ),
    p_now
  );

  return jsonb_build_object(
    'status', 'ok',
    'engine_version', 'm4-identity-bridge-v1',
    'promotions_created', v_promotions,
    'attual_one_rows_touched', v_pending,
    'rows_suppressed', v_suppressed,
    'marketing_enabled', false,
    'n8n_external_actions_enabled', false
  );
end;
$m4$;

revoke all on function public.matrix_run_m4_control(timestamptz)
  from public, anon, authenticated, service_role;

create or replace view public.matrix_m4_observability_current as
with projects as (
  select id as project_id from public.matrix_projects where project_key = 'attualplay'
), current_links as (
  select project_id, count(*)::integer as active_identity_links
  from public.matrix_identity_links
  where link_status = 'active' and external_system = 'attual_one'
  group by project_id
), current_sessions as (
  select project_id, count(*)::integer as active_person_sessions
  from public.matrix_person_sessions
  where status = 'active' and expires_at > now()
  group by project_id
), outbox as (
  select project_id,
    count(*) filter (where destination='attual_one' and status='pending')::integer as attual_one_pending,
    count(*) filter (where destination='attual_one' and status='delivered')::integer as attual_one_delivered,
    count(*) filter (where destination='n8n' and status in ('pending','processing'))::integer as n8n_executable_rows
  from public.matrix_m3_action_outbox
  group by project_id
)
select
  p.project_id,
  coalesce(l.active_identity_links,0) as active_identity_links,
  coalesce(s.active_person_sessions,0) as active_person_sessions,
  coalesce(o.attual_one_pending,0) as attual_one_pending,
  coalesce(o.attual_one_delivered,0) as attual_one_delivered,
  coalesce(o.n8n_executable_rows,0) as n8n_executable_rows,
  false as marketing_enabled,
  now() as observed_at
from projects p
left join current_links l using (project_id)
left join current_sessions s using (project_id)
left join outbox o using (project_id);

revoke all on public.matrix_m4_observability_current from public, anon, authenticated;
grant select on public.matrix_m4_observability_current to service_role;

do $cron$
declare
  v_job_id bigint;
begin
  for v_job_id in select jobid from cron.job where jobname = 'matrix-m4-control-v1' loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'matrix-m4-control-v1',
    '4,14,24,34,44,54 * * * *',
    $job$select public.matrix_run_m4_control(now());$job$
  );
end;
$cron$;

select public.matrix_run_m4_control(now());

commit;
