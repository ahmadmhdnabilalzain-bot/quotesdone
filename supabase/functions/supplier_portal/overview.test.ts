// deno test --no-lock --node-modules-dir=auto supabase/functions/supplier_portal/overview.test.ts
//
// The combined supplier overview (15 Sep 2026). A fake client answers every read after a fixed delay
// and records what was asked, so the tests measure the two things the change is for: how many reads
// the dashboard makes, and how many of them wait on another. That is counted as WAVES - reads that
// start after the same number of earlier reads finished form one - not as wall time: 29 Sep 2026 a loaded CI runner
// took 121 ms for two 40 ms waves and failed a test that had nothing wrong with it. No
// network, no environment, no real row — nothing here can reach a person.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { agreementSigning, buildAlerts, buildDashboard, buildEligibility, buildNotifications, NOTICE_TAB, supplierCard, type Supplier } from './overview.ts';

const DELAY = 40;
type Answer = { data?: unknown; count?: number | null; error?: unknown };

// `rejects`: table names whose single-row read throws, the way a dropped connection does.
function fakeAdmin(answers: Record<string, Answer> = {}, rejects: string[] = []) {
  const reads: string[] = [];
  // Every read takes exactly DELAY, so reads start and finish in lockstep batches: the number of reads
  // already finished when a read starts names its wave. Serial reads each see a new count; a batch shares one.
  let done = 0;
  const starts = new Set<number>();
  const track = <T>(p: Promise<T>): Promise<T> => { starts.add(done); return p.finally(() => { done++; }); };
  // An answer keyed by the exact read wins; one keyed by the table or routine name is the fallback.
  const settle = (key: string): Promise<Answer> => track(new Promise((res) => setTimeout(() => res(answers[key] ?? answers[key.split('?')[0]] ?? { data: null, count: 0 }), DELAY)));
  const table = (name: string) => {
    const filters: string[] = [];
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'in', 'neq', 'not', 'is', 'order', 'limit', 'gte']) q[m] = (...a: unknown[]) => { if (m === 'eq' || m === 'in') filters.push(String(a[0]) + '=' + JSON.stringify(a[1])); return q; };
    const key = () => name + (filters.length ? '?' + filters.join('&') : '');
    q.maybeSingle = () => { reads.push(key()); return rejects.includes(name) ? track(new Promise((_, rej) => setTimeout(() => rej(new Error('read failed')), DELAY))) : settle(name); };
    q.then = (ok: (v: Answer) => unknown, bad?: (e: unknown) => unknown) => { reads.push(key()); return settle(key()).then(ok, bad); };
    return q;
  };
  return { reads, waves: () => starts.size, from: table, rpc: (fn: string) => { reads.push('rpc:' + fn); return settle('rpc:' + fn); } };
}

const SUP: Supplier = { id: 7, company_name: 'ZZ DEMO — fixture', approval_status: 'pending', registration_status: null, license_expiry: null, name_corrected_from: null };

Deno.test('alerts: two waves, not five in a row', async () => {
  const admin = fakeAdmin({
    'inquiry_matches?supplier_id=7': { data: [{ inquiry_id: 'a' }, { inquiry_id: 'b' }] },
    'quotes?supplier_id=7': { data: [{ inquiry_id: 'b' }] },
    'inquiries?id=["a","b"]&status=["sent","open","active","collecting","live","quoted"]': { data: [{ id: 'a' }, { id: 'b' }] },
  });
  const alerts = await buildAlerts(admin, 7);
  // Serial, the five reads are five waves. Batched, two.
  assert(admin.waves() <= 2, `alerts took ${admin.waves()} waves — reads are waiting on each other`);
  assertEquals(alerts.map((a) => a.kind), ['new_rfq']);
  assertEquals(alerts[0].count, 1, 'the quoted inquiry is not an RFQ waiting');
});

Deno.test('eligibility: every read in one wave, and an unconfirmed scope blocks', async () => {
  const admin = fakeAdmin({ leads: { data: { id: 7, sector: 'hvac', registration_submitted_at: '2026-09-01', phone: '+971500000000' } } });
  const e = await buildEligibility(admin, 7);
  assert(admin.waves() <= 2, `eligibility took ${admin.waves()} waves`);
  assertEquals(e.eligible, false);
  assert(e.blocking.some((b: { code: string }) => b.code === 'scope_unconfirmed'));
  assertEquals(e.reach.shortlist_size, 8);
});

// "ELIGIBLE FOR MATCHING" WHILE MATCHING REFUSES HIM (10 Nov 2026, customer_support, supplier-journey audit). Matching asks
// fn_is_matchable: verified AND approval_status = 'approved' (a_supplier_is_matchable_only_once_approved), not banned,
// not blocked, not closed, under the strike limit. This panel never asked approval at all, so a supplier held 'pending'
// (an unread licence number, a document still being read, auto-approve off) or 'action_required' (an item of the six
// missing) with a confirmed scope read a green "Eligible for matching" badge and the insights hint "your first request
// is on its way" while no request could reach him. One gate, two readings; the panel now reads matching's.
const READY = { id: 7, sector: 'hvac', registration_submitted_at: '2026-09-01', phone: '+971500000000', verified: true, approval_status: 'approved' };
const ready = (lead: Record<string, unknown>, six: string[] = []) => fakeAdmin({
  leads: { data: lead }, supplier_capabilities: { data: { trades: ['hvac'], confirmed_at: '2026-09-02' } }, 'rpc:fn_supplier_mandatory_six_for': { data: six },
});
Deno.test('eligibility: an approved, verified, confirmed supplier is eligible (control)', async () => {
  const e = await buildEligibility(ready(READY), 7);
  assertEquals(e.blocking, []);
  assertEquals(e.eligible, true);
});
Deno.test('eligibility: a supplier the gate holds pending is not eligible, and is told why', async () => {
  const e = await buildEligibility(ready({ ...READY, verified: false, approval_status: 'pending', licence_gate_reason: 'licence_number_unread' }), 7);
  assertEquals(e.eligible, false, 'fn_is_matchable refuses a supplier who is not approved');
  const b = e.blocking.find((x: { code: string }) => x.code === 'not_approved');
  assert(b, 'the reason he is not matched is on the list');
  assertEquals((b as { params: { reason: string } }).params.reason, 'licence_number_unread');
});
Deno.test('eligibility: an item of the six missing is not eligible either (the checklist names it)', async () => {
  const e = await buildEligibility(ready({ ...READY, verified: false, approval_status: 'action_required' }, ['reg_licence']), 7);
  assertEquals(e.eligible, false);
  assert(!e.blocking.some((x: { code: string }) => x.code === 'not_approved'), 'the six are the checklist itself, not listed twice');
});

Deno.test('eligibility: a scope read that throws fails closed — the scope gate still blocks', async () => {
  const admin = fakeAdmin({ leads: { data: { id: 7, sector: 'hvac', registration_submitted_at: '2026-09-01' } }, supplier_capabilities: { data: { confirmed_at: '2026-09-01' } } }, ['supplier_capabilities']);
  const e = await buildEligibility(admin, 7);
  assertEquals(e.eligible, false);
  assert(e.blocking.some((b: { code: string }) => b.code === 'scope_unconfirmed'), 'a failed read must never read as a confirmed scope');
});

Deno.test('dashboard: one payload carries stats, alerts, eligibility, impact and the bell counts', async () => {
  const admin = fakeAdmin({
    'rpc:fn_supplier_stats': { data: { quotes_total: 3 } },
    'rpc:fn_supplier_document_impact': { data: { documents: [] } },
    'messages?supplier_id=7&sender="customer"&read_by_supplier=false&blocked=false': { count: 2 },
    'quote_spec_hold?supplier_id=7&state=["open","awaiting_approval"]': { count: 1 },
  });
  const { status, body } = await buildDashboard(admin, SUP);
  assertEquals(status, 200);
  assertEquals(body.stats, { quotes_total: 3 });
  assertEquals(body.notifications, { unread_messages: 2, spec_holds: 1, notices: [] });
  assertEquals(body.document_impact, { ok: true, documents: [] });
  assertEquals(body.eligibility.ok, true);
  assertEquals(body.supplier.company_name, 'ZZ DEMO — fixture');
  // The deepest chain is alerts (matches, then open inquiries) and the mandatory-six check; nothing
  // waits on fn_supplier_stats any more. Before: 8 serial reads in overview alone.
  assert(admin.waves() <= 3, `dashboard took ${admin.waves()} waves — expected at most three`);
  console.log(`dashboard: ${admin.reads.length} reads in ${admin.waves()} waves`);
});

Deno.test('dashboard: a stats failure is a 500, not an empty dashboard', async () => {
  const admin = fakeAdmin({ 'rpc:fn_supplier_stats': { data: null, error: { message: 'boom' } } });
  const { status, body } = await buildDashboard(admin, SUP);
  assertEquals(status, 500);
  assertEquals(body.error, 'boom');
});

Deno.test('dashboard: a failed impact read is null, never zeros', async () => {
  const admin = fakeAdmin({ 'rpc:fn_supplier_document_impact': { data: null, error: { message: 'x' } } });
  const { body } = await buildDashboard(admin, SUP);
  assertEquals(body.document_impact, null);
});

// Audit 21 Sep 2026, findings 5 and 6: the reveal reached the supplier as a notification row and the
// bell never showed it; the only link a supplier had opened the CUSTOMER portal. Every notice must carry
// a supplier-portal tab (never a URL), and a type with no tab is dropped, not guessed.
Deno.test('bell: a reveal is a notice on the Messages tab; unknown types are dropped; tabs are portal tabs only', async () => {
  const admin = fakeAdmin({ 'notifications?to_role="supplier"&lead_id=7': { data: [
    { id: 9, type: 'quote_accepted', inquiry_id: 'i1', quote_id: 'q1', created_at: '2026-09-21T10:00:00Z' },
    { id: 8, type: 'quote_coaching', inquiry_id: null, quote_id: null, created_at: '2026-09-21T09:00:00Z' },
    { id: 7, type: 'new_inquiry', inquiry_id: 'i2', quote_id: null, created_at: '2026-09-20T09:00:00Z' },
  ] } });
  const n = await buildNotifications(admin, 7);
  assertEquals(n.notices.map((x: { id: number; tab: string }) => [x.id, x.tab]), [[9, 'messages'], [7, 'rfqs']]);
  const PORTAL_TABS = ['services', 'rfqs', 'quotes', 'messages', 'documents', 'insights'];
  for (const [type, tab] of Object.entries(NOTICE_TAB)) assert(PORTAL_TABS.includes(tab), type + ' -> ' + tab + ' is not a supplier-portal tab');
});

// Finding 6: "1 new RFQ" beside "Inquiries received (3)" — the count now carries what it is out of.
Deno.test('alerts: the new-RFQ count names the total received', async () => {
  const admin = fakeAdmin({
    'inquiry_matches?supplier_id=7': { data: [{ inquiry_id: 'a' }, { inquiry_id: 'b' }, { inquiry_id: 'c' }] },
    'quotes?supplier_id=7': { data: [{ inquiry_id: 'a' }, { inquiry_id: 'b' }] },
    inquiries: { data: [{ id: 'a' }, { id: 'b' }, { id: 'c' }] },
  });
  const alerts = await buildAlerts(admin, 7);
  const rfq = alerts.find((a) => a.kind === 'new_rfq') as { params: { count: number; total: number } };
  assertEquals(rfq.params, { count: 1, total: 3 });
});

// Finding 20: "Set your sector", "Add your categories" and "Add your capability summary" sent the
// supplier to Profile, which has none of the three. A hint may only name a field the supplier can edit.
Deno.test('eligibility: every ranking hint points at a field the supplier can reach', async () => {
  const admin = fakeAdmin({ leads: { data: { id: 7, registration_submitted_at: '2026-09-01' } } });
  const e = await buildEligibility(admin, 7);
  const codes = (e.improving as { code: string; fix: string }[]).map((i) => i.code);
  for (const gone of ['no_sector', 'empty_categories', 'empty_capability_summary']) assert(!codes.includes(gone), gone + ' names a field the portal does not have');
  assert(codes.includes('empty_products') && codes.includes('empty_services'));
});

// Finding 20: "Set your sector", "Add your categories" and "Add your capability summary" sent the
// supplier to Profile, which has none of the three. A hint may only name a field the supplier can edit.
Deno.test('eligibility: every ranking hint points at a field the supplier can reach', async () => {
  const admin = fakeAdmin({ leads: { data: { id: 7, registration_submitted_at: '2026-09-01' } } });
  const e = await buildEligibility(admin, 7);
  const codes = (e.improving as { code: string; fix: string }[]).map((i) => i.code);
  for (const gone of ['no_sector', 'empty_categories', 'empty_capability_summary']) assert(!codes.includes(gone), gone + ' names a field the portal does not have');
  assert(codes.includes('empty_products') && codes.includes('empty_services'));
});

Deno.test('the wave counter itself: three reads in a row are three waves, three together are one', async () => {
  const serial = fakeAdmin();
  await serial.rpc('a'); await serial.rpc('b'); await serial.rpc('c');
  assertEquals(serial.waves(), 3);
  const batched = fakeAdmin();
  await Promise.all([batched.rpc('a'), batched.rpc('b'), batched.rpc('c')]);
  assertEquals(batched.waves(), 1);
  const chained = fakeAdmin();
  await Promise.all([chained.rpc('a').then(() => chained.rpc('b')), chained.rpc('c')]);
  assertEquals(chained.waves(), 2);
});

// 10 Nov 2026: an accepted Supplier Agreement whose certificate has not landed is "being signed", never "action required".
Deno.test('agreement_signing: accepted with no certificate for that acceptance is signing; signed after it, or never accepted, is not', () => {
  const acc = '2026-11-10T09:00:00Z';
  assertEquals(agreementSigning({ accepted_terms_at: acc, signed_terms_at: null }), true);
  assertEquals(agreementSigning({ accepted_terms_at: acc, signed_terms_at: '2026-11-10T09:00:20Z' }), false);
  assertEquals(agreementSigning({ accepted_terms_at: acc, signed_terms_at: '2026-10-01T00:00:00Z' }), true, 'a certificate of an EARLIER acceptance does not sign this one');
  assertEquals(agreementSigning({ accepted_terms_at: null, signed_terms_at: null }), false);
  const card = supplierCard({ id: 1, company_name: 'ZZ DEMO', approval_status: 'action_required', registration_status: null, license_expiry: null,
    name_corrected_from: null, licence_gate_reason: 'reg_terms', accepted_terms_at: acc, signed_terms_at: null } as Supplier);
  assertEquals((card as Record<string, unknown>).agreement_signing, true, 'the card the portal renders carries it');
});
