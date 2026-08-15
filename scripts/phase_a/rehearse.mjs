// PHASE A — STEP 5: rehearse the COMMITTED migration inside an aborted production transaction.
//
// The exact committed bytes are sent, with one statement appended that raises. PostgreSQL wraps a
// multi-statement simple query in a single implicit transaction, so the raise takes every change
// with it and production is untouched — while the appended statement reads the POST-change counts
// first, so the numbers still come out.
//
// Which error comes back is the whole result:
//   * "PHASE A REHEARSAL" with counts  -> the migration ran and its own postconditions passed
//   * "PRECONDITION: …" / "POST: …"    -> the migration refused itself; nothing would have applied
//   * anything else                    -> a real SQL failure, and the rehearsal has done its job
//
//   node scripts/phase_a/rehearse.mjs
import { readFileSync } from 'node:fs';
import { PROD_REF } from '../staging/qd_guard.mjs';

const FWD = 'supabase/migrations/20260815050000_phase_a_organization_closure.sql';
const sql = readFileSync(FWD, 'utf8');
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

// Read the post-change state, then abort. The read has to happen INSIDE the same transaction or it
// would be measuring the rolled-back database and reporting it as the result of the migration.
const ABORT = `
do $$
declare v_d int; v_r int; v_o int; v_w int; v_n int; v_ret int; v_ali int; v_com int; v_shape text;
begin
  select count(*) into v_d from public.org_departments where active;
  select count(*) into v_r from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  select count(*) into v_o from public.org_role where status='active' and runtime_mode = 'knowledge_overlay';
  select count(*) into v_w from public.org_workflow_ownership;
  select count(*) into v_n from public.org_role where status='active' and necessity_status is not null;
  select count(*) into v_ret from public.org_role where status='retired';
  select count(*) into v_ali from public.org_role_alias;
  select count(*) into v_com from public.org_role_committee where committee_key='exec_committee';
  select string_agg(n::text, ',' order by n) into v_shape from (
    select count(*) n from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay'
     group by primary_department_id) s;
  raise exception 'PHASE A REHEARSAL — ROLLED BACK. departments=% roles=% overlays=% shape=% workflows_owned=% roles_with_necessity=% retired=% aliases=% exec_committee=%',
    v_d, v_r, v_o, v_shape, v_w, v_n, v_ret, v_ali, v_com;
end $$;`;

const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: sql + '\n' + ABORT }),
});
const body = await r.text();
const msg = (() => { try { return JSON.parse(body).message || body; } catch { return body; } })();

console.log(`rehearsal HTTP ${r.status}`);
console.log(msg.replace(/\\n/g, '\n').slice(0, 2000));

if (r.ok) {
  console.error('\nFAILED: the rehearsal returned success. The abort did not fire, which means the');
  console.error('changes may have COMMITTED. Verify the fingerprint immediately.');
  process.exit(1);
}
if (/PHASE A REHEARSAL/.test(msg)) {
  console.log('\nREHEARSAL PASSED — the migration applied cleanly, its own preconditions and');
  console.log('postconditions passed, and the transaction was then aborted.');
  process.exit(0);
}
console.error('\nREHEARSAL DID NOT REACH THE ABORT. The migration refused itself or failed; the');
console.error('message above is the reason. Nothing was applied.');
process.exit(2);
