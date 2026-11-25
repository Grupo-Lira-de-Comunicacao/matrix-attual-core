-- M4 privacy receipt: may be reviewed independently of institutional migration 026.
-- Store no raw token. A revoked session can recover only its own bounded receipt.
begin;

create table public.matrix_m4_revocation_receipts (
  session_id uuid primary key references public.matrix_person_sessions(id) on delete cascade,
  tenant_id uuid not null references public.matrix_tenants(id),
  project_id uuid not null references public.matrix_projects(id),
  person_id uuid not null references public.matrix_people(id),
  operation_id uuid not null unique default gen_random_uuid(),
  status text not null default 'pending' check (status in ('pending', 'confirmed')),
  received_at timestamptz not null,
  confirmed_at timestamptz,
  retry_attempts integer not null default 0 check (retry_attempts >= 0),
  next_attempt_at timestamptz not null default now() + interval '30 seconds',
  recover_until timestamptz not null,
  check (status = 'confirmed' or confirmed_at is null),
  check (status <> 'confirmed' or confirmed_at is not null)
);
create index matrix_m4_revocation_pending_subject
  on public.matrix_m4_revocation_receipts(tenant_id, project_id, person_id)
  where status = 'pending';
create index matrix_m4_revocation_retry_due
  on public.matrix_m4_revocation_receipts(next_attempt_at, operation_id)
  where status = 'pending';

alter table public.matrix_m4_revocation_receipts enable row level security;
revoke all on public.matrix_m4_revocation_receipts from public, anon, authenticated;
grant select, insert, update on public.matrix_m4_revocation_receipts to service_role;

create function public.matrix_m4_begin_revocation(
  p_tenant_id uuid, p_project_id uuid, p_token_hash text
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_session public.matrix_person_sessions%rowtype;
  v_receipt public.matrix_m4_revocation_receipts%rowtype;
  v_now timestamptz;
  v_purpose text;
  v_consent uuid;
begin
  select * into v_session from public.matrix_person_sessions
   where tenant_id = p_tenant_id and project_id = p_project_id and token_hash = p_token_hash;
  if not found then return null; end if;

  -- Serialize by subject before taking any session row locks.
  perform pg_advisory_xact_lock(hashtextextended(v_session.person_id::text, 0));
  select * into v_session from public.matrix_person_sessions
   where tenant_id = p_tenant_id and project_id = p_project_id and token_hash = p_token_hash for update;
  if not found then return null; end if;
  v_now := clock_timestamp();

  select * into v_receipt from public.matrix_m4_revocation_receipts where session_id = v_session.id;
  if found then
    if v_receipt.recover_until <= v_now then return null; end if;
  else
    if v_session.status <> 'active' or v_session.expires_at <= v_now then return null; end if;
    insert into public.matrix_m4_revocation_receipts
      (session_id, tenant_id, project_id, person_id, received_at, recover_until)
    values (v_session.id, p_tenant_id, p_project_id, v_session.person_id, v_now, v_now + interval '7 days')
    returning * into v_receipt;

    update public.matrix_person_sessions set status = 'revoked', revoked_at = v_now
      where tenant_id = p_tenant_id and project_id = p_project_id
        and person_id = v_session.person_id and status = 'active';
    update public.matrix_identity_links set link_status = 'revoked', revoked_at = v_now
      where tenant_id = p_tenant_id and project_id = p_project_id and person_id = v_session.person_id
        and external_system = 'attual_one' and link_status = 'active';
    update public.matrix_identity_bridge_tokens set status = 'revoked'
      where tenant_id = p_tenant_id and project_id = p_project_id and person_id = v_session.person_id
        and external_system = 'attual_one' and status = 'pending';
    update public.matrix_m3_action_outbox
       set status = 'suppressed', last_error = 'm4_revocation_recorded', updated_at = v_now
      where tenant_id = p_tenant_id and project_id = p_project_id and person_id = v_session.person_id
        and destination = 'attual_one' and status in ('pending','processing','failed');

    foreach v_purpose in array array['analytics','personalization'] loop
      insert into public.matrix_consents
        (tenant_id, person_id, purpose, channel, status, legal_basis, source, policy_version, withdrawn_at, metadata, created_at)
      values (p_tenant_id, v_session.person_id, v_purpose, 'attualplay', 'withdrawn', 'consent',
              'attualplay-m4', 'attualplay-privacy-v4-2026-09-07', v_now,
              '{"adult_confirmed":false,"marketing":false,"m4_identity_explicit":true}', v_now)
      returning id into v_consent;
      insert into public.matrix_consent_events
        (consent_id, action, new_status, occurred_at, actor_type, actor_id, correlation_id, metadata)
      values (v_consent, 'withdrawn', 'withdrawn', v_now, 'person', v_session.person_id::text,
              v_receipt.operation_id, '{"source":"attualplay-m4"}');
    end loop;

    insert into public.matrix_audit_log
      (tenant_id, project_id, actor_type, action, target_type, result, correlation_id, metadata, created_at)
    values (p_tenant_id, p_project_id, 'person', 'm4.identity.unlinked', 'matrix_identity_link', 'ok',
            v_receipt.operation_id, '{"marketing":false,"external_actions":false}', v_now);
  end if;

  return jsonb_build_object('matrix_person_id', v_receipt.person_id,
    'operation_id', v_receipt.operation_id, 'confirmed', v_receipt.status = 'confirmed');
end;
$$;

revoke all on function public.matrix_m4_begin_revocation(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.matrix_m4_begin_revocation(uuid, uuid, text) to service_role;

-- Keep any fresh activation from crossing an unresolved downstream revocation.
-- The existing link flow must be made transactional separately before promotion.
create function public.matrix_m4_guard_pending_revocation() returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_table_name = 'matrix_person_sessions' and to_jsonb(new)->>'status' <> 'active' then return new; end if;
  if tg_table_name = 'matrix_identity_links'
      and (to_jsonb(new)->>'link_status' <> 'active' or to_jsonb(new)->>'external_system' is distinct from 'attual_one') then return new; end if;
  if tg_table_name = 'matrix_consents'
      and (to_jsonb(new)->>'status' <> 'granted' or to_jsonb(new)->>'source' <> 'attualplay-m4'
           or new.person_id is null) then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.person_id::text, 0));
  if exists (select 1 from public.matrix_m4_revocation_receipts
    where tenant_id = new.tenant_id and person_id = new.person_id and status = 'pending') then
    raise exception 'Matrix privacy confirmation is still pending' using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function public.matrix_m4_guard_pending_revocation() from public, anon, authenticated;
grant execute on function public.matrix_m4_guard_pending_revocation() to service_role;
create trigger matrix_m4_guard_sessions before insert or update of status on public.matrix_person_sessions
  for each row execute function public.matrix_m4_guard_pending_revocation();
create trigger matrix_m4_guard_links before insert or update of link_status on public.matrix_identity_links
  for each row execute function public.matrix_m4_guard_pending_revocation();
create trigger matrix_m4_guard_consents before insert on public.matrix_consents
  for each row execute function public.matrix_m4_guard_pending_revocation();

commit;
