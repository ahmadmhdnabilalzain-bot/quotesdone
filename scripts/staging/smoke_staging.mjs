// smoke_staging.mjs — does the staging application actually respond?
//
// Phase 1's completion standard is "staging is runnable": schemas exist, Auth works, Storage
// works, and the customer and supplier APIs answer. A migration count does not show any of that.
// This creates a real user through the real Auth endpoint, signs in as them, and calls the
// deployed Edge Functions with that user's JWT.
//
// It refuses to run against production. It prints status codes and counts, never a token.
//
//   node scripts/staging/smoke_staging.mjs [--keep]
//
// --keep leaves the synthetic user behind for follow-up work; the default deletes it.
import { assertNotProduction } from './qd_guard.mjs';
import { readFileSync } from 'node:fs';

const REF = assertNotProduction(process.env.QD_STAGING_REF || 'pglpqrhvozwepymcuunn', 'smoke test');
const BASE = `https://${REF}.supabase.co`;
const KEEP = process.argv.includes('--keep');
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`,
  { headers: { Authorization: 'Bearer ' + mgmtToken } })).json();
const ANON = keys.find(k => k.name === 'anon')?.api_key;
const SERVICE = keys.find(k => k.name === 'service_role')?.api_key;
if (!ANON || !SERVICE) { console.error('FAIL: could not read staging api keys'); process.exit(1); }

const results = [];
const record = (area, name, ok, detail) => {
  results.push({ area, name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${area.padEnd(9)} ${name.padEnd(28)} ${detail}`);
};

// ---- 1. Auth -------------------------------------------------------------------------------
const email = `qd-smoke+${Date.now().toString(36)}@example.com`;
const password = 'Smoke-' + Math.random().toString(36).slice(2) + 'A1!';
let userId = null, jwt = null;

try {
  const r = await fetch(`${BASE}/auth/v1/admin/users`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  const b = await r.json();
  userId = b.id ?? null;
  record('auth', 'create user', r.ok && !!userId, `HTTP ${r.status}`);
} catch (e) { record('auth', 'create user', false, String(e.message).slice(0, 80)); }

try {
  const r = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const b = await r.json();
  jwt = b.access_token ?? null;
  record('auth', 'sign in (password grant)', r.ok && !!jwt, `HTTP ${r.status}`);
} catch (e) { record('auth', 'sign in (password grant)', false, String(e.message).slice(0, 80)); }

// ---- 2. Storage ----------------------------------------------------------------------------
try {
  const r = await fetch(`${BASE}/storage/v1/bucket`, {
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
  });
  const b = await r.json();
  record('storage', 'list buckets', r.ok, `HTTP ${r.status}, ${Array.isArray(b) ? b.length : 0} bucket(s)`);
} catch (e) { record('storage', 'list buckets', false, String(e.message).slice(0, 80)); }

// ---- 3. PostgREST --------------------------------------------------------------------------
try {
  const r = await fetch(`${BASE}/rest/v1/app_secrets?select=key&limit=1`, {
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
  });
  record('rest', 'postgrest reachable', r.ok, `HTTP ${r.status}`);
} catch (e) { record('rest', 'postgrest reachable', false, String(e.message).slice(0, 80)); }

// ---- 4. Edge Functions -----------------------------------------------------------------------
// A function that answers at all - even with a structured refusal - is deployed and running.
// A 404 means it is not there; a 5xx means it crashed on boot, which is the interesting failure.
const FNS = [
  ['customer_api', { action: 'ping' }],
  ['supplier_api', { action: 'ping' }],
  ['os_api', { action: 'ping' }],
  ['inquiry_intake', {}],
  ['route_inquiry', {}],
  ['ai_gateway', {}],
  ['kb_retrieve', {}],
  ['i18n_get', { lang: 'en' }],
  ['quote_compare', {}],
  ['login_otp', {}],
];

for (const [slug, body] of FNS) {
  try {
    const r = await fetch(`${BASE}/functions/v1/${slug}`, {
      method: 'POST',
      headers: {
        apikey: ANON,
        Authorization: 'Bearer ' + (jwt || ANON),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(30000),
    });
    const raw = await r.text();
    const text = raw.slice(0, 120).replace(/\s+/g, ' ');
    // A function that answers with its OWN JSON has booted and run, whatever the status - even
    // 404 {"error":"not_found"}, which is the correct reply to a request naming no record.
    // A function that is not deployed returns 404 with the platform's own non-JSON body, and a
    // function that crashes on boot returns 5xx. Those are the failures worth reporting.
    let ownReply = false;
    try { ownReply = typeof JSON.parse(raw) === 'object'; } catch { /* not its own reply */ }
    const alive = r.status < 500 && (ownReply || r.status !== 404);
    record('edgefn', slug, alive, `HTTP ${r.status} ${text}`);
  } catch (e) {
    record('edgefn', slug, false, String(e.message).slice(0, 80));
  }
}

// ---- cleanup ---------------------------------------------------------------------------------
if (userId && !KEEP) {
  const r = await fetch(`${BASE}/auth/v1/admin/users/${userId}`, {
    method: 'DELETE',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
  });
  record('auth', 'delete synthetic user', r.ok, `HTTP ${r.status}`);
}

const pass = results.filter(r => r.ok).length;
console.log(`\nSMOKE ${pass}/${results.length} passed on ${REF}`);
process.exitCode = pass === results.length ? 0 : 1;
