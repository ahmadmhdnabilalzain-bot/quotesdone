// RETIRED 3 Sep 2026 — WITH THE FREEZE-AMENDMENT RITUAL IT SERVED.
//
// The founder removed the phase freezes on 2 Sep 2026: no PCCR amendments, no session signatures.
// A digest of an amendment document nobody will sign again is a ceremony, not a gate. The kernel
// tables it guarded are still measured by the kernel boards and phase_c_invariants, which read
// production. See docs/agents/RETIRED_MIRROR_GATES.md. Body left intact and unreachable.
process.exit(0);

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
const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

// THE APPROVED BODY OF A CHANGE REQUEST: everything above its execution-record appendix.
//
// Returns null when the file has no appendix, in which case the whole-file digest is the only
// thing to compare and nothing here applies. The marker is matched on the heading, and the
// separator line and blank line that precede it are dropped with it, so the body is byte-identical
// to the file as it stood before the appendix was written.
const APPENDIX = /^## Execution record\b/;
function approvedBodyOf(p) {
  let lines;
  try { lines = readFileSync(p, 'utf8').split('\n'); } catch { return null; }
  const at = lines.findIndex((l) => APPENDIX.test(l));
  if (at < 0) return null;
  let end = at;                                    // first line NOT in the approved body
  while (end > 0 && lines[end - 1].trim() === '') end -= 1;      // blank lines before the heading
  if (end > 0 && lines[end - 1].trim() === '---') end -= 1;      // the separator rule
  while (end > 0 && lines[end - 1].trim() === '') end -= 1;      // blank lines before that
  return Buffer.from(lines.slice(0, end).join('\n') + '\n', 'utf8');
}

const hashOf = (p) => { try { return createHash('sha256').update(readFileSync(p)).digest('hex'); }
                        catch { return null; } };
// A DIGEST THAT DOES NOT MATCH THE WORKING TREE IS NOT AUTOMATICALLY WRONG. PCCR-006's execution
// record was APPENDED to the document after he approved it, which moves the file's sha256 — the
// document says so itself and preserves the approved digest at a named commit. So a mismatch sends
// us to git history, and only a digest that has never existed for that path is a failure.
// 26 AUG 2026: THIS RAN IN CI AND PRINTED NOTHING AT ALL BEFORE EXITING 1 -- not one line, in a
// step that ran for eight minutes. A check that fails silently cannot be diagnosed from its own
// output, which is the whole point of having output, so every branch below now says what it did
// and the git work is reported as it happens rather than only when it succeeds.
const git = (args, enc = 'utf8') =>
  execFileSync('git', args, { encoding: enc, maxBuffer: 64e6, stdio: ['ignore', 'pipe', 'pipe'] });

// SHALLOW IS NOT "NEVER EXISTED", and reporting it as such would be a statement about the clone
// dressed up as a statement about the estate. actions/checkout defaults to fetch-depth 1, so
// without the workflow asking for history this returns true and the caller says so.
let shallow = null;
try { shallow = git(['rev-parse', '--is-shallow-repository']).trim() === 'true'; }
catch (e) { shallow = null; console.log(`  git is not usable here: ${String(e.message).slice(0, 120)}`); }

// SEARCH FIRST, THEN QUALIFY A MISS. The first cut of this returned SHALLOW_CLONE without looking,
// and was wrong in the most ordinary case: a shallow clone still CONTAINS commits, and this
// repository's own working tree is shallow while holding the very commit being looked for. Shallow
// means the history is truncated, not that it is empty. So the scan always runs; shallowness only
// changes what a MISS is allowed to be reported as, because in a truncated history "not found" can
// never be upgraded to "never existed".
const commitCarrying = (p, want) => {
  if (shallow === null) return { at: null, why: 'GIT_UNAVAILABLE' };
  let commits;
  try { commits = git(['rev-list', '--all', '--', p]).split('\n').filter(Boolean); }
  catch (e) { return { at: null, why: `REV_LIST_FAILED ${String(e.message).slice(0, 120)}` }; }
  const scan = commits.slice(0, 400);
  console.log(`  searching ${scan.length} of ${commits.length} commit(s) touching ${p} for digest ${want.slice(0, 12)}…`);
  for (const c of scan) {
    let blob;
    try { blob = git(['show', `${c}:${p}`], 'buffer'); } catch { continue; }
    if (createHash('sha256').update(blob).digest('hex') === want) return { at: c.slice(0, 7), why: null };
  }
  if (commits.length > scan.length) return { at: null, why: 'NOT_IN_FIRST_400' };
  return { at: null, why: shallow ? 'SHALLOW_CLONE' : 'NO_COMMIT_EVER_HELD_IT' };
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
  let whyNot = null;

  // A DOCUMENT MAY GAIN AN EXECUTION RECORD AND MAY NOT GAIN ANYTHING ELSE.
  //
  // A change request cannot be finished before it is applied: this repository's own
  // freeze_amendment_names_a_real_change_request.test.mjs requires it to name the amendment id its
  // approval produced, and that id does not exist until the change is applied. So the file the
  // founder approved MUST change afterwards, and appending changes its sha256.
  //
  // This used to be resolved by searching history for ANY commit that ever held the approved digest
  // and passing if one was found. That accepts an append — and accepts a substantive rewrite of the
  // approved text just as readily, because both leave the old bytes somewhere in history. The
  // digest then pins nothing at HEAD, which is the only place anyone reads the document.
  //
  // What is checked instead: the document ABOVE the execution-record marker must still hash to the
  // approved digest, at HEAD. PCCR-006 states this rule in its own appendix — "Everything above this
  // line is what the founder approved and it is unchanged" — and it is now enforced rather than
  // asserted. One byte edited above the marker fails this check; the appendix below it is free.
  if (!ok) {
    const body = approvedBodyOf(path);
    if (body && sha256(body) === r.approved_amendment_table_digest) {
      ok = true;
      where = `the approved body of ${path} at HEAD (execution record appended below the marker)`;
    }
  }

  // History is now DIAGNOSIS ONLY. It says which commit last held the approved bytes so a reader
  // can see what was changed and when; it can no longer make this check pass.
  if (!ok) {
    const found = commitCarrying(path, r.approved_amendment_table_digest);
    whyNot = found.at
      ? `EDITED_SINCE_APPROVAL_AT_${found.at}`
      : found.why;
  }
  console.log(`${line}  ${ok ? 'matches' : 'DIFFERS FROM'} ${where}`
    + `  (route ${r.approval_route ?? '(none)'}, subject ${r.approval_auth_subject})${basis}`);
  if (!ok) {
    // WHICH FACT THIS IS. "The clone cannot see it" and "it never existed" are different findings
    // and only one of them is about the estate.
    const explain = {
      SHALLOW_CLONE: 'this is a SHALLOW clone, so the history that would carry it is not here. '
        + 'The job needs actions/checkout with fetch-depth: 0. This says nothing about the estate.',
      GIT_UNAVAILABLE: 'git could not be run here, so history could not be searched at all. '
        + 'This says nothing about the estate.',
      NOT_IN_FIRST_400: 'it is not among the 400 most recent commits touching that path; the search '
        + 'is bounded and stopped there rather than pretending to be exhaustive.',
      NO_COMMIT_EVER_HELD_IT: 'and no commit in this repository has ever held that path at that '
        + 'digest, which IS a finding about the estate.',
    }[whyNot] ?? (String(whyNot).startsWith('EDITED_SINCE_APPROVAL_AT_')
      ? `and the document HAS BEEN EDITED SINCE HE APPROVED IT. The approved bytes were last held at `
        + `commit ${String(whyNot).replace('EDITED_SINCE_APPROVAL_AT_', '')}, and neither the file at `
        + `HEAD nor its body above the execution-record marker reproduces them. A digest that only `
        + `matches something in history pins nothing at HEAD, which is the only place the document `
        + `is read. Either restore the approved text, or reissue the approval against the new digest.`
      : String(whyNot));
    fail.push(`amendment ${r.amendment_id} was approved against document digest `
      + `${r.approved_amendment_table_digest} for ${path} (working tree: ${live ?? 'file absent'}) -- `
      + explain);
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
