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
  /** The reply to a held question, WRITTEN BY A MODEL now (aiReply: the company brief, the figure check, the model
   *  ladder; rulings 1195/1196). null when no model answered — then nothing is sent. */
  writeReply(question: string, lang: 'en' | 'ar', o?: { channel?: string; note?: string; subject?: Record<string, unknown>;
    audience?: 'customer' | 'supplier' | 'visitor' | 'founder'; facts?: string; seat?: 'customer_support' | 'sales_engineer' }): Promise<string | null>;
  /** writeReply with the model's state: outage is true only when no call reached a model (openrouter_down.ts), the one case
   *  a code-written notice may go out (founder ruling 1339). Optional: an io without it never sends a code-written notice. */
  writeNotice?(question: string, lang: 'en' | 'ar', o?: { channel?: string; note?: string; subject?: Record<string, unknown>; facts?: string; must?: string[] }): Promise<{ reply: string; outage: boolean }>;
  /** A model-written, guarded reply posted into a supplier's quotation thread (never one that is submitted or closed). */
  postQuoteReview?(reviewId: string, text: string): Promise<Sent>;
  /** A held DM's grounded reply, sent by marketing_social_inbox on the platform (reasoned_reply). */
  socialReply(subject: Record<string, unknown>, meaning: string): Promise<Sent>;
  /** Every regenerated Arabic quotation whose lines are now all reasoned (fn_arabic_waiters_ready): render it and send
   *  the approval request (supplier_api spec_arabic_finish -> workflow.ts finishArabic). Decision point trade_glossary_ar. */
  arabicFinishReady?(): Promise<Sent>;
  /** Every held Arabic comparison report whose lines are now all reasoned (fn_arabic_compare_waiters_ready): customer_api
   *  compare_arabic_finish renders it and sends it to the customer, once (customer_api/compare_arabic.ts). */
  compareArabicReady?(): Promise<Sent>;
  /** A customer's Arabic answer or note, now reasoned into English: store it as the supplier copy and e-mail every
   *  matched supplier (_shared/supplier_english.ts finishEnglish). Surface sales_engineer.supplier_english. */
  supplierEnglish?(clarificationId: number, answer: string): Promise<Sent>;
  /** A public comment whose CLASS was held: run it through the comment policy with the reasoned class (marketing_social_comments.ts). */
  socialCommentClassified(subject: Record<string, unknown>, cls: string): Promise<Sent>;
  /** E-mail (email_triage, 28 Sep 2026): reply in the inbound message's own thread (fn_inbox_send). `person` also
   *  files the pending inbound_review a customer who asked for a person is owed. */
  emailReply?(messageId: number, text: string, person: boolean): Promise<Sent>;
}
/** 'unwritten': the model was up and nothing it wrote passed — nothing was sent. fn_reason_held_delivered puts the row back
 *  to 'held' (scripts/sql/an_unwritten_person_notice_goes_back_to_the_replay.sql; without it the row stayed 'reasoned',
 *  which nothing reads), so fn_reason_held_due asks again after 10 minutes; at its third try the row is 'failed',
 *  fn_reason_held_escalate hands it to customer_support, and the person is owed the model-written holding notice. */
export type Delivery = { delivered: boolean; via: 'whatsapp_text' | 'whatsapp_template' | 'social' | 'accountant_sweep' | 'bookkeeper' | 'outreach_follow_up' | 'email' | 'portal' | 'unwritten' | 'none'; detail?: string };

const isAr = (s: string) => /[؀-ۿ]/.test(s);

/** WhatsApp: free text inside the window, the approved template outside it. */
export async function whatsapp(io: DeliveryIO, phone: string, question: string, text: string): Promise<Delivery> {
  if (await io.waWindowOpen(phone)) {
    const s = await io.sendWaText(phone, text);
    return { delivered: s.ok, via: 'whatsapp_text', detail: s.err };
  }
  const s = await io.queueWaTemplate(phone, question, text, isAr(question) ? 'ar' : 'en');
  return { delivered: s.ok, via: 'whatsapp_template', detail: s.ok ? 'queued for the support_reply template (outside the 24-hour window)' : s.err };
}

/** A held conversation turn's question carries its facts and the person's own words ("MESSAGE:" / "THEIR MESSAGE:"). */
export function splitHeldQuestion(q: string): [string, string] {
  const m = q.match(/\n\n(?:THEIR )?MESSAGE:\n([\s\S]*)$/);
  return m ? [q.slice(0, m.index), m[1]] : ['', q];
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
    const contact = ((await io.founderContact()) ?? '').trim();
    const [, said] = splitHeldQuestion(question);
    const lang: 'en' | 'ar' = isAr(said || question) ? 'ar' : 'en';
    // THE MODEL WRITES THE CONTACT NOTICE (founder ruling 1339, extended by ledger 1348: any message a person reads as a
    // reply is the model's; code-written text only when OpenRouter is down). The facts are code's: a person will follow
    // up, and the direct line and who answers it. personContactNotice goes out only on an outage; with the model up and
    // nothing it wrote passing (or a draft in the wrong language, or the brand in Arabic letters), nothing is sent and the
    // row goes back to the replay (via 'unwritten'; fn_reason_held_delivered).
    const w = io.writeNotice
      ? await io.writeNotice(said || question, lang, { channel: 'WhatsApp', subject, facts: personContactFacts(contact), must: contact ? [contact] : undefined,
        note: 'Plain text for WhatsApp, two sentences at most. They need a person. Thank them for their patience and tell them, in your own words, the facts given: a person will follow up with them, and the direct line (keep the number exactly, on its own line). Do not answer their question itself and do not promise a time.' })
      : { reply: '', outage: false };
    // A draft in the wrong language, or one that spells the brand in Arabic letters, is refused: it counts as unwritten.
    const refused = personNoticeProblems(w.reply, lang);
    const text = personNoticeDraft(w.reply, lang) || (w.outage ? personContactNotice(lang, contact) : '');
    await io.reportToCeo('reasoned:person:' + row.id, text
      ? 'A held WhatsApp message was reasoned to need a person and was given the public contact'
      : 'A held WhatsApp message was reasoned to need a person; no model-written contact notice passed yet, so nothing was sent (1339)',
      { held_id: row.id, message: question.slice(0, 300), reasoning: r.answer.slice(0, 500), written_by: personNoticeDraft(w.reply, lang) ? 'model' : w.outage ? 'outage_fallback' : 'none',
        ...(refused.length ? { refused } : {}) });
    if (!text) return { delivered: false, via: 'unwritten', detail: io.writeNotice ? 'model up, no contact notice it wrote passed the guards' + (refused.length ? ' (' + refused.join('; ') + ')' : '') + ': nothing code-written is sent (1339); asked again on replay' : 'no model writer: a code-written notice is never sent blind (1339)' };
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
    // Whatever the reasoned meaning (size, coverage, a trade, an intent), the reply is WRITTEN BY A MODEL now — no capability
    // statement, no trade-list sentence, no stored intent answer (rulings 1195/1196, 12 Oct 2026). A request for a person
    // is delivered by wa_inbound.needs_a_person (its own held row), never twice; greetings and small talk owe nothing more.
    const owed = !!choice && choice !== 'none' && !['intent:contact_human', 'intent:greeting', 'intent:small_talk'].includes(choice);
    const text = owed ? await io.writeReply(question, lang, { channel: 'WhatsApp', subject }) : null;
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
  // A held Arabic COMPARISON REPORT (customer_api compare_pdf answered 202) waits by its inquiry the same way and goes to
  // the customer from customer_api (compare_arabic.ts), so both renderers are asked; one failing never skips the other.
  if (row.surface === 'sales_engineer.document_arabic') {
    if (!io.arabicFinishReady && !io.compareArabicReady) return { delivered: false, via: 'none', detail: 'stored; no renderer wired' };
    const q = io.arabicFinishReady ? await io.arabicFinishReady().catch((e) => ({ ok: false, err: String(e) } as Sent)) : { ok: true };
    const c = io.compareArabicReady ? await io.compareArabicReady().catch((e) => ({ ok: false, err: String(e) } as Sent)) : { ok: true };
    const err = [q.err && 'quotations: ' + q.err, c.err && 'comparison reports: ' + c.err].filter(Boolean).join('; ');
    return { delivered: q.ok && c.ok, via: 'none', detail: err || 'every quotation and comparison report whose Arabic is complete was rendered and sent on' };
  }

  // A customer's Arabic text held for its supplier copy: the English goes to every matched supplier now.
  if (row.surface === 'sales_engineer.supplier_english') {
    const id = Number(subject.clarification_id);
    if (!io.supplierEnglish || !id) return { delivered: false, via: 'none', detail: 'no clarification id or no sender wired' };
    const s = await io.supplierEnglish(id, r.answer);
    return { delivered: s.ok, via: 'email', detail: s.err };
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
    const lang = isAr(question) ? 'ar' : 'en';
    const body = await io.writeReply(question, lang, { channel: 'e-mail', subject, note: 'An e-mail body without a greeting or a sign-off (they are added). They asked to speak to a person: say plainly that a member of the team will reply to them in this same thread.' });
    if (!body) return { delivered: false, via: 'none', detail: 'no model answered; nothing was sent' };
    const s = await io.emailReply(Number(subject.message_id), composeMailReply({ lang, answer: body }), true);
    return { delivered: s.ok, via: 'email', detail: s.err };
  }
  if (row.surface === 'email_triage.reply' && subject.channel === 'email') {
    const ok = r.verified?.status === 'agreed' && r.answer.trim();
    if (!ok || !io.emailReply || !Number(subject.message_id)) return { delivered: false, via: 'none', detail: ok ? 'no e-mail sender or message id' : 'the answer was not verified; the receipt stands' };
    const s = await io.emailReply(Number(subject.message_id), composeMailReply({ lang: isAr(question) ? 'ar' : 'en', answer: r.answer }), false);
    return { delivered: s.ok, via: 'email', detail: s.err };
  }

  // A held ANSWER (think.answer on a channel). NO MODEL REPLY REACHES A PERSON UNGUARDED (review of #1335): think()'s
  // answer is not sent as it stands. It goes to aiReply as a fact to check, with the turn's own facts, and only what
  // passes aiReply's figure, policy, anonymity and reply guards (with model rewrites) is sent. Nothing passes: nothing is
  // sent, and the 15-minute / 48-hour escalation hands the turn to the seat.
  const [facts, said] = splitHeldQuestion(question);
  const audience = (['customer', 'supplier', 'visitor', 'founder'] as const).find((a) => a === row.request?.context?.audience) ?? 'customer';
  const lang: 'en' | 'ar' = audience === 'supplier' ? 'en' : row.request?.context?.language === 'ar' || isAr(said) ? 'ar' : 'en';
  const checked = (channel: string, seat: 'customer_support' | 'sales_engineer') => io.writeReply(said, lang, { channel, subject, audience, seat,
    facts: facts + (r.answer ? '\n\nA REASONED DRAFT TO CHECK (use only what agrees with the brief and the facts):\n' + r.answer.slice(0, 2000) : '') });
  if (row.surface === 'supplier_api.quote_review_unwritten' && subject.review_id) {
    if (!io.postQuoteReview) return { delivered: false, via: 'none', detail: 'no quotation-thread poster' };
    const text = await checked('the supplier portal quotation chat', 'sales_engineer');
    if (!text) return { delivered: false, via: 'none', detail: 'no model reply passed the guard; the seat gets it at 15 minutes' };
    const s = await io.postQuoteReview(String(subject.review_id), text);
    return { delivered: s.ok, via: 'portal', detail: s.err };
  }
  if (!row.request?.decision && subject.channel === 'whatsapp' && subject.phone && r.answer) {
    const text = await checked('WhatsApp', 'customer_support');
    if (!text) return { delivered: false, via: 'none', detail: 'no model reply passed the guard; the seat gets it by escalation' };
    return await whatsapp(io, String(subject.phone), question, text);
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

/** What the person-contact notice must convey: the model's facts (founder ruling 1339 / ledger 1348). */
export function personContactFacts(contact: string): string {
  return 'A person from our team will follow up with them.' + (contact
    ? ' If they would rather speak to someone directly, they can call or message ' + contact + ', which is answered by the owner of the company.'
    : ' They can reply in this same chat and a person will see it.');
}
/** The brand written in Arabic letters (kwts dn, with its variants of the vowel, the s and the n, spaced or not): every
 *  customer reads it as "QuotesDone". */
// written in escapes: a pattern, not a message (every_arabic_message_is_written_not_translated reviews messages)
const ARABIC_BRAND = /\u0643[\u0648\u064F]?[\u062A\u0637][\u0633\u0632\u0635]\s*[-\u0640]?\s*\u062F[\u0648\u064F]?[\u0646\u06BB]/;
const LATIN = /[A-Za-z]/g;
const ARABIC_LETTERS = /[\u0621-\u064A\u0671-\u06D3]/g;
/** Why a model draft of the person-contact notice is refused (empty: it may be sent). The person's language is
 *  the notice's: an Arabic message gets Arabic, an English one gets no Arabic. Latin letters that are the brand, a
 *  link or an e-mail address are not counted against an Arabic draft. */
export function personNoticeProblems(draft: string, lang: 'en' | 'ar'): string[] {
  const t = String(draft ?? '').trim();
  if (!t) return [];
  const out: string[] = [];
  const ar = (t.match(ARABIC_LETTERS) ?? []).length;
  const latin = (t.replace(/QuotesDone/gi, '').replace(/\S+@\S+|https?:\/\/\S+|\b[\w-]+\.(?:com|ae)\b/gi, '').match(LATIN) ?? []).length;
  if (lang === 'ar' && ar <= latin) out.push('it is not in Arabic, the language they wrote in');
  if (lang === 'en' && ar > 0) out.push('it carries Arabic, but they wrote in English');
  if (ARABIC_BRAND.test(t)) out.push('it spells the brand in Arabic letters; it must read "QuotesDone"');
  return out;
}
/** The model's draft when it passes personNoticeProblems, else '' (unwritten). */
export function personNoticeDraft(draft: string, lang: 'en' | 'ar'): string {
  const t = String(draft ?? '').trim();
  return t && !personNoticeProblems(t, lang).length ? t : '';
}
/** The person-contact notice in code's words: sent ONLY when OpenRouter is down (Delivery of wa_inbound.needs_a_person).
 *  With no published line on file it is the holding notice (a person has it, the reply comes here), never a blank number. */
export function personContactNotice(lang: 'en' | 'ar', contact: string): string {
  if (!contact) return HOLDING_NOTICE[lang];
  return lang === 'ar'
    ? `شكرًا لصبركم. إن كنتم تفضّلون التحدث مع شخص مباشرةً، يمكنكم الاتصال أو المراسلة على ${contact}، ويجيب عليه مالك الشركة.`
    : `Thank you for your patience. If you would rather speak to someone directly, call or message ${contact}, which is answered by the owner.`;
}

/** The fixed holding notice: with personContactNotice, the ONLY code-written words here, sent only when OpenRouter is down
 *  (founder ruling 1339). */
export const HOLDING_NOTICE: Record<'en' | 'ar', string> = {
  en: 'Thank you for your patience. Your question is now with our team and a person is handling it; we will reply here.',
  ar: 'شكرًا لصبركم. سؤالكم لدى فريقنا الآن ويتابعه شخص مختص، وسنعود إليكم بالإجابة هنا.',
};

/** A question held 48 hours (or failed, or refused by every re-ask: _shared/reask.ts) was escalated to its seat
 *  (fn_reason_held_escalate). A WhatsApp customer is told it is being handled — once, by the row's escalation — under the
 *  same window rule as an answer. Other surfaces already replied at the time, or have no person waiting on a channel.
 *  THE MODEL WRITES IT (founder ruling 1339, 27 Oct 2026: "the engineer and customer support never replies without llm
 *  unless the server of open router is down"). Until this change the fixed line went out whatever the model's state. Now
 *  writeNotice asks the model (aiReply: every guard), HOLDING_NOTICE goes only when no call reached a model (outage), and
 *  with the model up and nothing it wrote passing, nothing is sent: the attempt is recorded and tried again (30 minutes,
 *  fn_reason_held_notice_due). An io with no model writer sends nothing (fail closed: it cannot tell up from down). */
export async function holdingNotice(row: { id: number; surface: string; question?: string; subject?: Record<string, unknown> | null }, io: DeliveryIO): Promise<Delivery> {
  const phone = String(row.subject?.phone ?? '');
  if (!phone) return { delivered: false, via: 'none', detail: 'no customer channel on ' + row.surface };
  const q = String(row.question ?? '');
  const [, said] = splitHeldQuestion(q);
  const lang: 'en' | 'ar' = row.subject?.audience === 'supplier' ? 'en' : isAr(said || q) ? 'ar' : 'en';
  if (!io.writeNotice) return { delivered: false, via: 'none', detail: 'no model writer: a code-written notice is never sent blind (1339)' };
  const w = await io.writeNotice(said || q, lang, { channel: 'WhatsApp', subject: row.subject ?? undefined,
    note: 'Plain text for WhatsApp, two sentences at most. We could not answer their message yet. Thank them for their patience and tell them a member of our team now has their question and will reply in this same chat. Do not answer the question itself, do not promise a time, and do not say we will get back to them or contact them: say the reply will come here.' });
  const text = w.reply.trim() || (w.outage ? HOLDING_NOTICE[lang] : '');
  if (!text) return { delivered: false, via: 'none', detail: 'model up, no notice it wrote passed the guards: nothing code-written is sent (1339); tried again later' };
  return await whatsapp(io, phone, q, text);
}

/** Every owed holding notice (fn_reason_held_notice_due: escalated, a customer phone, not yet delivered, not tried in
 *  30 minutes) is sent, and EACH ATTEMPT IS RECORDED (fn_reason_held_notice_record), so a failed send comes back on a
 *  later tick instead of being lost with the step's log (a_customer_notice_that_failed_is_sent_again.sql). A throw is
 *  a failed attempt, never an abandoned batch.
 *  `record` may return a bare thenable: a supabase-js `admin.rpc(...)` builder has `then` and no `catch`, and
 *  calling `.catch` on it threw a TypeError AFTER the notice was sent, so the send was never recorded and
 *  reask_turns answered 500 (15 times on 1-2 Nov 2026, it_engineer). A builder also never THROWS on a database
 *  error: it resolves `{ error }`. So both a throw and a resolved `.error` are a failed record, logged and returned
 *  as `record_error`. A delivered notice that was not recorded is offered again by fn_reason_held_notice_due once
 *  its 30-minute claim lapses (a_holding_notice_is_claimed_by_one_sender.sql), up to 8 times: that repeat is why
 *  the failure must be seen, not swallowed. */
export async function sendHeldNotices(rows: { id: number; surface: string; question?: string; subject?: Record<string, unknown> | null }[], io: DeliveryIO,
  record: (id: number, d: Delivery) => PromiseLike<unknown>): Promise<{ id: number; delivered: boolean; via: string; detail?: string; record_error?: string }[]> {
  const out = [];
  for (const r of rows) {
    const d: Delivery = await holdingNotice(r, io).catch((e) => ({ delivered: false, via: 'none' as const, detail: String(e?.message || e).slice(0, 200) }));
    let recordError: string | undefined;
    try {
      const res = await record(r.id, d) as { error?: { message?: string } | null } | null | undefined;
      if (res?.error) recordError = String(res.error.message || JSON.stringify(res.error)).slice(0, 200);
    } catch (e) { recordError = String((e as Error)?.message || e).slice(0, 200); }
    if (recordError) console.error('fn_reason_held_notice_record failed for held question ' + r.id + ' (delivered=' + d.delivered + '): ' + recordError);
    out.push({ id: r.id, ...d, ...(recordError ? { record_error: recordError } : {}) });
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
      const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/supplier_api?forceFunctionRegion=ap-southeast-1', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '') },
        body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), action: 'spec_arabic_finish', quote_id: String(quoteId) }),
      }, 60_000);
      const j = await r.json().catch(() => ({}));
      if (!(r.ok && j?.ok)) errs.push(quoteId + ': ' + String(j?.code ?? j?.error ?? r.status));
      }
      return errs.length ? { ok: false, err: errs.join('; ') } : { ok: true };
    },
    compareArabicReady: async () => {
      const { data: ids, error } = await admin.rpc('fn_arabic_compare_waiters_ready', { p_limit: 10 });
      if (error) return { ok: false, err: error.message };
      const errs: string[] = [];
      const { timedFetch } = await import('./timed_fetch.ts');
      for (const inquiryId of (Array.isArray(ids) ? ids : []) as string[]) {
        // customer_api acknowledges at once (202) and renders after its answer, so this tick waits seconds, not a render.
        const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/customer_api', {
          method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '') },
          body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), action: 'compare_arabic_finish', inquiry_id: String(inquiryId) }),
        }, 15_000).catch((e) => ({ ok: false, status: String(e), json: () => Promise.resolve({}) } as unknown as Response));
        const j = await r.json().catch(() => ({}));
        if (!(r.ok && j?.ok)) errs.push(inquiryId + ': ' + String(j?.error ?? r.status));
      }
      return errs.length ? { ok: false, err: errs.join('; ') } : { ok: true };
    },
    supplierEnglish: async (id, answer) => {
      const { finishEnglish } = await import('./supplier_english.ts');
      const r = await finishEnglish(admin, id, answer);
      return r.ok ? { ok: true } : { ok: false, err: r.err };
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
    writeReply: async (question, lang, o = {}) => {
      const { aiReply } = await import('./ai_reply.ts');
      const { defaultDeps } = await import('./think.ts');
      const a = await aiReply(defaultDeps(admin, 'reasoned_delivery'), { seat: o.seat ?? 'customer_support', channel: o.channel ?? 'WhatsApp', audience: o.audience ?? 'customer', lang,
        message: question, rules: o.note, facts: o.facts, subject: o.subject });
      return a.reply || null;
    },
    writeNotice: async (question, lang, o = {}) => {
      const { aiReply } = await import('./ai_reply.ts');
      const { defaultDeps } = await import('./think.ts');
      const a = await aiReply(defaultDeps(admin, 'reasoned_delivery'), { seat: 'customer_support', channel: o.channel ?? 'WhatsApp', audience: 'customer', lang,
        message: question, rules: o.note, subject: o.subject, facts: o.facts, must: o.must });
      return { reply: a.reply || '', outage: a.outage === true };
    },
    postQuoteReview: async (reviewId, text) => {
      const { data: rv } = await admin.from('quote_reviews').select('id,status').eq('id', reviewId).maybeSingle();
      if (!rv || ['submitted', 'closed'].includes(String(rv.status))) return { ok: false, err: 'the thread is closed' };
      const { error } = await admin.from('quote_review_messages').insert({ review_id: reviewId, role: 'sales_engineer', kind: 'text', body: text.slice(0, 4000), body_ar: null, attachments: [], issues: null });
      return error ? { ok: false, err: error.message } : { ok: true };
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
      const { defaultDeps } = await import('./think.ts');
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
        // gte-small in embed_ml (heartbeat placement): this runs in the resilience_ping replay worker, 2 s CPU cap (#1678)
        process: (tokenFor) => processComment(adminStore(admin, f, tokenFor, Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway', defaultDeps(admin, 'marketing', { gte: 'remote' })), ev, cls as any),
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
