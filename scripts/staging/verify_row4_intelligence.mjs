// PROVE THE ROW #4 INTELLIGENCE BACKEND BY EXECUTING IT — against STAGING, on fixture data this
// script creates and then deletes.
//
// WHY IT HAS TO CREATE DATA. Production and staging both hold zero customers, zero inquiries and
// zero quotes, so calling these routines there exercises exactly ONE branch: the honest-empty one.
// That branch matters and is asserted below, but a forecast that only ever returns "no history" is
// not a forecast, and a negotiation assistant whose target-price arithmetic has never run once is
// not deployed, it is merely present. Every populated branch is therefore driven with real rows and
// the numbers are checked against values computed here, independently of the routine.
//
//   node scripts/staging/verify_row4_intelligence.mjs
//
// Teardown is in a finally and deletes by captured id, so a mid-run throw does not litter staging.
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { REF, q, num, makeInquiry, makeCustomer, withRun, call } from './demo_factory.mjs';

const one = async (sql) => { const r = await mgmtRead(REF, sql, 'verify'); return r[0] ? Object.values(r[0])[0] : null; };
const rows = (sql) => mgmtRead(REF, sql, 'verify');
const w = (sql, what = 'fixture') => mgmtWrite(REF, sql, what);

let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => {
  if (cond) { pass++; console.log(`  PASS  ${name}${detail ? '  — ' + detail : ''}`); }
  else { fail++; console.log(`  FAIL  ${name}${detail ? '  — ' + detail : ''}`); }
};

const ids = { customer: null, leads: [], projects: [], inquiries: [], quotes: [] };

await withRun(async (run) => {
try {
  console.log(`\nrow #4 intelligence backend, executed against ${REF}\n`);

  // ── 0. THE HONEST-EMPTY BRANCH, FIRST, ON A CUSTOMER THAT DOES NOT EXIST ──────────────────────
  const empty = JSON.parse(await one(`select public.fn_customer_forecast('00000000-0000-0000-0000-000000000000'::uuid)::text`));
  ok('forecast: unknown customer returns basis=no_history', empty.basis === 'no_history', `basis=${empty.basis}`);
  ok('forecast: series is [] not twelve zeroes', Array.isArray(empty.series) && empty.series.length === 0, `series length ${empty.series.length}`);
  ok('forecast: next-year figures are null, not 0', empty.next_year.projected_rfqs === null && empty.next_year.projected_spend_aed === null);
  ok('forecast: empty_reason explains itself', typeof empty.empty_reason === 'string' && empty.empty_reason.length > 40);
  ok('forecast: no predictions invented', empty.predictions.length === 0);

  // ── 1. FIXTURE ────────────────────────────────────────────────────────────────────────────────
  // A REAL auth user, because section 8 below calls the two new edge functions over HTTP with this
  // customer's own JWT. A hand-inserted customers row has no token and would leave the endpoints —
  // the only thing a surface can actually reach — unexercised.
  const cust = await makeCustomer(run);
  ids.customer = cust.customerId;

  for (const nm of ['QD Row4 Supplier A', 'QD Row4 Supplier B', 'QD Row4 Supplier C', 'QD Row4 Stranger']) {
    ids.leads.push(await one(`select id::text from public.leads where company_name = ${q(nm)}`)
      ?? (await w(`insert into public.leads (company_name, sector, emirate, source)
                   values (${q(nm)}, 'contracting', 'Dubai', 'qd_row4_verify') returning id`))[0].id);
  }
  const [S1, S2, S3, STRANGER] = ids.leads;

  // A finished project (its lead time is what the prediction learns) and a live one 60 days out.
  const mkProject = async (name, target, status, createdDaysAgo) => (await w(
    `insert into public.projects (customer_id, name, status, target_open_date, budget_total, created_at)
     values (${q(ids.customer)}, ${q(name)}, ${q(status)}, current_date + ${num(target)},
             1500000, now() - interval '${Number(createdDaysAgo)} days') returning id`))[0].id;
  const P_PAST = await mkProject('QD Row4 Past Villa', -20, 'completed', 200);
  const P_LIVE = await mkProject('QD Row4 Live Tower', 60, 'active', 40);
  ids.projects.push(P_PAST, P_LIVE);

  // THE INQUIRY IS BUILT BY demo_factory.makeInquiry, NOT BY A HAND-WRITTEN INSERT. A plain insert
  // lands with rfq_ready = false (trg_inquiry_enrich scores completeness at 30), and an inquiry that
  // is not rfq_ready is silently unmatchable — see the note on inquiry_matches below. makeInquiry
  // fills the required category_specs answers, so the fixture is an RFQ the platform itself
  // considers routable, which is the only fixture worth asserting against.
  const mkInquiry = async (project, category, daysAgo, status, value) => {
    const inq = await makeInquiry(run, { customer: { customerId: ids.customer }, trade: category, emirate: 'Dubai' });
    await w(`update public.inquiries set project_id = ${q(project)}, status = ${q(status)},
                    expected_value = ${num(value)}, created_at = now() - interval '${Number(daysAgo)} days'
              where id = ${q(inq.id)}`);
    return inq.id;
  };
  // Past project: both trades. Live project: joinery only, so aluminium is the predicted gap.
  const I_ALU_PAST = await mkInquiry(P_PAST, 'aluminium', 150, 'completed', 400000);
  const I_JOI_PAST = await mkInquiry(P_PAST, 'joinery', 140, 'completed', 250000);
  const I_JOI_LIVE = await mkInquiry(P_LIVE, 'joinery', 20, 'sent', 300000);
  ids.inquiries.push(I_ALU_PAST, I_JOI_PAST, I_JOI_LIVE);

  // Four aluminium quotes, because the house policy refuses to quote a market price below four.
  const mkQuote = async (inq, supplier, amount, daysAgo) => (await w(
    `insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, created_at)
     values (${q(inq)}, ${num(supplier)}, ${num(amount)}, 'sent', now() - interval '${Number(daysAgo)} days')
     returning id`))[0].id;
  const QA = await mkQuote(I_ALU_PAST, S1, 400000, 148);
  const QB = await mkQuote(I_ALU_PAST, S2, 460000, 147);
  const QC = await mkQuote(I_ALU_PAST, S3, 520000, 146);
  const QD = await mkQuote(I_ALU_PAST, STRANGER, 900000, 145);   // the outlier we will benchmark
  const QJ = await mkQuote(I_JOI_LIVE, S1, 300000, 18);
  ids.quotes.push(QA, QB, QC, QD, QJ);

  // public.inquiry_matches carries a BEFORE INSERT gate (trg_gate_incomplete_match) that SILENTLY
  // drops a match whose inquiry is not rfq_ready — it returns null, so the insert reports success
  // and writes nothing. The first run of this script asserted supplier_count and rfqs_sent against
  // four matches that were never stored, and only the read-back below caught it.
  await w(`insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
           values (${q(I_ALU_PAST)}, ${num(S1)}, 0.9, now(), 'verify'),
                  (${q(I_ALU_PAST)}, ${num(S2)}, 0.8, now(), 'verify'),
                  (${q(I_JOI_LIVE)}, ${num(S1)}, 0.7, now(), 'verify'),
                  (${q(I_JOI_LIVE)}, ${num(S3)}, 0.6, now(), 'verify')`);
  const nMatches = await one(`select count(*)::text from public.inquiry_matches where inquiry_id in
      (${q(I_ALU_PAST)}, ${q(I_JOI_LIVE)})`);
  ok('fixture: the four matches were actually stored', nMatches === '4', `${nMatches} stored`);

  await w(`update public.inquiries set hired_supplier_id = ${num(S1)} where id = ${q(I_ALU_PAST)}`);

  await w(`insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id,
                                            quote_amount, revealed_at, supplier_ack_at, reveal_fee)
           values (${q(QA)}, ${q(I_ALU_PAST)}, ${num(S1)}, ${q(ids.customer)}, 400000, now() - interval '140 days', now() - interval '139 days', 250),
                  (${q(QB)}, ${q(I_ALU_PAST)}, ${num(S2)}, ${q(ids.customer)}, 460000, now() - interval '140 days', null, 250)`);

  // supplier_score is the PLATFORM-WIDE table (0 rows on staging, 20,464 on production). Two rows
  // so the supplier_performance endpoint has something to serve and the reveal gate has something
  // to withhold.
  await w(`insert into public.supplier_score (lead_id, response_rate, avg_response_hours, quotes_submitted,
                                              quotes_won, price_index, quality_rating, reliability, computed_at)
           values (${num(S1)}, 0.82, 6.5, 12, 4, 0.97, 4.3, 0.88, now()),
                  (${num(S3)}, 0.44, 31.0, 5, 0, 1.12, 3.1, 0.51, now())
           on conflict (lead_id) do nothing`);

  // THE FIXTURE HAS TO OBEY THE PRODUCT'S OWN RULE (14 Aug 2026). `reviews_reason_required` requires
  // a comment of at least 10 characters — a review must carry a real reason, not a word — and this
  // fixture said 'good', four characters. The insert therefore threw 23514 and killed the whole
  // script AFTER it had already printed "146/147", so every run today was a PARTIAL run reporting a
  // complete-looking score. A partial scorer run is not a score.
  // The constraint is correct product behaviour and is NOT relaxed; the fixture is what was wrong.
  await w(`insert into public.reviews (supplier_id, customer_id, inquiry_id, rating, comment,
                                       r_communication, r_quality, r_punctuality, r_documentation, r_after_sales, r_compliance)
           values (${num(S1)}, ${q(ids.customer)}, ${q(I_ALU_PAST)}, 4,
                   'Good work overall — on time, clean handover, minor snag on documentation.',
                   4, 5, 4, 4, 3, 4)`);

  // ── 2. §8 — the reference number ──────────────────────────────────────────────────────────────
  const refs = await rows(`select rfq_no from public.inquiries where id in
      (${q(I_ALU_PAST)}, ${q(I_JOI_PAST)}, ${q(I_JOI_LIVE)}) order by rfq_no`);
  const refNos = refs.map(r => Number(r.rfq_no));
  ok('rfq_no: every inquiry got one', refNos.every(n => Number.isInteger(n) && n > 0), refNos.join(','));
  ok('rfq_no: they are distinct', new Set(refNos).size === refNos.length);
  ok('rfq_no: five digits, human-readable', refNos.every(n => n >= 10000 && n <= 999999));
  const dup = await one(`select count(*)::text from (select rfq_no from public.inquiries group by rfq_no having count(*) > 1) z`);
  ok('rfq_no: unique across the table', dup === '0', `${dup} duplicated value(s)`);

  // ── 3. §5 — the three project_summary figures ─────────────────────────────────────────────────
  const ps = (await rows(`select trade_breakdown::text tb, supplier_count::text sc, timeline_pct::text tp,
                                 rfq_count::text rc from public.project_summary where project_id = ${q(P_LIVE)}`))[0];
  const tb = JSON.parse(ps.tb);
  ok('project_summary.trade_breakdown lists the project trades', tb.length === 1 && tb[0].category === 'joinery' && tb[0].rfqs === 1, ps.tb);
  ok('project_summary.supplier_count counts this project only', ps.sc === '2', `supplier_count=${ps.sc} (4 matches exist, 2 of them on this project)`);
  const tp = Number(ps.tp);
  ok('project_summary.timeline_pct is a real elapsed percentage', tp > 30 && tp < 60, `timeline_pct=${ps.tp} (40 days elapsed of a 100-day window)`);

  const psPast = (await rows(`select trade_breakdown::text tb from public.project_summary where project_id = ${q(P_PAST)}`))[0];
  ok('project_summary.trade_breakdown splits by trade', JSON.parse(psPast.tb).length === 2, psPast.tb);

  const noTarget = (await w(`insert into public.projects (customer_id, name, status)
                             values (${q(ids.customer)}, 'QD Row4 No Deadline', 'active') returning id`))[0].id;
  ids.projects.push(noTarget);
  const npt = await one(`select coalesce(timeline_pct::text,'NULL') from public.project_summary where project_id = ${q(noTarget)}`);
  ok('project_summary.timeline_pct is NULL without a target date, not 0%', npt === 'NULL', `got ${npt}`);

  // ── 4. §11 / §20 — the forecast and the prediction ────────────────────────────────────────────
  const f = JSON.parse(await one(`select public.fn_customer_forecast(${q(ids.customer)}::uuid)::text`));
  ok('forecast: basis is history once history exists', f.basis === 'history');
  ok('forecast: observed counts the customer own RFQs', f.observed.rfqs === 3, `rfqs=${f.observed.rfqs}`);
  ok('forecast: series starts at the first RFQ, not 12 months back',
     f.series.length >= 5 && f.series.length <= 7, `${f.series.length} month point(s) for a 150-day-old account`);
  ok('forecast: sufficient_data is true at 3 RFQs over 2+ months', f.sufficient_data === true);
  ok('forecast: next-year projection is a number', Number(f.next_year.projected_rfqs) > 0, `projected_rfqs=${f.next_year.projected_rfqs}`);
  ok('forecast: by_category only lists categories the customer actually bought',
     f.next_year.by_category.map(c => c.category).sort().join(',') === 'aluminium,joinery',
     f.next_year.by_category.map(c => c.category).join(','));
  const pred = f.predictions.find(p => p.category === 'aluminium' && p.project_name === 'QD Row4 Live Tower');
  ok('prediction: names the gap on the live project', !!pred, JSON.stringify(f.predictions.map(p => p.category + '@' + p.project_name)));
  if (pred) {
    ok('prediction: carries a time window in days', Number.isInteger(pred.within_days) && pred.within_days >= 0, `within_days=${pred.within_days}`);
    ok('prediction: window is the deadline minus the observed lead time',
       pred.within_days < 60, `target is 60 days out; the customer historically raised aluminium ~${60 - pred.within_days} days ahead`);
    ok('prediction: recommends an action', /RFQ/.test(pred.recommended_action || ''), (pred.recommended_action || '').slice(0, 80));
    ok('prediction: states the evidence it used', /procured/.test(pred.reason || ''), (pred.reason || '').slice(0, 80));
  }
  const noPred = f.predictions.find(p => p.project_name === 'QD Row4 No Deadline');
  ok('prediction: a project with no deadline gets no invented horizon', !noPred);

  // ── 5. §13 — the per-customer relationship score ──────────────────────────────────────────────
  const rel = JSON.parse(await one(`select public.fn_customer_supplier_score(${q(ids.customer)}::uuid, ${num(S1)})::text`));
  ok('relationship: basis is shared_history', rel.basis === 'shared_history');
  ok('relationship: score is 0-100', Number(rel.relationship_score) > 0 && Number(rel.relationship_score) <= 100, `score=${rel.relationship_score}`);
  ok('relationship: history is THIS customer only', rel.history.rfqs_sent === 2 && rel.history.quotes_received === 2 && rel.history.orders === 1,
     JSON.stringify(rel.history));
  ok('relationship: delivery_pct from this customer own reveals', rel.delivery_pct === 100, `delivery_pct=${rel.delivery_pct} (1 of 1 reveal acknowledged)`);
  ok('relationship: quality_pct from this customer own review', rel.quality_pct === 80, `quality_pct=${rel.quality_pct} (4 of 5 stars)`);
  ok('relationship: components show their working', rel.components.length >= 3, rel.components.map(c => c.name).join(','));
  ok('relationship: platform-wide figures are labelled separately', 'platform_wide' in rel);

  const stranger = JSON.parse(await one(`select public.fn_customer_supplier_score(${q(ids.customer)}::uuid, ${num(STRANGER)})::text`));
  ok('relationship: a supplier who only quoted is still shared history', stranger.basis === 'shared_history', `basis=${stranger.basis}`);
  const unknown = JSON.parse(await one(`select public.fn_customer_supplier_score('00000000-0000-0000-0000-000000000000'::uuid, ${num(S1)})::text`));
  ok('relationship: no shared history returns NULL, never 0', unknown.relationship_score === null && unknown.basis === 'no_shared_history');
  ok('relationship: and says why', /have not worked with/.test(unknown.empty_reason || ''));

  // ── 6. §15 — negotiation guidance ─────────────────────────────────────────────────────────────
  const stats = (await rows(`select n::text, median::text from public.category_price_stats where category = 'aluminium'`))[0];
  // >= 4, not = 4: category_price_stats is global, so any other aluminium quote alive on staging
  // counts too. The claim under test is that the sample now clears the policy's min_sample, not
  // that this script is the only writer on a shared branch.
  ok('market: category_price_stats now clears the policy min_sample', Number(stats.n) >= 4, `n=${stats.n} median=${stats.median}`);

  const g = JSON.parse(await one(`select public.fn_negotiation_guidance(${q(ids.customer)}::uuid, ${q(QD)}::uuid)::text`));
  ok('negotiation: the market median reaches the caller', Number(g.market_median) === Number(stats.median), `median=${g.market_median}`);
  ok('negotiation: the quote is measured against it', Number(g.delta_vs_median_pct) > 0, `delta=${g.delta_vs_median_pct}%`);
  ok('negotiation: policy scope is named', g.policy_scope === 'default', `scope=${g.policy_scope}`);
  ok('negotiation: a recommended action is produced', typeof g.recommended_action === 'string' && g.recommended_action !== 'no_policy', g.recommended_action);
  ok('negotiation: a target price is produced', Number(g.target_price) > 0, `target=${g.target_price} against a quote of ${g.quote_amount}`);
  ok('negotiation: the target respects the policy floor',
     Number(g.target_price) >= Math.round(Number(stats.median) * 0.8), `target=${g.target_price}, floor=${Math.round(Number(stats.median) * 0.8)}`);
  ok('negotiation: the ask is inside the policy cap', Number(g.ask_discount_pct) > 0 && Number(g.ask_discount_pct) <= 25, `ask=${g.ask_discount_pct}%`);
  ok('negotiation: a ready-to-send message is drafted', (g.suggested_message || '').length > 150);
  ok('negotiation: the message quotes the target, not a placeholder',
     (g.suggested_message || '').includes(String(g.target_price)), (g.suggested_message || '').slice(0, 90));
  ok('negotiation: an Arabic draft is produced and is Arabic',
     /[؀-ۿ]/.test(g.suggested_message_ar || ''), (g.suggested_message_ar || '').slice(0, 40));

  const gj = JSON.parse(await one(`select public.fn_negotiation_guidance(${q(ids.customer)}::uuid, ${q(QJ)}::uuid)::text`));
  ok('negotiation: a category with one quote gets NO benchmark', gj.band === 'insufficient_data', `band=${gj.band} n=${gj.market_sample_n}`);
  ok('negotiation: and NO target price', gj.target_price === null && gj.ask_discount_pct === null);
  ok('negotiation: and says why instead', /fewer comparable quotes/.test(gj.empty_reason || ''), (gj.empty_reason || '').slice(0, 80));
  ok('negotiation: the thin-data message asks for scope, it does not cite a market figure',
     /inclusions and exclusions/.test(gj.suggested_message || ''), (gj.suggested_message || '').slice(0, 70));

  const foreign = JSON.parse(await one(`select public.fn_negotiation_guidance('00000000-0000-0000-0000-000000000000'::uuid, ${q(QD)}::uuid)::text`));
  ok('negotiation: another customer quote is refused', foreign.error === 'not_your_quote');

  // ── 7. §11 — savings, broken down by category ─────────────────────────────────────────────────
  const sav = JSON.parse(await one(`select public.fn_customer_savings(${q(ids.customer)}::uuid)::text`));
  const alu = (sav.by_category || []).find(c => c.category === 'joinery');
  ok('savings: broken down by category', Array.isArray(sav.by_category) && sav.by_category.length > 0,
     (sav.by_category || []).map(c => c.category).join(','));
  ok('savings: a total figure is presented', Number(sav.total_spread_saving_aed) >= 0, `total_spread=${sav.total_spread_saving_aed}`);
  ok('savings: the benchmark half names its own evidence', typeof (alu || {}).benchmark_basis === 'string',
     (alu || {}).benchmark_basis);
  const savEmpty = JSON.parse(await one(`select public.fn_customer_savings('00000000-0000-0000-0000-000000000000'::uuid)::text`));
  ok('savings: no quotes gives [] and a null total, not a zero', savEmpty.by_category.length === 0
     && savEmpty.total_spread_saving_aed === null, JSON.stringify(savEmpty.total_spread_saving_aed));
  ok('savings: and says why', /nothing to compute/.test(savEmpty.empty_reason || ''));

  // ── 8. THE ENDPOINTS, OVER HTTP, WITH THIS CUSTOMER'S OWN JWT ─────────────────────────────────
  // A routine the surface cannot reach is not deployed. Each action is called the way a browser
  // would call it, and the response shape asserted is the one the surface agent is told to expect.
  const ci = (b) => call('customer_intelligence', cust.jwt, b);
  const na = (b) => call('negotiation_assistant', cust.jwt, b);

  const eForecast = await ci({ action: 'forecast' });
  ok('endpoint customer_intelligence/forecast: boots and answers 200', eForecast.status === 200, `HTTP ${eForecast.status} ${eForecast.text.slice(0, 90)}`);
  ok('endpoint customer_intelligence/forecast: serves the prediction array',
     Array.isArray(eForecast.json?.predictions) && eForecast.json.predictions.length > 0,
     `${eForecast.json?.predictions?.length} prediction(s)`);
  ok('endpoint customer_intelligence/forecast: serves the next-year projection',
     Number(eForecast.json?.forecast?.next_year?.projected_rfqs) > 0);

  const eRel = await ci({ action: 'supplier_relationship', supplier_id: Number(S1) });
  ok('endpoint customer_intelligence/supplier_relationship: 200', eRel.status === 200, `HTTP ${eRel.status} ${eRel.text.slice(0, 90)}`);
  ok('endpoint supplier_relationship: returns a score', Number(eRel.json?.relationship_score) > 0, `score=${eRel.json?.relationship_score}`);
  ok('endpoint supplier_relationship: a revealed supplier is named', !!eRel.json?.relationship?.supplier_name, eRel.json?.relationship?.supplier_name);

  const eRelLocked = await ci({ action: 'supplier_relationship', supplier_id: Number(S3) });
  ok('endpoint supplier_relationship: an UNREVEALED supplier stays behind the paywall',
     !eRelLocked.json?.relationship?.supplier_name && typeof eRelLocked.json?.relationship?.locked === 'string',
     String(eRelLocked.json?.relationship?.locked || '').slice(0, 60));

  const ePerf = await ci({ action: 'supplier_performance' });
  const perfIds = (ePerf.json?.suppliers || []).map(s => Number(s.lead_id)).sort();
  ok('endpoint customer_intelligence/supplier_performance: 200', ePerf.status === 200, `HTTP ${ePerf.status}`);
  ok('endpoint supplier_performance: serves the four named dimensions',
     ePerf.json?.suppliers?.[0] && ['reliability', 'price_index', 'quality_rating', 'response_rate']
       .every(k => ePerf.json.suppliers[0][k] !== undefined),
     JSON.stringify(ePerf.json?.suppliers?.[0] || {}).slice(0, 110));
  ok('endpoint supplier_performance: lists the revealed suppliers and NOT the unrevealed one',
     perfIds.includes(Number(S1)) && !perfIds.includes(Number(S3)),
     `returned lead_id(s) [${perfIds.join(',')}]; S1=${S1} revealed, S3=${S3} scored but never revealed`);

  const eSav = await ci({ action: 'savings' });
  ok('endpoint customer_intelligence/savings: 200 with a by_category array', eSav.status === 200 && Array.isArray(eSav.json?.by_category),
     `HTTP ${eSav.status}`);

  const eGuid = await na({ action: 'guidance', quote_id: QD });
  ok('endpoint negotiation_assistant/guidance: boots and answers 200', eGuid.status === 200, `HTTP ${eGuid.status} ${eGuid.text.slice(0, 90)}`);
  ok('endpoint guidance: serves a recommended action and a target price',
     !!eGuid.json?.recommended_action && Number(eGuid.json?.target_price) > 0,
     `${eGuid.json?.recommended_action} @ ${eGuid.json?.target_price}`);
  ok('endpoint guidance: serves the drafted message', (eGuid.json?.suggested_message || '').length > 150);

  const eMkt = await na({ action: 'market', category: 'aluminium', amount: 900000 });
  ok('endpoint negotiation_assistant/market: 200 with the market row', eMkt.status === 200 && !!eMkt.json?.category_price_stats,
     `HTTP ${eMkt.status} n=${eMkt.json?.category_price_stats?.n}`);

  const ePol = await na({ action: 'policy' });
  ok('endpoint negotiation_assistant/policy: serves the seeded house policy',
     ePol.status === 200 && ePol.json?.policy?.scope === 'default', `HTTP ${ePol.status}`);
  ok('endpoint policy: the seeded bounds are readable',
     Number(ePol.json?.policy?.policy?.min_sample) === 4
     && Number(ePol.json?.policy?.policy?.bands?.suspiciously_high?.max_ask_discount_pct) === 25,
     JSON.stringify(ePol.json?.policy?.policy?.bands?.suspiciously_high || {}));

  const eAnon = await call('negotiation_assistant', null, { action: 'policy' });
  ok('endpoint negotiation_assistant: refuses a call with no customer JWT', eAnon.status === 401, `HTTP ${eAnon.status}`);

  // §5 — the three project figures, on the endpoint a surface actually opens a project through.
  const eDet = await call('project_api', cust.jwt, { action: 'detail', id: P_LIVE });
  ok('endpoint project_api/detail: 200', eDet.status === 200, `HTTP ${eDet.status} ${eDet.text.slice(0, 90)}`);
  ok('endpoint project_api/detail: serves the trade breakdown',
     Array.isArray(eDet.json?.trade_breakdown) && eDet.json.trade_breakdown.length === 1,
     JSON.stringify(eDet.json?.trade_breakdown));
  ok('endpoint project_api/detail: serves the per-project supplier count',
     Number(eDet.json?.supplier_count) === 2, `supplier_count=${eDet.json?.supplier_count}`);
  ok('endpoint project_api/detail: serves the timeline percentage',
     Number(eDet.json?.timeline_pct) > 0 && Number(eDet.json?.timeline_pct) <= 100, `timeline_pct=${eDet.json?.timeline_pct}`);
  ok('endpoint project_api/detail: each RFQ carries its human reference number',
     (eDet.json?.rfqs || []).every(r => Number(r.rfq_no) > 0),
     (eDet.json?.rfqs || []).map(r => 'RFQ #' + r.rfq_no).join(','));

  // §8 — the reference has to be ON THE WIRE, not only in the column. my_inquiries is the payload
  // the customer's request list is built from, and it selected an explicit column list that did
  // not include it.
  const eMine = await call('customer_api', cust.jwt, { action: 'my_inquiries' });
  ok('endpoint customer_api/my_inquiries: 200', eMine.status === 200, `HTTP ${eMine.status} ${eMine.text.slice(0, 80)}`);
  ok('endpoint customer_api/my_inquiries: every RFQ carries rfq_no',
     (eMine.json?.inquiries || []).length === 3 && eMine.json.inquiries.every(i => Number(i.rfq_no) > 0),
     (eMine.json?.inquiries || []).map(i => 'RFQ #' + i.rfq_no).join(','));

  const eDetNoDate = await call('project_api', cust.jwt, { action: 'detail', id: noTarget });
  ok('endpoint project_api/detail: no deadline gives timeline_pct null, not 0',
     eDetNoDate.json?.timeline_pct === null, `timeline_pct=${JSON.stringify(eDetNoDate.json?.timeline_pct)}`);

} finally {
  // Teardown by captured id, FK order, never by pattern.
  const del = async (sql) => { try { await w(sql, 'teardown'); } catch (e) { console.log('  teardown: ' + String(e.message || e).slice(0, 120)); } };
  if (ids.customer) {
    await del(`delete from public.reviews where customer_id = ${q(ids.customer)}`);
    await del(`delete from public.transactions where customer_id = ${q(ids.customer)}`);
    await del(`delete from public.inquiry_matches where inquiry_id in
                 (select id from public.inquiries where customer_id = ${q(ids.customer)})`);
    await del(`delete from public.quotes where inquiry_id in
                 (select id from public.inquiries where customer_id = ${q(ids.customer)})`);
    await del(`delete from public.inquiries where customer_id = ${q(ids.customer)}`);
    await del(`delete from public.projects where customer_id = ${q(ids.customer)}`);
    // The customers row itself is withRun's to remove — it also owns the auth user and the
    // notifications / customer_preference rows that reference it, and deleting it here first
    // raised 23503 on every run.
  }
  if (ids.leads.length) {
    await del(`delete from public.supplier_score where lead_id in (${ids.leads.map(num).join(',')})`);
    await del(`delete from public.leads where id in (${ids.leads.map(num).join(',')}) and source = 'qd_row4_verify'`);
  }
  console.log(`\n${pass} passed, ${fail} failed\n`);
  process.exitCode = fail ? 1 : 0;
}
}, { tag: 'row4int', quiet: false });
