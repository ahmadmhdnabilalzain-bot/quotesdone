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

Deno.test('a held ANSWER on WhatsApp goes back as the answer, under the same window rule', async () => {
  const { x, log } = io(false);
  const d = await deliverReasoned(row('think.answer', 'what depth can my pool be?', { channel: 'whatsapp', phone: '+971500000001' }, false),
    answered(null, 'In Dubai private pools need a DM permit; which emirate is the villa in?'), x);
  assertEquals(d.via, 'whatsapp_template');
  assertMatch(log[0], /\[what depth can my pool be\?\] In Dubai/);
});
