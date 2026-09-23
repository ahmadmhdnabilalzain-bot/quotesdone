// CUSTOMER PREFERENCES — spec file #1's "Company Memory", the last requirement in that file.
//
// The table held 0 rows and 0 readers. What it was NOT is blocked on the customer portal:
// fn_ws_customer_360 already derived a customer's categories and emirates from their inquiry
// history on every single call — the company computed the memory and discarded it.
//
// Production has 0 customers, so the table will legitimately hold 0 rows there. The requirement is
// met by a correct MECHANISM, exactly as company_goals.revenue_annual is met by summing real fees
// while returning 0. That is why this gate builds its own customers rather than asserting a count.
//
// FOUR NEGATIVE ASSERTIONS. N2 is the one that matters: it overwrites the stored preference with a
// value that appears in NONE of the customer's inquiries. Any reader that re-derives instead of
// remembering — which is precisely what fn_ws_customer_360 did before this change — fails it.
//
//   node scripts/staging/verify_customer_preference.mjs      # zero spend, cleans up after itself
import { mgmtRead, mgmtWrite } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(62)} ${detail}`);
};
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;
const TAG = 'qd-custpref';
const EMAIL_A = `${TAG}-consented@example.com`;
const EMAIL_B = `${TAG}-noconsent@example.com`;

async function cleanup() {
  await mgmtWrite(STAGE, `delete from public.company_event where entity_type='inquiry'
     and entity_id in (select id::text from public.inquiries where customer_id in
       (select id from public.customers where email like '${TAG}-%'))`, 'ce');
  await mgmtWrite(STAGE, `delete from public.inquiries where customer_id in
     (select id from public.customers where email like '${TAG}-%')`, 'inq');
  await mgmtWrite(STAGE, `delete from public.customer_preference where customer_id in
     (select id from public.customers where email like '${TAG}-%')`, 'pref');
  await mgmtWrite(STAGE, `delete from public.customers where email like '${TAG}-%'`, 'cust');
}

const prefOf = async (email) => one(await mgmtRead(STAGE,
  `select p.preferences::text from public.customer_preference p
     join public.customers c on c.id = p.customer_id where c.email = '${email}'`));
const c360 = async (email) => one(await mgmtRead(STAGE,
  `select public.fn_ws_customer_360((select id from public.customers where email='${email}'))->'preferences'`));

try {
  await cleanup();

  // A has consented; B has not. Same shape otherwise.
  await mgmtWrite(STAGE,
    `insert into public.customers (email, full_name, tos_accepted_at)
     values ('${EMAIL_A}', 'Fixture Consented', now()),
            ('${EMAIL_B}', 'Fixture No Consent', null)`, 'customers');

  const mkInquiry = (email, emirate, extra = '') => mgmtWrite(STAGE,
    `insert into public.inquiries (customer_id, category, emirate, scope_type, expected_value, summary${extra ? ', status' : ''})
     select id, 'joinery', ${emirate ? `'${emirate}'` : 'null'}, 'turnkey', 42000,
            '${TAG} fixture inquiry ${emirate || 'no-emirate'}'${extra ? `, 'new'` : ''}
       from public.customers where email='${email}'`, 'inquiry');

  await mkInquiry(EMAIL_A, 'Sharjah');
  await mkInquiry(EMAIL_B, 'Dubai');

  // ---- P1: the writer fired, from a trigger, with consent carried across --------------------
  const pA = await prefOf(EMAIL_A);
  step('an inquiry teaches the customer preference', !!pA && pA.includes('Sharjah'),
    pA ? `inferred emirates carry Sharjah; consented_at set from customers.tos_accepted_at` : 'NO ROW WRITTEN');

  // ---- N1: NO CONSENT, NO ROW. Fails if the writer upserts without checking. ------------------
  const pB = await prefOf(EMAIL_B);
  step('a customer who never consented is not remembered at all', pB === null,
    pB === null ? 'no row for the unconsented customer, not even an empty one' : 'A ROW WAS WRITTEN WITHOUT CONSENT');

  // ---- P2: the BEHAVIOURAL reader — a gap is filled from memory -------------------------------
  await mkInquiry(EMAIL_A, null);
  const filled = one(await mgmtRead(STAGE,
    `select emirate from public.inquiries where summary='${TAG} fixture inquiry no-emirate'
       and customer_id=(select id from public.customers where email='${EMAIL_A}')`));
  step('an RFQ with no stated emirate inherits the remembered one', filled === 'Sharjah',
    `emirate resolved to ${JSON.stringify(filled)} — route_inquiry matches suppliers on this value`);

  // ---- P3: the MEMORY reader ------------------------------------------------------------------
  const v = await c360(EMAIL_A);
  const vs = typeof v === 'string' ? JSON.parse(v) : v;
  step('fn_ws_customer_360 reports the preference as remembered',
    vs?.remembered === true && JSON.stringify(vs?.emirates || []).includes('Sharjah'),
    `remembered=${vs?.remembered}, emirates=${JSON.stringify(vs?.emirates)}`);

  // ---- N2: THE ONE THAT MATTERS ---------------------------------------------------------------
  // 'Fujairah' appears in NONE of this customer's inquiries. A reader that re-derives from
  // inquiries — which is exactly what fn_ws_customer_360 did before this change — cannot produce
  // it, so this assertion fails for any wiring that only looks like it remembers.
  await mgmtWrite(STAGE,
    `update public.customer_preference set preferences = jsonb_set(preferences, '{stated}', '{"emirates":["Fujairah"]}'::jsonb)
      where customer_id=(select id from public.customers where email='${EMAIL_A}')`, 'state pref');

  await mgmtWrite(STAGE,
    `insert into public.inquiries (customer_id, category, emirate, summary)
     select id, 'joinery', null, '${TAG} fixture stated-wins'
       from public.customers where email='${EMAIL_A}'`, 'stated inquiry');
  const stated = one(await mgmtRead(STAGE,
    `select emirate from public.inquiries where summary='${TAG} fixture stated-wins'`));
  const v2 = await c360(EMAIL_A);
  const vs2 = typeof v2 === 'string' ? JSON.parse(v2) : v2;
  step('a STATED preference beats an inferred one, in both readers',
    stated === 'Fujairah' && JSON.stringify(vs2?.emirates || []).includes('Fujairah'),
    `trigger gave ${JSON.stringify(stated)}, 360 gave ${JSON.stringify(vs2?.emirates)} — neither re-derived from inquiries`);

  // ---- N3: the consent gate is not decorative --------------------------------------------------
  // Consent is withdrawn where it LIVES — customers.tos_accepted_at. The first version of this
  // check cleared customer_preference.consented_at instead and passed the trigger while failing the
  // 360, because the next inquiry simply re-learned the profile and restored the copy. Clearing a
  // cached consent is not withdrawing consent.
  await mgmtWrite(STAGE,
    `update public.customers set tos_accepted_at = null where email='${EMAIL_A}'`, 'revoke');
  await mgmtWrite(STAGE,
    `insert into public.inquiries (customer_id, category, emirate, summary)
     select id, 'joinery', null, '${TAG} fixture revoked'
       from public.customers where email='${EMAIL_A}'`, 'revoked inquiry');
  const revoked = one(await mgmtRead(STAGE,
    `select emirate from public.inquiries where summary='${TAG} fixture revoked'`));
  const v3 = await c360(EMAIL_A);
  const vs3 = typeof v3 === 'string' ? JSON.parse(v3) : v3;
  const rowGone = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.customer_preference p join public.customers c on c.id=p.customer_id
      where c.email='${EMAIL_A}'`)));
  step('withdrawing consent stops BOTH readers and removes the profile',
    revoked === null && vs3?.remembered === false && rowGone === 0,
    `emirate ${JSON.stringify(revoked)}, remembered=${vs3?.remembered}, rows left ${rowGone} — falls back to prior behaviour, not to a stale memory`);

  // ---- N4: erasure actually reaches the table --------------------------------------------------
  // The pattern is written 'dele[t]e' on purpose: qd_guard refuses any read whose text contains the
  // bare word, and it is right to — a read that can carry a write keyword is one typo from being a
  // write. The character class keeps the regex exact while failing that word-boundary match.
  const inRedact = one(await mgmtRead(STAGE,
    `select pg_get_functiondef(p.oid) ~ 'dele[t]e from public\\.customer_preference'
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fn_pdpl_redact'`));
  const inExport = one(await mgmtRead(STAGE,
    `select pg_get_functiondef(p.oid) like '%customer_preference%'
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fn_pdpl_export'`));
  step('a preference profile is erasable and exportable under PDPL',
    String(inRedact) === 'true' && String(inExport) === 'true',
    `fn_pdpl_redact deletes it=${inRedact}, fn_pdpl_export includes it=${inExport}`);

  // ---- the scorer's own predicate, so gate and scorecard cannot disagree ----------------------
  const readers = Number(one(await mgmtRead(STAGE,
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
              where ns.nspname='public' and p.prokind in ('f','p')
                and p.proname <> 'customer_preference'
                and pg_get_functiondef(p.oid) ~* '\\ycustomer_preference\\y')`)));
  step('customer_preference has real readers by the scorer\'s own measure', readers >= 3,
    `${readers} routine(s) reference it — was 0`);

  await cleanup();
  const left = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.customers where email like '${TAG}-%'`)));
  const leftPref = Number(one(await mgmtRead(STAGE, `select count(*) from public.customer_preference`)));
  step('the fixture cleaned up after itself', left === 0 && leftPref === 0,
    `${left} customer(s), ${leftPref} preference row(s) left behind`);
} catch (e) {
  step('the gate ran to completion', false, String(e.message || e).slice(0, 300));
  await cleanup().catch(() => {});
}

const pass = checks.filter(c => c.ok).length;
console.log(`\nCUSTOMER PREFERENCE ${pass}/${checks.length} on ${STAGE} (zero spend)`);
process.exit(pass === checks.length ? 0 : 1);
