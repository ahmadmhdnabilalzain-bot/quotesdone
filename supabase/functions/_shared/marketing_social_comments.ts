// THE MARKETING SEAT ANSWERS PUBLIC COMMENTS ON THE COMPANY'S OWN CHANNELS (marketing, 23 Sep 2026).
//
// Founder, instruction 866: "the marketing agent need to be able to reply to the comments as well. If
// someone said something, he should be able to reply … that applies to all the platforms on social
// media." And, the same day: "I don't want to be approving every comment … Otherwise, this is not
// automation." So there is NO per-reply approval anywhere below: the system guarantees the reply instead.
//
// MEASURED 23 Sep 2026 (read-only, htdblwldjkcgjvmqkbeh + docs.postiz.com/llms.txt): Postiz's public API
// publishes, lists posts and reads analytics; it has no endpoint that reads or answers a comment.
//   instagram / facebook — Meta webhook (marketing_social_inbox) delivers the comment; reply and hide via Graph
//   youtube              — our own OAuth (instructions 919-920 replace the earlier "Postiz only" ruling): the
//                          founder's one link (marketing_social_connect) stores the channel's token; the duty reads
//                          commentThreads and answers through the Data API. Not connected: skipped, and says so.
//   linkedin             — ONLY the QuotesDone company page, through the Community Management API with the
//                          organization scopes the same link grants; the actor of every reply is the page, never
//                          a member (never a personal profile).
//   x                    — REMOVED (founder, 23 Sep 2026: no paid X API). Nothing here reads or answers X.
//
// THE POLICY, applied to the REASONED class (processComment; the class itself is reasoned, reasoned_social.ts):
//   spam_abuse       -> hidden where the platform allows it, AND handed to customer_support to review
//                       (unhideRequest reverses it); never hidden when the comment also asks or wants to join
//   complaint, sensitive_legal, a request for a person
//                    -> handed to customer_support ('social.escalation') + a fixed acknowledgement
//   sales_lead / supplier_enquiry -> handed to sales_engineer ('social.lead') + the fixed reply
//   praise           -> the fixed thanks
//   question         -> the comment library / FAQ / knowledge answer; only when none exists does the model
//                       draft. While the model is held: recorded 'held_not_run', nothing sent.
//   off_topic        -> ignored
// EVERY text that would be sent — library, FAQ, knowledge or model — passes guard() and the platform's
// length limit, or it is NOT sent: the comment is escalated and the fixed acknowledgement goes instead. A
// fact is never truncated. Our own account is never answered; a comment id is answered at most once; a
// thread takes at most 3 seat replies in 10 minutes. Nothing is sent unless app_secrets.social_send_enabled
// = 'on' (the emergency stop) and the author is not a ZZDEMO fixture.
import { langOf, type Lang } from './chat_answers.ts';
import { LI_REST, liHeaders } from './marketing_social_oauth.ts';

export type Platform = 'facebook' | 'instagram' | 'youtube' | 'linkedin';
export type Class = 'question' | 'praise' | 'complaint' | 'spam_abuse' | 'sales_lead' | 'supplier_enquiry' | 'sensitive_legal' | 'off_topic';

export interface CommentEvent {
  platform: Platform;
  accountId: string;        // OUR account on that platform
  commentId: string;        // the idempotency key
  authorId: string;
  handle: string | null;    // what the platform shows publicly; nothing more is kept
  text: string;
  at: Date;
  threadId: string;         // the post / video the comment sits under
}

// ── NORMALISE: what a reader sees, not what the bytes say ─────────────────────────────────────────────
// NFKC; Arabic-Indic and Persian digits to ASCII; every Unicode dash to '-'; Cyrillic/Greek look-alikes to
// Latin; curly quotes to straight; zero-width and tatweel removed; diacritics (Latin accents and Arabic
// harakat) stripped. Without this "Е‑Trader" (Cyrillic Е, U+2011) and "٥٪" walk past every rule.
const LOOKALIKE: Record<string, string> = {
  'а': 'a', 'е': 'e', 'о': 'o', 'р': 'p', 'с': 'c', 'у': 'y', 'х': 'x', 'і': 'i', 'ј': 'j', 'ѕ': 's', 'һ': 'h', 'ԁ': 'd', 'ӏ': 'l',
  'А': 'A', 'В': 'B', 'Е': 'E', 'К': 'K', 'М': 'M', 'Н': 'H', 'О': 'O', 'Р': 'P', 'С': 'C', 'Т': 'T', 'Х': 'X', 'У': 'Y', 'І': 'I', 'Ј': 'J', 'Ѕ': 'S',
  'α': 'a', 'ο': 'o', 'ρ': 'p', 'ε': 'e', 'ι': 'i', 'κ': 'k', 'ν': 'v', 'τ': 't', 'Α': 'A', 'Β': 'B', 'Ε': 'E', 'Ι': 'I', 'Κ': 'K', 'Μ': 'M', 'Ν': 'N', 'Ο': 'O', 'Ρ': 'P', 'Τ': 'T', 'Χ': 'X',
};
export function normalise(s: string): string {
  return String(s || '').normalize('NFKC')
    .replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660))
    .replace(/[۰-۹]/g, (c) => String(c.charCodeAt(0) - 0x6F0))
    .replace(/[‐-―−﹘﹣－­]/g, '-')
    .replace(/[‘’‛′＇]/g, "'").replace(/[“”‟″]/g, '"')
    .replace(/[​-‏‪-‮⁠-⁤﻿ـ]/g, '')
    .replace(/[Ѐ-ӿͰ-Ͽ]/g, (c) => LOOKALIKE[c] ?? c)
    // Hamza carriers folded BEFORE the mark strip, so NFD cannot silently turn ئ into ي mid-word unseen by the rules.
    .replace(/[ئى]/g, 'ي').replace(/ؤ/g, 'و').replace(/[أإآٱ]/g, 'ا').replace(/ء/g, '')
    .normalize('NFD').replace(/\p{Mn}/gu, '').normalize('NFC');
}

// ── CLASSIFY: REASONED, NOT MATCHED (23 Sep 2026, founder_instruction 886-903) ────────────────────────
// The RULES / ABUSE / ASKS regex lists that decided what a public comment IS — hidden, answered, handed off —
// are deleted. The class arrives already reasoned (_shared/reasoned_social.ts commentClass, decision point
// marketing_social.comment_classify); null means that reasoning is held, and processComment then hides nothing,
// says nothing and hands nothing off: the comment is recorded 'held_classify' and the replay
// (_shared/reasoned_delivery.ts) runs it through this same policy with the reasoned class. guard() below stays:
// it vets OUR outgoing text, never what a person meant.

// ── THE GUARDS every outgoing text passes before it can be sent (founder, 23 Sep 2026) ────────────────
// The facts are the company's published ones (site FAQ, supplier agreement v12, portal copy): customers pay
// a 3% reveal fee only on a reveal; the first 1,000 suppliers are free permanently, AED 1,000 a year from the
// 1,001st registration; DET Trader Licence 1633275 (never "E-Trader"); the company mailbox. Anything else
// asserted with a number, a link, a phone, a company name, a promise or a legal view fails. No phone number
// is ever posted in public — the founder's mobile least of all.
export const FACTS = {
  percents: ['3'],
  amounts: ['1,000', '1000'],
  numbers: ['1633275', '1,000', '1000', '1,001', '1001'],
  domains: /^(www\.)?quotesdone\.(com|ae)$/,
  emails: ['management@quotesdone.com'],
};
export const LIMIT: Record<Platform, number> = { instagram: 300, facebook: 300, youtube: 500, linkedin: 500 };
const AR = /[؀-ۿ]/g;
const arabicShare = (s: string) => (s.match(AR) || []).length / Math.max(1, (s.match(/[A-Za-z؀-ۿ]/g) || []).length);
const NUM_WORDS = 'one|two|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty|hundred|thousand|half|zero'
  + '|واحد|اثنين|اثنان|اربعه|خمسه|سته|سبعه|ثمانيه|تسعه|عشره|عشرين|ثلاثين|خمسين|مائه|مئه|مية|الف|نصف|صفر';
// Matched against normalised text (hamza folded, ة→ه): المئة arrives as الميه, المائة as الماه/المايه.
const PCT = "%|٪|percent|per ?cents?|pct|pc|(?:بال|في ال|فى ال|من ال)(?:ميه|مايه|ماه|مئه|مائه|مية)|بالميه|نسبه";
const CUR = 'aed|dhs?|dirhams?|درهم|دراهم';

export function guard(draft: string, ev: Pick<CommentEvent, 'platform' | 'text' | 'handle'>): string[] {
  const f: string[] = [];
  const raw = String(draft || '').trim();
  if (!raw || /^UNKNOWN\b/.test(raw)) return ['empty'];
  if (raw.length > LIMIT[ev.platform]) f.push('too_long');
  const d = normalise(raw);                                   // case kept: the company-name rule reads capitals
  const l = d.toLowerCase().replace(/[إأآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي');
  const lang: Lang = langOf(ev.text);
  const share = arabicShare(d);
  if (lang === 'ar' ? share < 0.6 : share > 0.1) f.push('wrong_language');
  // fees
  for (const m of l.matchAll(new RegExp(`(\\d+(?:[.,]\\d+)?)\\s*(?:${PCT})`, 'g'))) if (!FACTS.percents.includes(m[1])) f.push('percent:' + m[1]);
  if (new RegExp(`(?:^|[^\\p{L}])(?:${NUM_WORDS})[\\s-]*(?:${PCT})`, 'u').test(l)) f.push('percent_words');
  // amounts
  for (const m of l.matchAll(new RegExp(`(?<![a-z])(?:${CUR})\\s*([\\d,.]+)|([\\d,.]+)\\s*(?:${CUR})(?![a-z])`, 'g'))) {
    const v = (m[1] || m[2]).replace(/[.,]$/, '');
    if (!FACTS.amounts.includes(v)) f.push('amount:' + v);
  }
  if (new RegExp(`(?:^|[^\\p{L}])(?:${NUM_WORDS}|thousands?|hundreds?)[\\s-]+(?:${CUR})(?![a-z])`, 'u').test(l)) f.push('amount_words');
  // free-for-everyone / no-fee claims (the published fact is narrower: the first 1,000 suppliers)
  if (/free (?:forever|for (?:everyone|everybody|all|life|ever))|no fees?\b|zero fees?|without (?:any )?fees?|never pay|(?:completely|totally|100%) free|always free|مجانا للجميع|مجاني للجميع|مجانا دائما|مجاني دائما|بدون (?:اي )?رسوم|بلا رسوم|لا (?:توجد|يوجد) (?:اي )?رسوم|مجاني تماما|مجانا تماما|مجاني بالكامل/.test(l)) f.push('free_claim');
  // refund promises
  if (/we(?:'ll| will| shall| can) (?:refund|return your money|give (?:you )?(?:a |your )?(?:full )?refund)|full refund|refund(?:ed)? (?:you )?in full|money back|guaranteed refund|سنعيد|سنرد|سنرجع|نعيد لك|نعيد لكم|نرجع لك|نرجع لكم|استرداد كامل|استرجاع كامل|نسترد لك|نسترد لكم|نعوضك|نعوضكم/.test(l)) f.push('refund_promise');
  // numbers nobody verified (after digit folding)
  const noUrls = l.replace(/https?:\/\/\S+/g, '');
  for (const m of noUrls.matchAll(/\d[\d,]*/g)) {
    const digits = m[0].replace(/,/g, '');
    if (digits.length >= 4 && !FACTS.numbers.includes(m[0].replace(/,$/, ''))) f.push('number:' + m[0]);
  }
  for (const m of noUrls.matchAll(/(?:\+|00)?\d[\d\s().-]{6,}\d/g)) if (m[0].replace(/\D/g, '').length >= 7 && !FACTS.numbers.includes(m[0].trim())) f.push('phone');
  if (/e[\s._-]*trader|اي ?تريدر/.test(l)) f.push('e_trader');
  // links: only our own domains; shorteners, chat links (wa.me, t.me) and every other host fail
  const noMail = l.replace(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, (e) => { if (!FACTS.emails.includes(e)) f.push('email'); return ' '; });
  for (const m of noMail.matchAll(/(?:https?:\/\/)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?![a-z0-9-])/g)) {
    if (!FACTS.domains.test(m[1])) f.push('link:' + m[1]);
  }
  if (/https?:\/\/(?!(?:www\.)?quotesdone\.(?:com|ae)\b)/.test(noMail)) f.push('link');
  for (const m of d.matchAll(/@([A-Za-z0-9_.]+)/g)) if (m[1].toLowerCase() !== String(ev.handle || '').toLowerCase().replace(/^@/, '') && !/quotesdone/i.test(m[1])) f.push('mention');
  // a DM instruction under a public post ("reply 'agent'") or a private channel
  if (/(?:reply|type|send|write|message us)\s+["']?(?:agent|human|person)|whatsapp|واتساب|اكتب(?:وا)?\s+["']?(?:agent|وكيل|موظف)/.test(l)) f.push('dm_instruction');
  // a named third party: legal forms, "done by <Name>", "Al <Name>", an Arabic company named
  if (/\b(?:l\.?l\.?c|fze|fzco|fz-llc|trading|contracting|establishment|est\.|group|holding)\b|(?:supplier|customer|client|company|firm|contractor) (?:named|called|is)\b|ذ\.م\.م|المورد (?:هو|اسمه)|العميل (?:هو|اسمه)|شركه [^\s]+ (?:نفذت|قامت)|(?:نفذ(?:ه|ها|ت)?|قامت? به) (?:شركه|مؤسسه)/.test(l)
    || /\b(?:by|from|with|via|to|and) (?:(?:Al|El)[\s-])?(?!QuotesDone\b|Quotes\b|UAE\b|Dubai\b|Abu\b|Sharjah\b)[A-Z][a-z]{2,}(?:[\s-][A-Z][a-z]+)*/.test(d)
    || /\b(?:Al|El)[\s-][A-Z][a-z]{2,}/.test(d)) f.push('identity');
  if (/\b(?:guarantee[ds]?|promise[ds]?|we will (?:fix|call|pay)|will cost|costs? (?:around|about|from)|starting (?:at|from)|cheapest|best price|within \d+ (?:hours|minutes|days))\b|نضمن|نعدكم|نعدك|يكلف|اقل سعر/.test(l)) f.push('promise_or_price');
  if (/\b(?:liable|liability|lawsuit|legal advice|legally|court|sue|entitled|by law|under (?:uae |the |federal |local )?law|your rights?|consumer rights?|the law)\b|قانوني|قانونيا|محكمه|مسؤوليه قانونيه|حسب القانون|بموجب القانون|وفق القانون|يحق لك|يحق لكم|من حقك|من حقكم/.test(l)) f.push('legal');
  if (/[؀-ۿ][,;?]/.test(raw) || /يرجى ملاحظة/.test(raw)) f.push('arabic_register');
  return [...new Set(f)];
}


// ── THE STORE, injected so tests replay every platform with no network and no database ─────────────
export interface Decided { kind: string; key: string | null; text: string }
export interface SendResult { ok: boolean; id?: string | null; error?: string }
export type HandoffType = 'social.escalation' | 'social.lead';
export interface Store {
  insertInbound(ev: CommentEvent, cls: Class | null): Promise<number | null>;   // cls null: still being reasoned; returns null: already answered (idempotency)
  release(inId: number): Promise<void>;                                  // processing failed before a send: retry later
  threadAllowed(ev: CommentEvent): Promise<boolean>;
  record(inId: number, row: Outcome): Promise<void>;
  handoff(type: HandoffType, ev: CommentEvent, cls: Class, extra?: Record<string, unknown>): Promise<number | null>;
  switchOn(key: 'social_send_enabled' | 'social_model_enabled'): Promise<boolean>;
  library(key: string, lang: Lang): Promise<string>;
  deterministic(ev: CommentEvent): Promise<Decided>;                 // comment_* library rows, FAQ, knowledge
  draft(ev: CommentEvent, lang: Lang): Promise<string | null>;        // the model, only over retrieved knowledge
  reply(ev: CommentEvent, text: string): Promise<SendResult>;
  hide(ev: CommentEvent): Promise<SendResult>;
  /** Already handled (an inbound row with an outcome): a redelivery must not re-ask the reasoning. Optional for test stores. */
  seen?(ev: CommentEvent): Promise<boolean>;
}
export interface Outcome {
  classification: Class | null;
  outcome: string;
  reply: string | null;
  decided_by: 'rule' | 'model' | 'guard_fallback' | null;
  send_status: 'sent' | 'failed' | 'held_switch_off' | 'held_fixture' | 'held_model' | 'rate_limited' | 'not_sent' | 'hidden';
  guard_failures: string[];
  handoff_id: number | null;
  send_error?: string | null;
  platform_reply_id?: string | null;
}

export const isFixture = (ev: CommentEvent) => /^ZZDEMO/i.test(ev.authorId) || /^ZZ ?DEMO/i.test(ev.handle || '');
const SEAT: Record<HandoffType, string> = { 'social.escalation': 'customer_support', 'social.lead': 'sales_engineer' };
export const seatFor = (t: HandoffType) => SEAT[t];

type Lazy<T> = T | (() => Promise<T>);
/** The comment policy for a comment whose class was REASONED (`reasoned`; null while that reasoning is held).
 *  Either argument may be a function: the reasoning (think()) then runs only for a comment that is not our own
 *  and not empty, and never for one the store already recorded (a redelivery or sweep retry). */
export async function processComment(s: Store, ev: CommentEvent, reasoned: Lazy<Class | null>, wantsPerson: Lazy<boolean> = false): Promise<string> {
  if (!ev.text.trim() || ev.authorId === ev.accountId) return 'own_or_empty';
  const lazy = typeof reasoned === 'function' || typeof wantsPerson === 'function';
  if (lazy && s.seen && (await s.seen(ev))) return 'duplicate';
  const klass = typeof reasoned === 'function' ? await reasoned() : reasoned;
  const person = typeof wantsPerson === 'function' ? await wantsPerson() : wantsPerson;
  // A reasoned request for a person is handled as a complaint — except abuse, which is hidden and reviewed anyway.
  const cls: Class | null = person && klass !== 'spam_abuse' ? 'complaint' : klass;
  const inId = await s.insertInbound(ev, cls);
  if (inId == null) return 'duplicate';
  let sent = false;
  try {
    return await run();
  } catch (e) {
    // Nothing reached the commenter: give the row back so the next delivery or the sweep retries it.
    if (!sent) await s.release(inId).catch(() => {});
    throw e;
  }

  async function run(): Promise<string> {
    const lang = langOf(ev.text);
    const o: Outcome = { classification: cls, outcome: '', reply: null, decided_by: 'rule', send_status: 'not_sent', guard_failures: [], handoff_id: null };
    const done = async (outcome: string) => { o.outcome = outcome; await s.record(inId!, o); return outcome; };
    const escalate = async (type: HandoffType, extra?: Record<string, unknown>) => { o.handoff_id = await s.handoff(type, ev, o.classification as Class, extra); };
    const ack = async () => { if (!o.handoff_id) await escalate('social.escalation'); return await s.library('comment_escalated_ack', lang); };

    // HELD: what this comment is has not been reasoned yet. Nothing is hidden, said or handed off on a guess;
    // the replay applies the policy the moment the hold lifts. (The person check has its own queue, point 72.)
    if (cls === null) { o.decided_by = null; o.send_status = 'held_model'; return await done('held_classify'); }
    if (cls === 'off_topic') return await done('ignored_off_topic');
    if (cls === 'spam_abuse') {
      if (isFixture(ev)) { o.send_status = 'held_fixture'; return await done('hide_held'); }
      if (!(await s.switchOn('social_send_enabled'))) { o.send_status = 'held_switch_off'; return await done('hide_held'); }
      const r = await s.hide(ev);
      sent = r.ok;
      o.send_status = r.ok ? 'hidden' : 'failed'; o.send_error = r.error ?? null;
      // Every hide is reviewed by a person-facing seat, who can reverse it (unhideRequest).
      // Every hide is reviewed; a hide that could not be done is reviewed too, so abuse is never left unseen.
      await escalate('social.escalation', r.ok ? { hidden: true, review: 'un-hide if this was not abuse' } : { hidden: false, review: 'could not hide: ' + (r.error || '') });
      return await done(r.ok ? 'hidden' : 'hide_failed');
    }

    let text = '';
    if (cls === 'complaint' || cls === 'sensitive_legal') text = await ack();
    else if (cls === 'supplier_enquiry') { await escalate('social.lead'); text = await s.library('comment_supplier', lang); }
    else if (cls === 'sales_lead') { await escalate('social.lead'); text = await s.library('comment_lead', lang); }
    else if (cls === 'praise') text = await s.library('comment_praise', lang);
    else {
      const d = await s.deterministic(ev);
      if (d.kind === 'handoff') { o.classification = 'complaint'; text = await ack(); }
      else if (d.kind !== 'unknown' && d.text) text = d.text;
      else {
        if (!(await s.switchOn('social_model_enabled'))) { o.decided_by = null; o.send_status = 'held_model'; return await done('held_not_run'); }
        text = String((await s.draft(ev, lang)) || '').trim();
        o.decided_by = 'model';
      }
    }
    // EVERY text, whatever produced it, passes the guards and fits the platform — or it is not sent: the
    // subject goes to the seat that owns it and the fixed acknowledgement goes instead. Never truncated.
    const failures = text ? guard(text, ev) : ['empty'];
    if (failures.length) {
      o.guard_failures = failures;
      o.decided_by = 'guard_fallback';
      text = await ack();
      const again = text ? guard(text, ev) : ['empty'];
      if (again.length) { o.guard_failures = [...failures, ...again.map((x) => 'ack:' + x)]; return await done('not_sent_guard'); }
    }
    o.reply = text;
    if (!(await s.threadAllowed(ev))) { o.send_status = 'rate_limited'; return await done('rate_limited'); }
    if (isFixture(ev)) { o.send_status = 'held_fixture'; return await done('reply_held'); }
    if (!(await s.switchOn('social_send_enabled'))) { o.send_status = 'held_switch_off'; return await done('reply_held'); }
    const r = await s.reply(ev, text);
    sent = r.ok;
    o.send_status = r.ok ? 'sent' : 'failed'; o.send_error = r.error ?? null; o.platform_reply_id = r.id ?? null;
    return await done(r.ok ? 'replied' : 'reply_failed');
  }
}

// ── THE PLATFORM CALLS. Pure request builders + readers with the fetch injected. ──────────────────────
export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export interface Req { url: string; method: string; headers: Record<string, string>; body?: string }
const J = { 'Content-Type': 'application/json' };
const GRAPH = 'https://graph.facebook.com/v21.0/';

export function replyRequest(ev: CommentEvent, text: string, token: string): Req {
  const auth = { ...J, Authorization: 'Bearer ' + token };
  switch (ev.platform) {
    case 'instagram': return { url: GRAPH + encodeURIComponent(ev.commentId) + '/replies', method: 'POST', headers: auth, body: JSON.stringify({ message: text }) };
    case 'facebook': return { url: GRAPH + encodeURIComponent(ev.commentId) + '/comments', method: 'POST', headers: auth, body: JSON.stringify({ message: text }) };
    case 'youtube': return { url: 'https://www.googleapis.com/youtube/v3/comments?part=snippet', method: 'POST', headers: auth,
      body: JSON.stringify({ snippet: { parentId: ev.commentId, textOriginal: text } }) };
    // The actor is the company page (ev.accountId is its organization URN) — never a member.
    case 'linkedin': return { url: LI_REST + 'socialActions/' + encodeURIComponent(ev.commentId) + '/comments', method: 'POST',
      headers: { ...J, ...liHeaders(token) },
      body: JSON.stringify({ actor: ev.accountId, object: ev.threadId, parentComment: ev.commentId, message: { text } }) };
  }
}
/** Hides (hidden = true) or restores (hidden = false) a comment. Every hide can be reversed by the reviewing seat. */
export function hideRequest(ev: CommentEvent, token: string, hidden = true): Req | null {
  const auth = { ...J, Authorization: 'Bearer ' + token };
  switch (ev.platform) {
    case 'instagram': return { url: GRAPH + encodeURIComponent(ev.commentId), method: 'POST', headers: auth, body: JSON.stringify({ hide: hidden }) };
    case 'facebook': return { url: GRAPH + encodeURIComponent(ev.commentId), method: 'POST', headers: auth, body: JSON.stringify({ is_hidden: hidden }) };
    case 'youtube': return { url: 'https://www.googleapis.com/youtube/v3/comments/setModerationStatus?id=' + encodeURIComponent(ev.commentId)
      + '&moderationStatus=' + (hidden ? 'heldForReview' : 'published'), method: 'POST', headers: auth };
    // LinkedIn offers only DELETE, which cannot be reversed: nothing is hidden, the comment goes to review.
    case 'linkedin': return null;
  }
}
export const unhideRequest = (ev: CommentEvent, token: string) => hideRequest(ev, token, false);

export async function call(f: Fetch, r: Req | null): Promise<SendResult> {
  if (!r) return { ok: false, error: 'this platform has no reversible hide' };
  try {
    const res = await f(r.url, { method: r.method, headers: r.headers, body: r.body });
    const j = await res.json().catch(() => ({})) as any;
    if (!res.ok) return { ok: false, error: String(j?.error?.message || j?.detail || j?.title || res.status).slice(0, 300) };
    return { ok: true, id: j?.data?.id ?? j?.id ?? null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 300) }; }
}

// ── READING the comments on our own YouTube channel and LinkedIn company page ──────────────────────────
// Only comments newer than `since` are read, so connecting does not answer a year of history. The author is kept
// as the platform's opaque id; no member profile is ever fetched.
export async function youtubeComments(f: Fetch, token: string, channelId: string, since: Date): Promise<CommentEvent[]> {
  const r = await f('https://www.googleapis.com/youtube/v3/commentThreads?part=snippet&maxResults=50&order=time&moderationStatus=published&allThreadsRelatedToChannelId='
    + encodeURIComponent(channelId), { headers: { Authorization: 'Bearer ' + token } });
  const j = await r.json().catch(() => ({})) as any;
  if (!r.ok) throw new Error('youtube commentThreads HTTP ' + r.status + ': ' + String(j?.error?.message || '').slice(0, 120));
  const out: CommentEvent[] = [];
  for (const it of j.items || []) {
    const c = it?.snippet?.topLevelComment; const s = c?.snippet || {};
    const at = new Date(s.publishedAt || 0);
    if (!c?.id || at < since) continue;
    out.push({ platform: 'youtube', accountId: channelId, commentId: c.id, authorId: String(s.authorChannelId?.value || ''), handle: s.authorDisplayName ?? null,
      text: String(s.textOriginal || ''), at, threadId: String(it.snippet.videoId || c.id) });
  }
  return out;
}
export async function linkedinComments(f: Fetch, token: string, orgId: string, since: Date): Promise<CommentEvent[]> {
  const org = 'urn:li:organization:' + orgId;
  const r = await f(LI_REST + 'posts?q=author&count=10&sortBy=LAST_MODIFIED&author=' + encodeURIComponent(org), { headers: liHeaders(token) });
  const j = await r.json().catch(() => ({})) as any;
  if (!r.ok) throw new Error('linkedin posts HTTP ' + r.status + ': ' + String(j?.message || '').slice(0, 120));
  const out: CommentEvent[] = [];
  for (const p of j.elements || []) {
    const post = String(p.id || ''); if (!post) continue;
    const c = await f(LI_REST + 'socialActions/' + encodeURIComponent(post) + '/comments?count=50', { headers: liHeaders(token) });
    const cj = await c.json().catch(() => ({})) as any;
    if (!c.ok) throw new Error('linkedin comments HTTP ' + c.status + ': ' + String(cj?.message || '').slice(0, 120));
    for (const e of cj.elements || []) {
      const at = new Date(Number(e?.created?.time || 0));
      const urn = String(e?.['$URN'] || e?.commentUrn || '');
      if (!urn || at < since) continue;
      out.push({ platform: 'linkedin', accountId: org, commentId: urn, authorId: String(e.actor || ''), handle: null,
        text: String(e?.message?.text || ''), at, threadId: post });
    }
  }
  return out;
}
