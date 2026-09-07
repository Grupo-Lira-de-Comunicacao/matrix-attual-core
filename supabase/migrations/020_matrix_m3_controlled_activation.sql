-- Matrix Attual Core
-- Migration 020: M3 controlled activation, observability and downstream safety gates

begin;

create table if not exists public.matrix_m3_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  policy_version text not null,
  min_score numeric(10,4) not null default 1.5000 check (min_score >= 0),
  min_confidence numeric(5,4) not null default 0.3500 check (min_confidence between 0 and 1),
  min_signal_count integer not null default 2 check (min_signal_count > 0),
  max_recommendation_age_hours integer not null default 24 check (max_recommendation_age_hours between 1 and 168),
  personalization_requires_opt_in boolean not null default true,
  downstream_requires_identified_person boolean not null default true,
  marketing_enabled boolean not null default false,
  n8n_external_actions_enabled boolean not null default false,
  status text not null default 'active' check (status in ('active','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, policy_version)
);

create table if not exists public.matrix_m3_decisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  recommendation_id uuid not null references public.matrix_recommendations(id) on delete cascade,
  person_id uuid references public.matrix_people(id),
  anonymous_profile_id uuid references public.matrix_anonymous_profiles(id) on delete cascade,
  policy_version text not null,
  decision_status text not null check (decision_status in ('eligible','insufficient','expired','superseded')),
  top_topic_key text,
  top_score numeric(10,4),
  top_confidence numeric(5,4),
  top_signal_count integer,
  reason_code text not null,
  evaluated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  check ((person_id is not null and anonymous_profile_id is null) or (person_id is null and anonymous_profile_id is not null)),
  unique (recommendation_id, policy_version)
);

create index if not exists idx_matrix_m3_decisions_anon
  on public.matrix_m3_decisions (anonymous_profile_id, decision_status, evaluated_at desc)
  where anonymous_profile_id is not null;

create index if not exists idx_matrix_m3_decisions_person
  on public.matrix_m3_decisions (person_id, decision_status, evaluated_at desc)
  where person_id is not null;

create table if not exists public.matrix_m3_quality_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  window_start timestamptz not null,
  window_end timestamptz not null,
  consented_events integer not null default 0,
  personalization_opt_in_events integer not null default 0,
  active_anonymous_profiles integer not null default 0,
  active_interest_scores integer not null default 0,
  shadow_recommendations integer not null default 0,
  eligible_decisions integer not null default 0,
  recommendation_shown integer not null default 0,
  recommendation_clicked integer not null default 0,
  invalidated_events integer not null default 0,
  dlq_pending integer not null default 0,
  generated_at timestamptz not null default now()
);

create index if not exists idx_matrix_m3_quality_project_time
  on public.matrix_m3_quality_snapshots (project_id, generated_at desc);

create table if not exists public.matrix_m3_action_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  decision_id uuid not null references public.matrix_m3_decisions(id) on delete cascade,
  person_id uuid not null references public.matrix_people(id),
  destination text not null check (destination in ('attual_one','n8n')),
  action_type text not null check (action_type in ('qualified_interest_signal')),
  idempotency_key text not null unique,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','processing','delivered','failed','suppressed')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_matrix_m3_outbox_delivery
  on public.matrix_m3_action_outbox (destination, status, available_at)
  where status in ('pending','failed');

alter table public.matrix_m3_policies enable row level security;
alter table public.matrix_m3_decisions enable row level security;
alter table public.matrix_m3_quality_snapshots enable row level security;
alter table public.matrix_m3_action_outbox enable row level security;

revoke all on table public.matrix_m3_policies from public, anon, authenticated;
revoke all on table public.matrix_m3_decisions from public, anon, authenticated;
revoke all on table public.matrix_m3_quality_snapshots from public, anon, authenticated;
revoke all on table public.matrix_m3_action_outbox from public, anon, authenticated;

grant select on table public.matrix_m3_policies to service_role;
grant select on table public.matrix_m3_decisions to service_role;
grant select on table public.matrix_m3_quality_snapshots to service_role;
grant select, insert, update on table public.matrix_m3_action_outbox to service_role;

with tenant as (
  select id from public.matrix_tenants where key = 'grupo-lira'
), project as (
  select p.id, p.tenant_id
  from public.matrix_projects p
  join tenant t on t.id = p.tenant_id
  where p.project_key = 'attualplay'
)
insert into public.matrix_m3_policies (
  tenant_id, project_id, policy_version, min_score, min_confidence, min_signal_count,
  max_recommendation_age_hours, personalization_requires_opt_in,
  downstream_requires_identified_person, marketing_enabled, n8n_external_actions_enabled, status
)
select
  p.tenant_id, p.id, 'm3-policy-v1', 1.5000, 0.3500, 2, 24,
  true, true, false, false, 'active'
from project p
on conflict (project_id, policy_version) do update
set min_score = excluded.min_score,
    min_confidence = excluded.min_confidence,
    min_signal_count = excluded.min_signal_count,
    max_recommendation_age_hours = excluded.max_recommendation_age_hours,
    personalization_requires_opt_in = true,
    downstream_requires_identified_person = true,
    marketing_enabled = false,
    n8n_external_actions_enabled = false,
    status = 'active',
    updated_at = now();

create or replace function public.matrix_run_m3_control(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $m3$
declare
  v_policy record;
  v_evaluated integer := 0;
  v_eligible integer := 0;
  v_snapshots integer := 0;
  v_outbox integer := 0;
begin
  update public.matrix_m3_decisions
  set decision_status = 'expired'
  where decision_status = 'eligible'
    and expires_at <= p_now;

  for v_policy in
    select *
    from public.matrix_m3_policies
    where status = 'active'
  loop
    insert into public.matrix_m3_decisions (
      tenant_id, project_id, recommendation_id, person_id, anonymous_profile_id,
      policy_version, decision_status, top_topic_key, top_score, top_confidence,
      top_signal_count, reason_code, evaluated_at, expires_at
    )
    select
      r.tenant_id,
      r.project_id,
      r.id,
      r.person_id,
      r.anonymous_profile_id,
      v_policy.policy_version,
      case
        when r.generated_at < p_now - make_interval(hours => v_policy.max_recommendation_age_hours) then 'expired'
        when coalesce((r.source_signals -> 0 ->> 'score')::numeric,0) >= v_policy.min_score
         and coalesce((r.source_signals -> 0 ->> 'confidence')::numeric,0) >= v_policy.min_confidence
         and coalesce((r.source_signals -> 0 ->> 'signal_count')::integer,0) >= v_policy.min_signal_count
          then 'eligible'
        else 'insufficient'
      end,
      r.source_signals -> 0 ->> 'topic_key',
      coalesce((r.source_signals -> 0 ->> 'score')::numeric,0),
      coalesce((r.source_signals -> 0 ->> 'confidence')::numeric,0),
      coalesce((r.source_signals -> 0 ->> 'signal_count')::integer,0),
      case
        when coalesce((r.source_signals -> 0 ->> 'score')::numeric,0) >= v_policy.min_score
         and coalesce((r.source_signals -> 0 ->> 'confidence')::numeric,0) >= v_policy.min_confidence
         and coalesce((r.source_signals -> 0 ->> 'signal_count')::integer,0) >= v_policy.min_signal_count
          then 'm3_quality_threshold_met'
        else 'm3_quality_threshold_not_met'
      end,
      p_now,
      least(coalesce(r.expires_at, p_now + interval '24 hours'), p_now + make_interval(hours => v_policy.max_recommendation_age_hours))
    from public.matrix_recommendations r
    where r.project_id = v_policy.project_id
      and r.recommendation_type = 'topic_affinity_shadow'
      and r.engine_version = 'm2-shadow-rules-v1'
      and r.status = 'shadow'
      and r.expires_at > p_now
      and not exists (
        select 1 from public.matrix_m3_decisions d
        where d.recommendation_id = r.id
          and d.policy_version = v_policy.policy_version
      );

    get diagnostics v_evaluated = row_count;

    select count(*)::integer
    into v_eligible
    from public.matrix_m3_decisions d
    where d.project_id = v_policy.project_id
      and d.policy_version = v_policy.policy_version
      and d.decision_status = 'eligible'
      and d.expires_at > p_now;

    insert into public.matrix_m3_quality_snapshots (
      tenant_id, project_id, window_start, window_end,
      consented_events, personalization_opt_in_events, active_anonymous_profiles,
      active_interest_scores, shadow_recommendations, eligible_decisions,
      recommendation_shown, recommendation_clicked, invalidated_events, dlq_pending, generated_at
    )
    select
      v_policy.tenant_id,
      v_policy.project_id,
      p_now - interval '24 hours',
      p_now,
      (select count(*)::integer from public.matrix_events e where e.project_id=v_policy.project_id and e.received_at >= p_now - interval '24 hours' and e.consent_snapshot ->> 'analytics'='true'),
      (select count(*)::integer from public.matrix_events e where e.project_id=v_policy.project_id and e.received_at >= p_now - interval '24 hours' and e.consent_snapshot ->> 'personalization'='true'),
      (select count(*)::integer from public.matrix_anonymous_profiles a where a.project_id=v_policy.project_id and a.expires_at > p_now),
      (select count(*)::integer from public.matrix_interest_scores s where s.project_id=v_policy.project_id and s.engine_version='m2-shadow-rules-v1' and s.signal_count > 0),
      (select count(*)::integer from public.matrix_recommendations r where r.project_id=v_policy.project_id and r.recommendation_type='topic_affinity_shadow' and r.status='shadow' and r.expires_at > p_now),
      v_eligible,
      (select count(*)::integer from public.matrix_events e where e.project_id=v_policy.project_id and e.received_at >= p_now - interval '24 hours' and e.event_type='recommendation_shown'),
      (select count(*)::integer from public.matrix_events e where e.project_id=v_policy.project_id and e.received_at >= p_now - interval '24 hours' and e.event_type='recommendation_clicked'),
      (select count(*)::integer from public.matrix_event_invalidations i join public.matrix_events e on e.id=i.event_id where e.project_id=v_policy.project_id and i.created_at >= p_now - interval '24 hours'),
      (select count(*)::integer from public.matrix_dead_letter_events q left join public.matrix_events e on e.id=q.original_event_id where q.resolved_at is null and (e.project_id=v_policy.project_id or q.original_event_id is null)),
      p_now;

    v_snapshots := v_snapshots + 1;

    if not v_policy.marketing_enabled and not v_policy.n8n_external_actions_enabled then
      insert into public.matrix_m3_action_outbox (
        tenant_id, project_id, decision_id, person_id, destination, action_type,
        idempotency_key, payload, status, available_at, expires_at
      )
      select
        d.tenant_id,
        d.project_id,
        d.id,
        d.person_id,
        destination.value,
        'qualified_interest_signal',
        'm3:' || d.id::text || ':' || destination.value,
        jsonb_build_object(
          'matrix_person_id', d.person_id,
          'topic_key', d.top_topic_key,
          'score', d.top_score,
          'confidence', d.top_confidence,
          'signal_count', d.top_signal_count,
          'policy_version', d.policy_version,
          'marketing_allowed', false,
          'external_action_allowed', false
        ),
        'suppressed',
        p_now,
        p_now + interval '7 days'
      from public.matrix_m3_decisions d
      cross join (values ('attual_one'),('n8n')) as destination(value)
      where d.project_id = v_policy.project_id
        and d.policy_version = v_policy.policy_version
        and d.decision_status = 'eligible'
        and d.person_id is not null
        and not exists (
          select 1 from public.matrix_m3_action_outbox o
          where o.idempotency_key = 'm3:' || d.id::text || ':' || destination.value
        );
      get diagnostics v_outbox = row_count;
    end if;
  end loop;

  delete from public.matrix_m3_quality_snapshots where generated_at < p_now - interval '365 days';
  update public.matrix_m3_action_outbox set status='suppressed', updated_at=p_now where status in ('pending','failed') and expires_at <= p_now;

  insert into public.matrix_audit_log (
    actor_type, actor_id, action, target_type, result, metadata, created_at
  ) values (
    'system', 'matrix-m3-control', 'm3.control.run', 'matrix_intelligence', 'ok',
    jsonb_build_object(
      'policy_version','m3-policy-v1',
      'evaluated_new',v_evaluated,
      'eligible_active',v_eligible,
      'quality_snapshots_written',v_snapshots,
      'downstream_rows_suppressed',v_outbox,
      'personalization_requires_opt_in',true,
      'marketing_enabled',false,
      'n8n_external_actions_enabled',false
    ),
    p_now
  );

  return jsonb_build_object(
    'status','ok',
    'policy_version','m3-policy-v1',
    'eligible_active',v_eligible,
    'quality_snapshots_written',v_snapshots,
    'personalization_requires_opt_in',true,
    'marketing_enabled',false,
    'n8n_external_actions_enabled',false
  );
end;
$m3$;

revoke all on function public.matrix_run_m3_control(timestamptz) from public, anon, authenticated, service_role;

create or replace view public.matrix_m3_observability_current as
select distinct on (q.project_id)
  q.project_id,
  q.window_start,
  q.window_end,
  q.consented_events,
  q.personalization_opt_in_events,
  q.active_anonymous_profiles,
  q.active_interest_scores,
  q.shadow_recommendations,
  q.eligible_decisions,
  q.recommendation_shown,
  q.recommendation_clicked,
  case when q.recommendation_shown > 0 then round(q.recommendation_clicked::numeric / q.recommendation_shown::numeric, 4) else 0 end as click_through_rate,
  q.invalidated_events,
  q.dlq_pending,
  q.generated_at
from public.matrix_m3_quality_snapshots q
order by q.project_id, q.generated_at desc;

revoke all on public.matrix_m3_observability_current from public, anon, authenticated;
grant select on public.matrix_m3_observability_current to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname = 'matrix-m3-control-v1';

select cron.schedule(
  'matrix-m3-control-v1',
  '3,13,23,33,43,53 * * * *',
  $cron$select public.matrix_run_m3_control(now());$cron$
);

select public.matrix_run_m3_control(now());

commit;
