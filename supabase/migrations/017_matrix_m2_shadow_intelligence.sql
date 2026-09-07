-- Matrix Attual Core
-- Migration 017: anonymous-first deterministic Interest + Recommendation engines in shadow mode

begin;

-- M2 must not manufacture a person identity for anonymous AttualPlay analytics.
alter table public.matrix_interest_scores
  alter column person_id drop not null;

alter table public.matrix_interest_scores
  add column if not exists project_id uuid references public.matrix_projects(id),
  add column if not exists anonymous_profile_id uuid references public.matrix_anonymous_profiles(id);

do $m2_subject_constraint$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'matrix_interest_scores_subject_check'
      and conrelid = 'public.matrix_interest_scores'::regclass
  ) then
    alter table public.matrix_interest_scores
      add constraint matrix_interest_scores_subject_check
      check (
        (person_id is not null and anonymous_profile_id is null)
        or (person_id is null and anonymous_profile_id is not null)
      ) not valid;
  end if;
end;
$m2_subject_constraint$;

alter table public.matrix_interest_scores
  validate constraint matrix_interest_scores_subject_check;

create unique index if not exists uq_matrix_interest_scores_anon_topic
  on public.matrix_interest_scores (tenant_id, anonymous_profile_id, topic_id)
  where anonymous_profile_id is not null;

create index if not exists idx_matrix_interest_scores_anon_rank
  on public.matrix_interest_scores (anonymous_profile_id, score desc, calculated_at desc)
  where anonymous_profile_id is not null;

-- Declarative, auditable signal rules. No model/LLM makes these decisions in M2.
create table if not exists public.matrix_signal_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  rule_key text not null,
  event_type text not null,
  property_key text,
  property_value text,
  topic_id uuid not null references public.matrix_topics(id),
  contribution numeric(10,4) not null check (contribution > 0),
  reason_code text not null,
  engine_version text not null,
  status text not null default 'active' check (status in ('active','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, rule_key)
);

-- Event-level idempotency per engine version. A future engine version can replay safely.
create table if not exists public.matrix_m2_event_state (
  event_id uuid not null references public.matrix_events(id) on delete cascade,
  engine_version text not null,
  signal_count integer not null default 0 check (signal_count >= 0),
  processed_at timestamptz not null default now(),
  primary key (event_id, engine_version)
);

alter table public.matrix_signal_rules enable row level security;
alter table public.matrix_m2_event_state enable row level security;

-- Add media/interaction topics that describe what AttualPlay can actually observe.
with tenant as (
  select id from public.matrix_tenants where key = 'grupo-lira'
)
insert into public.matrix_topics (tenant_id, key, label)
select tenant.id, seed.key, seed.label
from tenant
cross join (values
  ('tv-ao-vivo','TV ao vivo'),
  ('radio','Radio'),
  ('programacao','Programacao'),
  ('participacao','Participacao')
) as seed(key, label)
on conflict (tenant_id, key) do update
set label = excluded.label,
    status = 'active';

-- Seed deterministic AttualPlay rules. These infer format affinity only from observed actions;
-- they do not infer sensitive traits or identity.
with tenant as (
  select id from public.matrix_tenants where key = 'grupo-lira'
), project as (
  select p.id, p.tenant_id
  from public.matrix_projects p
  join tenant t on t.id = p.tenant_id
  where p.project_key = 'attualplay'
), rules(rule_key, event_type, property_key, property_value, topic_key, contribution, reason_code) as (
  values
    ('tv-start-format', 'tv_started', null, null, 'tv-ao-vivo', 1.0000, 'tv_started'),
    ('tv-start-broad', 'tv_started', null, null, 'audiovisual', 0.5000, 'tv_started_audiovisual'),
    ('tv-stop-0-30', 'tv_stopped', 'watch_seconds_bucket', '0-30s', 'tv-ao-vivo', 0.2500, 'tv_watch_0_30'),
    ('tv-stop-31-120', 'tv_stopped', 'watch_seconds_bucket', '31-120s', 'tv-ao-vivo', 0.7500, 'tv_watch_31_120'),
    ('tv-stop-121-300', 'tv_stopped', 'watch_seconds_bucket', '121-300s', 'tv-ao-vivo', 1.5000, 'tv_watch_121_300'),
    ('tv-stop-300-plus', 'tv_stopped', 'watch_seconds_bucket', '300s+', 'tv-ao-vivo', 2.5000, 'tv_watch_300_plus'),
    ('radio-start-format', 'radio_started', null, null, 'radio', 1.0000, 'radio_started'),
    ('radio-start-broad', 'radio_started', null, null, 'musica', 0.5000, 'radio_started_music'),
    ('radio-stop-0-30', 'radio_stopped', 'listen_seconds_bucket', '0-30s', 'radio', 0.2500, 'radio_listen_0_30'),
    ('radio-stop-31-120', 'radio_stopped', 'listen_seconds_bucket', '31-120s', 'radio', 0.7500, 'radio_listen_31_120'),
    ('radio-stop-121-300', 'radio_stopped', 'listen_seconds_bucket', '121-300s', 'radio', 1.5000, 'radio_listen_121_300'),
    ('radio-stop-300-plus', 'radio_stopped', 'listen_seconds_bucket', '300s+', 'radio', 2.5000, 'radio_listen_300_plus'),
    ('page-programacao', 'page_viewed', 'path', '/programacao', 'programacao', 1.0000, 'programacao_viewed'),
    ('page-programacao-events', 'page_viewed', 'path', '/programacao', 'eventos', 0.2500, 'programacao_events_affinity'),
    ('page-participacao', 'page_viewed', 'path', '/chat', 'participacao', 1.0000, 'participacao_viewed')
)
insert into public.matrix_signal_rules (
  tenant_id,
  project_id,
  rule_key,
  event_type,
  property_key,
  property_value,
  topic_id,
  contribution,
  reason_code,
  engine_version,
  status
)
select
  p.tenant_id,
  p.id,
  r.rule_key,
  r.event_type,
  r.property_key,
  r.property_value,
  t.id,
  r.contribution,
  r.reason_code,
  'm2-shadow-rules-v1',
  'active'
from project p
cross join rules r
join public.matrix_topics t
  on t.tenant_id = p.tenant_id
 and t.key = r.topic_key
on conflict (project_id, rule_key) do update
set event_type = excluded.event_type,
    property_key = excluded.property_key,
    property_value = excluded.property_value,
    topic_id = excluded.topic_id,
    contribution = excluded.contribution,
    reason_code = excluded.reason_code,
    engine_version = excluded.engine_version,
    status = 'active',
    updated_at = now();

create or replace function public.matrix_run_m2_shadow(
  p_now timestamptz default now(),
  p_event_limit integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $m2_engine$
declare
  v_engine constant text := 'm2-shadow-rules-v1';
  v_event_ids uuid[] := '{}'::uuid[];
  v_events_processed integer := 0;
  v_evidence_added integer := 0;
  v_invalidated_evidence_removed integer := 0;
  v_scores_active integer := 0;
  v_recommendations_generated integer := 0;
  v_existing_recommendation uuid;
  v_recommendation_id uuid;
  v_source_signals jsonb;
  v_top_confidence numeric(5,4);
  v_profile record;
begin
  if p_event_limit < 1 or p_event_limit > 10000 then
    raise exception 'p_event_limit must be between 1 and 10000';
  end if;

  -- An invalidated event must stop contributing on the next engine run.
  with removed as (
    delete from public.matrix_interest_evidence ie
    using public.matrix_events e
    where ie.event_id = e.id
      and exists (
        select 1
        from public.matrix_event_invalidations inv
        where inv.event_id = e.id
      )
    returning ie.id
  )
  select count(*)::integer
  into v_invalidated_evidence_removed
  from removed;

  -- Process only consented adult analytics events that were not handled by this engine version.
  select coalesce(array_agg(candidate.id), '{}'::uuid[])
  into v_event_ids
  from (
    select e.id
    from public.matrix_events e
    where e.anonymous_profile_id is not null
      and e.consent_snapshot ->> 'analytics' = 'true'
      and e.consent_snapshot ->> 'adult_confirmed' = 'true'
      and not exists (
        select 1
        from public.matrix_event_invalidations inv
        where inv.event_id = e.id
      )
      and not exists (
        select 1
        from public.matrix_m2_event_state state
        where state.event_id = e.id
          and state.engine_version = v_engine
      )
    order by e.received_at, e.id
    limit p_event_limit
  ) as candidate;

  v_events_processed := coalesce(cardinality(v_event_ids), 0);

  if v_events_processed > 0 then
    -- Create anonymous subject/topic score rows before attaching evidence.
    insert into public.matrix_interest_scores (
      tenant_id,
      project_id,
      person_id,
      anonymous_profile_id,
      topic_id,
      score,
      confidence,
      signal_count,
      engine_version,
      calculated_at
    )
    select distinct
      e.tenant_id,
      e.project_id,
      null,
      e.anonymous_profile_id,
      rule.topic_id,
      0,
      0,
      0,
      v_engine,
      p_now
    from public.matrix_events e
    join public.matrix_signal_rules rule
      on rule.project_id = e.project_id
     and rule.event_type = e.event_type
     and rule.engine_version = v_engine
     and rule.status = 'active'
     and (
       rule.property_key is null
       or e.properties ->> rule.property_key = rule.property_value
     )
    where e.id = any(v_event_ids)
      and not exists (
        select 1
        from public.matrix_interest_scores score
        where score.tenant_id = e.tenant_id
          and score.anonymous_profile_id = e.anonymous_profile_id
          and score.topic_id = rule.topic_id
      );

    with inserted as (
      insert into public.matrix_interest_evidence (
        interest_score_id,
        event_id,
        contribution,
        reason_code,
        created_at
      )
      select
        score.id,
        e.id,
        rule.contribution,
        rule.reason_code,
        p_now
      from public.matrix_events e
      join public.matrix_signal_rules rule
        on rule.project_id = e.project_id
       and rule.event_type = e.event_type
       and rule.engine_version = v_engine
       and rule.status = 'active'
       and (
         rule.property_key is null
         or e.properties ->> rule.property_key = rule.property_value
       )
      join public.matrix_interest_scores score
        on score.tenant_id = e.tenant_id
       and score.anonymous_profile_id = e.anonymous_profile_id
       and score.topic_id = rule.topic_id
      where e.id = any(v_event_ids)
      on conflict (interest_score_id, event_id, reason_code) do nothing
      returning id
    )
    select count(*)::integer
    into v_evidence_added
    from inserted;

    insert into public.matrix_m2_event_state (event_id, engine_version, signal_count, processed_at)
    select
      e.id,
      v_engine,
      count(rule.id)::integer,
      p_now
    from public.matrix_events e
    left join public.matrix_signal_rules rule
      on rule.project_id = e.project_id
     and rule.event_type = e.event_type
     and rule.engine_version = v_engine
     and rule.status = 'active'
     and (
       rule.property_key is null
       or e.properties ->> rule.property_key = rule.property_value
     )
    where e.id = any(v_event_ids)
    group by e.id
    on conflict (event_id, engine_version) do nothing;
  end if;

  -- Recompute deterministic scores from valid evidence. Retention bounds the evidence window to 90 days.
  update public.matrix_interest_scores score
  set score = aggregate.total_score,
      confidence = aggregate.confidence,
      signal_count = aggregate.signal_count,
      engine_version = v_engine,
      calculated_at = p_now
  from (
    select
      ie.interest_score_id,
      round(sum(ie.contribution), 4) as total_score,
      count(*)::integer as signal_count,
      least(
        0.9500::numeric,
        0.2000::numeric
          + least(0.6000::numeric, count(*)::numeric * 0.1000::numeric)
          + least(0.1500::numeric, sum(ie.contribution) * 0.0200::numeric)
      )::numeric(5,4) as confidence
    from public.matrix_interest_evidence ie
    join public.matrix_events e on e.id = ie.event_id
    where not exists (
      select 1
      from public.matrix_event_invalidations inv
      where inv.event_id = e.id
    )
    group by ie.interest_score_id
  ) aggregate
  where score.id = aggregate.interest_score_id
    and score.anonymous_profile_id is not null;

  -- Scores with no remaining valid evidence are disposable.
  delete from public.matrix_interest_scores score
  where score.anonymous_profile_id is not null
    and score.engine_version = v_engine
    and not exists (
      select 1
      from public.matrix_interest_evidence ie
      where ie.interest_score_id = score.id
    );

  select count(*)::integer
  into v_scores_active
  from public.matrix_interest_scores score
  where score.anonymous_profile_id is not null
    and score.engine_version = v_engine
    and score.signal_count > 0;

  -- If a profile lost every valid score, no shadow recommendation may remain active.
  update public.matrix_recommendations recommendation
  set status = 'superseded',
      expires_at = least(coalesce(recommendation.expires_at, p_now), p_now)
  where recommendation.recommendation_type = 'topic_affinity_shadow'
    and recommendation.engine_version = v_engine
    and recommendation.status = 'shadow'
    and recommendation.anonymous_profile_id is not null
    and not exists (
      select 1
      from public.matrix_interest_scores score
      where score.anonymous_profile_id = recommendation.anonymous_profile_id
        and score.engine_version = v_engine
        and score.signal_count > 0
    );

  -- Produce explainable top-3 topic recommendations without exposing them to AttualPlay.
  for v_profile in
    select distinct
      score.tenant_id,
      score.project_id,
      score.anonymous_profile_id
    from public.matrix_interest_scores score
    where score.anonymous_profile_id is not null
      and score.project_id is not null
      and score.engine_version = v_engine
      and score.signal_count > 0
  loop
    select
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'topic_key', ranked.topic_key,
            'topic_label', ranked.topic_label,
            'score', ranked.score,
            'confidence', ranked.confidence,
            'signal_count', ranked.signal_count,
            'engine_version', v_engine
          )
          order by ranked.score desc, ranked.topic_key
        ),
        '[]'::jsonb
      ),
      coalesce(max(ranked.confidence), 0)::numeric(5,4)
    into v_source_signals, v_top_confidence
    from (
      select
        topic.key as topic_key,
        topic.label as topic_label,
        score.score,
        score.confidence,
        score.signal_count
      from public.matrix_interest_scores score
      join public.matrix_topics topic on topic.id = score.topic_id
      where score.anonymous_profile_id = v_profile.anonymous_profile_id
        and score.engine_version = v_engine
        and score.signal_count > 0
      order by score.score desc, topic.key
      limit 3
    ) ranked;

    v_existing_recommendation := null;
    select recommendation.id
    into v_existing_recommendation
    from public.matrix_recommendations recommendation
    where recommendation.anonymous_profile_id = v_profile.anonymous_profile_id
      and recommendation.recommendation_type = 'topic_affinity_shadow'
      and recommendation.engine_version = v_engine
      and recommendation.status = 'shadow'
      and recommendation.expires_at > p_now
      and recommendation.source_signals = v_source_signals
    order by recommendation.generated_at desc
    limit 1;

    if v_existing_recommendation is null then
      update public.matrix_recommendations recommendation
      set status = 'superseded',
          expires_at = least(coalesce(recommendation.expires_at, p_now), p_now)
      where recommendation.anonymous_profile_id = v_profile.anonymous_profile_id
        and recommendation.recommendation_type = 'topic_affinity_shadow'
        and recommendation.engine_version = v_engine
        and recommendation.status = 'shadow';

      insert into public.matrix_recommendations (
        tenant_id,
        project_id,
        person_id,
        anonymous_profile_id,
        recommendation_type,
        engine_version,
        status,
        confidence,
        reason_code,
        reason_text,
        source_signals,
        generated_at,
        expires_at
      ) values (
        v_profile.tenant_id,
        v_profile.project_id,
        null,
        v_profile.anonymous_profile_id,
        'topic_affinity_shadow',
        v_engine,
        'shadow',
        v_top_confidence,
        'top_interest_topics_v1',
        'Topicos ordenados por evidencias comportamentais consentidas e regras deterministicas; resultado somente em modo sombra.',
        v_source_signals,
        p_now,
        p_now + interval '24 hours'
      )
      returning id into v_recommendation_id;

      insert into public.matrix_recommendation_items (
        recommendation_id,
        rank,
        object_type,
        object_id,
        score,
        reason_text,
        metadata
      )
      select
        v_recommendation_id,
        row_number() over (order by score.score desc, topic.key)::integer,
        'topic',
        topic.id,
        score.score,
        'Afinidade observada por sinais consentidos do AttualPlay.',
        jsonb_build_object(
          'topic_key', topic.key,
          'topic_label', topic.label,
          'confidence', score.confidence,
          'signal_count', score.signal_count,
          'shadow', true
        )
      from public.matrix_interest_scores score
      join public.matrix_topics topic on topic.id = score.topic_id
      where score.anonymous_profile_id = v_profile.anonymous_profile_id
        and score.engine_version = v_engine
        and score.signal_count > 0
      order by score.score desc, topic.key
      limit 3;

      v_recommendations_generated := v_recommendations_generated + 1;
    end if;
  end loop;

  insert into public.matrix_audit_log (
    tenant_id,
    project_id,
    actor_type,
    actor_id,
    action,
    target_type,
    result,
    metadata,
    created_at
  )
  select
    tenant.id,
    project.id,
    'system',
    v_engine,
    'm2.shadow.run',
    'matrix_intelligence',
    'ok',
    jsonb_build_object(
      'engine_version', v_engine,
      'shadow_mode', true,
      'events_processed', v_events_processed,
      'evidence_added', v_evidence_added,
      'invalidated_evidence_removed', v_invalidated_evidence_removed,
      'scores_active', v_scores_active,
      'recommendations_generated', v_recommendations_generated,
      'personalization_exposed', false,
      'marketing_enabled', false,
      'ran_at', p_now
    ),
    p_now
  from public.matrix_tenants tenant
  join public.matrix_projects project on project.tenant_id = tenant.id
  where tenant.key = 'grupo-lira'
    and project.project_key = 'attualplay'
  limit 1;

  return jsonb_build_object(
    'status', 'ok',
    'engine_version', v_engine,
    'shadow_mode', true,
    'events_processed', v_events_processed,
    'evidence_added', v_evidence_added,
    'invalidated_evidence_removed', v_invalidated_evidence_removed,
    'scores_active', v_scores_active,
    'recommendations_generated', v_recommendations_generated,
    'personalization_exposed', false,
    'marketing_enabled', false,
    'ran_at', p_now
  );
end;
$m2_engine$;

revoke all on function public.matrix_run_m2_shadow(timestamptz, integer) from public;
revoke all on function public.matrix_run_m2_shadow(timestamptz, integer) from anon;
revoke all on function public.matrix_run_m2_shadow(timestamptz, integer) from authenticated;
revoke all on function public.matrix_run_m2_shadow(timestamptz, integer) from service_role;

-- Re-create the named cron deterministically if this migration is replayed in a controlled environment.
do $m2_cron_cleanup$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'matrix-m2-shadow-v1'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
end;
$m2_cron_cleanup$;

select cron.schedule(
  'matrix-m2-shadow-v1',
  '*/10 * * * *',
  $cron$select public.matrix_run_m2_shadow();$cron$
);

-- Initial shadow run is deliberately inside the migration transaction: failures roll back M2 atomically.
select public.matrix_run_m2_shadow(now(), 2000);

-- Self-validation: fail closed if M2 is accidentally exposed or incompletely seeded.
do $m2_validate$
declare
  v_rule_count integer;
  v_cron_count integer;
  v_person_nullable text;
begin
  select is_nullable
  into v_person_nullable
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'matrix_interest_scores'
    and column_name = 'person_id';

  if v_person_nullable <> 'YES' then
    raise exception 'M2 validation failed: person_id must be nullable for anonymous-first scores';
  end if;

  select count(*)::integer
  into v_rule_count
  from public.matrix_signal_rules rule
  join public.matrix_projects project on project.id = rule.project_id
  where project.project_key = 'attualplay'
    and rule.engine_version = 'm2-shadow-rules-v1'
    and rule.status = 'active';

  if v_rule_count <> 15 then
    raise exception 'M2 validation failed: expected 15 active AttualPlay rules, got %', v_rule_count;
  end if;

  select count(*)::integer
  into v_cron_count
  from cron.job
  where jobname = 'matrix-m2-shadow-v1';

  if v_cron_count <> 1 then
    raise exception 'M2 validation failed: expected exactly one M2 cron job, got %', v_cron_count;
  end if;

  if has_function_privilege('anon', 'public.matrix_run_m2_shadow(timestamptz,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.matrix_run_m2_shadow(timestamptz,integer)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.matrix_run_m2_shadow(timestamptz,integer)', 'EXECUTE') then
    raise exception 'M2 validation failed: shadow engine execution is exposed to a client/service role';
  end if;
end;
$m2_validate$;

commit;
