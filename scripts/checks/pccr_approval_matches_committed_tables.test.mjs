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
import { execFileSync } from 'node:child_process';
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
    approved_amendment_table_digest, approved_amendment_table_path, deployed_before_approval,
    original_deployment_at::text as original_deployment_at
  from public.phase_c_freeze_amendment order by amendment_id`);

console.log(`sha256(${TABLES}) = ${digest}`);
console.log(`${rows.length} recorded amendment(s) on ${PROJECT_REF}`);

// EACH AMENDMENT NAMES ITS OWN DOCUMENT, AND IS HASHED AGAINST THAT ONE.
// PCCR-006 added approved_amendment_table_path for exactly this reason — so a SECOND amendment
// document could be verified without invalidating the first five — and this file went on hashing
// one hard-coded path. Amendment 51 names docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md.
const hashOf = (p) => { try { return createHash('sha256').update(readFileSync(p)).digest('hex'); }
                        catch { return null; } };
// A DIGEST THAT DOES NOT MATCH THE WORKING TREE IS NOT AUTOMATICALLY WRONG. PCCR-006's execution
// record was APPENDED to the document after he approved it, which moves the file's sha256 — the
// document says so itself and preserves the approved digest at a named commit. So a mismatch sends
// us to git history, and only a digest that has never existed for that path is a failure.
const commitCarrying = (p, want) => {
  try {
    const commits = execFileSync('git', ['rev-list', '--all', '--', p], { encoding: 'utf8' })
      .split('\n').filter(Boolean).slice(0, 400);
    for (const c of commits) {
      const blob = execFileSync('git', ['show', `${c}:${p}`], { encoding: 'buffer', maxBuffer: 64e6 });
      if (createHash('sha256').update(blob).digest('hex') === want) return c.slice(0, 7);
    }
  } catch { /* fall through to "nowhere" */ }
  return null;
};

// THE ONE-TIME BOOTSTRAP, ACCEPTED ONCE AND POLICED HERE TOO.
// PCCR-006 could not be approved through the door PCCR-006 created — the change request that makes
// the rule cannot satisfy it retroactively without the unbacked write it forbids. It was approved
// on an authenticated Command Center command instead, recorded as its own basis rather than
// mislabelled AUTHENTICATED_FOUNDER_SESSION (which would be false) or WRITTEN_INSTRUCTION (also
// false). fn_phase_c_freeze_drift already goes red at anything but exactly one such row; this file
// asserts the same bound independently, because a single instrument policing a single-use
// exception is a single point of failure.
const BOOTSTRAP = 'AUTHENTICATED_FOUNDER_COMMAND_BOOTSTRAP';
const bootstraps = rows.filter((r) => r.approval_basis === BOOTSTRAP);

const fail = [];
if (bootstraps.length > 1) {
  fail.push(`${bootstraps.length} amendments carry ${BOOTSTRAP} and exactly one may: `
    + bootstraps.map((b) => `${b.amendment_id}/${b.change_request_ref}`).join(', '));
}
for (const b of bootstraps) {
  if (b.change_request_ref !== 'PCCR-006') {
    fail.push(`amendment ${b.amendment_id} carries ${BOOTSTRAP} for ${b.change_request_ref}; `
      + 'the bootstrap exists only for PCCR-006, the change request that created the door it '
      + 'could not itself walk through');
  }
}

for (const r of rows) {
  const line = `  amendment ${String(r.amendment_id).padStart(2)}  ${r.change_request_ref}  ${r.subject}`;
  if (r.approval_basis !== 'AUTHENTICATED_FOUNDER_SESSION' && r.approval_basis !== BOOTSTRAP) {
    console.log(`${line}  basis=${r.approval_basis ?? '(unapproved)'}`);
    fail.push(`amendment ${r.amendment_id} is ${r.approval_basis ?? 'unapproved'}, not an approval given in a verified founder session`);
    continue;
  }
  const path = r.approved_amendment_table_path || TABLES;
  const live = hashOf(path);
  const basis = r.approval_basis === BOOTSTRAP ? `  [${BOOTSTRAP}]` : '';
  let ok = r.approved_amendment_table_digest === live;
  let where = 'the committed file';
  if (!ok) {
    const at = commitCarrying(path, r.approved_amendment_table_digest);
    if (at) { ok = true; where = `${path} as committed at ${at}`; }
  }
  console.log(`${line}  ${ok ? 'matches' : 'DIFFERS FROM'} ${where}`
    + `  (route ${r.approval_route ?? '(none)'}, subject ${r.approval_auth_subject})${basis}`);
  if (!ok) {
    fail.push(`amendment ${r.amendment_id} was approved against document digest `
      + `${r.approved_amendment_table_digest} for ${path}, and no commit in this repository has ever `
      + `held that path at that digest (working tree: ${live ?? 'file absent'})`);
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
