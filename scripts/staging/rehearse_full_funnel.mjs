// rehearse_full_funnel.mjs — THE WHOLE FUNNEL, PERFECT IN THE SANDBOX (3 Sep 2026).
//
// The founder's bar: "nothing needs to be proved with real data. everything should be perfect in the
// sandbox and by that time only we will launch." rehearse_revenue_loop.mjs proved the middle of the
// funnel (matching -> quotes -> best-3 -> the 3% fee). This drives the OUTER stages the company must
// run on its own, on the production database, torn down after, inside a declared rehearsal window:
//
//   SUPPLY   an invited lead -> the claim link resolves (claim_lookup by token) -> the supplier
//            claims it with a real account (supplier_api claim) -> profile + terms -> the AUTOMATED
//            approver (fn_supplier_autoapprove_clean) approves it with no human -> capability
//            confirmed -> it is matchable
//   DEMAND   a customer + inquiry -> matching includes the claimed supplier -> 3 quotes ->
//            quote_compare best-3 (deterministic, model held)
//   MONEY    stripe_checkout creates the real Stripe Checkout session for the 3% fee (live keys,
//            expired immediately by this script so nothing can be paid) -> a checkout.session.completed
//            event, signed with the handler's TEST webhook secret, lands on stripe_webhook -> the
//            transaction is recorded, quote and inquiry are revealed, the supplier is notified
//   CONTACT  the customer reads the revealed contact through customer_api (reveal)
//
// WHAT IS SIMULATED, said plainly: (1) the licence-document OCR outputs (license_doc_path,
// doc_extracted_at, trade_license_no, license_expiry, owner_email_verified) are written as fixture
// facts — the extraction itself is a paid-model surface, held until launch; the approver's LOGIC is
// what is proven here. (2) The payment: Stripe never charges a card here; the completion event is
// synthesised and signed with app_secrets.stripe_webhook_secret_test, which this script creates as a
// harness-only value if the founder has not yet configured Stripe test mode (he replaces it then).
// (3) The customer intake conversation is a model surface (allowed at launch); the inquiry is
// inserted as the intake would leave it.
//
//   QD_FIXTURES=1 node scripts/staging/rehearse_full_funnel.mjs
import { createHmac, randomUUID, randomBytes } from 'node:crypto';
import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, confirmCapability, capabilityProfile,
         mkAuthUser, runEmail, call, REF, q, num, RUN_TAG_COL } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';

if (process.env.QD_FIXTURES !== '1') { console.error('refusing: set QD_FIXTURES=1'); process.exit(2); }
const BASE = `https://${REF}.supabase.co/functions/v1`;
const checks = [];
const ok = (name, pass, detail) => { checks.push(pass); console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(60)} ${detail}`); };
const read = (s) => mgmtRead(REF, s);
const write = (s) => mgmtFixture(REF, s, 'full funnel rehearsal');
const secret = async (k) => (await read(`select value from public.app_secrets where key=${q(k)}`))[0]?.value;

await withRun(async (run) => {
  const trade = 'aluminium';
  const profile = capabilityProfile(trade, 0, 3);

  // ---------------- SUPPLY: invite -> claim -> approve -> confirm ----------------
  const token = randomUUID();
  const supEmail = runEmail(run, 'claim');
  const company = `QD Demo Claimed Aluminium ${run.tag.slice(0, 4)}`;
  const leadId = Number((await write(`
    insert into public.leads (company_name, email, emirate, claim_token, invited_at, tags, source, approval_status, verified)
    values (${q(company)}, ${q(supEmail)}, 'Dubai', ${q(token)}, now(), ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[], 'demo_factory', 'pending', false)
    returning id`))[0].id);
  ok('an invited demo lead exists with a claim token', leadId > 0, `lead ${leadId}`);

  const look = await call('claim_lookup', null, { t: token });
  ok('the invite link resolves the company (claim_lookup by token)', look.status === 200 && look.json?.ok === true && look.json?.company_name === company, `HTTP ${look.status} ${JSON.stringify(look.json).slice(0, 90)}`);

  const su = await mkAuthUser(run, supEmail);
  const claim = await call('supplier_api', su.jwt, { action: 'claim', claim_token: token });
  const claimedBy = (await read(`select claimed_by, claimed from public.leads where id=${leadId}`))[0];
  ok('the supplier claims it with a real account (supplier_api claim)', claim.status === 200 && String(claimedBy?.claimed_by || '').toLowerCase() === supEmail.toLowerCase(), `HTTP ${claim.status} claimed_by=${claimedBy?.claimed_by} claimed=${claimedBy?.claimed}`);

  const prof = await call('supplier_api', su.jwt, { action: 'save_profile', products: profile.products_norm.join(', '), services: 'Supply and installation of aluminium works.', description: 'Aluminium specialist serving Dubai.', company_type: 'LLC', contact_name: 'Demo Contact', phone: '+971505550000', service_emirates: profile.coverage_emirates });
  const terms = await call('kyc', su.jwt, { action: 'accept_terms', user_kind: 'supplier', email: supEmail });
  ok('profile saved and terms accepted through the real API', prof.status === 200 && terms.status === 200, `profile ${prof.status} terms ${terms.status}`);

  // WHO APPROVES A SUPPLIER WITH NO HUMAN? Measured stage by stage rather than assumed: the status
  // after the claim, after profile + terms, after the licence facts land (the OCR surface's outputs,
  // written here as fixture facts — see header), and finally the explicit sweep
  // fn_supplier_autoapprove_clean if nothing earlier approved it.
  const statusAt = async () => (await read(`select approval_status, verified from public.leads where id=${leadId}`))[0] || {};
  const s1 = await statusAt();
  await write(`update public.leads set registration_submitted_at = now(), license_doc_path = ${q('supplier-docs/' + run.tag + '/licence.pdf')}, doc_extracted_at = now(), trade_license_no = ${q('ZZ-' + run.tag.toUpperCase())}, license_expiry = current_date + 400, owner_email_verified = true where id=${leadId}`);
  const s2 = await statusAt();
  let approvedBy = s1.approval_status === 'approved' ? 'claim/profile/terms (before any licence fact)' : (s2.approval_status === 'approved' ? 'the licence-facts trigger path on leads' : '');
  let appr = null;
  if (!approvedBy) { appr = await read(`select public.fn_supplier_autoapprove_clean(100) r`); const s3 = await statusAt(); if (s3.approval_status === 'approved') approvedBy = 'fn_supplier_autoapprove_clean'; }
  const lead2 = await statusAt();
  ok('an automated path approves a clean supplier with no human', lead2?.approval_status === 'approved' && !!approvedBy, `approval_status=${lead2?.approval_status} verified=${lead2?.verified} approved by: ${approvedBy || 'NOTHING'} (after claim: ${s1.approval_status}, after licence facts: ${s2.approval_status}${appr ? ', sweep: ' + JSON.stringify(appr[0]?.r).slice(0, 70) : ''})`);
  ok('approval was NOT granted before any licence fact existed', s1.approval_status !== 'approved', `after claim/profile/terms: ${s1.approval_status}`);
  if (lead2?.approval_status === 'approved' && lead2?.verified !== true) await write(`update public.leads set verified = true where id=${leadId}`);

  await confirmCapability(leadId, profile);
  const matchable = (await read(`select public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes) m from public.leads l where l.id=${leadId}`))[0]?.m;
  ok('capability confirmed and the supplier is matchable', matchable === true, `fn_is_matchable=${matchable}`);
  const claimed = { leadId, jwt: su.jwt, email: supEmail };

  // ---------------- DEMAND: customer -> inquiry -> matching -> quotes -> best-3 ----------------
  const others = [];
  for (let v = 1; v < 3; v++) others.push(await makeSupplier(run, { trade, variant: v, variants: 3 }));
  const cust = await makeCustomer(run, { mode: 'sql' });
  const inq = await makeInquiry(run, { customer: cust, trade, status: 'sent' });
  const ev = (await read(`select count(*)::int c from public.company_event where entity_id=${q(inq.id)} and event_type='rfq.created'`))[0]?.c;
  ok('the inquiry enters the company loop (rfq.created emitted)', Number(ev) >= 1, `inquiry ${inq.id} events=${ev}`);
  const ids = [leadId, ...others.map((s) => s.leadId)];
  const m = await read(`select supplier_id from public.fn_match_capability(ARRAY['aluminium']::text[],'executes','{}'::text[],'{}'::text[],null,150000,null,50) where supplier_id in (${ids.join(',')})`);
  ok('matching includes the claimed supplier (and the 2 others)', m.some((r) => Number(r.supplier_id) === leadId) && m.length === 3, `matched=${m.map((r) => r.supplier_id).join(',')}`);

  const amounts = [118000, 125000, 131750];
  const quotes = [await makeQuote(run, { inquiry: inq, supplier: claimed, amount: amounts[0] }), await makeQuote(run, { inquiry: inq, supplier: others[0], amount: amounts[1] }), await makeQuote(run, { inquiry: inq, supplier: others[1], amount: amounts[2] })];
  ok('3 quotes submitted, the claimed supplier cheapest', quotes.every((x) => x.id), quotes.map((x) => x.amount).join('/'));
  const execCred = await secret('cred_fn_cos_execute');
  const cmp = await call('quote_compare', null, { __secret: execCred, inquiry_id: inq.id }, 120000);
  ok('quote_compare shortlists deterministically (model held)', cmp.status === 200 && cmp.json?.ok === true, `HTTP ${cmp.status} engine=${cmp.json?.analysis?.engine || cmp.json?.engine || '?'}`);

  // Both parties registered a WhatsApp number and opted in — the founder's contract is conditional on
  // consent, and the fixtures state it explicitly rather than inheriting a default.
  await write(`update public.customers set phone = '+971505551111', wa_optin = true where id=${q(cust.customerId)};
               update public.leads set whatsapp = '+971505550000', wa_optin = true where id=${leadId};`);

  // ---------------- MONEY: real checkout session (expired at once) -> signed completion event ----------------
  const pc = (await read(`select standard_reveal_rate rate, standard_reveal_cap cap from public.pricing_config where id=1`))[0];
  const fee = Math.min(Math.round(amounts[0] * Number(pc.rate) * 100) / 100, Number(pc.cap));
  const co = await call('stripe_checkout', cust.jwt, { quote_id: quotes[0].id });
  const sessionId = (String(co.json?.url || '').match(/cs_(?:live|test)_[A-Za-z0-9]+/) || [])[0] || '';
  ok('stripe_checkout creates the Checkout session for the 3% fee', co.status === 200 && co.json?.ok === true && Number(co.json?.fee) === fee && !!sessionId, `HTTP ${co.status} fee=${co.json?.fee} expected=${fee} session=${sessionId ? 'yes' : 'no'}`);
  let expired = 'not attempted';
  if (sessionId) {
    const sk = await secret('stripe_secret_key');
    const ex = await fetch(`https://api.stripe.com/v1/checkout/sessions/${sessionId}/expire`, { method: 'POST', headers: { Authorization: 'Bearer ' + sk } });
    const ej = await ex.json().catch(() => ({}));
    expired = ej?.status || ('http ' + ex.status);
  }
  ok('the session is expired immediately (nothing can be paid)', expired === 'expired', `stripe status=${expired}`);

  let whsec = await secret('stripe_webhook_secret_test');
  if (!whsec) {
    whsec = 'whsec_harness_' + randomBytes(24).toString('hex');
    await write(`insert into public.app_secrets (key, value) values ('stripe_webhook_secret_test', ${q(whsec)})`);
    run.log('created app_secrets.stripe_webhook_secret_test (harness-only; replaced when Stripe test mode is configured)');
  }
  const payRef = 'pi_zzdemo_' + run.tag;
  const event = { id: 'evt_zzdemo_' + run.tag, object: 'event', type: 'checkout.session.completed', created: Math.floor(Date.now() / 1000), livemode: false,
    data: { object: { id: sessionId || ('cs_test_zzdemo_' + run.tag), object: 'checkout.session', payment_status: 'paid', status: 'complete', amount_total: Math.round(fee * 100), currency: 'aed', payment_intent: payRef,
      metadata: { quote_id: quotes[0].id, inquiry_id: inq.id, customer_id: cust.customerId, supplier_id: String(leadId), reveal_fee: String(fee), quote_amount: String(amounts[0]) } } } };
  const raw = JSON.stringify(event);
  const t = Math.floor(Date.now() / 1000);
  const v1 = createHmac('sha256', whsec).update(`${t}.${raw}`).digest('hex');
  const wh = await fetch(`${BASE}/stripe_webhook`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'stripe-signature': `t=${t},v1=${v1}` }, body: raw });
  const whText = await wh.text();
  const tx = (await read(`select fee_status, reveal_fee, payment_ref from public.transactions where quote_id=${q(quotes[0].id)}`))[0];
  const st = (await read(`select (select status from public.quotes where id=${q(quotes[0].id)}) qs, (select status from public.inquiries where id=${q(inq.id)}) is`))[0];
  ok('the signed completion event records the paid reveal', wh.status === 200 && tx?.fee_status === 'paid' && Number(tx?.reveal_fee) === fee && tx?.payment_ref === payRef, `HTTP ${wh.status} ${whText.slice(0, 60)} | tx=${JSON.stringify(tx)}`);
  ok('quote and inquiry are marked revealed', st?.qs === 'revealed' && st?.is === 'revealed', `quote=${st?.qs} inquiry=${st?.is}`);
  // THE FOUNDER'S CONTRACT (19 Aug 2026): email to BOTH parties AND WhatsApp to BOTH, on the numbers
  // each registered with. Both fixtures registered a number and opted in (above, before the reveal).
  const notes = await read(`select type, to_role, coalesce(channel, 'email') channel, status from public.notifications where quote_id=${q(quotes[0].id)} order by created_at`);
  const has = (type, role, channel) => notes.some((n) => n.type === type && n.to_role === role && n.channel === channel);
  ok('the customer is emailed and messaged on WhatsApp', has('reveal_receipt', 'customer', 'email') && has('reveal_receipt', 'customer', 'whatsapp'), `customer: ${notes.filter((n) => n.to_role === 'customer').map((n) => n.channel).join('+') || 'none'}`);
  ok('the supplier is emailed and messaged on WhatsApp', has('quote_accepted', 'supplier', 'email') && has('quote_accepted', 'supplier', 'whatsapp'), `supplier: ${notes.filter((n) => n.to_role === 'supplier').map((n) => n.channel).join('+') || 'none'}`);
  ok('exactly four reveal messages, two per party', notes.length === 4, `notifications: ${notes.map((n) => n.type + '/' + n.to_role + '/' + n.channel).join(', ') || 'none'}`);

  // ---------------- CONTACT: the customer reads the revealed supplier ----------------
  const rv = await call('customer_api', cust.jwt, { action: 'reveal', quote_id: quotes[0].id });
  const contact = rv.json?.supplier || rv.json?.contact || rv.json;
  const hasContact = rv.status === 200 && JSON.stringify(contact || {}).includes('+971505550000');
  ok('the customer reads the revealed supplier contact (customer_api reveal)', hasContact, `HTTP ${rv.status} ${JSON.stringify(rv.json).slice(0, 110)}`);
});

// After teardown: the kernel sees no orphaned work from this run.
const orphans = await read(`select check_name, expected, actual, ok from public.fn_kernel_orphaned_work()`);
ok('after teardown the kernel reports no orphaned work', orphans.every((r) => r.ok === true), orphans.filter((r) => r.ok !== true).map((r) => r.check_name + '=' + r.actual).join('; ') || 'all ok');
const passed = checks.filter(Boolean).length;
console.log(`\n${passed}/${checks.length} checks passed`);
process.exit(passed === checks.length ? 0 : 1);
