// What an expense document is, who issued it, and what a bank line is — reasoned with a MOCKED model.
// No network, no env, no paid call. ZZ DEMO / example.invalid only.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { bankLineKind, deliverBooks, documentKind, readingOf, reasonBankLines, receiptVendor, type ExpenseMail } from './reasoned_books.ts';

const J = (x: unknown) => JSON.stringify(x);
const PLAN = J({ steps: [{ id: 's1', goal: 'read the document', needs_knowledge: false }], facts: [] });
function mock(o: { held?: boolean; choices?: (string | Record<string, unknown>)[]; lines?: unknown[] }) {
  const rpcs: [string, Record<string, unknown>][] = []; const systems: string[] = [];
  const choices = [...(o.choices ?? [])];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve(o.held ? { allowed: false, rule: 'founder_hold' } : { allowed: true, rule: 'ok' }),
    llm: (phase: Phase, system: string) => {
      systems.push(system);
      if (phase === 'decompose') return Promise.resolve({ content: PLAN } as LlmReply);
      const c = choices.shift();
      const decision = typeof c === 'string' ? { choice: c } : { fields: c };
      return Promise.resolve({ content: J({ answer: 'Reasoned from the document as a whole.', reasoning: ['s1: read it'], decision }), model: 'm' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_reason_hold') return Promise.resolve({ data: 9, error: null });
      if (fn === 'fn_accountant_bank_lines_to_reason') return Promise.resolve({ data: { owner: 'ZZ DEMO OWNER', lines: o.lines ?? [] }, error: null });
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  return { deps, rpcs, systems };
}
const MAIL: ExpenseMail = { emailId: 'zz-demo-1', from: 'founder@example.invalid', to: 'expenses@mail.quotesdone.com',
  subject: 'Fw: Your receipt', text: 'From: ZZ DEMO Vendor <billing@example.invalid>\nTotal AED 20.00', filenames: ['receipt.pdf'], mailbox: 'expenses', providerEmailId: 'zz-demo-1' };
const RENEWALS = [{ item: 'trade_licence_det_1633275', kind: 'licence', expires_on: '2027-06-24' }];

Deno.test('the document kind is a reasoned choice among named options, renewals included', async () => {
  const m = mock({ choices: ['renewal:trade_licence_det_1633275'] });
  const r = await documentKind(m.deps, MAIL, RENEWALS, []);
  assertEquals(r.value, 'renewal:trade_licence_det_1633275');
  assertEquals(readingOf(r.value!), { period: 'annual', readAs: 'renewal', renewsItem: 'trade_licence_det_1633275' });
  assert(m.systems.some((s) => /renewal:trade_licence_det_1633275/.test(s)), 'the renewal is offered as an option');
  assertEquals(readingOf('receipt_monthly'), { period: 'monthly', readAs: 'receipt_monthly', renewsItem: null });
  assertEquals(readingOf('meta_ads_invoice')?.readAs, 'meta_ads_invoice');
  assertEquals([readingOf('bank_statement'), readingOf('other')], [null, null]);
});

Deno.test('an option that does not exist is refused, and a model that keeps inventing is held, never guessed', async () => {
  const m = mock({ choices: ['receipt_weekly', 'receipt_weekly'] });
  const r = await documentKind(m.deps, MAIL, [], []);
  assertEquals(r.value, null);
  assertEquals(r.result.status, 'held');
  assert(m.rpcs.some(([f, a]) => f === 'fn_reason_hold' && a.p_surface === 'accountant.document_kind'));
});

Deno.test('under the hold: nothing is chosen, the question is queued for the accountant with the email it is about', async () => {
  const m = mock({ held: true });
  const r = await documentKind(m.deps, MAIL, RENEWALS, []);
  assertEquals([r.value, r.result.status], [null, 'held']);
  const [, a] = m.rpcs.find(([f]) => f === 'fn_reason_hold')!;
  assertEquals([a.p_seat, a.p_surface, a.p_dedupe_key], ['accountant', 'accountant.document_kind', 'expense_kind:zz-demo-1']);
  assertEquals((a.p_subject as Record<string, unknown>).mailbox, 'expenses');
  // a dry run reasons but files nothing
  const d = mock({ held: true });
  await documentKind(d.deps, { ...MAIL, dryRun: true }, [], []);
  assertEquals(d.rpcs.filter(([f]) => f === 'fn_reason_hold').length, 0);
});

Deno.test('the vendor: a known one by choice; an unknown one by a second decision quoting the document', async () => {
  const known = await receiptVendor(mock({ choices: ['Apify'] }).deps, MAIL, ['Apify', 'apify', 'Vercel']);
  assertEquals(known.value, 'Apify');
  const named = await receiptVendor(mock({ choices: ['another_vendor', { vendor: { value: 'ZZ DEMO Vendor', evidence: 'From: ZZ DEMO Vendor' } }] }).deps, MAIL, ['Apify']);
  assertEquals(named.value, 'ZZ DEMO Vendor');
  // a name not in the document is refused twice and held: no invented vendor
  const invented = await receiptVendor(mock({ choices: ['another_vendor', { vendor: { value: 'Acme', evidence: 'Acme Corp LLC' } }, { vendor: { value: 'Acme', evidence: 'Acme Corp LLC' } }] }).deps, MAIL, []);
  assertEquals(invented.value, null);
  const held = mock({ held: true });
  assertEquals((await receiptVendor(held.deps, MAIL, ['Apify'])).value, null);
  assertEquals(held.rpcs.find(([f]) => f === 'fn_reason_hold')![1].p_dedupe_key, 'expense_vendor:zz-demo-1');
});

Deno.test('a bank line: reasoned, recorded; under the hold its kind stays empty and it waits in the queue', async () => {
  const line = { id: 501, value_date: '2026-09-01', description: 'ZZ DEMO Monthly Maintenance Fee 000', amount_aed: -199, account: 'zz_demo' };
  const m = mock({ choices: ['bank_charge'], lines: [line] });
  assertEquals(await reasonBankLines(m.deps), { reasoned: 1, held: 0 });
  const [, rec] = m.rpcs.find(([f]) => f === 'fn_accountant_bank_line_reasoned')!;
  assertEquals([rec.p_line_id, rec.p_kind, rec.p_by], [501, 'bank_charge', 'reasoning']);
  const h = mock({ held: true, lines: [line] });
  assertEquals(await reasonBankLines(h.deps), { reasoned: 0, held: 1 });
  assertEquals(h.rpcs.some(([f]) => f === 'fn_accountant_bank_line_reasoned'), false, 'nothing recorded on a guess');
  assertEquals(h.rpcs.find(([f]) => f === 'fn_reason_hold')![1].p_subject, { line_id: 501 });
  const owner = mock({ choices: ['owner_transfer'] });
  const o = await bankLineKind(owner.deps, { ...line, amount_aed: 1000, description: 'ZZ DEMO IPP TRANSFER' }, 'ZZ DEMO OWNER');
  assertEquals(o.value, 'owner_transfer');
  assert(owner.systems.some((s) => /ZZ DEMO OWNER/.test(s)));
});

Deno.test('the replay: the expenses mailbox re-runs the sweep; another mailbox goes to the bookkeeper; "other" does nothing', async () => {
  const log: string[] = [];
  const io = { accountantSweep: (id: string) => { log.push('sweep ' + id); return Promise.resolve({ ok: true }); },
               receiptToBookkeeper: (id: string) => { log.push('bk ' + id); return Promise.resolve({ ok: true }); } };
  const res = (choice: string) => ({ status: 'answered' as const, answer: 'x', decision: { choice, fields: {} }, steps: [], context_used: {}, missing_context: [], sources: [], confidence: 1 });
  const row = (surface: string, subject: Record<string, unknown>) => ({ id: 1, seat: 'accountant', surface, subject, request: { seat: 'accountant' as const, surface, question: 'q' } });
  assertEquals((await deliverBooks(row('accountant.document_kind', { email_id: 'e1', mailbox: 'expenses' }), res('receipt_one_off'), io))?.via, 'accountant_sweep');
  assertEquals((await deliverBooks(row('accountant.document_kind', { email_id: 'e2', mailbox: 'other', provider_email_id: 'p2' }), res('meta_ads_invoice'), io))?.via, 'bookkeeper');
  assertEquals((await deliverBooks(row('accountant.document_kind', { email_id: 'e3', mailbox: 'expenses' }), res('other'), io))?.via, 'none');
  assertEquals(await deliverBooks(row('wa_inbound.needs_a_person', {}), res('x'), io), null);
  assertEquals(log, ['sweep e1', 'bk p2']);
});
