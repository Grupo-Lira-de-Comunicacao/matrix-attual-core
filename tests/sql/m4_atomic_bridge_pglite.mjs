// Local PostgreSQL fixture; pg_cron is staged as a registration shim, not executed.
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { readFile, readdir } from 'node:fs/promises';
const db = new PGlite({extensions:{pgcrypto}});
const dir = new URL('../../supabase/migrations/',import.meta.url);
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema cron;
    create table cron.job (jobid bigserial, jobname text unique, schedule text, command text, active boolean default true);
    create function cron.schedule(name text, schedule text, command text) returns bigint
      language sql as $$ insert into cron.job(jobname,schedule,command) values ($1,$2,$3)
       on conflict (jobname) do update set schedule=excluded.schedule,command=excluded.command returning jobid $$;
    create function cron.unschedule(bigint) returns boolean language sql as
       $$ with d as (delete from cron.job where jobid=$1 returning 1) select exists(select from d) $$;
  `);
  const files=(await readdir(dir)).filter(f=>/^(0[0-1][0-9]|02[0-578])_/.test(f)).sort();
  for(const f of files) {
    try { await db.exec((await readFile(new URL(f,dir),'utf8')).replace(/^create extension if not exists pg_cron[^;]*;$/gm,'')); console.log('PASS',f); }
    catch(e) { console.error('FAIL',f,e.message); throw e; }
  }
  const t=(await db.query("select id from public.matrix_tenants where key='grupo-lira'")).rows[0].id;
  const p=(await db.query("select id from public.matrix_projects where tenant_id=$1 and project_key='attualplay'",[t])).rows[0].id;
  const u=(await db.query("insert into public.matrix_people(tenant_id) values ($1) returning id",[t])).rows[0].id;
  const identity=(await db.query("insert into public.matrix_identities(tenant_id,person_id,identity_type,normalized_hash,verified) values ($1,$2,'attual_one_account_ref','fixture-external',true) returning id",[t,u])).rows[0].id;
  const b='a'.repeat(64), prior='b'.repeat(64), fresh='c'.repeat(64);
  const addBridge=(hash,createdOffset)=>db.query(`insert into public.matrix_identity_bridge_tokens(tenant_id,project_id,person_id,identity_id,
    external_system,external_ref_hash,bridge_code_hash,expires_at,created_at)
    values ($1,$2,$3,$4,'attual_one','fixture-external',$5,now()+interval '5 minutes',clock_timestamp()+$6::interval)`,[t,p,u,identity,hash,createdOffset]);
  await addBridge(b,'-2 minutes');
  await db.exec("alter table public.matrix_audit_log add constraint fixture_fail_bridge check (action <> 'm4.identity.linked')");
  const consent={analytics:true,adult_confirmed:true,personalization:true,marketing:false,policy_version:'test-policy-v1'};
  const cid='10000000-0000-4000-8000-000000000001';
  const auth=()=>db.exec('set role service_role');
  const admin=()=>db.exec('reset role');
  const claim=async(hash,session,c=consent,project=p)=> (await db.query(
    'select public.matrix_m4_consume_bridge($1,$2,$3,$4,$5,$6,$7) receipt',[t,project,hash,'d'.repeat(64),session,c,cid])).rows[0].receipt;
  const status=async(hash)=> (await db.query('select status from public.matrix_identity_bridge_tokens where bridge_code_hash=$1',[hash])).rows[0].status;
  const count=async(table)=> (await db.query(`select count(*)::int qty from public.${table}`)).rows[0].qty;
  async function mustReject(op,code){let rejected=false;try{await op();}catch(e){if(e.code!==code)throw e;rejected=true;}if(!rejected)throw new Error('expected '+code);}
  await auth();
  const initial=await count('matrix_person_sessions');
  await mustReject(()=>claim(b,'e'.repeat(64)),'23514');
  if(await status(b)!=='pending'||await count('matrix_person_sessions')!==initial||await count('matrix_consents')!==0)
    throw new Error('database left a partial bridge');
  await admin();await db.exec('alter table public.matrix_audit_log drop constraint fixture_fail_bridge');await auth();
  await mustReject(()=>claim(b,'e'.repeat(64),{...consent,analytics:false}),'22023');
  if(await claim(b,'e'.repeat(64),consent,t)!==null||await status(b)!=='pending')throw new Error('cross-project claim changed bridge');
  const first=await claim(b,'e'.repeat(64));
  if(first.matrix_person_id!==u||await status(b)!=='consumed'||await count('matrix_person_sessions')!==initial+1)
    throw new Error('bridge did not commit atomically');
  if(await claim(b,'f'.repeat(64))!==null||await count('matrix_person_sessions')!==initial+1)
    throw new Error('bridge replay created another session');
  const revoke=(await db.query('select public.matrix_m4_begin_revocation($1,$2,$3) r',[t,p,'e'.repeat(64)])).rows[0].r;
  await addBridge(prior,'0 seconds');
  await mustReject(()=>claim(prior,'f'.repeat(64)),'55000');
  await db.query("update public.matrix_m4_revocation_receipts set status='confirmed',confirmed_at=clock_timestamp() where operation_id=$1",[revoke.operation_id]);
  await mustReject(()=>claim(prior,'f'.repeat(64)),'55000');
  await addBridge(fresh,'0 seconds');
  const relink=await claim(fresh,'f'.repeat(64));
  if(relink.matrix_person_id!==u||await count('matrix_person_sessions')!==initial+2)throw new Error('fresh post-confirmation link did not work');
  const old=(await db.query('select public.matrix_m4_begin_revocation($1,$2,$3) r',[t,p,'e'.repeat(64)])).rows[0].r;
  if(old.operation_id!==revoke.operation_id||!old.confirmed||(await db.query("select status from public.matrix_person_sessions where token_hash=$1",['f'.repeat(64)])).rows[0].status!=='active')
    throw new Error('old confirmed receipt reactivated or revoked new state');
  console.log('PASS: real local schema, service_role, rollback, single-use, receipt-scoped recovery, fresh-link fence');
} finally { await db.close(); }
