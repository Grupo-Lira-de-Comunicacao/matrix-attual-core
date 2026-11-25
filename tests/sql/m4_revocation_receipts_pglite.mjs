// Local only: install @electric-sql/pglite separately without changing the service lockfile.
import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
const db = new PGlite();
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create table public.matrix_tenants (id uuid primary key);
    create table public.matrix_projects (id uuid primary key);
    create table public.matrix_people (id uuid primary key);
    create table public.matrix_person_sessions (
      id uuid primary key default gen_random_uuid(), tenant_id uuid, project_id uuid, person_id uuid,
      token_hash text unique, status text, expires_at timestamptz, revoked_at timestamptz);
    create table public.matrix_identity_links (
      tenant_id uuid, project_id uuid, person_id uuid, external_system text, link_status text, revoked_at timestamptz);
    create table public.matrix_identity_bridge_tokens (
      tenant_id uuid, project_id uuid, person_id uuid, external_system text, status text);
    create table public.matrix_m3_action_outbox (
      tenant_id uuid, project_id uuid, person_id uuid, destination text, status text, last_error text, updated_at timestamptz);
    create table public.matrix_consents (
      id uuid primary key default gen_random_uuid(), tenant_id uuid, person_id uuid, purpose text, channel text,
      status text, legal_basis text, source text, policy_version text, withdrawn_at timestamptz, metadata jsonb, created_at timestamptz);
    create table public.matrix_consent_events (
      consent_id uuid, action text, new_status text, occurred_at timestamptz, actor_type text, actor_id text,
      correlation_id uuid, metadata jsonb);
    create table public.matrix_audit_log (
      tenant_id uuid, project_id uuid, actor_type text, action text, target_type text, result text,
      correlation_id uuid, metadata jsonb, created_at timestamptz);
  `);
  await db.exec(await readFile(new URL("../../supabase/migrations/027_matrix_m4_revocation_receipts.sql", import.meta.url), "utf8"));
  await db.exec(`
    do $$
    declare
      t uuid := '10000000-0000-4000-8000-000000000001';
      p uuid := '20000000-0000-4000-8000-000000000001';
      u uuid := '30000000-0000-4000-8000-000000000001';
      first jsonb; replay jsonb; op uuid;
    begin
      insert into public.matrix_tenants values (t);
      insert into public.matrix_projects values (p);
      insert into public.matrix_people values (u);
      insert into public.matrix_person_sessions (tenant_id,project_id,person_id,token_hash,status,expires_at)
        values (t,p,u,'fixture-token-hash','active',now() + interval '1 day');
      insert into public.matrix_identity_links values (t,p,u,'attual_one','active',null);
      insert into public.matrix_identity_bridge_tokens values (t,p,u,'attual_one','pending');
      insert into public.matrix_m3_action_outbox values (t,p,u,'attual_one','pending',null,null);
      alter table public.matrix_audit_log add constraint fixture_failed_audit check (result <> 'ok');
      begin
        perform public.matrix_m4_begin_revocation(t,p,'fixture-token-hash');
        raise exception 'expected the audit fixture to fail';
      exception when check_violation then null;
      end;
      if (select status from public.matrix_person_sessions) <> 'active'
        or exists (select from public.matrix_m4_revocation_receipts)
        or exists (select from public.matrix_consent_events) then
        raise exception 'partial write survived rollback';
      end if;
      alter table public.matrix_audit_log drop constraint fixture_failed_audit;
      first := public.matrix_m4_begin_revocation(t,p,'fixture-token-hash');
      replay := public.matrix_m4_begin_revocation(t,p,'fixture-token-hash');
      op := (first->>'operation_id')::uuid;
      if first is distinct from replay or op is null or first->>'confirmed' is distinct from 'false'
         or (select status from public.matrix_person_sessions) <> 'revoked'
         or (select link_status from public.matrix_identity_links) <> 'revoked'
         or (select status from public.matrix_identity_bridge_tokens) <> 'revoked'
         or (select status from public.matrix_m3_action_outbox) <> 'suppressed'
         or (select count(*) from public.matrix_consent_events) <> 2 then
        raise exception 'revocation state or replay invariant failed';
      end if;
      if public.matrix_m4_begin_revocation(t,p,'wrong-token-hash') is not null
        or public.matrix_m4_begin_revocation(t,t,'fixture-token-hash') is not null then
        raise exception 'receipt escaped token or project scope';
      end if;
      begin
        insert into public.matrix_person_sessions (tenant_id,project_id,person_id,token_hash,status,expires_at)
          values (t,p,u,'second-fixture','active',now() + interval '1 day');
        raise exception 'pending privacy operation allowed relink';
      exception when object_not_in_prerequisite_state then null;
      end;
      update public.matrix_m4_revocation_receipts set status='confirmed', confirmed_at=now() where operation_id=op;
      replay := public.matrix_m4_begin_revocation(t,p,'fixture-token-hash');
      if replay->>'operation_id' is distinct from op::text or replay->>'confirmed' is distinct from 'true' then
        raise exception 'lost response could not recover confirmed receipt';
      end if;
      if has_function_privilege('anon','public.matrix_m4_begin_revocation(uuid,uuid,text)','EXECUTE')
         or not has_function_privilege('service_role','public.matrix_m4_begin_revocation(uuid,uuid,text)','EXECUTE') then
        raise exception 'receipt RPC permissions escaped the service boundary';
      end if;
    end
    $$;
  `);
  console.log("PASS: atomic rollback, local fences, receipts, scoped replay, service-only permissions");
} finally {
  await db.close();
}
