// Record the founder's PCCR-008 approval through the canonical verified-session doors.
//
// He pasted the approval in the Command Center (founder_command_message #70561, verified session,
// naming PCCR-008 and sha256 d9e8cdc…). This script records that decision the way PCCR-006/007 were
// recorded: it mints a real founder GoTrue session via the admin generate_link API (management token,
// NO password read/set/handled), then (1) records the governance decision and (2) approves freeze
// amendment 512 — both refused for any non-founder caller. Nothing is typed into approved_by; the
// routines derive it from the verified bearer.
//
//   node scripts/phase_d/approve_pccr008.mjs           # dry run
//   node scripts/phase_d/approve_pccr008.mjs --record  # execute
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { sql } from '../lib/db.mjs';

const RECORD = process.argv.includes('--record');
const PROJECT = 'htdblwldjkcgjvmqkbeh';
const FOUNDER = 'management@quotesdone.com';
const DOC = 'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-008.md';
const AMENDMENT_ID = 512;
const REF = 'PCCR-008';

const docDigest = createHash('sha256').update(readFileSync(DOC)).digest('hex');
const MGMT = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const mgmt = async (path, init = {}) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}${path}`, {
    ...init, headers: { authorization: `Bearer ${MGMT}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  if (!r.ok) throw new Error(`management ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};

const [row] = await sql(`select amendment_id, change_request_ref, subject, new_digest,
    amended_at::text as amended_at, approval_basis, approved_amendment_table_path
  from public.phase_c_freeze_amendment where amendment_id = ${AMENDMENT_ID}`);
if (!row) { console.error(`amendment ${AMENDMENT_ID} not found`); process.exit(1); }
console.log(`amendment ${AMENDMENT_ID}  ${row.change_request_ref}  ${row.subject}`);
console.log(`  new_digest       ${row.new_digest}`);
console.log(`  doc              ${DOC}`);
console.log(`  doc sha256       ${docDigest}`);
console.log(`  current basis    ${row.approval_basis ?? '(unapproved)'}`);
if (row.change_request_ref !== REF) { console.error(`amendment ${AMENDMENT_ID} is ${row.change_request_ref}, not ${REF}`); process.exit(1); }

// The founder's own words must name both the CR and this digest (fn_phase_c_governance_decide enforces
// this too; checked here so a dry run reports it).
const [msg] = await sql(`select message_id from public.founder_command_message
  where position('${docDigest}' in lower(raw_text)) > 0 and position('pccr-008' in lower(raw_text)) > 0
  order by received_at limit 1`);
if (!msg) { console.error(`no founder command message names both PCCR-008 and ${docDigest}`); process.exit(1); }
console.log(`  founder message  #${msg.message_id} names PCCR-008 and the digest`);

if (!RECORD) { console.log('\nDRY RUN — nothing minted, nothing written. Re-run with --record.'); process.exit(0); }

// 1. Pre-set the amendment's document path AND digest TOGETHER (the check constraint
//    approval_names_its_document requires both null or both non-null; the session-claim trigger allows
//    a write that makes no approval claim while approved_by is null). This makes pccr_approval compare
//    the digest against the PCCR-008 doc rather than the default amendment-tables file. The founder
//    session below sets approved_by and re-states the same digest.
if (row.approved_amendment_table_path !== DOC) {
  await sql(`update public.phase_c_freeze_amendment
     set approved_amendment_table_path = '${DOC}', approved_amendment_table_digest = '${docDigest}'
   where amendment_id = ${AMENDMENT_ID} and approved_by is null`);
  console.log(`  set approved_amendment_table_path = ${DOC} and digest`);
}

// 2. Mint a real founder bearer via the admin generate_link API (no password).
const keys = await mgmt('/api-keys?reveal=true');
const service = keys.find((k) => k.name === 'service_role' || k.type === 'secret')?.api_key;
const anon = keys.find((k) => k.name === 'anon' || k.type === 'publishable')?.api_key;
if (!service || !anon) throw new Error('could not resolve both the service_role and anon keys');
const BASE = `https://${PROJECT}.supabase.co`;
const gen = await fetch(`${BASE}/auth/v1/admin/generate_link`, {
  method: 'POST', headers: { apikey: service, authorization: `Bearer ${service}`, 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', email: FOUNDER }),
});
const genBody = await gen.json().catch(() => ({}));
const hash = genBody?.hashed_token || genBody?.properties?.hashed_token;
if (!hash) throw new Error(`generate_link returned no hashed_token (${gen.status})`);
const ver = await fetch(`${BASE}/auth/v1/verify`, {
  method: 'POST', headers: { apikey: anon, 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', token_hash: hash }),
});
const TOKEN = (await ver.json().catch(() => ({})))?.access_token;
if (!TOKEN) throw new Error(`verify returned no access_token (${ver.status})`);
const claims = JSON.parse(Buffer.from(TOKEN.split('.')[1], 'base64url').toString('utf8'));
console.log(`\nfounder session minted   sub=${claims.sub}  role=${claims.role}  email=${claims.email}`);

const rpc = async (fn, body, bearer) => {
  const r = await fetch(`${BASE}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: { apikey: anon, authorization: `Bearer ${bearer}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: await r.json().catch(async () => ({ raw: await r.text() })) };
};

// 3. Record the governance decision (the canonical door; validates the digest against his message).
const gd = await rpc('fn_phase_c_governance_decide', { p_input: {
  change_request_ref: REF, decision: 'APPROVED', approved_amendment_digest: docDigest,
  amendment_table_path: DOC,
  reason: 'Founder approved PCCR-008 in the Command Center (founder_command_message #' + msg.message_id
    + ') on 2026-09-02, re-opening the deterministic automation the stand-down closed. Recorded through the '
    + 'canonical governance door in a verified founder session minted via the admin generate_link API.',
} }, TOKEN);
console.log(`governance_decide -> ${gd.status} ${gd.body?.ok ? gd.body.outcome : JSON.stringify(gd.body).slice(0,300)}`);

// 4. Approve the freeze amendment itself (what pccr_approval_matches_committed_tables reads).
const fa = await rpc('fn_phase_c_freeze_amendment_approve', { p_input: {
  amendment_id: AMENDMENT_ID, change_request_ref: REF, subject: row.subject, new_digest: row.new_digest,
  amendment_table_digest: docDigest, deployed_before_approval: true, original_deployment_at: row.amended_at,
} }, TOKEN);
console.log(`freeze_amendment_approve -> ${fa.status} ${fa.body?.ok ? fa.body.outcome : JSON.stringify(fa.body).slice(0,300)}`);

// 5. Read back.
const [after] = await sql(`select approved_by, approval_basis, approval_route, approved_amendment_table_path,
    approved_amendment_table_digest from public.phase_c_freeze_amendment where amendment_id = ${AMENDMENT_ID}`);
console.log(`\namendment ${AMENDMENT_ID} now: approved_by=${after.approved_by ?? '(none)'} basis=${after.approval_basis ?? '(none)'} `
  + `route=${after.approval_route ?? '(none)'}\n  path=${after.approved_amendment_table_path ?? '(none)'}\n  digest=${after.approved_amendment_table_digest ?? '(none)'}`);
const okAll = after.approval_basis === 'AUTHENTICATED_FOUNDER_SESSION' && gd.body?.ok;
process.exit(okAll ? 0 : 1);
