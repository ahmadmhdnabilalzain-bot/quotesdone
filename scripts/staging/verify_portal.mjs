// verify_portal.mjs — what the customer portal is actually served.
//
// §3.3 called this the section that most needs demo data, and it is right: the journey produces
// exactly ONE inquiry with two quotes and then deletes the quotes, so no test has ever seen a
// portal with several inquiries in different states, and none has ever seen a REVEALED quote.
//
// The reveal is the whole business. QuotesDone is a marketplace where the customer pays to learn
// which supplier quoted, and `customer_api my_inquiries` decides what to disclose purely by whether
// a `transactions` row exists for that quote_id:
//
//   pre-reveal   supplier_ref null · rating/review/years BANDED · emirate, rating_source and
//                win_rate omitted from the JSON entirely rather than sent as null
//   post-reveal  supplier_ref = the real lead id, and every one of those fields exact
//
// A leak there is not a display bug, it is the paywall handing the product away. So the assertions
// below are about what is ABSENT from the pre-reveal payload, which is the half a screenshot cannot
// show you.
//
// Zero model calls: every inquiry, quote and reveal is built through the factory's SQL path.
//
//     node scripts/staging/verify_portal.mjs
import { mgmtRead } from '../lib/qd_guard.mjs';
import { readCustomerPortal } from '../lib/portal_sources.mjs';
import {
  REF, withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, makeReveal,
  mkAuthUser, call, q,
} from '../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(52)} ${detail}`);
};

await withRun(async (run) => {
  const cust = await makeCustomer(run, { mode: 'sql', full_name: 'Portal Demo Customer' });
  // Four suppliers, not three: `quotes` is UNIQUE (inquiry_id, supplier_id) and makeQuote upserts,
  // so adding the draft below with a supplier that already quoted would rewrite that supplier's
  // real quote into a draft rather than adding one.
  const sups = [];
  for (let i = 0; i < 4; i++) {
    sups.push(await makeSupplier(run, { trade: 'aluminium', variant: i % 3, variants: 3, withAuth: false }));
  }

  // Four inquiries spanning the states the portal has to render differently.
  const STATES = [
    { status: 'sent', quotes: 0 },        // dispatched, nothing back yet
    { status: 'quoted', quotes: 3 },      // the comparison case
    { status: 'completed', quotes: 2 },   // hired, closed
    { status: 'cancelled', quotes: 1 },   // withdrawn by the customer
  ];
  const built = [];
  for (const [n, s] of STATES.entries()) {
    const inq = await makeInquiry(run, {
      customer: cust, trade: 'aluminium', status: s.status,
      summary: `Demo ${s.status} inquiry ${n + 1}: aluminium windows for a villa`,
    });
    const qs = [];
    for (let i = 0; i < s.quotes; i++) {
      qs.push(await makeQuote(run, {
        inquiry: inq, supplier: sups[i], amount: 120000 + i * 7500,
        notes: `Quotation from demo supplier ${i + 1}.`,
      }));
    }
    // Spread FIRST: STATES carries its own `quotes` count, and `{inq, quotes: qs, ...s}` overwrites
    // the array with the number.
    built.push({ ...s, inq, quotes: qs });
  }

  // A draft must never reach the portal: my_inquiries filters status <> 'draft'.
  const draftInq = built[1].inq;
  await makeQuote(run, {
    inquiry: draftInq, supplier: sups[3], amount: 99000, status: 'draft',
    notes: 'Incomplete draft that must stay invisible.',
  });

  // Reveal exactly one quote, on the quoted inquiry.
  const revealed = built[1].quotes[0];
  await makeReveal(run, {
    quote: revealed, inquiry: built[1].inq, supplier: sups[0], customer: cust, reveal_fee: 150,
  });

  // ---- what the portal is served ---------------------------------------------------------------
  const r = await call('customer_api', cust.jwt, { action: 'my_inquiries' });
  const rows = Array.isArray(r.json?.inquiries) ? r.json.inquiries : [];
  const byId = new Map(rows.map((x) => [String(x.id), x]));
  step('the portal is served every inquiry, in every state',
    r.status === 200 && rows.length === 4
      && built.every((b) => byId.get(String(b.inq.id))?.status === b.status),
    `HTTP ${r.status} ${rows.length} inquiry(ies): ` +
    rows.map((x) => `${x.status}/${(x.quotes || []).length}q`).join(', '));

  const quotedRow = byId.get(String(built[1].inq.id)) || {};
  const qrs = quotedRow.quotes || [];
  step('a draft quote is never shown to the customer',
    qrs.length === 3 && !qrs.some((x) => x.status === 'draft'),
    `${qrs.length} quote(s) returned for an inquiry carrying 4 (one draft)`);

  step('quotes arrive cheapest first',
    qrs.length === 3 && qrs.every((x, i) => i === 0 || Number(qrs[i - 1].price) <= Number(x.price)),
    `prices ${qrs.map((x) => x.price).join(' → ')}`);

  step('every quote carries an anonymous label and a reveal fee',
    qrs.every((x) => /^Supplier /.test(String(x.label || '')) && Number(x.reveal_fee) > 0),
    `labels ${qrs.map((x) => x.label).join(', ')}; fees ${[...new Set(qrs.map((x) => x.reveal_fee))].join('/')} AED`);

  // ---- the paywall ------------------------------------------------------------------------------
  const paid = qrs.filter((x) => x.revealed === true);
  const unpaid = qrs.filter((x) => x.revealed !== true);
  const tx = (await mgmtRead(REF,
    `select quote_id::text, customer_id::text, revealed_at is not null revealed
       from public.transactions where inquiry_id=${q(built[1].inq.id)}`))[0] || {};
  step('exactly the paid-for quote is marked revealed',
    paid.length === 1 && unpaid.length === 2 && String(paid[0].id) === String(revealed.id),
    `${paid.length} revealed, ${unpaid.length} not. transactions row: quote=${String(tx.quote_id).slice(0, 8)} ` +
    `customer=${String(tx.customer_id).slice(0, 8)} (portal customer=${String(cust.customerId).slice(0, 8)}) ` +
    `expected quote=${String(revealed.id).slice(0, 8)}`);

  // The identity itself.
  step('an unrevealed quote carries no supplier identity',
    unpaid.every((x) => x.supplier_ref === null),
    `supplier_ref ${unpaid.map((x) => String(x.supplier_ref)).join(', ')} for the unpaid quotes`);

  // The fields that must be ABSENT, not null. `undefined` makes JSON.stringify drop the key
  // outright, so a client cannot reason about a null the way it can about a missing field.
  const leakedKeys = unpaid.flatMap((x) =>
    ['emirate', 'rating_source', 'win_rate'].filter((k) => Object.prototype.hasOwnProperty.call(x, k)));
  step('pre-reveal payloads omit the identifying keys entirely',
    leakedKeys.length === 0,
    leakedKeys.length ? `LEAKED ${[...new Set(leakedKeys)].join(', ')}`
                      : 'emirate, rating_source and win_rate are absent, not null');

  // Bands, not exact figures.
  const exactish = unpaid.filter((x) => typeof x.rating === 'number' || typeof x.rating_count === 'number');
  step('pre-reveal rating and review counts are banded, not exact',
    exactish.length === 0,
    `rating=${JSON.stringify(unpaid[0]?.rating)} count=${JSON.stringify(unpaid[0]?.rating_count)} ` +
    `years=${JSON.stringify(unpaid[0]?.years_active)}`);

  step('the revealed quote carries the real supplier id and exact figures',
    Number(paid[0].supplier_ref) === Number(sups[0].leadId)
      && Object.prototype.hasOwnProperty.call(paid[0], 'emirate'),
    `supplier_ref=${paid[0].supplier_ref} (lead ${sups[0].leadId}), ` +
    `emirate=${paid[0].emirate ?? 'null'} revealed_at=${paid[0].revealed_at ? 'set' : 'MISSING'}`);

  // ---- "reached nobody" vs "waiting" ------------------------------------------------------------
  // matched_suppliers exists so the portal can tell a customer their request reached nobody instead
  // of showing hope. The `sent` inquiry here was never dispatched, so it must read 0.
  const sentRow = byId.get(String(built[0].inq.id)) || {};
  step('an inquiry that reached nobody says so',
    Number(sentRow.matched_suppliers) === 0 && (sentRow.quotes || []).length === 0,
    `matched_suppliers=${sentRow.matched_suppliers} quotes=${(sentRow.quotes || []).length} ` +
    '— the portal can distinguish "waiting" from "reached nobody"');

  // ---- an auth user with no customers row --------------------------------------------------------
  // mkUser() produces this state and nothing has ever asserted what the portal does with it.
  const ghost = await mkAuthUser(run, `qd-${run.tag}-ghost@example.com`);
  const before = Number((await mgmtRead(REF,
    `select count(*)::int n from public.customers where id=${q(ghost.id)}`))[0].n);
  const gm = await call('customer_api', ghost.jwt, { action: 'me' });
  const gi = await call('customer_api', ghost.jwt, { action: 'my_inquiries' });
  const after = Number((await mgmtRead(REF,
    `select count(*)::int n from public.customers where lower(email)=lower(${q(ghost.email)})`))[0].n);
  step('a signed-in user with no customers row is handled, not crashed',
    gm.status === 200 && gi.status === 200 && (gi.json?.inquiries || []).length === 0,
    `me HTTP ${gm.status}, my_inquiries HTTP ${gi.status} with ` +
    `${(gi.json?.inquiries || []).length} inquiries; customers row ${before} → ${after} ` +
    `(created on first call, with a fresh uuid — not the auth uid)`);

  // ---- the Arabic customer ------------------------------------------------------------------------
  const ar = await makeCustomer(run, { mode: 'sql', locale: 'ar', full_name: 'عميل تجريبي' });
  const arInq = await makeInquiry(run, {
    customer: ar, trade: 'aluminium', locale: 'ar', status: 'quoted',
  });
  await makeQuote(run, {
    inquiry: arInq, supplier: sups[0], amount: 118000,
    notes: 'عرض سعر لتوريد وتركيب نوافذ ألمنيوم لفيلا في دبي.',
  });
  const arRows = await call('customer_api', ar.jwt, { action: 'my_inquiries' });
  const arRow = (arRows.json?.inquiries || [])[0] || {};
  const arNote = String((arRow.quotes || [])[0]?.notes || '');
  step('Arabic content survives the round trip intact',
    arRows.status === 200 && /[؀-ۿ]/.test(String(arRow.summary || ''))
      && /[؀-ۿ]/.test(arNote),
    `summary "${String(arRow.summary || '').slice(0, 34)}…", quote note carries Arabic=${/[؀-ۿ]/.test(arNote)}`);

  // FIXED 5 Aug 2026, and the brief's framing was not quite right. "customers.locale is stored and
  // never served" is false as stated: `me` returns the whole customer row via select('*'), locale
  // included - MEASURED, the key is present with value 'ar'. But THE PORTAL NEVER CALLS `me`. It
  // calls `kyc state` and `my_inquiries`, so the field was on the wire only where nothing was
  // listening. my_inquiries now serves it.
  const stored = (await mgmtRead(REF,
    `select locale from public.customers where id=${q(ar.customerId)}`))[0]?.locale;
  const servedHere = Object.prototype.hasOwnProperty.call(arRows.json || {}, 'locale');
  step('the customer\'s stored language is served where the portal actually looks',
    stored === 'ar' && servedHere && arRows.json.locale === 'ar',
    `customers.locale='${stored}', my_inquiries returns locale=${JSON.stringify(arRows.json?.locale)} ` +
    '(me already served it via select(*), but the portal calls kyc state + my_inquiries, never me)');

  // The half that is NOT done, pinned so it cannot be quietly forgotten: CustomerPortal still
  // decides language from localStorage['qd-lang'] and the NEXT_LOCALE cookie. `lang` lives in
  // CustomerPortal() while loadInq lives in Dashboard(), which receives lang as a read-only prop,
  // so consuming the served value needs it threaded through Authed -> Dashboard. Not done here:
  // there is still no browser harness (§3.6, itself blocked on a staging-pointed preview URL), and
  // a blind edit to language switching is not worth the risk for a field that is now available.
  // FLIPPED 5 Aug 2026. This used to assert 'the portal still ignores it', which is the shape of
  // gate that keeps a defect green. The wiring landed: onServedLocale is threaded
  // CustomerPortal -> Authed -> Dashboard, and loadInq applies j.locale.
  //
  // Still a GREP, not a render. There is no eslint, no jsx-a11y, no axe and no browser runner in
  // this repo (npm test is scripts/checks/run.mjs), so this proves the wiring EXISTS, not that it
  // works. It was hand-verified in a browser against a staging-pointed build. Do not report this
  // as proof the portal renders Arabic.
  const portalSrc = readCustomerPortal();
  const wired = /onServedLocale/.test(portalSrc)
    && /Dashboard\(\{[^)]*onServedLocale/.test(portalSrc)
    && /j\.locale/.test(portalSrc);
  const precedence = /localStorage\.getItem\('qd-lang'\)\)\s*return/.test(portalSrc);
  step('the portal consumes the served locale, and an explicit choice still wins',
    wired && precedence,
    wired
      ? (precedence ? 'onServedLocale threaded to Dashboard; applied from j.locale only when qd-lang is unset'
                    : 'WIRED but the explicit-choice guard is missing — a stored locale would override a toggle')
      : 'CustomerPortal does not consume j.locale');
});

const pass = checks.filter((c) => c.ok).length;
console.log(`\nPORTAL ${pass}/${checks.length} on ${REF} (zero spend)`);
process.exitCode = pass === checks.length ? 0 : 1;
