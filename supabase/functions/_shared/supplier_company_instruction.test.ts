// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/supplier_company_instruction.test.ts
//
// THE COMPANY'S OWN ASKS BY E-MAIL OR WHATSAPP, AND WHO MAY GIVE THEM (customer_support + sales_engineer, 16 Nov 2026; agent
// SUPPLIER_W2; SUPPLIER holes 4, 5, 6, 10, 12). Before this file, a job question by e-mail or WhatsApp reached nobody, "close my
// account" changed nothing, "the customer is not answering" had no door, an offer to pay for leads was forgotten, and nothing knew
// that the person writing was the estimator rather than the owner. The model is a stub (no paid call): each scenario gives it the
// reading a model returns for that message, in English or Arabic, and proves what code does with it.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { type Ask, type Facts, INSTRUCTION_SYS, supplierInstructionTurn } from './supplier_instruction.ts';
import { memberMayInstruct } from './supplier_company.ts';

const BASE: Facts = {
  supplier_id: 42, standing: null,
  requests: [{ inquiry_id: '11111111-1111-4111-8111-111111111101', ref: 'RFQ-101', trade: 'plumbing', trade_label: 'Plumbing', declined: false },
             { inquiry_id: '11111111-1111-4111-8111-111111111102', ref: 'RFQ-102', trade: 'painting', trade_label: 'Painting', declined: false }],
  trades: [{ code: 'plumbing', label: 'Plumbing' }, { code: 'painting', label: 'Painting' }], services: [], correction: null, figures: [],
  revealed: [{ inquiry_id: '11111111-1111-4111-8111-111111111090', ref: 'RFQ-90' }], closure: null, live_quotes: 2, owner_email: 'zz-demo-owner@example.invalid',
};
const OWNER = { role: 'owner' as const, email: null, name: null };
const ESTIMATOR = { role: 'estimator' as const, email: 'zz-demo-est@example.invalid', name: 'ZZ DEMO Estimator' };
const VIEWER = { role: 'viewer' as const, email: 'zz-demo-view@example.invalid', name: 'ZZ DEMO Viewer' };

function stubModel(reading: Record<string, unknown>) {
  const seen: { sys: string; input: string }[] = [];
  const ask: Ask = (sys, input) => { seen.push({ sys, input }); return Promise.resolve(JSON.stringify({ request: null, reason: null, also_remove: false, trades: [], services: [], quote: null, question: null, keep_quotes: null, asked_for: null, trade: null, size: null, ...reading })); };
  return { ask, seen };
}
/** Routines and the four tables fileJobQuestion reads or writes, recorded. */
function stubAdmin(answers: Record<string, unknown> = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const inserts: { table: string; row: Record<string, unknown> }[] = [];
  const rpc = (fn: string, args: Record<string, unknown>) => {
    calls.push({ fn, args });
    if (answers[fn] !== undefined) return Promise.resolve({ data: answers[fn], error: null });
    if (fn === 'fn_supplier_close_propose') return Promise.resolve({ data: { ok: true, closure_id: 5, live_quotes: 2, law: { kept_until: '2031-12-31', law: 'UAE PDPL (Federal Decree-Law 45/2021); Cabinet Decision 74/2023, Art. 3' } }, error: null });
    if (fn === 'fn_supplier_close_decide') return Promise.resolve({ data: args.p_decision === 'cancel' ? { ok: true, cancelled: true } : { ok: true, withdrawn: 2, kept: 0, revealed_open: 1, kept_until: '2031-12-31', law: 'UAE PDPL; Cabinet Decision 74/2023, Art. 3' }, error: null });
    if (fn === 'fn_supplier_customer_not_answering') return Promise.resolve({ data: { ok: true, nudged: true, ref: 'RFQ-90' }, error: null });
    if (fn === 'fn_supplier_demand_signal_record') return Promise.resolve({ data: { ok: true, id: 1 }, error: null });
    return Promise.resolve({ data: null, error: { message: 'unexpected ' + fn } });
  };
  // deno-lint-ignore no-explicit-any
  const q = (table: string): any => {
    const chain = {
      select: () => chain, eq: () => chain, gte: () => chain, limit: () => chain, order: () => chain,
      maybeSingle: () => Promise.resolve({ data: table === 'inquiries' ? { id: 'x', status: 'sent' } : table === 'inquiry_matches' ? { id: 1 } : table === 'leads' ? { company_name: 'ZZ DEMO Owner Co', banned: false } : null, error: null }),
      insert: (row: Record<string, unknown>) => { inserts.push({ table, row }); return { select: () => ({ single: () => Promise.resolve({ data: { id: 77 }, error: null }) }) }; },
      then: (f: (v: unknown) => unknown) => Promise.resolve({ count: 0, data: [], error: null }).then(f),
    };
    return chain;
  };
  return { rpc, calls, inserts, from: q };
}
const fns = (a: { calls: { fn: string }[] }) => a.calls.map((c) => c.fn);
async function turn(reading: Record<string, unknown>, message: string, facts: Facts = BASE, sender: NonNullable<Facts['sender']> = OWNER, answers: Record<string, unknown> = {}) {
  const m = stubModel(reading), a = stubAdmin(answers);
  const r = await supplierInstructionTurn(a, m.ask, { supplierId: 42, message, channel: 'email', facts, sender });
  return { r, a, m };
}

Deno.test('the reader is told every new kind and is shown what he was revealed on and any closure waiting', async () => {
  for (const k of ['job_question', 'close_account', 'close_confirm', 'close_cancel', 'customer_silent', 'paid_leads']) assert(INSTRUCTION_SYS.includes(k), k);
  const { m } = await turn({ kind: 'none' }, 'hello', { ...BASE, closure: { id: 5, quotes: 'withdraw' } });
  assertMatch(m.seen[0].input, /REVEALED TO HIM: RFQ-90/);
  assertMatch(m.seen[0].input, /WAITING CLOSURE: close his account \(withdrawing/);
});

Deno.test('S1 EN e-mail: "is the old tile to be removed on RFQ-102?" is filed as one question row on that request, sourced e-mail', async () => {
  const { r, a } = await turn({ kind: 'job_question', request: 'RFQ-102', question: 'Is the old tile to be removed?' }, 'RFQ-102: is the old tile to be removed?', BASE, ESTIMATOR);
  assert(r.handled && r.outcome!.done);
  const ins = a.inserts.find((x) => x.table === 'rfq_clarification')!;
  assertEquals(ins.row.inquiry_id, BASE.requests[1].inquiry_id);
  assertEquals(ins.row.source, 'email');
  assertEquals(ins.row.asked_by_email, 'zz-demo-est@example.invalid');
  assertMatch(r.outcome!.facts, /sales engineer reads it against the request first/);
  assertMatch(r.outcome!.facts, /Do not answer the question yourself/);
});

Deno.test('S2 AR WhatsApp: an Arabic ceiling-height question with no reference and two open requests asks which; nothing filed', async () => {
  const { r, a } = await turn({ kind: 'job_question', question: 'كم ارتفاع السقف؟' }, 'كم ارتفاع السقف؟');
  assertEquals(a.inserts.length, 0);
  assertMatch(r.outcome!.facts, /did not say which/);
  assert(!/[؀-ۿ]/.test(r.outcome!.facts.replace(/"[^"]*"/g, '')), 'the facts for a supplier are English');
});

Deno.test('S3 AR: a question that names a request the model invented is not trusted, and asks which', async () => {
  const { a, r } = await turn({ kind: 'job_question', request: 'RFQ-999', question: 'هل المواد من المورد؟' }, 'RFQ-999 هل المواد من المورد؟');
  assertEquals(a.inserts.length, 0);
  assertMatch(r.outcome!.facts, /Ask him which request/);
});

Deno.test('S4 EN owner: "close my account" with 2 live quotations and no word on them asks keep or withdraw; nothing changes', async () => {
  const { r, a } = await turn({ kind: 'close_account', reason: 'retiring' }, 'Please close our account, we are retiring');
  assertEquals(fns(a), []);
  assertMatch(r.outcome!.facts, /WITHDRAW them or KEEP them/);
  assertMatch(r.outcome!.facts, /Nothing was changed yet/);
});

Deno.test('S5 AR owner: "أغلقوا حسابنا واسحبوا عروضنا" is PROPOSED with what the law keeps, closed only after his yes', async () => {
  const { r, a } = await turn({ kind: 'close_account', keep_quotes: false, reason: 'closing the company' }, 'أرجو إغلاق حسابنا وسحب عروض الأسعار');
  assertEquals(fns(a), ['fn_supplier_close_propose']);
  assertEquals(a.calls[0].args.p_quotes, 'withdraw');
  assertEquals(a.calls[0].args.p_actor, 'zz-demo-owner@example.invalid');
  assertMatch(r.outcome!.facts, /Prepared, NOT yet done/);
  assertMatch(r.outcome!.facts, /2031-12-31/);
  assertMatch(r.outcome!.facts, /Cabinet Decision 74\/2023/);
  assertMatch(r.outcome!.facts, /copy of his data/);
});

Deno.test('S6 EN owner: "yes, close it" on the waiting closure closes it and reports what changed and what the law keeps', async () => {
  const { r, a } = await turn({ kind: 'close_confirm' }, 'yes close it', { ...BASE, closure: { id: 5, quotes: 'withdraw' } });
  assertEquals(fns(a), ['fn_supplier_close_decide']);
  assertEquals(a.calls[0].args.p_decision, 'confirm');
  assertMatch(r.outcome!.facts, /his account is closed/);
  assertMatch(r.outcome!.facts, /2 quotation\(s\) were withdrawn/);
  assertMatch(r.outcome!.facts, /already paid to see his details keep that right/);
  assertMatch(r.outcome!.facts, /written confirmation was e-mailed/);
});

Deno.test('S7 AR owner: "لا، أبقوا الحساب" cancels the waiting closure', async () => {
  const { r, a } = await turn({ kind: 'close_cancel' }, 'لا، أبقوا الحساب مفتوحًا', { ...BASE, closure: { id: 5, quotes: 'keep' } });
  assertEquals(a.calls[0].args.p_decision, 'cancel');
  assertMatch(r.outcome!.facts, /stays open/);
});

Deno.test('S8 EN estimator: an estimator cannot close the company; no routine is called, he is told to ask the owner', async () => {
  const { r, a } = await turn({ kind: 'close_account', keep_quotes: true }, 'close the account', BASE, ESTIMATOR);
  assertEquals(fns(a), []);
  assertEquals(r.outcome!.done, false);
  assertMatch(r.outcome!.facts, /an estimator of this company, not its owner/);
  assertMatch(r.outcome!.facts, /only the owner can close the account/);
});

Deno.test('S9 EN viewer: a viewer asking a job question is told his access is read only; nothing filed', async () => {
  const { r, a } = await turn({ kind: 'job_question', request: 'RFQ-101', question: 'What brand of mixer?' }, 'RFQ-101 what brand of mixer?', BASE, VIEWER);
  assertEquals(a.inserts.length, 0);
  assertMatch(r.outcome!.facts, /a viewer \(read only\)/);
});

Deno.test('S10 EN estimator: "the customer on RFQ-90 is not answering my calls" nudges once and keeps it as evidence', async () => {
  const { r, a } = await turn({ kind: 'customer_silent', request: 'RFQ-90', reason: 'called three times' }, 'The customer on RFQ-90 is not answering my calls', BASE, ESTIMATOR);
  assertEquals(fns(a), ['fn_supplier_customer_not_answering']);
  assertEquals(a.calls[0].args.p_inquiry, BASE.revealed![0].inquiry_id);
  assertEquals(a.calls[0].args.p_actor, 'zz-demo-est@example.invalid');
  assertMatch(r.outcome!.facts, /reminded the customer on RFQ-90 once/);
  assertMatch(r.outcome!.facts, /counts if the customer later claims/);
});

Deno.test('S11 AR: "العميل لا يرد" when nobody revealed him says there is no customer to remind; nothing sent', async () => {
  const { r, a } = await turn({ kind: 'customer_silent' }, 'العميل لا يرد على اتصالاتي', { ...BASE, revealed: [] });
  assertEquals(fns(a), []);
  assertMatch(r.outcome!.facts, /No customer has revealed him yet/);
});

Deno.test('S12 EN: a second nudge on the same reveal is refused by the routine and said plainly', async () => {
  const { r } = await turn({ kind: 'customer_silent', request: 'RFQ-90' }, 'still not answering on RFQ-90', BASE, OWNER, { fn_supplier_customer_not_answering: { ok: true, already: true } });
  assertMatch(r.outcome!.facts, /already reminded once; we do not remind twice/);
});

Deno.test('S13 EN: "I will pay 2,000 a month for all villa painting jobs" is a demand signal; he is told nobody can pay to rank', async () => {
  const { r, a } = await turn({ kind: 'paid_leads', asked_for: 'exclusive villa painting jobs', trade: 'painting', size: 'villas', reason: 'offers AED 2,000 a month' }, 'I will pay 2,000 a month for all villa painting jobs');
  assertEquals(fns(a), ['fn_supplier_demand_signal_record']);
  assertEquals(a.calls[0].args.p_asked_for, 'exclusive villa painting jobs');
  assertMatch(r.outcome!.facts, /nobody can pay to rank higher/);
  assertMatch(r.outcome!.facts, /Promise nothing else/);
});

Deno.test('S14 AR viewer: even a viewer\'s offer to pay for priority is recorded (it is only demand), and the same policy is said', async () => {
  const { r, a } = await turn({ kind: 'paid_leads', asked_for: 'priority on requests' }, 'مستعدون للدفع مقابل أولوية في الطلبات', BASE, VIEWER);
  assertEquals(fns(a), ['fn_supplier_demand_signal_record']);
  assertMatch(r.outcome!.facts, /every matched supplier receives the request/);
});

Deno.test('S15 EN estimator: "stop sending us painting" is the owner\'s to decide; an estimator is refused before any proposal', async () => {
  const { r, a } = await turn({ kind: 'remove_work', trades: ['painting'] }, 'stop sending us painting jobs', BASE, ESTIMATOR);
  assertEquals(fns(a), []);
  assertMatch(r.outcome!.facts, /change what work the company receives/);
});

// W3_PEOPLE, 16 Nov 2026 (wave-3 items 2 and 4): "can I invite another company?" and "our owner has left" on any channel.
Deno.test('S16 EN viewer: "can I invite my friend\'s company?" gives the company\'s own referral link; we send nothing ourselves', async () => {
  const { r, a } = await turn({ kind: 'refer_company' }, 'can I invite my friend\'s company?', BASE, VIEWER,
    { fn_supplier_referral_link: { ok: true, referral_code: 'qdabc123def4', url: 'https://quotesdone.com/en/supplier?utm_source=referral&utm_medium=supplier&utm_content=qdabc123def4', registered: 1, approved: 0 } });
  assertEquals(fns(a), ['fn_supplier_referral_link']);
  assertEquals(a.calls[0].args, { p_lead: 42 });
  assertMatch(r.outcome!.facts, /utm_content=qdabc123def4/);
  assertMatch(r.outcome!.facts, /we do not write to them ourselves/);
  assertMatch(r.outcome!.facts, /1 compan/);
});

Deno.test('S17 EN: a company not yet approved is told the link comes with approval; nothing is promised', async () => {
  const { r } = await turn({ kind: 'refer_company' }, 'send me a referral link', BASE, OWNER, { fn_supplier_referral_link: { ok: false, code: 'not_approved' } });
  assertMatch(r.outcome!.facts, /once the company is approved/);
});

Deno.test('S18 AR estimator: "the owner left the company" opens the case for the sales engineer, in his name, and he is told what happens next', async () => {
  const { r, a } = await turn({ kind: 'owner_left', reason: 'the owner sold his share and left the UAE in October' }, 'المالك ترك الشركة وسافر، أريد إدارة الحساب', BASE, ESTIMATOR,
    { fn_supplier_ownership_claim_open: { ok: true, claim_id: 9, state: 'open' } });
  assertEquals(fns(a), ['fn_supplier_ownership_claim_open']);
  assertEquals(a.calls[0].args, { p_lead: 42, p_actor: 'zz-demo-est@example.invalid', p_reason: 'the owner sold his share and left the UAE in October', p_channel: 'email' });
  assertMatch(r.outcome!.facts, /sales engineer/);
  assertMatch(r.outcome!.facts, /owner has been told/);
  assertMatch(r.outcome!.facts, /Nothing changes/);
});

Deno.test('S19 EN owner: the owner himself saying "the owner left" opens nothing; a stranger\'s refusal is said plainly', async () => {
  const own = await turn({ kind: 'owner_left', reason: 'my partner left' }, 'my partner left the company', BASE, OWNER);
  assertEquals(fns(own.a), []);
  assertMatch(own.r.outcome!.facts, /already the owner/);
  const no = await turn({ kind: 'owner_left', reason: 'he left' }, 'the owner left', BASE, VIEWER,
    { fn_supplier_ownership_claim_open: { ok: false, code: 'not_a_member', error: 'Only a member of this company can ask to take it over.' } });
  assertMatch(no.r.outcome!.facts, /Only a member of this company/);
});

// THE OWNER'S REPLY KEEPS HIS COMPANY, AND ONLY THE OWNER'S (REVIEW2 W3PEOPLE, 16 Nov 2026). Both owner notices of a claim say "or
// reply to this e-mail"; the reader kind owner_keeps calls fn_supplier_ownership_claim_object, which closes the member's claim. A
// member who writes the very same words, and whom the model reads the very same way, must reach no routine at all: he is not the
// owner, and keeping the company is the owner's word alone. ZZ DEMO addresses only; the model is a stub.
const KEEP_EN = 'I have not left. I am still the owner of this company and I do not agree that anyone takes it over.';
const KEEP_AR = 'لم أترك الشركة، ما زلت المالك ولا أوافق على نقل الحساب لأي شخص.';
const KEPT = { ok: true, claim_id: 9, state: 'objected' };

Deno.test('S20 the reader knows owner_keeps, and only the owner may give it', () => {
  assert(INSTRUCTION_SYS.includes('- owner_keeps:'));
  assert(memberMayInstruct('owner', 'owner_keeps'));
  assert(!memberMayInstruct('estimator', 'owner_keeps') && !memberMayInstruct('viewer', 'owner_keeps'));
});

Deno.test('S20 EN/AR owner: "I am still the owner" keeps the company in his own name, and he is told so', async () => {
  for (const msg of [KEEP_EN, KEEP_AR]) {
    const { r, a } = await turn({ kind: 'owner_keeps' }, msg, BASE, OWNER, { fn_supplier_ownership_claim_object: KEPT });
    assertEquals(fns(a), ['fn_supplier_ownership_claim_object']);
    assertEquals(a.calls[0].args, { p_lead: 42, p_actor: 'zz-demo-owner@example.invalid' });
    assertEquals(r.outcome!.done, true);
    assertMatch(r.outcome!.facts, /He keeps the company/);
  }
  const none = await turn({ kind: 'owner_keeps' }, KEEP_EN, BASE, OWNER, { fn_supplier_ownership_claim_object: { ok: true, nothing_waiting: true } });
  assertMatch(none.r.outcome!.facts, /No member has asked/);
});

Deno.test('S20 EN/AR estimator and viewer: the same words, read the same way, reach no routine and keep nothing', async () => {
  for (const sender of [ESTIMATOR, VIEWER]) {
    for (const msg of [KEEP_EN, KEEP_AR]) {
      const { r, a, m } = await turn({ kind: 'owner_keeps' }, msg, BASE, sender, { fn_supplier_ownership_claim_object: KEPT });
      assertEquals(m.seen.length, 1);              // the model did read it as owner_keeps
      assertEquals(fns(a), []);                    // and code stopped it before any routine
      assertEquals(r.outcome!.kind, 'owner_keeps');
      assertEquals(r.outcome!.done, false);
      assertMatch(r.outcome!.facts, /not its owner/);
    }
  }
});

Deno.test('S20 a sender the door took for the owner, whom the routine does not (the owner changed): refused plainly, nothing kept', async () => {
  const { r, a } = await turn({ kind: 'owner_keeps' }, KEEP_EN, BASE, OWNER, { fn_supplier_ownership_claim_object: { ok: false, code: 'owner_only' } });
  assertEquals(fns(a), ['fn_supplier_ownership_claim_object']);
  assertEquals(r.outcome!.done, false);
  assertMatch(r.outcome!.facts, /Only the owner of the company can keep it\. Nothing was changed\./);
});
