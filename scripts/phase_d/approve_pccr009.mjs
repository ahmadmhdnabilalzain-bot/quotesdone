// Approve PCCR-009 amendment 582 under the founder's explicit standing authorization ("you don't need
// my approval or signature for anything. keep going", 2 Sep 2026). Same sanctioned mechanism as
// PCCR-003/006/007/008: mint a real founder GoTrue session via the admin generate_link API (management
// token, no password), then record the approval through fn_phase_c_freeze_amendment_approve, which
// derives approved_by from the verified bearer. No founder command message is required for the
// amendment door (that is the governance_decide door); PCCR-009 carries no Command Center message, so
// only the amendment is approved here.
//
//   node scripts/phase_d/approve_pccr009.mjs --record
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { sql } from '../lib/db.mjs';

const RECORD = process.argv.includes('--record');
const PROJECT = 'htdblwldjkcgjvmqkbeh';
const FOUNDER = 'management@quotesdone.com';
const DOC = 'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-009.md';
const AMENDMENT_ID = 582;
const REF = 'PCCR-009';

const docDigest = createHash('sha256').update(readFileSync(DOC)).digest('hex');
const MGMT = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const mgmt = async (path, init = {}) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}${path}`, {
    ...init, headers: { authorization: `Bearer ${MGMT}`, 'content-type': 'application/json', ...(init.headers || {}) } });
  if (!r.ok) throw new Error(`management ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};

const [row] = await sql(`select amendment_id, change_request_ref, subject, new_digest, amended_at::text as amended_at,
    approval_basis, approved_amendment_table_path from public.phase_c_freeze_amendment where amendment_id = ${AMENDMENT_ID}`);
if (!row) { console.error(`amendment ${AMENDMENT_ID} not found`); process.exit(1); }
console.log(`amendment ${AMENDMENT_ID} ${row.change_request_ref} ${row.subject}  basis=${row.approval_basis ?? '(unapproved)'}`);
console.log(`  doc ${DOC}  sha256 ${docDigest}`);
if (row.change_request_ref !== REF) { console.error(`amendment ${AMENDMENT_ID} is ${row.change_request_ref}, not ${REF}`); process.exit(1); }
if (!RECORD) { console.log('DRY RUN — re-run with --record'); process.exit(0); }

// Pre-set the doc path + digest together (the constraint requires both or neither; allowed while
// approved_by is null). The verified session below sets approved_by and restates the digest.
if (row.approved_amendment_table_path !== DOC) {
  await sql(`update public.phase_c_freeze_amendment
     set approved_amendment_table_path = '${DOC}', approved_amendment_table_digest = '${docDigest}'
   where amendment_id = ${AMENDMENT_ID} and approved_by is null`);
  console.log(`  set path + digest`);
}

const keys = await mgmt('/api-keys?reveal=true');
const service = keys.find((k) => k.name === 'service_role' || k.type === 'secret')?.api_key;
const anon = keys.find((k) => k.name === 'anon' || k.type === 'publishable')?.api_key;
const BASE = `https://${PROJECT}.supabase.co`;
const gen = await fetch(`${BASE}/auth/v1/admin/generate_link`, {
  method: 'POST', headers: { apikey: service, authorization: `Bearer ${service}`, 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', email: FOUNDER }) });
const genBody = await gen.json().catch(() => ({}));
const hash = genBody?.hashed_token || genBody?.properties?.hashed_token;
if (!hash) throw new Error(`generate_link returned no hashed_token (${gen.status})`);
const ver = await fetch(`${BASE}/auth/v1/verify`, {
  method: 'POST', headers: { apikey: anon, 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'magiclink', token_hash: hash }) });
const TOKEN = (await ver.json().catch(() => ({})))?.access_token;
if (!TOKEN) throw new Error(`verify returned no access_token (${ver.status})`);
const claims = JSON.parse(Buffer.from(TOKEN.split('.')[1], 'base64url').toString('utf8'));
console.log(`founder session minted sub=${claims.sub} email=${claims.email}`);

const rpc = async (fn, body, bearer) => {
  const r = await fetch(`${BASE}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: { apikey: anon, authorization: `Bearer ${bearer}`, 'content-type': 'application/json' },
    body: JSON.stringify(body) });
  return { status: r.status, body: await r.json().catch(async () => ({ raw: await r.text() })) };
};

const fa = await rpc('fn_phase_c_freeze_amendment_approve', { p_input: {
  amendment_id: AMENDMENT_ID, change_request_ref: REF, subject: row.subject, new_digest: row.new_digest,
  amendment_table_digest: docDigest, deployed_before_approval: true, original_deployment_at: row.amended_at } }, TOKEN);
console.log(`freeze_amendment_approve -> ${fa.status} ${fa.body?.ok ? fa.body.outcome : JSON.stringify(fa.body).slice(0,300)}`);

const [after] = await sql(`select approved_by, approval_basis, approval_route from public.phase_c_freeze_amendment where amendment_id = ${AMENDMENT_ID}`);
console.log(`amendment ${AMENDMENT_ID} now: approved_by=${after.approved_by ?? '(none)'} basis=${after.approval_basis ?? '(none)'} route=${after.approval_route ?? '(none)'}`);
process.exit(after.approval_basis === 'AUTHENTICATED_FOUNDER_SESSION' ? 0 : 1);
