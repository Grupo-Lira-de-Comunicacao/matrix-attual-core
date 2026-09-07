-- Matrix Attual Core
-- Migration 018: fix anonymous person_id NULL typing in M2 shadow engine

begin;

do $m2_function_hotfix$
declare
  v_definition text;
  v_fixed text;
  v_needle text := E'      e.project_id,\n      null,\n      e.anonymous_profile_id,';
  v_replacement text := E'      e.project_id,\n      null::uuid,\n      e.anonymous_profile_id,';
begin
  select pg_get_functiondef('public.matrix_run_m2_shadow(timestamptz,integer)'::regprocedure)
  into v_definition;

  if v_definition is null then
    raise exception 'M2 hotfix failed: matrix_run_m2_shadow function not found';
  end if;

  if position(v_needle in v_definition) = 0 then
    if position('null::uuid' in v_definition) > 0 then
      return;
    end if;
    raise exception 'M2 hotfix failed: expected anonymous score insert fragment not found';
  end if;

  v_fixed := replace(v_definition, v_needle, v_replacement);
  execute v_fixed;
end;
$m2_function_hotfix$;

revoke all on function public.matrix_run_m2_shadow(timestamptz, integer) from public;
revoke all on function public.matrix_run_m2_shadow(timestamptz, integer) from anon;
revoke all on function public.matrix_run_m2_shadow(timestamptz, integer) from authenticated;
revoke all on function public.matrix_run_m2_shadow(timestamptz, integer) from service_role;

do $m2_hotfix_validate$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.matrix_run_m2_shadow(timestamptz,integer)'::regprocedure)
  into v_definition;

  if position('null::uuid' in v_definition) = 0 then
    raise exception 'M2 hotfix validation failed: explicit UUID NULL cast missing';
  end if;

  if has_function_privilege('anon', 'public.matrix_run_m2_shadow(timestamptz,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.matrix_run_m2_shadow(timestamptz,integer)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.matrix_run_m2_shadow(timestamptz,integer)', 'EXECUTE') then
    raise exception 'M2 hotfix validation failed: engine execution exposed to client/service role';
  end if;
end;
$m2_hotfix_validate$;

commit;
