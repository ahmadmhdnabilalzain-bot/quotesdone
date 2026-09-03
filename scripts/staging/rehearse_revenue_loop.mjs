// rehearse_revenue_loop.mjs — the SANDBOX REVENUE-LOOP REHEARSAL, on committed data, torn down after.
//
// demo_factory's selftest proves the funnel through quotes. This drives the links after it — the ones
// that make money — against the one project, inside withRun() so every row is removed on the way out:
//   confirmed suppliers -> customer -> inquiry (emits rfq.created, the event rfq_handling now waits on)
//   -> matching returns them -> 4 quotes -> quote_compare shortlists the best 3 (deterministic while the
//   model is held) -> reveal records the 3% fee read from pricing_config.
//
//   QD_FIXTURES=1 node scripts/staging/rehearse_revenue_loop.mjs
import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, makeReveal, call,
         REF, q, num, snapshot, diffSnapshots } from './demo_factory.mjs';
import { mgmtRead } from './qd_guard.mjs';

const checks = [];
const ok = (name, pass, detail) => { checks.push(pass); console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(52)} ${detail}`); };

const before = await snapshot();
await withRun(async (run) => {
  const cust = await makeCustomer(run, { mode: 'sql' });
  const sups = [];
  for (let v = 0; v < 4; v++) sups.push(await makeSupplier(run, { trade: 'aluminium', variant: v, variants: 4 }));
  ok('4 confirmed suppliers stood up', sups.every((s) => s.leadId && s.jwt), sups.map((s) => s.leadId).join(','));

  const inq = await makeInquiry(run, { customer: cust, trade: 'aluminium', status: 'sent' });
  const ready = (await mgmtRead(REF, `select rfq_ready from public.inquiries where id=${q(inq.id)}`))[0]?.rfq_ready;
  ok('inquiry is rfq_ready', ready === true, `id=${inq.id}`);

  // THE REVENUE-LOOP ENTRY (rewired 3 Sep): an inquiry emits rfq.created, and rfq_handling waits on it.
  const ev = (await mgmtRead(REF, `select count(*)::int c from public.company_event where entity_id=${q(inq.id)} and event_type='rfq.created'`))[0]?.c;
  const trig = (await mgmtRead(REF, `select trigger_event from public.workflow where workflow_key='rfq_handling'`))[0]?.trigger_event;
  ok('inquiry emitted rfq.created', Number(ev) >= 1, `events=${ev}`);
  ok('rfq_handling waits on that exact event', trig === 'rfq.created', `trigger_event=${trig}`);

  // MATCHING: the real capability matcher returns the demo suppliers for the inquiry's trade.
  const ids = sups.map((s) => s.leadId).join(',');
  const m = await mgmtRead(REF, `select count(*)::int c from public.fn_match_capability(ARRAY['aluminium']::text[],'executes','{}'::text[],'{}'::text[],null,150000,null,50) where supplier_id in (${ids})`);
  ok('matching returns >=3 of the 4 (enough for best-3)', Number(m[0]?.c) >= 3, `matched=${m[0]?.c}`);

  // QUOTES: four comparable, different amounts.
  const amounts = [125000, 131750, 118000, 140000];
  const quotes = [];
  for (let i = 0; i < 4; i++) quotes.push(await makeQuote(run, { inquiry: inq, supplier: sups[i], amount: amounts[i] }));
  ok('4 quotes submitted', quotes.every((x) => x.id && x.status === 'submitted'), quotes.map((x) => x.amount).join('/'));

  // COMPARE: best 3 of 4. With the paid provider held this is the deterministic shortlist — served, not refused.
  const execCred = (await mgmtRead(REF, "select value from public.app_secrets where key='cred_fn_cos_execute'"))[0]?.value;
  const cmp = await call('quote_compare', null, { __secret: execCred, inquiry_id: inq.id }, 120000);
  const a = cmp.json?.analysis || {};
  ok('quote_compare answers 200 ok', cmp.status === 200 && cmp.json?.ok === true, `HTTP ${cmp.status} ${cmp.json?.error || ''} ${cmp.text.slice(0, 80)}`);
  ok('shortlists the best 3 of 4', Array.isArray(a.top3) && a.top3.length === 3 && Number(a.considered) === 4,
     `top3=${a.top3?.length ?? '-'} considered=${a.considered ?? '-'} degraded=${cmp.json?.degraded === true} labels=${(a.top3 || []).map((t) => t.label).join('|')}`);
  ok('ranked #1 has a stated reason', !!(a.top3?.[0]?.why), `#1=${a.top3?.[0]?.label ?? '-'}: ${String(a.top3?.[0]?.why || '').slice(0, 70)}`);

  // REVEAL + THE 3% FEE, from the live pricing_config (no hardcoded rate).
  const pc = (await mgmtRead(REF, `select standard_reveal_rate rate, standard_reveal_cap cap from public.pricing_config where id=1`))[0];
  const chosen = quotes[2]; // the AED 118,000 quote
  const fee = Math.min(Math.round(Number(chosen.amount) * Number(pc.rate) * 100) / 100, Number(pc.cap));
  const rev = await makeReveal(run, { quote: chosen, inquiry: inq, supplier: sups[2], customer: cust, reveal_fee: fee });
  const tx = (await mgmtRead(REF, `select quote_amount, reveal_fee, fee_status from public.transactions where quote_id=${q(chosen.id)} and inquiry_id=${q(inq.id)} order by id desc limit 1`))[0] || {};
  ok('reveal fee is 3% of the chosen quote', Number(tx.reveal_fee) === fee && Math.abs(Number(tx.reveal_fee) - Number(tx.quote_amount) * 0.03) < 0.005,
     `quote=${tx.quote_amount} fee=${tx.reveal_fee} rate=${pc.rate} status=${tx.fee_status}`);
});
const after = await snapshot();
const drift = diffSnapshots(before, after);
console.log(`baseline drift after teardown: ${drift.length ? drift.map((d) => `${d.t} ${d.before}->${d.after}`).join(', ') : 'none'}`);
const fails = checks.filter((c) => !c).length;
console.log(`\n${fails ? 'FAIL' : 'PASS'} — ${checks.length - fails}/${checks.length} revenue-loop checks passed`);
process.exit(fails ? 1 : 0);
