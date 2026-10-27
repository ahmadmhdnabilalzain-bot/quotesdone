// scripts/e2e/mystery_shopper.mjs — THE IT ENGINEER'S DAILY MYSTERY SHOPPER (founder ruling 1209, 13 Oct 2026).
// Assigned: it_engineer. Run once a day by .github/workflows/mystery-shopper.yml.
//
// One ZZ DEMO customer (@example.invalid, demo-flagged, never billed) runs one whole request through production:
//   signup      kyc save_customer + the e-mail OTP + the WhatsApp choice + accept_terms (fixtures makeDemoCustomer, the nightly's own sign-up: no model)
//   suppliers   two ZZ DEMO aluminium suppliers, the mandatory six completed and approved by the sales engineer's own
//               verification (demo_factory makeSupplier 'sql': no model)
//   intake      an rfq_ready request (demo_factory makeInquiry 'sql', the fixture path: the interview is a model)
//   matching    fn_match_capability, the matcher's SQL core, on the request's own trades, need and emirate; it must find
//               BOTH run suppliers, and only they are written to inquiry_matches (demo pairs with demo only)
//   quote       two complete quotes (demo_factory makeQuote 'sql')
//   comparison  quote_compare as the customer, on the real model (ruling 1260, 19 Oct 2026: "all tests need to be done
//               with AI. from now on open router stays on"): the call carries the run tag, so the model call is let
//               through inside the run's rehearsal window and costed against it. The report must list both quotes, be
//               the model's (a deterministic fallback, degraded, is the finding) and rank a top 3 or hold it for review
//   cleanup     the run's own teardown by its tag, then every table counted by the run's handles must read 0
// Every broken step is handed to public.fn_it_engineer_mystery_shopper_ingest, which files an IT finding naming the step
// and the error (and closes the step's finding when it passes again) and writes the heartbeat the IT engineer's
// it_engineer.mystery_shopper_heartbeat duty reads. A step after a broken one is SKIPPED, never guessed.
//
// INCAPABLE OF REACHING A REAL PERSON: it refuses to start without the demo capture and the demo/real pairing guards
// (the same preflight as scripts/e2e/run.mjs), every identity is qd-<tag>-*@example.invalid or the reserved
// +971 50 000 00xx block, it opens a rehearsal window, and it never reveals or pays, so no customer is ever charged.
// The one paid call is the comparison's model, tagged with the run and inside its window (ruling 1260).
//
//   node scripts/e2e/mystery_shopper.mjs                 the daily run (reports to the IT engineer)
//   node scripts/e2e/mystery_shopper.mjs --no-report     run and print, report nothing
//   node scripts/e2e/mystery_shopper.mjs --until quote   stop before the comparison (no quote_compare call)
process.env.QD_FIXTURES = '1';
const { openRun, closeRun, makeDemoCustomer, read, write, REF } = await import('./fixtures.mjs');
const { makeSupplier, makeInquiry, makeQuote, call, q } = await import('../lib/demo_factory.mjs');
const { sql, lit } = await import('../lib/db.mjs');

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const NO_REPORT = argv.includes('--no-report');
export const STEPS = ['preflight', 'signup', 'suppliers', 'intake', 'matching', 'quote', 'comparison', 'cleanup'];
const UNTIL = val('--until');
if (UNTIL && !STEPS.includes(UNTIL)) { console.error(`--until must be one of ${STEPS.join(', ')}`); process.exit(2); }

const steps = [];
let broken = null;
async function step(name, fn) {
  if (UNTIL && STEPS.indexOf(name) > STEPS.indexOf(UNTIL) && name !== 'cleanup') {
    steps.push({ step: name, status: 'SKIP', error: `not run (--until ${UNTIL})` });
    return null;
  }
  if (broken && name !== 'cleanup') {
    steps.push({ step: name, status: 'SKIP', error: `not run: ${broken} broke first` });
    return null;
  }
  try {
    const detail = await fn();
    steps.push({ step: name, status: 'PASS', detail: String(detail ?? '').slice(0, 600) });
    console.log(`PASS ${name} — ${String(detail ?? '').slice(0, 200)}`);
    return true;
  } catch (e) {
    broken = broken || name;
    const error = String(e?.message || e).slice(0, 600);
    steps.push({ step: name, status: 'FAIL', error });
    console.log(`FAIL ${name} — ${error}`);
    return false;
  }
}
const must = (ok, msg) => { if (!ok) throw new Error(msg); };

// ---- preflight: nothing this run does may reach a real person ---------------------------------------
await step('preflight', async () => {
  const g = (await read(`select tgname from pg_trigger where not tgisinternal and tgname in
    ('zzzz_notifications_demo_capture','a01_inquiry_match_demo_and_real_never_pair','a01_quote_demo_and_real_never_pair')`)).map((r) => r.tgname);
  must(g.length === 3, `the demo guards are not installed on ${REF} (found ${g.join(', ') || 'none'}): refusing to run`);
  return `demo capture and pairing guards present on ${REF}`;
});
if (broken) { await report(null); process.exit(1); }

const run = await openRun();
const fx = {};
try {
  await step('signup', async () => {
    fx.cust = await makeDemoCustomer(run, { label: 'Mystery Shopper', locale: 'en' });
    const c = (await read(`select email_verified, tos_accepted_at is not null tos, public.fn_is_demo_email(email) demo
                             from public.customers where id = ${q(fx.cust.customerId)}`))[0];
    must(c, 'no customers row after sign-up');
    must(c.demo === true, 'the shopper is not on a demo address');
    must(c.email_verified === true, 'the e-mail OTP did not verify the address');
    must(c.tos === true, 'the customer terms were not accepted');
    return `${fx.cust.email}: verified, terms accepted`;
  });

  await step('suppliers', async () => {
    fx.sups = [];
    for (const label of ['A', 'B']) {
      const s = await makeSupplier(run, { trade: 'aluminium', company_name: `ZZ DEMO Mystery Supplier ${label} ${run.tag}`,
                                          coverage_emirates: ['Dubai'], services: 'all' });
      run.ids.leads.add(String(s.leadId));
      fx.sups.push(s);
    }
    const rows = await read(`select id, approval_status, is_demo from public.leads where id in (${fx.sups.map((s) => Number(s.leadId)).join(',')})`);
    must(rows.length === 2 && rows.every((r) => r.approval_status === 'approved' && r.is_demo), `suppliers not approved demo: ${JSON.stringify(rows)}`);
    return `2 ZZ DEMO aluminium suppliers approved (${rows.map((r) => r.id).join(', ')})`;
  });

  await step('intake', async () => {
    fx.inq = await makeInquiry(run, { customer: fx.cust, trade: 'aluminium', emirate: 'Dubai', locale: 'en' });
    run.ids.inquiries.add(String(fx.inq.id));
    const i = (await read(`select rfq_ready, public.fn_inquiry_is_demo(id) demo from public.inquiries where id = ${q(fx.inq.id)}`))[0];
    must(i?.rfq_ready === true, 'the request is not rfq_ready');
    must(i?.demo === true, 'the request is not marked demo');
    return `request ${fx.inq.id} rfq_ready`;
  });

  await step('matching', async () => {
    const mine = fx.sups.map((s) => Number(s.leadId));
    const cand = (await read(`select m.supplier_id from public.inquiries i,
        public.fn_match_capability(public.fn_taxonomy_trades_for(i.trades), coalesce(nullif(i.role_needed, ''), 'executes'),
                                   '{}'::text[], '{}'::text[], i.scope_type, null, i.emirate, 100000) m
       where i.id = ${q(fx.inq.id)}`)).map((r) => Number(r.supplier_id));
    const found = mine.filter((id) => cand.includes(id));
    must(found.length === mine.length, `the matcher found ${found.length} of the run's ${mine.length} exact-trade suppliers (candidates: ${cand.length})`);
    await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason)
                 select ${q(fx.inq.id)}, x, 'mystery shopper (fn_match_capability)' from unnest(array[${mine.join(',')}]::bigint[]) x
                 on conflict (inquiry_id, supplier_id) do nothing`, 'mystery shopper matches');
    const m = await read(`select m.supplier_id, l.is_demo from public.inquiry_matches m join public.leads l on l.id = m.supplier_id
                           where m.inquiry_id = ${q(fx.inq.id)}`);
    must(m.length === mine.length && m.every((r) => r.is_demo), `matches landed: ${JSON.stringify(m)}`);
    return `${m.length} ZZ DEMO suppliers matched (of ${cand.length} candidates)`;
  });

  await step('quote', async () => {
    fx.quotes = [];
    for (const [i, s] of fx.sups.entries()) {
      const qt = await makeQuote(run, { inquiry: fx.inq, supplier: s, amount: [118500, 124900][i], notes: `ZZ DEMO mystery quote ${i + 1}` });
      must(qt.id, `supplier ${s.leadId}: no quote row`);
      // A COMPLETE QUOTE as fn_quote_quality_gate judges it (measured 13 Oct 2026: without these it stays a draft): a priced
      // line stating every spec of one aluminium checklist (trade_spec_checklist, read, not hard-coded) and a VAT basis.
      const amt = [118500, 124900][i];
      await write(`insert into public.quote_items (quote_id, line_no, description, qty, unit, unit_price, amount, spec)
                   select ${q(qt.id)}, 1, 'Supply and installation as specified', 40, 'nr', ${amt / 40}, ${amt},
                          coalesce((select jsonb_object_agg(s->>'code', 'ZZ DEMO stated: ' || coalesce(s->>'label_en', s->>'code'))
                                      from (select c.specs from public.trade_spec_checklist c
                                             where c.trade_code = 'aluminium' or c.trade_code = any(public.fn_taxonomy_trades_for(array['aluminium']))
                                             order by c.topic_id limit 1) l, jsonb_array_elements(l.specs) s), '{}'::jsonb);
                   update public.quotes set vat_treatment = 'exclusive', status = 'submitted' where id = ${q(qt.id)}`, 'mystery shopper quote line');
      run.ids.quotes.add(String(qt.id));
      fx.quotes.push(qt);
    }
    const st = await read(`select status from public.quotes where inquiry_id = ${q(fx.inq.id)}`);
    must(st.length === 2 && st.every((r) => r.status === 'submitted'), `quotes: ${JSON.stringify(st)}; holds: ${JSON.stringify(await read(`select h.flags from public.quote_quality_hold h join public.quotes x on x.id = h.quote_id where x.inquiry_id = ${q(fx.inq.id)}`))}`);
    return '2 complete quotes submitted';
  });

  await step('comparison', async () => {
    must(process.env.QD_E2E_RUN_TAG === run.tag, 'the run tag is not set, so the model call would be refused as untagged test traffic');
    const r = await call('quote_compare', fx.cust.jwt, { inquiry_id: fx.inq.id, lang: 'en' }, 180000);
    must(r.status === 200 && r.json?.ok === true, `quote_compare HTTP ${r.status} ${String(r.text).slice(0, 300)}`);
    // A model failure still answers 200 with the deterministic ranking and degraded: true. For the customer that is a
    // safe fallback; for the shopper it is the broken step, with the model's own detail as the error.
    must(r.json.degraded !== true, `the model did not write the comparison (degraded: ${String(r.json.detail ?? '').slice(0, 300)})`);
    const a = r.json.analysis || {};
    must(Array.isArray(a.all_quotes) && a.all_quotes.length === 2, `the report lists ${a.all_quotes?.length ?? 0} of 2 quotes`);
    // Both quotes exceed the large-choice threshold, so the second seat may hold the recommendation for review: that
    // is the product working, and it must say so (on_review with its second_seat record), never an empty ranking.
    must((Array.isArray(a.top3) && a.top3.length >= 1) || (a.on_review === true && a.second_seat), 'the report ranks no quote and holds none for review');
    return `comparison report by the model: ${a.all_quotes.length} quotes listed, ${a.on_review ? 'recommendation held for second-seat review' : `top ${a.top3.length} ranked`}`;
  });
} finally {
  let closed = null;
  await step('cleanup', async () => {
    closed = await closeRun(run);
    must(closed.leftovers && closed.leftovers.total === 0, `leftovers after teardown: ${JSON.stringify(closed.leftovers)}`);
    return `removed: ${closed.removed?.summary ?? '?'}; leftovers 0`;
  });
  await report(run.tag);
}

async function report(tag) {
  const out = { tag: tag || 'preflight', steps };
  console.log(JSON.stringify(out, null, 1));
  if (NO_REPORT) return;
  const [r] = await sql(`select public.fn_it_engineer_mystery_shopper_ingest(${lit(JSON.stringify(out))}::jsonb) r`);
  console.log('reported to the IT engineer:', JSON.stringify(r.r));
  if (steps.some((s) => s.status === 'FAIL')) process.exitCode = 1;
}
