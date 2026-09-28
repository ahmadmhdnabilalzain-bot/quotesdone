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
//   * a held comment CLASS (marketing_social.comment_classify): the comment policy runs now, and its reply or hide
//     is posted with THAT platform's own credential (replayHeldComment below). Until 24 Sep 2026 the replay handed a
//     LinkedIn comment to the Meta page-token lookup and YouTube no token at all, so neither could post (found in
//     the review of PR #898). A missing token (or a refused refresh) is a named skip: nothing runs, nothing is sent,
//     nothing throws, and the comment stays 'held_classify'. The held question itself was already closed by
//     replayHeld, so the marketing duty's retry_unfinished sweep is what picks it up again — and that sweep checks the
//     same token BEFORE reasoning and asks a comment's class at most MAX_CLASS_QUESTIONS times (marketing/duties.ts
//     reviveHeldComments), so a skipped comment waits without a model call instead of being re-reasoned every sweep.
// deliverReasoned is pure over its `io`, so reasoned_delivery.test.ts pins every branch.
import type { HeldRow } from './think.ts';
import { coverageReply, type Trade } from '../wa_inbound/coverage.ts';
import { capabilityAnswer } from '../wa_inbound/founder_queries.ts';
import type { ThinkResult } from './think.ts';
import type { CommentEvent } from './marketing_social_comments.ts';
import { composeMailReply } from './customer_mail.ts';
// Batch 8 (accountant + marketing): an expense email's reasoned kind or vendor re-runs the accountant's sweep, and
// a LinkedIn reply's reasoned class drafts its follow-up. Their branches live with their decisions.
import { deliverBooks, liveBooksIO, type BooksIO } from './reasoned_books.ts';
import { deliverOutreach, liveOutreachIO, type OutreachIO } from './reasoned_outreach.ts';

/** skipped: nothing was attempted and the subject is left as it was, for a later run (e.g. 'linkedin token missing'). */
export type Sent = { ok: boolean; err?: string; skipped?: string };
export interface DeliveryIO extends BooksIO, OutreachIO {
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
  /** Every regenerated Arabic quotation whose lines are now all reasoned (fn_arabic_waiters_ready): render it and send
   *  the approval request (supplier_api spec_arabic_finish -> workflow.ts finishArabic). Decision point trade_glossary_ar. */
  arabicFinishReady?(): Promise<Sent>;
  /** A public comment whose CLASS was held: run it through the comment policy with the reasoned class (marketing_social_comments.ts). */
  socialCommentClassified(subject: Record<string, unknown>, cls: string): Promise<Sent>;
  /** E-mail (email_triage, 28 Sep 2026): reply in the inbound message's own thread (fn_inbox_send). `person` also
   *  files the pending inbound_review a customer who asked for a person is owed. */
  emailReply?(messageId: number, text: string, person: boolean): Promise<Sent>;
}
export type Delivery = { delivered: boolean; via: 'whatsapp_text' | 'whatsapp_template' | 'social' | 'accountant_sweep' | 'bookkeeper' | 'outreach_follow_up' | 'email' | 'none'; detail?: string };

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

  const books = await deliverBooks(row, r, io);
  if (books) return books;
  const outreach = await deliverOutreach(row, r, io);
  if (outreach) return outreach;
  // A held Arabic translation: fn_reason_apply_sales_engineer__document_arabic has stored the Arabic and flushed any
  // parked message; what is left is a regenerated quotation, which needs a render (a PDF) before its approval request.
  // The waiting quotations are found by the QUOTE (arabic_document_waiter), not by this row's subject: the same lines
  // may have been filed first by another document, and a held row keeps its first subject.
  if (row.surface === 'sales_engineer.document_arabic') {
    if (!io.arabicFinishReady) return { delivered: false, via: 'none', detail: 'stored; no renderer wired' };
    const s = await io.arabicFinishReady();
    return { delivered: s.ok, via: 'none', detail: s.ok ? 'every quotation whose Arabic is complete was rendered and asked for approval' : s.err };
  }

  if (row.surface === 'marketing_social.comment_classify') {
    // Nothing was hidden, said or handed off while the class was held; the policy runs now, once.
    if (!choice) return { delivered: false, via: 'none', detail: 'no class on the reasoned result' };
    const s = await io.socialCommentClassified(subject, choice);
    return { delivered: s.ok, via: 'social', detail: s.skipped ? 'skipped: ' + s.skipped : s.err };
  }

  if (row.surface === 'site_assistant.person') {
    // The visitor already has the public contact in the reply (the assistant gives it whenever a person is asked
    // for); what was owed is the CEO's visibility report, filed only when the reasoning says a person was asked for.
    if (choice !== 'needs_a_person') return { delivered: false, via: 'none', detail: 'reasoned: no person was asked for' };
    await io.reportToCeo('widget:person:held:' + row.id, 'A website visitor asked to speak to a person and was given the public contact',
      { surface: 'website_widget', held_id: row.id, path: subject.path ?? null, message: question.slice(0, 300), reasoning: r.answer.slice(0, 500) });
    return { delivered: true, via: 'none', detail: 'reported to the CEO for visibility' };
  }

  // E-MAIL (email_triage, 28 Sep 2026). The customer already has a reply in the thread: a knowledge passage or a
  // receipt that said the answer would follow there. The replay keeps that promise, and a reasoned request for a
  // person gets the person.
  if (row.surface === 'email_triage.needs_a_person') {
    if (choice !== 'needs_a_person') return { delivered: false, via: 'none', detail: 'reasoned: no person is needed; the reply already went' };
    if (!io.emailReply || !Number(subject.message_id)) return { delivered: false, via: 'none', detail: 'no e-mail sender or message id' };
    const s = await io.emailReply(Number(subject.message_id), composeMailReply({ lang: isAr(question) ? 'ar' : 'en', person: true }), true);
    return { delivered: s.ok, via: 'email', detail: s.err };
  }
  if (row.surface === 'email_triage.reply' && subject.channel === 'email') {
    const ok = r.verified?.status === 'agreed' && r.answer.trim();
    if (!ok || !io.emailReply || !Number(subject.message_id)) return { delivered: false, via: 'none', detail: ok ? 'no e-mail sender or message id' : 'the answer was not verified; the receipt stands' };
    const s = await io.emailReply(Number(subject.message_id), composeMailReply({ lang: isAr(question) ? 'ar' : 'en', answer: r.answer }), false);
    return { delivered: s.ok, via: 'email', detail: s.err };
  }

  // A held ANSWER (think.answer on a channel): the answer itself goes back where the question came from.
  if (!row.request?.decision && subject.channel === 'whatsapp' && subject.phone && r.answer) {
    return await whatsapp(io, String(subject.phone), question, r.answer);
  }
  return { delivered: false, via: 'none', detail: 'no channel effect for ' + row.surface };
}

// ── a held comment, replayed with its own platform's credential ─────────────────────────────────────────────────
// The same credentials the live comment path uses (marketing/duties.ts socialComments): YouTube and the LinkedIn
// company page post with the token set the founder's one link stored (marketing_social_oauth.ts accessToken, which
// refreshes it when due); Instagram and Facebook with the page's own token (marketing_social_store.ts metaPageToken).
export interface CommentReplayIO {
  /** accessToken(): the connected YouTube / LinkedIn token set, refreshed when due; null = not connected. */
  ownToken(p: 'youtube' | 'linkedin'): Promise<{ access_token: string } | null>;
  /** metaPageToken(): the Instagram / Facebook page's own token; null = not derivable. */
  metaPageToken(platform: 'facebook' | 'instagram', accountId: string): Promise<string | null>;
  /** tiktokToken(): the TikTok business account's own token (#898); null = not connected. */
  tiktokToken?(): Promise<string | null>;
  /** processComment over the live store, which posts every reply and hide with tokenFor(ev). */
  process(tokenFor: (ev: CommentEvent) => Promise<string | null>): Promise<string>;
}
export async function replayHeldComment(ev: Pick<CommentEvent, 'platform' | 'accountId'>, io: CommentReplayIO): Promise<Sent> {
  let tokenFor: (ev: CommentEvent) => Promise<string | null>;
  if (ev.platform === 'youtube' || ev.platform === 'linkedin') {
    // Resolved BEFORE the policy runs: with no token nothing is recorded, so the comment stays 'held_classify'. The
    // marketing duty's sweep (reviveHeldComments) re-checks the token before any reasoning and runs it once the
    // platform is connected again.
    let token: string | null;
    try { token = String((await io.ownToken(ev.platform))?.access_token ?? '').trim() || null; }
    catch (e) { return { ok: false, skipped: ev.platform + ' token refresh failed: ' + String((e as Error)?.message || e).slice(0, 160) }; }
    if (!token) return { ok: false, skipped: ev.platform + ' token missing' };
    tokenFor = () => Promise.resolve(token);
  } else if (ev.platform === 'tiktok') {
    tokenFor = () => io.tiktokToken ? io.tiktokToken() : Promise.resolve(null);
  } else {
    // Meta: looked up at the send, exactly as before (a comment the policy ignores never derives a page token).
    tokenFor = (e) => io.metaPageToken(e.platform as 'facebook' | 'instagram', e.accountId);
  }
  try { return { ok: true, err: await io.process(tokenFor) }; }
  catch (e) { return { ok: false, err: String((e as Error)?.message || e).slice(0, 200) }; }
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

/** Every owed holding notice (fn_reason_held_notice_due: escalated, a customer phone, not yet delivered, not tried in
 *  30 minutes) is sent, and EACH ATTEMPT IS RECORDED (fn_reason_held_notice_record), so a failed send comes back on a
 *  later tick instead of being lost with the step's log (a_customer_notice_that_failed_is_sent_again.sql). A throw is
 *  a failed attempt, never an abandoned batch. */
export async function sendHeldNotices(rows: { id: number; surface: string; question?: string; subject?: Record<string, unknown> | null }[], io: DeliveryIO,
  record: (id: number, d: Delivery) => Promise<unknown>): Promise<{ id: number; delivered: boolean; via: string; detail?: string }[]> {
  const out = [];
  for (const r of rows) {
    const d: Delivery = await holdingNotice(r, io).catch((e) => ({ delivered: false, via: 'none' as const, detail: String(e?.message || e).slice(0, 200) }));
    await record(r.id, d).catch(() => null);
    out.push({ id: r.id, ...d });
  }
  return out;
}

// ── the live io ──────────────────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
type Admin = any;
type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

/** app_secrets for a token refresh, with a COMPARE-AND-SET save: a refreshed token set is written only while the stored
 *  sealed value is still the one this run read. If the founder reconnected in between (a new token set stored), the
 *  newer one is kept and this run's refresh is used for its own send only. Never an upsert over what was not read. */
export function casSecrets(admin: Admin) {
  const read = new Map<string, string>();
  const sec = async (k: string) => {
    const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
    const v = (data?.value as string) || '';
    read.set(k, v);
    return v;
  };
  const save = async (k: string, v: string) => {
    const was = read.get(k);
    if (!was) return;   // nothing was read, so there is nothing this run may replace
    const { data, error } = await admin.from('app_secrets').update({ value: v }).eq('key', k).eq('value', was).select('key');
    if (error) throw new Error('app_secrets ' + k + ': ' + error.message);
    if (data?.length) read.set(k, v);   // else: changed since the read; the newer value stands
  };
  return { sec, save };
}

/** seams: the key material and fetch the token path uses (default: the function's service-role key and timedFetch);
 *  reasoned_delivery.test.ts passes a test key and a stubbed fetch. */
export function liveDeliveryIO(admin: Admin, seams: { master?: string; fetch?: Fetch } = {}): DeliveryIO {
  const sec = async (k: string) => { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; };
  const digits = (p: string) => p.replace(/[^0-9]/g, '');
  return {
    ...liveBooksIO(admin),
    ...liveOutreachIO(admin),
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
    emailReply: async (messageId, text, person) => {
      const { data, error } = await admin.rpc('fn_inbox_send', { p_id: messageId, p_body: text, p_by: 'customer_support' });
      const err = error?.message ?? (data as { error?: string } | null)?.error;
      if (err) return { ok: false, err };
      if (person) await admin.from('agent_actions').insert({ agent: 'email', kind: 'inbound_review', status: 'pending', risk: 'low',
        title: 'Inbox: a customer asked for a person', recommendation: 'The customer asked to speak to a person and was told a member of the team will reply in the same thread. Reply from the Inbox.',
        target_table: 'inbound_messages', target_id: String(messageId), detail: { via: 'reasoned replay' } });
      return { ok: true };
    },
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
    waIntentReply: async (phone, question, intent) => {
      const { data } = await admin.rpc('fn_wa_answer', { p_from: phone, p_body: question.slice(0, 4000), p_intent: intent });
      return (data as { matched?: boolean; reply?: string } | null)?.matched ? String(data.reply || '') || null : null;
    },
    waTrades: async () => {
      // Each trade with its live group (#885), the same read wa_inbound makes; ungrouped if the groups are absent.
      const grouped = await admin.from('taxonomy_trade').select('code,label,label_ar,aliases,group:taxonomy_trade_group(code,label_en,label_ar,sort)').eq('active', true).order('sort').order('code');
      if (!grouped.error) return (grouped.data || []) as unknown as Trade[];
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
    socialCommentClassified: async (subject, cls) => {
      const { data: m } = await admin.from('social_message')
        .select('id,meta_message_id,platform,body,parent_id,occurred_at,outcome,conversation:social_conversation(user_id,handle,account_id)')
        .eq('platform', String(subject.platform ?? '')).eq('meta_message_id', String(subject.message_id ?? '')).eq('direction', 'in').maybeSingle();
      if (!m) return { ok: false, err: 'comment_not_found' };
      if (m.outcome !== 'held_classify') return { ok: true, err: 'already_processed:' + String(m.outcome) };
      // processComment's own insert takes a held_classify row over (marketing_social_store.ts); the row is never emptied.
      const { processComment } = await import('./marketing_social_comments.ts');
      const { adminStore, metaPageToken } = await import('./marketing_social_store.ts');
      const { accessToken } = await import('./marketing_social_oauth.ts');
      const { timedFetch } = await import('./timed_fetch.ts');
      const f = seams.fetch ?? timedFetch;
      const ev: CommentEvent = {
        platform: m.platform, accountId: m.conversation?.account_id, commentId: m.meta_message_id, authorId: m.conversation?.user_id,
        handle: m.conversation?.handle ?? null, text: String(m.body || ''), at: new Date(m.occurred_at), threadId: m.parent_id || m.meta_message_id,
      };
      // A refreshed YouTube token is re-sealed where it was read, compare-and-set (casSecrets above).
      const secrets = casSecrets(admin);
      return await replayHeldComment(ev, {
        ownToken: (p) => accessToken(f, p, seams.master ?? (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''), secrets.sec, secrets.save),
        metaPageToken: (p, accountId) => metaPageToken(admin, f, p, accountId),
        // TikTok (#898): the business account's own token, as the marketing duty uses it; replies post AS that account.
        tiktokToken: async () => String((await admin.from('app_secrets').select('value').eq('key', 'tiktok_business_token').maybeSingle()).data?.value ?? '').trim() || null,
        // deno-lint-ignore no-explicit-any
        process: (tokenFor) => processComment(adminStore(admin, f, tokenFor, Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway'), ev, cls as any),
      });
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
