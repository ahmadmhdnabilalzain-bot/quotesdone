// A held question, reasoned after the hold lifts, is delivered on its own channel under the channel's rules.
import { assertEquals, assertMatch } from 'jsr:@std/assert';
import { deliverReasoned, holdingNotice, sendHeldNotices, type DeliveryIO } from './reasoned_delivery.ts';
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
    waIntentReply: (p, _q, intent) => { log.push('intent ' + p + ' ' + intent); return Promise.resolve(intent === 'pricing' ? 'Posting a request is free.' : null); },
    waTrades: () => Promise.resolve([{ code: 'hvac', label: 'HVAC & air conditioning', label_ar: 'التكييف والتهوية', aliases: [] }]),
    socialReply: (s, meaning) => { log.push('reply ' + s.platform + ' ' + s.message_id + ' ' + meaning); return Promise.resolve({ ok: true }); },
    accountantSweep: (id) => { log.push('sweep ' + id); return Promise.resolve({ ok: true, found: true, verdict: 'booked' }); },
    receiptToBookkeeper: (id) => { log.push('bookkeeper ' + id); return Promise.resolve({ ok: true }); },
    outreachPage: () => Promise.resolve({ full_name: 'ZZ DEMO Sara', language: 'en' as const }),
    outreachReasoned: (t, c, f) => { log.push(`outreach ${t} ${c} ${f ? 'draft' : 'none'}`); return Promise.resolve({ ok: true }); },
    arabicFinishReady: () => { log.push('arabic ready'); return Promise.resolve({ ok: true }); },
    socialCommentClassified: (s, c) => { log.push('classified ' + s.platform + ' ' + s.message_id + ' ' + c); return Promise.resolve({ ok: true }); },
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

Deno.test('escalated at 48 hours: a WhatsApp customer is told a person is handling it; a row with no customer channel sends nothing', async () => {
  const { x, log } = io(true);
  const d = await holdingNotice({ id: 9, surface: 'wa_inbound.needs_a_person', question: 'where is my quote?', subject: { phone: '+971500000001' } }, x);
  assertEquals([d.delivered, d.via], [true, 'whatsapp_text']);
  assertMatch(log[0], /^text \+971500000001 Thank you for your patience\. Your question is now with our team/);
  const none = await holdingNotice({ id: 10, surface: 'ceo.command_intent', question: 'stop the campaign', subject: { command_id: 1 } }, x);
  assertEquals([none.delivered, none.via], [false, 'none']);
  assertEquals(log.length, 1);
});

Deno.test('a held ANSWER on WhatsApp goes back as the answer, under the same window rule', async () => {
  const { x, log } = io(false);
  const d = await deliverReasoned(row('think.answer', 'what depth can my pool be?', { channel: 'whatsapp', phone: '+971500000001' }, false),
    answered(null, 'In Dubai private pools need a DM permit; which emirate is the villa in?'), x);
  assertEquals(d.via, 'whatsapp_template');
  assertMatch(log[0], /\[what depth can my pool be\?\] In Dubai/);
});

// ── a held MEANING (reasoned_channels.ts): the answer the reasoned meaning selects, once ────────────
const meaningRow = (surface: string, question: string, subject: Record<string, unknown>): HeldRow => ({
  id: 9, seat: surface.startsWith('wa_') ? 'customer_support' : 'marketing', surface, subject,
  request: { seat: 'customer_support', surface, question, decision: { name: 'q', options: [{ id: 'none', meaning: '' }] } },
});

Deno.test('WhatsApp meaning: an intent is answered by the database, a trade from the live list, size by the statement', async () => {
  const wa = { channel: 'whatsapp', phone: '+971500000021' };
  const a = io(true);
  const i = await deliverReasoned(meaningRow('wa_inbound.intent_table', 'is it free?', wa), answered('intent:pricing'), a.x);
  assertEquals([i.delivered, i.via], [true, 'whatsapp_text']);
  assertEquals(a.log, ['intent +971500000021 pricing', 'text +971500000021 Posting a request is free.']);
  const b = io(true);
  await deliverReasoned(meaningRow('wa_inbound.intent_table', 'هل تقدمون أعمال التكييف', wa), answered('trade:hvac'), b.x);
  assertMatch(b.log[0], /^text \+971500000021 نعم، التكييف والتهوية من التخصصات/);
  const c = io(false);
  const s = await deliverReasoned(meaningRow('wa_inbound.intent_table', 'how many suppliers do you have', wa), answered('size'), c.x);
  assertEquals(s.via, 'whatsapp_template'); // outside the window: the template, never free text
  assertMatch(c.log[0], /^template \+971500000021 en \[how many suppliers do you have\] Thank you for your interest in QuotesDone/);
});

Deno.test('WhatsApp meaning: nothing more is sent for none, for a person (its own held row delivers that), or with no phone', async () => {
  const { x, log } = io(true);
  for (const [choice, subject] of [['none', { phone: '+971500000021' }], ['intent:contact_human', { phone: '+971500000021' }], ['intent:pricing', {}]] as const) {
    const d = await deliverReasoned(meaningRow('wa_inbound.intent_table', 'q', subject), answered(choice), x);
    assertEquals([d.delivered, d.via], [false, 'none'], choice);
  }
  assertEquals(log, []);
});

Deno.test('social meaning: the grounded reply is sent on the platform; none sends nothing', async () => {
  const { x, log } = io(true);
  const subject = { platform: 'instagram', message_id: 'mZZDEMO', passages: [] };
  const d = await deliverReasoned(meaningRow('marketing_social.library_match', 'who sets the warranty?', subject), answered('kb:0'), x);
  assertEquals([d.delivered, d.via], [true, 'social']);
  const n = await deliverReasoned(meaningRow('marketing_social.library_match', 'what is the weather', subject), answered('none'), x);
  assertEquals([n.delivered, n.via], [false, 'none']);
  assertEquals(log, ['reply instagram mZZDEMO kb:0']);
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

Deno.test('a held Arabic translation: a waiting regenerated quotation is rendered and asked for approval; anything else was already stored', async () => {
  const { x, log } = io(true);
  const r = (subject: Record<string, unknown>): HeldRow => ({ id: 9, seat: 'sales_engineer', surface: 'sales_engineer.document_arabic', subject, request: { seat: 'sales_engineer', surface: 'sales_engineer.document_arabic', question: 'x' } });
  // whoever filed the lines first (another document, another quote), every waiting quotation is looked up by its own id
  const d = await deliverReasoned(r({ sources: ['a'], inquiry_id: 'zz-other-document' }), answered(null, '{"1":"أ"}'), x);
  assertEquals([d.delivered, log], [true, ['arabic ready']]);
  const { x: bare } = io(true); delete (bare as Partial<DeliveryIO>).arabicFinishReady;
  assertEquals((await deliverReasoned(r({ sources: ['a'] }), answered(null), bare)).delivered, false);
});

Deno.test('a public comment whose CLASS was held runs through the comment policy with the reasoned class, once', async () => {
  const { x, log } = io(true);
  const d = await deliverReasoned(row('marketing_social.comment_classify', 'I need a quote for my villa', { platform: 'instagram', message_id: 'c9' }), answered('sales_lead'), x);
  assertEquals([d.delivered, d.via], [true, 'social']);
  assertEquals(log, ['classified instagram c9 sales_lead']);
  const none = await deliverReasoned(row('marketing_social.comment_classify', 'x', { platform: 'instagram', message_id: 'c10' }), answered(null), x);
  assertEquals([none.delivered, none.via], [false, 'none']);
  assertEquals(log.length, 1);
});

Deno.test('the website widget: a visitor reasoned to have asked for a person is reported to the CEO; otherwise nothing', async () => {
  const { x, log } = io(true);
  const yes = await deliverReasoned(row('site_assistant.person', 'can I talk to someone real please', { path: '/pricing' }), answered('needs_a_person'), x);
  assertEquals([yes.delivered, yes.via], [true, 'none']);
  assertEquals(log, ['ceo widget:person:held:7']);
  const no = await deliverReasoned(row('site_assistant.person', 'how do fees work?', { path: '/' }), answered('no_person'), x);
  assertEquals(no.delivered, false);
  assertEquals(log.length, 1);
});

Deno.test('a holding notice that failed is recorded as failed and sent again; a throw is a failed attempt, not a lost batch', async () => {
  const { x } = io(true);
  let fail = true;
  const flaky: DeliveryIO = { ...x, sendWaText: () => Promise.resolve(fail ? { ok: false, err: 'twilio 63016' } : { ok: true }) };
  const rec: [number, boolean][] = [];
  const record = (id: number, d: { delivered: boolean }) => { rec.push([id, d.delivered]); return Promise.resolve(); };
  const rows = [{ id: 7, surface: 'wa_inbound.needs_a_person', question: 'where is my quote?', subject: { phone: '+971500000001' } }];
  const first = await sendHeldNotices(rows, flaky, record);
  assertEquals(first.map((r) => r.delivered), [false]);
  fail = false;                              // the next tick, fn_reason_held_notice_due returns the same row
  const second = await sendHeldNotices(rows, flaky, record);
  assertEquals(second.map((r) => r.delivered), [true]);
  assertEquals(rec, [[7, false], [7, true]]);
  const throwing: DeliveryIO = { ...x, waWindowOpen: () => Promise.reject(new Error('db down')) };
  const t = await sendHeldNotices([...rows, { ...rows[0], id: 8 }], throwing, record);
  assertEquals(t.map((r) => [r.id, r.delivered]), [[7, false], [8, false]]);
});
