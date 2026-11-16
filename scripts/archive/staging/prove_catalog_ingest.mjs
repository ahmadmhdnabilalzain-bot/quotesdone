// PROVE §7 BY EXECUTION: a price list goes in, product RECORDS come out.
//
//   node scripts/archive/staging/prove_catalog_ingest.mjs <ref>
//
// The claim §7 makes is a CONVERSION, and the scorer's own note is emphatic that a reader of the
// product store is not an extractor. So this asserts the destination: rows in supplier_product that
// did not exist before, carrying the attributes the file stated.
//
// The fixture includes a TOTAL row and a blank name on purpose. A spreadsheet's totals line is not
// a product, and an extractor that inserts it puts rubbish in a store the supplier then has to
// clean by hand.
import { supabaseAccessToken } from '../../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { pickApiKey } from '../../lib/supabase_keys.mjs';   // new keys first; legacy only as a temporary fallback (27 Oct 2026)

const ref = process.argv[2];
if (!ref) { console.error('usage: prove_catalog_ingest.mjs <ref>'); process.exit(2); }
const token = supabaseAccessToken();
const H = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };
const sql = async (q) => (await (await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
  method: 'POST', headers: H, body: JSON.stringify({ query: q }),
})).json());

const keys = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys?reveal=true`, { headers: H })).json();
const ANON = pickApiKey(keys, 'publishable');
const SERVICE = pickApiKey(keys, 'secret');
const BASE = `https://${ref}.supabase.co`;
const svc = { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' };

const who = await sql(`select id::text, claimed_by from public.leads where place_id='qd-demo-supplier-001'`);
const supId = who?.[0]?.id, email = who?.[0]?.claimed_by;
if (!email) { console.error('demo supplier missing'); process.exit(1); }

const CSV = [
  'product,brand,model,unit,price,finish',
  'Aluminium curtain wall profile,Alumil,M11000,lm,142.50,mill finish',
  'Shopfront door leaf,Alumil,SD67,each,890,powder coated',
  'Structural glazing gasket,Reddiplex,RG-12,lm,18.75,black EPDM',
  ',,,,,',                       // blank: not a product
  'TOTAL,,,,1051.25,',           // totals line: not a product
].join('\n');

const before = Number((await sql(`select count(*)::text n from public.supplier_product where supplier_id=${supId}`))?.[0]?.n || 0);

const pw = 'Probe-' + Math.random().toString(36).slice(2) + 'A1!';
const list = await (await fetch(`${BASE}/auth/v1/admin/users?filter=${encodeURIComponent(email)}`, { headers: svc })).json();
const pre = (list.users || []).find((u) => (u.email || '').toLowerCase() === email.toLowerCase());
let userId = pre?.id || null, created = false;
try {
  if (!userId) {
    const cu = await (await fetch(`${BASE}/auth/v1/admin/users`, { method: 'POST', headers: svc, body: JSON.stringify({ email, password: pw, email_confirm: true }) })).json();
    userId = cu.id; created = true;
  } else {
    await fetch(`${BASE}/auth/v1/admin/users/${userId}`, { method: 'PUT', headers: svc, body: JSON.stringify({ password: pw }) });
  }
  const tok = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: pw }),
  })).json();
  if (!tok.access_token) throw new Error('no JWT');

  const r = await fetch(`${BASE}/functions/v1/supplier_catalog_ingest`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + tok.access_token },
    body: JSON.stringify({ file_name: 'zz-demo-pricelist.csv', data: Buffer.from(CSV, 'utf8').toString('base64') }),
  });
  const d = await r.json();
  console.log(`${ref}  POST supplier_catalog_ingest -> ${r.status}`);
  console.log(`  status=${d.status} format=${d.format} found=${d.products_found} created=${d.products_created}`);
  console.log(`  route: ${d.note || d.why || ''}`);

  const after = Number((await sql(`select count(*)::text n from public.supplier_product where supplier_id=${supId}`))?.[0]?.n || 0);
  const rows = await sql(`select name, brand, model, attributes->>'finish' finish
    from public.supplier_product where supplier_id=${supId} and status='extracted' order by name limit 5`);
  for (const x of rows) console.log(`    · ${x.name} | ${x.brand} ${x.model} | finish=${x.finish}`);

  const fails = [];
  if (!d.ok) fails.push('endpoint returned not-ok: ' + JSON.stringify(d).slice(0, 200));
  if (d.products_created !== 3) fails.push(`expected 3 products, created ${d.products_created}`);
  if (after - before !== 3) fails.push(`supplier_product grew by ${after - before}, expected 3`);
  if (rows.some((x) => /^total/i.test(x.name || ''))) fails.push('a TOTAL row was inserted as a product');
  if (!rows.some((x) => x.finish)) fails.push('the file stated a finish and no product carries it');

  if (fails.length) { console.log('\nFAILED:'); fails.forEach((f) => console.log('  - ' + f)); process.exit(1); }
  console.log(`\nPASS: ${before} -> ${after} product records written from a file, totals and blanks refused.`);
} finally {
  if (created && userId) await fetch(`${BASE}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: svc }).catch(() => {});
}
