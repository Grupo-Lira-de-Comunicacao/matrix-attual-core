-- Matrix Attual Core
-- Migration 016: bounded analytics retention and scheduled cleanup

begin;

create extension if not exists pg_cron;

create index if not exists idx_matrix_events_retention
  on public.matrix_events (received_at);

create index if not exists idx_matrix_anonymous_profiles_retention
  on public.matrix_anonymous_profiles (last_seen_at);

update public.matrix_anonymous_profiles
set expires_at = last_seen_at + interval '90 days'
where expires_at is null;

create or replace function public.matrix_run_retention(
  p_now timestamptz default now(),
  p_event_days integer default 90,
  p_anonymous_days integer default 90,
  p_dlq_days integer default 90,
  p_audit_days integer default 365
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $retention$
declare
  v_feedback_deleted bigint := 0;
  v_evidence_deleted bigint := 0;
  v_invalidations_deleted bigint := 0;
  v_events_deleted bigint := 0;
  v_dlq_deleted bigint := 0;
  v_recommendations_deleted bigint := 0;
  v_identity_links_deleted bigint := 0;
  v_anonymous_deleted bigint := 0;
  v_audit_deleted bigint := 0;
  v_result jsonb;
begin
  if p_event_days < 30 or p_anonymous_days < 30 or p_dlq_days < 30 or p_audit_days < 90 then
    raise exception 'retention windows are below Matrix safety minimums';
  end if;

  delete from public.matrix_recommendation_feedback rf
  using public.matrix_events e
  where rf.event_id = e.id
    and e.received_at < p_now - make_interval(days => p_event_days);
  get diagnostics v_feedback_deleted = row_count;

  delete from public.matrix_interest_evidence ie
  using public.matrix_events e
  where ie.event_id = e.id
    and e.received_at < p_now - make_interval(days => p_event_days);
  get diagnostics v_evidence_deleted = row_count;

  delete from public.matrix_event_invalidations i
  using public.matrix_events e
  where i.event_id = e.id
    and e.received_at < p_now - make_interval(days => p_event_days);
  get diagnostics v_invalidations_deleted = row_count;

  delete from public.matrix_events
  where received_at < p_now - make_interval(days => p_event_days);
  get diagnostics v_events_deleted = row_count;

  delete from public.matrix_dead_letter_events
  where coalesce(resolved_at, last_failed_at) < p_now - make_interval(days => p_dlq_days);
  get diagnostics v_dlq_deleted = row_count;

  delete from public.matrix_recommendations
  where anonymous_profile_id is not null
    and (
      (expires_at is not null and expires_at < p_now)
      or generated_at < p_now - make_interval(days => p_anonymous_days)
    );
  get diagnostics v_recommendations_deleted = row_count;

  delete from public.matrix_identity_links il
  using public.matrix_anonymous_profiles ap
  where il.anonymous_profile_id = ap.id
    and coalesce(ap.expires_at, ap.last_seen_at + make_interval(days => p_anonymous_days)) < p_now
    and not exists (
      select 1
      from public.matrix_events e
      where e.anonymous_profile_id = ap.id
    );
  get diagnostics v_identity_links_deleted = row_count;

  delete from public.matrix_anonymous_profiles ap
  where coalesce(ap.expires_at, ap.last_seen_at + make_interval(days => p_anonymous_days)) < p_now
    and not exists (
      select 1
      from public.matrix_events e
      where e.anonymous_profile_id = ap.id
    )
    and not exists (
      select 1
      from public.matrix_recommendations r
      where r.anonymous_profile_id = ap.id
    )
    and not exists (
      select 1
      from public.matrix_identity_links il
      where il.anonymous_profile_id = ap.id
    );
  get diagnostics v_anonymous_deleted = row_count;

  delete from public.matrix_audit_log
  where created_at < p_now - make_interval(days => p_audit_days);
  get diagnostics v_audit_deleted = row_count;

  v_result := jsonb_build_object(
    'policy_version', 'matrix-retention-v1-2026-09-06',
    'event_days', p_event_days,
    'anonymous_days', p_anonymous_days,
    'dlq_days', p_dlq_days,
    'audit_days', p_audit_days,
    'recommendation_feedback_deleted', v_feedback_deleted,
    'interest_evidence_deleted', v_evidence_deleted,
    'event_invalidations_deleted', v_invalidations_deleted,
    'events_deleted', v_events_deleted,
    'dlq_deleted', v_dlq_deleted,
    'anonymous_recommendations_deleted', v_recommendations_deleted,
    'identity_links_deleted', v_identity_links_deleted,
    'anonymous_profiles_deleted', v_anonymous_deleted,
    'audit_rows_deleted', v_audit_deleted,
    'ran_at', p_now
  );

  insert into public.matrix_audit_log (
    tenant_id,
    actor_type,
    actor_id,
    action,
    target_type,
    result,
    metadata,
    created_at
  )
  select
    t.id,
    'system',
    'matrix-retention-v1',
    'retention.run',
    'matrix_analytics',
    'ok',
    v_result,
    p_now
  from public.matrix_tenants t
  where t.key = 'grupo-lira'
  limit 1;

  return v_result;
end;
$retention$;

revoke all on function public.matrix_run_retention(timestamptz, integer, integer, integer, integer) from public;
revoke all on function public.matrix_run_retention(timestamptz, integer, integer, integer, integer) from anon;
revoke all on function public.matrix_run_retention(timestamptz, integer, integer, integer, integer) from authenticated;
revoke all on function public.matrix_run_retention(timestamptz, integer, integer, integer, integer) from service_role;

select cron.schedule(
  'matrix-retention-daily-v1',
  '17 3 * * *',
  $cron$select public.matrix_run_retention();$cron$
);

do $verify$
begin
  if not exists (
    select 1
    from cron.job
    where jobname = 'matrix-retention-daily-v1'
      and active is true
      and schedule = '17 3 * * *'
  ) then
    raise exception 'Matrix retention cron was not installed as expected';
  end if;

  if has_function_privilege('anon', 'public.matrix_run_retention(timestamptz,integer,integer,integer,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.matrix_run_retention(timestamptz,integer,integer,integer,integer)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.matrix_run_retention(timestamptz,integer,integer,integer,integer)', 'EXECUTE') then
    raise exception 'Matrix retention function has an unexpected executable role';
  end if;
end;
$verify$;

commit;
