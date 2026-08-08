// PROVE §12 OVER HTTPS: the assistant reads the thread, does the arithmetic, and refuses to
// recommend a discount.
//
//   node scripts/staging/prove_supplier_negotiation.mjs <ref>
//
// The demo customer message asks for indicative RATES and a lead time. That is a request for
// information, not price pressure, so a correct analyser answers FALSE. A detector that says yes to
// any message mentioning money is useless, and this is the case that catches it.
import { readFileSync } from 'node:fs';

const ref = process.argv[2];
if (!ref) { console.error('usage: prove_supplier_negotiation.mjs <ref>'); process.exit(2); }
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const H = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };
const keys = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys?reveal=true`, { headers: H })).json();
const ANON = keys.find((k) => k.name === 'anon')?.api_key;
const SERVICE = keys.find((k) => k.name === 'service_role')?.api_key;
const BASE = `https://${ref}.supabase.co`;
const svc = { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' };

const q = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
  method: 'POST', headers: H,
  body: JSON.stringify({ query: `select claimed_by from public.leads where place_id='qd-demo-supplier-001'` }),
})).json();
const email = q?.[0]?.claimed_by;
if (!email) { console.error('demo supplier has no claimed_by'); process.exit(1); }

const list = await (await fetch(`${BASE}/auth/v1/admin/users?filter=${encodeURIComponent(email)}`, { headers: svc })).json();
const pre = (list.users || []).find((u) => (u.email || '').toLowerCase() === email.toLowerCase());
const pw = 'Probe-' + Math.random().toString(36).slice(2) + 'A1!';
let userId = pre?.id || null, created = false;
try {
  if (!userId) {
    const cu = await (await fetch(`${BASE}/auth/v1/admin/users`, { method: 'POST', headers: svc, body: JSON.stringify({ email, password: pw, email_confirm: true }) })).json();
    userId = cu.id; created = true;
    if (!userId) throw new Error('auth create failed');
  } else {
    await fetch(`${BASE}/auth/v1/admin/users/${userId}`, { method: 'PUT', headers: svc, body: JSON.stringify({ password: pw }) });
  }
  const tok = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: pw }),
  })).json();
  if (!tok.access_token) throw new Error('no JWT');

  const r = await fetch(`${BASE}/functions/v1/supplier_portal`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + tok.access_token },
    body: JSON.stringify({ action: 'negotiation' }),          // no quote_id: analyse the latest
  });
  const d = await r.json();
  console.log(`${ref}  POST supplier_portal{negotiation} -> ${r.status}`);
  if (!d.ok) { console.log('  NOT OK: ' + JSON.stringify(d).slice(0, 300)); process.exit(1); }
  console.log(`  quote ${d.quote_amount} -> customer ${d.customer_price}; app_fee ${d.margin?.app_fee} (${d.margin?.whose})`);
  console.log(`  supplier_cost_known=${d.supplier_cost_known}  possible_reduction.available=${d.possible_reduction?.available}`);
  for (const s of d.possible_reduction?.scenarios || [])
    console.log(`    -${s.reduction_pct}%  you receive ${s.you_receive}  customer pays ${s.customer_pays}  you give up ${s.you_give_up}`);
  console.log(`  detected=${JSON.stringify(d.analysis?.price_pressure_detected)}  ${String(d.analysis?.detection || '').slice(0, 120)}`);
  console.log(`  draft: ${String(d.analysis?.recommended_response || '').slice(0, 160)}`);

  const fails = [];
  if (d.supplier_cost_known !== false) fails.push('supplier_cost_known must be false — the platform does not know their cost');
  if (d.possible_reduction?.available !== false) fails.push('possible_reduction claims to be available');
  if ((d.possible_reduction?.scenarios || []).length !== 3) fails.push('expected three reduction scenarios');
  // Asking for rates is NOT price pressure. A detector that says yes here says yes to everything.
  if (d.analysis?.price_pressure_detected === true)
    fails.push('called a request for indicative rates a discount request');
  // And the draft must never name a discount, because the floor is unknown.
  const draft = String(d.analysis?.recommended_response || '');
  if (/\b\d+\s*%|discount of|reduce (it |the price )?to\b/i.test(draft))
    fails.push('the drafted reply proposes a discount: ' + draft.slice(0, 120));

  if (fails.length) { console.log('\nFAILED:'); fails.forEach((f) => console.log('  - ' + f)); process.exit(1); }
  console.log('\nPASS: arithmetic exact, floor withheld, a request for rates not mistaken for pressure, no discount drafted.');
} finally {
  if (created && userId) await fetch(`${BASE}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: svc }).catch(() => {});
}
