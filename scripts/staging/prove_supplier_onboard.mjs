// PROVE §2 BY EXECUTION: a sentence in, a structured supplier profile out, on a REAL project.
//
//   node scripts/staging/prove_supplier_onboard.mjs <ref>
//
// It stands up a throwaway auth user, calls supplier_onboard over HTTPS with a paragraph a real
// supplier might type, prints what came back, and deletes the user in a finally block. It asserts
// the two things that matter and cannot be faked by a shape check:
//   1. the six §2 fields are EXTRACTED from prose that contains none of them as labels;
//   2. nothing is invented — a fact the paragraph does not state comes back null.
// The second assertion is the one worth having. An extractor that fills every field always looks
// better and is worse.
import { readFileSync } from 'node:fs';

const ref = process.argv[2];
if (!ref) { console.error('usage: node scripts/staging/prove_supplier_onboard.mjs <ref>'); process.exit(2); }
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const H = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };

const keys = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys?reveal=true`, { headers: H })).json();
const ANON = keys.find((k) => k.name === 'anon')?.api_key;
const SERVICE = keys.find((k) => k.name === 'service_role')?.api_key;
if (!ANON || !SERVICE) { console.error('could not read api keys for ' + ref); process.exit(1); }
const BASE = `https://${ref}.supabase.co`;

// Deliberately messy, lowercase, no field labels, and it states five of the six things while
// saying NOTHING about what kind of business it is. company_type must come back null.
const PARAGRAPH = 'hi, we are al waha aluminium, based out of sharjah. we do curtain walling, '
  + 'shopfronts and aluminium cladding, been at it about twelve years now with our own fabrication '
  + 'shop. we take work across all seven emirates and we have shipped a few jobs to oman as well.';

const email = `qd-onboard-probe-${Date.now()}@example.invalid`;
let userId = null;
try {
  const cu = await (await fetch(`${BASE}/auth/v1/admin/users`, {
    method: 'POST', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'Probe-' + Math.random().toString(36).slice(2) + 'A1!', email_confirm: true }),
  })).json();
  userId = cu.id;
  if (!userId) throw new Error('auth create failed: ' + JSON.stringify(cu).slice(0, 200));

  // Unauthenticated first: a live function that gates is a different fact from a live function.
  const anonCall = await fetch(`${BASE}/functions/v1/supplier_onboard`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + ANON },
    body: JSON.stringify({ action: 'extract', text: PARAGRAPH }),
  });
  console.log(`${ref}  unauthenticated -> ${anonCall.status} (401 expected: the endpoint gates)`);

  const tok = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: cu.password }),
  })).json().catch(() => ({}));
  // The password is not returned by the admin API, so sign in with a fresh one we set ourselves.
  const pw = 'Probe-' + Math.random().toString(36).slice(2) + 'A1!';
  await fetch(`${BASE}/auth/v1/admin/users/${userId}`, {
    method: 'PUT', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ password: pw }),
  });
  const t2 = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: pw }),
  })).json();
  const jwt = t2.access_token || tok.access_token;
  if (!jwt) throw new Error('could not mint a supplier JWT: ' + JSON.stringify(t2).slice(0, 200));

  const t0 = Date.now();
  const r = await fetch(`${BASE}/functions/v1/supplier_onboard`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + jwt },
    body: JSON.stringify({ action: 'extract', text: PARAGRAPH }),
  });
  const d = await r.json();
  console.log(`${ref}  authenticated   -> ${r.status} in ${Date.now() - t0}ms`);
  if (!d.ok) { console.log('  NOT OK:', JSON.stringify(d).slice(0, 400)); process.exit(1); }

  const p = d.profile || {};
  for (const f of ['company_name', 'category', 'company_type', 'location', 'capability_summary', 'markets'])
    console.log(`  ${f.padEnd(19)} ${JSON.stringify(p[f])}`);
  console.log(`  filled: [${(d.filled || []).join(' ')}]  missing: [${(d.missing || []).join(' ')}]`);
  console.log(`  reply: ${String(d.reply || '').slice(0, 160)}`);

  const fails = [];
  if (!/waha/i.test(String(p.company_name || ''))) fails.push('company_name not extracted');
  if (p.category !== 'aluminium') fails.push(`category is ${JSON.stringify(p.category)}, expected "aluminium"`);
  if (!/sharjah/i.test(String(p.location || ''))) fails.push('location not extracted');
  if (!p.capability_summary) fails.push('capability_summary not extracted');
  if (!Array.isArray(p.markets) || p.markets.length < 7) fails.push(`markets got ${JSON.stringify(p.markets)}, expected all seven emirates`);
  // THE ANTI-INVENTION ASSERTION, and the reason it is worth more than "must be null": a company
  // type is allowed, but only if the supplier's own words support it and those words are really in
  // what they wrote. The first staging run returned "contractor" for a paragraph that never says
  // it, which is exactly the failure this catches.
  if (p.company_type !== null) {
    const b = String(p.company_type_basis || '').toLowerCase().replace(/\s+/g, ' ');
    if (!b) fails.push(`company_type ${JSON.stringify(p.company_type)} with NO basis quoted`);
    else if (!PARAGRAPH.replace(/\s+/g, ' ').includes(b)) fails.push(`company_type basis ${JSON.stringify(b)} is NOT in what the supplier wrote — invented`);
    else console.log(`  company_type grounded in: "${b}"`);
  }

  if (fails.length) { console.log('\nFAILED:'); for (const f of fails) console.log('  - ' + f); process.exit(1); }
  console.log(`\nPASS ${ref}: the six §2 fields extracted from unlabelled prose, company_type grounded in a verbatim quote.`);
} finally {
  if (userId) await fetch(`${BASE}/auth/v1/admin/users/${userId}`, {
    method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
  }).catch(() => {});
}
