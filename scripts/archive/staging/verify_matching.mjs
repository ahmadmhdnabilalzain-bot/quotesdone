// verify_matching.mjs — what a supplier corpus is actually for.
//
// Phase 8's corpus is not a scale test. It exists to answer questions that one supplier cannot:
// does the relevance floor discard what it should, does the fan-out cap hold, does a different
// trade reach a different set of suppliers, and do the hard gates gate.
//
// Everything in the default run is SQL against the deployed fn_match_capability with a corpus built
// by demo_factory's zero-LLM path: 100 suppliers, 4 per trade across all 25 taxonomy_trade codes,
// two management-API round trips, no model calls, torn down as a set. Replaying journey_test 100
// times would be 12.9 hours and ~3,400 agent runs and would answer none of these questions.
//
// The score being asserted is
//     w_prod * product_hits/|p_products|   (40)
//   + w_brand * brand_hit                  (20)
//   + w_ptype * ptype_hit                  (15)
//   + w_track * track                      (15)
//   + w_size  * (size_known ? 1 : 0.5)     (10)
// so with brands and project_type left out of the query and `track` 0 on a fresh corpus, score is a
// pure function of product overlap. That is why the corpus varies products_norm and holds every
// gate uniform - see demo_factory's capabilityProfile.
//
//     node scripts/archive/staging/verify_matching.mjs           zero spend
//     node scripts/archive/staging/verify_matching.mjs --live    + one real dispatch (1 rfq_routing call)
import { mgmtRead, mgmtWrite } from '../../lib/qd_guard.mjs';
import {
  REF, withRun, makeBulkCorpus, makeCustomer, makeInquiry, makeRequirement,
  makeSupplier, capabilityProfile, internalCred, call, TRADES, TRADE_CODES, arr, q, num,
} from '../../lib/demo_factory.mjs';

const LIVE = process.argv.includes('--live');
const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(46)} ${detail}`);
};

const FLOOR = Number((await mgmtRead(REF,
  "select (value #>> '{}')::numeric v from public.decision_policy where key='match_relevance_floor'"))[0]?.v ?? 35);
const FANOUT = Number((await mgmtRead(REF,
  "select (value #>> '{}')::numeric v from public.decision_policy where key='match_max_fanout'"))[0]?.v ?? 5);

// route_inquiry calls fn_match_capability with this hardcoded limit and applies the floor AFTER it.
const ROUTE_LIMIT = 12;

const match = (trade, opts = {}) => mgmtRead(REF,
  `select supplier_id, company_name, score, product_hits, track
     from public.fn_match_capability(
       ${arr(opts.trades || [trade])}, ${q(opts.need || 'executes')},
       ${arr(opts.products || TRADES[trade].products)}, ${arr(opts.brands || [])},
       ${q(opts.project_type ?? null)}, ${num(opts.value ?? 150000)},
       ${q(opts.emirate ?? null)}, ${num(opts.limit ?? ROUTE_LIMIT)})
    order by score desc, supplier_id`);

await withRun(async (run) => {
  const corpus = await makeBulkCorpus(run, { perTrade: 4 });
  step('100-supplier corpus, 4 per trade across 25 trades, zero model calls',
    corpus.suppliers.length === 100 && corpus.trades.length === 25,
    `${corpus.suppliers.length} supplier(s), ${corpus.trades.length} trade(s), 2 round trips`);

  // ---- the score ladder, measured through the deployed function ------------------------------
  const ids = new Set(corpus.suppliers.map((s) => Number(s.leadId)));
  const rows = (await match('aluminium')).filter((r) => ids.has(Number(r.supplier_id)));
  const scores = rows.map((r) => Number(r.score));
  step('product overlap is the score dial, and it spreads',
    scores.length === 4 && new Set(scores).size === 4,
    `scores ${scores.join(' / ')} from ${rows.map((r) => r.product_hits).join('/')} product hits`);

  step('the ladder lands where the weights say it should',
    JSON.stringify(scores) === JSON.stringify([50, 40, 30, 5]),
    `expected 50/40/30/5 (40*hits/8 + w_size 10, decoy 0 + w_size*0.5), got ${scores.join('/')}`);

  const above = scores.filter((s) => s >= FLOOR);
  step(`match_relevance_floor ${FLOOR} discards the weak half`,
    above.length === 2 && scores.filter((s) => s < FLOOR).length === 2,
    `${above.length} of 4 at or above ${FLOOR}: ${above.join(', ')} — discarded ${scores.filter((s) => s < FLOOR).join(', ')}`);

  const decoy = rows[rows.length - 1];
  step('a supplier with zero product overlap sits on the 5-point floor',
    Number(decoy.score) === 5 && Number(decoy.product_hits) === 0,
    `score=${decoy.score} hits=${decoy.product_hits} — w_size*0.5 with min/max_project_value null`);

  step('track is 0 on a fresh corpus, so the spread is reproducible',
    rows.every((r) => Number(r.track) === 0),
    `track ${[...new Set(rows.map((r) => String(r.track)))].join(',')} — quote_rate overrides ` +
    'perf_score once matched>0, which is why rating is the wrong dial');

  // ---- the limit the brief thought was the constraint ------------------------------------------
  step(`p_limit ${ROUTE_LIMIT} never binds on a trade-spread corpus`,
    rows.length === 4 && rows.length < ROUTE_LIMIT,
    `${rows.length} candidate(s) reach a limit of ${ROUTE_LIMIT} — trades are a GATE, not a score term`);

  // ---- the hard gates --------------------------------------------------------------------------
  const other = (await match('hvac')).filter((r) => ids.has(Number(r.supplier_id)));
  const overlap = other.filter((r) => rows.some((a) => Number(a.supplier_id) === Number(r.supplier_id)));
  step('a different trade reaches a different set of suppliers',
    other.length === 4 && overlap.length === 0,
    `hvac returned ${other.length}, ${overlap.length} of them also in the aluminium set`);

  // electrical requires the electrical_utility authority. The corpus holds it; strip it from one
  // supplier and that supplier must vanish before scoring, not score low.
  const elec = (await match('electrical')).filter((r) => ids.has(Number(r.supplier_id)));
  const victim = elec[0];
  await mgmtWrite(REF,
    `update public.supplier_capabilities set authority_approvals='{}'::jsonb
      where supplier_id=${num(victim.supplier_id)}`, 'strip authority');
  const elecAfter = (await match('electrical')).filter((r) => ids.has(Number(r.supplier_id)));
  step('a missing mandatory authority removes a supplier entirely',
    elec.length === 4 && elecAfter.length === 3
      && !elecAfter.some((r) => Number(r.supplier_id) === Number(victim.supplier_id)),
    `electrical ${elec.length} -> ${elecAfter.length} after dropping electrical_utility from ` +
    `supplier ${victim.supplier_id} (it does not score low, it disappears)`);

  // roles are a gate too: a supplies-only supplier cannot be found for 'executes'.
  const sup = await makeSupplier(run, {
    trade: 'joinery', withAuth: false,
    profile: capabilityProfile('joinery', 0, 1, { roleSet: 'supplies_only' }),
  });
  const asExec = (await match('joinery')).some((r) => Number(r.supplier_id) === Number(sup.leadId));
  const asSupp = (await match('joinery', { need: 'supplies' }))
    .some((r) => Number(r.supplier_id) === Number(sup.leadId));
  step('the role gate excludes a supplies-only supplier from executes work',
    asExec === false && asSupp === true,
    `p_need executes -> ${asExec ? 'FOUND' : 'excluded'}, p_need supplies -> ${asSupp ? 'found' : 'MISSING'}`);

  // ---- the fan-out cap -------------------------------------------------------------------------
  // The ladder deliberately puts only 2 of 4 above the floor, which can never exercise a cap of 5.
  // A flat corpus gives every supplier the full product list so they all clear it.
  const flat = await makeBulkCorpus(run, { trades: ['flooring'], perTrade: 8, flat: true });
  const flatIds = new Set(flat.suppliers.map((s) => Number(s.leadId)));
  // 300000 sits inside every band the fixture declares. 150000 does not - see the next check.
  const JOB = 300000;
  const flatRows = (await match('flooring', { limit: 50, value: JOB })).filter((r) => flatIds.has(Number(r.supplier_id)));
  const flatAbove = flatRows.filter((r) => Number(r.score) >= FLOOR);
  step(`more candidates above the floor than MAX_FANOUT ${FANOUT} can take`,
    flatAbove.length === 8 && flatAbove.length > FANOUT,
    `${flatAbove.length} supplier(s) at score ${[...new Set(flatAbove.map((r) => String(r.score)))].join('/')} ` +
    `against a cap of ${FANOUT}`);

  // The size GATE, which is not the same thing as the w_size score term and is not in the brief.
  // `p_value is null or (p_value >= min_project_value and p_value <= max_project_value)` runs in the
  // cand CTE, so a supplier whose declared minimum is above the job value is removed before scoring
  // - it does not score low, it is absent. Two of these eight declare min 250,000.
  const small = (await match('flooring', { limit: 50, value: 150000 })).filter((r) => flatIds.has(Number(r.supplier_id)));
  step('min_project_value is a hard gate, not a score term',
    small.length === 6 && flatRows.length === 8,
    `same 8 suppliers: job ${JOB} -> ${flatRows.length} candidates, job 150000 -> ${small.length} ` +
    '(the 2 declaring min 250,000 disappear rather than scoring low)');

  if (LIVE) {
    const cust = await makeCustomer(run, { mode: 'sql' });
    const inq = await makeInquiry(run, { customer: cust, trade: 'flooring', emirate: 'Dubai' });
    await makeRequirement(run, { inquiry: inq, trade: 'flooring', value_band: 300000 });
    const cred = await internalCred();
    const d = await call('dispatch_inquiry', null, { __secret: cred, inquiry_id: inq.id });
    const notified = Number(d.json?.notified ?? -1);
    const matched = await mgmtRead(REF,
      `select supplier_id from public.inquiry_matches where inquiry_id=${q(inq.id)}`);
    step('dispatch never exceeds MAX_FANOUT',
      d.status === 200 && notified >= 0 && notified <= FANOUT && matched.length <= FANOUT,
      `HTTP ${d.status} outcome=${d.json?.outcome ?? '-'} notified=${notified} ` +
      `capped=${d.json?.capped} rows=${matched.length} cap=${d.json?.max_fanout ?? FANOUT} :: ${d.text}`);
    // Membership of the `flat` set is the WRONG assertion: the 100-supplier corpus also holds 4
    // flooring suppliers, so the eligible pool is 12, not 8. The real claim is that every supplier
    // contacted declares the trade that was asked for.
    const wrongTrade = await mgmtRead(REF,
      `select m.supplier_id, sc.trades
         from public.inquiry_matches m
         join public.supplier_capabilities sc on sc.supplier_id = m.supplier_id
        where m.inquiry_id = ${q(inq.id)} and not ('flooring' = any(sc.trades))`);
    step('every supplier contacted declares the trade that was asked for',
      matched.length > 0 && wrongTrade.length === 0,
      `${matched.length} match(es), ${wrongTrade.length} outside the flooring trade` +
      (wrongTrade.length ? `: ${wrongTrade.map((r) => r.supplier_id).join(', ')}` : ''));
  }
}, { quiet: false });

const pass = checks.filter((c) => c.ok).length;
console.log(`\nMATCHING ${pass}/${checks.length} on ${REF}${LIVE ? ' (with live dispatch)' : ' (zero spend)'}`);
process.exitCode = pass === checks.length ? 0 : 1;
