// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/a_party_under_screening_is_frozen.test.ts
//
// FAILURES items 3 and 5 (16 Nov 2026): a party with an open sanctions-screening hit is frozen at every reveal door until
// the CEO decides; a customer who may be a supplier in disguise has his quotes in that supplier's trades held while the
// accountant's flag is open. Both reads fail closed. The fakes answer only what the helpers read.
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { canReveal } from './reveal_guard.ts';
import { screeningOpen } from './sanctioned.ts';
import { quotesBeingChecked, withheldWhileChecked, BEING_CHECKED_REFUSAL } from './quotes_being_checked.ts';
import { customerFrozen, heldForComplianceReview } from '../customer_api/lib/compliance_hold.ts';
import { rematchDue } from '../customer_api/lib/rematch.ts';

// deno-lint-ignore no-explicit-any
type Rows = Record<string, any>;
/** Each table answers its rows to any filter; a table named in `errors` answers an error, as PostgREST does. */
function fakeAdmin(rows: Rows, errors: string[] = []) {
  const reads: string[] = [];
  const mk = (table: string) => {
    reads.push(table);
    const all = () => (rows[table] ?? []);
    const res = () => errors.includes(table) ? { data: null, error: { message: 'boom' } } : { data: all(), error: null };
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, eq: () => b, in: () => b, not: () => b, order: () => b,
      limit: () => res(),
      range: (from: number, to: number) => Promise.resolve({ data: all().slice(from, to + 1), error: null }),
      maybeSingle: () => Promise.resolve(errors.includes(table) ? { data: null, error: { message: 'boom' } } : { data: rows[table] ?? null, error: null }),
      then: (f: (r: unknown) => unknown) => Promise.resolve(f(res())),
    };
    return b;
  };
  const rpc = (fn: string) => {
    if (fn === 'fn_customer_quotes_being_checked') return Promise.resolve(rows.checking_error ? { data: null, error: { message: 'down' } } : { data: rows.checking ?? { inquiry_ids: [] }, error: null });
    if (fn === 'fn_trade_reveal_allowed') return Promise.resolve({ data: { allowed: true }, error: null });
    return Promise.resolve({ data: { hold: false }, error: null });
  };
  return { from: mk, rpc, reads };
}

const QUOTE = { id: 'q1', inquiry_id: 'i1', supplier_id: 7, status: 'submitted', quote_amount: 6000, price_ex_vat: 6000, lead_time: '21 days',
  warranty: '2 years on workmanship', scope: 'Supply and installation of wardrobes by our team',
  terms_spec: { installation: { included: 'yes', detail: 'by our team', source: 'reasoned' }, warranty: { period: '2 years', coverage: 'workmanship', source: 'reasoned' } } };
const ITEM = { quote_id: 'q1', line_no: 1, description: 'Wardrobes 18mm MR MDF, HPL finish', amount: 6000,
  spec: { material: 'MR MDF', thickness_mm: '18', finish: 'HPL' }, spec_source: { material: 'reasoned', thickness_mm: 'reasoned', finish: 'reasoned' } };
const BASE = { quotes: QUOTE, inquiries: { id: 'i1', customer_id: 'c1', status: 'sent', category: 'joinery', spec: null }, quote_items: [ITEM], transactions: null, sanctions_ban: [] };
const code = async (rows: Rows, errors: string[] = []) => {
  const r = await canReveal(fakeAdmin(rows, errors), { quoteId: 'q1', customerId: 'c1' });
  return r.ok ? 'allowed' : r.code + ':' + r.status;
};

Deno.test('control: with no hit on either party the reveal is allowed', async () => {
  assertEquals(await code(BASE), 'allowed');
});

Deno.test('an open hit on the supplier, or a hit on the customer, freezes the reveal; paid or not', async () => {
  assertEquals(await code({ ...BASE, supplier_screening_hit: [{ id: 1 }] }), 'compliance_review:409');
  assertEquals(await code({ ...BASE, customer_screening_hit: [{ id: 2 }] }), 'compliance_review:409');
  // already paid: the freeze is on dealing with the party, so the contact is not shown again while it is reviewed
  assertEquals(await code({ ...BASE, transactions: { id: 't1' }, supplier_screening_hit: [{ id: 1 }] }), 'compliance_review:409');
  // a confirmed ban keeps its own, stronger refusal
  assertEquals(await code({ ...BASE, sanctions_ban: [{ lead_id: 7 }], supplier_screening_hit: [{ id: 1 }] }), 'account_sanctioned:403');
});

Deno.test('the screening read fails closed: an unreadable hit table refuses the request, it never reveals', async () => {
  await assertRejects(() => code(BASE, ['supplier_screening_hit']));
  await assertRejects(() => code(BASE, ['customer_screening_hit']));
  await assertRejects(() => screeningOpen(fakeAdmin({}, ['customer_screening_hit']), { customerId: 'c1' }));
  assertEquals(await screeningOpen(fakeAdmin({}), { leadId: null, customerId: null }), false);
});

Deno.test('the refusal states no reason and promises nothing it cannot keep', async () => {
  const r = await canReveal(fakeAdmin({ ...BASE, supplier_screening_hit: [{ id: 1 }] }), { quoteId: 'q1', customerId: 'c1' });
  assert(!r.ok);
  for (const t of [r.message, r.message_ar]) assert(!/sanction|عقوب/i.test(t), 'a screening is never explained to a party: ' + t);
  // an already-paid reveal reaches this refusal too, so it must not say "you have not been charged"
  assert(!/charged/.test(r.message) && !/يُخصم/.test(r.message_ar), 'the same refusal answers a reveal already paid for: ' + r.message);
});

Deno.test('a customer with an open hit is not matched; his request waits for the decision, not on the outage schedule', async () => {
  assertEquals(await customerFrozen(fakeAdmin({ inquiries: { customer_id: 'c1' } }), 'i1'), false);
  assertEquals(await customerFrozen(fakeAdmin({ inquiries: { customer_id: 'c1' }, customer_screening_hit: [{ id: 3 }] }), 'i1'), true);
  assertEquals(await customerFrozen(fakeAdmin({ inquiries: null }), 'i1'), false);
  // unreadable: held, never matched blind
  assertEquals(await customerFrozen(fakeAdmin({ inquiries: { customer_id: 'c1' } }, ['customer_screening_hit']), 'i1'), true);
  assertEquals(await customerFrozen(fakeAdmin({}, ['inquiries']), 'i1'), true);
  const now = new Date('2026-11-16T08:00:00Z');
  const r = heldForComplianceReview({ attempts: 3, first_failed_at: '2026-11-15T08:00:00Z' }, 'extra note', now);
  assertEquals([r.matcher_unavailable, r.waiting_for, r.fanout], [true, 'compliance_review', 0]);
  // deno-lint-ignore no-explicit-any
  const s = r.rematch as any;
  assertEquals([s.next_at, s.exhausted, s.attempts, s.held_for, s.extra, s.first_failed_at], [null, false, 0, 'compliance_review', 'extra note', '2026-11-15T08:00:00Z']);
  // never asked again by the sweep, however long the decision takes (the 14-day closer skips a request that is not exhausted)
  for (const days of [0, 1, 7, 30]) assert(!rematchDue(r, new Date(now.getTime() + days * 86_400_000)), 'asked again after ' + days + ' days');
  // the CEO's false_positive sets next_at to now (fn_customer_screening_decide): the sweep then takes it at once
  const released = { ...r, rematch: { ...s, next_at: now.toISOString() } };
  assert(rematchDue(released, new Date(now.getTime() + 60_000)), 'a released request is matched on the next beat');
});

Deno.test('a customer_matches_supplier flag holds that customer\'s requests; unreadable fails closed', async () => {
  assertEquals([...await quotesBeingChecked(fakeAdmin({ checking: { inquiry_ids: ['i1', 'i9'] } }), 'c1')].sort(), ['i1', 'i9']);
  assertEquals((await quotesBeingChecked(fakeAdmin({}), 'c1')).size, 0);
  assertEquals((await quotesBeingChecked(fakeAdmin({ checking: { inquiry_ids: ['i1'] } }), null)).size, 0);
  await assertRejects(() => quotesBeingChecked(fakeAdmin({ checking_error: true }), 'c1'));
});

// HOLE 5 THROUGH COMPARE (review of 16 Nov 2026): the comparison, its PDF and CSV and the quote PDF withhold the same quotes.
Deno.test('a request being checked withholds every quote on it except one already paid for; unreadable fails closed', async () => {
  const named = { checking: { inquiry_ids: ['i1'] }, transactions: [{ quote_id: 'q2' }] };
  assertEquals([...await withheldWhileChecked(fakeAdmin(named), 'c1', 'i1', ['q1', 'q2', 'q3'])].sort(), ['q1', 'q3']);
  // control: a request the flag does not name withholds nothing
  assertEquals((await withheldWhileChecked(fakeAdmin(named), 'c1', 'i9', ['q1', 'q2'])).size, 0);
  assertEquals((await withheldWhileChecked(fakeAdmin(named), null, 'i1', ['q1'])).size, 0);
  await assertRejects(() => withheldWhileChecked(fakeAdmin({ checking_error: true }), 'c1', 'i1', ['q1']));
  await assertRejects(() => withheldWhileChecked(fakeAdmin({ checking: { inquiry_ids: ['i1'] } }, ['transactions']), 'c1', 'i1', ['q1']));
  for (const t of [BEING_CHECKED_REFUSAL.message, BEING_CHECKED_REFUSAL.message_ar]) assert(!/supplier|sanction|fraud|مورّد|عقوب|احتيال/i.test(t), 'the refusal says why: ' + t);
});

Deno.test('quote_compare leaves the withheld quotes out before it letters, ranks or benchmarks; quote_pdf refuses before its cache', async () => {
  const qc = await Deno.readTextFile(new URL('../quote_compare/index.ts', import.meta.url));
  const at = (re: RegExp) => { const m = re.exec(qc); assert(m, 'not found: ' + re); return m.index; };
  const filt = at(/qs = qs\.filter\(\(q: any\) => !beingChecked\.has\(String\(q\.id\)\)\)/);
  assert(at(/withheldWhileChecked\(admin, inq\.customer_id/) < filt, 'asked with the request\'s own customer, whoever the caller is');
  assert(filt < at(/if \(qs\.length < 2\) \{\n\s*await logRun\('ok', \{ compared: 0, quotes_seen: qs\.length, held_at_ranking/), 'before the need-two answer');
  assert(filt < at(/recordShown\(admin, new Map\(\[\[String\(inquiry_id\), qs\]\]\)/), 'before a letter is recorded for what is shown');
  assert(/priceBenchmarks = data\.filter\(\(b: any\) => !beingChecked\.has/.test(qc), 'the benchmark lines of a withheld quote are dropped');
  const rp = await Deno.readTextFile(new URL('../customer_api/actions/reports.ts', import.meta.url));
  const qp = rp.slice(rp.indexOf("if (action === 'quote_pdf')"));
  const chk = qp.indexOf('withheldWhileChecked(admin, String(cust.id), String(inq.id), [qid])');
  assert(chk > 0 && chk < qp.indexOf("from('quote_pdf_cache')"), 'quote_pdf refuses a withheld quote before it serves a cached file');
  // compare_pdf and compare_csv read the analysis only through quote_compare
  for (const a of ['compare_pdf', 'compare_csv']) {
    const body = rp.slice(rp.indexOf(`if (action === '${a}')`), rp.indexOf('if (action ===', rp.indexOf(`if (action === '${a}')`) + 10));
    assert(/fetchCompareAnalysis\(iid, lang\)/.test(body) && !/from\('quotes'\)/.test(body), a + ' reads quotes only through quote_compare');
  }
});
