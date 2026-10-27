// demo_factory.mjs — the demo-data factory for staging.
//
// THE RULE (session 9): anything that needs data to be tested gets demo data built for it,
// asserted against, and deleted afterwards. Production has 0 customers, 0 inquiries and 0 quotes,
// so demo data is the only way to prove anything.
//
// This module exists because journey_test.mjs was the only end-to-end demo-data creator in the
// repo and every helper inside it was a private top-level const. standUpSupplier() returned
// {ok, detail} and threw away the supplier's id, email and JWT, so a caller could make a supplier
// but never ACT AS it. The 18-column supplier_capabilities INSERT was written out twice, verbatim.
//
// Three things this fixes, all of them measured failures:
//
//   1. TEARDOWN BY TAG, NOT BY GUESSWORK. journey_test deleted auth users, 'Journey Test %' leads
//      and a HAND-LISTED set of storage paths. Everything else survived: 65 customers rows (every
//      single one an orphan whose auth user was already gone), 41 inquiries, 24 dangling documents,
//      118 signed-terms PDFs. Here every row a run creates carries the run tag, and teardown
//      derives the storage paths FROM THE DATABASE rather than from a list someone maintained.
//
//   2. try/finally. journey_test is a bare linear file, so a mid-run throw leaks everything. The
//      15 orphaned auth users in staging are the proof it already happened. withRun() below
//      tears down on the way out of a throw.
//
//   3. VARIETY. Twelve identically-scored suppliers make every later supplier structurally
//      invisible to matching. TRADES below carries all 25 taxonomy_trade codes and the corpus
//      builder spreads products_norm across them on a deterministic ladder, because products_norm
//      overlap - not leads.rating - is the score dial that actually works (see §2.4 of the brief:
//      supplier_perf prefers app_rating, and quote_rate overrides perf_score the moment
//      matched > 0, so a rating-spread corpus collapses on its second run).
//
// Usage as a module:
//     import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote } from './demo_factory.mjs';
//     await withRun(async (run) => {
//       const cust = await makeCustomer(run);          // { id, email, jwt, customerId }
//       const sup  = await makeSupplier(run, { trade: 'aluminium' });
//       ...assert...
//     });                                              // teardown runs even if the body throws
//
// Usage as a CLI:
//     node scripts/lib/demo_factory.mjs --selftest    create, assert, tear down, prove the
//                                                     database returned to its exact baseline
//     node scripts/lib/demo_factory.mjs --purge       delete the accumulated litter
//     node scripts/lib/demo_factory.mjs --purge --dry-run
//     node scripts/lib/demo_factory.mjs --corpus 100  build a matching corpus (add --keep)
import { supabaseAccessToken } from './supabase_token.mjs';
import { assertNotProduction, mgmtRead, mgmtFixture, PROD_REF } from './qd_guard.mjs';
import { demoPdf, demoTradeLicence } from './demo_pdf.mjs';
import { readFileSync } from 'node:fs';
import { randomBytes, createHmac } from 'node:crypto';
import { pickApiKey } from './supabase_keys.mjs';   // new keys first; legacy only as a temporary fallback (27 Oct 2026)

// THE TARGET, REHOMED 15 AUG 2026 — AND WHY THIS ONE LINE MATTERED MORE THAN IT LOOKS.
//
// It used to read `assertNotProduction(process.env.QD_STAGING_REF || 'pglpqrhvozwepymcuunn')`.
// pglpqrhvozwepymcuunn was deleted that morning, so this default made every importer target a
// project that does not exist — and 75 files import REF from here, 28 of them only to use it as a
// default --ref for a read. A grep for the dead ref found 39 files; 87 actually reached it, because
// this line is the indirection the other 48 came through. Fixing the export fixes all of them at
// once; retargeting them one by one would have missed the ones that never spell the ref out.
//
// Resolution order, deliberately: an explicit QD_STAGING_REF wins, so the day a new staging project
// exists this file needs no edit. With none set it resolves the one project that does exist. The
// WRITE path is what keeps that honest — see mgmtFixture in qd_guard.mjs. assertNotProduction is
// still applied to an explicitly-supplied ref, so a typo that lands on production is still refused;
// it is only the implicit default that is allowed to be the live project.
export const REF = process.env.QD_STAGING_REF
  ? assertNotProduction(process.env.QD_STAGING_REF, 'demo factory')
  : PROD_REF;
export const BASE = `https://${REF}.supabase.co`;

// ---- SQL literals ----------------------------------------------------------------------------
// Every value that reaches the database goes through one of these. A demo fixture that carries an
// apostrophe (an Arabic transliteration, a company name like "Al Reem Ali's") must not be able to
// end a string literal.
export const q = (v) => (v === null || v === undefined) ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
export const num = (v) => (v === null || v === undefined || v === '') ? 'null' : String(Number(v));
export const arr = (a) => (Array.isArray(a) && a.length) ? `ARRAY[${a.map(q).join(',')}]::text[]` : `'{}'::text[]`;
export const jb = (o) => (o === null || o === undefined) ? 'null' : `${q(JSON.stringify(o))}::jsonb`;
export const bool = (v) => (v === null || v === undefined) ? 'null' : (v ? 'true' : 'false');

// ---- staging api keys ------------------------------------------------------------------------
let _keys = null;
export async function keys() {
  if (_keys) return _keys;
  const mgmt = supabaseAccessToken();
  // 14 SEP 2026, smoke run 34885431255: in CI this answered with something that was not an array and
  // the harness died on "k.find is not a function", which names neither the status nor the reason.
  // The same token ran /database/query in the same job, so it is the api-keys call itself (a scope, or
  // a throttle). A 429 waits like scripts/lib/db.mjs; anything else fails saying what came back.
  let r, k;
  for (let attempt = 0; ; attempt++) {
    r = await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`,
      { headers: { Authorization: 'Bearer ' + mgmt } });
    if ((r.status === 429 || r.status >= 500) && attempt < 5) {
      await new Promise((res) => setTimeout(res, Math.min(2000 * 2 ** attempt, 30000)));
      continue;
    }
    break;
  }
  const text = await r.text();
  try { k = JSON.parse(text); } catch { k = null; }
  if (!Array.isArray(k)) {
    throw new Error(`the management api refused the project's api keys: HTTP ${r.status} ${text.slice(0, 300)}`);
  }
  const ANON = pickApiKey(k, 'publishable');
  const SERVICE = pickApiKey(k, 'secret');
  if (!ANON || !SERVICE) throw new Error('could not read staging api keys');
  _keys = { ANON, SERVICE };
  return _keys;
}

export async function call(slug, jwt, body, timeoutMs = 90000) {
  const { ANON } = await keys();
  try {
    const r = await fetch(`${BASE}/functions/v1/${slug}?forceFunctionRegion=ap-southeast-1`, {
      method: 'POST',
      // QD_E2E_RUN_TAG: the stage-2 harness's run tag, carried to every model call so its ai_cost_log
      // rows are stamped (scripts/sql/a_sandbox_run_is_tagged_capped_and_let_through_only_inside_its_window.sql).
      headers: { apikey: ANON, Authorization: 'Bearer ' + (jwt || ANON), 'Content-Type': 'application/json',
        // and the proof that the tag comes from inside (_shared/e2e_run.ts): without it the tag is ignored
        ...(process.env.QD_E2E_RUN_TAG ? { 'x-qd-e2e-run': process.env.QD_E2E_RUN_TAG, 'x-qd-e2e-secret': await internalCred() } : {}) },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* a non-JSON body is itself the finding */ }
    return { status: r.status, json, text: text.slice(0, 200).replace(/\s+/g, ' '), body: text };
  } catch (e) {
    return { status: 0, json: null, text: String(e.message).slice(0, 200) };
  }
}

// ---- the trade vocabulary --------------------------------------------------------------------
// These 25 codes are public.taxonomy_trade.code, which is what fn_match_capability's `cand` CTE
// gates on (sc.trades && p_trades) and what its req_auth CTE reads authority_required from. They
// are NOT catalog_supplier_categories.slug (86 rows, a different vocabulary) - conflating the two
// is why a capability fixture can pass every visible check and still match nothing.
//
// Three trades carry a mandatory authority: a capability row without that key in
// authority_approvals is dropped by the `not exists (... where not (sc.authority_approvals ? a))`
// gate, silently and before scoring.
export const AUTHORITY = {
  electrical: 'electrical_utility',
  fire_fighting: 'civil_defence',
  security_systems: 'sira',
};

import { TRADE_DEFS as TRADES } from './trade_defs.mjs';
export { TRADES };
export const TRADE_CODES = Object.keys(TRADES);

export const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain'];
export const PROJECT_TYPES = [['villa', 'residential'], ['commercial', 'office'], ['hotel', 'hospitality'],
  ['industrial', 'warehouse'], ['retail', 'mall']];

// roles are CODES from public.taxonomy_role, not needs. fn_match_capability requires a
// taxonomy_role row whose code appears in sc.roles AND whose column for p_need is true:
// executes -> contractor | installer | maintenance | turnkey_fitout
// supplies -> contractor | distributor | manufacturer | supplier | turnkey_fitout
// whole_scope -> turnkey_fitout only
export const ROLE_SETS = {
  both: ['contractor', 'installer', 'supplier'],
  executes_only: ['installer', 'maintenance'],
  supplies_only: ['supplier', 'distributor', 'manufacturer'],
  turnkey: ['turnkey_fitout'],
};

// ---- run -------------------------------------------------------------------------------------
// Every row a run creates carries the tag. customers and leads carry it in columns that survive
// independently of each other, because the reason 62 customers rows outlived their suppliers is
// that customers.full_name was 'Journey Test Customer' for journey rows and NULL for smoke rows,
// so no single predicate could find them all.
//
//   auth.users / customers / inquiry_intake / email_verifications -> email `qd-<tag>-...@example.invalid` (@example.com before 30 Sep 2026; teardown matches both)
//   leads                                                          -> tags @> {qd_demo, qd_run:<tag>}
//   inquiries                                                      -> provenance->>'qd_run'
//   quotes / supplier_capabilities / documents / storage objects    -> reached through their parents
export function newRun(opts = {}) {
  const tag = (opts.tag || randomBytes(4).toString('hex')).toLowerCase();
  if (!/^[a-z0-9]{4,16}$/.test(tag)) throw new Error(`bad run tag ${JSON.stringify(tag)}`);
  return {
    tag,
    ref: REF,
    base: BASE,
    keep: !!opts.keep,
    quiet: !!opts.quiet,
    seq: 0,
    authUsers: [],          // ids we created through the auth admin API
    log: (...a) => { if (!opts.quiet) console.log(...a); },
  };
}

export const runEmail = (run, kind) => `qd-${run.tag}-${kind}${run.seq++}@example.invalid`;
// The reserved fixture mobile block, +971 50 000 00xx. 00-89 only: 90-99 are held for checks that need
// a number NO run can hold at the same time (a_phone_cannot_select_an_account uses 98 and 97). A UAE
// mobile (+9715) is one of the mandatory six, and fn_is_demo_phone marks the row demo on its own.
let mobileSeq = Math.floor(Math.random() * 90);
export const demoMobile = () => '+9715000000' + String((mobileSeq++) % 90).padStart(2, '0');
// The agreement version a fixture's acceptance records: the key compliance_archive and kyc read.
const TERMS_VERSION_SQL = `coalesce((select value from public.app_secrets where key='supplier_terms_version'),
  (select value from public.app_secrets where key='terms_version'))`;
export const RUN_TAG_COL = (tag) => `'qd_run:${tag}'`;

/**
 * Run `fn` against a fresh tagged run and ALWAYS tear it down, including on a throw.
 * This is the whole reason the module exists: the 15 orphaned auth users in staging came from a
 * mid-run throw in a script that had no finally.
 */
/**
 * Close a run's rehearsal window: the one routine every closer uses (withRun's finally, and
 * run.mjs --purge-tag for a run whose process died before its finally ran).
 * 6 Oct 2026: a check killed by a shell timeout left qd_run:1eb782ae open for hours. While a window is open,
 * the failed-run watcher stays quiet and the stage-2 harness refuses to start.
 */
export async function closeRehearsalWindow(tag) {
  if (!/^[a-z0-9]{4,16}$/.test(String(tag))) throw new Error(`bad run tag ${JSON.stringify(tag)}`);
  if (process.env.QD_E2E_RUN_TAG === tag) delete process.env.QD_E2E_RUN_TAG;
  return mgmtFixture(REF, `update public.rehearsal_window set ended_at = now(), models_allowed = false where run_tag = 'qd_run:${tag}' and ended_at is null`, 'rehearsal window');
}

/**
 * Close a window when the process is ended before its `finally` can run: SIGTERM (a cancelled CI job),
 * SIGINT, or an uncaught exception / unhandled rejection. 13 Oct 2026: nine smoke and withRun windows
 * stayed open for hours and blocked stage2. Same pattern as a_phone_cannot_select_an_account.test.mjs
 * (#1362, #1377). Returns a disarm function; call it once the normal `finally` has closed the window.
 * A kill -9 is caught by nothing here: fn_rehearsal_window_sweep is the net for that.
 */
export function closeOnExit(close) {
  const h = (code, err) => () => {
    if (err !== undefined) console.error(err);
    Promise.resolve().then(close).catch(() => {}).finally(() => process.exit(code));
  };
  const handlers = {
    SIGTERM: h(143), SIGINT: h(130),
    uncaughtException: (e) => h(1, e)(), unhandledRejection: (e) => h(1, e)(),
  };
  for (const [ev, fn] of Object.entries(handlers)) process.once(ev, fn);
  return () => { for (const [ev, fn] of Object.entries(handlers)) process.removeListener(ev, fn); };
}

export async function withRun(fn, opts = {}) {
  // AI ON, CAPPED (founder ruling 18 Oct 2026): the window lets this run's tagged model calls through up to capUsd.
  const { capUsd = 15, minutes = 120, ...rest } = opts;   // ledger 1247: no spend limit on tests; 15 is the CHECK maximum, 120 min the window limit
  const run = newRun(rest);
  run.log(`demo run ${run.tag} on ${REF}`);
  // DECLARE THE WINDOW (3 Sep 2026). Every function this run exercises logs into agent_runs like a
  // real call, and fn_watch_failed_runs paged the founder twice about one morning's rehearsals.
  // A declared window tells the watcher these rows are the operator's; rows outside it are judged
  // exactly as before. The row is never deleted by teardown — it is the record that a rehearsal ran.
  try {
    await mgmtFixture(REF, `insert into public.rehearsal_window (run_tag, opened_by, models_allowed, cap_usd, expires_at)
      values ('qd_run:${run.tag}', 'demo_factory.withRun', true, ${Number(capUsd)}, now() + make_interval(mins => ${Math.min(120, Number(minutes) | 0)}))`, 'rehearsal window');
    process.env.QD_E2E_RUN_TAG = run.tag;
  }
  catch (e) { run.log(`(rehearsal window not declared: ${String(e.message || e).slice(0, 120)})`); }
  const disarm = closeOnExit(() => closeRehearsalWindow(run.tag));
  try {
    return await fn(run);
  } finally {
    disarm();
    if (run.keep) run.log(`run ${run.tag} KEPT (teardown skipped) - tear down later with --purge`);
    else {
      const t = await teardown(run);
      run.log(`run ${run.tag} torn down: ${t.summary}`);
    }
    try { await closeRehearsalWindow(run.tag); }
    catch (e) { run.log(`(rehearsal window not closed: ${String(e.message || e).slice(0, 120)})`); }
  }
}

// ---- auth ------------------------------------------------------------------------------------
export async function mkAuthUser(run, email) {
  const { ANON, SERVICE } = await keys();
  const password = 'Demo-' + randomBytes(8).toString('hex') + 'A1!';
  const c = await fetch(`${BASE}/auth/v1/admin/users`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
    // app_metadata.e2e_run: only the service role can set it, and _shared/e2e_run.ts lets a browser session
    // reason inside its run's open window ONLY when it is present and matches (review of #1361).
    body: JSON.stringify({ email, password, email_confirm: true,
      ...(/^qd-([a-z0-9]{4,16})-/.test(email) ? { app_metadata: { e2e_run: email.match(/^qd-([a-z0-9]{4,16})-/)[1] } } : {}) }),
  });
  const cu = await c.json();
  if (!cu.id) throw new Error(`auth create failed for ${email}: ${JSON.stringify(cu).slice(0, 200)}`);
  run.authUsers.push(cu.id);
  const t = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const tok = await t.json();
  return { id: cu.id, email, password, jwt: tok.access_token ?? null };
}

async function deleteAuthUsersByTag(tag) {
  const { SERVICE } = await keys();
  const rows = await mgmtRead(REF,
    `select id from auth.users where email like 'qd-${tag}-%@example.%'`);
  let n = 0;
  for (const r of rows) {
    const d = await fetch(`${BASE}/auth/v1/admin/users/${r.id}`, {
      method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
    });
    if (d.ok) n++;
  }
  return n;
}

// ---- customers -------------------------------------------------------------------------------
/**
 * makeCustomer(run, opts) -> { id, email, jwt, customerId, locale }
 *
 * mode 'sql'  (default): auth-admin identity + a direct customers INSERT. Zero model calls, zero
 *                        Edge Function calls. This is the bulk path.
 * mode 'api'            : the real journey - kyc save_customer, the OTP round trip through
 *                        login_otp, and kyc accept_terms (which writes a signed-terms PDF).
 *                        Still zero MODEL calls; kyc does not use the gateway.
 */
export async function makeCustomer(run, opts = {}) {
  const mode = opts.mode || 'sql';
  const email = opts.email || runEmail(run, 'cust');
  const locale = opts.locale || 'en';
  const fullName = opts.full_name || (locale === 'ar' ? 'عميل تجريبي' : 'Demo Customer');
  const phone = opts.phone || '+9715' + String(10000000 + Math.floor(Math.random() * 8999999));
  const u = await mkAuthUser(run, email);

  if (mode === 'api') {
    await call('kyc', u.jwt, { action: 'save_customer', user_kind: 'customer', email, full_name: fullName, phone });
    if (opts.verified !== false) await verifyEmailByOtp(email, 'customer');
    if (opts.terms !== false) await call('kyc', u.jwt, { action: 'accept_terms', user_kind: 'customer', email });
    if (locale !== 'en') {
      await mgmtFixture(REF, `update public.customers set locale=${q(locale)} where id=${q(u.id)}`, 'customer locale');
    }
  } else {
    // tos_version is read from app_secrets by kyc so the acceptance records WHICH document was
    // signed; the SQL path records the same version rather than inventing one.
    await mgmtFixture(REF,
      `insert into public.customers (id, email, full_name, phone, email_verified, locale
         ${opts.terms === false ? '' : ', tos_accepted_at, tos_version'})
       values (${q(u.id)}, ${q(email)}, ${q(fullName)}, ${q(phone)},
               ${bool(opts.verified !== false)}, ${q(locale)}
         ${opts.terms === false ? '' : `, now(), (select value from public.app_secrets where key='customer_terms_version')`})
       on conflict (id) do update set email=excluded.email, full_name=excluded.full_name`,
      'demo customer');
  }
  const row = (await mgmtRead(REF, `select id from public.customers where id=${q(u.id)}`))[0];
  if (!row) throw new Error(`customers row not created for ${email}`);
  return { id: u.id, customerId: u.id, email, jwt: u.jwt, password: u.password, locale, full_name: fullName };
}

/**
 * The OTP hop, exactly as journey_test does it: login_otp stores an HMAC of the code and never the
 * code, and staging cannot receive mail (email_enabled is forced off), so we write the row with a
 * code we chose, hashed the way login_otp hashes it, then verify through the REAL endpoint. Hash
 * comparison, expiry, purpose, single-use and the customers.email_verified write are all genuinely
 * exercised; only the delivery hop is skipped.
 */
export async function verifyEmailByOtp(email, userKind = 'customer', code = '424242') {
  // A SEEDED CODE IS A SESSION FOR WHOEVER OWNS THE ADDRESS (19 Oct 2026). Only a reserved RFC 2606
  // address can be seeded; a real account's address is refused before anything is written.
  if (!/^[^@\s]+@example\.invalid$/i.test(String(email))) {
    throw new Error(`REFUSED: a sign-in code is only ever seeded for a demo @example.invalid address, not ${email}`);
  }
  const key = (await mgmtRead(REF, "select value from public.app_secrets where key='otp_hmac_key'"))[0]?.value;
  if (!key) throw new Error('otp_hmac_key missing from staging app_secrets');
  const hash = createHmac('sha256', key).update(code).digest('hex');
  await mgmtFixture(REF,
    `insert into public.email_verifications (email, token_hash, purpose, user_kind, expires_at)
     values (${q(email)}, ${q(hash)}, 'login', ${q(userKind)}, now() + interval '10 minutes')`, 'seed otp');
  return call('login_otp', null, { action: 'verify', identifier: email, code, user_kind: userKind });
}

// ---- suppliers -------------------------------------------------------------------------------
/**
 * The capability profile for one supplier, parameterised by trade and by a variant index.
 *
 * The variant ladder is the point. fn_match_capability scores
 *     w_prod * product_hits/|p_products|  (40)
 *   + w_brand * brand_hit                 (20)
 *   + w_ptype * ptype_hit                 (15)
 *   + w_track * track                     (15)
 *   + w_size  * (size_known ? 1 : 0.5)    (10)
 * so with brands and project_type left out of the query, and track 0 on a fresh corpus, score is a
 * pure function of how many of the query's products the supplier declares. Variant 0 declares all
 * of them, the last variant declares NONE of them and leaves min/max_project_value null, which is
 * the 5-point floor case the relevance floor is supposed to discard.
 */
export function capabilityProfile(trade, variant = 0, variants = 1, opts = {}) {
  const t = TRADES[trade];
  if (!t) throw new Error(`unknown trade ${trade} (expected one of taxonomy_trade.code)`);
  const decoyTrade = TRADE_CODES[(TRADE_CODES.indexOf(trade) + 7) % TRADE_CODES.length];
  // `flat` gives every supplier the full product list, so they all clear match_relevance_floor.
  // That is what a fan-out test needs: the ladder deliberately puts only 2 of 4 above the floor,
  // which can never exercise a cap of 5.
  const isDecoy = !opts.flat && variants >= 3 && variant === variants - 1;

  // Two products dropped per rung, and the last rung of a 3+ ladder is a zero-overlap decoy. With
  // the default 8 products and 4 variants that is 8, 6, 4 and 0 matching products, so a query using
  // all 8 scores 50, 40, 30 and 5 - two clearly above the match_relevance_floor of 35, one clearly
  // below it, and one on the w_size*0.5 floor. No rung lands ON 35, so a floor test never depends
  // on whether the comparison is > or >=.
  const keep = opts.flat ? t.products.length : Math.max(1, t.products.length - variant * 2);
  const products = isDecoy ? TRADES[decoyTrade].products.slice(0, 4) : t.products.slice(0, keep);
  const auth = AUTHORITY[trade];
  return {
    trades: [trade],
    // Roles are a GATE, not a score term, so they are uniform unless a caller asks otherwise.
    // Varying them "for realism" silently changes eligibility: the first cut of this file gave
    // every 4th supplier supplies_only roles, which is exactly the decoy slot, so the decoy was
    // dropped by the role gate and never reached the relevance floor it was built to test. Vary
    // the score dial (products_norm); hold the gates still.
    roles: ROLE_SETS[opts.roleSet] || ROLE_SETS.both,
    products_norm: products,
    project_types: PROJECT_TYPES[variant % PROJECT_TYPES.length],
    brands: t.brands.slice(0, 1 + (variant % t.brands.length)),
    coverage_emirates: EMIRATES.slice(0, 1 + (variant % 3)),
    // A mandatory authority missing from authority_approvals drops the row before scoring, so the
    // fixture holds it for regulated trades. The decoy deliberately still holds it: its low score
    // must come from products, not from being silently gated out for a different reason.
    authority_approvals: auth ? { [auth]: { ref: `DEMO-${auth.toUpperCase()}-${variant}`, valid_until: '2027-12-31' } } : {},
    min_project_value: isDecoy ? null : [1000, 25000, 100000, 250000][variant % 4],
    max_project_value: isDecoy ? null : [500000, 2000000, 5000000, 20000000][variant % 4],
    completeness: isDecoy ? 55 : 95 - variant * 5,
  };
}

const capabilityInsert = (leadId, p) => `insert into public.supplier_capabilities
   (supplier_id, trades, roles, products_norm, project_types, brands, exclusions,
    authority_approvals, source_docs, confidence, missing_fields, excluded_trades,
    completeness, review_status, confirmed_at, extracted_at,
    min_project_value, max_project_value, coverage_emirates)
 values (${num(leadId)}, ${arr(p.trades)}, ${arr(p.roles)}, ${arr(p.products_norm)},
   ${arr(p.project_types)}, ${arr(p.brands)}, '{}'::text[],
   ${jb(p.authority_approvals)}, '{}'::jsonb, '{"overall":0.9}'::jsonb,
   '{}'::text[], '{}'::text[],
   ${num(p.completeness)}, 'confirmed', now(), now(),
   ${num(p.min_project_value)}, ${num(p.max_project_value)}, ${arr(p.coverage_emirates)})
 on conflict (supplier_id) do update
   set trades=excluded.trades, roles=excluded.roles, products_norm=excluded.products_norm,
       project_types=excluded.project_types, brands=excluded.brands,
       authority_approvals=excluded.authority_approvals,
       min_project_value=excluded.min_project_value, max_project_value=excluded.max_project_value,
       coverage_emirates=excluded.coverage_emirates,
       completeness=excluded.completeness, review_status='confirmed', confirmed_at=now()`;

/**
 * makeSupplier(run, opts) -> { leadId, id, email, jwt, companyName, trade, profile }
 *
 * Returns the WHOLE identity, which standUpSupplier() did not: a caller can now make a supplier and
 * then act as it (inbox, submit_quote, extract_quote) instead of only asserting that it exists.
 *
 * mode 'sql' (default): auth-admin identity + one leads INSERT + one supplier_capabilities INSERT.
 *                       Zero model calls.
 * mode 'api'          : create_company -> save_profile -> accept_terms -> approve -> enrich_capability.
 *                       Costs 3 billable model calls (profile_ai on save_profile,
 *                       enrich_capability, supplier_review). It was 2 until 5 Aug 2026, when
 *                       supplier_review was moved off supplier_matching (tier=none) onto
 *                       json_extraction: it had been resolving to use_llm:false and LAUNDERING that
 *                       refusal into severity='clean', so every demo supplier - and every real one -
 *                       was certified clean by a model that never ran.
 *
 * Both modes end approved WITH the founder's mandatory six (completeMandatorySix): since #698 the
 * database refuses an approval with anything missing, so the supplier is inserted undecided and the
 * sales engineer's verification approves it. The one exception is a caller that brings its own
 * documents (scripts/e2e/fixtures.mjs): it passes opts.approval ('pending'), the row is inserted with
 * that status and no documents, and completing it is the caller's job. Use makeLicenceGatedSupplier()
 * when you want a supplier the six refuse.
 */
export async function makeSupplier(run, opts = {}) {
  const trade = opts.trade || 'aluminium';
  const t = TRADES[trade];
  if (!t) throw new Error(`unknown trade ${trade}`);
  const mode = opts.mode || 'sql';
  const variant = opts.variant ?? 0;
  // opts.coverage_emirates: the e2e funnel's demo suppliers serve every emirate its customers ask in (stage2 run f4294be8: a
  // Dubai-only profile left 6 of 8 requests in other emirates with nobody to match).
  const profile = { ...(opts.profile || capabilityProfile(trade, variant, opts.variants ?? 1)), ...(opts.coverage_emirates ? { coverage_emirates: opts.coverage_emirates } : {}) };
  const email = opts.email || runEmail(run, 'sup');
  const companyName = opts.company_name || `QD Demo ${t.name} ${run.tag.slice(0, 4)}-${run.seq}`;
  const emirate = opts.emirate || profile.coverage_emirates[0] || 'Dubai';
  const withAuth = opts.withAuth !== false;
  // Since #698 trg_leads_e0_mandatory_six_gate REFUSES an approval unless the six are complete (the
  // licence and company profile must exist in supplier-docs). By default the factory completes them
  // and the sales engineer approves; a caller passing approval ('pending') brings its own documents.
  const bringsOwnDocs = opts.approval !== undefined;
  const phone = demoMobile();

  const u = withAuth ? await mkAuthUser(run, email) : { id: null, email, jwt: null, password: null };

  let leadId = null;
  if (mode === 'api') {
    const c = await call('supplier_api', u.jwt, {
      action: 'create_company', company_name: companyName, emirate, role: 'supplier',
    });
    leadId = c.json?.id ?? null;
    if (!leadId) throw new Error(`create_company failed: HTTP ${c.status} ${c.text}`);
    await call('supplier_api', u.jwt, {
      action: 'save_profile',
      products: profile.products_norm.join(', '),
      services: `Supply and installation of ${t.name.toLowerCase()}.`,
      description: `${t.name} specialist serving ${profile.coverage_emirates.join(', ')}.`,
      company_type: 'LLC', contact_name: 'Demo Contact', phone,
      service_emirates: profile.coverage_emirates,
    });
    await call('kyc', u.jwt, { action: 'accept_terms', user_kind: 'supplier', email });
    // No approval is written here any more: completeMandatorySix below brings the documents and the
    // sales engineer decides. The mobile is recorded as verified directly - Twilio Verify cannot be
    // driven without sending an SMS, and the number is the fixture block by design. The e-mail was
    // confirmed by the auth admin API. Match case-insensitively - the API lowercases claimed_by.
    await mgmtFixture(REF,
      `update public.leads
          set phone = ${q(phone)}, owner_phone_verified = true, owner_email_verified = true,
              tags = (select array(select distinct unnest(coalesce(tags,'{}'::text[])
                       || ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[])))
        where lower(claimed_by)=lower(${q(email)})`, 'demo supplier mobile and e-mail verified');
    if (opts.enrich !== false) {
      const cred = await internalCred();
      if (cred) await call('enrich_capability', null, { __secret: cred, lead_id: leadId });
    }
  } else {
    const ins = await mgmtFixture(REF,
      `insert into public.leads
         (company_name, emirate, city, claimed, claimed_by, email, contact_name, phone,
          company_type, products, services, description, service_emirates, source,
          verified, approval_status, owner_email_verified, owner_phone_verified, accepted_terms_at,
          accepted_terms_version, locale, tags)
       values (${q(companyName)}, ${q(emirate)}, ${q(emirate)}, ${bool(withAuth)},
               ${withAuth ? q(email) : 'null'}, ${q(email)}, 'Demo Contact', ${q(phone)},
               'LLC', ${q(profile.products_norm.join(', '))},
               ${q(`Supply and installation of ${t.name.toLowerCase()}.`)},
               ${q(`${t.name} specialist serving ${profile.coverage_emirates.join(', ')}.`)},
               ${arr(profile.coverage_emirates)}, 'demo_factory',
               false, ${bringsOwnDocs ? q(opts.approval) : 'null'}, true, true, now(), ${TERMS_VERSION_SQL},
               ${q(opts.locale || 'en')},
               ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[])
       returning id`, 'demo supplier');
    leadId = ins?.[0]?.id ?? null;
    if (!leadId) throw new Error(`leads insert returned no id for ${companyName}`);
  }

  if (opts.capability === 'agent') await confirmCapability(leadId, profile);
  else if (opts.capability !== false) await mgmtFixture(REF, capabilityInsert(leadId, profile), 'demo capability');
  // THE SERVICES TAB (28 Sep 2026). A supplier that declares a trade and ticks none of the services an inquiry names
  // in it is NOT reached (founder instruction 857). The default fixture ticks nothing, which is the shape the 857
  // check needs; opts.services: 'all' ticks every active service of the supplier's own trades, the way a real
  // supplier who does the whole trade fills the tab. (Measured on #1056's rehearsal: an MEP inquiry naming
  // mep_general.mep_install reached the plumbing and HVAC demo suppliers, never asked, and not the MEP one, which
  // declared the trade and had ticked nothing: the matcher was right and the fixture was the gap.)
  if (opts.services === 'all' && opts.capability !== false) {
    await mgmtFixture(REF,
      `update public.supplier_capabilities sc
          set services = (select coalesce(array_agg(t.trade_code || '.' || t.code order by t.trade_code, t.sort), '{}')
                            from public.taxonomy_trade_service t where t.active and t.trade_code = any(sc.trades))
        where sc.supplier_id = ${num(leadId)}`, 'demo supplier ticks its trade services');
  }
  // The API path stamps the tag in its verification UPDATE; the SQL path stamps it in the INSERT.
  // Belt and braces for the api path where create_company may have raced the update.
  await mgmtFixture(REF,
    `update public.leads set tags = (select array(select distinct unnest(coalesce(tags,'{}'::text[])
       || ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[]))) where id=${num(leadId)}`, 'tag demo supplier');
  if (!bringsOwnDocs) await completeMandatorySix(run, [{ leadId, companyName }]);

  return {
    leadId, id: leadId, email, jwt: u.jwt, password: u.password, authUserId: u.id,
    companyName, trade, profile, emirate,
  };
}

// Run fn over items with at most n in flight; results keep the input order.
async function eachLimit(items, n, fn) {
  const out = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (next < items.length) { const k = next++; out[k] = await fn(items[k]); }
  }));
  return out;
}

/**
 * The founder's mandatory six for demo suppliers, produced the way a real registration produces them,
 * and then DECIDED by the sales engineer (fn_sales_engineer_verifies_supplier), never by writing
 * approval_status. Since #698 trg_leads_e0_mandatory_six_gate refuses an approval while anything is
 * missing, so an approved fixture with no documents is no longer a thing that can exist.
 *
 *   1-3  company name, the fixture +9715 mobile (verified) and the verified e-mail: the INSERT.
 *   4-5  a licence PDF and a company-profile PDF as real objects in supplier-docs: the six counts a
 *        document only if storage holds it. The row names them BEFORE the bytes go up, so a failed
 *        upload leaves a path to nothing (harmless) rather than an object no row names (litter).
 *   6    the signed Supplier Agreement: compliance_archive 'sign', the same call qd_sign_supplier
 *        makes on acceptance. It refuses without accepted_terms_at on record and writes
 *        signed_terms_path itself. Keyed by lead id, which compliance_archive supports, so an
 *        unclaimed (withAuth:false) supplier is signed too - the trigger keys on claimed_by and
 *        would skip it. A row already signed (the api path's kyc accept_terms) is not signed twice.
 *
 * Teardown reaches all three files through BUCKET_SOURCES (license_doc_path and
 * company_profile_doc_path in supplier-docs, signed_terms_path in signed-terms), and reg_lead_docs
 * registers the two documents rows, which teardown also sweeps.
 */
async function completeMandatorySix(run, sups) {
  if (!sups.length) return;
  const docs = sups.map((s) => ({
    ...s,
    lic: `licenses/${s.leadId}/${run.tag}_trade_licence.pdf`,
    prof: `profiles/${s.leadId}/${run.tag}_company_profile.pdf`,
    no: `ZZDEMO-${run.tag}-${s.leadId}`.toUpperCase(),
  }));
  const ids = docs.map((d) => num(d.leadId)).join(',');
  await mgmtFixture(REF,
    `update public.leads l
        set license_doc_path = v.lic, license_doc_name = 'trade_licence.pdf', trade_license_no = v.no,
            license_authority = 'Dubai DET (fixture)', license_expiry = current_date + 365,
            license_city = 'Dubai', company_profile_doc_path = v.prof, licence_legal_name = v.legal
       from (values ${docs.map((d) => `(${num(d.leadId)}::bigint, ${q(d.lic)}, ${q(d.no)}, ${q(d.prof)}, ${q(d.companyName)})`).join(', ')})
            as v(id, lic, no, prof, legal)
      where l.id = v.id`, 'demo supplier documents');
  // licence_legal_name is the name the licence reader takes off the document (a model surface, held): written here
  // as the fixture fact it would read, because since the licence-name rule an UNREAD name holds every registration
  // (fn_sales_engineer_verifies_supplier: licence_name_unread) and no demo supplier could be approved (28 Sep 2026).
  await eachLimit(docs, 8, async (d) => {
    await uploadObject('supplier-docs', d.lic,
      demoTradeLicence({ company: d.companyName, licenceNo: d.no }), 'application/pdf');
    await uploadObject('supplier-docs', d.prof, demoPdf([
      ['COMPANY PROFILE (ZZ DEMO FIXTURE - NOT A REAL COMPANY)', 14], [d.companyName, 12],
      ['Supply and installation, United Arab Emirates.', 11], [`Run ${run.tag}`, 9],
    ]), 'application/pdf');
  });

  const cred = await internalCred();
  const unsigned = await mgmtRead(REF,
    `select id from public.leads where id in (${ids}) and coalesce(btrim(signed_terms_path), '') = ''`);
  await eachLimit(unsigned, 6, async (r) => {
    const s = await call('compliance_archive', null,
      { __secret: cred, action: 'sign', kind: 'supplier', id: Number(r.id) });
    if (s.json?.ok !== true) throw new Error(`compliance_archive refused to sign lead ${r.id}: HTTP ${s.status} ${s.text}`);
  });

  const out = await mgmtFixture(REF,
    `select l.id, public.fn_sales_engineer_verifies_supplier(l.id, 'demo_factory') v
       from public.leads l where l.id in (${ids})`, 'sales engineer verifies demo suppliers');
  const refused = (out || []).filter((r) => r.v?.decision !== 'approved' || (r.v?.missing || []).length);
  if (refused.length || (out || []).length !== docs.length) {
    throw new Error(`the sales engineer approved ${(out || []).length - refused.length}/${docs.length} demo ` +
      `supplier(s); first refusals: ${JSON.stringify(refused.slice(0, 3).map((r) => ({ id: r.id, ...r.v })))} ` +
      `(decision 'pending' with nothing missing means pricing_config.auto_approve_suppliers is off)`);
  }
}

/**
 * A supplier that is deliberately NOT complete: approved with the six, then its licence path is
 * pointed at an object that does not exist and the licence number cleared. trg_leads_e0_mandatory_six_gate
 * demotes it to 'action_required' with licence_gate_reason 'reg_licence', and trg_leads_exception_invariant
 * opens the 14-day window in the same statement. This is the exception-window fixture. (Until 7 Sep the
 * refusal came from fn_supplier_licence_gate, dropped that day; the six gate is what refuses now.)
 * The real licence object it replaced is still named by its documents row, so teardown removes it.
 * opts.unreadable_upload: instead the supplier uploads an unreadable licence through supplier_api process_docs
 * (the real path) - the licence_unreadable case. The direct write stays only for the missing-object case, which
 * the product refuses to produce (process_docs answers document_not_found).
 */
export async function makeLicenceGatedSupplier(run, opts = {}) {
  // ZZ DEMO naming (demo-fixture convention). Without a name this supplier fell to makeSupplier's
  // "QD Demo <trade>" default: stage-2 S02 left "QD Demo Steel Fabrication" (sup13) on 7 Oct 2026.
  const name = opts.company_name || `ZZ DEMO licence-gated ${(TRADES[opts.trade || 'aluminium'] || {}).name || 'supplier'} ${run.tag}`;
  const s = await makeSupplier(run, { ...opts, company_name: name, capability: opts.capability !== false });
  if (opts.unreadable_upload) {
    // THE PRODUCT PATH (stage-2 S02, 7 Oct 2026). The supplier uploads a new licence through supplier_api
    // process_docs, exactly as the portal does: a valid image with no text layer, so code reads no name and
    // process_docs writes licence_legal_name = null itself. Whatever re-gates him (z20 -> the sales engineer's
    // verification) must do it from that write; a direct UPDATE here hid that nothing re-ran the review.
    // Zero model calls while app_secrets.document_expiry_ai is unset (measured 7 Oct 2026: absent).
    const PNG_1PX = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    const r = await call('supplier_api', s.jwt, { action: 'process_docs',
      license: { original_b64: PNG_1PX, mime: 'image/png', filename: 'zz_demo_unreadable_licence.png' } });
    if (r.status !== 200) throw new Error(`process_docs licence upload failed: HTTP ${r.status} ${r.text}`);
  } else await mgmtFixture(REF,
    `update public.leads
        set license_doc_path = ${q(opts.license_doc_path || `supplier-docs/demo/${run.tag}/licence.pdf`)},
            trade_license_no = ${q(opts.trade_license_no ?? null)},
            license_expiry   = ${opts.license_expiry ? q(opts.license_expiry) : 'null'},
            -- a NEW licence nobody has read: the product nulls the name exactly so (supplier_api
            -- "a new licence replaces the old name even when nothing is read"); a stale read name
            -- here made the gate look passed (stage-2 S02, 7 Oct 2026)
            licence_legal_name = ${opts.licence_legal_name ? q(opts.licence_legal_name) : 'null'}
      where id = ${num(s.leadId)}`, 'open licence gate');
  const row = (await mgmtRead(REF,
    `select approval_status, licence_gate_reason from public.leads where id=${num(s.leadId)}`))[0];
  return { ...s, approval_status: row?.approval_status, licence_gate_reason: row?.licence_gate_reason };
}

/**
 * Confirm a capability through the PRODUCT, not through a raw INSERT.
 *
 * capability_agent's `confirm` action makes no model call at all - the single model call in that
 * function sits on the `analyze` path - so this costs nothing, and unlike the 18-column INSERT that
 * journey_test writes out twice it also validates trades and roles against the controlled
 * vocabulary and records a supplier_capability_confirmation ledger row with a version. That ledger
 * is the thing that matters the day a supplier disputes a match.
 *
 * It needs `capability_agent` in a credential scope; seed_staging_secrets.mjs adds it to
 * db.internal. Until session 9 no credential in EITHER project scoped it, which is why the half of
 * the capability flow that is NOT blocked by fn_ai_route's supplier_matching tier=none policy had
 * still never run.
 *
 * Since 5 Aug 2026 the endpoint accepts and writes min_project_value / max_project_value, so this
 * path and the raw SQL INSERT now produce an IDENTICAL row from an identical profile — which is
 * what makes replacing the journey's hand-written 18-column INSERT with this call safe. Before
 * that, a supplier confirmed here scored w_size*0.5 instead of w_size in fn_match_capability and
 * ranked below an otherwise identical supplier created by a fixture.
 */
export async function confirmCapability(leadId, profile, opts = {}) {
  const cred = await internalCred();
  if (!cred) throw new Error('cred_db_internal missing from staging app_secrets');
  const r = await call('capability_agent', null, {
    __secret: cred, action: 'confirm', supplier_id: Number(leadId),
    trades: profile.trades, roles: profile.roles, products: profile.products_norm,
    brands: profile.brands, project_types: profile.project_types,
    coverage_emirates: profile.coverage_emirates, exclusions: profile.exclusions || [],
    min_project_value: profile.min_project_value ?? null,
    max_project_value: profile.max_project_value ?? null,
    confirmed_via: opts.confirmed_via || 'demo_factory',
  });
  if (r.status !== 200 || r.json?.ok !== true) {
    throw new Error(`capability_agent confirm failed: HTTP ${r.status} ${r.text}`);
  }
  return r.json;
}

let _cred = null;
export async function internalCred() {
  if (_cred !== null) return _cred;
  _cred = (await mgmtRead(REF, "select value from public.app_secrets where key='cred_db_internal'"))[0]?.value || null;
  return _cred;
}

// ---- inquiries -------------------------------------------------------------------------------
/**
 * makeInquiry(run, opts) -> { id, customerId, category, trades, status }
 *
 * mode 'sql' (default): one INSERT. Fires enrich_inquiry, rfq_complete, scrub_inquiry_contacts,
 *                       fn_emit_event('inquiry','rfq.created') and trg_inquiry_received, so it
 *                       leaves a company_event row and a queued notifications row behind - both of
 *                       which teardown removes.
 * mode 'api'          : the real multi-turn inquiry_intake loop plus customer_api create_inquiry.
 *                       That is roughly 8 model calls; reserve it for the deep cases.
 */
export async function makeInquiry(run, opts = {}) {
  const cust = opts.customer;
  if (!cust) throw new Error('makeInquiry needs { customer }');
  const trade = opts.trade || 'aluminium';
  const t = TRADES[trade] || TRADES.aluminium;
  const emirate = opts.emirate || 'Dubai';
  const status = opts.status || 'sent';
  const locale = opts.locale || cust.locale || 'en';
  const summary = opts.summary || (locale === 'ar'
    ? `توريد وتركيب ${t.name} لفيلا في ${emirate}`
    : `Supply and install ${t.name.toLowerCase()} for a villa in ${emirate}`);
  const rawInput = opts.raw_input || (locale === 'ar'
    ? `نحتاج ${t.name} لفيلا خاصة في ${emirate}. الرجاء تقديم عرض سعر شامل التوريد والتركيب.`
    : `We need ${t.name.toLowerCase()} supplied and installed for a private villa in ${emirate}.`);

  if (opts.mode === 'api') {
    const answers = opts.answers || DEFAULT_INTAKE_ANSWERS(t, emirate);
    const intake = await runIntake(cust, answers);
    const r = await call('customer_api', cust.jwt, {
      action: 'create_inquiry', intake_id: intake.intakeId, text: rawInput,
    });
    const id = r.json?.id ?? r.json?.inquiry_id ?? null;
    if (!id) throw new Error(`create_inquiry failed: HTTP ${r.status} ${r.text}`);
    await tagInquiry(run, id);
    return { id, customerId: cust.customerId, category: trade, trades: [trade], status, intake };
  }

  const ins = await mgmtFixture(REF,
    `insert into public.inquiries
       (customer_id, category, emirate, role_needed, raw_input, summary, keywords, trades,
        status, budget, scope_type, brief_source, urgency, drawing_file_path, drawing_file_name,
        provenance, spec)
     values (${q(cust.customerId)}, ${q(trade)}, ${q(emirate)}, ${q(opts.role_needed || 'executes')},
             ${q(rawInput)}, ${q(summary)}, ${arr(t.products.slice(0, 4))}, ${arr([trade])},
             ${q(status)}, ${num(opts.budget ?? null)}, ${q(opts.scope_type || 'single')},
             ${q(opts.brief_source || 'chat')}, ${q(opts.urgency || 'normal')},
             ${q(opts.drawing_file_path ?? null)}, ${q(opts.drawing_file_name ?? null)},
             ${jb({ qd_run: run.tag, source: 'demo_factory' })},
             ${rfqReadySpec(trade, opts)})
     returning id`, 'demo inquiry');
  const id = ins?.[0]?.id;
  if (!id) throw new Error('inquiries insert returned no id');

  // An inquiry that is not rfq_ready cannot be dispatched, and dispatch_inquiry says so with
  // {"ok":true,"skip":"not_rfq_ready"} - a 200 that did nothing. Fail loudly here instead.
  if (opts.rfqReady !== false) {
    const row = (await mgmtRead(REF,
      `select rfq_ready, completeness->>'score' score,
              completeness->'category_check'->>'missing' cat_missing
         from public.inquiries where id=${q(id)}`))[0] || {};
    if (row.rfq_ready !== true) {
      throw new Error(`demo inquiry ${id} is not rfq_ready (score ${row.score}, ` +
        `category_specs still missing ${row.cat_missing}) - dispatch would answer ` +
        '{"ok":true,"skip":"not_rfq_ready"} and contact nobody');
    }
  }
  return { id, customerId: cust.customerId, category: trade, trades: [trade], status };
}

/**
 * The structured capability requirement `route_inquiry` gates on. Without a row here
 * `capabilityRetrieve` calls `inquiry_parse` to build one - a model call - and returns null if it
 * still cannot, dropping routing back to the loose legacy path. Writing it directly keeps a
 * matching test deterministic and free.
 *
 * Note `route_inquiry` calls fn_match_capability with a hardcoded `p_limit: 12` and applies
 * `match_relevance_floor` AFTER that limit, so the limit binds before the floor does.
 */
export async function makeRequirement(run, opts = {}) {
  const { inquiry } = opts;
  if (!inquiry) throw new Error('makeRequirement needs { inquiry }');
  const trade = opts.trade || inquiry.category || 'aluminium';
  const t = TRADES[trade] || TRADES.aluminium;
  await mgmtFixture(REF,
    `insert into public.inquiry_requirement
       (inquiry_id, trades_required, role_required, emirate, authority_required, products_norm,
        brands_specified, project_type, value_band, scope_type, confidence, missing_fields,
        parsed_at, parser_version)
     values (${q(inquiry.id)}, ${arr(opts.trades || [trade])}, ${q(opts.role || 'executes')},
             ${q(opts.emirate ?? null)}, ${arr(opts.authority || [])},
             ${arr(opts.products || t.products)}, ${arr(opts.brands || [])},
             ${q(opts.project_type ?? null)}, ${num(opts.value_band ?? 150000)},
             ${q(opts.scope_type || 'single')}, '{"overall":0.9}'::jsonb, '{}'::text[],
             now(), 'demo_factory')
     on conflict (inquiry_id) do update
       set trades_required=excluded.trades_required, role_required=excluded.role_required,
           products_norm=excluded.products_norm, value_band=excluded.value_band,
           emirate=excluded.emirate, project_type=excluded.project_type`, 'demo requirement');
  return { inquiry_id: inquiry.id, trades: opts.trades || [trade] };
}

/**
 * A spec that satisfies the category's OWN checklist.
 *
 * `trg_rfq_complete` runs `fn_rfq_score` on every insert and update, so `rfq_ready` cannot be set
 * by hand - it is computed. It needs 70 generic points AND `fn_rfq_required_check` to find an
 * answer for every field `category_specs` marks required. A hand-written spec satisfies the first
 * and fails the second, and the only symptom is dispatch_inquiry returning
 * {"ok":true,"skip":"not_rfq_ready"}: an ok:true that contacted nobody.
 *
 * So the required keys are read out of category_specs IN SQL rather than hard-coded. A field with
 * `options` gets its first option (which is also what the option-token fallback scans the blob
 * for); everything else gets its own question echoed back, which is enough for `_rfq_answered` -
 * that only rejects null, empty, '[]', '{}', '-', '?', 'null', 'not sure', 'unknown', 'tbd',
 * 'n/a' and 'na'. Reading the checklist instead of copying it means a new required field starts
 * being answered the day it is added.
 */
function rfqReadySpec(trade, opts) {
  const base = opts.spec || { products: (TRADES[trade] || TRADES.aluminium).products.slice(0, 4),
                              quantity: opts.quantity ?? 40 };
  if (opts.rfqReady === false) return jb(base);
  return `(coalesce((
      select jsonb_object_agg(lower(f->>'key'),
               coalesce((select o from jsonb_array_elements_text(f->'options') o limit 1),
                        'Demo answer: ' || coalesce(f->>'question', f->>'key')))
        from public.category_specs cs, jsonb_array_elements(cs.fields) f
       where lower(cs.category) = lower(${q(trade)})
         and coalesce((f->>'required')::boolean, false)
         and nullif(btrim(lower(coalesce(f->>'key',''))), '') is not null
    ), '{}'::jsonb) || ${jb(base)})`;
}

const tagInquiry = (run, id) => mgmtFixture(REF,
  `update public.inquiries
      set provenance = coalesce(provenance,'{}'::jsonb) || ${jb({ qd_run: run.tag, source: 'demo_factory' })}
    where id = ${q(id)}`, 'tag demo inquiry');

export const DEFAULT_INTAKE_ANSWERS = (t, emirate) => [
  `${t.name}: supply and installation. 40 units for a private villa in ${emirate}.`,
  'Sizes: 40 units at 1200 mm W x 1500 mm H each, approximately 72 square metres in total.',
  'Scope: supply and install, including removing the existing units and disposing of them.',
  `Property: private villa in ${emirate}, ground and first floor, direct vehicle access, no crane needed.`,
  `Specification: ${t.products.slice(0, 3).join(', ')}, standard commercial grade.`,
  'Timeline: installation within eight weeks of order. Budget is open; include supply and install.',
];

/** The adaptive intake loop. Each turn answers whatever the server still says is missing. */
// The fact sheet lives in ./fact_sheet.mjs (importable without a management token, so its test runs in CI).
export { factSheet } from './fact_sheet.mjs';

/**
 * Drive inquiry_intake. `answers` are the scripted turns; after them a `sheet` (factSheet) answers
 * what was asked. Without a sheet the old filler stays, for callers that script every turn.
 */
export async function runIntake(cust, answers, maxTurns = 10, sheet = null) {
  let intakeId = null, status = null, readiness = 0, missing = [], turns = 0, last = null;
  const log = [];
  for (let i = 0; i < maxTurns; i++) {
    const answer = i < answers.length ? answers[i]
      : sheet ? sheet.answerFor(last)
      : `Details: ${missing.slice(0, 6).map((m) => `${m}: standard specification, please assume typical values`).join('; ') || 'please proceed with typical values'}.`;
    const r = await call('inquiry_intake', cust.jwt,
      intakeId ? { intake_id: intakeId, text: answer, email: cust.email }
               : { text: answer, email: cust.email });
    turns++;
    if (r.status !== 200) { status = `HTTP ${r.status} ${r.text}`; break; }
    last = r.json;
    intakeId = r.json?.intake_id ?? r.json?.id ?? intakeId;
    status = r.json?.status ?? null;
    // readiness is an object {filled, required, score}; the number is readiness_score.
    readiness = Number(r.json?.readiness_score ?? r.json?.readiness?.score ?? 0);
    missing = Array.isArray(r.json?.missing) ? r.json.missing.map(String) : [];
    log.push({ turn: turns, answer, asked_key: r.json?.next_question?.key ?? null, missing_keys: r.json?.required_gate?.missing_keys ?? null, status });
    if (status === 'ready') break;
    // A HELD TURN ENDS THE INTERVIEW AND SAYS WHY (12 Oct 2026, run 1c94fa6a). 'held' means no model could
    // read the trade; re-asking 13 more times only repeated it, and the result read "readiness 0" with the
    // gateway's HTTP status (a 502 from a spent OpenRouter key) nowhere in it. 'held' also means a spec went
    // unanswered three turns (slots.ts MAX_OPEN_TURNS): held_reason then reads 'specs_unanswered: <keys>'.
    if (status === 'held') {
      const f = r.json?.llm_failure;
      status = `held (${r.json?.held_reason ?? 'held'}${f ? `; gateway HTTP ${f.http} ${f.error} ${f.detail}` : ''})`;
      break;
    }
  }
  return { intakeId, status, readiness, missing, turns, log };
}

// ---- quotes ----------------------------------------------------------------------------------
/**
 * A quote is only ACCEPTED (status submitted, not draft) when the form is complete: source 'form',
 * at least one priced item, and validity, warranty and lead_time all present. Amount plus notes
 * alone leaves a draft with submittable=false while the API still answers status 'submitted', and
 * comparison then reports "needs at least two complete quotes" for an RFQ that has two.
 */
export const quotePayload = (inquiryId, amount, note, extra = {}) => ({
  action: 'submit_quote', inquiry_id: inquiryId, amount, currency: 'AED', source: 'form',
  items: [{ description: extra.item || 'Supply and installation as specified', qty: 40, unit_price: Math.round(amount / 40) }],
  lead_time: '8 weeks', validity: '30 days', warranty: '12 months',
  payment_terms: '50% advance, 50% on completion',
  scope: extra.scope || 'Supply, delivery and installation including removal of existing units.',
  conditions: 'Access to site during working hours.',
  exclusions: 'Civil works, painting, scaffolding.',
  notes: note,
  ...extra.overrides,
});

export async function makeQuote(run, opts = {}) {
  const { inquiry, supplier } = opts;
  if (!inquiry || !supplier) throw new Error('makeQuote needs { inquiry, supplier }');
  const amount = opts.amount ?? 125000;
  const note = opts.notes || 'Demo quotation for the stated scope.';

  if (opts.mode === 'api') {
    const r = await call('supplier_api', supplier.jwt, quotePayload(inquiry.id, amount, note, opts));
    if (r.status !== 200) throw new Error(`submit_quote failed: HTTP ${r.status} ${r.text}`);
    const row = (await mgmtRead(REF,
      `select id, status, submittable from public.quotes
        where inquiry_id=${q(inquiry.id)} and supplier_id=${num(supplier.leadId)}`))[0] || {};
    return { id: row.id, status: row.status, submittable: row.submittable, amount };
  }

  const ins = await mgmtFixture(REF,
    `insert into public.quotes
       (inquiry_id, supplier_id, quote_amount, notes, status, source, lead_time, validity,
        warranty, payment_terms, scope, conditions, exclusions, anonymized)
     values (${q(inquiry.id)}, ${num(supplier.leadId)}, ${num(amount)}, ${q(note)},
             ${q(opts.status || 'submitted')}, ${q(opts.source || 'form')},
             ${q(opts.lead_time || '8 weeks')}, ${q(opts.validity || '30 days')},
             ${q(opts.warranty || '12 months')}, ${q(opts.payment_terms || '50% advance, 50% on completion')},
             ${q(opts.scope || 'Supply, delivery and installation as specified.')},
             ${q(opts.conditions || 'Access to site during working hours.')},
             ${q(opts.exclusions || 'Civil works, painting, scaffolding.')},
             ${bool(opts.anonymized ?? true)})
     on conflict (inquiry_id, supplier_id, option_no) do update
       set quote_amount=excluded.quote_amount, status=excluded.status, notes=excluded.notes
     returning id, status, quote_amount`, 'demo quote');
  const row = ins?.[0] || {};
  return { id: row.id, status: row.status, amount: Number(row.quote_amount) };
}

/**
 * Reveal a quote — the paid step the whole marketplace turns on.
 *
 * `customer_api my_inquiries` decides what a customer may see about a supplier purely by whether a
 * `transactions` row exists for that quote_id: pre-reveal it returns `supplier_ref: null`, banded
 * rating/review/years figures, and OMITS `emirate`, `rating_source` and `win_rate` entirely rather
 * than sending nulls. So a transactions row is not bookkeeping here, it is the switch.
 */
export async function makeReveal(run, opts = {}) {
  const { quote, inquiry, supplier, customer } = opts;
  if (!quote || !inquiry || !supplier || !customer) {
    throw new Error('makeReveal needs { quote, inquiry, supplier, customer }');
  }
  const fee = opts.reveal_fee ?? 150;
  const ins = await mgmtFixture(REF,
    `insert into public.transactions
       (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee,
        customer_price, fee_status, revealed_at, paid_by, payment_ref)
     values (${q(quote.id)}, ${q(inquiry.id)}, ${num(supplier.leadId)}, ${q(customer.customerId)},
             ${num(quote.amount)}, ${num(fee)}, ${num(quote.amount)}, ${q(opts.fee_status || 'paid')},
             now(), ${q(opts.paid_by || 'customer')}, ${q(opts.payment_ref || `demo-${run.tag}`)})
     returning id`, 'demo reveal');
  return { id: ins?.[0]?.id, reveal_fee: fee };
}

// ---- bulk corpus -----------------------------------------------------------------------------
/**
 * makeBulkCorpus(run, opts) -> { suppliers: [...], customers: [...], trades: [...] }
 *
 * The acceptance-scale corpus, built with ZERO model calls. Standing one supplier up through the
 * API costs 2 billable model calls, so 100 suppliers that way is ~200 inference calls and no extra
 * confidence: reserve the API path for the 2-3 deep cases actually being asserted end to end.
 *
 * Suppliers default to withAuth:false - a matching corpus never logs in, and skipping 100 auth
 * round trips is most of the runtime. Pass withAuth:true if you need to act as them.
 */
export async function makeBulkCorpus(run, opts = {}) {
  const trades = opts.trades || TRADE_CODES;
  const perTrade = opts.perTrade ?? 4;
  const nCustomers = opts.customers ?? 0;
  const withAuth = opts.withAuth === true;

  // One multi-row INSERT for all suppliers, one for all capabilities: 2 management-API round trips
  // instead of 200. leads.id is GENERATED ALWAYS AS IDENTITY, so the ids come back from RETURNING.
  const specs = [];
  for (const trade of trades) {
    for (let v = 0; v < perTrade; v++) {
      const profile = capabilityProfile(trade, v, perTrade, { flat: opts.flat, roleSet: opts.roleSet });
      const t = TRADES[trade];
      specs.push({
        trade, variant: v, profile,
        // run.seq, not specs.length: leads carries a unique index on lower(email), and a second
        // makeBulkCorpus call in the same run would restart the numbering and collide on corp0.
        email: `qd-${run.tag}-corp${run.seq++}@example.invalid`,
        companyName: `QD Demo ${t.name} ${String(v + 1).padStart(2, '0')} ${run.tag.slice(0, 4)}`,
        emirate: profile.coverage_emirates[0] || 'Dubai',
      });
    }
  }
  if (!specs.length) return { suppliers: [], customers: [], trades };

  const values = specs.map((s) => `(${q(s.companyName)}, ${q(s.emirate)}, ${q(s.emirate)},
      false, null, ${q(s.email)}, 'Demo Contact', ${q(demoMobile())},
      'LLC', ${q(s.profile.products_norm.join(', '))},
      ${q(`Supply and installation of ${TRADES[s.trade].name.toLowerCase()}.`)},
      ${q(`${TRADES[s.trade].name} specialist serving ${s.profile.coverage_emirates.join(', ')}.`)},
      ${arr(s.profile.coverage_emirates)}, 'demo_factory', false, null, true, true, now(), ${TERMS_VERSION_SQL}, 'en',
      ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[])`).join(',\n');

  // Inserted undecided (approval_status null) and approved by the sales engineer once the six are in:
  // see completeMandatorySix below, which every corpus supplier goes through.
  const ins = await mgmtFixture(REF,
    `insert into public.leads
       (company_name, emirate, city, claimed, claimed_by, email, contact_name, phone,
        company_type, products, services, description, service_emirates, source,
        verified, approval_status, owner_email_verified, owner_phone_verified, accepted_terms_at,
        accepted_terms_version, locale, tags)
     values ${values}
     returning id, email`, 'demo corpus suppliers');

  const byEmail = new Map((ins || []).map((r) => [String(r.email).toLowerCase(), r.id]));
  const suppliers = specs.map((s) => ({
    ...s, leadId: byEmail.get(s.email.toLowerCase()) ?? null, jwt: null,
  })).filter((s) => s.leadId != null);
  if (suppliers.length !== specs.length) {
    throw new Error(`corpus insert returned ${suppliers.length} ids for ${specs.length} rows`);
  }

  const capValues = suppliers.map((s) => {
    const p = s.profile;
    return `(${num(s.leadId)}, ${arr(p.trades)}, ${arr(p.roles)}, ${arr(p.products_norm)},
      ${arr(p.project_types)}, ${arr(p.brands)}, '{}'::text[], ${jb(p.authority_approvals)},
      '{}'::jsonb, '{"overall":0.9}'::jsonb, '{}'::text[], '{}'::text[],
      ${num(p.completeness)}, 'confirmed', now(), now(),
      ${num(p.min_project_value)}, ${num(p.max_project_value)}, ${arr(p.coverage_emirates)})`;
  }).join(',\n');
  await mgmtFixture(REF,
    `insert into public.supplier_capabilities
       (supplier_id, trades, roles, products_norm, project_types, brands, exclusions,
        authority_approvals, source_docs, confidence, missing_fields, excluded_trades,
        completeness, review_status, confirmed_at, extracted_at,
        min_project_value, max_project_value, coverage_emirates)
     values ${capValues}
     on conflict (supplier_id) do nothing`, 'demo corpus capabilities');

  if (withAuth) for (const s of suppliers) {
    const u = await mkAuthUser(run, s.email);
    s.jwt = u.jwt; s.authUserId = u.id;
    await mgmtFixture(REF,
      `update public.leads set claimed=true, claimed_by=${q(s.email)} where id=${num(s.leadId)}`,
      'claim corpus supplier');
  }
  await completeMandatorySix(run, suppliers);

  const customers = [];
  for (let i = 0; i < nCustomers; i++) {
    customers.push(await makeCustomer(run, {
      mode: 'sql', locale: i % 10 === 0 ? 'ar' : 'en',
      full_name: i % 10 === 0 ? `عميل ${i}` : `Demo Customer ${i}`,
    }));
  }

  run.log(`corpus: ${suppliers.length} supplier(s) across ${trades.length} trade(s)` +
          `${nCustomers ? `, ${customers.length} customer(s)` : ''}`);
  return { suppliers, customers, trades };
}

// ---- teardown --------------------------------------------------------------------------------
// Storage paths are DERIVED FROM THE DATABASE, never from a hand-maintained list. The hand-listed
// version in journey_test is why 118 signed-terms objects and 19 comparison PDFs are still sitting
// in staging: nobody added those two buckets to the list.
// A scope is a set of WHERE fragments, one per table, all derived from the run tag. Everything
// downstream (storage discovery, the delete order) is built from these rather than from string
// surgery on a subquery, which is how the first cut of this file produced
// `select id::text from (select id from ...)` and would have silently deleted nothing.
function scopeForRun(tag) {
  const cust = `email like 'qd-${tag}-%@example.%'`;
  const lead = `'qd_run:${tag}' = any(coalesce(tags,'{}'::text[]))`;
  const inq = `(customer_id in (select id from public.customers where ${cust})` +
              ` or provenance->>'qd_run' = '${tag}')`;
  const quote = `(inquiry_id in (select id from public.inquiries where ${inq})` +
                ` or supplier_id in (select id from public.leads where ${lead}))`;
  return { cust, lead, inq, quote, redaction: `(customer_id in (select id from public.customers where ${cust}) or owner_email like 'qd-${tag}-%@example.%')` };
}

const scopeSql = (s) => ({
  CUST: `(select id from public.customers where ${s.cust})`,
  LEAD: `(select id from public.leads where ${s.lead})`,
  INQ: `(select id from public.inquiries where ${s.inq})`,
  QUO: `(select id from public.quotes where ${s.quote})`,
  INQ_T: `(select id::text from public.inquiries where ${s.inq})`,
  QUO_T: `(select id::text from public.quotes where ${s.quote})`,
  LEAD_T: `(select id::text from public.leads where ${s.lead})`,
});

const BUCKET_SOURCES = (s) => [
  {
    bucket: 'drawing-files', sql:
      `select drawing_file_path p from public.inquiries where ${s.inq} and drawing_file_path is not null
       union select unnest(drawing_redacted_paths) from public.inquiries where ${s.inq}
       union select source_path from public.drawing_redaction_runs where ${s.redaction} and source_path is not null
       union select unnest(output_paths) from public.drawing_redaction_runs where ${s.redaction}`,
  },
  {
    // 15 Sep 2026: the quotation conversation stores each file the supplier attaches under
    // quote-files/review/..., named on quote_reviews and on its messages' attachments.
    bucket: 'quote-files', sql:
      `select original_file_path p from public.quotes where ${s.quote} and original_file_path is not null
       union select r.original_file_path from public.quote_reviews r
        where (r.inquiry_id in (select id from public.inquiries where ${s.inq}) or r.supplier_id in (select id from public.leads where ${s.lead}))
          and r.original_file_path is not null
       union select a->>'path' from public.quote_review_messages m join public.quote_reviews r on r.id = m.review_id
        cross join jsonb_array_elements(coalesce(m.attachments, '[]'::jsonb)) a
        where (r.inquiry_id in (select id from public.inquiries where ${s.inq}) or r.supplier_id in (select id from public.leads where ${s.lead}))
          and a->>'bucket' = 'quote-files' and a->>'path' is not null`,
  },
  {
    bucket: 'signed-terms', sql:
      `select signed_terms_path p from public.customers where ${s.cust} and signed_terms_path is not null
       union select signed_terms_path from public.leads where ${s.lead} and signed_terms_path is not null`,
  },
  {
    // supplier-docs had NO teardown rule until 5 Aug 2026, and nothing noticed because the bucket
    // held 0 objects: every licence fixture to date wrote a FAKE license_doc_path and never put
    // bytes anywhere. The first run of supplier_api process_docs against real storage would have
    // leaked every licence, profile and catalogue it stored - the same class as the 118
    // signed-terms objects in §2.2, caught this time before it accumulated rather than after.
    //
    // Two path shapes exist and both are swept. process_docs writes a bucket-relative path
    // (`licenses/<lead>/<ts>_<name>.pdf`), while makeLicenceGatedSupplier and
    // verify_exception_window write a bucket-PREFIXED one (`supplier-docs/demo/<tag>/licence.pdf`)
    // for a row that names an object that was never uploaded. Stripping the prefix makes one rule
    // cover both; deleting an object that does not exist is a no-op.
    bucket: 'supplier-docs', sql:
      `select regexp_replace(license_doc_path, '^supplier-docs/', '') p from public.leads
        where ${s.lead} and license_doc_path is not null
       union select regexp_replace(company_profile_doc_path, '^supplier-docs/', '') from public.leads
        where ${s.lead} and company_profile_doc_path is not null
       union select regexp_replace(unnest(coalesce(catalog_doc_paths, '{}'::text[])), '^supplier-docs/', '')
         from public.leads where ${s.lead}
       -- supplier_catalog_ingest stores catalog/<lead>/<ts>-<name> and names it only on its catalogue row (19 Oct 2026, S20).
       union select c.source_document_path from public.supplier_catalog c
        where c.source_document_path is not null and c.supplier_id in (select id from public.leads where ${s.lead})`,
  },
  {
    // The comparison PDF is the one output whose path NOTHING records: comparison_run_v2 has no
    // path column and the signed URL is only ever returned to the caller. It is derivable from the
    // filename convention instead - QD-<first 8 of the inquiry id, uppercased>-CMP.pdf - which is
    // how 20 of them accumulated in agent-docs without appearing on anybody's cleanup list.
    bucket: 'agent-docs', sql:
      `select o.name p from storage.objects o
        where o.bucket_id = 'agent-docs'
          and exists (select 1 from public.inquiries i
                       where ${s.inq}
                         and o.name like '%QD-' || upper(left(i.id::text, 8)) || '-CMP%')`,
  },
];

/**
 * Put a real object in a real bucket. Teardown finds it again through whichever row names it
 * (`inquiries.drawing_file_path`, `documents.path`, …), so callers must attach the returned path to
 * something - an orphan object is exactly the litter this module exists to stop.
 */
export async function uploadObject(bucket, path, bytes, mime = 'application/octet-stream') {
  const { SERVICE } = await keys();
  const r = await fetch(`${BASE}/storage/v1/object/${bucket}/${path}`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': mime, 'x-upsert': 'true' },
    body: bytes,
  });
  if (!r.ok) throw new Error(`upload to ${bucket}/${path} failed: HTTP ${r.status} ${(await r.text()).slice(0, 200)}`);
  return path;
}

async function deleteObjects(bucket, paths) {
  const clean = [...new Set(paths.filter(Boolean))];
  if (!clean.length) return 0;
  const { SERVICE } = await keys();
  let n = 0;
  for (let i = 0; i < clean.length; i += 100) {
    const chunk = clean.slice(i, i + 100);
    const r = await fetch(`${BASE}/storage/v1/object/${bucket}`, {
      method: 'DELETE',
      headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefixes: chunk }),
    });
    if (r.ok) n += chunk.length;
  }
  return n;
}

// A step may carry its own CTE (the leads step deletes inbound_messages in the same statement, so no new
// message can land between the two). Postgres refuses a data-modifying WITH nested inside another, so that
// step's CTEs are lifted to the top level beside `d` (19 Oct 2026: every teardown since #1496 stopped at
// 'leads' with 0A000 and left the run's leads, auth users and files behind).
export const countedDelete = (sql) => {
  const m = String(sql).match(/^\s*with\s+([\s\S]*\))\s+(delete\s[\s\S]*)$/i);
  return m ? `with ${m[1]}, d as (${m[2]} returning 1) select count(*)::int n from d`
           : `with d as (${sql} returning 1) select count(*)::int n from d`;
};
const delCount = async (label, sql) => {
  const rows = await mgmtFixture(REF, countedDelete(sql), label);
  return Number(rows?.[0]?.n ?? 0);
};

/**
 * Delete everything this run created, in foreign-key order, including the storage objects and the
 * auth users. Safe to call twice.
 */
/** [table, column] of every single-column foreign key in public that references public.<parent>(id). */
async function fkChildren(parent) {
  return (await mgmtRead(REF, `select c.conrelid::regclass::text t, a.attname col
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = ${q('public.' + parent)}::regclass and cardinality(c.conkey) = 1
       and c.conrelid::regclass::text <> ${q(parent)} order by 1`)).map((r) => [String(r.t).replace(/^public\./, ''), r.col]);
}

export async function teardown(run) {
  const tag = run.tag;
  const s = scopeForRun(tag);
  const { CUST, LEAD, INQ, QUO, INQ_T, QUO_T, LEAD_T } = scopeSql(s);
  const DOCS_W = `((ref_table='inquiries' and ref_id in ${INQ_T})` +
                 ` or (ref_table='quotes' and ref_id in ${QUO_T})` +
                 ` or (ref_table='leads' and ref_id in ${LEAD_T}))`;

  // 1. storage first, while the rows that name the objects still exist
  const objs = {};
  for (const src of BUCKET_SOURCES(s)) {
    const rows = await mgmtRead(REF, src.sql);
    objs[src.bucket] = await deleteObjects(src.bucket, rows.map((r) => r.p));
  }
  // documents rows name their own bucket, so they are their own source of truth
  const docRows = await mgmtRead(REF, `select bucket, path from public.documents where ${DOCS_W}`);
  for (const b of new Set(docRows.map((r) => r.bucket))) {
    objs[b] = (objs[b] || 0) + await deleteObjects(b, docRows.filter((r) => r.bucket === b).map((r) => r.path));
  }

  // 2. rows, children before parents. Everything below is one statement per table so a failure
  //    names the table it failed on instead of collapsing into one opaque constraint error.
  const counts = {};
  // THE RUN'S MONEY GOES BEFORE THE PEOPLE IT NAMES (15 Sep 2026). supplier_dues has no foreign key to its
  // supplier or transaction, and no step here touched it, so an e2e clawback due outlived the lead and the
  // transaction it named. The first booking tick after the bank-booking hold lifted posted that orphan
  // (supplier_dues #272) into the real ledger as journal #690. Every money row a run can create is removed
  // here while the transaction, lead and customer rows that scope it still exist.
  const TX = `(select id from public.transactions where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD})`;
  const DUES_W = `(transaction_id in ${TX} or supplier_id in ${LEAD} or quote_id in ${QUO})`;
  // A run's due that already reached the ledger must not be deleted from under its journal: stop and say so.
  // fn_gl_sync_business refuses fixture dues, so this should never fire.
  const booked = await mgmtRead(REF, `select d.id from public.supplier_dues d where ${DUES_W} and exists (select 1 from public.gl_journal g
      where g.source in ('commission_accrue','commission_collect') and g.source_ref = d.id::text and g.status in ('draft','posted'))`);
  if (booked.length) throw new Error(`teardown refused: supplier_dues ${booked.map((r) => r.id).join(', ')} of run ${tag} are in the ledger; the accountant reverses them first (fn_gl_reverse)`);
  const steps = [
    ['accountant_issued_document', `delete from public.accountant_issued_document where due_id in (select id from public.supplier_dues where ${DUES_W})`],
    // A dues checkout (supplier_pay) points at its dues; it goes first or the dues delete fails on its FK (19 Oct 2026).
    ['supplier_due_checkouts', `delete from public.supplier_due_checkouts where due_id in (select id from public.supplier_dues where ${DUES_W})`],
    ['supplier_dues', `delete from public.supplier_dues where ${DUES_W}`],
    ...['charge_audit', 'reveal_invoices', 'stripe_dispute', 'supplier_response_watch'].map((t) => [t,
      `delete from public.${t} where transaction_id in ${TX}`]),
    // trg_event_transaction emits payment.received keyed on the transaction id (as TEXT), so it must go
    // before the transaction row it names — the same ordering rule as the quote/inquiry/lead log rows.
    // THE REFUND LOOP'S ROWS (14 Sep 2026). A demo customer's refund request opens a refunds case, and
    // the CEO's loop writes beside it. None of these cascade from the transaction, and refunds is
    // ON DELETE SET NULL, so without these steps a run's refund case would outlive it as an orphan.
    // refund_status_transition carries no transaction, refund or quote column, so it cannot be scoped
    // to a run and is left alone on purpose.
    ...['refund_case', 'refund_ceo_check', 'refund_ceo_review', 'refund_incident', 'refund_ladder_evidence'].map((t) => [t,
      `delete from public.${t} where transaction_id in (select id from public.transactions where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD})
          or refund_id in (select id from public.refunds where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST})`]),
    // trg_emit_refund_requested puts the case on the bus keyed on the refund id (entity_type 'refund').
    ['company_event (refund)', `delete from public.company_event where entity_type='refund' and entity_id in (select id::text from public.refunds where transaction_id in (select id from public.transactions where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD}) or quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST})`],
    ['refunds', `delete from public.refunds where transaction_id in (select id from public.transactions where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD}) or quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST}`],
    // The accountant's reveal-invoice handoff to the sales engineer targets the transaction (14 Sep 2026).
    ['agent_actions (transaction)', `delete from public.agent_actions where target_table='transactions' and target_id in (select id::text from public.transactions where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD})`],
    ['company_event (transaction)',`delete from public.company_event where entity_type='transaction' and entity_id in (select id::text from public.transactions where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD})`],
    // A review references its transaction (reviews_transaction_id_fkey, no cascade). Journey h rates
    // the revealed supplier, and on 21 Sep 2026 its first run stopped teardown here with 23503.
    ['reviews', `delete from public.reviews where transaction_id in ${TX} or customer_id in ${CUST} or supplier_id in ${LEAD}`],
    ['transactions', `delete from public.transactions where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD}`],
    // notifications names all three parents (inquiry_id, lead_id, quote_id) and has no children of
    // its own, so it goes first - after the quote is deleted the quote_id clause matches nothing.
    ['notifications', `delete from public.notifications where inquiry_id in ${INQ} or lead_id in ${LEAD} or quote_id in ${QUO} or to_email like 'qd-${tag}-%@example.%'`],
    ['comparison_candidate_v2', `delete from public.comparison_candidate_v2 where quote_id in ${QUO}`],
    ['comparison_run_v2', `delete from public.comparison_run_v2 where inquiry_id in ${INQ}`],
    // doc_versions, documents, company_event and agent_actions key off the quote/inquiry/lead id as
    // TEXT, so they must go before the row they name: once the quote is deleted the subquery finds
    // nothing and the log row survives as litter. That ordering mistake is exactly what left 452
    // doc_versions and 186 company_event rows in staging.
    //
    // agent_actions carries three such branches and only ONE of them used to be reachable. The step
    // sat below both 'quotes' and 'inquiries', so those two branches matched an already-empty
    // subquery every time; only 'leads' fired, because leads are deleted one step later - which is
    // why an exception-window run looked like it swept correctly. route_inquiry writes a
    // 'coverage_gap' row against 'inquiries' whenever a dispatch finds no capable supplier, and
    // journey_test produces one on every run because it creates the inquiry before the supplier
    // exists. 14 dangling rows had accumulated by 6 Aug 2026, one per run, while teardown reported
    // success and the baseline counter check stayed green - the factory's own selftest never
    // dispatches into an empty corpus, so it never generates the row it fails to clean up.
    ['agent_actions', `delete from public.agent_actions where (target_table='leads' and target_id in ${LEAD_T}) or (target_table='inquiries' and target_id in ${INQ_T}) or (target_table='quotes' and target_id in ${QUO_T})`],
    ['doc_versions', `delete from public.doc_versions where entity_type='quote' and entity_id in ${QUO_T}`],
    ['doc_versions (rfq)', `delete from public.doc_versions where entity_type='rfq' and entity_id in ${INQ_T}`],
    // quote_items keys off quote_id as TEXT, so like its neighbours above it must go BEFORE the
    // quotes row it names. It was never swept at all: measured 6 Aug 2026, staging held 109 rows
    // across 109 distinct quote_ids against 0 surviving quotes — every one an orphan, the oldest
    // from 5 Aug and the newest written during that morning's own gate run. The baseline counter
    // could not catch it because quote_items was not in EXACT_TABLES either, which is the same
    // pair of holes that let agent_actions leak for two sessions.
    ['quote_items', `delete from public.quote_items where quote_id::text in ${QUO_T}`],
    ['documents', `delete from public.documents where ${DOCS_W}`],
    ['company_event (quote)', `delete from public.company_event where entity_type='quote' and entity_id in ${QUO_T}`],
    ['quotes', `delete from public.quotes where id in ${QUO}`],
    // The quotation conversation (15 Sep 2026) references its inquiry and its supplier with no cascade —
    // a real conversation is never deleted with its parent — so a run's conversation goes first, children
    // before the review.
    ['quote_review_request', `delete from public.quote_review_request where review_id in (select id from public.quote_reviews where inquiry_id in ${INQ} or supplier_id in ${LEAD})`],
    ['quote_review_messages', `delete from public.quote_review_messages where review_id in (select id from public.quote_reviews where inquiry_id in ${INQ} or supplier_id in ${LEAD})`],
    ['quote_reviews', `delete from public.quote_reviews where inquiry_id in ${INQ} or supplier_id in ${LEAD}`],
    ['supplier_opportunity_score', `delete from public.supplier_opportunity_score where inquiry_id in ${INQ} or supplier_id in ${LEAD}`],
    ['reviews', `delete from public.reviews where inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD}`],
    ['inquiry_matches', `delete from public.inquiry_matches where inquiry_id in ${INQ} or supplier_id in ${LEAD}`],
    ['company_event (lead)', `delete from public.company_event where entity_type='lead' and entity_id in ${LEAD_T}`],
    ['company_event (inquiry)', `delete from public.company_event where entity_type='inquiry' and entity_id in ${INQ_T}`],
    ['inquiry_supplier_brief', `delete from public.inquiry_supplier_brief where inquiry_id in ${INQ}`],
    ['inquiries_unhire', `update public.inquiries set hired_supplier_id=null where hired_supplier_id in ${LEAD}`],
    ['inquiries', `delete from public.inquiries where id in ${INQ}`],
    ['doc_reviews', `delete from public.doc_reviews where lead_id in ${LEAD}`],
    ['inbound_messages', `delete from public.inbound_messages where lead_id in ${LEAD}`],
    // supplier_product.catalog_id references supplier_catalog: products first (23503 on 19 Oct 2026, S20).
    ['supplier_product', `delete from public.supplier_product where supplier_id in ${LEAD}`],
    // sanitizeAndScan records each supplier upload in file_scan keyed by the lead id as text.
    ['file_scan', `delete from public.file_scan where source = 'supplier_catalog_ingest' and subject in ${LEAD_T}`],
    ['supplier_catalog', `delete from public.supplier_catalog where supplier_id in ${LEAD}`],
    ['supplier_capability_confirmation', `delete from public.supplier_capability_confirmation where supplier_id in ${LEAD}`],
    // EVERY OTHER TABLE THAT POINTS AT leads (12 Oct 2026, stage2 run 1c94fa6a: licence_renewal_ask, added that day,
    // refused the leads delete and stranded the run). Found from the catalogue at teardown time, so a table added
    // tomorrow is covered too; only rows of THIS run's own lead ids are removed.
    ...(await fkChildren('leads')).map(([t, c]) => [`${t} (fk ${c} -> leads)`, `delete from public.${t} where ${c} in ${LEAD}`]),
    // A LATE inbound message (19 Oct 2026, platform-on simulation: the stale-run sweep failed 23503 on
    // inbound_messages_lead_id_fkey) can land between the inbound_messages step above and this one. It is
    // taken in the same statement as the lead, so no gap is left for it.
    ['leads', `with im as (delete from public.inbound_messages where lead_id in ${LEAD}) delete from public.leads where id in ${LEAD}`],
    ['drawing_redaction_runs', `delete from public.drawing_redaction_runs where customer_id in ${CUST} or owner_email like 'qd-${tag}-%@example.%'`],
    ['customer_preference', `delete from public.customer_preference where customer_id in ${CUST}`],
    ['customer_organization', `delete from public.customer_organization where owner_customer_id in ${CUST}`],
    ['company_event (customer)', `delete from public.company_event where entity_type='customer' and entity_id in (select id::text from public.customers where id in ${CUST})`],
    // support_customer_profile is NOT taken by customer id here (review of #1464): stage2's marker sweep removes the run's
    // profiles (and their cases first) by the run's own markers only.
    ...(await fkChildren('customers')).filter(([t]) => t !== 'support_customer_profile').map(([t, c]) => [`${t} (fk ${c} -> customers)`, `delete from public.${t} where ${c} in ${CUST}`]),
    ['customers', `delete from public.customers where id in ${CUST}`],
    ['inquiry_intake', `delete from public.inquiry_intake where email like 'qd-${tag}-%@example.%'`],
    ['email_verifications', `delete from public.email_verifications where email like 'qd-${tag}-%@example.%'`],
  ];
  // A TABLE THAT WAS DROPPED MUST NOT STRAND EVERYTHING AFTER IT (14 Sep 2026). The first e2e harness
  // run died at 'comparison_candidate_v2' (42P01, the table no longer exists) and every later step -
  // quotes, inquiries, leads, customers, auth users - never ran, so the run's rows survived its own
  // teardown. A missing relation is skipped and named; any other error still stops the teardown.
  for (const [label, sql] of steps) {
    try {
      const n = await delCount(`teardown ${label}`, sql);
      if (n) counts[label] = n;
    } catch (e) {
      // A discovered-FK child that is itself still referenced (support_customer_profile <- support_case) is left for
      // the caller's sweep and NAMED; the parent delete after it then fails loudly if anything really remains.
      if (/\(fk /.test(label) && /23503/.test(String(e.message))) { counts[`${label} (deferred: still referenced)`] = 0; continue; }
      if (!/42P01|does not exist/.test(String(e.message))) throw e;
      counts[`${label} (table no longer exists)`] = 0;
    }
  }

  // 3. auth users last: the email pattern is the only handle on them once the rows are gone
  const users = await deleteAuthUsersByTag(tag);
  if (users) counts.auth_users = users;
  const objTotal = Object.values(objs).reduce((a, b) => a + b, 0);
  if (objTotal) counts.storage_objects = objTotal;

  const summary = Object.keys(counts).length
    ? Object.entries(counts).map(([k, v]) => `${k} ${v}`).join(', ')
    : 'nothing to remove';
  return { counts, objects: objs, summary };
}

// ---- purge -----------------------------------------------------------------------------------
// Teardown handles a run this process created. Purge handles DRIFT: what previous runs left behind
// before the tag existed, and what a mid-run throw leaks. The rules are deliberately about
// synthetic markers and orphanhood, not "delete everything in staging".
//
// The bucket allowlist is explicit and MUST NOT contain 'brand'. brand holds the fonts
// sync_staging_assets copies from production, and Phase 1's "15/15 storage buckets" was true and
// useless precisely because it counted buckets and not objects: an empty brand bucket made
// pdf_native fall back to WinAnsi Helvetica, which throws on any character above U+00FF, and one
// '≠' from a model 502'd a customer's comparison PDF.
export const PURGE_BUCKETS = ['drawing-files', 'quote-files', 'signed-terms', 'agent-docs', 'supplier-docs'];
export const PROTECTED_BUCKETS = ['brand', 'site', 'demo-assets', 'social-media', 'kb-import-assets', 'backups'];

const P_CUST = `(select id from public.customers where email like 'qd-%@example.%' or email is null or id not in (select id from auth.users))`;
const P_LEAD = `(select id from public.leads where 'qd_demo' = any(coalesce(tags,'{}'::text[])) or company_name like 'Journey Test %' or company_name like 'QD Demo %' or source='demo_factory' or claimed_by like 'qd-%@example.%')`;
const P_INQ = `(select id from public.inquiries where customer_id in ${P_CUST} or customer_id is null or provenance->>'qd_run' is not null)`;
const P_QUO = `(select id from public.quotes where inquiry_id in ${P_INQ} or supplier_id in ${P_LEAD})`;

export async function purge(opts = {}) {
  const dry = !!opts.dryRun;
  const log = opts.quiet ? () => {} : console.log;
  for (const b of PURGE_BUCKETS) {
    if (PROTECTED_BUCKETS.includes(b)) throw new Error(`refusing to purge protected bucket ${b}`);
  }

  const brandBefore = Number((await mgmtRead(REF,
    "select count(*)::int n from storage.objects where bucket_id='brand'"))[0].n);

  const steps = [
    // children -> parents, then the orphan sweeps that only make sense once the parents are gone
    ['reviews', `delete from public.reviews where transaction_id in (select id from public.transactions where quote_id in ${P_QUO} or inquiry_id in ${P_INQ} or customer_id in ${P_CUST} or supplier_id in ${P_LEAD}) or customer_id in ${P_CUST} or supplier_id in ${P_LEAD}`],
    ['transactions', `delete from public.transactions where quote_id in ${P_QUO} or inquiry_id in ${P_INQ} or customer_id in ${P_CUST} or supplier_id in ${P_LEAD}`],
    ['comparison_candidate_v2', `delete from public.comparison_candidate_v2 where quote_id in ${P_QUO}`],
    ['comparison_run_v2', `delete from public.comparison_run_v2 where inquiry_id in ${P_INQ}`],
    ['doc_versions (quote)', `delete from public.doc_versions where entity_type='quote' and entity_id not in (select id::text from public.quotes)`],
    ['quotes', `delete from public.quotes where id in ${P_QUO}`],
    ['supplier_opportunity_score', `delete from public.supplier_opportunity_score where inquiry_id in ${P_INQ} or supplier_id in ${P_LEAD}`],
    ['reviews', `delete from public.reviews where inquiry_id in ${P_INQ} or customer_id in ${P_CUST} or supplier_id in ${P_LEAD}`],
    ['inquiry_matches', `delete from public.inquiry_matches where inquiry_id in ${P_INQ} or supplier_id in ${P_LEAD}`],
    ['inquiries (unhire)', `update public.inquiries set hired_supplier_id=null where hired_supplier_id in ${P_LEAD}`],
    ['inquiries', `delete from public.inquiries where id in ${P_INQ}`],
    ['doc_reviews', `delete from public.doc_reviews where lead_id in ${P_LEAD}`],
    ['inbound_messages', `delete from public.inbound_messages where lead_id in ${P_LEAD}`],
    ['supplier_product', `delete from public.supplier_product where supplier_id in ${P_LEAD}`],
    ['supplier_catalog', `delete from public.supplier_catalog where supplier_id in ${P_LEAD}`],
    ['supplier_capability_confirmation', `delete from public.supplier_capability_confirmation where supplier_id in ${P_LEAD} or supplier_id not in (select id from public.leads)`],
    ['leads', `with im as (delete from public.inbound_messages where lead_id in ${P_LEAD}) delete from public.leads where id in ${P_LEAD}`],
    ['drawing_redaction_runs', `delete from public.drawing_redaction_runs where customer_id is null or customer_id not in (select id from public.customers) or owner_email like 'qd-%@example.%'`],
    ['customer_preference', `delete from public.customer_preference where customer_id in ${P_CUST}`],
    ['customer_organization', `delete from public.customer_organization where owner_customer_id in ${P_CUST}`],
    ['customers', `delete from public.customers where id in ${P_CUST}`],
    ['inquiry_intake', `delete from public.inquiry_intake where email like 'qd-%@example.%' or customer_id is null or customer_id not in (select id from public.customers)`],
    ['email_verifications', `delete from public.email_verifications where email like 'qd-%@example.%'`],
    // orphan sweeps: run last, when "dangling" finally means what it says
    ['documents (dangling)', `delete from public.documents where (ref_table='inquiries' and ref_id not in (select id::text from public.inquiries)) or (ref_table='quotes' and ref_id not in (select id::text from public.quotes)) or (ref_table='leads' and ref_id not in (select id::text from public.leads))`],
    // notifications is a QUEUE, not a log. 66 'supplier_registered' rows addressed to
    // management@quotesdone.com survived the first purge because they carry a lead_id and no
    // inquiry_id - every one of them for a supplier that no longer exists. email_enabled is false
    // on staging today, so they sat there harmlessly; the moment it is turned on behind a
    // recipient allowlist to prove notification, they would all fire at once.
    ['notifications (dangling)', `delete from public.notifications where to_email like 'qd-%@example.%' or (inquiry_id is not null and inquiry_id not in (select id from public.inquiries)) or (lead_id is not null and lead_id not in (select id from public.leads)) or (quote_id is not null and quote_id not in (select id from public.quotes))`],
    ['company_event (dangling)', `delete from public.company_event where (entity_type in ('inquiry','quote') and entity_id not in (select id::text from public.inquiries union all select id::text from public.quotes)) or (entity_type='lead' and entity_id not in (select id::text from public.leads))`],
    ['inquiry_supplier_brief (dangling)', `delete from public.inquiry_supplier_brief where inquiry_id not in (select id from public.inquiries)`],
    ['agent_actions (dangling)', `delete from public.agent_actions where (target_table='leads' and target_id not in (select id::text from public.leads)) or (target_table='inquiries' and target_id not in (select id::text from public.inquiries)) or (target_table='quotes' and target_id not in (select id::text from public.quotes))`],
  ];

  const counts = {};
  if (dry) {
    // A dry run counts each rule against the CURRENT state, but the orphan sweeps at the end only
    // become true once their parents are gone - the real run deleted 26 dangling documents where
    // the dry run predicted 13, and 415 notifications where it predicted 382. The dry run is a
    // lower bound on what will go, never an upper one.
    for (const [label, sql] of steps) {
      const probe = sql.startsWith('update')
        ? sql.replace(/^update public\.(\w+) set .*? where /, 'select count(*)::int n from public.$1 where ')
        : sql.replace(/^delete from /, 'select count(*)::int n from ');
      const rows = await mgmtRead(REF, probe);
      const n = Number(rows?.[0]?.n ?? 0);
      if (n) counts[label] = n;
    }
  } else {
    for (const [label, sql] of steps) {
      const n = await delCount(`purge ${label}`, sql);
      if (n) counts[label] = n;
    }
  }

  // storage: every object in the four demo buckets. Staging holds no real uploads - the 118
  // signed-terms PDFs and 19 comparison PDFs are all previous runs' litter.
  const objs = {};
  for (const bucket of PURGE_BUCKETS) {
    const rows = await mgmtRead(REF,
      `select name from storage.objects where bucket_id=${q(bucket)} order by name`);
    objs[bucket] = dry ? rows.length : await deleteObjects(bucket, rows.map((r) => r.name));
  }

  let users = 0;
  const orphanRows = await mgmtRead(REF, `select id from auth.users where email like 'qd-%@example.%'`);
  if (dry) users = orphanRows.length;
  else {
    const { SERVICE } = await keys();
    for (const r of orphanRows) {
      const d = await fetch(`${BASE}/auth/v1/admin/users/${r.id}`, {
        method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
      });
      if (d.ok) users++;
    }
  }

  const brandAfter = Number((await mgmtRead(REF,
    "select count(*)::int n from storage.objects where bucket_id='brand'"))[0].n);
  if (brandAfter !== brandBefore) {
    throw new Error(`purge touched the brand bucket: ${brandBefore} -> ${brandAfter}. ` +
      'brand holds the fonts pdf_native needs; restore with sync_staging_assets.mjs.');
  }

  log(`\n${dry ? 'PURGE (dry run) would remove AT LEAST' : 'PURGED'}:`);
  for (const [k, v] of Object.entries(counts)) log(`  ${String(v).padStart(6)}  ${k}`);
  for (const [k, v] of Object.entries(objs)) if (v) log(`  ${String(v).padStart(6)}  storage/${k}`);
  if (users) log(`  ${String(users).padStart(6)}  auth users (qd-%@example.*)`);
  log(`  brand bucket preserved at ${brandAfter} object(s)`);
  return { counts, objects: objs, authUsers: users, dry };
}

// ---- baseline diff ---------------------------------------------------------------------------
/**
 * Count every non-empty public table plus the storage buckets. The selftest takes this before and
 * after a run and asserts they match: it is the only check that catches a table a trigger wrote
 * that nobody remembered to tear down. company_event, doc_versions and notifications were all
 * found this way.
 */
export const EXACT_TABLES = ['customers', 'leads', 'inquiries', 'quotes', 'supplier_capabilities',
  'supplier_capability_confirmation',
  'inquiry_matches', 'inquiry_intake', 'inquiry_requirement', 'inquiry_supplier_brief',
  'email_verifications', 'drawing_redaction_runs', 'documents', 'transactions', 'notifications',
  'company_event', 'doc_versions', 'comparison_run_v2', 'comparison_candidate_v2',
  // quote_items: 109 orphans had accumulated by 6 Aug 2026 with 0 quotes alive. A counter only
  // catches what something wrote, and this counter did not exist while the teardown rule did not
  // either — so the selftest read 18/18 through every leaking run.
  'quote_items',
  // Added after an exception-window run left a dangling row here: the baseline check can only catch
  // what it counts, and this table was not on the list.
  'agent_actions'];

export async function snapshot() {
  // Only tables that exist. comparison_candidate_v2 is gone from production (to_regclass null on
  // 15 Sep 2026) and one missing name failed the whole snapshot with 42P01, so the selftest could not
  // run at all. A dropped table has nothing left to leak; every table that exists is still counted.
  const present = (await mgmtRead(REF,
    `select t from unnest(${arr(EXACT_TABLES)}) t where to_regclass('public.' || t) is not null`)).map((r) => r.t);
  const exact = await mgmtRead(REF, present.map((t) =>
    `select ${q(t)} as t, count(*)::bigint n from public.${t}`).join(' union all '));
  const rest = await mgmtRead(REF,
    `select 'storage:'||bucket_id as t, count(*)::bigint n from storage.objects group by bucket_id
     union all select 'auth.users', count(*)::bigint from auth.users`);
  const m = {};
  for (const r of [...exact, ...rest]) m[r.t] = Number(r.n);
  return m;
}

export function diffSnapshots(before, after) {
  const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])].sort();
  return keys.map((k) => ({ t: k, before: before[k] ?? 0, after: after[k] ?? 0 }))
             .filter((r) => r.before !== r.after);
}

// ---- CLI -------------------------------------------------------------------------------------
const isMain = !!process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('/demo_factory.mjs');

if (isMain) {
  const argv = process.argv.slice(2);
  const has = (f) => argv.includes(f);
  const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

  if (has('--purge')) {
    await purge({ dryRun: has('--dry-run') });
  } else if (has('--corpus')) {
    const n = Number(val('--corpus', '100'));
    const perTrade = Math.max(1, Math.round(n / TRADE_CODES.length));
    await withRun(async (run) => {
      const c = await makeBulkCorpus(run, { perTrade, customers: Number(val('--customers', '0')) });
      console.log(`corpus tag=${run.tag} suppliers=${c.suppliers.length}`);
    }, { keep: has('--keep') });
  } else {
    // --selftest (default): the factory proving itself against the rule it exists to enforce.
    await selftest();
  }
}

export async function selftest() {
  const checks = [];
  const ok = (name, pass, detail) => {
    checks.push({ name, pass, detail });
    console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(46)} ${detail}`);
  };

  const before = await snapshot();
  let out = null;
  try {
    out = await withRun(async (run) => {
      const cust = await makeCustomer(run, { mode: 'sql', locale: 'ar', full_name: 'عميل تجريبي' });
      ok('makeCustomer returns a usable identity', !!cust.id && !!cust.jwt && !!cust.email,
        `id=${cust.id ? 'yes' : 'NO'} jwt=${cust.jwt ? 'yes' : 'NO'} ${cust.email}`);

      const me = await call('customer_api', cust.jwt, { action: 'me' });
      ok('the made customer can act as itself', me.status === 200 && me.json?.customer?.id === cust.id,
        `HTTP ${me.status} me.id matches=${me.json?.customer?.id === cust.id}`);

      const supA = await makeSupplier(run, { trade: 'aluminium', variant: 0, variants: 4 });
      const supB = await makeSupplier(run, { trade: 'aluminium', variant: 3, variants: 4 });
      ok('makeSupplier returns id, email and JWT', !!supA.leadId && !!supA.email && !!supA.jwt,
        `lead=${supA.leadId} jwt=${supA.jwt ? 'yes' : 'NO'} ${supA.companyName}`);

      const supMe = await call('supplier_api', supA.jwt, { action: 'me' });
      ok('the made supplier can act as itself',
        supMe.status === 200 && Number(supMe.json?.supplier?.id) === Number(supA.leadId),
        `HTTP ${supMe.status} approval=${supMe.json?.supplier?.approval_status ?? '-'}`);

      // The variety claim, measured through the real function rather than asserted in a comment.
      // p_value is supplied on purpose: w_size scores 10 when the supplier states a range that
      // contains the job and 5 when it does not, so omitting p_value makes size_known false for
      // EVERY candidate and quietly shifts the whole ladder down by 5.
      const products = TRADES.aluminium.products;
      const scores = await mgmtRead(REF,
        `select supplier_id, score, product_hits from public.fn_match_capability(
           ARRAY['aluminium']::text[], 'executes', ${arr(products)}, '{}'::text[], null, 150000, null, 50)
         where supplier_id in (${supA.leadId}, ${supB.leadId}) order by score desc`);
      const sA = scores.find((r) => Number(r.supplier_id) === Number(supA.leadId));
      const sB = scores.find((r) => Number(r.supplier_id) === Number(supB.leadId));
      ok('capability variants score differently (not a tie)',
        !!sA && !!sB && Number(sA.score) > Number(sB.score),
        `variant0=${sA?.score ?? 'absent'} (${sA?.product_hits ?? '-'}/${products.length} products), ` +
        `decoy=${sB?.score ?? 'absent'} (${sB?.product_hits ?? '-'}/${products.length})`);
      ok('the zero-overlap decoy sits on the 5-point floor',
        !!sB && Number(sB.score) === 5 && Number(sB.product_hits) === 0,
        `score=${sB?.score ?? 'absent'} hits=${sB?.product_hits ?? '-'} (w_size*0.5 with min/max null)`);

      const inq = await makeInquiry(run, { customer: cust, trade: 'aluminium', status: 'sent' });
      ok('makeInquiry writes a tagged inquiry', !!inq.id, `id=${inq.id}`);
      const tagged = (await mgmtRead(REF,
        `select provenance->>'qd_run' t from public.inquiries where id=${q(inq.id)}`))[0]?.t;
      ok('every row carries the run tag', tagged === run.tag, `provenance.qd_run=${tagged}`);

      // rfq_ready is computed by trg_rfq_complete and cannot be set by hand. An inquiry that is not
      // ready cannot be dispatched, and dispatch_inquiry reports that as {"ok":true,
      // "skip":"not_rfq_ready"} - a 200 that contacted nobody.
      const ready = (await mgmtRead(REF,
        `select rfq_ready, completeness->>'score' score,
                completeness->'category_check'->>'required_total' req
           from public.inquiries where id=${q(inq.id)}`))[0] || {};
      ok('the inquiry satisfies the category checklist and is dispatchable',
        ready.rfq_ready === true,
        `rfq_ready=${ready.rfq_ready} score=${ready.score}/70 ` +
        `category_specs required fields answered=${ready.req}`);

      const qa = await makeQuote(run, { inquiry: inq, supplier: supA, amount: 125000 });
      const qb = await makeQuote(run, { inquiry: inq, supplier: supB, amount: 131750 });
      ok('makeQuote writes comparable quotes', !!qa.id && !!qb.id && qa.amount !== qb.amount,
        `${qa.amount} vs ${qb.amount}, status=${qa.status}`);

      const corpus = await makeBulkCorpus(run, { trades: ['hvac', 'glazing'], perTrade: 4 });
      ok('makeBulkCorpus builds a trade-spread corpus with zero model calls',
        corpus.suppliers.length === 8,
        `${corpus.suppliers.length} supplier(s) across ${corpus.trades.length} trade(s), 2 round trips`);

      // Since #698 an approval is the database's decision. Both a claimed supplier (signed through its
      // e-mail's row) and an unclaimed corpus supplier (signed by lead id) must come out approved by the
      // sales engineer with nothing missing and all three files in storage.
      const six = await mgmtRead(REF, `
        select l.id, l.approval_status, l.approval_decided_by, l.claimed_by is null as unclaimed,
               to_jsonb(public.fn_supplier_mandatory_six(l)) as missing,
               exists (select 1 from storage.objects o where o.bucket_id = 'signed-terms' and o.name = l.signed_terms_path) as signed
          from public.leads l where l.id in (${num(supA.leadId)}, ${num(corpus.suppliers[0].leadId)})`);
      ok('made suppliers carry the six and the sales engineer approved them',
        six.length === 2 && six.some((r) => r.unclaimed) && six.every((r) => r.approval_status === 'approved'
          && r.approval_decided_by === 'sales_engineer' && Array.isArray(r.missing) && r.missing.length === 0 && r.signed),
        six.map((r) => `lead ${r.id}${r.unclaimed ? ' (unclaimed)' : ''}: ${r.approval_status} by ` +
          `${r.approval_decided_by} missing=${JSON.stringify(r.missing)} signed=${r.signed}`).join('; '));

      // Ahead of the capability_agent block on purpose: that function was deleted (182308b) and is not
      // deployed, so its checks fail and end the body; this fixture does not depend on it.
      const gated = await makeLicenceGatedSupplier(run, { trade: 'steel' });
      ok('the licence gate fixture actually opens the gate',
        gated.approval_status === 'action_required' && gated.licence_gate_reason === 'reg_licence',
        `approval_status=${gated.approval_status} reason=${gated.licence_gate_reason ?? 'none'}`);

      // The capability flow through the PRODUCT rather than a raw INSERT. Zero model calls: the
      // only model call in capability_agent is on the `analyze` path, which is separately blocked
      // by fn_ai_route routing supplier_matching to tier=none.
      const supAgent = await makeSupplier(run, { trade: 'hvac', capability: 'agent' });
      const confirmed = (await mgmtRead(REF, `
        select c.review_status, c.confirmed_version, c.trades, c.roles,
               c.min_project_value, c.max_project_value,
               (select count(*)::int from public.supplier_capability_confirmation f
                 where f.supplier_id = c.supplier_id) as ledger
          from public.supplier_capabilities c where c.supplier_id = ${supAgent.leadId}`))[0] || {};
      ok('capability_agent confirm writes the real record',
        confirmed.review_status === 'confirmed' && Number(confirmed.ledger) === 1
          && Array.isArray(confirmed.trades) && confirmed.trades.includes('hvac'),
        `review_status=${confirmed.review_status} version=${confirmed.confirmed_version} ` +
        `ledger_rows=${confirmed.ledger} trades=${(confirmed.trades || []).join('+')}`);

      // min/max_project_value are a HARD GATE in fn_match_capability's cand CTE, not a score term:
      // a job outside the range removes the supplier before scoring. The endpoint never wrote them,
      // so a supplier confirmed this way scored w_size*0.5 and ranked below an identical supplier
      // created by a raw INSERT. Asserted against the PROFILE so both creation paths must agree.
      ok('confirm persists the supplier-declared project-value range',
        Number(confirmed.min_project_value) === Number(supAgent.profile.min_project_value)
          && Number(confirmed.max_project_value) === Number(supAgent.profile.max_project_value),
        `row ${confirmed.min_project_value}..${confirmed.max_project_value} vs profile ` +
        `${supAgent.profile.min_project_value}..${supAgent.profile.max_project_value}`);

      // The negative case for the new trust boundary. An inverted range would silently make the
      // supplier unmatchable for every job, so it must be refused rather than stored.
      const badRange = await call('capability_agent', null, {
        __secret: await internalCred(), action: 'confirm', supplier_id: Number(supAgent.leadId),
        trades: ['hvac'], roles: ['contractor'], products: ['x', 'y'],
        min_project_value: 5000000, max_project_value: 1000,
      });
      const afterBad = (await mgmtRead(REF,
        `select min_project_value, max_project_value from public.supplier_capabilities
          where supplier_id = ${supAgent.leadId}`))[0] || {};
      ok('confirm refuses an inverted project-value range and leaves the stored range intact',
        badRange.status === 400 && badRange.json?.error === 'invalid_project_value_range'
          && Number(afterBad.min_project_value) === Number(supAgent.profile.min_project_value),
        `HTTP ${badRange.status} ${badRange.json?.error || ''}; stored range still ` +
        `${afterBad.min_project_value}..${afterBad.max_project_value}`);

      // The vocabulary gate is the reason to prefer the endpoint over an INSERT: a raw INSERT will
      // happily store a trade code that fn_match_capability can never match.
      const junk = await call('capability_agent', null, {
        __secret: await internalCred(), action: 'confirm', supplier_id: Number(supAgent.leadId),
        trades: ['not_a_real_trade'], roles: ['contractor'], products: ['x'],
      });
      ok('confirm refuses codes outside the controlled vocabulary',
        junk.status === 400 && junk.json?.error === 'need_at_least_one_trade_and_role',
        `HTTP ${junk.status} ${junk.json?.error ?? junk.text}`);

      // agent_actions is counted by the baseline check but nothing here ever GENERATED one, so the
      // teardown rule for it went two sessions without being exercised - and two of its three
      // branches were dead, because the step ran after the quotes and inquiries it names had already
      // been deleted. A counter can only catch a row that something wrote. Write all three shapes:
      // 'leads' is what fn_supplier_exception_sweep records, 'inquiries' is the coverage_gap
      // route_inquiry writes when a dispatch finds no capable supplier, 'quotes' completes the set.
      const seeded = await mgmtFixture(REF, `with i as (
          insert into public.agent_actions (agent, kind, target_table, target_id) values
            ('operations_ai', 'coverage_gap',  'inquiries', ${q(String(inq.id))}),
            ('operations_ai', 'selftest_probe','quotes',    ${q(String(qa.id))}),
            ('operations_ai', 'selftest_probe','leads',     ${q(String(supA.leadId))})
          returning 1) select count(*)::int n from i`, 'selftest seed agent_actions');
      ok('the teardown rule for agent_actions is actually exercised',
        Number(seeded?.[0]?.n ?? 0) === 3,
        `${seeded?.[0]?.n ?? 0} telemetry row(s) written against this run's inquiry, quote and lead ` +
        `- the baseline check below is what proves teardown removes them`);

      return { tag: run.tag };
    });
  } catch (e) {
    ok('factory body completed', false, String(e.message).slice(0, 160));
  }

  // This check compares absolute counts, so it assumes nothing else is writing to staging while it
  // runs. Running it alongside journey_test.mjs will fail it on the journey's rows, not on a
  // teardown defect - read the named counters before believing the failure.
  const after = await snapshot();
  const drift = diffSnapshots(before, after);
  ok('teardown returned the database to its baseline', drift.length === 0,
    drift.length
      ? drift.map((d) => `${d.t} ${d.before}->${d.after}`).join(', ') + '  (another writer running?)'
      : `no drift in ${Object.keys(after).length} counters`);

  const pass = checks.filter((c) => c.pass).length;
  console.log(`\nDEMO FACTORY SELFTEST ${pass}/${checks.length} on ${REF}`);
  process.exitCode = pass === checks.length ? 0 : 1;
  return { pass, total: checks.length };
}
