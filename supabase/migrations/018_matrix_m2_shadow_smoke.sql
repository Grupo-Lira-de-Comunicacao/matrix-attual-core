-- Matrix Attual Core
-- Migration 018: reversible production smoke for M2 shadow intelligence

begin;

do $m2_smoke$
declare
  v_tenant_id uuid;
  v_project_id uuid;
  v_profile_id uuid := gen_random_uuid();
  v_radio_event uuid := gen_random_uuid();
  v_tv_event uuid := gen_random_uuid();
  v_program_event uuid := gen_random_uuid();
  v_radio_score numeric(10,4);
  v_tv_score numeric(10,4);
  v_program_score numeric(10,4);
  v_events_score numeric(10,4);
  v_recommendation_id uuid;
  v_top_1 text;
  v_top_2 text;
  v_top_3 text;
  v_remaining_scores integer;
  v_active_shadow integer;
begin
  select t.id, p.id
  into v_tenant_id, v_project_id
  from public.matrix_tenants t
  join public.matrix_projects p on p.tenant_id = t.id
  where t.key = 'grupo-lira'
    and p.project_key = 'attualplay'
  limit 1;

  if v_tenant_id is null or v_project_id is null then
    raise exception 'M2 smoke failed: Grupo Lira / AttualPlay project not found';
  end if;

  insert into public.matrix_anonymous_profiles (
    id,
    tenant_id,
    project_id,
    anonymous_key_hash,
    first_seen_at,
    last_seen_at,
    expires_at
  ) values (
    v_profile_id,
    v_tenant_id,
    v_project_id,
    'm2-smoke-' || v_profile_id::text,
    now(),
    now(),
    now() + interval '1 hour'
  );

  insert into public.matrix_events (
    id,
    tenant_id,
    project_id,
    person_id,
    anonymous_profile_id,
    event_type,
    occurred_at,
    received_at,
    session_id,
    source,
    schema_version,
    consent_snapshot,
    properties,
    context,
    idempotency_key,
    processing_status
  ) values
  (
    v_radio_event,
    v_tenant_id,
    v_project_id,
    null,
    v_profile_id,
    'radio_stopped',
    now(),
    now(),
    'm2-smoke-session',
    'matrix-m2-production-smoke',
    1,
    '{"essential":true,"analytics":true,"adult_confirmed":true,"personalization":false,"marketing":false,"policy_version":"m2-smoke-v1"}'::jsonb,
    '{"station_key":"radio-attual-live","listen_seconds_bucket":"300s+"}'::jsonb,
    '{}'::jsonb,
    'm2-smoke-radio-' || v_radio_event::text,
    'pending'
  ),
  (
    v_tv_event,
    v_tenant_id,
    v_project_id,
    null,
    v_profile_id,
    'tv_stopped',
    now(),
    now(),
    'm2-smoke-session',
    'matrix-m2-production-smoke',
    1,
    '{"essential":true,"analytics":true,"adult_confirmed":true,"personalization":false,"marketing":false,"policy_version":"m2-smoke-v1"}'::jsonb,
    '{"channel_key":"tv-attual-live","watch_seconds_bucket":"121-300s"}'::jsonb,
    '{}'::jsonb,
    'm2-smoke-tv-' || v_tv_event::text,
    'pending'
  ),
  (
    v_program_event,
    v_tenant_id,
    v_project_id,
    null,
    v_profile_id,
    'page_viewed',
    now(),
    now(),
    'm2-smoke-session',
    'matrix-m2-production-smoke',
    1,
    '{"essential":true,"analytics":true,"adult_confirmed":true,"personalization":false,"marketing":false,"policy_version":"m2-smoke-v1"}'::jsonb,
    '{"path":"/programacao","page_type":"app_tab"}'::jsonb,
    '{}'::jsonb,
    'm2-smoke-program-' || v_program_event::text,
    'pending'
  );

  perform public.matrix_run_m2_shadow(now(), 10000);

  select max(score.score) filter (where topic.key = 'radio'),
         max(score.score) filter (where topic.key = 'tv-ao-vivo'),
         max(score.score) filter (where topic.key = 'programacao'),
         max(score.score) filter (where topic.key = 'eventos')
  into v_radio_score, v_tv_score, v_program_score, v_events_score
  from public.matrix_interest_scores score
  join public.matrix_topics topic on topic.id = score.topic_id
  where score.anonymous_profile_id = v_profile_id
    and score.engine_version = 'm2-shadow-rules-v1';

  if v_radio_score <> 2.5000
     or v_tv_score <> 1.5000
     or v_program_score <> 1.0000
     or v_events_score <> 0.2500 then
    raise exception 'M2 smoke failed: unexpected deterministic scores radio=%, tv=%, program=%, events=%',
      v_radio_score, v_tv_score, v_program_score, v_events_score;
  end if;

  select recommendation.id,
         recommendation.source_signals -> 0 ->> 'topic_key',
         recommendation.source_signals -> 1 ->> 'topic_key',
         recommendation.source_signals -> 2 ->> 'topic_key'
  into v_recommendation_id, v_top_1, v_top_2, v_top_3
  from public.matrix_recommendations recommendation
  where recommendation.anonymous_profile_id = v_profile_id
    and recommendation.recommendation_type = 'topic_affinity_shadow'
    and recommendation.engine_version = 'm2-shadow-rules-v1'
    and recommendation.status = 'shadow'
  order by recommendation.generated_at desc
  limit 1;

  if v_recommendation_id is null
     or v_top_1 <> 'radio'
     or v_top_2 <> 'tv-ao-vivo'
     or v_top_3 <> 'programacao' then
    raise exception 'M2 smoke failed: unexpected top-3 shadow recommendation %, %, %', v_top_1, v_top_2, v_top_3;
  end if;

  insert into public.matrix_event_invalidations (
    event_id,
    reason,
    actor_type,
    actor_id,
    created_at
  ) values
    (v_radio_event, 'matrix_m2_production_smoke_cleanup', 'system', 'matrix-m2-smoke', now()),
    (v_tv_event, 'matrix_m2_production_smoke_cleanup', 'system', 'matrix-m2-smoke', now()),
    (v_program_event, 'matrix_m2_production_smoke_cleanup', 'system', 'matrix-m2-smoke', now());

  perform public.matrix_run_m2_shadow(now(), 10000);

  select count(*)::integer
  into v_remaining_scores
  from public.matrix_interest_scores score
  where score.anonymous_profile_id = v_profile_id
    and score.engine_version = 'm2-shadow-rules-v1';

  select count(*)::integer
  into v_active_shadow
  from public.matrix_recommendations recommendation
  where recommendation.anonymous_profile_id = v_profile_id
    and recommendation.recommendation_type = 'topic_affinity_shadow'
    and recommendation.engine_version = 'm2-shadow-rules-v1'
    and recommendation.status = 'shadow';

  if v_remaining_scores <> 0 or v_active_shadow <> 0 then
    raise exception 'M2 smoke failed: invalidated events still influence engine scores=% active_shadow=%',
      v_remaining_scores, v_active_shadow;
  end if;

  -- Remove only synthetic fixtures. Production data remains untouched.
  delete from public.matrix_recommendation_items item
  using public.matrix_recommendations recommendation
  where item.recommendation_id = recommendation.id
    and recommendation.anonymous_profile_id = v_profile_id;

  delete from public.matrix_recommendations
  where anonymous_profile_id = v_profile_id;

  delete from public.matrix_interest_scores
  where anonymous_profile_id = v_profile_id;

  delete from public.matrix_m2_event_state
  where event_id in (v_radio_event, v_tv_event, v_program_event);

  delete from public.matrix_event_invalidations
  where event_id in (v_radio_event, v_tv_event, v_program_event);

  delete from public.matrix_events
  where id in (v_radio_event, v_tv_event, v_program_event);

  delete from public.matrix_anonymous_profiles
  where id = v_profile_id;

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
  ) values (
    v_tenant_id,
    v_project_id,
    'system',
    'matrix-m2-smoke',
    'm2.shadow.production_smoke',
    'matrix_intelligence',
    'ok',
    jsonb_build_object(
      'engine_version', 'm2-shadow-rules-v1',
      'radio_score_expected', 2.5,
      'tv_score_expected', 1.5,
      'programacao_score_expected', 1.0,
      'eventos_score_expected', 0.25,
      'top_3_expected', jsonb_build_array('radio','tv-ao-vivo','programacao'),
      'invalidation_verified', true,
      'synthetic_fixtures_removed', true,
      'personalization_exposed', false,
      'marketing_enabled', false
    ),
    now()
  );
end;
$m2_smoke$;

commit;
