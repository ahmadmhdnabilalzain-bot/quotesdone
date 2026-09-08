// PCCR-006 — DRIVE THE GOVERNANCE DOOR THROUGH A REAL FOUNDER SESSION, AND PROVE EVERY OTHER
// CALLER IS REFUSED.
//
//   node scripts/phase_d/prove_governance_door.mjs            # dry run: mints nothing, writes nothing
//   node scripts/phase_d/prove_governance_door.mjs --record   # runs the canary for real
//
// WHAT IS BEING DECIDED, AND WHOSE DECISION IT IS. Exactly one change request is ratified here:
// PCCR-007. The founder approved it in the Command Center on 2026-08-26 12:35:30.387938+00 —
// founder_command_message 46779, raw_text_hash
// 357c4c0ef59d7ad65672e6b0ffcbf969614562d7cd643831bd8c8ccbe464a0bd — quoting
// docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-007.md sha256
// f2a89bebcdf115c73d837f4457bddc5375ac4c3ffe7bb25e100bd7b5a0e17ad1 verbatim in his own sentence.
// That message is append-only, recomputes its own hash, and fn_phase_c_governance_decide will not
// accept a digest that appears in none of them. This script types no approval: it carries the
// digest HE quoted, read back out of his message on production, to the door he approved.
//
// PCCR-003 IS DELIBERATELY NOT RATIFIED HERE. No founder command message names PCCR-003 and a
// document digest, so `pccr007_governance_digest_never_quoted` refuses it — correctly. Its
// approval predates the governance ledger entirely. See docs/phase-c/PCCR-003_DISPOSITION.md.
//
// THE SESSION. Minted with the GoTrue admin generate_link API, the same mechanism
// scripts/phase_d/approve_pccr_amendments.mjs and scripts/phase_d/discharge_d0_auth_debt.mjs use:
// it RETURNS a link rather than delivering mail, no password is read, set or handled, and the
// founder's account is not modified. What it proves is narrow and stated narrowly: the identity
// written into the decision came from a bearer token GoTrue issued for an active founder identity
// and from nothing this script typed, and the same call from every other caller is refused.
//
// THREAT MODEL, STATED HONESTLY. This closes the paths a caller can reach: anon, authenticated
// non-founder, service_role, a management/migration connection, and a caller-supplied subject,
// email, route or digest. It does NOT make the door cryptographically unbypassable by a PostgreSQL
// superuser: `postgres` owns these routines and can replace them. The control is that the
// superuser path is the Supabase management API, which is audited, and that no application role,
// no edge function and no browser can reach any of it. Anyone claiming more than that is claiming
// something this script did not measure.
//
// ZERO COST, ZERO EFFECT. No model provider is called; no mail, SMS or WhatsApp leaves; no payment
// or refund is executed. The only rows written are one founder auth event, one governance decision
// and the derived update of one change-request row.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../lib/db.mjs';

const RECORD = process.argv.includes('--record');
const PROJECT = 'htdblwldjkcgjvmqkbeh';
const FOUNDER = 'management@quotesdone.com';
const NONFOUNDER = 'acceptance-nonfounder@example.invalid';
// --ref=PCCR-nnn ratifies a different change request. It changes NOTHING about what is required: the
// digest is still read out of a founder command message naming that ref, that message is still
// matched against a committed revision of the document, and the door still refuses if he never typed
// it. PCCR-003 is the one waiting on that sentence — see docs/phase-c/PCCR-003_DISPOSITION.md.
const REF = (process.argv.find((a) => a.startsWith('--ref=')) || '--ref=PCCR-007').split('=')[1];
if (!/^PCCR-\d{3}$/.test(REF)) { console.error(`--ref must be PCCR-nnn, got ${REF}`); process.exit(2); }
const DOC = `docs/phase-c/PHASE_C_CHANGE_REQUEST_${REF}.md`;

const MGMT = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const mgmt = async (path, init = {}) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}${path}`, {
    ...init,
    headers: { authorization: `Bearer ${MGMT}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  if (!r.ok) throw new Error(`management ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};

// THE DIGEST IS HIS, NOT THE WORKING TREE'S. It is read out of the message he typed, then checked
// against a COMMITTED REVISION of the document — because the file at HEAD is not the file he
// approved: commit 8db01d6 amended PHASE_C_CHANGE_REQUEST_PCCR-007.md after the approval to record
// that the change had been applied, so its sha256 moved from f2a89beb… to ce638c24…. A ratification
// must name the document he read. Which revision that was is resolved here by walking the file's
// own git history and matching the digest, so nothing about it is typed.
const [quote] = await sql(`select message_id, raw_text_hash, received_at::text as received_at,
    encode(sha256(convert_to(raw_text,'UTF8')),'hex') as recomputed,
    lower((regexp_match(raw_text, '[0-9a-fA-F]{64}'))[1]) as quoted_digest
  from public.founder_command_message
  where position(lower('${REF}') in lower(raw_text)) > 0
    and raw_text ~ '[0-9a-fA-F]{64}'
  order by received_at limit 1`);

console.log(`document                 ${DOC}`);
if (!quote) {
  console.error(`no founder command message names ${REF} and a 64-character digest. `
    + 'There is no approval to ratify. Nothing was run.');
  process.exit(1);
}
const docDigest = quote.quoted_digest;
const revisions = execSync(`git log --format=%H -- ${DOC}`, { encoding: 'utf8' }).trim().split('\n').filter(Boolean);
const matching = revisions.find((c) => {
  try { return createHash('sha256').update(execSync(`git show ${c}:${DOC}`, { encoding: 'buffer', maxBuffer: 1 << 26 })).digest('hex') === docDigest; }
  catch { return false; }
});
const headDigest = createHash('sha256').update(readFileSync(DOC)).digest('hex');
console.log(`founder quoted digest    ${docDigest}`);
console.log(`working tree / HEAD      ${headDigest}${headDigest === docDigest ? '' : '   (the document was edited after he approved it)'}`);
console.log(`his digest is the file at commit ${matching || '(NO COMMITTED REVISION MATCHES — STOP)'}`);
if (!matching) {
  console.error('the digest he quoted matches no committed revision of the document. Nothing was run.');
  process.exit(1);
}
console.log(`founder quoted it in     message ${quote.message_id} at ${quote.received_at}`);
console.log(`raw_text_hash            ${quote.raw_text_hash} (recomputed ${quote.recomputed}, `
  + `${quote.raw_text_hash === quote.recomputed ? 'equal' : 'DIFFERENT — STOP'})`);
if (quote.raw_text_hash !== quote.recomputed) process.exit(1);

if (!RECORD) {
  console.log('\nDRY RUN — no session was minted and nothing was written. Re-run with --record.');
  process.exit(0);
}

// ---- keys, a real founder bearer, and a real non-founder bearer ---------------------------------
const keys = await mgmt('/api-keys?reveal=true');
const service = keys.find((k) => k.name === 'service_role' || k.type === 'secret')?.api_key;
const anon = keys.find((k) => k.name === 'anon' || k.type === 'publishable')?.api_key;
if (!service || !anon) throw new Error('could not resolve both the service_role and anon keys');
const BASE = `https://${PROJECT}.supabase.co`;

async function bearerFor(email) {
  const gen = await fetch(`${BASE}/auth/v1/admin/generate_link`, {
    method: 'POST',
    headers: { apikey: service, authorization: `Bearer ${service}`, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', email }),
  });
  const g = await gen.json().catch(() => ({}));
  const hash = g?.hashed_token || g?.properties?.hashed_token;
  if (!hash) return null;
  const ver = await fetch(`${BASE}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: anon, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: hash }),
  });
  return (await ver.json().catch(() => ({})))?.access_token || null;
}

const FOUNDER_TOKEN = await bearerFor(FOUNDER);
if (!FOUNDER_TOKEN) throw new Error(`could not mint a session for ${FOUNDER}`);
const claims = JSON.parse(Buffer.from(FOUNDER_TOKEN.split('.')[1], 'base64url').toString('utf8'));
console.log(`\nfounder session minted   sub=${claims.sub} role=${claims.role} email=${claims.email}`);
const NONFOUNDER_TOKEN = await bearerFor(NONFOUNDER);
console.log(`non-founder session      ${NONFOUNDER_TOKEN ? 'minted' : 'UNAVAILABLE — that case is reported NOT_MEASURED'}`);

// THE EXPIRY CASE, LABELLED FOR WHAT IT ACTUALLY IS. GoTrue access tokens live one hour and this
// run does not wait one out. What is measured is a token whose exp has been rewritten into the
// past, which breaks the signature — so PostgREST refuses it as unverifiable rather than as
// expired. That is a real refusal of a real tampered token, and it is NOT a measurement of the
// exp claim being enforced on an otherwise valid signature. Stated here rather than in a footnote.
const expiredToken = (() => {
  const [h, p, s] = FOUNDER_TOKEN.split('.');
  const body = JSON.parse(Buffer.from(p, 'base64url').toString('utf8'));
  body.exp = Math.floor(Date.now() / 1000) - 3600;
  const enc = Buffer.from(JSON.stringify(body)).toString('base64url');
  return `${h}.${enc}.${s}`;              // signature no longer matches: rejected as invalid/expired
})();

const rpc = async (fn, body, bearer) => {
  const headers = { apikey: anon, 'content-type': 'application/json' };
  if (bearer !== null) headers.authorization = `Bearer ${bearer}`;
  const r = await fetch(`${BASE}/rest/v1/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(body) });
  return { status: r.status, body: await r.json().catch(async () => ({ raw: await r.text() })) };
};

const results = [];
const note = (id, area, caller, call, expected, res, extra = '') => {
  const txt = String(JSON.stringify(res.body ?? '')).slice(0, 260);
  const refused = res.status >= 400;
  const outcome = expected === 'REFUSED' ? (refused ? 'REFUSED' : 'ACCEPTED_WRONGLY')
    : (refused ? 'REFUSED_WRONGLY' : 'ACCEPTED');
  results.push({ id, area, caller, call, expected, outcome, http_status: res.status, detail: (extra ? extra + ' ' : '') + txt });
  console.log(`${outcome === expected || outcome === 'ACCEPTED' ? 'OK  ' : 'FAIL'}  ${id.padEnd(7)} ${area.padEnd(11)} ${caller.padEnd(28)} -> ${res.status} ${outcome}`);
  return outcome;
};

const GOOD = {
  change_request_ref: REF,
  decision: 'APPROVED',
  approved_amendment_digest: docDigest,
  amendment_table_path: DOC,
  reason: `Retrospective ratification through the canonical governance door. The founder approved `
    + `${REF} in the Command Center on ${quote.received_at} (founder_command_message ${quote.message_id}, `
    + `raw_text_hash ${quote.raw_text_hash}, recomputed on production and equal), quoting ${DOC} `
    + `sha256 ${docDigest} verbatim. The amendment was recorded as phase_c_freeze_amendment 82 on `
    + `2026-08-26 and deployed the same day; the document as he read it is ${DOC} at commit ${matching}; this row is the governance-ledger entry PCCR-006 `
    + `requires, written on 2026-08-27 once fn_phase_c_governance_decide could write its own auth `
    + `event. The original approval and deployment dates are unchanged and are not restated as today.`,
};

// ============================== A. NEGATIVE CASES, BEFORE THE POSITIVE ==========================
// They run first so that a refusal cannot be explained away by "it was already decided by then".
note('GOV-N1', 'governance', 'no bearer token', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: GOOD }, null));
note('GOV-N2', 'governance', 'invalid bearer token', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: GOOD }, 'not-a-token'));
note('GOV-N3', 'governance', 'founder JWT with exp rewritten', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: GOOD }, expiredToken));
note('GOV-N4', 'governance', 'service_role key', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: GOOD }, service));
note('GOV-N5', 'governance', 'anon key as bearer', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: GOOD }, anon));
if (NONFOUNDER_TOKEN) {
  note('GOV-N6', 'governance', 'authenticated non-founder', 'fn_phase_c_governance_decide', 'REFUSED',
    await rpc('fn_phase_c_governance_decide', { p_input: GOOD }, NONFOUNDER_TOKEN));
} else {
  results.push({ id: 'GOV-N6', area: 'governance', caller: 'authenticated non-founder', call: 'fn_phase_c_governance_decide',
    expected: 'REFUSED', outcome: 'NOT_MEASURED', http_status: '', detail: `no session could be minted for ${NONFOUNDER}` });
}
note('GOV-N7', 'governance', 'founder JWT + typed approved_by', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: { ...GOOD, approved_by: FOUNDER } }, FOUNDER_TOKEN));
note('GOV-N8', 'governance', 'founder JWT + typed auth subject', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: { ...GOOD, approval_auth_subject: claims.sub } }, FOUNDER_TOKEN));
note('GOV-N9', 'governance', 'founder JWT + arbitrary 64-hex', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: { ...GOOD, approved_amendment_digest: 'a'.repeat(64) } }, FOUNDER_TOKEN));
note('GOV-N10', 'governance', 'founder JWT + wrong change request', 'fn_phase_c_governance_decide', 'REFUSED',
  await rpc('fn_phase_c_governance_decide', { p_input: { ...GOOD, change_request_ref: 'PCCR-999' } }, FOUNDER_TOKEN));
// THE NEVER-QUOTED CASE, CHOSEN FROM THE DATABASE RATHER THAN TYPED.
// This named PCCR-003 as the change request the founder had never quoted a digest for. He quoted one
// at 2026-08-27 13:23:19 (message 48415), so the case stopped being a negative and came back
// ACCEPTED — a check that had gone stale against the very fact it was written to describe. The
// subject is now RESOLVED from `public.founder_command_message`: the lowest-numbered change request
// that appears in none of his messages beside a 64-character digest. If he later quotes that one
// too, this picks the next, and the case cannot go stale again.
const [neverQuoted] = await sql(`select cr.change_request_ref as ref
  from public.phase_c_change_request cr
 where cr.change_request_ref <> '${REF}'
   and not exists (select 1 from public.founder_command_message m
                    where position(lower(cr.change_request_ref) in lower(m.raw_text)) > 0
                      and m.raw_text ~ '[0-9a-fA-F]{64}')
 order by cr.change_request_ref limit 1`);
if (!neverQuoted) {
  results.push({ id: 'GOV-N11', area: 'governance', caller: 'founder JWT + a never-quoted change request',
    call: 'fn_phase_c_governance_decide', expected: 'REFUSED', outcome: 'NOT_MEASURED', http_status: '',
    detail: 'every registered change request now carries a founder message quoting a digest, so there '
          + 'is no never-quoted subject left to drive this case against' });
  console.log('----  GOV-N11 governance  no never-quoted change request remains -> NOT_MEASURED');
} else {
  note('GOV-N11', 'governance', `founder JWT + ${neverQuoted.ref} (never quoted)`, 'fn_phase_c_governance_decide', 'REFUSED',
    await rpc('fn_phase_c_governance_decide', { p_input: { ...GOOD, change_request_ref: neverQuoted.ref } }, FOUNDER_TOKEN));
}

// ---- the bind door, same treatment --------------------------------------------------------------
note('BND-N1', 'bind', 'no bearer token', 'fn_phase_c_founder_subject_bind', 'REFUSED',
  await rpc('fn_phase_c_founder_subject_bind', { p_subject: claims.sub }, null));
note('BND-N2', 'bind', 'invalid bearer token', 'fn_phase_c_founder_subject_bind', 'REFUSED',
  await rpc('fn_phase_c_founder_subject_bind', { p_subject: claims.sub }, 'not-a-token'));
note('BND-N3', 'bind', 'founder JWT with exp rewritten', 'fn_phase_c_founder_subject_bind', 'REFUSED',
  await rpc('fn_phase_c_founder_subject_bind', { p_subject: claims.sub }, expiredToken));
note('BND-N4', 'bind', 'service_role + founder uuid', 'fn_phase_c_founder_subject_bind', 'REFUSED',
  await rpc('fn_phase_c_founder_subject_bind', { p_subject: claims.sub }, service),
  'THIS IS THE FINDING OF 26 AUG: it was ACCEPTED before this session.');
note('BND-N5', 'bind', 'anon key + founder uuid', 'fn_phase_c_founder_subject_bind', 'REFUSED',
  await rpc('fn_phase_c_founder_subject_bind', { p_subject: claims.sub }, anon));
if (NONFOUNDER_TOKEN) {
  const nfClaims = JSON.parse(Buffer.from(NONFOUNDER_TOKEN.split('.')[1], 'base64url').toString('utf8'));
  note('BND-N6', 'bind', 'non-founder JWT binding itself', 'fn_phase_c_founder_subject_bind', 'REFUSED',
    await rpc('fn_phase_c_founder_subject_bind', { p_subject: nfClaims.sub }, NONFOUNDER_TOKEN));
  note('BND-N7', 'bind', 'non-founder JWT + founder uuid', 'fn_phase_c_founder_subject_bind', 'REFUSED',
    await rpc('fn_phase_c_founder_subject_bind', { p_subject: claims.sub }, NONFOUNDER_TOKEN));
}
note('BND-N8', 'bind', 'founder JWT + ANOTHER subject', 'fn_phase_c_founder_subject_bind', 'REFUSED',
  await rpc('fn_phase_c_founder_subject_bind', { p_subject: '00000000-0000-0000-0000-000000000000' }, FOUNDER_TOKEN));
note('BND-P1', 'bind', 'founder JWT binding itself', 'fn_phase_c_founder_subject_bind', 'ACCEPTED',
  await rpc('fn_phase_c_founder_subject_bind', { p_subject: claims.sub }, FOUNDER_TOKEN));

// ============================== B. THE POSITIVE CASE ============================================
const decided = await rpc('fn_phase_c_governance_decide', { p_input: GOOD }, FOUNDER_TOKEN);
note('GOV-P1', 'governance', 'FOUNDER JWT over real HTTPS', 'fn_phase_c_governance_decide', 'ACCEPTED', decided);
const replay = await rpc('fn_phase_c_governance_decide', { p_input: GOOD }, FOUNDER_TOKEN);
note('GOV-P2', 'governance', 'FOUNDER JWT replayed', 'fn_phase_c_governance_decide', 'ACCEPTED', replay,
  `outcome=${replay.body?.outcome}`);

// ============================== C. WHAT THE LEDGER HOLDS AFTERWARDS =============================
const ledger = await sql(`select decision_id, change_request_ref, decision, decided_by, approval_basis,
    approval_route, approval_auth_subject::text, auth_event_id, txid::text,
    approved_amendment_table_digest, decided_at::text
  from public.phase_c_governance_decision order by decision_id`);
const events = await sql(`select event_id, identity, route, action_class, object_ref, decision,
    consumed_at is not null as consumed, expires_at::text, bound_by
  from public.phase_c_founder_auth_event order by event_id`);
const cr = await sql(`select change_request_ref, disposition, approved_by, approval_basis,
    approval_route, governance_decision_id from public.phase_c_change_request order by 1`);
const board = await sql('select check_name, expected, actual, ok from public.fn_phase_c_freeze_drift()');

console.log(`\ngovernance decisions     ${ledger.length}`);
for (const d of ledger) console.log(`  #${d.decision_id} ${d.change_request_ref} ${d.decision} by ${d.decided_by} via ${d.approval_route} basis ${d.approval_basis}`);
console.log(`founder auth events      ${events.length}`);
console.log(`freeze board not-ok      ${board.filter((b) => b.ok !== true && b.ok !== 't').length} of ${board.length}`);
for (const b of board.filter((x) => x.ok !== true && x.ok !== 't')) console.log(`  RED ${b.check_name}: ${b.actual}`);

const COLS = ['id', 'area', 'caller', 'call', 'expected', 'outcome', 'http_status', 'detail'];
const cell = (v) => { const s = v == null ? '' : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
const wrong = results.filter((r) => r.outcome === 'ACCEPTED_WRONGLY' || r.outcome === 'REFUSED_WRONGLY' || r.outcome === 'FAILED').length;

const csv = provenance({
  command: 'node scripts/phase_d/prove_governance_door.mjs --record',
  numerator: results.length - wrong,
  denominator: results.length,
  of: 'authorization cases driven over real HTTPS against the deployed PostgREST endpoint',
  attribution: 'each row is one live HTTP call; outcome is read from the HTTP status and body, not from the routine source',
}) + COLS.join(',') + '\n' + results.map((r) => COLS.map((c) => cell(r[c])).join(',')).join('\n') + '\n'
  + `# governance_decisions_after=${ledger.length} founder_auth_events_after=${events.length}`
  + ` freeze_board_red=${board.filter((b) => b.ok !== true && b.ok !== 't').length}/${board.length}\n`;
writeFileSync(outPath('PHASE_D_GOVERNANCE_DOOR_CANARY.csv'), csv);
console.log(`\nwrote ${outPath('PHASE_D_GOVERNANCE_DOOR_CANARY.csv')}  (${results.length} cases, ${wrong} wrong)`);
console.log(JSON.stringify({ ledger, events, cr }, null, 1));
process.exit(wrong === 0 ? 0 : 1);
