// PHASE D · D0 — discharge the two authentication cases the founder named at Phase C approval.
//
// public.phase_d_preflight_requirement holds them as OUTSTANDING:
//
//   D0-AUTH-001  valid enabled founder JWT reaches the Command Center      -> expect 2xx
//   D0-AUTH-002  valid non-founder JWT is refused by the Command Center    -> expect 403
//
// The Phase C closure audit was read-only and declined to mint a production session, so both were
// recorded as verification debt owed at Phase D D0 rather than as permission to reopen Phase C.
// Reading the branch at supabase/functions/os_api/index.ts:186 is not executing it, and the whole
// point of the debt is that a branch nobody has run is a branch nobody has proved.
//
// HOW THE TWO IDENTITIES ARE OBTAINED, AND WHY EACH IS SAFE.
//
// Positive case: management@quotesdone.com, which public.phase_c_founder_identity holds as active,
// kind email. The session is minted with the admin generate_link API, which RETURNS a link and
// does not send mail, then verified for a real bearer. No password is read, set or handled, and
// the founder's account is not modified.
//
// Negative case: a canary auth user under the repository's established fixture convention —
// example.invalid, ZZ-prefixed — created, used for exactly one request, and DELETED in the same
// run. PHASE_D_PRODUCTION_DIRECT_PROTOCOL.md permits "explicitly namespaced/cleaned canaries" and
// forbids persistent demo customers and suppliers; this is the former and is not the latter. It
// is an auth identity only: no customer, supplier, inquiry or any business row is created.
//
// The cleanup runs in a finally, so a failure between create and delete still removes the canary.

import { readFileSync } from 'node:fs';

const PROJECT = 'htdblwldjkcgjvmqkbeh';
const MGMT = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const mgmt = async (path, init = {}) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}${path}`, {
    ...init, headers: { authorization: `Bearer ${MGMT}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  if (!r.ok) throw new Error(`management ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};

// ---- keys -------------------------------------------------------------------------------------
const keys = await mgmt('/api-keys?reveal=true');
const service = keys.find((k) => k.name === 'service_role' || k.type === 'secret')?.api_key;
const anon = keys.find((k) => k.name === 'anon' || k.type === 'publishable')?.api_key;
if (!service || !anon) throw new Error('could not resolve both the service_role and anon keys');

const BASE = `https://${PROJECT}.supabase.co`;
const OS_API = `${BASE}/functions/v1/os_api`;

const admin = async (path, init = {}) => {
  const r = await fetch(`${BASE}/auth/v1${path}`, {
    ...init,
    headers: { apikey: service, authorization: `Bearer ${service}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  const body = await r.json().catch(() => ({}));
  return { status: r.status, body };
};

// A bearer for an email, without touching its password. generate_link returns the link; it does
// not deliver mail. The token_hash is then verified for a real session.
const bearerFor = async (email) => {
  const gen = await admin('/admin/generate_link', {
    method: 'POST', body: JSON.stringify({ type: 'magiclink', email }),
  });
  const hash = gen.body?.hashed_token || gen.body?.properties?.hashed_token;
  if (!hash) throw new Error(`generate_link for ${email} returned no hashed_token (${gen.status})`);
  const r = await fetch(`${BASE}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: anon, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: hash }),
  });
  const b = await r.json().catch(() => ({}));
  if (!b?.access_token) throw new Error(`verify for ${email} returned no access_token (${r.status})`);
  return b.access_token;
};

// One harmless, read-only, already-classified action. `ping` proves the identity branch without
// asking the Command Center to change anything.
const callOsApi = async (token) => {
  const r = await fetch(OS_API, {
    method: 'POST',
    headers: { apikey: anon, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'ping' }),
  });
  return { status: r.status, body: (await r.text()).slice(0, 200) };
};

const CANARY = 'zz-phase-d-canary@example.invalid';
let canaryId = null;
const results = [];

try {
  // ---- D0-AUTH-001 — the founder positive case ------------------------------------------------
  const founder = 'management@quotesdone.com';
  const founderToken = await bearerFor(founder);
  const pos = await callOsApi(founderToken);
  results.push({
    requirement: 'D0-AUTH-001', identity: founder, expected: '2xx',
    status: pos.status, pass: pos.status >= 200 && pos.status < 300, body: pos.body,
  });

  // ---- D0-AUTH-002 — a real non-founder session -----------------------------------------------
  const made = await admin('/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email: CANARY, email_confirm: true, password: crypto.randomUUID() + 'Aa1!' }),
  });
  canaryId = made.body?.id;
  if (!canaryId) throw new Error(`could not create the canary identity (${made.status}): ${JSON.stringify(made.body).slice(0, 200)}`);

  const canaryToken = await bearerFor(CANARY);
  const neg = await callOsApi(canaryToken);
  results.push({
    requirement: 'D0-AUTH-002', identity: CANARY, expected: '403',
    status: neg.status, pass: neg.status === 403, body: neg.body,
  });
} finally {
  if (canaryId) {
    const del = await admin(`/admin/users/${canaryId}`, { method: 'DELETE' });
    const check = await admin(`/admin/users/${canaryId}`);
    console.log(`canary cleanup: delete -> ${del.status}, read-back -> ${check.status} `
      + `(404 means the identity is gone; anything else means it is NOT and must be removed by hand)`);
  }
}

for (const r of results) {
  console.log(`${r.pass ? 'PASS' : 'FAIL'}  ${r.requirement}  ${r.identity}  expected ${r.expected}, got ${r.status}`);
  console.log(`      ${r.body}`);
}
process.exit(results.every((r) => r.pass) ? 0 : 1);
