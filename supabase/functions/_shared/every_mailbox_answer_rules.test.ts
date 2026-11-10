// deno test supabase/functions/_shared/every_mailbox_answer_rules.test.ts
// EVERY MAILBOX IS READ (2 Nov 2026): what a handed message to management@ changes in the answer rules, with controls, and
// that email_triage is wired to them. A reply never reaches the founder, a machine, or someone who said stop.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DAILY_AUTO_ANSWER_CAP, declinedRowFields, noAutoReply, overDailyAnswerCap, tenantMailAnswerable } from './customer_mail.ts';
import { accountFacts, SEPARATE_COMPANY_FACT, SUPPLIER_SIGN_IN_FACT, supplierFacts, unregisteredSupplierFacts } from '../email_triage/account_facts.ts';
import { planCreateCompany } from '../supplier_api/create_company.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const FOUNDER = ['management@quotesdone.com', 'owner@example.invalid'];

Deno.test('management@: a stranger and a supplier get the normal triage; the founder, our domains, machines and stop mail do not', () => {
  const to = (o: Record<string, unknown> = {}) => ({ from_email: 'info@zz-demo.example.invalid', to_email: 'management@quotesdone.com', subject: 'Registering a subsidiary', body: 'Please advise.', ...o });
  assertEquals(noAutoReply(to(), FOUNDER), 'internal');
  assertEquals(tenantMailAnswerable(to()), true);
  assertEquals(tenantMailAnswerable(to({ to_email: 'expenses@mail.quotesdone.com' })), false);
  assertEquals(tenantMailAnswerable(to({ to_email: 'expenses@quotesdone.com' })), false);
  assertEquals(tenantMailAnswerable(to({ to_email: 'supplier@quotesdone.com' })), false, 'supplier@ keeps its own rule');
  assertEquals(tenantMailAnswerable(to({ from_email: 'x@mail.quotesdone.com' })), false);
  assertEquals(tenantMailAnswerable(to({ owner_role: 'accountant' })), false);
  assertEquals(tenantMailAnswerable(to(), true), false, 'suppressed');
  assertEquals(tenantMailAnswerable(to({ subject: 'Automatic reply: away' })), false);
  assertEquals(noAutoReply(to({ to_email: '', from_email: 'management@quotesdone.com' }), FOUNDER), 'founder');
});

Deno.test('no loop: a Microsoft report, a no-reply sender, an out-of-office and a mailing list are not answered on any mailbox', () => {
  const info = (o: Record<string, unknown> = {}) => ({ from_email: 'a@zz-demo.example.invalid', to_email: 'info@quotesdone.com', subject: 'Hi', ...o });
  assertEquals(noAutoReply(info(), FOUNDER), null);
  assertEquals(noAutoReply(info({ from_email: 'MicrosoftExchange329e71ec88ae4615bbc36ab6ce41109e@NETORGFT20811795.onmicrosoft.com' }), FOUNDER), 'bounce');
  assertEquals(noAutoReply(info({ from_email: 'no-reply@zz-demo.example.invalid' }), FOUNDER), 'no_reply');
  assertEquals(noAutoReply(info({ subject: 'Out of office' }), FOUNDER), 'auto_submitted');
  assertEquals(noAutoReply(info({ raw: { list_unsubscribe: '<mailto:x@y.invalid>' } }), FOUNDER), 'auto_submitted');
});

Deno.test('a declined machine mail from another mailbox has an owner and leaves the Inbox; supplier@ and Resend mail are untouched', () => {
  assertEquals(declinedRowFields({ to_email: 'management@quotesdone.com', provider_email_id: 'm365:A' }), { owner_role: 'customer_support', needs_review: false });
  assertEquals(declinedRowFields({ to_email: 'supplier@quotesdone.com', provider_email_id: 'm365:A' }), {});
  assertEquals(declinedRowFields({ to_email: 'info@mail.quotesdone.com', provider_email_id: 'abc' }), {});
});

Deno.test('a subsidiary: the facts say what the platform really does, and it does refuse a second company on one e-mail', () => {
  assertEquals(planCreateCompany({ ownCompany: true, emailLeads: [], emailProven: true }).kind, 'company_exists');
  assertEquals(planCreateCompany({ ownCompany: false, emailLeads: [{ id: 1, claimed: true, claimed_by: 'sales@zz-demo.example.invalid' }], emailProven: true }).kind, 'email_taken');
  assertEquals(planCreateCompany({ ownCompany: false, emailLeads: [], emailProven: true }).kind, 'insert');
  for (const f of [SEPARATE_COMPANY_FACT]) {
    assert(f.includes('its own trade licence') && f.includes('different work e-mail') && f.includes('one e-mail manages exactly one company'));
  }
  for (const t of [supplierFacts('ZZ DEMO', []), supplierFacts('ZZ DEMO', [{ inquiry_id: 1 }]), unregisteredSupplierFacts('ZZ DEMO', 'https://x.invalid/portal'), SUPPLIER_SIGN_IN_FACT]) {
    assert(t.includes(SEPARATE_COMPANY_FACT));
  }
});

Deno.test('an account holder whose address is not the listing\'s still gets the company facts', async () => {
  const seen: string[] = [];
  const db = { from: () => {
    let col = '';
    // deno-lint-ignore no-explicit-any
    const q: any = { select: () => q, eq: () => q, order: () => q, in: () => q,
      ilike: (c: string) => { col = c; seen.push(c); return q; },
      limit: () => Promise.resolve({ data: col === 'claimed_by' ? [{ id: 7, company_name: 'ZZ DEMO', claimed: true }] : col === 'email' ? [] : [] }) };
    return q;
  } };
  const facts = await accountFacts(db, 'sales@zz-demo.example.invalid', 'supplier');
  assertEquals(seen, ['email', 'claimed_by']);
  assert(facts.includes('ZZ DEMO'), facts);
});

Deno.test('the per-sender daily cap stops an autoresponder loop', () => {
  assertEquals(overDailyAnswerCap(DAILY_AUTO_ANSWER_CAP - 1), false);
  assertEquals(overDailyAnswerCap(DAILY_AUTO_ANSWER_CAP), true);
  assertEquals(overDailyAnswerCap(null), false);
});

Deno.test('every insert in resend_inbound records provider_email_id, so nothing can be handed twice', async () => {
  // The whole function, not index.ts alone: since the split the inserts live in resend_inbound/steps/*.ts.
  const src = functionSource('resend_inbound');
  const blocks = src.split(".from('inbound_messages').insert(").slice(1).map((b) => b.slice(0, 600));
  assert(blocks.length >= 12, 'found ' + blocks.length);
  for (const b of blocks) assert(b.includes('provider_email_id'), b.slice(0, 160));
});

Deno.test('wiring: email_triage uses these rules, checks the founder\'s own inboxes, and a failed answer leaves a live review', async () => {
  const src = await Deno.readTextFile(new URL('../email_triage/index.ts', import.meta.url));
  assert(src.includes('tenantMailAnswerable(m, !!(sup && sup.length))'));
  assert(src.includes("rpc('fn_is_founder_own_inbox'"));
  assert(src.includes('...declinedRowFields(m)'));
  assert(src.includes("m.lead_id ? reply1(m, 'supplier', SEPARATE_COMPANY_FACT)"));
  const failed = src.slice(src.indexOf('counts.answer_failed++'), src.indexOf('for (const m of ((msgs'));
  assert(failed.includes("rpc('fn_seat_handoff'") && failed.includes("p_to: 'ceo'"), 'a failed answer no longer reaches the ceo seat');
  assert(!failed.includes('inbound_review'), 'nothing comes back to the founder (ledger 1438)');
  assert(src.includes('overDailyAnswerCap(count)'));
});
