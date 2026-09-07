-- Matrix Attual Core
-- Migration 022: least-privilege M4 API grants and self-validation

begin;

grant insert on table public.matrix_audit_log to service_role;

do $validate$
declare
  v_count integer;
begin
  select count(*)::integer into v_count
  from information_schema.tables
  where table_schema = 'public'
    and table_name in (
      'matrix_identity_bridge_tokens',
      'matrix_person_sessions',
      'matrix_m4_context_promotions'
    );
  if v_count <> 3 then
    raise exception 'M4_REQUIRED_TABLES_MISSING';
  end if;

  if to_regprocedure('public.matrix_current_person_consent(uuid,text,timestamp with time zone)') is null then
    raise exception 'M4_CONSENT_FUNCTION_MISSING';
  end if;

  if to_regprocedure('public.matrix_run_m4_control(timestamp with time zone)') is null then
    raise exception 'M4_CONTROL_FUNCTION_MISSING';
  end if;

  if not exists (
    select 1 from cron.job where jobname = 'matrix-m4-control-v1'
  ) then
    raise exception 'M4_CRON_MISSING';
  end if;

  if exists (
    select 1
    from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name = 'matrix_run_m4_control'
      and grantee in ('anon','authenticated','service_role','PUBLIC')
  ) then
    raise exception 'M4_CONTROL_EXECUTE_EXPOSED';
  end if;

  if exists (
    select 1
    from public.matrix_m3_action_outbox
    where destination = 'n8n'
      and status in ('pending','processing')
  ) then
    raise exception 'M4_N8N_EXTERNAL_ACTION_ROW_PRESENT';
  end if;
end;
$validate$;

commit;
