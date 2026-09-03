// rehearse_stripe_test_payment.mjs — A REAL STRIPE TEST-MODE PAYMENT, END TO END (3 Sep 2026).
//
// rehearse_full_funnel.mjs proves the reveal with a SYNTHETIC completion event. This closes the last
// gap on the money path with a real one: the demo objects are seeded and KEPT, a Checkout Session is
// created in the Stripe sandbox (the founder's "QuotesDone sandbox" account) with exactly the metadata
// stripe_checkout sets, a test card pays it in a browser, Stripe signs and delivers
// checkout.session.completed to the platform's webhook through the sandbox endpoint, and the platform
// records the reveal. Then this script verifies and tears the fixtures down.
//
//   QD_FIXTURES=1 node scripts/staging/rehearse_stripe_test_payment.mjs seed      -> prints the ids and the fee
//   (create the session in the sandbox with those ids, pay it with 4242 4242 4242 4242)
//   QD_FIXTURES=1 node scripts/staging/rehearse_stripe_test_payment.mjs verify <tag> <quote_id> <session_id>
import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, teardown, newRun, REF, q } from './demo_factory.mjs';
import { mgmtRead, mgmtFixture } from './qd_guard.mjs';

if (process.env.QD_FIXTURES !== '1') { console.error('refusing: set QD_FIXTURES=1'); process.exit(2); }
const [mode, tagArg, quoteArg, sessionArg] = process.argv.slice(2);
const read = (s) => mgmtRead(REF, s);

if (mode === 'seed') {
  await withRun(async (run) => {
    await mgmtFixture(REF, `insert into public.rehearsal_window (run_tag, opened_by) values ('qd_run:${run.tag}', 'rehearse_stripe_test_payment')`, 'rehearsal window');
    const cust = await makeCustomer(run, { mode: 'sql' });
    const sup = await makeSupplier(run, { trade: 'aluminium', variant: 0, variants: 1 });
    const inq = await makeInquiry(run, { customer: cust, trade: 'aluminium', status: 'sent' });
    const quote = await makeQuote(run, { inquiry: inq, supplier: sup, amount: 118000 });
    const pc = (await read('select standard_reveal_rate rate, standard_reveal_cap cap from public.pricing_config where id=1'))[0];
    const fee = Math.min(Math.round(118000 * Number(pc.rate) * 100) / 100, Number(pc.cap));
    console.log(JSON.stringify({ tag: run.tag, quote_id: quote.id, inquiry_id: inq.id, customer_id: cust.customerId, supplier_id: sup.leadId, quote_amount: 118000, reveal_fee: fee, fee_fils: Math.round(fee * 100) }));
  }, { keep: true, quiet: true });
} else if (mode === 'verify') {
  const tag = tagArg, quoteId = quoteArg, sessionId = sessionArg;
  const results = [];
  const ok = (n, p, d) => { results.push(p); console.log(`${p ? 'PASS' : 'FAIL'} ${n.padEnd(60)} ${d}`); };
  try {
    const tx = (await read(`select fee_status, reveal_fee, payment_ref, paid_by from public.transactions where quote_id=${q(quoteId)}`))[0];
    ok('a transaction was recorded by the webhook from a REAL Stripe event', !!tx && tx.fee_status === 'paid' && String(tx.payment_ref || '').startsWith('pi_'), JSON.stringify(tx));
    const st = (await read(`select (select status from public.quotes where id=${q(quoteId)}) qs, (select status from public.inquiries where id=(select inquiry_id from public.quotes where id=${q(quoteId)})) is`))[0];
    ok('quote and inquiry are marked revealed', st?.qs === 'revealed' && st?.is === 'revealed', JSON.stringify(st));
    const notes = await read(`select type, to_role, coalesce(channel,'email') channel from public.notifications where quote_id=${q(quoteId)} order by created_at`);
    ok('both parties queued on email (WhatsApp only with opt-in)', notes.some((n) => n.to_role === 'customer') && notes.some((n) => n.to_role === 'supplier'), notes.map((n) => n.type + '/' + n.to_role + '/' + n.channel).join(', ') || 'none');
    const wh = (await read(`select status, counts->>'reveal_fee' fee, left(note,100) note, started_at from public.agent_runs where agent='stripe_webhook' order by started_at desc limit 1`))[0];
    ok('the webhook run row says ok', wh?.status === 'ok', JSON.stringify(wh));
    const sess = (await read(`select count(*)::int c from public.transactions where quote_id=${q(quoteId)}`))[0].c;
    ok('exactly one transaction (idempotent on redelivery)', sess === 1, `transactions=${sess} (session ${sessionId})`);
  } finally {
    const run = newRun({ tag, quiet: true });
    const t = await teardown(run);
    await mgmtFixture(REF, `update public.rehearsal_window set ended_at = now() where run_tag = 'qd_run:${tag}' and ended_at is null`, 'rehearsal window');
    console.log('torn down:', t.summary);
  }
  const passed = results.filter(Boolean).length; console.log(`${passed}/${results.length} passed`); process.exit(passed === results.length ? 0 : 1);
} else { console.error('usage: seed | verify <tag> <quote_id> <session_id>'); process.exit(2); }
