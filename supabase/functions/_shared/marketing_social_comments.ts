// THE MARKETING SEAT ANSWERS PUBLIC COMMENTS ON EVERY CHANNEL SYNCED IN POSTIZ (marketing, 23 Sep 2026).
//
// Founder, instruction 866: "the marketing agent need to be able to reply to the comments as well. If
// someone said something, he should be able to reply … that applies to all the platforms on social
// media." And, the same day: "I don't want to be approving every comment … Otherwise, this is not
// automation." So there is NO per-reply approval anywhere below: the system guarantees the reply instead.
//
// MEASURED 23 Sep 2026 (read-only, htdblwldjkcgjvmqkbeh + docs.postiz.com/llms.txt): Postiz's public API
// publishes, lists posts and reads analytics; it has no endpoint that reads or answers a comment. So each
// platform is reached directly with its own official API:
//   instagram / facebook — Meta webhook (marketing_social_inbox) delivers the comment; reply and hide via Graph
//   x                    — polled: GET /2/users/:id/mentions; reply POST /2/tweets; hide PUT /2/tweets/:id/hidden
//   youtube              — polled: commentThreads.list; reply comments.insert; hide comments.setModerationStatus
//   linkedin-page        — NOT built: see the PR. scripts/checks/linkedin_is_never_automated.test.mjs forbids
//                          any code naming LinkedIn's API host, and the Community Management API needs LinkedIn's
//                          own approval of the app first.
//
// THE POLICY, deterministic first (processComment):
//   spam_abuse       -> hidden where the platform allows it, never argued with
//   complaint, sensitive_legal, a request for a person
//                    -> handed to customer_support (fn_seat_handoff 'social.escalation') + a fixed public
//                       acknowledgement that states no fact
//   sales_lead       -> handed to sales_engineer ('social.lead') + the fixed how-it-works reply (comment_lead)
//   supplier_enquiry -> handed to sales_engineer ('social.lead') + the fixed supplier reply (fee facts)
//   praise           -> the fixed thanks
//   question         -> the library / FAQ / knowledge answer (reply.ts decide); only when none exists does the
//                       model draft, and the draft must pass guard() or it is NOT sent (the comment is
//                       escalated instead). While the model is held: recorded 'held_not_run', nothing sent.
//   off_topic        -> ignored
// Our own account is never answered (no loop); a comment id is answered at most once (unique key); a thread
// takes at most 3 seat replies in 10 minutes. Nothing is sent unless app_secrets.social_send_enabled = 'on'
// (the emergency stop) and the author is not a ZZDEMO fixture.
import { langOf, type Lang } from './chat_answers.ts';

export type Platform = 'facebook' | 'instagram' | 'x' | 'youtube';
export type Class = 'question' | 'praise' | 'complaint' | 'spam_abuse' | 'sales_lead' | 'supplier_enquiry' | 'sensitive_legal' | 'off_topic';

export interface CommentEvent {
  platform: Platform;
  accountId: string;        // OUR account on that platform
  commentId: string;        // the idempotency key
  authorId: string;
  handle: string | null;    // what the platform shows publicly; nothing more is kept
  text: string;
  at: Date;
  threadId: string;         // the post / video / conversation the comment sits under
}

// ── CLASSIFY ─────────────────────────────────────────────────────────────────────────────────────
// First hit wins, in this order: abuse before everything (an insult with a question is still abuse),
// legal and complaint before leads (an angry supplier is a complaint, not a lead), a question before praise
// ("great, how do I register?" wants the answer). Asking who a supplier or customer is, is identity: escalated.
const n = (s: string) => ' ' + String(s || '').toLowerCase().replace(/[إأآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/\s+/g, ' ') + ' ';
const RULES: [Class, RegExp][] = [
  ['spam_abuse', /(https?:\/\/(?!(www\.)?quotesdone\.(com|ae))|\bwww\.(?!quotesdone)|crypto|bitcoin|forex|followers|dm me for|promo code|onlyfans|\bidiot|\bstupid\b|\bscam(mers)?\b|fuck|shit|bastard|نصاب|نصابين|حرامي|حراميه|تافه|غبي|كلب|اربح|متابعين)/],
  ['sensitive_legal', /(lawyer|lawsuit|\bsue\b|court|legal action|police|report you|consumer protection|fraud|who (is|was) the (supplier|customer|client)|name of the (supplier|customer|client)|which (supplier|company) (did|was|is)|اسم المورد|اسم العميل|مين المورد|من هو المورد|منو المورد|محامي|محكمه|قضيه|الشرطه|بلاغ|حمايه المستهلك|احتيال)/],
  ['complaint', /(refund|complain|complaint|terrible|worst|disappointed|never (replied|responded|answered)|no one (replied|answered)|charged me|overcharged|not happy|bad service|استرجاع|استرداد|شكوي|اشتكي|سيء|سيئ|اسوا|ما احد رد|ما رد|محد رد|خصم مني|خدمه سيئه|غير راضي)/],
  ['supplier_enquiry', /(supplier|contractor|vendor|register (my|our) (company|business)|list (my|our) (company|business)|get (leads|jobs|projects)|trade licen[cs]e|مورد|موردين|مقاول|تسجيل شركتي|تسجيل شركتنا|رخصه تجاريه)/],
  ['sales_lead', /(i need (a |an )?(quote|quotation)|need quotes?|looking for (a |an )?(company|someone|quote)|can you (do|quote)|how much (for|to|would)|price for|احتاج عرض|ابي عرض|ابغي عرض|اريد عرض|عرض سعر|ابحث عن شركه|كم سعر|كم يكلف)/],
  ['question', /(\?|؟|\bhow\b|\bwhat\b|\bwhere\b|\bwhen\b|\bwhy\b|\bcan i\b|\bdo you\b|\bis it\b|\bfee|كيف|وش|ايش|متي|وين|ليش|هل|كم)/],
  ['praise', /(great|amazing|awesome|love (it|this)|well done|good job|excellent|thank(s| you)|nice|brilliant|👏|🔥|❤|ممتاز|رائع|جميل|يعطيكم العافيه|شكرا|ما شاء الله|مبدعين|احسنتم)/],
];
export function classify(text: string, wantsPerson = false): Class {
  const t = n(text);
  if (RULES[0][1].test(t)) return 'spam_abuse';
  if (wantsPerson) return 'complaint';
  for (const [c, re] of RULES.slice(1)) if (re.test(t)) return c;
  return 'off_topic';
}

// ── THE GUARDS every model draft passes before it can be sent (founder, 23 Sep 2026) ────────────────
// The facts are the company's published ones (site FAQ, supplier agreement v12, portal copy):
// customers pay a 3% reveal fee only on a reveal; the first 1,000 suppliers are free permanently, AED 1,000
// a year from the 1,001st registration; DET Trader Licence 1633275 (never "E-Trader"); the contact line and
// mailbox below. Anything else the draft asserts with a number is a claim nobody verified: it fails.
export const FACTS = {
  percents: ['3'],
  amounts: ['1,000', '1000'],
  numbers: ['1633275', '1,000', '1000', '1,001', '1001', '3', '24', '9', '6', '971'],
  domains: /^(www\.)?quotesdone\.(com|ae)$/,
  emails: ['management@quotesdone.com'],
  phones: ['971509319355'],
};
export const LIMIT: Record<Platform, number> = { x: 280, instagram: 300, facebook: 300, youtube: 500 };
const AR = /[؀-ۿ]/g;
const arabicShare = (s: string) => (s.match(AR) || []).length / Math.max(1, (s.match(/[A-Za-z؀-ۿ]/g) || []).length);

export function guard(draft: string, ev: Pick<CommentEvent, 'platform' | 'text' | 'handle'>): string[] {
  const f: string[] = [];
  const d = String(draft || '').trim();
  if (!d || /^UNKNOWN\b/.test(d)) return ['empty'];
  if (d.length > LIMIT[ev.platform]) f.push('too_long');
  const lang: Lang = langOf(ev.text);
  const share = arabicShare(d);
  if (lang === 'ar' ? share < 0.6 : share > 0.1) f.push('wrong_language');
  for (const m of d.matchAll(/(\d+(?:[.,]\d+)?)\s*(%|٪|percent|بالمئه|بالمائة)/gi)) if (!FACTS.percents.includes(m[1])) f.push('percent:' + m[1]);
  for (const m of d.matchAll(/(?:aed|dhs?|درهم)\s*([\d,]+)|([\d,]+)\s*(?:aed|dhs?|درهم)/gi)) {
    if (!FACTS.amounts.includes(m[1] || m[2])) f.push('amount:' + (m[1] || m[2]));
  }
  for (const m of d.replace(/https?:\/\/\S+/g, '').matchAll(/\d[\d,]*/g)) {
    const digits = m[0].replace(/,/g, '');
    if (digits.length >= 4 && !FACTS.numbers.includes(m[0]) && !FACTS.phones.some((p) => p.includes(digits))) f.push('number:' + m[0]);
  }
  if (/e[\s-]?trader|اي تريدر|إي تريدر/i.test(d)) f.push('e_trader');
  for (const m of d.matchAll(/https?:\/\/([^/\s]+)|\b((?:www\.)?[a-z0-9-]+\.(?:com|ae|net|org|io|co))\b/gi)) {
    if (!FACTS.domains.test((m[1] || m[2]).toLowerCase())) f.push('link:' + (m[1] || m[2]));
  }
  for (const m of d.matchAll(/[\w.+-]+@[\w-]+\.[\w.]+/g)) if (!FACTS.emails.includes(m[0].toLowerCase())) f.push('email');
  for (const m of d.matchAll(/(?:\+|00)?\d[\d\s-]{7,}\d/g)) if (!FACTS.phones.includes(m[0].replace(/\D/g, '').replace(/^00/, ''))) f.push('phone');
  for (const m of d.matchAll(/@([A-Za-z0-9_.]+)/g)) if (m[1].toLowerCase() !== String(ev.handle || '').toLowerCase().replace(/^@/, '') && !/quotesdone/i.test(m[1])) f.push('mention');
  if (/\b(l\.?l\.?c|fze|fzco|trading|contracting|establishment)\b|(supplier|customer|client) (named|called|is)\b|ذ\.م\.م|المورد (هو|اسمه)|العميل (هو|اسمه)/i.test(d)) f.push('identity');
  if (/\b(guarantee[ds]?|promise|we will (refund|fix|call)|will cost|costs? (around|about|from)|starting (at|from)|cheapest|best price|within \d+ (hours|minutes))\b|نضمن|نعدكم|يكلف|اقل سعر|أقل سعر/i.test(d)) f.push('promise_or_price');
  if (/\b(liable|liability|lawsuit|legal advice|legally|court|sue)\b|قانوني|قانونيا|محكمة|مسؤولية قانونية/i.test(d)) f.push('legal');
  if (/[؀-ۿ][,;?]/.test(d) || /يرجى ملاحظة/.test(d)) f.push('arabic_register');
  return f;
}

// ── THE STORE, injected so tests replay every platform with no network and no database ─────────────
export interface Decided { kind: string; key: string | null; text: string }
export interface SendResult { ok: boolean; id?: string | null; error?: string }
export interface Store {
  insertInbound(ev: CommentEvent, cls: Class): Promise<number | null>;   // null: already seen (idempotency)
  threadAllowed(ev: CommentEvent): Promise<boolean>;
  record(inId: number, row: Outcome): Promise<void>;
  handoff(to: 'customer_support' | 'sales_engineer', type: 'social.escalation' | 'social.lead', ev: CommentEvent, cls: Class): Promise<number | null>;
  switchOn(key: 'social_send_enabled' | 'social_model_enabled'): Promise<boolean>;
  library(key: string, lang: Lang): Promise<string>;
  deterministic(ev: CommentEvent): Promise<Decided>;                 // reply.ts decide(): library, FAQ, knowledge
  draft(ev: CommentEvent, lang: Lang): Promise<string | null>;        // the model, only over retrieved knowledge
  reply(ev: CommentEvent, text: string): Promise<SendResult>;
  hide(ev: CommentEvent): Promise<SendResult>;
}
export interface Outcome {
  classification: Class;
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

export async function processComment(s: Store, ev: CommentEvent, wantsPerson = false): Promise<string> {
  if (!ev.text.trim() || ev.authorId === ev.accountId) return 'own_or_empty';
  const cls = classify(ev.text, wantsPerson);
  const inId = await s.insertInbound(ev, cls);
  if (inId == null) return 'duplicate';
  const lang = langOf(ev.text);
  const o: Outcome = { classification: cls, outcome: '', reply: null, decided_by: 'rule', send_status: 'not_sent', guard_failures: [], handoff_id: null };
  const done = async (outcome: string) => { o.outcome = outcome; await s.record(inId, o); return outcome; };
  const escalate = async (to: 'customer_support' | 'sales_engineer', type: 'social.escalation' | 'social.lead') => {
    o.handoff_id = await s.handoff(to, type, ev, cls);
  };

  if (cls === 'off_topic') return await done('ignored_off_topic');
  if (cls === 'spam_abuse') {
    if (isFixture(ev)) { o.send_status = 'held_fixture'; return await done('hide_held'); }
    if (!(await s.switchOn('social_send_enabled'))) { o.send_status = 'held_switch_off'; return await done('hide_held'); }
    const r = await s.hide(ev);
    o.send_status = r.ok ? 'hidden' : 'failed'; o.send_error = r.error ?? null;
    return await done(r.ok ? 'hidden' : 'hide_failed');
  }

  let text = '';
  if (cls === 'complaint' || cls === 'sensitive_legal') { await escalate('customer_support', 'social.escalation'); text = await s.library('comment_escalated_ack', lang); }
  else if (cls === 'supplier_enquiry') { await escalate('sales_engineer', 'social.lead'); text = await s.library('comment_supplier', lang); }
  else if (cls === 'sales_lead') { await escalate('sales_engineer', 'social.lead'); text = await s.library('comment_lead', lang); }
  else if (cls === 'praise') text = await s.library('comment_praise', lang);
  else {
    const d = await s.deterministic(ev);
    if (d.kind === 'handoff') { o.classification = 'complaint'; await escalate('customer_support', 'social.escalation'); text = await s.library('comment_escalated_ack', lang); }
    else if (d.kind !== 'unknown' && d.text) text = d.text;
    else {
      if (!(await s.switchOn('social_model_enabled'))) { o.decided_by = null; o.send_status = 'held_model'; return await done('held_not_run'); }
      const draft = await s.draft(ev, lang);
      o.guard_failures = guard(draft || '', ev);
      if (!o.guard_failures.length) { text = String(draft).trim(); o.decided_by = 'model'; }
      else {
        // A failed draft is never sent and never queued for a person to approve: the seat that owns
        // the subject answers the commenter privately, and the public reply states no fact.
        o.decided_by = 'guard_fallback';
        await escalate('customer_support', 'social.escalation');
        text = await s.library('comment_escalated_ack', lang);
      }
    }
  }
  if (!text) return await done('no_reply_text');
  if (text.length > LIMIT[ev.platform]) text = text.slice(0, LIMIT[ev.platform] - 1).replace(/\s+\S*$/, '') + '…';
  o.reply = text;
  if (!(await s.threadAllowed(ev))) { o.send_status = 'rate_limited'; return await done('rate_limited'); }
  if (isFixture(ev)) { o.send_status = 'held_fixture'; return await done('reply_held'); }
  if (!(await s.switchOn('social_send_enabled'))) { o.send_status = 'held_switch_off'; return await done('reply_held'); }
  const r = await s.reply(ev, text);
  o.send_status = r.ok ? 'sent' : 'failed'; o.send_error = r.error ?? null; o.platform_reply_id = r.id ?? null;
  return await done(r.ok ? 'replied' : 'reply_failed');
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
    case 'x': return { url: 'https://api.x.com/2/tweets', method: 'POST', headers: auth, body: JSON.stringify({ text, reply: { in_reply_to_tweet_id: ev.commentId } }) };
    case 'youtube': return { url: 'https://www.googleapis.com/youtube/v3/comments?part=snippet', method: 'POST', headers: auth,
      body: JSON.stringify({ snippet: { parentId: ev.commentId, textOriginal: text } }) };
  }
}
export function hideRequest(ev: CommentEvent, token: string): Req {
  const auth = { ...J, Authorization: 'Bearer ' + token };
  switch (ev.platform) {
    case 'instagram': return { url: GRAPH + encodeURIComponent(ev.commentId), method: 'POST', headers: auth, body: JSON.stringify({ hide: true }) };
    case 'facebook': return { url: GRAPH + encodeURIComponent(ev.commentId), method: 'POST', headers: auth, body: JSON.stringify({ is_hidden: true }) };
    // X hides replies only under OUR posts; a stand-alone mention cannot be hidden (the API answers 403).
    case 'x': return { url: 'https://api.x.com/2/tweets/' + encodeURIComponent(ev.commentId) + '/hidden', method: 'PUT', headers: auth, body: JSON.stringify({ hidden: true }) };
    case 'youtube': return { url: 'https://www.googleapis.com/youtube/v3/comments/setModerationStatus?id=' + encodeURIComponent(ev.commentId) + '&moderationStatus=heldForReview', method: 'POST', headers: auth };
  }
}
export async function call(f: Fetch, r: Req): Promise<SendResult> {
  try {
    const res = await f(r.url, { method: r.method, headers: r.headers, body: r.body });
    const j = await res.json().catch(() => ({})) as any;
    if (!res.ok) return { ok: false, error: String(j?.error?.message || j?.detail || j?.title || res.status).slice(0, 300) };
    return { ok: true, id: j?.data?.id ?? j?.id ?? null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 300) }; }
}

/** X: mentions of our account since the last one we stored. OAuth 2.0 user token (tweet.read users.read). */
export async function readX(f: Fetch, token: string, userId: string, sinceId: string | null): Promise<CommentEvent[]> {
  const q = new URLSearchParams({ max_results: '100', expansions: 'author_id', 'user.fields': 'username', 'tweet.fields': 'created_at,conversation_id,author_id' });
  if (sinceId) q.set('since_id', sinceId);
  const r = await f('https://api.x.com/2/users/' + encodeURIComponent(userId) + '/mentions?' + q, { headers: { Authorization: 'Bearer ' + token } });
  if (!r.ok) throw new Error('x mentions HTTP ' + r.status);
  const j = await r.json() as any;
  const users = new Map<string, string>((j?.includes?.users || []).map((u: any) => [String(u.id), String(u.username)]));
  return (j?.data || []).map((t: any) => ({ platform: 'x' as const, accountId: userId, commentId: String(t.id), authorId: String(t.author_id),
    handle: users.get(String(t.author_id)) ?? null, text: String(t.text || '').replace(/^(@\w+\s+)+/, '').trim(),
    at: new Date(t.created_at || Date.now()), threadId: String(t.conversation_id || t.id) }));
}

/** YouTube: an access token from the channel's refresh token (scope youtube.force-ssl). */
export async function youtubeToken(f: Fetch, clientId: string, clientSecret: string, refresh: string): Promise<string> {
  const r = await f('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, refresh_token: refresh, grant_type: 'refresh_token' }).toString() });
  const j = await r.json().catch(() => ({})) as any;
  if (!r.ok || !j?.access_token) throw new Error('youtube token HTTP ' + r.status);
  return String(j.access_token);
}
/** YouTube: the newest top-level comments on every video of our channel. */
export async function readYouTube(f: Fetch, token: string, channelId: string): Promise<CommentEvent[]> {
  const r = await f('https://www.googleapis.com/youtube/v3/commentThreads?part=snippet&order=time&maxResults=50&allThreadsRelatedToChannelId='
    + encodeURIComponent(channelId), { headers: { Authorization: 'Bearer ' + token } });
  if (!r.ok) throw new Error('youtube commentThreads HTTP ' + r.status);
  const j = await r.json() as any;
  return (j?.items || []).map((it: any) => {
    const s = it?.snippet?.topLevelComment?.snippet || {};
    return { platform: 'youtube' as const, accountId: channelId, commentId: String(it?.snippet?.topLevelComment?.id || it.id),
      authorId: String(s?.authorChannelId?.value || ''), handle: s?.authorDisplayName ? String(s.authorDisplayName) : null,
      text: String(s?.textOriginal || '').trim(), at: new Date(s?.publishedAt || Date.now()), threadId: String(it?.snippet?.videoId || it.id) };
  });
}
