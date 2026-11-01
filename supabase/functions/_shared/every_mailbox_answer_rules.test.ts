// deno test supabase/functions/_shared/every_mailbox_answer_rules.test.ts
// EVERY MAILBOX IS READ (2 Nov 2026): what a handed message to management@ changes in the answer rules, with controls, and
// that email_triage is wired to them. A reply never reaches the founder, a machine, or someone who said stop.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { declinedRowFields, noAutoReply, tenantMailAnswerable } from './customer_mail.ts';

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

Deno.test('wiring: email_triage uses these rules, checks the founder\'s own inboxes, and a failed answer leaves a live review', async () => {
  const src = await Deno.readTextFile(new URL('../email_triage/index.ts', import.meta.url));
  assert(src.includes('tenantMailAnswerable(m, !!(sup && sup.length))'));
  assert(src.includes("rpc('fn_is_founder_own_inbox'"));
  assert(src.includes('...declinedRowFields(m)'));
  assert(src.includes("await reply1(m, m.lead_id ? 'supplier' : 'customer')"));
  assert(/counts\.answer_failed\+\+[\s\S]{0,700}kind: 'inbound_review', status: 'pending'/.test(src), 'a failed answer no longer files a review');
});
