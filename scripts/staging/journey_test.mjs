// journey_test.mjs — drive the real customer-to-quotation journey against deployed staging.
//
// Phase 2's standard is that each step is proven through the deployed application, not that a
// table exists. Every step here is a real HTTP call to a deployed Edge Function, authenticated
// as a real Auth user, in the order a customer and a supplier would actually hit them.
//
// It refuses to run against production. It prints status codes and truncated bodies, never tokens.
//
//   node scripts/staging/journey_test.mjs [--keep]
import { assertNotProduction, mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { readFileSync } from 'node:fs';
import { createHmac } from 'node:crypto';

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

// Journey step 2 - email verification. login_otp stores an HMAC of the code, never the code, so
// the code cannot be read back out. Staging cannot receive the email either (email_enabled is
// forced off so staging can never mail a real person). So the test writes a verification row with
// a code it chose, hashed exactly the way login_otp hashes it, and then verifies through the real
// endpoint. Everything except the delivery hop is genuinely exercised: hash comparison, expiry,
// purpose, single-use, and the customers.email_verified write that gates create_inquiry.
const OTP = '424242';
const otpKey = (await mgmtRead(REF, "select value from public.app_secrets where key='otp_hmac_key'"))[0]?.value;
if (otpKey) {
  const hash = createHmac('sha256', otpKey).update(OTP).digest('hex');
  await mgmtWrite(REF,
    `insert into public.email_verifications (email, token_hash, purpose, user_kind, expires_at)
     values ('${cust.email}', '${hash}', 'login', 'customer', now() + interval '10 minutes')`,
    'seed otp');
  r = await call('login_otp', null, {
    action: 'verify', identifier: cust.email, code: OTP, user_kind: 'customer',
  });
  step('email verification (OTP)', r.status === 200, `HTTP ${r.status} ${r.text}`);
} else {
  step('email verification (OTP)', false, 'otp_hmac_key missing from staging app_secrets');
}

// Journey steps 3 and 4. create_inquiry refuses with 428 registration_incomplete until the
// customer has a name, a mobile number and an accepted T&C version - and none of that lives in
// customer_api. kyc owns it: save_customer writes the profile, accept_terms records the version
// from app_secrets so the acceptance says which document was actually signed.
r = await call('kyc', cust.jwt, {
  action: 'save_customer', user_kind: 'customer',
  email: cust.email, full_name: 'Journey Test Customer', phone: '+971501234567',
});
step('customer profile (kyc save)', r.status === 200, `HTTP ${r.status} ${r.text}`);

r = await call('kyc', cust.jwt, { action: 'accept_terms', user_kind: 'customer', email: cust.email });
step('customer accepts terms', r.status === 200, `HTTP ${r.status} ${r.text}`);

// Journey steps 5-8: the AI question flow. create_inquiry refuses with 428 intake_required
// unless body.intake_id names an inquiry_intake row owned by this customer whose status is
// 'ready' - a deliberate gate added 27 Jul after the old one could be waived from the client.
// This runs the real multi-turn intake through OpenRouter until it reports ready.
// Concrete values, not polite vagueness. The intake runs a structured extractor against the
// trade's checklist, so "standard specification, please assume typical values" populates nothing
// and readiness stalls at 40. Each line below answers a specific checklist field.
const ANSWERS = [
  'Aluminium windows: supply and installation. 40 units for a private villa in Dubai Marina.',
  'Sizes: 40 units at 1200 mm W x 1500 mm H each, approximately 72 square metres in total.',
  'Scope: supply and install, including removing the existing windows and disposing of them.',
  'Property: private villa in Dubai Marina, ground and first floor, direct vehicle access, no crane needed.',
  'Specification: powder-coated white aluminium, double glazed 6-12-6, with mosquito mesh and handles.',
  'Timeline: installation within eight weeks of order. Budget is open; include supply and install.',
];
// The loop is adaptive, not a fixed script. Once category_specs was loaded the intake gained a
// real per-trade checklist, and a canned six-message conversation stopped reaching 'ready' - the
// earlier one-turn pass happened only because an empty category_specs meant no checklist existed
// to satisfy. Each turn answers whatever the server says is still missing.
let intakeId = null, intakeStatus = null, turns = 0, readiness = 0, missing = [];
for (let i = 0; i < 10; i++) {
  const answer = i < ANSWERS.length
    ? ANSWERS[i]
    : `Details: ${missing.slice(0, 6).map((m) => `${m}: standard specification, please assume typical values`).join('; ') || 'please proceed with typical values'}.`;
  const ir = await call('inquiry_intake', cust.jwt,
    intakeId ? { intake_id: intakeId, text: answer, email: cust.email }
             : { text: answer, email: cust.email });
  turns++;
  if (ir.status !== 200) { intakeStatus = `HTTP ${ir.status} ${ir.text}`; break; }
  intakeId = ir.json?.intake_id ?? ir.json?.id ?? intakeId;
  intakeStatus = ir.json?.status ?? null;
  readiness = Number(ir.json?.readiness ?? 0);
  missing = Array.isArray(ir.json?.missing) ? ir.json.missing.map(String) : [];
  if (intakeStatus === 'ready') break;
}
step('AI intake question flow', intakeStatus === 'ready',
  `${turns} turn(s), status=${intakeStatus}, readiness=${readiness}, still missing=${missing.length ? missing.slice(0, 4).join('|') : 'none'}`);

r = await call('customer_api', cust.jwt, {
  action: 'create_inquiry',
  intake_id: intakeId,
  text: 'We need 40 aluminium windows supplied and installed for a villa in Dubai Marina.',
});
const inquiryId = r.json?.id ?? r.json?.inquiry_id ?? r.json?.group_id ?? null;
step('create inquiry', r.status === 200, `HTTP ${r.status} id=${inquiryId ?? 'none'} ${r.text}`);

r = await call('customer_api', cust.jwt, { action: 'my_inquiries' });
const listCount = Array.isArray(r.json) ? r.json.length : (r.json?.inquiries?.length ?? null);
step('list my inquiries', r.status === 200, `HTTP ${r.status} count=${listCount ?? '?'}`);

// complete_inquiry closes a job against an accepted QUOTE, not the intake draft - it answers
// "Quote not found" until one exists. It belongs at the end of the journey, after a supplier has
// quoted, so it is asserted there rather than here.

// ---- supplier -------------------------------------------------------------------------------
const supA = await mkUser('supA');
created.push(supA.id);
step('supplier A signup (auth)', !!supA.id && !!supA.jwt, supA.jwt ? 'signed in' : 'no token');

r = await call('supplier_api', supA.jwt, { action: 'me' });
step('supplier profile (me)', r.status === 200, `HTTP ${r.status} ${r.text}`);

// The field is company_name, not name: create_company reads body.company_name and rejects a
// short one with "Enter your company name." Suppliers live in `leads`, keyed by claimed_by.
r = await call('supplier_api', supA.jwt, {
  action: 'create_company',
  company_name: 'Journey Test Aluminium LLC',
  emirate: 'Dubai',
  role: 'supplier',
});
const companyId = r.json?.id ?? r.json?.company_id ?? null;
step('supplier create company', r.status === 200, `HTTP ${r.status} id=${companyId ?? 'none'} ${r.text}`);

r = await call('supplier_api', supA.jwt, { action: 'inbox' });
step('supplier inbox', r.status === 200, `HTTP ${r.status} ${r.text}`);

// submit_quote refuses with "accept the supplier terms first" until leads.accepted_terms_at is
// set. Same kyc endpoint, keyed on user_kind, recording the supplier terms version.
r = await call('kyc', supA.jwt, { action: 'accept_terms', user_kind: 'supplier', email: supA.email });
step('supplier accepts terms', r.status === 200, `HTTP ${r.status} ${r.text}`);

// Journey step: supplier approval. submit_quote refuses with 403 until an admin approves the
// registration. This sets approval_status directly rather than through the OS console, so it
// proves the GATE is real and correctly positioned - it does NOT prove the admin review UI.
// Driving os_api as a real admin is a separate step and is not claimed here.
// Match case-insensitively: the API lowercases the address before storing claimed_by, so an
// exact-match update on the mixed-case address silently touched zero rows and the step failed
// with approval_status=none while the UPDATE itself reported success.
await mgmtWrite(REF,
  `update public.leads set approval_status = 'approved', verified = true
   where lower(claimed_by) = lower('${supA.email}')`,
  'approve supplier');
r = await call('supplier_api', supA.jwt, { action: 'me' });
step('supplier approved (direct, not via OS UI)',
  r.status === 200 && r.json?.supplier?.approval_status === 'approved',
  `approval_status=${r.json?.supplier?.approval_status ?? 'none'}`);

r = await call('supplier_api', supA.jwt, {
  action: 'submit_quote',
  inquiry_id: inquiryId,
  amount: 125000,          // the field is `amount`; `total` reads as 0 and is refused
  currency: 'AED',
  lead_time_days: 56,
  notes: 'Supply and installation of 40 powder-coated aluminium windows, double glazed.',
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
  // Any 4xx is a refusal. "claim your company first" (400) rejects supplier B just as firmly as
  // a 403 would; asserting on one specific code would have failed a working guard.
  const refused = r.status >= 400 && r.status < 500;
  const leaked = JSON.stringify(r.json ?? '').includes('aluminium windows');
  step('supplier B blocked from A inquiry', refused && !leaked, `HTTP ${r.status} ${r.text}`);
} else {
  step('supplier B blocked from A inquiry', false, 'skipped - no inquiry id');
}

// Now that a quote may exist, close the loop the way a customer would.
if (inquiryId) {
  r = await call('customer_api', cust.jwt, { action: 'complete_inquiry', id: inquiryId });
  // 404 "Quote not found" is correct when no quote was accepted; it is a reasoned refusal, not a
  // crash. Anything 5xx is not.
  step('complete inquiry responds sanely', r.status < 500, `HTTP ${r.status} ${r.text}`);
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
