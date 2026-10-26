// PROVE §10 OVER HTTPS: the ranked-opportunities action answers, and answers RANKED.
//
//   node scripts/staging/prove_supplier_opportunities.mjs <ref>
//
// supplier_portal resolves the supplier from the caller's e-mail via leads.claimed_by, so this
// signs in AS the fenced demo supplier. The auth user is created only if it is missing and is
// removed again in a finally block unless it was already there.
import { readFileSync } from 'node:fs';

const ref = process.argv[2];
if (!ref) { console.error('usage: prove_supplier_opportunities.mjs <ref>'); process.exit(2); }
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const H = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };

const keys = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys?reveal=true`, { headers: H })).json();
const ANON = keys.find((k) => k.name === 'anon')?.api_key;
const SERVICE = keys.find((k) => k.name === 'service_role')?.api_key;
const BASE = `https://${ref}.supabase.co`;
const svc = { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' };

// Whatever claimed_by holds is the identity supplier_portal will resolve — read it, never assume it.
const q = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
  method: 'POST', headers: H,
  body: JSON.stringify({ query: `select claimed_by from public.leads where place_id='qd-demo-supplier-001'` }),
})).json();
const email = q?.[0]?.claimed_by;
if (!email) { console.error('demo supplier has no claimed_by on ' + ref); process.exit(1); }

const existing = await (await fetch(`${BASE}/auth/v1/admin/users?filter=${encodeURIComponent(email)}`, { headers: svc })).json();
const preExisting = (existing.users || []).find((u) => (u.email || '').toLowerCase() === email.toLowerCase());
const pw = 'Probe-' + Math.random().toString(36).slice(2) + 'A1!';
let userId = preExisting?.id || null;
let created = false;
try {
  if (!userId) {
    const cu = await (await fetch(`${BASE}/auth/v1/admin/users`, {
      method: 'POST', headers: svc, body: JSON.stringify({ email, password: pw, email_confirm: true }),
    })).json();
    userId = cu.id; created = true;
    if (!userId) throw new Error('auth create failed: ' + JSON.stringify(cu).slice(0, 200));
  } else {
    await fetch(`${BASE}/auth/v1/admin/users/${userId}`, { method: 'PUT', headers: svc, body: JSON.stringify({ password: pw }) });
  }
  const tok = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: pw }),
  })).json();
  if (!tok.access_token) throw new Error('no JWT: ' + JSON.stringify(tok).slice(0, 200));

  const r = await fetch(`${BASE}/functions/v1/supplier_portal`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + tok.access_token },
    body: JSON.stringify({ action: 'opportunities' }),
  });
  const d = await r.json();
  console.log(`${ref}  POST supplier_portal{opportunities} -> ${r.status}`);
  if (!d.ok) { console.log('  NOT OK: ' + JSON.stringify(d).slice(0, 300)); process.exit(1); }
  console.log(`  count=${d.count} ordered_by="${d.ordered_by}" population=${JSON.stringify(d.population)}`);

  const fails = [];
  if (r.status !== 200) fails.push('status ' + r.status);
  if (!Array.isArray(d.opportunities)) fails.push('no opportunities array');
  // RANKED, not chronological: fit_score must be non-increasing across the list.
  const scores = (d.opportunities || []).map((o) => o.fit_score ?? -1);
  for (let i = 1; i < scores.length; i++) if (scores[i] > scores[i - 1]) fails.push('not ordered by fit_score');
  // Every opportunity must carry all four reasons, or the "why" is decoration.
  for (const o of d.opportunities || []) {
    const keysSeen = new Set((o.reasons || []).map((x) => x.key));
    for (const k of ['trade', 'location', 'capacity', 'history'])
      if (!keysSeen.has(k)) fails.push(`opportunity ${o.inquiry_id} missing reason "${k}"`);
  }
  for (const o of d.opportunities || []) {
    const h = (o.reasons || []).find((x) => x.key === 'history');
    if (d.population?.quotes_in_estate === 0 && h && h.available !== false)
      fails.push('history claims to be answerable while the estate holds 0 quotes');
  }
  if (fails.length) { console.log('\nFAILED:'); fails.forEach((f) => console.log('  - ' + f)); process.exit(1); }
  console.log(`  scores in order: [${scores.join(' ')}]`);
  console.log('\nPASS: ranked by fit, every opportunity carries all four reasons, history honestly unanswerable.');
} finally {
  if (created && userId) await fetch(`${BASE}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: svc }).catch(() => {});
}
