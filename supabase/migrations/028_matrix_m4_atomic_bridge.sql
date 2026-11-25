-- M4 explicit bridge consumption: one transaction, independent from institutional migration 026.
begin;

create function public.matrix_m4_consume_bridge(
  p_tenant_id uuid, p_project_id uuid, p_bridge_hash text, p_anonymous_hash text,
  p_session_hash text, p_consent jsonb, p_correlation_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_bridge public.matrix_identity_bridge_tokens%rowtype;
  v_now timestamptz;
  v_expiry timestamptz;
  v_anon uuid;
  v_purpose text;
  v_status text;
  v_consent uuid;
  v_policy text := p_consent->>'policy_version';
begin
  if p_consent->'analytics' is distinct from 'true'::jsonb
     or p_consent->'adult_confirmed' is distinct from 'true'::jsonb
     or p_consent->'marketing' is distinct from 'false'::jsonb
     or jsonb_typeof(p_consent->'personalization') is distinct from 'boolean'
     or v_policy is null or length(v_policy) not between 3 and 80
     or p_correlation_id is null then
    raise exception 'Explicit adult analytics consent required' using errcode = '22023';
  end if;
  if p_bridge_hash is null or p_bridge_hash !~ '^[0-9a-f]{64}$'
     or p_anonymous_hash is null or p_anonymous_hash !~ '^[0-9a-f]{64}$'
     or p_session_hash is null or p_session_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid bridge digest' using errcode = '22023';
  end if;

  select * into v_bridge from public.matrix_identity_bridge_tokens
   where tenant_id = p_tenant_id and project_id = p_project_id
     and bridge_code_hash = p_bridge_hash and external_system = 'attual_one';
  if not found then return null; end if;

  -- Same subject-lock ordering as revocation; recheck under the lock before any side effects.
  perform pg_advisory_xact_lock(hashtextextended(v_bridge.person_id::text, 0));
  v_now := clock_timestamp();
  v_expiry := v_now + interval '30 days';
  update public.matrix_identity_bridge_tokens
    set status = 'consumed', consumed_at = v_now
    where id = v_bridge.id and tenant_id = p_tenant_id and project_id = p_project_id
      and bridge_code_hash = p_bridge_hash and external_system = 'attual_one'
      and status = 'pending' and expires_at > v_now
    returning * into v_bridge;
  if not found then return null; end if;

  if not exists (
    select 1 from public.matrix_people p
    join public.matrix_identities i on i.person_id=p.id and i.tenant_id=p.tenant_id
    where p.id=v_bridge.person_id and p.tenant_id=p_tenant_id and p.status='active'
      and i.id=v_bridge.identity_id and i.verified and i.identity_type='attual_one_account_ref'
      and i.normalized_hash=v_bridge.external_ref_hash
  ) then
    raise exception 'Verified One bridge identity unavailable' using errcode = '55000';
  end if;
  if exists (
    select 1 from public.matrix_m4_revocation_receipts r
      where r.tenant_id=p_tenant_id and r.person_id=v_bridge.person_id
        and (r.status='pending' or r.confirmed_at >= v_bridge.created_at)
  ) then
    raise exception 'New bridge required after privacy revocation' using errcode = '55000';
  end if;

  insert into public.matrix_anonymous_profiles
    (tenant_id,project_id,anonymous_key_hash,last_seen_at,expires_at)
  values (p_tenant_id,p_project_id,p_anonymous_hash,v_now,v_now + interval '90 days')
  on conflict (tenant_id,project_id,anonymous_key_hash) do update
    set last_seen_at=excluded.last_seen_at, expires_at=excluded.expires_at
  returning id into v_anon;

  insert into public.matrix_identity_links
    (tenant_id,project_id,anonymous_profile_id,person_id,link_reason,confidence,
     link_status,external_system,external_ref_hash,verified_at,revoked_at,metadata)
  values (p_tenant_id,p_project_id,v_anon,v_bridge.person_id,'explicit_attual_one_bridge',1,
    'active','attual_one',v_bridge.external_ref_hash,v_now,null,
    jsonb_build_object('explicit_user_action',true,'hidden_stitching',false,'correlation_id',p_correlation_id))
  on conflict (anonymous_profile_id,person_id) do update set
    link_status='active', external_system=excluded.external_system,
    external_ref_hash=excluded.external_ref_hash, verified_at=excluded.verified_at,
    revoked_at=null, metadata=excluded.metadata;

  foreach v_purpose in array array['analytics','personalization'] loop
    v_status := case when v_purpose='analytics' or p_consent->'personalization'='true'::jsonb
      then 'granted' else 'withdrawn' end;
    insert into public.matrix_consents
      (tenant_id,person_id,purpose,channel,status,legal_basis,source,policy_version,
       granted_at,withdrawn_at,metadata,created_at)
    values (p_tenant_id,v_bridge.person_id,v_purpose,'attualplay',v_status,'consent','attualplay-m4',v_policy,
      case when v_status='granted' then v_now end,case when v_status='withdrawn' then v_now end,
      '{"adult_confirmed":true,"marketing":false,"m4_identity_explicit":true}',v_now)
    returning id into v_consent;

    insert into public.matrix_consent_events
      (consent_id,action,new_status,occurred_at,actor_type,actor_id,correlation_id,metadata)
    values (v_consent,v_status,v_status,v_now,'person',v_bridge.person_id::text,p_correlation_id,
      jsonb_build_object('source','attualplay-m4','policy_version',v_policy));
  end loop;

  insert into public.matrix_person_sessions
    (tenant_id,project_id,person_id,anonymous_profile_id,bridge_id,token_hash,status,issued_at,expires_at,last_seen_at,correlation_id)
  values (p_tenant_id,p_project_id,v_bridge.person_id,v_anon,v_bridge.id,p_session_hash,
    'active',v_now,v_expiry,v_now,p_correlation_id);

  insert into public.matrix_audit_log
    (tenant_id,project_id,actor_type,action,target_type,result,correlation_id,metadata,created_at)
  values (p_tenant_id,p_project_id,'person','m4.identity.linked','matrix_identity_link','ok',p_correlation_id,
    '{"explicit_user_action":true,"hidden_stitching":false,"marketing":false}',v_now);

  return jsonb_build_object('matrix_person_id',v_bridge.person_id,'expires_at',v_expiry);
end;
$$;

revoke all on function public.matrix_m4_consume_bridge(uuid,uuid,text,text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.matrix_m4_consume_bridge(uuid,uuid,text,text,text,jsonb,uuid) to service_role;

commit;
