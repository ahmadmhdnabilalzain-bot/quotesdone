// scripts/e2e/fixtures.mjs — demo identities WITHOUT anyone's credentials (14 Sep 2026).
// Assigned: ceo (it_engineer's tooling, carried out for the ceo).
//
// The founder: "do what is needed cause you need to keep browsing stuff without my credentials".
// This module mints complete ZZ DEMO customers and suppliers on the one production project, signs them
// in without delivering an OTP, and destroys everything a run created. It builds on
// scripts/staging/demo_factory.mjs (auth admin, teardown by tag, the OTP hop) rather than beside it.
//
// WHO THEY ARE
//   email   qd-<tag>-<kind><n>@example.invalid   RFC 2606: nobody can receive mail there
//   mobile  +971 50 000 00xx                     the reserved fixture block
//   name    ZZ DEMO …                            the estate's convention since 7 Aug 2026
// Each of those alone sets the database's derived customers.is_demo / leads.is_demo, and those drive
// every guard (scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql): a demo
// account is never matched to a real one, nothing addressed to it or about it is dispatched, it is never
// counted in a business figure, and it can only ever pay in Stripe TEST mode.
//
// HOW THEY SIGN IN (no OTP delivery, no change to real users' auth)
//   The Auth admin API creates the user with email_confirm=true and a random password held only in this
//   process; the password grant returns a normal Supabase session; browser.mjs writes that session into
//   the portal's own storage keys. Real users sign in by OTP exactly as before - nothing in Auth's
//   configuration was changed, and no test-OTP numbers were registered with the provider.
//   The EMAIL verification still runs through the real login_otp endpoint (the code is seeded hashed,
//   exactly as login_otp stores it; only delivery is skipped). The MOBILE verification is recorded
//   directly: Twilio Verify cannot be driven without sending an SMS, and the number is fake by design.
import { readFileSync } from 'node:fs';
import { newRun, mkAuthUser, makeSupplier, teardown, verifyEmailByOtp, call, keys, uploadObject, q, num, REF, BASE } from '../staging/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../staging/qd_guard.mjs';
import { demoTradeLicence } from '../lib/demo_pdf.mjs';

export { REF, BASE, call };
export const read = (sql) => mgmtRead(REF, sql);
export const write = (sql, where = 'e2e fixture') => mgmtFixture(REF, sql, where);

export const demoEmail = (run, kind) => `qd-${run.tag}-${kind}${run.seq++}@example.invalid`;
// 00-89 only. 90-99 are reserved for checks that need a fixture number NO run can hold at the same
// time (a_phone_cannot_select_an_account uses 98 as "unknown" and 97 as "shared"). On 14 Sep a run
// handed out 42 while that check still used 42 as its unknown number, and production answered it
// as a known supplier.
let mobileSeq = Math.floor(Math.random() * 60);
export const demoMobile = () => '+9715000000' + String((mobileSeq++) % 90).padStart(2, '0');

/** Open a run: a tag for every row, and a rehearsal window so the failed-run watcher never pages the founder. */
export async function openRun(opts = {}) {
  if (process.env.QD_FIXTURES !== '1') process.env.QD_FIXTURES = '1';   // this module IS the fixture door
  const run = newRun({ quiet: true, ...opts });
  run.ids = { inquiries: new Set(), quotes: new Set(), leads: new Set(), customers: new Set(), storage: [] };
  await write(`insert into public.rehearsal_window (run_tag, opened_by, note)
               values (${q('qd_run:' + run.tag)}, 'scripts/e2e/run.mjs', 'e2e harness run')`, 'rehearsal window');
  return run;
}

/** Tear everything down (unless kept), close the window, and prove nothing was left behind. */
export async function closeRun(run, { keep = false } = {}) {
  let removed = { summary: 'kept' };
  try {
    if (!keep) {
      // Inquiries created through the UI carry no run tag of their own; tag them so teardown's scope,
      // which is derived from the database rather than from a list, reaches them (and their quotes,
      // holds, notifications, documents) even if the customer row were already gone.
      const inq = [...run.ids.inquiries];
      if (inq.length) await write(`update public.inquiries set provenance = coalesce(provenance,'{}'::jsonb) || ${q(JSON.stringify({ qd_run: run.tag, source: 'e2e' }))}::jsonb
                                    where id in (${inq.map(q).join(',')})`, 'tag e2e inquiries');
      removed = await teardown(run);
      // Objects named with the run tag that no row points at any more (a signed PDF whose row went first).
      const stray = await read(`select bucket_id b, name from storage.objects where name like ${q('%' + run.tag + '%')}`);
      for (const o of stray) await deleteObject(o.b, o.name);
    }
  } finally {
    // ALWAYS closed, even when teardown throws. An open window silences the failed-run watcher for up
    // to six hours - the first harness run left one open exactly that way (14 Sep 2026).
    await write(`update public.rehearsal_window set ended_at = now() where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'rehearsal window');
  }
  return { removed, leftovers: keep ? null : await leftovers(run) };
}

async function deleteObject(bucket, name) {
  const { SERVICE } = await keys();
  await fetch(`${BASE}/storage/v1/object/${bucket}`, {
    method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefixes: [name] }),
  });
}

/** Every table a run can write, counted by the run's own handles. A clean run reads zero on every line. */
export async function leftovers(run) {
  const t = run.tag, like = `'qd-${t}-%'`;
  const ids = (s) => [...s].map(q).join(',') || 'null';
  const r = (await read(`select
      (select count(*) from auth.users where email like ${like})::int auth_users,
      (select count(*) from public.customers where email like ${like})::int customers,
      (select count(*) from public.leads where ${q('qd_run:' + t)} = any(coalesce(tags,'{}')) or claimed_by like ${like} or email like ${like})::int leads,
      (select count(*) from public.inquiries where provenance->>'qd_run' = ${q(t)} or id::text in (${ids(run.ids.inquiries)}))::int inquiries,
      (select count(*) from public.quotes where id::text in (${ids(run.ids.quotes)}))::int quotes,
      (select count(*) from public.quote_spec_hold where quote_id::text in (${ids(run.ids.quotes)}))::int quote_spec_hold,
      (select count(*) from public.notifications where to_email like ${like} or inquiry_id::text in (${ids(run.ids.inquiries)}) or quote_id::text in (${ids(run.ids.quotes)}))::int notifications,
      (select count(*) from public.transactions where quote_id::text in (${ids(run.ids.quotes)}))::int transactions,
      (select count(*) from public.refunds where quote_id::text in (${ids(run.ids.quotes)}) or inquiry_id::text in (${ids(run.ids.inquiries)}))::int refunds,
      (select count(*) from public.supplier_dues where quote_id::text in (${ids(run.ids.quotes)}) or supplier_id::text in (${ids(run.ids.leads)}))::int supplier_dues,
      (select count(*) from public.refund_case where refund_id in (select id from public.refunds where quote_id::text in (${ids(run.ids.quotes)})))::int refund_case,
      (select count(*) from public.inquiry_intake where email like ${like})::int inquiry_intake,
      (select count(*) from public.email_verifications where email like ${like})::int email_verifications,
      (select count(*) from storage.objects where name like ${q('%' + t + '%')})::int storage_objects`))[0];
  return { ...r, total: Object.values(r).reduce((a, b) => a + Number(b), 0) };
}

async function passwordSession(email, password) {
  const { ANON } = await keys();
  const r = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const s = await r.json();
  if (!s.access_token) throw new Error(`sign-in failed for ${email}: HTTP ${r.status}`);
  return s;   // { access_token, refresh_token, expires_in, expires_at, token_type, user }
}

/**
 * A customer with everything the account rule (_shared/account_rule.ts) requires: a name, an 18+ date
 * of birth, a verified email AND mobile, and the CURRENT customer terms accepted and signed.
 */
export async function makeDemoCustomer(run, { locale = 'en', label = 'Customer' } = {}) {
  const email = demoEmail(run, 'cust');
  const phone = demoMobile();
  const fullName = `ZZ DEMO ${label} ${run.tag}`;
  const u = await mkAuthUser(run, email);
  const steps = {};
  steps.save = await call('kyc', u.jwt, { action: 'save_customer', user_kind: 'customer', email, full_name: fullName, phone, dob: '1990-01-15' });
  steps.email_otp = await verifyEmailByOtp(email, 'customer');
  await write(`update public.customers set phone_verified = true, locale = ${q(locale)} where email = ${q(email)}`, 'demo mobile verified');
  steps.terms = await call('kyc', u.jwt, { action: 'accept_terms', user_kind: 'customer', email });
  const row = (await read(`select c.id, c.full_name, c.date_of_birth, c.email_verified, c.phone_verified, c.is_demo,
      c.tos_version, (select value from public.app_secrets where key='customer_terms_version') as current_terms,
      (c.signed_terms_path is not null or c.signed_terms_url is not null) as signed
      from public.customers c where c.email = ${q(email)}`))[0];
  if (!row) throw new Error(`customer row not created for ${email}: save HTTP ${steps.save.status} ${steps.save.text}`);
  run.ids.customers.add(row.id);
  const session = await passwordSession(email, u.password);
  return { kind: 'customer', email, phone, fullName, locale, customerId: row.id, row, steps, session, jwt: session.access_token };
}

/**
 * A supplier with the mandatory six (founder's list): name, mobile, email, trade licence document,
 * profile, and the CURRENT Supplier Agreement accepted and signed - approved, capability confirmed.
 */
export async function makeDemoSupplier(run, { trade = 'aluminium', label = 'A', locale = 'en' } = {}) {
  const email = demoEmail(run, 'sup');
  const phone = demoMobile();
  const company = `ZZ DEMO ${label} ${trade} ${run.tag}`;
  const s = await makeSupplier(run, { trade, email, company_name: company, locale });
  run.ids.leads.add(String(s.leadId));
  // 1-3: name, mobile, email.   4: the trade licence, a real PDF in the real bucket.
  const licenceNo = `ZZDEMO-${run.tag}-${label}`.toUpperCase();
  const path = `licenses/${s.leadId}/${run.tag}_trade_licence.pdf`;
  await uploadObject('supplier-docs', path, demoTradeLicence({ company, licenceNo, activity: 'Aluminium and Glass Works' }), 'application/pdf');
  run.ids.storage.push(`supplier-docs/${path}`);
  await write(`update public.leads set
      phone = ${q(phone)}, contact_name = ${q('ZZ DEMO Contact ' + label)}, owner_dob = '1985-06-01',
      owner_email_verified = true, owner_phone_verified = true,
      license_doc_path = ${q(path)}, license_doc_name = 'trade_licence.pdf', trade_license_no = ${q(licenceNo)},
      license_authority = 'Dubai DET (fixture)', license_expiry = (current_date + 365), license_city = 'Dubai'
    where id = ${num(s.leadId)}`, 'demo supplier documents');
  // 5: the profile was written by makeSupplier (products, services, description, emirates).
  // 6: the Supplier Agreement, accepted and signed through the real endpoint.
  const terms = await call('kyc', s.jwt, { action: 'accept_terms', user_kind: 'supplier', email });
  // WhatsApp is confirmed at sign-up (#657): a supplier's WhatsApp notice goes only to a number they
  // confirmed, and trigger a03 records every other one as 'skipped'. A real supplier answers that
  // question in the portal; this one answers it through the same kyc action ('same' = the verified
  // mobile above, the reserved fixture block), so its notices are addressed and then captured by
  // zzzz_notifications_demo_capture, never handed to Twilio. Smoke run 34888342875 (14 Sep 2026)
  // read 'skipped' because the fixture never answered, not because a notice was wrongly withheld.
  const wa = await call('kyc', s.jwt, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' });
  if (wa.json?.ok !== true) throw new Error(`whatsapp_choose failed for ${email}: HTTP ${wa.status} ${wa.text}`);
  const row = (await read(`select l.id, l.company_name, l.phone, l.is_demo, l.approval_status, l.license_doc_path,
      l.trade_license_no, l.products, l.accepted_terms_version,
      coalesce((select value from public.app_secrets where key='supplier_terms_version'),
               (select value from public.app_secrets where key='terms_version')) as current_terms,
      (l.signed_terms_path is not null or l.signed_terms_url is not null) as signed
      from public.leads l where l.id = ${num(s.leadId)}`))[0];
  const session = await passwordSession(email, s.password);
  return { kind: 'supplier', email, phone, company, leadId: s.leadId, trade, row, terms, session, jwt: session.access_token };
}

/** Wait for a condition the product reaches asynchronously (the signed-terms PDF, a notification). */
export async function waitFor(fn, { timeoutMs = 30000, everyMs = 1500 } = {}) {
  const t0 = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - t0 > timeoutMs) return v;
    await new Promise((r) => setTimeout(r, everyMs));
  }
}

export const readJsonFile = (p) => JSON.parse(readFileSync(p, 'utf8'));
