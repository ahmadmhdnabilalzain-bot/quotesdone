// reasoned_delivery — a question held under the model hold is answered ON THE CHANNEL IT CAME FROM.
// Seat: customer_support (WhatsApp) and marketing (social). 23 Sep 2026, founder_instruction 886-903.
//
// Under the hold think() files a question in its seat's queue; replayHeld (_shared/think.ts) reasons it
// the moment the hold lifts. A reasoning with an effect in the database (a CEO command's intent, an intake's
// trade) is applied by fn_reason_held_resolve. A reasoning whose effect is a MESSAGE is delivered here:
//   * WhatsApp, inside the customer's 24-hour window (wa_conversation.window_expires_at): free text, the
//     same send a live reply uses (_shared/wa_send.ts);
//   * WhatsApp, outside it: WhatsApp allows only an approved template, so a notifications row of type
//     'support_reply' is queued and send_whatsapp sends it on the support_reply template (its {{1}} the
//     question, {{2}} the answer). It stays queued, never dropped, until Meta approves that template;
//   * social (Instagram / Facebook): the platform reply path — marketing_social_inbox's own send, called
//     with an internal credential, which also applies Meta's messaging window (meta.ts withinWindow).
//   * a held MEANING (wa_inbound.intent_table, marketing_social.library_match — _shared/reasoned_channels.ts):
//     the answer the reasoned meaning selects — the database's intent reply, the trade list, the size statement
//     on WhatsApp; the library / FAQ / passage reply on the platform. Nothing when the meaning selects nothing.
// deliverReasoned is pure over its `io`, so reasoned_delivery.test.ts pins every branch.
import type { HeldRow } from './think.ts';
import { coverageReply, type Trade } from '../wa_inbound/coverage.ts';
import { capabilityAnswer } from '../wa_inbound/founder_queries.ts';
import type { ThinkResult } from './think.ts';

export type Sent = { ok: boolean; err?: string };
export interface DeliveryIO {
  waWindowOpen(phone: string): Promise<boolean>;
  sendWaText(phone: string, body: string): Promise<Sent>;
  queueWaTemplate(phone: string, question: string, answer: string, lang: 'en' | 'ar'): Promise<Sent>;
  founderContact(): Promise<string | null>;
  reportToCeo(key: string, subject: string, evidence: Record<string, unknown>): Promise<void>;
  socialHandoff(subject: Record<string, unknown>): Promise<Sent>;
  /** A public comment reasoned to need a person: the private conversation customer_support owns (social.escalation). */
  socialCommentHandoff(subject: Record<string, unknown>): Promise<Sent>;
  /** fn_wa_answer with the reasoned intent: the database's answer for this sender, or null. */
  waIntentReply(phone: string, question: string, intent: string): Promise<string | null>;
  /** public.taxonomy_trade, active rows: the live trade list a coverage answer is built from. */
  waTrades(): Promise<Trade[]>;
  /** A held DM's grounded reply, sent by marketing_social_inbox on the platform (reasoned_reply). */
  socialReply(subject: Record<string, unknown>, meaning: string): Promise<Sent>;
}
export type Delivery = { delivered: boolean; via: 'whatsapp_text' | 'whatsapp_template' | 'social' | 'none'; detail?: string };

const isAr = (s: string) => /[؀-ۿ]/.test(s);

/** WhatsApp: free text inside the window, the approved template outside it. */
async function whatsapp(io: DeliveryIO, phone: string, question: string, text: string): Promise<Delivery> {
  if (await io.waWindowOpen(phone)) {
    const s = await io.sendWaText(phone, text);
    return { delivered: s.ok, via: 'whatsapp_text', detail: s.err };
  }
  const s = await io.queueWaTemplate(phone, question, text, isAr(question) ? 'ar' : 'en');
  return { delivered: s.ok, via: 'whatsapp_template', detail: s.ok ? 'queued for the support_reply template (outside the 24-hour window)' : s.err };
}

export async function deliverReasoned(row: HeldRow, r: ThinkResult, io: DeliveryIO): Promise<Delivery> {
  const subject = row.subject ?? {};
  const question = String(row.request?.question ?? '');
  const choice = r.decision?.choice ?? null;

  if (row.surface === 'wa_inbound.needs_a_person') {
    // The reply to their message already went; what was owed is the person, if one is needed.
    if (choice !== 'needs_a_person') return { delivered: false, via: 'none', detail: 'reasoned: no person is needed; the reply already went' };
    const phone = String(subject.phone ?? '');
    if (!phone) return { delivered: false, via: 'none', detail: 'no phone on the held row' };
    const contact = (await io.founderContact()) ?? '';
    const text = isAr(question)
      ? `شكرًا لصبركم. إن كنتم تفضّلون التحدث مع شخص مباشرةً، يمكنكم الاتصال أو المراسلة على ${contact}، ويجيب عليه مالك الشركة.`
      : `Thank you for your patience. If you would rather speak to someone directly, call or message ${contact}, which is answered by the owner.`;
    await io.reportToCeo('reasoned:person:' + row.id, 'A held WhatsApp message was reasoned to need a person and was given the public contact',
      { held_id: row.id, message: question.slice(0, 300), reasoning: r.answer.slice(0, 500) });
    return await whatsapp(io, phone, question, text);
  }

  if (row.surface === 'marketing_social.needs_a_person') {
    if (choice !== 'needs_a_person') return { delivered: false, via: 'none', detail: 'reasoned: no person is needed; the reply already went' };
    const s = await io.socialHandoff(subject);
    return { delivered: s.ok, via: 'social', detail: s.err };
  }

  if (row.surface === 'marketing_social.comment_needs_a_person') {
    // The public reply already went under the comment policy; what was owed is the private handoff.
    if (choice !== 'needs_a_person') return { delivered: false, via: 'none', detail: 'reasoned: no person is needed; the comment was already answered' };
    const s = await io.socialCommentHandoff(subject);
    return { delivered: s.ok, via: 'social', detail: s.err };
  }

  if (row.surface === 'wa_inbound.intent_table') {
    // What an unanswered WhatsApp message asked, reasoned now: the database's answer goes on WhatsApp.
    const phone = String(subject.phone ?? '');
    if (!phone) return { delivered: false, via: 'none', detail: 'no phone on the held row' };
    const lang = isAr(question) ? 'ar' : 'en';
    let text: string | null = null;
    if (choice === 'size') text = capabilityAnswer(lang);
    else if (choice?.startsWith('coverage:') || choice?.startsWith('trade:')) text = coverageReply(choice, await io.waTrades(), lang);
    // A request for a person is delivered by wa_inbound.needs_a_person (its own held row), never twice.
    else if (choice?.startsWith('intent:') && !['intent:contact_human', 'intent:greeting', 'intent:small_talk'].includes(choice)) text = await io.waIntentReply(phone, question, choice.slice(7));
    if (!text) return { delivered: false, via: 'none', detail: 'reasoned: ' + (choice ?? 'no choice') + ' — nothing more is owed; the courteous reply and the knowledge gap stand' };
    return await whatsapp(io, phone, question, text);
  }

  if (row.surface === 'marketing_social.library_match') {
    if (!choice || choice === 'none') return { delivered: false, via: 'none', detail: 'reasoned: no grounded reply; the honest unknown already went' };
    const s = await io.socialReply(subject, choice);
    return { delivered: s.ok, via: 'social', detail: s.err };
  }

  // A held ANSWER (think.answer on a channel): the answer itself goes back where the question came from.
  if (!row.request?.decision && subject.channel === 'whatsapp' && subject.phone && r.answer) {
    return await whatsapp(io, String(subject.phone), question, r.answer);
  }
  return { delivered: false, via: 'none', detail: 'no channel effect for ' + row.surface };
}

/** A question held 48 hours (or failed) was escalated to its seat (fn_reason_held_escalate). A WhatsApp customer
 *  is told it is being handled — once, by the row's escalation — under the same window rule as an answer. Other
 *  surfaces already replied at the time, or have no person waiting on a channel. */
export async function holdingNotice(row: { id: number; surface: string; question?: string; subject?: Record<string, unknown> | null }, io: DeliveryIO): Promise<Delivery> {
  const phone = String(row.subject?.phone ?? '');
  if (!phone) return { delivered: false, via: 'none', detail: 'no customer channel on ' + row.surface };
  const q = String(row.question ?? '');
  const text = isAr(q)
    ? 'شكرًا لصبركم. سؤالكم لدى فريقنا الآن ويتابعه شخص مختص، وسنعود إليكم بالإجابة هنا.'
    : 'Thank you for your patience. Your question is now with our team and a person is handling it; we will reply here.';
  return await whatsapp(io, phone, q, text);
}

// ── the live io ──────────────────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
type Admin = any;
export function liveDeliveryIO(admin: Admin): DeliveryIO {
  const sec = async (k: string) => { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; };
  const digits = (p: string) => p.replace(/[^0-9]/g, '');
  return {
    waWindowOpen: async (phone) => {
      const { data } = await admin.from('wa_conversation').select('window_expires_at').eq('phone_e164', digits(phone)).maybeSingle();
      return !!data?.window_expires_at && new Date(data.window_expires_at).getTime() > Date.now();
    },
    sendWaText: async (phone, body) => { const { sendWhatsApp } = await import('./wa_send.ts'); return await sendWhatsApp(admin, phone, body.slice(0, 1200)); },
    queueWaTemplate: async (phone, question, answer, lang) => {
      // Through customer_support's delivery door, never a direct outbox write (_shared/deliver.ts).
      const { requestDelivery } = await import('./deliver.ts');
      const { error } = await requestDelivery(admin, {
        channel: 'whatsapp', type: 'support_reply', kind: 'customer_support_reasoned_reply', to_role: 'customer',
        to_phone: '+' + digits(phone), subject: question.slice(0, 200), body: answer.slice(0, 1500), status: 'queued',
        lang, sender: 'customer_support', requested_by: 'customer_support',
      });
      return error ? { ok: false, err: error.message } : { ok: true };
    },
    founderContact: async () => (await sec('founder_public_phone')) || null,
    reportToCeo: async (key, subject, evidence) => {
      await admin.rpc('fn_support_report_to_ceo', { p_idempotency_key: key, p_severity: 'routine', p_subject: subject, p_evidence: evidence,
        p_attempted: ['reasoned the held message', 'gave the approved public contact'], p_requested: 'Visibility only. No action is requested.' });
    },
    socialHandoff: async (subject) => {
      const { timedFetch } = await import('./timed_fetch.ts');
      const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/marketing_social_inbox', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), action: 'reasoned_handoff', platform: subject.platform, message_id: subject.message_id }),
      }, 20_000);
      const j = await r.json().catch(() => ({}));
      return r.ok && j?.ok ? { ok: true } : { ok: false, err: String(j?.error ?? r.status) };
    },
    waIntentReply: async (phone, question, intent) => {
      const { data } = await admin.rpc('fn_wa_answer', { p_from: phone, p_body: question.slice(0, 4000), p_intent: intent });
      return (data as { matched?: boolean; reply?: string } | null)?.matched ? String(data.reply || '') || null : null;
    },
    waTrades: async () => {
      const { data } = await admin.from('taxonomy_trade').select('code,label,label_ar,aliases').eq('active', true).order('sort').order('code');
      return (data || []) as Trade[];
    },
    socialReply: async (subject, meaning) => {
      const { timedFetch } = await import('./timed_fetch.ts');
      const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/marketing_social_inbox', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), action: 'reasoned_reply', platform: subject.platform, message_id: subject.message_id, meaning, passages: subject.passages ?? [] }),
      }, 20_000);
      const j = await r.json().catch(() => ({}));
      // Sent only when the inbox says it answered; 'already_answered', 'outside_window' and the like are reported, not counted.
      return r.ok && j?.ok && String(j?.outcome ?? '').startsWith('answered') ? { ok: true } : { ok: false, err: String(j?.error ?? j?.outcome ?? r.status) };
    },
    socialCommentHandoff: async (subject) => {
      const { data: m } = await admin.from('social_message')
        .select('meta_message_id,platform,body,parent_id,occurred_at,conversation:social_conversation(user_id,handle,account_id)')
        .eq('platform', String(subject.platform ?? '')).eq('meta_message_id', String(subject.message_id ?? '')).eq('direction', 'in').maybeSingle();
      if (!m) return { ok: false, err: 'comment_not_found' };
      // Once per comment: the live path may already have handed it off, and a replay can run twice.
      const { data: prior } = await admin.from('agent_actions').select('id').eq('kind', 'handoff').eq('agent', 'customer_support')
        .eq('target_table', 'social_message').eq('target_id', 'social.escalation:' + m.platform + ':' + m.meta_message_id).neq('status', 'failed').limit(1);
      if (prior && prior.length) return { ok: true };
      const { raiseSocialHandoff } = await import('../marketing/social_handoffs.ts');
      try {
        await raiseSocialHandoff(admin, 'social.escalation', {
          platform: m.platform, accountId: m.conversation?.account_id, commentId: m.meta_message_id, authorId: m.conversation?.user_id,
          handle: m.conversation?.handle ?? null, text: String(m.body || ''), at: new Date(m.occurred_at), threadId: m.parent_id || m.meta_message_id,
        }, 'complaint', { decided_by: 'reasoning' });
        return { ok: true };
      } catch (e) { return { ok: false, err: String((e as Error)?.message || e).slice(0, 200) }; }
    },
  };
}
