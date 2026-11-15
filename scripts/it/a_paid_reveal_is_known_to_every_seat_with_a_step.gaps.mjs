// A PAID REVEAL IS KNOWN TO EVERY SEAT WITH A STEP (it_engineer, 13 Nov 2026; founder_instruction 1685, 1687, 1688).
//
// The founder, 13 Nov 2026 (1685): "when the sales engineer is sharing a comparison report, then the customer ... paid the
// reveal fee, was the accountant aware that this is the invoice that we received? Is it kept in the books properly? Is the
// CEO aware that we made that sales? Is the sales engineer aware that the customer paid and now he closed this project
// totally, and now the accountant will start the timer from the day of payment for the refund window ...? Is the whole
// workflow tested this way?" (1687): "our reveal fee quotation should be excluding VAT 100%." (1688): "It's never like this
// agent is done with this task, he just sends an output and he doesn't know what happens after that."
//
// WHAT THIS CHECKS. One paid reveal, end to end, as a CHAIN (not unit by unit): every seat with a step was told and acted,
// the books entry exists and balances ex-VAT with no VAT line and names the invoice, the refund clock started at the
// payment time, the request was closed, the other suppliers were told, and somebody owns the follow-up.
//
// THREE SOURCES, the same assertions:
//   1. scripts/fixtures/zz_demo_paid_reveal_trace_2026-09-21.json: every row production holds for the ONE paid reveal it
//      keeps (transaction 29ac49f5, ZZ DEMO, Stripe test mode), captured read-only on 13 Nov 2026. Every rehearsal reveal
//      since (53 paid test invoices 10 Oct-12 Nov, accountant_reveal_reconcile_item) was torn down with its transaction,
//      so this is the only full trace there is.
//   2. The code on this branch: _shared/payment_handoffs.ts (the one list of money conversations, asserted equal to the
//      database by payments_are_the_accountant.test.mjs), _shared/reveal_sale.ts, _shared/reveal_fee_documents.ts and the
//      production mirror supabase/schema/full_schema/*.sql (fn_sales_engineer_acts_on_handoff, fn_gl_sync_business,
//      fn_seat_handoff).
//   3. LIVE, read-only, only when asked: REVEAL_TX=<transaction uuid> and a management token (SUPABASE_ACCESS_TOKEN or
//      ~/.supabase/access-token). The same trace is SELECTed for that transaction (no write of any kind) and judged the same.
//
// IT IS EXPECTED TO FAIL TODAY. Every test named "GAP n" is a gap measured on 13 Nov 2026 and listed in
// docs/reports (the workflow audit of 13 Nov). Do NOT weaken one to make it pass: it passes when the chain is built.
// Tests named "HOLDS" pass today and guard what already works. NOT wired into the gate: the file is not *.test.mjs, so
// scripts/checks/run.mjs does not discover it. Run it by hand:
//     node --test scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs
//     REVEAL_TX=<uuid> node --test scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs
//     REVEAL_REHEARSAL=scripts/fixtures/zz_demo_paid_reveal_rehearsal_<date>.json node --test scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const FIXTURE = 'scripts/fixtures/zz_demo_paid_reveal_trace_2026-09-21.json';
const REF = 'htdblwldjkcgjvmqkbeh';
const RATE = 0.03;

// ── the trace ────────────────────────────────────────────────────────────────────────────────────
function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  return existsSync(p) ? readFileSync(p, 'utf8').trim() : '';
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The SELECT that produced the fixture, for any transaction. Read-only: one statement, SELECT only. */
export function traceSql(tx) {
  if (!UUID.test(tx)) throw new Error('REVEAL_TX must be a transaction uuid');
  return `with t as (select * from public.transactions where id='${tx}')
select json_build_object(
 'transaction',(select json_build_object('id',id,'quote_id',quote_id,'inquiry_id',inquiry_id,'quote_amount',quote_amount,'reveal_fee',reveal_fee,'processing_fee',processing_fee,'total_charged',total_charged,'stripe_fee_fils',stripe_fee_fils,'fee_status',fee_status,'revealed_at',revealed_at,'paid_at',paid_at,'refund_deadline',refund_deadline,'refund_status',refund_status,'stripe_invoice_number',stripe_invoice_number,'stripe_invoice_total_fils',stripe_invoice_total_fils,'doc_kind',doc_kind) from t),
 'quote',(select json_build_object('id',q.id,'quote_amount',q.quote_amount,'price_ex_vat',q.price_ex_vat,'vat_treatment',q.vat_treatment,'status',q.status) from public.quotes q where q.id=(select quote_id from t)),
 'inquiry',(select json_build_object('id',i.id,'status',i.status,'outcome',i.outcome,'completed_at',i.completed_at,'hired_supplier_id',i.hired_supplier_id) from public.inquiries i where i.id=(select inquiry_id from t)),
 'other_quotes',(select coalesce(json_agg(json_build_object('id',q.id,'status',q.status,'supplier_id',q.supplier_id)),'[]') from public.quotes q where q.inquiry_id=(select inquiry_id from t) and q.id<>(select quote_id from t)),
 'handoffs',(select coalesce(json_agg(json_build_object('id',a.id,'to',a.agent,'from',a.detail->>'from','type',a.detail->>'type','status',a.status,'created_at',a.created_at,'decided_at',a.decided_at,'decided_by',a.decided_by,'subject_id',a.detail->>'subject_id','has_evidence',a.evidence is not null) order by a.id),'[]') from public.agent_actions a where a.kind='handoff' and (a.target_id::text ~ (select id::text from t) or a.detail->>'transaction_id'=(select id::text from t) or a.detail->>'quote_id'=(select quote_id::text from t) or a.detail->>'inquiry_id'=(select inquiry_id::text from t))),
 'notifications',(select coalesce(json_agg(json_build_object('type',n.type,'to_role',n.to_role,'channel',n.channel,'status',n.status,'requested_by',n.requested_by,'created_at',n.created_at,'subject',n.subject,'body',left(n.body,600)) order by n.id),'[]') from public.notifications n where (n.quote_id=(select quote_id from t) or n.inquiry_id=(select inquiry_id from t)) and n.created_at >= (select revealed_at from t) - interval '5 minutes'),
 'gl',(select coalesce(json_agg(json_build_object('entry_no',j.entry_no,'source',j.source,'source_ref',j.source_ref,'memo',j.memo,'lines',(select json_agg(json_build_object('account',l.account_code,'debit',l.debit,'credit',l.credit)) from public.gl_journal_lines l where l.journal_id=j.id))),'[]') from public.gl_journal j where j.source_ref in ((select id::text from t),(select stripe_invoice_number from t))),
 'events',(select coalesce(json_agg(json_build_object('type',e.event_type,'actor',e.actor,'at',e.occurred_at) order by e.occurred_at),'[]') from public.company_event e where e.entity_id::text in ((select id::text from t),(select quote_id::text from t)) and e.occurred_at >= (select revealed_at from t) - interval '5 minutes'),
 'refund_cases',(select count(*) from public.refunds r where r.transaction_id=(select id from t)),
 'response_watch',(select count(*) from public.supplier_response_watch w where w.transaction_id=(select id from t))
) as trace`;
}

async function liveTrace(tx) {
  const sql = traceSql(tx);
  if (!/^\s*with\s+t\s+as\s+\(select/i.test(sql) || /\b(insert|update|delete|alter|drop|create|grant|truncate)\b/i.test(sql.replace(/'[^']*'/g, ''))) throw new Error('trace SQL is not read-only');
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + token() }, body: JSON.stringify({ query: sql }),
  });
  const j = await r.json();
  if (!Array.isArray(j) || !j[0]?.trace) throw new Error('trace read failed: ' + JSON.stringify(j).slice(0, 300));
  return j[0].trace;
}

const LIVE = process.env.REVEAL_TX ? (token() ? process.env.REVEAL_TX : null) : null;
// 4. A REHEARSAL (sales_engineer, 13 Nov 2026): REVEAL_REHEARSAL=<fixture written by scripts/it/rehearse_a_paid_reveal_trace.mjs>,
//    the same trace produced by the code ON A BRANCH (its pending SQL applied inside one rolled-back request on production).
//    The 21 Sep capture can never change, so a gap judged on its rows stays red whatever is built until a real reveal is paid
//    on applied code; a rehearsal judges the branch. The routines are then read from the rehearsed SQL files first (the
//    mirror holds only what production runs), and the same assertions apply unchanged.
const REHEARSAL = !LIVE && process.env.REVEAL_REHEARSAL ? process.env.REVEAL_REHEARSAL : null;
const TRACE = LIVE ? await liveTrace(LIVE) : JSON.parse(read(REHEARSAL || FIXTURE));
const SOURCE = LIVE ? `production transaction ${LIVE} (read-only)` : REHEARSAL ? `rehearsal ${REHEARSAL}` : FIXTURE;
const REHEARSED_SQL = REHEARSAL && Array.isArray(TRACE.rehearsed_sql) ? TRACE.rehearsed_sql : [];

// ── helpers ──────────────────────────────────────────────────────────────────────────────────────
const tx = TRACE.transaction;
const hrs = (a, b) => (new Date(b) - new Date(a)) / 3.6e6;
const within = (row, h) => hrs(tx.revealed_at, row.created_at ?? row.at) <= h;
const handoffsTo = (seat) => TRACE.handoffs.filter((h) => h.to === seat && within(h, 24));
const notes = (role) => TRACE.notifications.filter((n) => n.to_role === role);
/** UAE working days (Mon-Fri), as public.fn_add_working_days counts them. */
function addWorkingDays(iso, n) { const d = new Date(iso); let left = n; while (left > 0) { d.setUTCDate(d.getUTCDate() + 1); const w = d.getUTCDay(); if (w !== 0 && w !== 6) left--; } return d; }
/** Boolean matchers: a failing message names the pattern, never dumps the file. */
const has = (re, text, msg = '') => assert.ok(re.test(String(text)), `${msg || 'expected'} ${re}`);
const lacks = (re, text, msg = '') => assert.ok(!re.test(String(text)), `${msg || 'unexpected'} ${re}`);
const ddMon = (iso) => new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'Asia/Dubai' });

/** A routine as the rehearsed SQL defines it (rehearsal mode only), or null. */
function rehearsedFn(name) {
  for (const f of [...REHEARSED_SQL].reverse()) {
    if (!existsSync(join(ROOT, f))) continue;   // another branch's pending file: judged by its own branch
    const s = read(f); const at = s.search(new RegExp(`create or replace function public\\.${name}\\(`, 'i'));
    if (at < 0) continue;
    const open = s.slice(at).match(/as \$(\w*)\$/i); if (!open) continue;
    const tag = `$${open[1]}$`; const body = s.indexOf(tag, at) + tag.length;
    return s.slice(at, s.indexOf(tag, body) + tag.length);
  }
  return null;
}
function mirrorFn(name) {
  const own = rehearsedFn(name); if (own) return own;
  const dir = 'supabase/schema/full_schema';
  for (const f of readdirSync(join(ROOT, dir)).filter((x) => x.endsWith('.sql')).sort()) {
    const s = read(join(dir, f)); const at = s.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
    if (at < 0) continue;
    const end = s.indexOf('$function$', s.indexOf('$function$', at) + 10);
    return s.slice(at, end + 10);
  }
  throw new Error(`public.${name} is not in the production mirror`);
}
const HANDOFFS = read('supabase/functions/_shared/payment_handoffs.ts');
const kinds = [...HANDOFFS.matchAll(/\{\s*type:\s*'([^']+)',\s*from:\s*'([^']+)',\s*to:\s*'([^']+)'\s*\}/g)].map((m) => ({ type: m[1], from: m[2], to: m[3] }));
// The reveal.paid branch of the sales engineer's handler, followed into the sales-engineer routines it actually CALLS (two
// levels; the branch must name them, so a routine that exists but is not on the path never counts): the behaviour is judged
// where the code path puts it, by the same pattern (review of W2, 13 Nov 2026).
const optFn = (n) => { try { return mirrorFn(n); } catch { return ''; } };
const calledBy = (text) => [...new Set([...text.matchAll(/public\.(fn_sales_engineer_\w+)\(/g)].map((m) => m[1]))]
  .filter((n) => n !== 'fn_sales_engineer_writes' && n !== 'fn_sales_engineer_acts_on_handoff');
const revealPaidBranch = (() => {
  const s = mirrorFn('fn_sales_engineer_acts_on_handoff'); const a = s.indexOf("if t = 'reveal.paid' then");
  const branch = s.slice(a, s.indexOf('elsif t =', a));
  const one = calledBy(branch).map(optFn).join('\n');
  return branch + one + calledBy(one).map(optFn).join('\n');
})();
const GL = mirrorFn('fn_gl_sync_business');
const glReveal = GL.slice(GL.indexOf('-- 1) Reveal-fee revenue'), GL.indexOf('-- 1b)'));

console.log(`# judged: ${SOURCE}`);

// ═════════════════════════════ HOLDS (true today; guards what works) ═════════════════════════════
test('HOLDS: the fee is 3% of the quote figure stored as ex-VAT, and the sale recorded exactly that fee', () => {
  const exVat = Number(TRACE.quote.price_ex_vat);
  assert.ok(exVat > 0, 'the revealed quote has an ex-VAT price');
  assert.equal(Number(TRACE.quote.quote_amount), exVat, 'quotes.quote_amount (what every charge path reads) equals price_ex_vat');
  assert.equal(Math.round(Number(tx.reveal_fee) * 100), Math.round(exVat * RATE * 100), 'reveal_fee = round(3% x ex-VAT)');
});

test('HOLDS: the sales engineer was handed reveal.paid and acted on it (customer receipt + chosen supplier told)', () => {
  const rp = handoffsTo('sales_engineer').filter((h) => h.type === 'reveal.paid');
  assert.equal(rp.length, 1, 'one reveal.paid handoff to the sales engineer');
  assert.equal(rp[0].status, 'done', 'it was closed');
  assert.ok(notes('customer').some((n) => n.type === 'reveal_receipt'), 'the customer was sent the reveal receipt');
  assert.ok(notes('supplier').some((n) => n.type === 'quote_accepted'), 'the chosen supplier was told it was revealed');
});

test('HOLDS: customer support delivered every message and returned the outcome to the seat that asked', () => {
  const req = handoffsTo('customer_support').filter((h) => h.type === 'delivery.request');
  assert.ok(req.length >= 2, 'delivery requests reached customer support');
  assert.ok(req.every((h) => h.status === 'done'), 'each request was answered');
  assert.ok(TRACE.handoffs.some((h) => h.type === 'delivery.result' && h.to === 'sales_engineer'), 'a delivery.result came back to the sales engineer');
});

test('HOLDS: the refund-window deadline is 5 working days after revealed_at', () => {
  assert.equal(new Date(tx.refund_deadline).toISOString().slice(0, 10), addWorkingDays(tx.revealed_at, 5).toISOString().slice(0, 10));
});

test('HOLDS: our invoice and receipt say no VAT is charged and print no TRN, and the revenue posting has no VAT line', () => {
  const docs = read('supabase/functions/_shared/reveal_fee_documents.ts');
  has(/not registered for VAT; no VAT has been charged on this amount/, docs);
  lacks(/Tax Invoice'|TRN:/, docs);
  lacks(/'account','(2100|1150)'/, glReveal, 'no VAT payable/recoverable line on reveal revenue');
});

// ═══════════════════════════ GAPS (fail today; each is a build item) ═════════════════════════════
test('GAP 1 [accountant]: the accountant is TOLD a payment arrived (a handoff addressed to the accountant)', () => {
  // Today trg_reveal_receipt files reveal.paid FROM 'accountant' TO 'sales_engineer': the accountant's name is on the
  // sender line, written by a trigger. No row is addressed to the accountant, so the seat never reads the payment.
  assert.ok(kinds.some((k) => k.to === 'accountant' && /reveal|payment|sale/.test(k.type)), 'payment_handoffs.ts has a reveal/payment conversation addressed TO the accountant');
  assert.ok(handoffsTo('accountant').some((h) => /reveal|payment|sale/.test(String(h.type))), `a reveal/payment handoff to the accountant within 24 h (${SOURCE})`);
});

test('GAP 2 [accountant]: the accountant reconciled THIS payment against THIS invoice and recorded its judgement', () => {
  // accountant_reveal_reconcile_item keeps only mismatches; seat_judgement holds 0 accountant decisions on a reveal.
  // The one reveal it did look at (charge_audit: AED 816.37 charged, AED 38.77 over the formula) was answered
  // "Its playbook has no deterministic remedy" and closed 33 days later with no refund of the overcharge.
  const ack = TRACE.handoffs.find((h) => h.to === 'accountant' && h.type === 'it.finding');
  const acted = handoffsTo('accountant').some((h) => /reconcil|reveal/.test(String(h.type)) && h.status === 'done' && h.has_evidence);
  assert.ok(acted, `a reconcile decision by the accountant on this transaction${ack ? ' (the only accountant row is a charge_audit finding answered with "no deterministic remedy")' : ''}`);
});

test('GAP 3 [accountant]: the books hold the sale: one reveal_fee journal for this transaction', () => {
  // fn_gl_sync_business books only rows fn_gl_fixture_or_orphan passes, so no rehearsal reveal is ever booked and no
  // rehearsal can prove the books. Production has 0 reveal_fee journals ever (gl_journal sources, 13 Nov 2026).
  assert.equal(TRACE.gl.filter((j) => j.source === 'reveal_fee').length, 1, `a reveal_fee journal for ${tx.id}`);
});

test('GAP 4 [accountant]: the journal balances, credits 4000 with the ex-VAT fee, debits 6100 with Stripe\'s fee, no VAT line', () => {
  const j = TRACE.gl.find((x) => x.source === 'reveal_fee');
  assert.ok(j, 'the journal exists (GAP 3)');
  const sum = (k) => j.lines.reduce((a, l) => a + Number(l[k] || 0), 0);
  assert.equal(Math.round(sum('debit') * 100), Math.round(sum('credit') * 100), 'balanced');
  assert.equal(Math.round(Number(j.lines.find((l) => l.account === '4000')?.credit) * 100), Math.round(Number(tx.reveal_fee) * 100), '4000 = reveal fee (3% of ex-VAT), nothing else');
  assert.equal(Math.round(Number(j.lines.find((l) => l.account === '6100')?.debit) * 100), Number(tx.stripe_fee_fils), '6100 = Stripe fee from the balance transaction');
  assert.ok(!j.lines.some((l) => ['2100', '1150'].includes(l.account)), 'no VAT line');
});

test('GAP 5 [accountant]: the journal names the invoice number it books', () => {
  // fn_gl_sync_business writes memo 'Reveal fee (net of Stripe fee)' and source_ref = transaction id: an auditor cannot go
  // from the ledger to the invoice the customer holds.
  has(/stripe_invoice_number/, glReveal, 'fn_gl_sync_business carries the invoice number into the reveal journal');
});

test('GAP 6 [accountant]: the refund clock starts at the moment Stripe took the money, not when our row was written', () => {
  // recordRevealSale stamps revealed_at = new Date() at insert; trg_reveal_window counts the 5 working days from it. A
  // late or lost webhook healed by the hourly reconcile therefore starts the customer's window late. No column holds
  // Stripe's paid time.
  const sale = read('supabase/functions/_shared/reveal_sale.ts');
  lacks(/revealed_at:\s*new Date\(\)\.toISOString\(\)/, sale, 'revealed_at is not the insert time');
  assert.ok('paid_at' in tx || 'stripe_paid_at' in tx, 'the transaction records Stripe\'s paid time');
});

test('GAP 7 [ceo]: the CEO is told of THIS sale (a handoff or brief line naming it), not only a daily count', () => {
  // Today the CEO sees reveals only as a number: report.five_numbers (ceo -> ceo, demo excluded) and the founder's
  // daily brief line "Customers who paid a reveal fee". No conversation to the CEO is registered for a sale.
  assert.ok(kinds.some((k) => k.to === 'ceo' && /reveal|sale|payment/.test(k.type)), 'payment_handoffs.ts has a sale notice addressed to the CEO');
  assert.ok(handoffsTo('ceo').length > 0, `a handoff to the CEO about this reveal within 24 h (${SOURCE})`);
});

test('GAP 8 [sales_engineer]: the reveal.paid seat closes the request: the sale is the request\'s recorded outcome', () => {
  // markRevealed sets inquiries.status = 'revealed', which is NOT closed (canReveal lets a second supplier be revealed);
  // outcome, completed_at and pipeline stay empty until a "did you hire?" yes or a Hire press.
  assert.ok(['closed', 'completed'].includes(String(TRACE.inquiry.status)) || TRACE.inquiry.outcome != null,
    `inquiry ${TRACE.inquiry.id} reads status=${TRACE.inquiry.status}, outcome=${TRACE.inquiry.outcome}`);
});

test('GAP 9 [sales_engineer]: the suppliers who were not chosen are told, anonymously, when the customer pays', () => {
  // fn_sales_engineer_tells_losing_suppliers exists but runs only on a hire (follow-up yes or Hire), never on the reveal.
  has(/fn_sales_engineer_tells_losing_suppliers|job_awarded_other|not_selected/, revealPaidBranch, 'the reveal.paid branch tells the other suppliers');
  const others = TRACE.other_quotes.length;
  if (others) assert.ok(notes('supplier').filter((n) => /awarded_other|not_selected/.test(n.type)).length >= others, 'each other supplier got a notice');
});

test('GAP 10 [sales_engineer]: somebody owns the follow-up of this reveal (response watch / did-you-get-the-job), from the payment', () => {
  assert.ok(Number(TRACE.response_watch) > 0, `a supplier_response_watch row for ${tx.id}`);
});

test('GAP 11 [sales_engineer]: the customer is told the date the refund window ends, on the receipt and the invoice', () => {
  const date = ddMon(tx.refund_deadline);
  assert.ok(notes('customer').some((n) => String(n.body).includes(date)), `a customer message names ${date}`);
  has(/refund_deadline|window ends|respond_by/, read('supabase/functions/_shared/reveal_fee_documents.ts'), 'the invoice/receipt print the window end date');
});

test('GAP 12 [it_engineer]: a rehearsal reveal leaves the chain observable (the demo filter hides every handoff)', () => {
  // fn_seat_handoff returns NULL for any ZZ DEMO payload (ruling 1199): since 18 Oct no reveal.paid handoff has been filed
  // (company_event handoff.reveal.paid.sent, last 18 Oct) although 53 test reveals were paid; teardown then deletes the
  // transaction. So no rehearsal can show the chain after the fact; only a rolled-back probe can.
  const seatHandoff = mirrorFn('fn_seat_handoff');
  lacks(/fn_seat_work_is_demo\([^)]*\)\s*\n?\s*and coalesce\(current_setting\('qd\.probe_files_demo_handoff'/, seatHandoff, 'a demo reveal files its handoffs (or a shadow trace) instead of nothing');
});
