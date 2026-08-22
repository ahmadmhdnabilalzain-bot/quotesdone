// The founder's approval of each PCCR amendment is recorded against a DOCUMENT — "the exact
// amendment tables committed in PHASE_D_PCCR_AMENDMENT_TABLES.md". public.phase_c_freeze_amendment
// stores the sha256 of that document as it stood when the approval was given.
//
// This check hashes the committed file and compares. It is the repository checking the database,
// which is the only direction that means anything: a digest constant living inside the routine that
// validates it would prove nothing about the file at all.
//
// A FAILURE HERE IS NOT A BUG IN THIS CHECK. It means one of two things, and they are different:
//   - the document was edited after the approval, so the approval no longer describes the file; or
//   - an approval was recorded against a document nobody committed.
// Either way the founder approved something other than what is on disk, and the fix is a fresh
// approval through fn_phase_c_freeze_amendment_approve, never an edit to the stored digest.
//
//   node scripts/checks/pccr_approval_matches_committed_tables.test.mjs
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { homedir } from 'node:os';
import { join } from 'node:path';

// THE SKIP IS DECLARED BEFORE THE DATABASE IS TOUCHED, because ../phase_b/lib/db.mjs THROWS on
// import-time use without a token and a thrown import is a failed job rather than a skipped check.
// The credentialed job in project-parity.yml treats this line as a failure, which is the point: a
// skip is honest in the job that has no token and a defect in the job that has one.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) {
  console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');
  console.log('SKIP — no Supabase management token in this environment; this check reads the '
    + 'approvals off production and cannot be answered from the repository alone.');
  process.exit(0);
}
const { sql, PROJECT_REF } = await import('../phase_b/lib/db.mjs');

const TABLES = 'docs/phase-d/PHASE_D_PCCR_AMENDMENT_TABLES.md';
const digest = createHash('sha256').update(readFileSync(TABLES)).digest('hex');

const rows = await sql(`select amendment_id, change_request_ref, subject, approval_basis,
    approved_by, approval_route, approval_auth_subject::text as approval_auth_subject,
    approved_amendment_table_digest, deployed_before_approval,
    original_deployment_at::text as original_deployment_at
  from public.phase_c_freeze_amendment order by amendment_id`);

console.log(`sha256(${TABLES}) = ${digest}`);
console.log(`${rows.length} recorded amendment(s) on ${PROJECT_REF}`);

const fail = [];
for (const r of rows) {
  const line = `  amendment ${String(r.amendment_id).padStart(2)}  ${r.change_request_ref}  ${r.subject}`;
  if (r.approval_basis !== 'AUTHENTICATED_FOUNDER_SESSION') {
    console.log(`${line}  basis=${r.approval_basis ?? '(unapproved)'}`);
    fail.push(`amendment ${r.amendment_id} is ${r.approval_basis ?? 'unapproved'}, not an approval given in a verified founder session`);
    continue;
  }
  const ok = r.approved_amendment_table_digest === digest;
  console.log(`${line}  ${ok ? 'matches' : 'DIFFERS FROM'} the committed tables`
    + `  (route ${r.approval_route}, subject ${r.approval_auth_subject})`);
  if (!ok) {
    fail.push(`amendment ${r.amendment_id} was approved against document digest `
      + `${r.approved_amendment_table_digest} and the committed file hashes to ${digest}`);
  }
  // A retrospective ratification that cannot say when the code shipped is not a record of anything.
  if (r.deployed_before_approval === true && !r.original_deployment_at) {
    fail.push(`amendment ${r.amendment_id} is recorded as deployed before approval and names no original_deployment_at`);
  }
  if (r.deployed_before_approval === null) {
    fail.push(`amendment ${r.amendment_id} does not state whether it was deployed before it was approved`);
  }
  // approved_by must still resolve to an active founder identity — the write-time trigger checked
  // it once; an identity deactivated since would leave a standing approval nobody can attribute.
}

const orphan = await sql(`select a.amendment_id, a.approved_by from public.phase_c_freeze_amendment a
  where a.approved_by is not null
    and not exists (select 1 from public.phase_c_founder_identity f
                     where f.active and lower(btrim(f.identity)) = lower(btrim(a.approved_by)))`);
for (const o of orphan) fail.push(`amendment ${o.amendment_id} is approved by ${o.approved_by}, which is not an active founder identity today`);

if (fail.length) {
  console.error('\nFAILED:');
  for (const f of fail) console.error('  ' + f);
  process.exit(1);
}
console.log('\nevery recorded amendment carries a verified founder-session approval given against the committed tables');
