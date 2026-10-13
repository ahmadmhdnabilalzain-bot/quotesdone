// scripts/e2e/fixtures.mjs — demo identities WITHOUT anyone's credentials (14 Sep 2026).
// Assigned: ceo (it_engineer's tooling, carried out for the ceo).
//
// The founder: "do what is needed cause you need to keep browsing stuff without my credentials".
// This module mints complete ZZ DEMO customers and suppliers on the one production project, signs them
// in without delivering an OTP, and destroys everything a run created. It builds on
// scripts/lib/demo_factory.mjs (auth admin, teardown by tag, the OTP hop) rather than beside it.
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
import { newRun, mkAuthUser, makeSupplier, teardown, verifyEmailByOtp, call, keys, uploadObject, q, num, REF, BASE, demoMobile, EMIRATES } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';
import { demoPdf, demoTradeLicence } from '../lib/demo_pdf.mjs';

export { REF, BASE, call };
export const read = (sql) => mgmtRead(REF, sql);
export const write = (sql, where = 'e2e fixture') => mgmtFixture(REF, sql, where);

export const demoEmail = (run, kind) => `qd-${run.tag}-${kind}${run.seq++}@example.invalid`;
// The fixture mobile block lives in demo_factory (00-89 only; 90-99 are reserved for checks that need
// a number NO run can hold - on 14 Sep a run handed out 42 while a check still used 42 as its unknown
// number, and production answered it as a known supplier). One definition, re-exported here.
export { demoMobile };

/** Open a run: a tag for every row, and a rehearsal window so the failed-run watcher never pages the founder. */
export async function openRun(opts = {}) {
  if (process.env.QD_FIXTURES !== '1') process.env.QD_FIXTURES = '1';   // this module IS the fixture door
  const run = newRun({ quiet: true, ...opts });
  run.ids = { inquiries: new Set(), quotes: new Set(), leads: new Set(), customers: new Set(), storage: [] };
  // The window's run time is its expires_at: fn_rehearsal_window_sweep closes it after that if this process died.
  // QD_E2E_WINDOW_MIN = the workflow's job wall + teardown (smoke 33, nightly 120); unset or bad = the 2 h maximum.
  const min = Math.min(120, Math.max(1, Number(process.env.QD_E2E_WINDOW_MIN) || 120));
  await write(`insert into public.rehearsal_window (run_tag, opened_by, note, expires_at)
               values (${q('qd_run:' + run.tag)}, 'scripts/e2e/run.mjs', 'e2e harness run', now() + interval '${min} minutes')`, 'rehearsal window');
  return run;
}

// THE PERSISTENT FOUNDER DEMO ACCOUNTS ARE NEVER A LEFTOVER. scripts/e2e/founder_demo_tour.mjs keeps
// the run tag 'founderdemo' (qd-founderdemo-*) on purpose, and the founder said leave demo records
// alone (instruction 571). Its tag is spelled here, not imported: that module imports this one.
const NEVER_SWEPT = new Set(['founderdemo']);

/**
 * Tags of harness runs that are OVER — every rehearsal window for the tag has ended, the last more
 * than `graceMinutes` ago — but whose fixtures are still in production. Measured 22 Sep 2026: runs
 * 7e3a1c99 and 12ddadff (windows ended 20:45Z and 23:45Z on 21 Sep) left three ZZ DEMO aluminium
 * suppliers each, and at 00:32Z the nightly's request was routed to three of THEM — the matcher's
 * per-trade cap is 3 — so none of the run's own suppliers was invited and "routing invited the demo
 * suppliers" failed on a product that had routed correctly. A tag with no window at all is not ours
 * to judge and is left alone; an open window is a run in progress and is never touched.
 */
export async function staleRunTags({ graceMinutes = 60 } = {}) {
  const rows = await read(`with t as (
      select distinct substring(x from '^qd_run:([a-z0-9]{4,16})$') tag from public.leads, unnest(coalesce(tags,'{}')) x where x like 'qd_run:%'
      union select distinct substring(email from '^qd-([a-z0-9]{4,16})-') from public.customers where email like 'qd-%@example.invalid'
      union select distinct substring(email from '^qd-([a-z0-9]{4,16})-') from auth.users where email like 'qd-%@example.invalid')
    select t.tag from t
     where t.tag is not null
       and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || t.tag)
       and not exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || t.tag
                        and (w.ended_at is null or w.ended_at > now() - make_interval(mins => ${Number(graceMinutes) | 0})))
     order by 1`);
  return rows.map((r) => r.tag).filter((t) => /^[a-z0-9]{4,16}$/.test(t) && !NEVER_SWEPT.has(t));
}

/** Remove the fixtures of runs that are over, each with the harness's own teardown by its exact tag. */
export async function sweepStaleRuns(opts = {}) {
  const out = [];
  for (const tag of await staleRunTags(opts)) {
    if (NEVER_SWEPT.has(tag)) continue;   // belt and braces: never the founder's demo accounts
    const t = await teardown(newRun({ tag, quiet: true }));
    out.push({ tag, summary: t.summary });
  }
  return out;
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
      (select count(*) from public.quote_reviews where inquiry_id::text in (${ids(run.ids.inquiries)}) or supplier_id::text in (${ids(run.ids.leads)}))::int quote_reviews,
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
export async function makeDemoCustomer(run, opts = {}) {
  const { locale = 'en', label = 'Customer' } = opts;
  const email = demoEmail(run, 'cust');
  const phone = demoMobile();
  const fullName = `ZZ DEMO ${label} ${run.tag}`;
  const u = await mkAuthUser(run, email);
  const steps = {};
  steps.save = await call('kyc', u.jwt, { action: 'save_customer', user_kind: 'customer', email, full_name: fullName, phone, dob: '1990-01-15' });
  steps.email_otp = await verifyEmailByOtp(email, 'customer');
  await write(`update public.customers set phone_verified = true, locale = ${q(locale)} where email = ${q(email)}`, 'demo mobile verified');
  if (opts.stopBeforeWhatsApp) {
    // Stopped at the sign-up step the WhatsApp question belongs to: profile saved, email and mobile
    // verified, NOT answered, terms NOT accepted. Tracked for teardown like every other fixture.
    const id = (await read(`select id from public.customers where email = ${q(email)}`))[0]?.id;
    if (!id) throw new Error(`customer row not created for ${email}: save HTTP ${steps.save.status} ${steps.save.text}`);
    run.ids.customers.add(id);
    const session = await passwordSession(email, u.password);
    return { kind: 'customer', email, phone, fullName, locale, customerId: id, steps, session, jwt: session.access_token,
             newSession: () => passwordSession(email, u.password) };
  }
  // Sign-up asks "Is <mobile> also your WhatsApp number?" and kyc accept_terms refuses without the
  // answer (15 Sep 2026). 'same' = the verified fixture mobile above; notices to it are captured.
  steps.whatsapp = await call('kyc', u.jwt, { action: 'whatsapp_choose', user_kind: 'customer', email, opt: 'same' });
  steps.terms = await call('kyc', u.jwt, { action: 'accept_terms', user_kind: 'customer', email });
  const row = (await read(`select c.id, c.full_name, c.date_of_birth, c.email_verified, c.phone_verified, c.is_demo,
      c.tos_version, (select value from public.app_secrets where key='customer_terms_version') as current_terms,
      (c.signed_terms_path is not null or c.signed_terms_url is not null) as signed
      from public.customers c where c.email = ${q(email)}`))[0];
  if (!row) throw new Error(`customer row not created for ${email}: save HTTP ${steps.save.status} ${steps.save.text}`);
  run.ids.customers.add(row.id);
  const session = await passwordSession(email, u.password);
  return { kind: 'customer', email, phone, fullName, locale, customerId: row.id, row, steps, session, jwt: session.access_token,
           newSession: () => passwordSession(email, u.password) };
}

/**
 * A supplier with the mandatory six (founder's list): name, mobile, email, trade licence document,
 * profile, and the CURRENT Supplier Agreement accepted and signed - approved, capability confirmed.
 */
export async function makeDemoSupplier(run, { trade = 'aluminium', label = 'A', locale = 'en', activity = 'Aluminium and Glass Works' } = {}) {
  const email = demoEmail(run, 'sup');
  const phone = demoMobile();
  const company = `ZZ DEMO ${label} ${trade} ${run.tag}`;
  // Inserted 'pending', not approved: since #698 the database refuses an approval while any of the six
  // is missing, and approves by itself (fn_sales_engineer_verifies_supplier) once the last one lands.
  const s = await makeSupplier(run, { trade, email, company_name: company, locale, approval: 'pending', coverage_emirates: EMIRATES });
  run.ids.leads.add(String(s.leadId));
  // 1-3: name, mobile, email.   4: the trade licence and 5: the company profile, real PDFs in the real
  // bucket - fn_supplier_mandatory_six counts a document only if its path exists in supplier-docs.
  const licenceNo = `ZZDEMO-${run.tag}-${label}`.toUpperCase();
  const path = `licenses/${s.leadId}/${run.tag}_trade_licence.pdf`;
  await uploadObject('supplier-docs', path, demoTradeLicence({ company, licenceNo, activity }), 'application/pdf');
  run.ids.storage.push(`supplier-docs/${path}`);
  const profilePath = `profiles/${s.leadId}/${run.tag}_company_profile.pdf`;
  await uploadObject('supplier-docs', profilePath, demoPdf([
    ['COMPANY PROFILE (ZZ DEMO FIXTURE - NOT A REAL COMPANY)', 14], [company, 12],
    ['Aluminium and glass supply and installation, Dubai.', 11], [`Run ${run.tag}`, 9],
  ]), 'application/pdf');
  run.ids.storage.push(`supplier-docs/${profilePath}`);
  await write(`update public.leads set
      phone = ${q(phone)}, contact_name = ${q('ZZ DEMO Contact ' + label)}, owner_dob = '1985-06-01',
      owner_email_verified = true, owner_phone_verified = true,
      license_doc_path = ${q(path)}, license_doc_name = 'trade_licence.pdf', trade_license_no = ${q(licenceNo)},
      license_authority = 'Dubai DET (fixture)', license_expiry = (current_date + 365), license_city = 'Dubai',
      -- what supplier_api's code reader takes off an uploaded licence; this upload bypasses it, and
      -- since 24 Sep an unread licence name holds the supplier at 'pending' (licence_name_unread)
      licence_legal_name = ${q(company)},
      company_profile_doc_path = ${q(profilePath)}
    where id = ${num(s.leadId)}`, 'demo supplier documents');
  // 6: the Supplier Agreement, accepted and signed through the real endpoint. The signed PDF lands
  // asynchronously (z21 -> compliance_archive), and its arrival re-runs the verification (z20).
  const terms = await call('kyc', s.jwt, { action: 'accept_terms', user_kind: 'supplier', email });
  // WhatsApp is confirmed at sign-up (#657): a supplier's WhatsApp notice goes only to a number they
  // confirmed, and trigger a03 records every other one as 'skipped'. A real supplier answers that
  // question in the portal; this one answers it through the same kyc action ('same' = the verified
  // mobile above, the reserved fixture block), so its notices are addressed and then captured by
  // zzzz_notifications_demo_capture, never handed to Twilio. Smoke run 34888342875 (14 Sep 2026)
  // read 'skipped' because the fixture never answered, not because a notice was wrongly withheld.
  const wa = await call('kyc', s.jwt, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' });
  if (wa.json?.ok !== true) throw new Error(`whatsapp_choose failed for ${email}: HTTP ${wa.status} ${wa.text}`);
  const readRow = async () => (await read(`select l.id, l.company_name, l.phone, l.is_demo, l.approval_status, l.license_doc_path,
      l.company_profile_doc_path, l.trade_license_no, l.products, l.accepted_terms_version,
      coalesce((select value from public.app_secrets where key='supplier_terms_version'),
               (select value from public.app_secrets where key='terms_version')) as current_terms,
      (l.signed_terms_path is not null or l.signed_terms_url is not null) as signed,
      to_jsonb(public.fn_supplier_mandatory_six(l)) as missing
      from public.leads l where l.id = ${num(s.leadId)}`))[0];
  const complete = (r) => r && Array.isArray(r.missing) && r.missing.length === 0 && r.approval_status === 'approved';
  const row = (await waitFor(async () => { const r = await readRow(); return complete(r) ? r : null; }, { timeoutMs: 60000 })) || await readRow();
  if (!complete(row)) {
    throw new Error(`demo supplier ${label} (lead ${s.leadId}) is not approved with the mandatory six: ` +
      `approval_status=${row?.approval_status} missing=${JSON.stringify(row?.missing)} ` +
      `(accept_terms HTTP ${terms.status}, signed=${row?.signed})`);
  }
  const session = await passwordSession(email, s.password);
  const services = await stateServices(s.leadId, session.access_token, trade);
  return { kind: 'supplier', email, phone, company, leadId: s.leadId, trade, row, terms, session, jwt: session.access_token, services,
           newSession: () => passwordSession(email, s.password) };
}

// THE SERVICES A REAL SUPPLIER STATES (22 Sep 2026, sales_engineer). MEASURED: the portal walk of 21 Sep
// posted an aluminium request and the product's routing invited 0 of the 3 ZZ DEMO aluminium suppliers;
// the harness had to write the matches itself, so the step proved nothing about routing. A probe on
// production found why: fn_match_capability gates on SERVICES when the request names one (a window
// request resolves to aluminium.windows_doors), and a demo supplier carried a trade with services = '{}'.
// That gate is the founder's rule, not a defect (instruction 438/439: the CONFIRMED service list drives
// matching; exact or none) — a real supplier states its services on the Services tab and the sales
// engineer rewrites them. So the fixture now does exactly that, through the product: its own sentence,
// services_rewrite, then services_save_rewrite with what the rewrite named. A trade with no sentence
// here gets no services and says so; the caller that needs routing must add one.
const SERVICE_WORDS = {
  aluminium: 'Aluminium windows and doors, curtain wall, ACP cladding, pergolas and louvres',
  gypsum: 'Gypsum partitions, false ceilings, decorative gypsum and bulkheads',
  painting: 'Interior painting and exterior painting',
};
async function stateServices(leadId, jwt, trade) {
  const text = SERVICE_WORDS[trade];
  if (!text) return { stated: [], note: `no service sentence for trade ${trade}` };
  const rw = await call('supplier_api', jwt, { action: 'services_rewrite', text, removed: [] });
  const stated = rw.json?.service_keys || [];
  if (!stated.length) throw new Error(`demo supplier ${leadId}: the sales engineer's rewrite named no service in "${text}" (HTTP ${rw.status} ${rw.text?.slice(0, 200)})`);
  const implied = (rw.json?.implied || []).filter((i) => !i.removed).map((i) => i.key);
  const st = await call('supplier_api', jwt, { action: 'services_state' });
  const sv = await call('supplier_api', jwt, {
    action: 'services_save_rewrite',
    trades: [...new Set([trade, ...(st.json?.checklist || []).map((c) => c.code)])],
    roles: st.json?.capability?.roles?.length ? st.json.capability.roles : ['contractor', 'installer', 'supplier'],
    services: stated, implied, removed: [], own_words: rw.json?.own_words || [], raw_text: text,
  });
  if (sv.json?.ok !== true) throw new Error(`demo supplier ${leadId}: services_save_rewrite failed HTTP ${sv.status} ${sv.text?.slice(0, 200)}`);
  return { stated, implied };
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
