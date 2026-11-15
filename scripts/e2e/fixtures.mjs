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
import { appendFileSync, readFileSync } from 'node:fs';
import { newRun, mkAuthUser, makeSupplier, teardown, verifyEmailByOtp, call as rawCall, keys, uploadObject, q, num, REF, BASE, demoMobile, EMIRATES } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';
import { demoPdf, demoTradeLicence } from '../lib/demo_pdf.mjs';

export { REF, BASE };

// A FIXTURE'S SESSION OUTLIVES ITS ACCESS TOKEN (19 Oct 2026, run qd_run:0a717394, S22). Each fixture
// signs in once; GoTrue's access token lives expires_in = 3600 s. The run opened 10:49 and S20-S22 ran
// after 11:50, so every call with a fixture JWT from then on got the gateway's HTTP 401
// UNAUTHORIZED_ASYMMETRIC_JWT "Invalid JWT" (verify_jwt = true rejects an expired token under that code;
// the function never ran). The portal never hits this: supabase-js refreshes its session. The harness
// now does the same: a token owned by a fixture and within REFRESH_MARGIN_S of expiry is re-issued
// through the fixture's newSession() before the call, and fixture.jwt / fixture.session move with it.
// Guard: scripts/e2e/fixtures_session.test.mjs.
// QD_E2E_REFRESH_MARGIN_S=3600 makes every fixture call use a re-issued token: how a short run proves the path.
export const REFRESH_MARGIN_S = Number(process.env.QD_E2E_REFRESH_MARGIN_S || 120);
const owners = new Map();   // access_token -> fixture
export function trackSession(fx) { if (fx?.jwt && fx.newSession) owners.set(fx.jwt, fx); return fx; }
export const tokenIsStale = (session, nowS = Date.now() / 1000) =>
  !session?.expires_at || Number(session.expires_at) - nowS < REFRESH_MARGIN_S;
export async function freshJwt(jwt, nowS) {
  const fx = owners.get(jwt);
  if (!fx || !tokenIsStale(fx.session, nowS)) return jwt;
  const s = await fx.newSession();
  owners.delete(jwt);
  fx.session = s; fx.jwt = s.access_token;
  owners.set(fx.jwt, fx);
  return fx.jwt;
}
export const call = async (slug, jwt, body, timeoutMs) => rawCall(slug, await freshJwt(jwt), body, timeoutMs);
export const read = (sql) => mgmtRead(REF, sql);
export const write = (sql, where = 'e2e fixture') => mgmtFixture(REF, sql, where);

export const demoEmail = (run, kind) => `qd-${run.tag}-${kind}${run.seq++}@example.invalid`;
// The fixture mobile block lives in demo_factory (00-89 only; 90-99 are reserved for checks that need
// a number NO run can hold - on 14 Sep a run handed out 42 while a check still used 42 as its unknown
// number, and production answered it as a known supplier). One definition, re-exported here.
export { demoMobile };

/**
 * Open a run: a tag for every row, and a CAPPED MODEL WINDOW for it (founder ruling, 18 Oct 2026: every test runs
 * with the AI on - real models inside a capped rehearsal window, never the fixture_no_spend stub). Before this the
 * window opened with models_allowed false, so every journey's model call was answered fixture_no_spend and the
 * journeys proved the stub. capUsd is the run's ceiling, enforced by fn_kernel_paid_provider_gate (rehearsal_cap)
 * on the run's tagged ai_cost_log spend; the window expires in the database even if this process dies.
 * QD_E2E_RUN_TAG makes call() carry the tag and its proof (_shared/e2e_run.ts). closeRun turns both off.
 */
export async function openRun(opts = {}) {
  if (process.env.QD_FIXTURES !== '1') process.env.QD_FIXTURES = '1';   // this module IS the fixture door
  const { capUsd = 15, minutes: _minutes, ...rest } = opts;   // ledger 1247: no spend limit on tests; 15 is the CHECK maximum, 120 min the window limit
  const run = newRun({ quiet: true, ...rest });
  run.ids = { inquiries: new Set(), quotes: new Set(), leads: new Set(), customers: new Set(), storage: [] };
  // THE JOB KNOWS EVERY WINDOW IT OPENED (18 Oct 2026). A script killed from outside never reaches closeRun's finally:
  // every_drawing_format_is_read was SIGTERMed at drawing_journeys_into_report's 12-minute ceiling every night 13-18 Oct
  // (qd_run:566956ec ... ad52831d stayed open past expires_at). With QD_E2E_RUN_TAGS set the tag is written BEFORE the
  // window opens, so the parent and the workflow's always() step tear it down and close it by its exact tag.
  if (process.env.QD_E2E_RUN_TAGS) appendFileSync(process.env.QD_E2E_RUN_TAGS, run.tag + '\n');
  // The window's run time is its expires_at: fn_rehearsal_window_sweep closes it after that if this process died.
  // QD_E2E_WINDOW_MIN = the workflow's job wall + teardown (smoke 33, nightly 120); an explicit opts.minutes wins;
  // unset or bad = the 2 h maximum.
  const min = Math.min(120, Math.max(1, Number(opts.minutes ?? process.env.QD_E2E_WINDOW_MIN) || 120));
  await write(`insert into public.rehearsal_window (run_tag, opened_by, note, models_allowed, cap_usd, expires_at)
               values (${q('qd_run:' + run.tag)}, 'scripts/e2e/run.mjs', 'e2e harness run', true, ${Number(capUsd)},
                       now() + make_interval(mins => ${min}))`, 'rehearsal window');
  process.env.QD_E2E_RUN_TAG = run.tag;
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
      union select distinct substring(email from '^qd-([a-z0-9]{4,16})-') from auth.users where email like 'qd-%@example.invalid'
      -- a run whose customer is gone but whose support profile survived (74 such on 27 Oct 2026, before teardown took them)
      union select distinct substring(email from '^qd-([a-z0-9]{4,16})-') from public.support_customer_profile where email like 'qd-%@example.invalid'
      -- 12 Nov 2026 (final audit F12): a run whose customer signed up through the real form at the Resend sink
      -- (delivered+qd-<tag>-...@resend.dev, which teardown already scopes) was never found here: 14 "ZZ DEMO Signup"
      -- customers of 2 Nov runs stayed, every one of their windows ended 2 Nov.
      union select distinct substring(email from '^delivered[+]qd-([a-z0-9]{4,16})-') from public.customers where email like 'delivered+qd-%@resend.dev'
      union select distinct substring(email from '^delivered[+]qd-([a-z0-9]{4,16})-') from auth.users where email like 'delivered+qd-%@resend.dev')
    select t.tag from t
     where t.tag is not null
       and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || t.tag)
       and not exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || t.tag
                        and (w.ended_at is null or w.ended_at > now() - make_interval(mins => ${Number(graceMinutes) | 0})))
       -- a run the sweep already found nothing removable in (sweepStaleRuns, SWEPT_EMPTY) is not tried again
       and not exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || t.tag and w.opened_by = ${q(SWEPT_EMPTY)})
     order by 1`);
  return rows.map((r) => r.tag).filter((t) => /^[a-z0-9]{4,16}$/.test(t) && !NEVER_SWEPT.has(t));
}

/** Remove the fixtures of runs that are over, each with the harness's own teardown by its exact tag. */
// opts.limit bounds how many runs one call removes (withRun sweeps a few per start; run.mjs takes them all).
//
// A RUN IT CAN REMOVE NOTHING FROM IS MARKED DONE, AND SAID ONCE (customer_support, 10 Nov 2026). Run fafbabb3 was found
// stale on every start and its teardown removed 0 rows each time ("comparison_candidate_v2 (table no longer exists) 0,
// customer_organization (table no longer exists) 0"), so every run's first teardown paid for it again. When a teardown
// removes nothing, one already-ended marker window is written for the tag (opened_by SWEPT_EMPTY, note = what is still
// there and why) and staleRunTags skips it from then on. The marker starts and ends at the run's own last ended_at,
// so fn_rehearsal_window_covers covers no moment it did not already cover and no real failure is hidden by it. The
// rows that remain are not hidden either: the sweep returns them as `left` (with any refused auth delete), run.mjs
// prints them, and the run that made them already failed "zero leftovers" when it closed.
export const SWEPT_EMPTY = 'fixtures.sweepStaleRuns:nothing_removable';
export async function sweepStaleRuns(opts = {}) {
  const out = [];
  for (const tag of (await staleRunTags(opts)).slice(0, opts.limit ?? Infinity)) {
    if (NEVER_SWEPT.has(tag)) continue;   // belt and braces: never the founder's demo accounts
    const t = await teardown(newRun({ tag, quiet: true }));
    if (t.removed === 0 && (t.objects ? Object.values(t.objects).every((n) => !n) : true)) {
      const left = (await staleRunTags({ graceMinutes: 0 })).includes(tag) ? 'still found by staleRunTags' : 'no longer found';
      const note = `swept ${new Date().toISOString()}: removed 0 (${t.summary}); ${left}${t.refused?.length ? '; auth delete refused: ' + t.refused.join(' | ') : ''}`.slice(0, 900);
      await write(`insert into public.rehearsal_window (run_tag, opened_by, note, models_allowed, cap_usd, started_at, ended_at, expires_at)
                   select w.run_tag, ${q(SWEPT_EMPTY)}, ${q(note)}, false, 0.01, max(w.ended_at), max(w.ended_at), max(w.ended_at)
                     from public.rehearsal_window w where w.run_tag = ${q('qd_run:' + tag)} and w.ended_at is not null group by w.run_tag`,
                  'mark a run the sweep can remove nothing from');
      out.push({ tag, summary: `${t.summary} — marked done (${left})`, left: left === 'still found by staleRunTags', refused: t.refused || [] });
    } else out.push({ tag, summary: t.summary, refused: t.refused || [] });
  }
  return out;
}

/** Tear everything down (unless kept), close the window, and prove nothing was left behind. */
export async function closeRun(run, { keep = false } = {}) {
  let removed = { summary: 'kept' }, filed = null;
  try {
    if (!keep) {
      // Counted BEFORE teardown: the run's tagged decision rows are what tie a gap to this run, and they go with it.
      filed = await gapsFiled(run).catch((e) => ({ error: String(e.message).slice(0, 200) }));
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
    await write(`update public.rehearsal_window set ended_at = now(), models_allowed = false where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'rehearsal window');
    if (process.env.QD_E2E_RUN_TAG === run.tag) delete process.env.QD_E2E_RUN_TAG;
  }
  if (keep) return { removed, leftovers: null };
  const left = await leftovers(run);
  // A rehearsal files no knowledge gap and no org_task (fn_sales_assist / fn_support_knowledge_gap). Any it did is a
  // leftover too, and is NOT removed here: a task in the queue is the founder's to see, so the run fails and names it.
  if (filed && !filed.error) {
    left.knowledge_gaps_filed = filed.gaps; left.org_tasks_filed = filed.tasks;
    left.total += filed.gaps + filed.tasks;
  } else if (filed?.error) left.knowledge_gaps_filed_error = filed.error;
  return { removed, leftovers: left };
}

/**
 * Knowledge gaps (and their org_tasks) first asked inside this run's window by a question this run asked, read from
 * the run's own tagged sales_decision_log rows. The test-traffic branch in fn_sales_assist makes it 0 (scripts/sql/
 * a_harness_chat_turn_carries_its_run_tag_and_files_no_gap_or_task.sql); anything else is a task nobody confirmed. If the
 * tag column is missing this throws (reported as knowledge_gaps_filed_error, never as 0).
 */
export async function gapsFiled(run) {
  const r = (await read(`with w as (select min(started_at) t0 from public.rehearsal_window where run_tag = ${q('qd_run:' + run.tag)}),
      g as (select distinct g.id, g.task_id from public.sales_knowledge_gap g, w
             where g.first_asked_at >= w.t0
               and g.question_norm in (select left(lower(regexp_replace(btrim(d.query), '\\s+', ' ', 'g')), 400)
                                         from public.sales_decision_log d where d.e2e_run_tag = ${q(run.tag)}))
    select (select count(*) from g)::int gaps, (select count(*) from g where task_id is not null)::int tasks`))[0];
  return { gaps: Number(r?.gaps ?? 0), tasks: Number(r?.tasks ?? 0) };
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
      (select count(*) from storage.objects where name like ${q('%' + t + '%')})::int storage_objects,
      (select count(*) from public.assistant_logs where audience in (select 'customer:' || x from unnest(array[${[...run.ids.customers].map(q).join(',')}]::text[]) x)
          or audience in (select 'supplier:' || x from unnest(array[${[...run.ids.leads].map(q).join(',')}]::text[]) x))::int assistant_logs,
      (select count(*) from public.support_customer_profile where email like ${like} or customer_id::text in (${ids(run.ids.customers)}))::int support_customer_profile,
      (select count(*) from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
        where p.email like ${like} or p.customer_id::text in (${ids(run.ids.customers)}))::int support_case`))[0];
  // The chat rows a turn writes, by the run tag the a00_*_e2e_run_tag triggers stamp (a_harness_chat_turn_carries_its_run_tag_
  // and_files_no_gap_or_task.sql). A table without the column says 'not applied' rather than a 0 it never measured.
  const tagged = new Set((await read(`select table_name t from information_schema.columns where table_schema = 'public' and column_name = 'e2e_run_tag'
      and table_name in ('assistant_logs','sales_decision_log','support_reply_readability')`)).map((x) => x.t));
  const byTag = ['assistant_logs', 'sales_decision_log', 'support_reply_readability'].filter((x) => tagged.has(x));
  const n = byTag.length ? (await read(`select ${byTag.map((x) => `(select count(*) from public.${x} where e2e_run_tag = ${q(t)})::int ${x}`).join(', ')}`))[0] : {};
  for (const x of ['assistant_logs', 'sales_decision_log', 'support_reply_readability']) {
    const k = x === 'assistant_logs' ? 'assistant_logs_run_tag' : x;
    r[k] = tagged.has(x) ? Number(n[x]) : 'not applied';
  }
  return { ...r, total: Object.values(r).reduce((a, b) => a + (typeof b === 'number' ? b : 0), 0) };
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
    return trackSession({ kind: 'customer', email, phone, fullName, locale, customerId: id, steps, session, jwt: session.access_token,
             newSession: () => passwordSession(email, u.password) });
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
  return trackSession({ kind: 'customer', email, phone, fullName, locale, customerId: row.id, row, steps, session, jwt: session.access_token,
           newSession: () => passwordSession(email, u.password) });
}

/**
 * A supplier with the mandatory six (founder's list): name, mobile, email, trade licence document,
 * profile, and the CURRENT Supplier Agreement accepted and signed - approved, capability confirmed.
 */
// coverage (13 Nov 2026, journey_proof): the emirates the supplier serves. Default every emirate, as before; a journey that
// proves the matcher asked the RIGHT suppliers makes some of the trade in another emirate only, which it must not ask.
export async function makeDemoSupplier(run, { trade = 'aluminium', label = 'A', locale = 'en', activity = 'Aluminium and Glass Works', coverage = EMIRATES } = {}) {
  const email = demoEmail(run, 'sup');
  const phone = demoMobile();
  const company = `ZZ DEMO ${label} ${trade} ${run.tag}`;
  // Inserted 'pending', not approved: since #698 the database refuses an approval while any of the six
  // is missing, and approves by itself (fn_sales_engineer_verifies_supplier) once the last one lands.
  const s = await makeSupplier(run, { trade, email, company_name: company, locale, approval: 'pending', coverage_emirates: coverage });
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
  let row = (await waitFor(async () => { const r = await readRow(); return complete(r) ? r : null; }, { timeoutMs: 60000 })) || await readRow();
  // ONE MORE CERTIFICATE ASK (13 Nov 2026, journey proof dry run 70b5d18b): 9 of 10 suppliers were certified; the 10th's
  // compliance_archive render answered cert_record_failed (its write of signed_terms_path failed; agent_runs kyc 07:45:58Z) and
  // the acceptance stood with no certificate. accept_terms for an acceptance already on file only asks for the certificate
  // again, as a supplier pressing the button again would. Recorded on the fixture (certificate_retried) so a journey reports it.
  let certificateRetried = false;
  if (!complete(row) && !row?.signed && row?.accepted_terms_version) {
    certificateRetried = true;
    await call('kyc', s.jwt, { action: 'accept_terms', user_kind: 'supplier', email });
    row = (await waitFor(async () => { const r = await readRow(); return complete(r) ? r : null; }, { timeoutMs: 60000 })) || await readRow();
  }
  if (!complete(row)) {
    throw new Error(`demo supplier ${label} (lead ${s.leadId}) is not approved with the mandatory six: ` +
      `approval_status=${row?.approval_status} missing=${JSON.stringify(row?.missing)} ` +
      `(accept_terms HTTP ${terms.status}, signed=${row?.signed})`);
  }
  const session = await passwordSession(email, s.password);
  const services = await stateServices(s.leadId, session.access_token, trade);
  return trackSession({ kind: 'supplier', email, phone, company, leadId: s.leadId, trade, row, terms, certificateRetried, session, jwt: session.access_token, services,
           newSession: () => passwordSession(email, s.password) });
}

// A DEMO JOURNEY POSTS ONLY IN A TRADE THAT IS OPEN THE WAY A REAL TRADE OPENS (11 Nov 2026, sales_engineer).
// MEASURED, nightly run 077cbbfc (10 Nov 22:07-23:46 UTC): drawing_reaches_suppliers and cad_identity_reaches_no_supplier
// each made ONE ZZ DEMO HVAC supplier, and create_inquiry answered HTTP 409 trade_not_open for HVAC. Since #1911
// (a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql) a ZZ DEMO customer's trade is open at the
// FLOOR (trade_opening_rule.floor_suppliers = 5, a CHECK), counting demo suppliers, while a real customer needs the
// CEO-tuned threshold (10) and never counts a demo supplier. Production held 0 matchable demo HVAC suppliers besides the
// run's own, so 1 < 5. run.mjs's three aluminium suppliers were short the same way (aluminium: 0 others on 11 Nov).
// THE HONEST FIX IS THE HARNESS, NOT THE RULE: lowering the demo floor to "what a journey happens to make" would let a
// demo journey prove a trade open at a count no real trade can open at. So the run itself holds the floor: the shortfall
// is made as BENCH suppliers through the same factory doors every demo supplier passes (demo_factory.makeSupplier: the
// mandatory six, the agreement signed by compliance_archive, approved by fn_sales_engineer_verifies_supplier, a confirmed
// capability), so fn_trade_verified_suppliers counts them by its own predicate. A bench supplier covers only BENCH_EMIRATE:
// the opening count is UAE-wide (as the real rule's is), while fn_match_capability gates on the request's emirate, so a
// journey's Dubai request is still routed to exactly the suppliers the journey asserts on.
// The floor is READ from the database, never written here, so the harness and the rule cannot drift apart again.
// prevented by: scripts/checks/a_demo_journey_holds_the_trade_opening_floor_itself.test.mjs
export const BENCH_EMIRATE = 'Fujairah';
/** How many bench suppliers a run must add so its own suppliers in a trade reach the floor. */
export const benchShortfall = (floor, own) => {
  const f = Number(floor), o = Number(own);
  if (!Number.isInteger(f) || f < 1) throw new Error(`trade opening floor ${JSON.stringify(floor)} is not a positive whole number`);
  if (!Number.isInteger(o) || o < 0) throw new Error(`own supplier count ${JSON.stringify(own)} is not a whole number`);
  return Math.max(0, f - o);
};
/**
 * Make the trade open for this run's ZZ DEMO customer: read the floor, add the shortfall as bench suppliers, then ask the
 * database's own question (fn_trade_is_open, the fixture branch) and refuse to go on if it still says no.
 * own: how many of this run's suppliers in that trade are already approved (makeDemoSupplier asserts it for each).
 */
export async function openTradeForDemo(run, trade, own) {
  const rule = (await read('select floor_suppliers from public.trade_opening_rule where id = 1'))[0];
  if (!rule) throw new Error('trade_opening_rule has no row 1: the trade-opening rule is not applied, so there is no floor to hold');
  const floor = Number(rule.floor_suppliers);
  const need = benchShortfall(floor, own);
  const bench = await Promise.all(Array.from({ length: need }, (_, k) => makeSupplier(run, {
    trade, coverage_emirates: [BENCH_EMIRATE], company_name: `ZZ DEMO bench ${k + 1} ${trade} ${run.tag}`,
  })));
  for (const b of bench) run.ids.leads.add(String(b.leadId));
  const st = (await read(`select public.fn_trade_is_open(${q(trade)}, true) as open, public.fn_trade_verified_suppliers(${q(trade)}, true) as counted`))[0] || {};
  if (st.open !== true) {
    throw new Error(`trade ${trade} is still not open for a demo customer after ${need} bench supplier(s): ` +
      `${st.counted} counted against a floor of ${floor} (own ${own}); a bench supplier is not passing fn_trade_verified_suppliers`);
  }
  return { trade, floor, own, bench: bench.map((b) => b.leadId), counted: Number(st.counted) };
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
  // 2 Nov 2026, nightly run 41417049225: "Aluminium windows and doors" is not a label, so the exact rewrite
  // never confirmed aluminium.windows_doors and the journey's window request routed to none of the three.
  // Every phrase is now an exact label. prevented by: scripts/checks/every_demo_service_sentence_names_exact_taxonomy_labels.test.mjs
  aluminium: 'Aluminium windows & doors, Curtain wall, ACP cladding, Pergolas & shades, Louvres',
  gypsum: 'Gypsum partitions, False ceilings, Decorative gypsum',
  painting: 'Interior painting, Exterior painting',
  // 19 Oct 2026, stage2 run 0a717394: these trades had no sentence, so their demo supplier confirmed no
  // service and fn_match_capability's services gate dropped it from every request that named one
  // (6 of 9 routed to nobody; hvac passed only because its brief named none). Exact taxonomy labels.
  // prevented by: scripts/checks/every_stage2_supplier_trade_states_its_services.test.mjs
  electrical: 'Wiring & electrical installation, Distribution boards & switchgear, Cable trays & containment, Lighting supply & installation, Electrical maintenance',
  plumbing: 'Water supply piping, Drainage & sewerage, Sanitary fixtures installation, Water heaters & pumps, Plumbing maintenance',
  // 12 Nov 2026 (review of PR #1980): "Testing & commissioning", "Wooden doors" and "Acoustic insulation" are each the label of TWO live
  // services, so the rewrite does not take them as names; each sentence holds labels that name one service only.
  hvac: 'Supply & installation of AC units, Ducting & ventilation, VRF & chiller systems, Maintenance & annual contracts',
  flooring: 'Tiling, Marble & granite, Parquet & vinyl, Epoxy flooring, Carpet',
  joinery: 'Kitchens, Wardrobes & closets, Carpentry & door repairs, Wood panelling, Custom furniture',
  glazing: 'Frameless glazing, Glass façades, Shower & glass partitions, Tempered & laminated glass, Mirrors',
  waterproofing: 'Roof waterproofing, Wet-area waterproofing, Basement & foundation waterproofing, Thermal insulation',
  landscaping: 'Softscape & planting, Hardscape, Irrigation systems, Artificial grass, Garden maintenance',
};
// A GATEWAY BLIP IS RETRIED, ONLY HERE (2 Nov 2026, customer_support). Nightly run 41410340385 never
// reached journey a: the third demo supplier's services_save_rewrite got the edge relay's own HTML
// "502 Bad Gateway" after 2 s (no JSON from our handler, a burst of worker shutdowns in function_logs),
// and the whole funnel was skipped for one blip. Both actions here SET the supplier's service list, so a
// second call is the same write; `call` itself is not changed because a quote submit is not idempotent.
// prevented by: scripts/e2e/fixtures_gateway_blip.test.mjs
export const isGatewayBlip = (r) => [502, 503, 504].includes(r?.status) && !r?.json && /<html|bad gateway|gateway time-?out|service unavailable/i.test(String(r?.text || ''));
// A ROW LOCKED BY SOMEONE ELSE'S ROLLED-BACK PROBE IS RETRIED TOO (10 Nov 2026, customer_support). Run 2026-11-10T14-20-25
// never reached journey f: demo supplier 156068's services_save_rewrite returned 500 services_rewrite_write_failed,
// "canceling statement due to statement timeout" at 14:21:25Z (postgres_logs). The upsert's foreign-key check on its
// own new lead waited on another session's demo-purge probe, which deleted every demo lead (28) inside one transaction
// for 33,962 ms and then rolled back. PostgREST's roles stop at 8 s (statement_timeout and lock_timeout = 8s), so the
// write was refused, not slow. The write is the same SET as the blip case, so a second call is safe; anything else
// still fails the fixture.
export const isLockWait = (r) => r?.status === 500 && /canceling statement due to (statement|lock) timeout|lock timeout|deadlock detected/i.test(String(r?.text || ''));
async function callRetryingBlip(fn, jwt, body) {
  let r = await call(fn, jwt, body);
  for (let i = 1; i <= 2 && (isGatewayBlip(r) || isLockWait(r)); i++) { await new Promise((s) => setTimeout(s, 3000 * i)); r = await call(fn, jwt, body); }
  return r;
}
async function stateServices(leadId, jwt, trade) {
  const text = SERVICE_WORDS[trade];
  if (!text) return { stated: [], note: `no service sentence for trade ${trade}` };
  const rw = await callRetryingBlip('supplier_api', jwt, { action: 'services_rewrite', text, removed: [] });
  // 12 Nov 2026 (rulings 1663/1664, review of PR #1980): the rewrite lists nothing for him; a text made only of our own unique service
  // names comes back as those services OFFERED ('exact_label', no model asked), and the demo supplier adds them, as a supplier taps Add
  const stated = (rw.json?.meaning?.proposals || []).filter((p) => p.because === 'exact_label').map((p) => p.key);
  if (!stated.length) throw new Error(`demo supplier ${leadId}: the sales engineer's rewrite named no service in "${text}" (HTTP ${rw.status} ${rw.text?.slice(0, 200)})`);
  const implied = (rw.json?.implied || []).filter((i) => !i.removed).map((i) => i.key);
  const st = await call('supplier_api', jwt, { action: 'services_state' });
  const sv = await callRetryingBlip('supplier_api', jwt, {
    action: 'services_save_rewrite',
    trades: [...new Set([trade, ...(st.json?.checklist || []).map((c) => c.code)])],
    roles: st.json?.capability?.roles?.length ? st.json.capability.roles : ['contractor', 'installer', 'supplier'],
    services: stated, implied, removed: [], own_words: rw.json?.own_words || [], raw_text: text,
  });
  if (sv.json?.ok !== true) throw new Error(`demo supplier ${leadId}: services_save_rewrite failed HTTP ${sv.status} ${sv.text?.slice(0, 400)}`);
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
