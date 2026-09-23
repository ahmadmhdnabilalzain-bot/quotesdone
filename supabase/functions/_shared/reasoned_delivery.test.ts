// A held question, reasoned after the hold lifts, is delivered on its own channel under the channel's rules.
import { assertEquals, assertMatch } from 'jsr:@std/assert';
import { deliverReasoned, type DeliveryIO } from './reasoned_delivery.ts';
import type { HeldRow, ThinkResult } from './think.ts';

function io(windowOpen: boolean) {
  const log: string[] = [];
  const x: DeliveryIO = {
    waWindowOpen: () => Promise.resolve(windowOpen),
    sendWaText: (p, b) => { log.push('text ' + p + ' ' + b); return Promise.resolve({ ok: true }); },
    queueWaTemplate: (p, q, a, l) => { log.push(`template ${p} ${l} [${q}] ${a}`); return Promise.resolve({ ok: true }); },
    founderContact: () => Promise.resolve('+971 50 000 0000'),
    reportToCeo: (k) => { log.push('ceo ' + k); return Promise.resolve(); },
    socialHandoff: (s) => { log.push('social ' + s.platform + ' ' + s.message_id); return Promise.resolve({ ok: true }); },
    socialCommentHandoff: (s) => { log.push('comment ' + s.platform + ' ' + s.message_id); return Promise.resolve({ ok: true }); },
    accountantSweep: (id) => { log.push('sweep ' + id); return Promise.resolve({ ok: true, found: true, verdict: 'booked' }); },
    receiptToBookkeeper: (id) => { log.push('bookkeeper ' + id); return Promise.resolve({ ok: true }); },
    outreachPage: () => Promise.resolve({ full_name: 'ZZ DEMO Sara', language: 'en' as const }),
    outreachReasoned: (t, c, f) => { log.push(`outreach ${t} ${c} ${f ? 'draft' : 'none'}`); return Promise.resolve({ ok: true }); },
  };
  return { x, log };
}
const row = (surface: string, question: string, subject: Record<string, unknown>, decision = true): HeldRow => ({
  id: 7, seat: 'customer_support', surface, subject,
  request: { seat: 'customer_support', surface, question, ...(decision ? { decision: { name: 'needs_a_person', options: [{ id: 'needs_a_person', meaning: '' }, { id: 'no_person', meaning: '' }] } } : {}) },
});
const answered = (choice: string | null, answer = 'They accuse us of taking money: a person is needed.'): ThinkResult =>
  ({ status: 'answered', answer, decision: { choice, fields: {} }, steps: [], context_used: {}, missing_context: [], sources: [], confidence: 0.8 });

Deno.test('WhatsApp, inside the 24-hour window: the contact goes as free text, and the CEO sees it', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('wa_inbound.needs_a_person', 'you took my money and vanished', { phone: 'whatsapp:+971500000001' }), answered('needs_a_person'), x);
  assertEquals([d.delivered, d.via], [true, 'whatsapp_text']);
  assertEquals(log[0], 'ceo reasoned:person:7');
  assertMatch(log[1], /^text whatsapp:\+971500000001 Thank you for your patience.*\+971 50 000 0000/);
});

Deno.test('WhatsApp, outside the window: only an approved template is allowed, so a support_reply row is queued', async () => {
  const { x, log } = io(false);
  const d = await deliverReasoned(row('wa_inbound.needs_a_person', 'نصبتوا علي', { phone: '+971500000001' }), answered('needs_a_person'), x);
  assertEquals([d.delivered, d.via], [true, 'whatsapp_template']);
  assertMatch(log[1], /^template \+971500000001 ar \[نصبتوا علي\] شكرًا لصبركم/);
  assertEquals(log.some((l) => l.startsWith('text')), false, 'no free text outside the window');
});

Deno.test('reasoned to need no person: nothing is sent again', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('wa_inbound.needs_a_person', 'is it legal to build a pool?', { phone: '+971500000001' }), answered('no_person'), x);
  assertEquals([d.delivered, d.via], [false, 'none']);
  assertEquals(log, []);
});

Deno.test('social: the handoff goes through the platform reply path', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('marketing_social.needs_a_person', 'is anyone actually there?', { platform: 'instagram', message_id: 'm1' }), answered('needs_a_person'), x);
  assertEquals([d.delivered, d.via], [true, 'social']);
  assertEquals(log, ['social instagram m1']);
});

Deno.test('a public comment reasoned to need a person gets the private handoff; one that does not gets nothing more', async () => {
  const { x, log } = io(true);
  const yes = await deliverReasoned(row('marketing_social.comment_needs_a_person', 'still waiting for my refund', { platform: 'youtube', message_id: 'c1' }), answered('needs_a_person'), x);
  assertEquals([yes.delivered, yes.via], [true, 'social']);
  const no = await deliverReasoned(row('marketing_social.comment_needs_a_person', 'is it legal to paint a villa blue?', { platform: 'youtube', message_id: 'c2' }), answered('no_person'), x);
  assertEquals([no.delivered, no.via], [false, 'none']);
  assertEquals(log, ['comment youtube c1']);
});

Deno.test('a held ANSWER on WhatsApp goes back as the answer, under the same window rule', async () => {
  const { x, log } = io(false);
  const d = await deliverReasoned(row('think.answer', 'what depth can my pool be?', { channel: 'whatsapp', phone: '+971500000001' }, false),
    answered(null, 'In Dubai private pools need a DM permit; which emirate is the villa in?'), x);
  assertEquals(d.via, 'whatsapp_template');
  assertMatch(log[0], /\[what depth can my pool be\?\] In Dubai/);
});

// Batch 8 (accountant + marketing): the effect of an expense or outreach reasoning, reached through deliverReasoned.
Deno.test('an expenses-mailbox email reasoned to be a receipt re-runs the accountant sweep; one reasoned "other" goes to the bookkeeper', async () => {
  const { x, log } = io(true);
  const sub = { email_id: 'zz-demo-e1', mailbox: 'expenses', provider_email_id: 'zz-demo-e1' };
  const yes = await deliverReasoned(row('accountant.document_kind', 'Fw: receipt', sub), answered('receipt_monthly', 'A monthly subscription receipt.'), x);
  assertEquals([yes.delivered, yes.via], [true, 'accountant_sweep']);
  const no = await deliverReasoned(row('accountant.document_kind', 'Fw: hello', sub), answered('other', 'Not an expense.'), x);
  assertEquals([no.delivered, no.via], [true, 'bookkeeper'], 'an expenses-mailbox email reasoned "other" still reaches a person');
  const other = await deliverReasoned(row('accountant.receipt_vendor', 'Fw: invoice', { email_id: 'zz-demo-e2', mailbox: 'other', provider_email_id: 'zz-demo-e2' }), answered('Apify', 'Apify issued it.'), x);
  assertEquals([other.delivered, other.via], [true, 'bookkeeper']);
  assertEquals(log, ['sweep zz-demo-e1', 'bookkeeper zz-demo-e1', 'bookkeeper zz-demo-e2']);
});

Deno.test('a LinkedIn reply reasoned after the hold gets its class and its drafted follow-up', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('marketing.outreach_reply', 'thanks, not for now', { mark_token: 'zz-tok' }), answered('later', 'Not now, not a refusal.'), x);
  assertEquals([d.delivered, d.via], [true, 'outreach_follow_up']);
  assertEquals(log, ['outreach zz-tok later draft']);
});
