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
// deliverReasoned is pure over its `io`, so reasoned_delivery.test.ts pins every branch.
import type { HeldRow } from './think.ts';
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
  /** Every regenerated Arabic quotation whose lines are now all reasoned (fn_arabic_waiters_ready): render it and send
   *  the approval request (supplier_api spec_arabic_finish -> workflow.ts finishArabic). Decision point trade_glossary_ar. */
  arabicFinishReady?(): Promise<Sent>;
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

  // A held Arabic translation: fn_reason_apply_sales_engineer__document_arabic has stored the Arabic and flushed any
  // parked message; what is left is a regenerated quotation, which needs a render (a PDF) before its approval request.
  // The waiting quotations are found by the QUOTE (arabic_document_waiter), not by this row's subject: the same lines
  // may have been filed first by another document, and a held row keeps its first subject.
  if (row.surface === 'sales_engineer.document_arabic') {
    if (!io.arabicFinishReady) return { delivered: false, via: 'none', detail: 'stored; no renderer wired' };
    const s = await io.arabicFinishReady();
    return { delivered: s.ok, via: 'none', detail: s.ok ? 'every quotation whose Arabic is complete was rendered and asked for approval' : s.err };
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
    arabicFinishReady: async () => {
      const { data: ids, error } = await admin.rpc('fn_arabic_waiters_ready', { p_limit: 10 });
      if (error) return { ok: false, err: error.message };
      const errs: string[] = [];
      for (const quoteId of (Array.isArray(ids) ? ids : []) as string[]) {
      const { timedFetch } = await import('./timed_fetch.ts');
      // supplier_api has verify_jwt = true: the service key passes the gateway; __secret decides the caller.
      const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/supplier_api', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '') },
        body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), action: 'spec_arabic_finish', quote_id: String(quoteId) }),
      }, 60_000);
      const j = await r.json().catch(() => ({}));
      if (!(r.ok && j?.ok)) errs.push(quoteId + ': ' + String(j?.code ?? j?.error ?? r.status));
      }
      return errs.length ? { ok: false, err: errs.join('; ') } : { ok: true };
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
