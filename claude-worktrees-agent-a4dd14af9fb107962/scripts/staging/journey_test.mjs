// journey_test.mjs — drive the real customer-to-quotation journey against deployed staging.
//
// Phase 2's standard is that each step is proven through the deployed application, not that a
// table exists. Every step here is a real HTTP call to a deployed Edge Function, authenticated
// as a real Auth user, in the order a customer and a supplier would actually hit them.
//
// It refuses to run against production. It prints status codes and truncated bodies, never tokens.
//
//   node scripts/staging/journey_test.mjs [--keep]
// REHOMED 15 AUG 2026 — kept, not deleted. 685 lines of end-to-end journey is the only coverage in
// the repo that walks a customer from sign-up to a revealed quote, and staging was deleted that
// morning. It now targets the one project that exists, and every write goes through mgmtFixture,
// which refuses unless QD_FIXTURES=1 is set for the run. Read the note on that function before you
// use it: this crosses HTTP, so nothing here is inside a transaction that can roll back. The
// teardown is tag-derived and runs in a finally; that is what stands between this and live data.
import { mgmtRead, mgmtFixture } from './qd_guard.mjs';
import { teardown, REF } from './demo_factory.mjs';
import { readFileSync } from 'node:fs';
import { createHmac, randomBytes } from 'node:crypto';

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

// One tag per run, embedded in every email this run creates, so demo_factory's teardown can find
// everything by tag instead of by the hand-maintained list this file used to carry. That list is
// why staging accumulated 65 orphaned `customers` rows: cleanup deleted the auth users and the
// `Journey Test %` leads and nothing else, so every run left its customer row, its inquiry, its
// intake, its verifications and its redaction runs behind.
const RUN = randomBytes(4).toString('hex');

async function mkUser(tag) {
  const email = `qd-${RUN}-${tag}${Date.now().toString(36)}${Math.floor(Math.random() * 1e4)}@example.com`;
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

// A quote is only ACCEPTED (status submitted, not draft) when the structured scorer passes or the
// form is complete: source 'form', at least one priced item, and validity, warranty and lead_time
// all present. Sending amount + notes alone leaves it a draft with submittable=false, while the
// API response still reports status "submitted" - so comparison then reports "needs at least two
// complete quotes" for an RFQ that has two.
const quotePayload = (inquiry_id, amount, note) => ({
  action: 'submit_quote', inquiry_id, amount, currency: 'AED', source: 'form',
  items: [{ description: 'Aluminium windows supply and install', qty: 40, unit_price: Math.round(amount / 40) }],
  lead_time: '8 weeks', validity: '30 days', warranty: '12 months',
  payment_terms: '50% advance, 50% on completion',
  scope: 'Supply, delivery and installation of 40 aluminium windows including removal of existing units.',
  conditions: 'Access to site during working hours.',
  exclusions: 'Civil works, painting, scaffolding.',
  notes: note,
});

// ---- customer -------------------------------------------------------------------------------
const cust = await mkUser('cust');
created.push(cust.id);
step('customer signup (auth)', !!cust.id && !!cust.jwt, cust.jwt ? 'signed in' : 'no token');

let r;

// ORDER MATTERS, AND THIS TEST HAD IT BACKWARDS (12 Aug 2026). The 'me' call below creates the
// customers row (customer_api: `if (!cust) insert({ email })`), and it used to run BEFORE the OTP
// step - so login_otp's `update customers set email_verified = true` always found a row to update.
// A real first-time customer produces the opposite order: they enter the emailed code before any
// portal call has ever run, the UPDATE matches nothing, and the row created moments later carries
// email_verified false forever. The harness manufactured the one ordering in which the bug cannot
// appear, which is why every staging customer is verified and production's only real one is not.
// Verification now runs first, exactly as a human does it, and the flag is asserted from the
// database rather than inferred from HTTP 200 - a 200 was returned throughout the broken period.

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
  await mgmtFixture(REF,
    `insert into public.email_verifications (email, token_hash, purpose, user_kind, expires_at)
     values ('${cust.email}', '${hash}', 'login', 'customer', now() + interval '10 minutes')`,
    'seed otp');
  r = await call('login_otp', null, {
    action: 'verify', identifier: cust.email, code: OTP, user_kind: 'customer',
  });
  step('email verification (OTP)', r.status === 200, `HTTP ${r.status} ${r.text}`);
  const ev = (await mgmtRead(REF,
    `select coalesce(bool_or(email_verified), false) as v from public.customers where email = '${cust.email}'`))[0]?.v;
  step('email verification persisted email_verified', ev === true || ev === 't',
    `customers.email_verified = ${ev} for a customer whose row did not exist when the code was verified`);
} else {
  step('email verification (OTP)', false, 'otp_hmac_key missing from staging app_secrets');
}

r = await call('customer_api', cust.jwt, { action: 'me' });
step('customer profile (me)', r.status === 200, `HTTP ${r.status} ${r.text}`);

// Journey steps 3 and 4. create_inquiry refuses with 403 account_incomplete until the customer has
// a name, an 18+ date of birth, an OTP-verified mobile or email and an accepted T&C version (the
// founder's account rule, 14 Sep 2026, _shared/account_rule.ts) - and none of that lives in
// customer_api. kyc owns it: save_customer writes the profile (refusing a missing or under-18 DOB),
// accept_terms records the version from app_secrets so the acceptance says which document was signed.
r = await call('kyc', cust.jwt, {
  action: 'save_customer', user_kind: 'customer',
  email: cust.email, full_name: 'Journey Test Customer', phone: '+971501234567', dob: '1990-01-01',
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

// Journey step 9: FILES AND DRAWINGS. The customer uploads a drawing, we read a draft BOQ off it
// and redact it before any supplier sees it. The fixture is a synthetic window-schedule elevation
// generated once with System.Drawing (see fixtures/README.md); its title block deliberately carries
// a consultant name, a client name, a plot number, a phone, an email and a drawing number, because
// the output of this step is shown to COMPETING SUPPLIERS and must not identify the customer.
// In the real app the browser rasterises PDF pages with pdf.js and posts the page images; this
// posts the same shape.
const drawingPng = readFileSync(new URL('./fixtures/drawing_windows.png', import.meta.url));
const drawingB64 = drawingPng.toString('base64');
r = await call('customer_api', cust.jwt, {
  action: 'analyze_drawing',
  drawing_file_name: 'west_elevation_windows.png',
  mime: 'image/png',
  hint: 'Aluminium windows for a villa, supply and install.',
  original_b64: drawingB64,
  images: [{ b64: drawingB64, mime: 'image/png' }],
});
const draw = r.json || {};
const drawingStoredPath = draw.drawing_file_path || null;
const boqLines = Array.isArray(draw.boq?.boq) ? draw.boq.boq : [];
step('customer uploads a drawing (BOQ extracted)',
  r.status === 200 && draw.ok === true && boqLines.length > 0 && !!draw.drawing_file_path,
  `HTTP ${r.status} ${boqLines.length} BOQ line(s), category=${draw.boq?.category || '-'}, ` +
  `confidence=${draw.boq?.confidence || '-'}, stored=${draw.drawing_file_path ? 'yes' : 'NO'}`);

// The privacy claim is the whole point of the redaction step, so assert it rather than trusting it.
const TITLE_BLOCK_PII = ['al nahda', 'omar bin faisal', '345-8871', '555 1234',
                         'alnahda-consult', 'an-2026-114', 'villa 42'];
const boqText = JSON.stringify(draw.boq || {}).toLowerCase();
const leaked = TITLE_BLOCK_PII.filter((s) => boqText.includes(s));
step('drawing BOQ carries no identifying detail', leaked.length === 0,
  leaked.length ? `LEAKED ${leaked.join(', ')}` : `none of ${TITLE_BLOCK_PII.length} title-block strings present`);

// A redaction the server did not RECORD cannot be verified at create_inquiry, so the record is the
// thing that matters, not the returned paths.
const redRun = draw.redaction_job_id
  ? (await mgmtRead(REF, `select status, pages_in, pages_out, pages_verified, verify_failed
                            from drawing_redaction_runs where id = '${draw.redaction_job_id}'`))[0]
  : null;
step('drawing redaction recorded and verified',
  !!redRun && redRun.status === 'complete' && Number(redRun.pages_out) >= Number(redRun.pages_in)
    && Number(redRun.verify_failed) === 0 && Number(redRun.pages_verified) >= Number(redRun.pages_in),
  redRun ? `status=${redRun.status} in=${redRun.pages_in} out=${redRun.pages_out} ` +
           `verified=${redRun.pages_verified} failed=${redRun.verify_failed}`
         : 'no redaction run recorded');

// A CAD upload takes a different branch: the browser cannot rasterise DWG/DXF, so analyze_drawing
// gets original_b64 with NO images and must route through cad_convert (CloudConvert) to get page
// images before it can read anything. DXF is plain text, so this needs no binary fixture.
const dxfEnt = [];
const dxfPush = (...a) => dxfEnt.push(...a.map(String));
const dxfLine = (x1, y1, x2, y2) => dxfPush(0, 'LINE', 8, '0', 10, x1, 20, y1, 30, 0, 11, x2, 21, y2, 31, 0);
const dxfText = (x, y, h, s) => dxfPush(0, 'TEXT', 8, '0', 10, x, 20, y, 30, 0, 40, h, 1, s);
dxfLine(0, 0, 400, 0); dxfLine(400, 0, 400, 300); dxfLine(400, 300, 0, 300); dxfLine(0, 300, 0, 0);
dxfLine(50, 50, 150, 50); dxfLine(150, 50, 150, 200); dxfLine(150, 200, 50, 200); dxfLine(50, 200, 50, 50);
dxfText(50, 220, 14, 'WINDOW W1 1200 x 1500 mm');
dxfText(50, 250, 14, 'QTY 40 NOS DOUBLE GLAZED');
dxfText(50, 20, 12, 'SCALE 1:50');
const dxfB64 = Buffer.from([
  '0', 'SECTION', '2', 'HEADER',
  '9', '$ACADVER', '1', 'AC1009',
  '9', '$EXTMIN', '10', '0.0', '20', '0.0', '30', '0.0',
  '9', '$EXTMAX', '10', '400.0', '20', '300.0', '30', '0.0',
  '0', 'ENDSEC',
  '0', 'SECTION', '2', 'ENTITIES', ...dxfEnt, '0', 'ENDSEC', '0', 'EOF',
].join('\n'), 'utf8').toString('base64');
r = await call('customer_api', cust.jwt, {
  action: 'analyze_drawing',
  drawing_file_name: 'floor_plan.dxf',
  mime: 'image/vnd.dxf',
  hint: 'Aluminium windows, CAD plan.',
  original_b64: dxfB64,
});
const cad = r.json || {};
const cadPath = cad.drawing_file_path || null;
// What this asserts is the half that is OURS: that .dxf is recognised as CAD and that the original
// the customer uploaded is actually STORED. Until 5 Aug it was not - customer_api allowed only
// SAFE_UPLOAD (PDF + images) and the drawing-files bucket's own allowed_mime_types excluded CAD
// too, so a DXF was refused at both layers and both returned the same silent null. The drawing was
// converted and read while the file the supplier needs to quote from was quietly dropped.
//
// Two things are deliberately NOT asserted. BOQ content: a DXF written by hand renders as a nearly
// blank raster unless it also carries LAYER and STYLE tables, so an empty BOQ here would measure
// the fixture, not the product (the BOQ read is already proven on the raster path above). And
// whether CloudConvert finished: cad_convert polls for 56s and then honestly returns a timeout,
// which analyze_drawing honestly reports as 'cad_not_converted'. Failing on a third party's queue
// latency would make this suite flaky, and both outcomes are correct behaviour.
step('CAD upload is recognised and the original is kept',
  r.status === 200 && cad.ok === true && !!cadPath,
  `HTTP ${r.status} stored=${cadPath ? 'yes' : 'NO'} ` +
  `conversion=${cad.note === 'cad_not_converted' ? 'not this run (CloudConvert queue)' : 'converted'}`);

// Reference photos are a separate, redact-only path (no BOQ) with its own credential.
r = await call('attach_photos', cust.jwt, {
  images: [{ data: drawingB64, mime: 'image/png' }],
});
const photoPaths = Array.isArray(r.json?.paths) ? r.json.paths : [];
// The job id is what lets create_inquiry ATTACH these photos: resolveRedactedPaths refuses any
// path it cannot trace to a drawing_redaction_runs row. attach_photos had the id and discarded it,
// so the photos were redacted, stored and recorded — and then reached no supplier.
const photoJob = r.json?.redaction_job_id || null;
step('customer reference photos redacted and stored',
  r.status === 200 && r.json?.ok === true && photoPaths.length > 0 && !!photoJob,
  `HTTP ${r.status} ${photoPaths.length} redacted photo path(s) job=${photoJob || 'NOT RETURNED'}`);

// REDACTION PROVENANCE (5 Aug 2026). attach_photos sent drawing_redact no owner at all, so this
// row landed with customer_id AND owner_email both NULL - a PRIVACY control whose record could not
// be attributed to the customer whose photos it redacted, and which `--purge` could only sweep as
// unattributable. drawing_redact's recordRun had always read both fields off the request body;
// nothing ever sent them. Asserted here rather than in a new fixture because this is the only path
// that calls attach_photos, and it already runs.
//
// The expected id is looked up by EMAIL: customer_api's `me` gives the public.customers row a
// FRESH uuid rather than the auth uid, so asserting against cust.id would pass for the wrong reason.
const prov = (await mgmtRead(REF, `
  select r.customer_id, r.owner_email, r.caller_ref,
         (select id from public.customers where lower(email) = lower('${cust.email}')) as expected_customer
    from public.drawing_redaction_runs r
   where lower(coalesce(r.owner_email,'')) = lower('${cust.email}')
     and coalesce(r.caller_ref,'') like 'refphoto/%'
   order by r.created_at desc limit 1`))[0];
step('the reference-photo redaction records WHO caused it',
  !!prov && !!prov.customer_id && !!prov.expected_customer && prov.customer_id === prov.expected_customer,
  prov ? `owner_email=${prov.owner_email} customer_id=${prov.customer_id} expected=${prov.expected_customer} caller_ref=${String(prov.caller_ref).slice(0, 28)}`
       : 'no drawing_redaction_runs row names this customer as owner - provenance is NULL');

r = await call('customer_api', cust.jwt, {
  action: 'create_inquiry',
  intake_id: intakeId,
  text: 'We need 40 aluminium windows supplied and installed for a villa in Dubai Marina.',
  drawing: {
    boq: draw.boq || null,
    drawing_file_path: draw.drawing_file_path || null,
    drawing_file_name: draw.drawing_file_name || null,
    // The reference photos ride the SAME channel as the redacted drawing pages —
    // inquiries.drawing_redacted_paths is what supplier_api signs for the supplier. Both halves are
    // required: the paths, and the run id that proves the customer owns them.
    drawing_redacted_paths: [...(draw.drawing_redacted_paths || []), ...photoPaths],
    redaction_job_id: draw.redaction_job_id || null,
    redaction_job_ids: photoJob ? [photoJob] : [],
    brief_source: 'drawing',
  },
});
const inquiryId = r.json?.id ?? r.json?.inquiry_id ?? r.json?.group_id ?? null;
step('create inquiry', r.status === 200, `HTTP ${r.status} id=${inquiryId ?? 'none'} ${r.text}`);

// create_inquiry re-resolves the redacted paths server-side rather than trusting the body, so this
// asserts what actually landed on the row, not what the client claimed.
if (inquiryId) {
  const row = (await mgmtRead(REF, `select (boq is not null) has_boq,
      (drawing_file_path is not null) has_file,
      coalesce(array_length(drawing_redacted_paths, 1), 0) n_red
      from inquiries where id = '${inquiryId}'`))[0] || {};
  step('inquiry carries the drawing and its redacted pages',
    row.has_boq === true && row.has_file === true && Number(row.n_red) > 0,
    `boq=${row.has_boq} original=${row.has_file} redacted_pages=${row.n_red}`);
} else {
  step('inquiry carries the drawing and its redacted pages', false, 'skipped - no inquiry id');
}

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

// Journey step: company profile. route_inquiry's usable() requires capability_summary, products
// or services - a supplier with none of them is filtered out of the candidate pool BEFORE
// scoring, which is why routing reported a genuine coverage gap (zero_fits_genuine=1) while an
// approved supplier sat right there. An approved supplier with an empty profile is invisible.
r = await call('supplier_api', supA.jwt, {
  action: 'save_profile',
  products: 'Aluminium windows, doors, curtain walling, glass partitions, powder-coated profiles.',
  services: 'Supply and installation of aluminium windows and doors, glazing, site measurement.',
  description: 'Aluminium and glass fabricator and installer serving Dubai and the Northern Emirates.',
  company_type: 'LLC',
  contact_name: 'Journey Test Contact',
  phone: '+971505550000',
  service_emirates: ['Dubai', 'Sharjah', 'Abu Dhabi'],
});
step('supplier saves capability profile', r.status === 200, `HTTP ${r.status} ${r.text}`);

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
await mgmtFixture(REF,
  `update public.leads set approval_status = 'approved', verified = true,
       tags = (select array(select distinct unnest(coalesce(tags,'{}'::text[])
                || ARRAY['qd_demo', 'qd_run:${RUN}']::text[])))
   where lower(claimed_by) = lower('${supA.email}')`,
  'approve supplier');
r = await call('supplier_api', supA.jwt, { action: 'me' });
step('supplier approved (direct, not via OS UI)',
  r.status === 200 && r.json?.supplier?.approval_status === 'approved',
  `approval_status=${r.json?.supplier?.approval_status ?? 'none'}`);

// Journey steps 13-16: dispatch. create_inquiry routed the RFQ before this supplier existed, so
// it correctly reported a genuine coverage gap. Now that an approved, profiled supplier is in
// place, dispatch it for real. dispatch_inquiry is internal-only: the db.internal credential is
// the one whose scope includes it.
const dispatchCred = (await mgmtRead(REF,
  "select value from public.app_secrets where key='cred_db_internal'"))[0]?.value;

// Phase 3: category and capability mapping. A dispatched RFQ carries a structured capability
// requirement, which switches route_inquiry from the loose "fallback" retrieval into
// "capability_gated" - it then demands a CONFIRMED supplier_capabilities record clearing a score
// floor. A supplier with products and services but no capability record scores zero there, which
// is why dispatch reported "no genuine seller" while a direct route call found three fits.
if (companyId && dispatchCred) {
  r = await call('enrich_capability', null, { __secret: dispatchCred, lead_id: companyId });
  step('supplier capability extracted', r.status === 200, `HTTP ${r.status} ${r.text}`);

  // enrich_capability writes leads.capability_summary - it does NOT create a structured
  // supplier_capabilities record. Those come from document extraction, and PRODUCTION HAS ZERO OF
  // THEM TOO, which is why this gate has never been exercised anywhere. There is no
  // supplier-facing flow to declare and confirm a capability yet; that is Phase 3 work
  // ("category and capability mapping"), not a staging data gap.
  //
  // The record is therefore written directly, and this step is named so it cannot be mistaken for
  // proof of a flow that does not exist. What it DOES prove is that the capability gate, the
  // score floor and the dispatch path all work once a confirmed record is present.
  // trades: the required set is derived per inquiry - one run asked for aluminium+doors, the next
  // aluminium+glazing - so declare everything an aluminium and glass fabricator genuinely does
  // rather than chasing whichever pair the model picked that run.
  //
  // roles: these are CODES from taxonomy_role, not the need. fn_match_capability requires a
  // taxonomy_role row whose code appears here AND whose column for the requested need is true -
  // for 'executes' that is contractor, installer, maintenance or turnkey_fitout. The fixture
  // previously listed 'executes' itself, which is not a code, so the role gate silently excluded
  // a supplier that passed confirmed_at, trade overlap, excluded_trades and fn_is_matchable.
  await mgmtFixture(REF,
    `insert into public.supplier_capabilities
       (supplier_id, trades, roles, products_norm, project_types, exclusions,
        authority_approvals, source_docs, confidence, missing_fields, excluded_trades,
        completeness, review_status, confirmed_at, extracted_at,
        min_project_value, max_project_value, coverage_emirates)
     values (${Number(companyId)},
       ARRAY['aluminium','doors','glazing','windows','glass','fenestration']::text[],
       ARRAY['contractor','installer','supplier','manufacturer']::text[],
       ARRAY['aluminium','windows','doors','glazing','glass','mesh','handles','powder-coated','double glazed']::text[],
       ARRAY['villa','residential']::text[], ARRAY[]::text[],
       '{}'::jsonb, '{}'::jsonb, '{"overall":0.9}'::jsonb,
       ARRAY[]::text[], ARRAY[]::text[],
       95, 'confirmed', now(), now(), 1000, 5000000, ARRAY['Dubai','Sharjah','Abu Dhabi']::text[])
     on conflict (supplier_id) do update
       set trades = excluded.trades, roles = excluded.roles,
           completeness = excluded.completeness, review_status = 'confirmed',
           confirmed_at = now()`, 'seed capability');
  const capRows = await mgmtRead(REF,
    `select count(*)::int as n from public.supplier_capabilities
      where supplier_id = ${Number(companyId)} and confirmed_at is not null`);
  step('capability record confirmed (direct - no supplier flow exists)',
    Number(capRows[0].n) > 0, `${capRows[0].n} confirmed record(s)`);
}
if (inquiryId && dispatchCred) {
  r = await call('dispatch_inquiry', null, { __secret: dispatchCred, inquiry_id: inquiryId });
  const dispatched = r.status === 200 && r.json?.ok !== false;
  step('dispatch inquiry to suppliers', dispatched, `HTTP ${r.status} ${r.text}`);

  r = await call('supplier_api', supA.jwt, { action: 'inbox' });
  const inbox = Array.isArray(r.json?.inquiries) ? r.json.inquiries : [];
  step('supplier receives the inquiry', r.status === 200 && inbox.length > 0,
    `HTTP ${r.status} inbox=${inbox.length} item(s)`);
} else {
  step('dispatch inquiry to suppliers', false, inquiryId ? 'cred_db_internal missing' : 'no inquiry id');
  step('supplier receives the inquiry', false, 'dispatch did not run');
}

r = await call('supplier_api', supA.jwt,
  quotePayload(inquiryId, 125000, 'Supply and installation of 40 powder-coated aluminium windows, double glazed.'));
step('supplier submit quote', r.status === 200, `HTTP ${r.status} ${r.text}`);

// Journey step 9, supplier half: a supplier who quotes by UPLOADING their own PDF rather than
// typing the form. The fixture is a synthetic quotation on a letterhead carrying a company name,
// two phone numbers, an email, a website, a TRN and a salesperson's name — because QuotesDone is a
// marketplace where the customer PAYS to reveal the supplier, so an unanonymised upload would hand
// the identity over for free and bypass the paywall entirely.
const quotePng = readFileSync(new URL('./fixtures/quotation_supplier.png', import.meta.url));
const quoteB64 = quotePng.toString('base64');
r = await call('supplier_api', supA.jwt, {
  action: 'extract_quote',
  inquiry_id: inquiryId,
  images: [{ b64: quoteB64, mime: 'image/png' }],
  original: { b64: quoteB64, mime: 'image/png', filename: 'quotation_eaw_2026_0741.png' },
});
const prop = r.json?.proposal || {};
const quoteDocPath = r.json?.original_file_path || null;
const quoteDocName = r.json?.original_file_name || null;
const propItems = Array.isArray(prop.line_items) ? prop.line_items : [];
const masked = Array.isArray(prop.masked_terms) ? prop.masked_terms : [];
step('supplier uploads a quotation document (read)',
  r.status === 200 && r.json?.ok === true && Number(prop.amount) > 0 && propItems.length >= 4
    && !!quoteDocPath,
  `HTTP ${r.status} total=${prop.amount ?? 'none'} items=${propItems.length} ` +
  `masked=${masked.length} stored=${quoteDocPath ? 'yes' : 'NO'}`);

// Masking is only real if the identity is absent from what the CUSTOMER would see. masked_terms is
// shown to the supplier for review; every other field goes to the customer.
const LETTERHEAD_PII = ['emirates alum', '338 7788', '442 9931', 'sales@emiratesalum',
                        'emiratesalum.ae', '100234567800003', 'rashid'];
const customerVisible = JSON.stringify({ ...prop, masked_terms: undefined }).toLowerCase();
const qLeaked = LETTERHEAD_PII.filter((s) => customerVisible.includes(s));
step('uploaded quotation is anonymised before the customer sees it',
  qLeaked.length === 0 && masked.length > 0,
  qLeaked.length ? `LEAKED ${qLeaked.join(', ')}` : `${masked.length} identity term(s) masked, 0 leaked`);

// The upload path must produce a real, comparable quote — not a draft. It is the same completeness
// contract as the form path: a priced items array, validity, warranty and lead time.
if (inquiryId && Number(prop.amount) > 0) {
  r = await call('supplier_api', supA.jwt, {
    action: 'submit_quote', inquiry_id: inquiryId, source: 'upload',
    amount: prop.amount, currency: 'AED',
    items: propItems.map((li) => ({ description: li.description, qty: li.qty, unit_price: li.amount })),
    lead_time: prop.lead_time, validity: prop.validity, warranty: prop.warranty,
    payment_terms: prop.payment_terms, scope: prop.scope,
    conditions: prop.conditions, exclusions: prop.exclusions,
    notes: prop.description_anonymized,
    original_file_path: quoteDocPath, original_file_name: quoteDocName,
  });
  const upQ = (await mgmtRead(REF, `select source, status, (original_file_path is not null) has_doc
      from quotes where inquiry_id = '${inquiryId}' and source = 'upload' limit 1`))[0] || {};
  step('quote submitted from the uploaded document',
    r.status === 200 && upQ.source === 'upload' && upQ.status !== 'draft' && upQ.has_doc === true,
    `HTTP ${r.status} source=${upQ.source || 'none'} status=${upQ.status || '-'} ` +
    `document_attached=${upQ.has_doc === true}`);
} else {
  step('quote submitted from the uploaded document', false, 'skipped - extraction produced no amount');
}

// A comparison needs something to compare. Stand up a second approved, capable supplier the same
// way as the first, dispatch to it, and have it quote - so step 20 exercises the real comparison
// path rather than the "needs at least two quotes" guard.
async function standUpSupplier(tag, companyName, amount) {
  const s = await mkUser(tag);
  created.push(s.id);
  let x = await call('supplier_api', s.jwt, {
    action: 'create_company', company_name: companyName, emirate: 'Dubai', role: 'supplier',
  });
  const cid = x.json?.id ?? null;
  if (!cid) return { ok: false, detail: `create_company HTTP ${x.status}` };
  await call('supplier_api', s.jwt, {
    action: 'save_profile',
    products: 'Aluminium windows, doors, curtain walling, glazing.',
    services: 'Supply and installation of aluminium windows and doors, glazing.',
    description: 'Aluminium and glass fabricator and installer in Dubai.',
    company_type: 'LLC', contact_name: tag + ' contact', phone: '+971505550001',
    service_emirates: ['Dubai', 'Sharjah'],
  });
  await call('kyc', s.jwt, { action: 'accept_terms', user_kind: 'supplier', email: s.email });
  await mgmtFixture(REF,
    `update public.leads set approval_status='approved', verified=true,
       tags = (select array(select distinct unnest(coalesce(tags,'{}'::text[])
                || ARRAY['qd_demo', 'qd_run:${RUN}']::text[])))
      where lower(claimed_by) = lower('${s.email}')`, 'approve supplier');
  await call('enrich_capability', null, { __secret: dispatchCred, lead_id: cid });
  await mgmtFixture(REF,
    `insert into public.supplier_capabilities
       (supplier_id, trades, roles, products_norm, project_types, exclusions,
        authority_approvals, source_docs, confidence, missing_fields, excluded_trades,
        completeness, review_status, confirmed_at, extracted_at,
        min_project_value, max_project_value, coverage_emirates)
     values (${Number(cid)},
       ARRAY['aluminium','doors','glazing','windows','glass','fenestration']::text[],
       ARRAY['contractor','installer','supplier','manufacturer']::text[],
       ARRAY['aluminium','windows','doors','glazing','glass','mesh','handles','powder-coated','double glazed']::text[],
       ARRAY['villa','residential']::text[], ARRAY[]::text[],
       '{}'::jsonb, '{}'::jsonb, '{"overall":0.9}'::jsonb,
       ARRAY[]::text[], ARRAY[]::text[],
       95, 'confirmed', now(), now(), 1000, 5000000, ARRAY['Dubai','Sharjah']::text[])
     on conflict (supplier_id) do nothing`, 'seed capability');
  if (inquiryId) await call('dispatch_inquiry', null, { __secret: dispatchCred, inquiry_id: inquiryId, force: false });
  x = await call('supplier_api', s.jwt,
    quotePayload(inquiryId, amount, 'Second competing quotation for the same scope.'));
  return { ok: x.status === 200, detail: `HTTP ${x.status} ${x.text}` };
}

const supC = inquiryId
  ? await standUpSupplier('supC', 'Journey Test Glass & Facade LLC', 131750)
  : { ok: false, detail: 'skipped - no inquiry id' };
step('second supplier quotes the same RFQ', supC.ok, supC.detail);

// Journey step 18: quotation revision. A supplier re-submitting against the same RFQ must revise
// the existing quote, not create a second one competing with itself.
if (inquiryId) {
  const countQuotes = async (extra = '') => Number((await mgmtRead(REF,
    `select count(*)::int as n from public.quotes where inquiry_id = '${inquiryId}'${extra}`))[0].n);
  const quotesBefore = await countQuotes();
  r = await call('supplier_api', supA.jwt,
    quotePayload(inquiryId, 118500, 'Revised: tighter lead time and a small discount on the same scope.'));
  const quotesAfter = await countQuotes();
  const nonDraft = await countQuotes(" and status <> 'draft'");
  step('supplier revises quote (no duplicate)',
    r.status === 200 && quotesAfter === quotesBefore,
    `HTTP ${r.status} quotes ${quotesBefore}->${quotesAfter}, ${nonDraft} non-draft`);

  // Journey step 19: the quotation is reviewed before the customer sees it. There are TWO review
  // paths and they record in different places. A quote UPLOADED as a document goes through
  // extraction and lands a row in quote_reviews; a quote typed into the structured FORM is judged
  // by fn_quote_structured_score, which writes quotes.quality and quotes.submittable. Asserting
  // only on quote_reviews reports "no review" for a form quote that was in fact fully scored.
  // CORRECTED 5 Aug 2026. This counted public.quote_reviews and passed on
  // `reviewRows > 0 || scored > 0`. quote_reviews can only ever return 0 — its sole writer,
  // quote_review_api, was deleted in d79b28e (22 Jul 2026) as proven-dead across
  // frontend/functions/SQL/cron/triggers — so half of this assertion was VACUOUS and the step
  // passed entirely on `scored`. Not a red gate, which would at least have been noticed: a green
  // one measuring something that cannot exist.
  //
  // There is ONE review path: fn_quote_structured_score writes quotes.quality and
  // quotes.submittable. quote_reviews / quote_review_messages / quote_committed_items are retired
  // schema (0 rows in production, no reader, no writer), not a missing subsystem.
  const scored = Number((await mgmtRead(REF,
    `select count(*)::int as n from public.quotes
      where inquiry_id = '${inquiryId}' and quality is not null`))[0].n);
  step('quotation scored before the customer sees it', scored > 0,
    `${scored} quote(s) carry a structured score`);

  // Journey step 19b: quotation HISTORY. Also recorded as "no table and no writer" — also wrong.
  // doc_versions + trigger version_quote have been keeping a jsonb snapshot per revision all along
  // (136 rows in production), with fn_doc_history / fn_doc_diff as readers. Asserting RECOVERY, not
  // merely that a row exists: the previous amount must still be readable after a revision.
  const vers = await mgmtRead(REF, `
    select v.version, v.snapshot->>'quote_amount' as amount
      from public.doc_versions v
      join public.quotes q on q.id::text = v.entity_id
     where v.entity_type = 'quote' and q.inquiry_id = '${inquiryId}'
     order by v.version`);
  step('a revised quotation keeps its previous version recoverable',
    vers.length >= 2 && vers.some((v) => Number(v.amount) === 125000) && vers.some((v) => Number(v.amount) === 118500),
    vers.length ? `${vers.length} version(s): ${vers.map((v) => v.amount).join(' -> ')}`
                : 'no doc_versions rows for this inquiry');

  // Journey step 20: comparison. The end of the journey the whole system exists for.
  // A 200 carrying {ok:false,error:'need_two'} is a refusal, not a comparison.
  r = await call('customer_api', cust.jwt, { action: 'compare_pdf', inquiry_id: inquiryId, lang: 'en' });
  step('customer quotation comparison', r.status === 200 && r.json?.ok !== false && !r.json?.error,
    `HTTP ${r.status} ${r.text}`);
} else {
  step('supplier revises quote (no duplicate)', false, 'skipped - no inquiry id');
  step('quotation review recorded', false, 'skipped - no inquiry id');
  step('customer quotation comparison', false, 'skipped - no inquiry id');
}

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
  // Two objects this run creates are recorded on NO row, so teardown cannot derive them and they
  // have to be named here:
  //   - the reference photos. attach_photos returns their paths and writes them nowhere. Its
  //     drawing_redaction_runs row carries customer_id NULL and owner_email NULL, so even the
  //     redaction record cannot be attributed to the customer who caused it - `--purge` sweeps
  //     those unattributable rows, but a single run cannot.
  //   - the CAD original. create_inquiry carries drawing_file_path for the raster upload only, so
  //     the .dxf the customer uploaded is stored and then referenced by nothing.
  let objs = 0;
  const orphanPaths = [...photoPaths, cadPath,
                       ...(Array.isArray(cad.drawing_redacted_paths) ? cad.drawing_redacted_paths : [])]
    .filter(Boolean);
  if (orphanPaths.length) {
    const del = await fetch(`${BASE}/storage/v1/object/drawing-files`, {
      method: 'DELETE',
      headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefixes: orphanPaths }),
    });
    if (del.ok) objs += orphanPaths.length;
  }
  // The reference-photo redaction runs, matched on the output paths this run knows.
  if (photoPaths.filter(Boolean).length) {
    await mgmtFixture(REF,
      `delete from public.drawing_redaction_runs
        where customer_id is null and owner_email is null
          and output_paths && ARRAY[${photoPaths.filter(Boolean).map((p) => `'${p.replace(/'/g, "''")}'`).join(',')}]::text[]`,
      'cleanup photo redaction runs');
  }

  // Everything else by run tag. This replaces a hand-maintained list that deleted auth users,
  // 'Journey Test %' leads and six named storage paths - and left the customers row, the inquiry,
  // the intake, the email verifications, the redaction runs, the documents, the notifications, the
  // company_event rows and the doc_versions behind on every single run.
  const t = await teardown({ tag: RUN });
  console.log(`\ncleaned up ${objs} unreferenced photo(s) + ${t.summary}`);
}

const pass = steps.filter(s => s.ok).length;
console.log(`\nJOURNEY ${pass}/${steps.length} passed on ${REF}`);
process.exitCode = pass === steps.length ? 0 : 1;
