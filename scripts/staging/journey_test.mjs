// journey_test.mjs — drive the real customer-to-quotation journey against deployed staging.
//
// Phase 2's standard is that each step is proven through the deployed application, not that a
// table exists. Every step here is a real HTTP call to a deployed Edge Function, authenticated
// as a real Auth user, in the order a customer and a supplier would actually hit them.
//
// It refuses to run against production. It prints status codes and truncated bodies, never tokens.
//
//   node scripts/staging/journey_test.mjs [--keep]
import { assertNotProduction } from './qd_guard.mjs';
import { readFileSync } from 'node:fs';

const REF = assertNotProduction(process.env.QD_STAGING_REF || 'pglpqrhvozwepymcuunn', 'journey test');
const BASE = `https://${REF}.supabase.co`;
const KEEP = process.argv.includes('--keep');
const mgmt = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`,
  { headers: { Authorization: 'Bearer ' + mgmt } })).json();
const ANON = keys.find(k => k.name === 'anon')?.api_key;
const SERVICE = keys.find(k => k.name === 'service_role')?.api_key;
if (!ANON || !SERVICE) { console.error('FAIL: could not read staging api keys'); process.exit(1); }

const steps = [];
let n = 0;
const step = (name, ok, detail) => {
  steps.push({ n: ++n, name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(n).padStart(2)} ${name.padEnd(34)} ${detail}`);
};

async function mkUser(tag) {
  const email = `qd-${tag}+${Date.now().toString(36)}${Math.floor(Math.random() * 1e4)}@example.com`;
  const password = 'Journey-' + Math.random().toString(36).slice(2) + 'A1!';
  const c = await fetch(`${BASE}/auth/v1/admin/users`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  const cu = await c.json();
  const t = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const tok = await t.json();
  return { id: cu.id ?? null, email, jwt: tok.access_token ?? null };
}

async function call(slug, jwt, body) {
  try {
    const r = await fetch(`${BASE}/functions/v1/${slug}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: 'Bearer ' + (jwt || ANON), 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(90000),
    });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* a non-JSON body is itself the finding */ }
    return { status: r.status, json, text: text.slice(0, 160).replace(/\s+/g, ' ') };
  } catch (e) {
    return { status: 0, json: null, text: String(e.message).slice(0, 160) };
  }
}

const created = [];

// ---- customer -------------------------------------------------------------------------------
const cust = await mkUser('cust');
created.push(cust.id);
step('customer signup (auth)', !!cust.id && !!cust.jwt, cust.jwt ? 'signed in' : 'no token');

let r = await call('customer_api', cust.jwt, { action: 'me' });
step('customer profile (me)', r.status === 200, `HTTP ${r.status} ${r.text}`);

r = await call('customer_api', cust.jwt, {
  action: 'create_inquiry',
  text: 'We need 40 aluminium windows supplied and installed for a villa in Dubai Marina.',
});
const inquiryId = r.json?.id ?? r.json?.inquiry_id ?? r.json?.group_id ?? null;
step('create inquiry', r.status === 200, `HTTP ${r.status} id=${inquiryId ?? 'none'} ${r.text}`);

r = await call('customer_api', cust.jwt, { action: 'my_inquiries' });
const listCount = Array.isArray(r.json) ? r.json.length : (r.json?.inquiries?.length ?? null);
step('list my inquiries', r.status === 200, `HTTP ${r.status} count=${listCount ?? '?'}`);

if (inquiryId) {
  r = await call('customer_api', cust.jwt, { action: 'complete_inquiry', id: inquiryId });
  step('complete inquiry', r.status === 200, `HTTP ${r.status} ${r.text}`);
} else {
  step('complete inquiry', false, 'skipped - no inquiry id from create_inquiry');
}

// ---- supplier -------------------------------------------------------------------------------
const supA = await mkUser('supA');
created.push(supA.id);
step('supplier A signup (auth)', !!supA.id && !!supA.jwt, supA.jwt ? 'signed in' : 'no token');

r = await call('supplier_api', supA.jwt, { action: 'me' });
step('supplier profile (me)', r.status === 200, `HTTP ${r.status} ${r.text}`);

r = await call('supplier_api', supA.jwt, {
  action: 'create_company',
  name: 'Journey Test Aluminium LLC',
  emirate: 'Dubai',
});
const companyId = r.json?.id ?? r.json?.company_id ?? null;
step('supplier create company', r.status === 200, `HTTP ${r.status} id=${companyId ?? 'none'} ${r.text}`);

r = await call('supplier_api', supA.jwt, { action: 'inbox' });
step('supplier inbox', r.status === 200, `HTTP ${r.status} ${r.text}`);

r = await call('supplier_api', supA.jwt, {
  action: 'submit_quote',
  inquiry_id: inquiryId,
  total: 125000,
  currency: 'AED',
  lines: [{ description: 'Aluminium windows supply and install', qty: 40, unit_price: 3125 }],
});
step('supplier submit quote', r.status === 200, `HTTP ${r.status} ${r.text}`);

// ---- cross-account isolation (Phase 3 / Phase 8) --------------------------------------------
const supB = await mkUser('supB');
created.push(supB.id);
r = await call('supplier_api', supB.jwt, { action: 'inbox' });
const bSeesNothingOfA = r.status === 200
  ? !JSON.stringify(r.json ?? '').includes('Journey Test Aluminium')
  : true;
step('supplier B cannot see A company', bSeesNothingOfA, `HTTP ${r.status}`);

if (inquiryId) {
  r = await call('supplier_api', supB.jwt, { action: 'extract_quote', inquiry_id: inquiryId });
  step('supplier B blocked from A inquiry', r.status === 401 || r.status === 403 || r.status === 404,
    `HTTP ${r.status} ${r.text}`);
} else {
  step('supplier B blocked from A inquiry', false, 'skipped - no inquiry id');
}

// ---- customer sees the quote ------------------------------------------------------------------
r = await call('customer_api', cust.jwt, { action: 'my_inquiries' });
step('customer sees quotation state', r.status === 200, `HTTP ${r.status} ${r.text}`);

// ---- cleanup -----------------------------------------------------------------------------------
if (!KEEP) {
  for (const id of created.filter(Boolean)) {
    await fetch(`${BASE}/auth/v1/admin/users/${id}`, {
      method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
    });
  }
  console.log(`\ncleaned up ${created.filter(Boolean).length} synthetic user(s)`);
}

const pass = steps.filter(s => s.ok).length;
console.log(`\nJOURNEY ${pass}/${steps.length} passed on ${REF}`);
process.exitCode = pass === steps.length ? 0 : 1;
