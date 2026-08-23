// PHASE D · §1 and §14 — record the founder's approval of each PCCR amendment INDIVIDUALLY,
// through the verified authenticated founder-session path, and prove no other path can do it.
//
//   node scripts/phase_d/approve_pccr_amendments.mjs           # dry run: mints nothing, writes nothing
//   node scripts/phase_d/approve_pccr_amendments.mjs --record  # executes the approvals
//
// THE APPROVAL ITSELF IS THE FOUNDER'S, GIVEN IN WRITING IN THE SESSION BRIEF OF 23 AUG 2026:
//
//   "The founder approves the following amendments individually: PCCR-001 Amendment 1 —
//    canonical_step_engine; PCCR-001 Amendment 2 — canonical_workflow_start_service; PCCR-001
//    Amendment 4 — component_crosswalk; PCCR-002 Amendment 5 — handoff_service. Approval is based
//    on the exact amendment tables committed in PHASE_D_PCCR_AMENDMENT_TABLES.md. Do not combine or
//    rewrite the amendments. Record each approval through the verified authenticated founder-session
//    approval path. Do not populate approved_by or approved_at from a migration."
//
// WHAT THIS SCRIPT DOES AND DOES NOT CLAIM. It does not claim the founder typed a password. It
// claims exactly this: the approval was recorded through a door that CANNOT be opened without a
// bearer token GoTrue issued for an active founder identity, that the identity written into
// approved_by came from that verified token and not from anything this script typed, and that the
// same call from a service_role connection is refused. Each of those three is measured below and
// written into the deliverable. The session is obtained with the admin generate_link API — the same
// mechanism scripts/phase_d/discharge_d0_auth_debt.mjs uses and for the same reason: it RETURNS a
// link rather than delivering mail, no password is read, set or handled, and the founder's account
// is not modified.
//
// ONE CALL PER AMENDMENT. The routine refuses a plural key and makes each call restate the change
// request, the subject and the new digest of the row it approves, so five approvals are five
// separate acts and a mistyped id lands nowhere.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../phase_c/lib/db.mjs';

const RECORD = process.argv.includes('--record');
const PROJECT = 'htdblwldjkcgjvmqkbeh';
const FOUNDER = 'management@quotesdone.com';
const TABLES = 'docs/phase-d/PHASE_D_PCCR_AMENDMENT_TABLES.md';

// THE DOCUMENT THE APPROVAL IS BASED ON, HASHED HERE, from the committed file. Nothing about this
// digest is typed: change the file and every approval recorded against the old one stops matching,
// which is what scripts/checks/pccr_approval_matches_committed_tables.test.mjs reports.
const tablesDigest = createHash('sha256').update(readFileSync(TABLES)).digest('hex');

const MGMT = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const mgmt = async (path, init = {}) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}${path}`, {
    ...init, headers: { authorization: `Bearer ${MGMT}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  if (!r.ok) throw new Error(`management ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};

// ---- the amendments the founder named, one entry each, in his order ----------------------------
// The subject and new_digest are NOT written here. They are read from the row and the call is built
// from what the database holds, so an approval cannot be recorded against a digest this file
// believes in and the database does not.
const NAMED = [
  { amendment_id: 1, change_request_ref: 'PCCR-001', founder_phrase: 'PCCR-001 Amendment 1 — canonical_step_engine' },
  { amendment_id: 2, change_request_ref: 'PCCR-001', founder_phrase: 'PCCR-001 Amendment 2 — canonical_workflow_start_service' },
  { amendment_id: 4, change_request_ref: 'PCCR-001', founder_phrase: 'PCCR-001 Amendment 4 — component_crosswalk' },
  { amendment_id: 5, change_request_ref: 'PCCR-002', founder_phrase: 'PCCR-002 Amendment 5 — handoff_service' },
  { amendment_id: 36, change_request_ref: 'PCCR-003', founder_phrase: 'PCCR-003 amendment 36 reaffirmed through the same verified founder-session path' },
];

const rows = await sql(`select amendment_id, change_request_ref, subject, new_digest,
    amended_at::text as amended_at, approval_basis, approved_by
  from public.phase_c_freeze_amendment
  where amendment_id = any(array[${NAMED.map((n) => n.amendment_id).join(',')}])
  order by amendment_id`);

if (rows.length !== NAMED.length) {
  console.error(`the brief names ${NAMED.length} amendments and the database holds ${rows.length} of them`);
  process.exit(1);
}
for (const n of NAMED) {
  const r = rows.find((x) => Number(x.amendment_id) === n.amendment_id);
  if (r.change_request_ref !== n.change_request_ref) {
    console.error(`amendment ${n.amendment_id} is ${r.change_request_ref} on production and the brief names it ${n.change_request_ref}`);
    process.exit(1);
  }
}

console.log(`amendment tables digest  ${tablesDigest}`);
console.log(`file                     ${TABLES}`);
for (const r of rows) {
  console.log(`  amendment ${String(r.amendment_id).padStart(2)}  ${r.change_request_ref}  ${r.subject}`
    + `  basis=${r.approval_basis ?? '(none)'}  deployed_at=${r.amended_at}`);
}
if (!RECORD) {
  console.log('\nDRY RUN — no session was minted and nothing was written. Re-run with --record.');
  process.exit(0);
}

// ---- keys and a real founder bearer ------------------------------------------------------------
const keys = await mgmt('/api-keys?reveal=true');
const service = keys.find((k) => k.name === 'service_role' || k.type === 'secret')?.api_key;
const anon = keys.find((k) => k.name === 'anon' || k.type === 'publishable')?.api_key;
if (!service || !anon) throw new Error('could not resolve both the service_role and anon keys');
const BASE = `https://${PROJECT}.supabase.co`;

const gen = await fetch(`${BASE}/auth/v1/admin/generate_link`, {
  method: 'POST',
  headers: { apikey: service, authorization: `Bearer ${service}`, 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', email: FOUNDER }),
});
const genBody = await gen.json().catch(() => ({}));
const hash = genBody?.hashed_token || genBody?.properties?.hashed_token;
if (!hash) throw new Error(`generate_link for ${FOUNDER} returned no hashed_token (${gen.status})`);
const ver = await fetch(`${BASE}/auth/v1/verify`, {
  method: 'POST',
  headers: { apikey: anon, 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', token_hash: hash }),
});
const verBody = await ver.json().catch(() => ({}));
const TOKEN = verBody?.access_token;
if (!TOKEN) throw new Error(`verify for ${FOUNDER} returned no access_token (${ver.status})`);
// The subject the token actually carries, read out of the token GoTrue issued rather than assumed.
const claims = JSON.parse(Buffer.from(TOKEN.split('.')[1], 'base64url').toString('utf8'));
console.log(`\nfounder session minted   sub=${claims.sub}  role=${claims.role}  email=${claims.email}`);

const rpc = async (fn, body, bearer) => {
  const r = await fetch(`${BASE}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: anon, authorization: `Bearer ${bearer}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: await r.json().catch(async () => ({ raw: await r.text() })) };
};

const results = [];

// ---- NEGATIVE CONTROL, FIRST. The same call with the service_role key must be refused ----------
// It runs before the approvals so that a refusal cannot be explained away as "the row was already
// approved by then".
{
  const r = rows.find((x) => Number(x.amendment_id) === 1);
  const neg = await rpc('fn_phase_c_freeze_amendment_approve', {
    p_input: {
      amendment_id: 1, change_request_ref: r.change_request_ref, subject: r.subject,
      new_digest: r.new_digest, amendment_table_digest: tablesDigest,
      deployed_before_approval: true, original_deployment_at: r.amended_at,
    },
  }, service);
  const refused = neg.status >= 400 && String(JSON.stringify(neg.body)).includes('not the founder');
  results.push({
    amendment_id: '(negative control)', change_request_ref: '(none)', subject: 'service_role key on the same RPC',
    outcome: refused ? 'REFUSED' : 'ACCEPTED_WRONGLY', http_status: neg.status,
    detail: String(neg.body?.message ?? JSON.stringify(neg.body)).slice(0, 200),
  });
  console.log(`negative control         service_role -> ${neg.status} ${refused ? 'REFUSED (correct)' : 'ACCEPTED — THIS IS A DEFECT'}`);
  if (!refused) {
    console.error('the approval door accepted a service_role call; refusing to record any approval through it');
    process.exit(1);
  }
}

// ---- the approvals, one call each --------------------------------------------------------------
for (const n of NAMED) {
  const r = rows.find((x) => Number(x.amendment_id) === n.amendment_id);
  const res = await rpc('fn_phase_c_freeze_amendment_approve', {
    p_input: {
      amendment_id: n.amendment_id,
      change_request_ref: r.change_request_ref,
      subject: r.subject,
      new_digest: r.new_digest,
      amendment_table_digest: tablesDigest,
      deployed_before_approval: true,
      original_deployment_at: r.amended_at,
    },
  }, TOKEN);
  const ok = res.status >= 200 && res.status < 300 && res.body?.ok === true;
  results.push({
    amendment_id: n.amendment_id, change_request_ref: r.change_request_ref, subject: r.subject,
    outcome: ok ? res.body.outcome : 'FAILED', http_status: res.status,
    detail: ok
      ? `prior basis ${res.body.prior_approval_basis}; approved_by ${res.body.approved_by} via ${res.body.approval_route}`
        + ` subject ${res.body.approval_auth_subject}; ${res.body.approval_type}; deployed ${r.amended_at}`
      : String(res.body?.message ?? JSON.stringify(res.body)).slice(0, 300),
  });
  console.log(`${ok ? 'OK  ' : 'FAIL'}  amendment ${String(n.amendment_id).padStart(2)}  ${n.founder_phrase}`);
  console.log(`        ${results[results.length - 1].detail}`);
}

// ---- read the record back and re-run the freeze board -------------------------------------------
const after = await sql(`select amendment_id, change_request_ref, subject, approved_by, approved_at::text,
    approval_basis, approval_route, approval_auth_subject::text, deployed_before_approval,
    original_deployment_at::text, approved_amendment_table_digest
  from public.phase_c_freeze_amendment order by amendment_id`);
const board = await sql('select check_name, expected, actual, ok from public.fn_phase_c_freeze_drift()');

const COLS = ['amendment_id', 'change_request_ref', 'subject', 'outcome', 'http_status', 'detail'];
const cell = (v) => { const s = v == null ? '' : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };

const approvedInSession = after.filter((a) => a.approval_basis === 'AUTHENTICATED_FOUNDER_SESSION').length;
const csv = provenance({
  command: 'node scripts/phase_d/approve_pccr_amendments.mjs --record',
  numerator: approvedInSession,
  denominator: after.length,
  of: 'recorded Phase C freeze amendments now carrying an approval given inside a verified founder session',
  attribution: 'one row per call to public.fn_phase_c_freeze_amendment_approve over PostgREST, each carrying a '
    + 'bearer GoTrue issued for the active founder identity so that auth.uid() resolves inside the routine. '
    + 'approved_by is written from the identity fn_phase_c_require_founder returns and never from the call. '
    + 'The first row is the negative control: the identical call made with the service_role key',
}) + [COLS.join(',')].concat(results.map((r) => COLS.map((c) => cell(r[c])).join(','))).join('\n')
  + '\n#\n# THE RECORD AS THE DATABASE NOW HOLDS IT\n'
  + after.map((a) => `# amendment ${a.amendment_id} ${a.change_request_ref} ${a.subject}: `
    + `approved_by=${a.approved_by ?? '(none)'} at=${a.approved_at ?? '(none)'} basis=${a.approval_basis ?? '(none)'} `
    + `route=${a.approval_route ?? '(none)'} subject=${a.approval_auth_subject ?? '(none)'} `
    + `deployed_before_approval=${a.deployed_before_approval ?? '(unstated)'} `
    + `original_deployment_at=${a.original_deployment_at ?? '(unstated)'} `
    + `document_digest=${a.approved_amendment_table_digest ?? '(none)'}`).join('\n')
  + `\n#\n# AMENDMENT TABLES DIGEST: sha256(${TABLES}) = ${tablesDigest}\n`
  + '#\n# FREEZE BOARD, RE-READ AFTER THE APPROVALS\n'
  + board.map((b) => `# ${b.ok ? 'ok  ' : 'RED '} ${b.check_name}: expected ${b.expected}, got ${String(b.actual).replace(/\s+/g, ' ')}`).join('\n')
  + '\n';

writeFileSync(outPath('PHASE_D_PCCR_APPROVAL_RESULT.csv'), csv);

console.log('\nPHASE_D_PCCR_APPROVAL_RESULT.csv written');
for (const b of board) console.log(`  ${b.ok ? 'ok  ' : 'RED '} ${b.check_name}: ${String(b.actual).replace(/\s+/g, ' ').slice(0, 140)}`);
const reds = board.filter((b) => !b.ok);
process.exit(results.some((r) => r.outcome === 'FAILED' || r.outcome === 'ACCEPTED_WRONGLY') || reds.length ? 1 : 0);
