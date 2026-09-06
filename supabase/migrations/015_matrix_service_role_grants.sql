-- Matrix Attual Core
-- Migration 015: least-privilege grants for Matrix Event API backend

begin;

grant usage on schema public to service_role;

grant select on table
  public.matrix_tenants,
  public.matrix_projects,
  public.matrix_identities
to service_role;

grant select, insert, update on table
  public.matrix_anonymous_profiles
to service_role;

grant select, insert on table
  public.matrix_events,
  public.matrix_event_invalidations
to service_role;

commit;
