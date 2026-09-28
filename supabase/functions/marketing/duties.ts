// THE MARKETING SEAT'S DUTY LIST (post_results and scorecard since 23 Sep 2026, instruction 865): the 'duties' action runs every entry on every
// call (resilience_ping step 'marketing', every 30 minutes) before fn_marketing_tick. Owner of every entry: the marketing seat.
//
// The builds that fill it (founder instruction 721, 22 Sep 2026):
//   * publishing / analytics / ad spend — schedule the approved posts through Postiz, read each channel's
//     analytics, and report each platform day of spend with fn_marketing_records_ad_spend (never book it);
//   * the social inbox — answer DMs from company knowledge (fn_marketing_assist) and hand a conversation to
//     the founder with fn_marketing_asks_the_founder_to_take_over the moment someone asks for a person.
//
// HOW TO ADD ONE. Append an entry. A duty decides its own due-ness (return { due: false } when it is not
// time) and returns counts. It throws only on a real failure: the runtime turns a throw into an IT finding
// owned by the marketing seat (fn_it_duty_settle 'marketing_duties'), closed on the first run it passes.
// The Meta and Postiz credentials may be read ONLY under supabase/functions/marketing/ (rule 641,
// scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs). Email and WhatsApp go through
// customer_support (_shared/deliver.ts); replies on the company's own social channels are this seat's.
import { makeLlmRich } from '../_shared/llm.ts';
import { modelHeld } from '../_shared/llm_hold.ts';
import { type Deps, runStep, type Step } from '../_shared/marketing_judgement.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { call, linkedinComments, processComment, tiktokComments, unhideRequest, youtubeComments, type CommentEvent, type Platform } from '../_shared/marketing_social_comments.ts';
import { commentClass } from '../_shared/reasoned_social.ts';
import { accessToken, type SocialPlatform } from '../_shared/marketing_social_oauth.ts';
import { pushFacebook, pushWhatsapp, pushYoutube, VARIANTS } from './profile_text.ts';
import { adminStore, metaPageToken } from '../_shared/marketing_social_store.ts';
import { postizIntegrations, type PostizIntegration } from '../_shared/marketing_channels.ts';
import { defaultDeps, think } from '../_shared/think.ts';
import { needsAPerson } from '../_shared/reasoned_decisions.ts';
import { duckSearch, modelCitation, parseRss, webCitation } from '../_shared/marketing_trends.ts';

// deno-lint-ignore no-explicit-any
export type Admin = any;
export interface DutyContext {
  admin: Admin;
  sec: (key: string) => Promise<string | undefined>;
  now: Date;
}
export interface Duty {
  name: string;
  owner_seat: 'marketing';   // every duty names the seat that owns it
  run: (ctx: DutyContext) => Promise<Record<string, unknown>>;
}

// ── EACH PLATFORM ON ITS OWN ─────────────────────────────────────────────────────────────────────────
// One platform failing never stops the others. A credential failure (missing, expired, refused) SKIPS that
// platform and says so; any other failure is collected and thrown once every step has run, so it becomes the
// seat's IT finding without costing the other platforms their run.
const CREDENTIAL = /\b(401|403|190)\b|token|credential|unauthori[sz]ed|forbidden|expired|oauth|not connected|no .*key/i;
export async function isolated(steps: Record<string, () => Promise<unknown>>) {
  const out: Record<string, unknown> = {}; const skipped: string[] = []; const errors: string[] = [];
  for (const [name, step] of Object.entries(steps)) {
    try { out[name] = await step(); }
    catch (e) {
      const msg = String((e as Error)?.message || e).slice(0, 200);
      if (e instanceof Skip || CREDENTIAL.test(msg)) skipped.push(name + ': ' + msg); else errors.push(name + ': ' + msg);
    }
  }
  return { out, skipped, errors };
}
export class Skip extends Error {}

// ── REVIVING A HELD COMMENT (retry_unfinished) ─────────────────────────────────────────────────────────
// Review of PR #969, 24 Sep 2026: a comment left 'held_classify' with no open question was re-reasoned on every
// sweep under a new retry key (a new model call each time) even when its platform had no usable token. LinkedIn
// not connected ended reply_failed after one wasted call; a YouTube token whose refresh is refused (invalid_grant)
// threw inside the send, release() handed the comment back, and the next sweep reasoned it again, without end.
// Now, for each row, in this order, and nothing is reasoned before the last step:
//   1. the platform already accepted a reply: finished as 'replied', never re-sent;
//   2. a stale 'replaying:<when>' is claimed back to 'held_classify' (compare-and-set); a fresh one is left alone;
//      a comment with an OPEN class question waits for that question's replay;
//   3. YouTube / LinkedIn: the token is resolved (accessToken, refreshing when due). Missing, or the refresh
//      refused: a named skip. No reasoning, no send; the comment stays 'held_classify' for the sweep after the
//      founder reconnects;
//   4. a comment whose class has been asked MAX_CLASS_QUESTIONS times (under the hold every ask files a
//      reasoning_held_question row, open or closed) is not asked again: a named skip, left held for a person;
//   5. only then is the class reasoned (a fresh retry key) and the policy run.
export const MAX_CLASS_QUESTIONS = 4;   // the first ask plus three revivals
type Klass = Awaited<ReturnType<typeof commentClass>>['value'];
export interface HeldCommentRow { id: number; outcome: string; send_status: string | null; meta_message_id: string; platform: Platform; body: string;
  parent_id: string | null; occurred_at: string; conversation?: { user_id: string; handle: string | null; account_id: string } | null }
export interface ReviveIO {
  finalizeSent(r: HeldCommentRow): Promise<void>;
  claim(r: HeldCommentRow): Promise<boolean>;
  classQuestions(r: HeldCommentRow): Promise<{ status: string }[]>;
  /** accessToken() for YouTube / LinkedIn: null = not connected; a throw = the refresh was refused. */
  ownToken(p: SocialPlatform): Promise<string | null>;
  classify(ev: CommentEvent): Promise<Klass>;
  process(ev: CommentEvent, cls: Klass): Promise<string>;
}
export async function reviveHeldComments(rows: HeldCommentRow[], now: Date, io: ReviveIO): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  const count = (k: string) => { counts[k] = (counts[k] || 0) + 1; };
  for (const r of rows) {
    if (r.send_status === 'sent') { await io.finalizeSent(r); count('finalized_sent'); continue; }
    if (String(r.outcome).startsWith('replaying:')) {
      const at = Date.parse(String(r.outcome).slice('replaying:'.length));
      if (!(at < now.getTime() - 10 * 60_000)) continue;
      if (!(await io.claim(r))) continue;
    }
    // Unreadable: skipped this sweep, never reasoned blind.
    const questions = await io.classQuestions(r).catch(() => null);
    if (!questions) { count('skipped:class questions unreadable'); continue; }
    if (questions.some((q) => q.status === 'held')) continue;
    if (r.platform === 'youtube' || r.platform === 'linkedin') {
      let token: string | null = null; let why = 'token missing';
      try { token = String((await io.ownToken(r.platform)) ?? '').trim() || null; } catch (_e) { why = 'token refresh failed'; }
      if (!token) { count('skipped:' + r.platform + ' ' + why); continue; }
    }
    if (questions.length >= MAX_CLASS_QUESTIONS) { count('skipped:class asked ' + MAX_CLASS_QUESTIONS + ' times'); continue; }
    const ev: CommentEvent = { platform: r.platform, accountId: r.conversation?.account_id ?? '', commentId: r.meta_message_id,
      authorId: r.conversation?.user_id ?? '', handle: r.conversation?.handle ?? null, text: r.body, at: new Date(r.occurred_at), threadId: r.parent_id || r.meta_message_id };
    const cls = await io.classify(ev);
    const o = await io.process(ev, cls).catch((e) => 'error:' + String(e?.message || e).slice(0, 60));
    count('revived:' + o);
  }
  return counts;
}

// SOCIAL COMMENTS (instruction 866; founder rulings of 23 Sep 2026). Instagram and Facebook comments arrive by
// Meta webhook at marketing_social_inbox; this duty
//   1. retries every Instagram/Facebook comment an earlier run left unfinished (no outcome after 10 minutes);
//   2. un-hides what a reviewing seat said was not abuse, and closes each social.* handoff the receiving seat
//      has answered (the originator closes: fn_marketing_social_handoffs_close);
//   3. YouTube, 4. the LinkedIn company page and 5. the TikTok business account: read the last 3 days of comments with the token the founder's
//      one link stored (marketing_social_connect; instructions 919-920) and answer each through processComment,
//      the same policy and guards as Instagram and Facebook. Not connected: skipped, and SAYS so.
// X is removed (founder, 23 Sep 2026: no paid X API).
export const socialComments: Duty = {
  name: 'social_comments',
  owner_seat: 'marketing',
  async run({ admin, sec, now }) {
    const gateway = Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway';
    const master = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const save = async (k: string, v: string) => { const { error } = await admin.from('app_secrets').upsert({ key: k, value: v }, { onConflict: 'key' }); if (error) throw new Error('app_secrets ' + k + ': ' + error.message); };
    const own = (p: SocialPlatform) => accessToken(timedFetch, p, master, sec, save);
    const metaToken = async (ev: { platform: Platform; accountId: string }) =>
      ev.platform === 'youtube' || ev.platform === 'linkedin' ? (await own(ev.platform))?.access_token ?? null
        : ev.platform === 'tiktok' ? (await sec('tiktok_business_token')) ?? null
        : metaPageToken(admin, timedFetch, ev.platform, ev.accountId);
    const since = new Date(now.getTime() - 3 * 24 * 3600_000);
    const answer = async (events: CommentEvent[]) => {
      const counts: Record<string, number> = { read: events.length };
      for (const ev of events) {
        // A person check is REASONED (think()) and lazy, as in retry_unfinished below; held, it is queued.
        const person = async () => (await needsAPerson(defaultDeps(admin, 'marketing'), { seat: 'marketing', surface: 'marketing_social.comment_needs_a_person',
          message: String(ev.text || '').slice(0, 4000), audience: 'visitor', dedupeKey: 'social_comment:' + ev.platform + ':' + ev.commentId,
          subject: { platform: ev.platform, message_id: ev.commentId, user_id: ev.authorId } })).value === true;
        // What the comment IS is reasoned too (reasoned_social.ts), lazily; held, nothing is hidden or said (held_classify).
        const cls = async () => (await commentClass(defaultDeps(admin, 'marketing'), { platform: ev.platform, commentId: ev.commentId, authorId: ev.authorId, text: String(ev.text || '') })).value;
        const o = await processComment(adminStore(admin, timedFetch, metaToken, gateway), ev, cls, person)
          .catch((e) => 'error:' + String(e?.message || e).slice(0, 60));
        counts[o] = (counts[o] || 0) + 1;
      }
      return counts;
    };

    const { out, skipped, errors } = await isolated({
      async retry_unfinished() {
        const { data, error } = await admin.from('social_message')
          .select('meta_message_id,platform,body,parent_id,occurred_at,conversation:social_conversation(user_id,handle,account_id)')
          .eq('direction', 'in').eq('channel', 'comment').is('outcome', null)
          .lt('created_at', new Date(now.getTime() - 10 * 60_000).toISOString())
          .gt('created_at', new Date(now.getTime() - 24 * 3600_000).toISOString()).limit(50);
        if (error) throw new Error('unfinished comments: ' + error.message);
        // A replay of a held comment that died mid-way leaves outcome 'replaying:<when>'. After 10 minutes it is
        // handed back to 'held_classify' (compare-and-set, so a live replay is never overtaken; never emptied, so a
        // failed run cannot delete it — release() returns it to 'held_classify' again) and re-run here with a FRESH
        // reasoning (a new dedupe key, since its first held question is already closed): answered, the policy runs;
        // held again, it is queued anew and waits for its own replay.
        // ALSO: a 'held_classify' comment with NO open held question (a replay answered but its send failed and
        // release() handed it back, a replay skipped for a missing token, or a run died before its question was filed)
        // is re-run the same way — through reviveHeldComments above, which checks the platform's token BEFORE any
        // reasoning and stops at MAX_CLASS_QUESTIONS, so no comment is reasoned without end. A row the platform
        // already accepted a reply for (send_status 'sent', marked at the send) is never re-sent.
        // A rotating window over the oldest first, sized to the backlog: with 50 or fewer every tick covers all of
        // them; with more, ceil(n/50) ticks cover all, so rows waiting on an OPEN question (skipped there) never starve
        // the rest. ponytail: move the "no open question" test into SQL (an RPC) if the backlog grows large.
        const staleOf = () => admin.from('social_message').select('id', { count: 'exact', head: true })
          .eq('direction', 'in').eq('channel', 'comment').or('outcome.like.replaying:%,outcome.eq.held_classify');
        const { count: backlog } = await staleOf();
        const windows = Math.max(1, Math.ceil((backlog ?? 0) / 50));
        const from = (Math.floor(now.getTime() / 600_000) % windows) * 50;
        const { data: stale, error: staleErr } = await admin.from('social_message')
          .select('id,outcome,send_status,meta_message_id,platform,body,parent_id,occurred_at,conversation:social_conversation(user_id,handle,account_id)')
          .eq('direction', 'in').eq('channel', 'comment').or('outcome.like.replaying:%,outcome.eq.held_classify')
          .order('occurred_at', { ascending: true }).range(from, from + 49);
        if (staleErr) throw new Error('stale comment replays: ' + staleErr.message);
        const counts = await reviveHeldComments((stale || []) as HeldCommentRow[], now, {
          finalizeSent: async (r) => { await admin.from('social_message').update({ outcome: 'replied' }).eq('id', r.id).eq('outcome', r.outcome); },
          claim: async (r) => { const { data: won } = await admin.from('social_message').update({ outcome: 'held_classify' }).eq('id', r.id).eq('outcome', r.outcome).select('id'); return !!won?.length; },
          // This comment's own class questions, by the subject every one of them carries (exact equality on
          // platform + message id): no LIKE or key range, so nothing in an id can act as a wildcard, and collation
          // (which ignores ':' in the database's locale, measured 23 Sep 2026) plays no part.
          classQuestions: async (r) => {
            const { data: qs, error: qe } = await admin.from('reasoning_held_question').select('status')
              .eq('surface', 'marketing_social.comment_classify').eq('subject->>platform', r.platform)
              .eq('subject->>message_id', r.meta_message_id).limit(MAX_CLASS_QUESTIONS + 1);
            if (qe) throw new Error('class questions: ' + qe.message);
            return (qs || []) as { status: string }[];
          },
          ownToken: async (p) => (await own(p))?.access_token ?? null,
          classify: async (ev) => (await commentClass(defaultDeps(admin, 'marketing'), { platform: ev.platform, commentId: ev.commentId, authorId: ev.authorId,
            text: String(ev.text || ''), retry: 'retry:' + now.toISOString() })).value,
          process: (ev, cls) => processComment(adminStore(admin, timedFetch, metaToken, gateway), ev, cls),
        });
        for (const r of data || []) {
          const ev: CommentEvent = { platform: r.platform, accountId: r.conversation?.account_id, commentId: r.meta_message_id,
            authorId: r.conversation?.user_id, handle: r.conversation?.handle ?? null, text: r.body, at: new Date(r.occurred_at), threadId: r.parent_id || r.meta_message_id };
          // A person check is REASONED (think()); held, it is queued under the same dedupe key the webhook used.
          const person = async () => (await needsAPerson(defaultDeps(admin, 'marketing'), { seat: 'marketing', surface: 'marketing_social.comment_needs_a_person',
            message: String(ev.text || '').slice(0, 4000), audience: 'visitor', dedupeKey: 'social_comment:' + ev.platform + ':' + ev.commentId,
            subject: { platform: ev.platform, message_id: ev.commentId, user_id: ev.authorId } })).value === true;
          // What the comment IS is reasoned too (reasoned_social.ts); held, nothing is hidden or said (held_classify).
          const cls = async () => (await commentClass(defaultDeps(admin, 'marketing'), { platform: ev.platform, commentId: ev.commentId, authorId: ev.authorId, text: String(ev.text || '') })).value;
          const o = await processComment(adminStore(admin, timedFetch, metaToken, gateway), ev, cls, person)
            .catch((e) => 'error:' + String(e?.message || e).slice(0, 60));
          counts[o] = (counts[o] || 0) + 1;
        }
        return counts;
      },
      async close_handoffs() {
        // A hide the reviewing seat reversed is un-hidden first; then every answered handoff is closed by us.
        const { data } = await admin.from('agent_actions').select('id,detail').eq('kind', 'handoff').eq('status', 'pending')
          .in('detail->>type', ['social.escalation', 'social.lead']).eq('detail->>unhide', 'true').is('detail->>unhidden_at', null).limit(50);
        let unhidden = 0;
        for (const h of data || []) {
          const d = h.detail || {};
          const ev = { platform: d.platform, accountId: d.account, commentId: d.comment } as CommentEvent;
          const t = await metaToken(ev);
          if (!t) continue;
          const r = await call(timedFetch, unhideRequest(ev, t));
          if (r.ok) { await admin.from('agent_actions').update({ detail: { ...d, unhidden_at: now.toISOString() } }).eq('id', h.id); unhidden++; }
        }
        const { data: closed, error } = await admin.rpc('fn_marketing_social_handoffs_close');
        if (error) throw new Error('fn_marketing_social_handoffs_close: ' + error.message);
        return { unhidden, closed };
      },
      async youtube() {
        const t = await own('youtube');
        if (!t) throw new Skip('youtube not connected (the founder\'s link: scripts/marketing/social_connect_link.mjs youtube)');
        return await answer(await youtubeComments(timedFetch, t.access_token, t.account_id, since));
      },
      async linkedin() {
        const t = await own('linkedin');
        if (!t) throw new Skip('linkedin company page not connected (the founder\'s link: scripts/marketing/social_connect_link.mjs linkedin)');
        return await answer(await linkedinComments(timedFetch, t.access_token, t.account_id, since));
      },
      // TikTok: the business account's own token, so every reply posts AS the QuotesDone account.
      async tiktok() {
        const token = await sec('tiktok_business_token'); const biz = await sec('tiktok_business_id');
        if (!token || !biz) throw new Skip('tiktok business account not connected (app_secrets.tiktok_business_token + tiktok_business_id)');
        return await answer(await tiktokComments(timedFetch, token, biz, since));
      },
    });
    const counts = { ...out, skipped };
    if (errors.length) throw new Error(errors.join(' | ') + ' (the other steps ran: ' + JSON.stringify(counts).slice(0, 300) + ')');
    return counts;
  },
};

import { POST_RESULTS, SCORECARD } from './post_results.ts';

// A page's VISIBLE text, so a rotated script nonce or tracking tag is not a "change" — only the words are.
export function visibleText(html: string): string {
  return html.replace(/<(script|style|noscript)[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ')
    // Google's help pages carry a fresh random 10+ digit token on every load; it is not a word of the page.
    .replace(/&[a-z#0-9]+;/gi, ' ').replace(/\b\d{10,}\b/g, ' ').replace(/\s+/g, ' ').trim();
}
async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// PLATFORM SPEC FRESHNESS (founder instruction 869, 23 Sep 2026). Every page marketing_platform_spec cites is re-read
// once a month, three per beat (the edge CPU cap). A changed page, or one that stops answering, is an IT finding owned
// by marketing (fn_marketing_platform_spec_freshness -> fn_it_duty_settle 'marketing_platform_spec_freshness') and it
// stays open until the rows are re-checked and fn_marketing_platform_spec_source_verified(url, who) is called.
const platformSpecFreshness: Duty = {
  name: 'platform_spec_freshness',
  owner_seat: 'marketing',
  run: async ({ admin }) => {
    const due = await admin.rpc('fn_marketing_platform_spec_sources_due', { p_limit: 3 });
    if (due.error) throw new Error('sources_due: ' + due.error.message);
    const urls = (due.data || []) as string[];
    let changed = 0;
    for (const url of urls) {
      let hash: string | null = null, status = 0, error: string | null = null;
      try {
        const r = await fetch(url, { headers: { 'User-Agent': 'QuotesDone-marketing-spec-check' }, signal: AbortSignal.timeout(12000) });
        status = r.status;
        if (r.ok) hash = await sha256(visibleText(await r.text()));
        else error = 'HTTP ' + r.status;
      } catch (e) { error = String((e as Error)?.message || e); }
      const seen = await admin.rpc('fn_marketing_platform_spec_source_seen', { p_url: url, p_hash: hash, p_status: status, p_error: error });
      if (seen.error) throw new Error('source_seen: ' + seen.error.message);
      if (seen.data?.changed) changed++;
    }
    const settled = await admin.rpc('fn_marketing_platform_spec_freshness');
    if (settled.error) throw new Error('freshness: ' + settled.error.message);
    return { due: urls.length > 0, read: urls.length, changed, open_findings: settled.data?.failing ?? null };
  },
};


// ── THE JUDGEMENT DUTIES (marketing, 23 Sep 2026; founder instructions 865, 866, 867) ─────────────────────────
// scripts/sql/the_marketing_seat_watches_its_videos_studies_the_market_and_argues_its_month_with_the_ceo.sql.
// Owner of every entry below: the marketing seat. Cadence: resilience_step 'marketing' (every 30 minutes); each
// duty bounds itself (fn_marketing_steps_due caps per day; at most 1 model step per beat, so the 55 s heartbeat call is never outrun; research weekly).
// While the founder's hold stands every model step records "held, not run" once a day and writes nothing else.

// THE GRAPH API VERSION IS ONE CONFIG VALUE: app_secrets.meta_graph_version, defaulting to the version the seat's
// other Meta callers use today. Moving versions is one row, not a code search.
const DEFAULT_GRAPH_VERSION = 'v21.0';
async function graphBase(ctx: DutyContext): Promise<string> {
  const v = String((await ctx.sec('meta_graph_version')) || DEFAULT_GRAPH_VERSION).trim();
  return 'https://graph.facebook.com/' + (/^v\d+\.\d+$/.test(v) ? v : DEFAULT_GRAPH_VERSION);
}

/** The seat's model client: its own class per step, charged to the marketing ceiling. */
function marketingDeps(ctx: DutyContext): Deps {
  return {
    admin: ctx.admin,
    held: () => modelHeld(ctx.admin),
    callModel: async (taskClass, max, messages, requireCaps) => {
      const llm = makeLlmRich(undefined, { fn: 'marketing', taskClass, dept: 'marketing', agent: 'marketing', max, timeoutMs: 45000, temperature: 0.2 });
      const r = await llm('', '', max, '', { messages, requireCaps });
      return { content: r.content, error: r.error, truncated: r.truncated, model: r.model ?? null };
    },
    download: async (bucket, path) => {
      const { data, error } = await ctx.admin.storage.from(bucket).download(path);
      if (error || !data) throw new Error('download ' + path + ': ' + (error?.message || 'nothing'));
      return new Uint8Array(await data.arrayBuffer());
    },
    signedUrl: async (bucket, path) => {
      const { data } = await ctx.admin.storage.from(bucket).createSignedUrl(path, 3600);
      return data?.signedUrl ?? null;
    },
  };
}

// post_results: ties each published post to its platform ids and reads its results at +1d/+3d/+7d/+28d.
// scorecard:    fn_marketing_scorecard stored weekly (Monday, Asia/Dubai) and at month end (the 1st).
// platform_spec_freshness: the cited platform pages re-read monthly (above).
// social_comments: public comments read and answered on every synced channel (instruction 866, above).
// PROFILE TEXT (instruction 920): once a day, every profile an API may write is made to equal profile_text.json.
export const profileText: Duty = {
  name: 'profile_text',
  owner_seat: 'marketing',
  async run({ admin, sec, now }) {
    if (now.getUTCHours() !== 3 || now.getUTCMinutes() >= 30) return { due: false };
    if ((await sec('profile_text_push')) === 'off') return { due: true, held: 'app_secrets.profile_text_push is off' };
    const since = new Date(now.getTime() - 10 * 60_000).toISOString();
    const master = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const save = async (k: string, v: string) => { const { error } = await admin.from('app_secrets').upsert({ key: k, value: v }, { onConflict: 'key' }); if (error) throw new Error(error.message); };
    const { out, skipped, errors } = await isolated({
      async whatsapp() {
        const [ks, kk, from] = await Promise.all([sec('twilio_api_key_sid'), sec('twilio_api_key_secret'), sec('twilio_wa_from')]);
        if (!ks || !kk || !from) throw new Skip('no Twilio key or twilio_wa_from');
        return await pushWhatsapp(timedFetch, 'Basic ' + btoa(`${ks}:${kk}`), from, since);
      },
      async facebook() {
        const { data } = await admin.from('marketing_meta_page').select('page_id').limit(1).maybeSingle();
        if (!data?.page_id) throw new Skip('no Facebook page cached yet (marketing_meta_page)');
        const t = await metaPageToken(admin, timedFetch, 'facebook', data.page_id);
        if (!t) throw new Skip('no page token');
        return await pushFacebook(timedFetch, data.page_id, t);
      },
      async youtube() {
        const t = await accessToken(timedFetch, 'youtube', master, sec, save);
        if (!t) throw new Skip('youtube not connected');
        return await pushYoutube(timedFetch, t.access_token);
      },
    });
    if (errors.length) throw new Error(errors.join(' | ') + ' (' + JSON.stringify({ out, skipped }).slice(0, 300) + ')');
    return { due: true, ...out, skipped, manual: VARIANTS.filter((v) => v.api === 'manual').map((v) => v.platform + '.' + v.field) };
  },
};


// ── TRENDS, GEO AND THE REVIEWS (marketing, 24 Sep 2026; ledger 983, GAPS.md "## Marketing" gaps 3, 5, 8) ───────
// scripts/sql/marketing_watches_trends_audits_answer_engines_and_reviews_the_brand_each_quarter.sql.
// Each bounds itself for the edge CPU cap: two feeds and ONE judgement per beat; two GEO checks per beat.

/** One trend's relevance, reasoned (surface marketing.trend_relevance). Held: null, and it is asked again next beat. */
export async function judgeTrend(deps: Parameters<typeof think>[0], t: { id: number; title: string; url: string; source: string }) {
  const r = await think(deps, {
    seat: 'marketing', surface: 'marketing.trend_relevance', queueWhenHeld: false, research: false,
    question: `A news item from "${t.source}": ${t.title} (${t.url}). Does it matter to QuotesDone, a UAE construction and fit-out procurement marketplace that is registering suppliers now and launches to customers in January 2027? If it does, say in one line what the marketing seat should do with it.`,
    context: { audience: 'internal' },
    decision: { name: 'trend_relevance', options: [
      { id: 'relevant', meaning: 'it changes what UAE buyers or suppliers of construction, fit-out, MEP or building materials need, fear or search for, or what a competitor offers; usable in content or positioning' },
      { id: 'not_relevant', meaning: 'nothing the company can act on' },
    ], fields: [{ key: 'why_it_matters', question: 'in one line, why it matters and what content or positioning it suggests' }] },
  });
  if (r.status !== 'answered' || !r.decision?.choice) return null;
  const why = (r.decision.fields?.why_it_matters?.value || r.answer || '').trim().slice(0, 300);
  // "Relevant" with no reason is not usable in a plan; recording it as not relevant (and saying why) ends the retry
  // instead of re-asking the model about the same headline every beat.
  if (r.decision.choice === 'relevant' && !why) return { relevant: false, why: 'judged relevant but no reason was given; not used', model: r.model ?? 'think' };
  return { relevant: r.decision.choice === 'relevant', why, model: r.model ?? 'think' };
}

export const trendWatch: Duty = {
  name: 'trend_watch',
  owner_seat: 'marketing',
  async run({ admin }) {
    const { data: srcs, error } = await admin.rpc('fn_marketing_trend_sources_due', { p_limit: 2 });
    if (error) throw new Error('fn_marketing_trend_sources_due: ' + error.message);
    let fresh = 0; const failed: string[] = [];
    for (const s of (srcs || []) as Array<{ id: number; name: string; feed_url: string }>) {
      let items: ReturnType<typeof parseRss> = [], err: string | null = null;
      try {
        const r = await timedFetch(s.feed_url, { headers: { 'User-Agent': 'QuotesDone-marketing-trends/1.0 (+https://www.quotesdone.ae)' } }, 12_000);
        if (r.ok) items = parseRss(await r.text()); else err = 'HTTP ' + r.status;
      } catch (e) { err = String((e as Error)?.message || e).slice(0, 200); }
      const seen = await admin.rpc('fn_marketing_trend_seen', { p_source_id: s.id, p_items: items, p_error: err });
      if (seen.error) throw new Error('fn_marketing_trend_seen: ' + seen.error.message);
      if (err) failed.push(s.name + ': ' + err); else fresh += Number(seen.data) || 0;
    }
    const { data: next } = await admin.rpc('fn_marketing_trend_next_to_judge');
    let judged: unknown = null;
    const t = (next || [])[0];
    if (t) {
      const j = await judgeTrend(defaultDeps(admin, 'marketing'), t);
      if (j) {
        const w = await admin.rpc('fn_marketing_trend_judged', { p_id: t.id, p_relevant: j.relevant, p_why: j.why, p_by: j.model });
        if (w.error) throw new Error('fn_marketing_trend_judged: ' + w.error.message);
        judged = { id: t.id, relevant: j.relevant };
      } else judged = { id: t.id, held: true };
    }
    // A feed that fails is recorded on its row (last_error) and retried tomorrow; only every active feed failing is a finding.
    if (failed.length) {
      const { data: healthy } = await admin.from('marketing_trend_source').select('id').eq('active', true).is('last_error', null).limit(1);
      if (!healthy?.length) throw new Error('every trend feed failed: ' + failed.join('; '));
    }
    return { due: (srcs || []).length > 0 || !!t, read: (srcs || []).length, new_trends: fresh, judged, failed };
  },
};

export const geoAudit: Duty = {
  name: 'geo_audit',
  owner_seat: 'marketing',
  async run(ctx) {
    const held = await modelHeld(ctx.admin);   // under the founder's hold only the web checks are due
    const { data, error } = await ctx.admin.rpc('fn_marketing_geo_due', { p_limit: 2, p_include_model: !held });
    if (error) throw new Error('fn_marketing_geo_due: ' + error.message);
    const rows = (data || []) as Array<{ question_id: number; question: string; engine: 'web' | 'model'; month: string }>;
    const done: unknown[] = [];
    for (const q of rows) {
      let rec: { cited: boolean; rank: number | null; evidence: string | null; model: string | null };
      if (q.engine === 'web') {
        // No results is a blocked or changed page, not "we are not cited": nothing is recorded, and it is a finding.
        let results;
        try { results = await duckSearch(q.question, (u, i) => timedFetch(u, i, 12_000)); }
        catch (e) { throw new Error((e as Error).message + ' for GEO question ' + q.question_id); }
        rec = { ...webCitation(results), model: null };
      } else {

        const a = await marketingDeps(ctx).callModel('marketing_research', 600,
          [{ role: 'user', content: q.question + ' Name specific platforms or companies if you know any.' }], []);
        if (a.error || !a.content) throw new Error('geo model check: ' + (a.error || 'no answer'));
        rec = { ...modelCitation(a.content), rank: null, model: a.model ?? null };
      }
      const w = await ctx.admin.rpc('fn_marketing_geo_record', { p_month: q.month, p_question_id: q.question_id, p_engine: q.engine,
        p_cited: rec.cited, p_rank: rec.rank, p_evidence: rec.evidence, p_model: rec.model });
      if (w.error) throw new Error('fn_marketing_geo_record: ' + w.error.message);
      done.push({ question: q.question_id, engine: q.engine, cited: rec.cited });
    }
    return { due: rows.length > 0, checked: done };
  },
};

export const reviews: Duty = {
  name: 'reviews',
  owner_seat: 'marketing',
  async run({ admin, now }) {
    const { data, error } = await admin.rpc('fn_marketing_reviews_tick', { p_at: now.toISOString() });
    if (error) throw new Error('fn_marketing_reviews_tick: ' + error.message);
    return { due: Object.keys(data || {}).length > 0, composed: data };
  },
};

// competitor_study, judgement, plan_loop: the judgement duties (instructions 865-867, above); profile_text (920).
export const DUTIES: Duty[] = [
  POST_RESULTS, SCORECARD, platformSpecFreshness, socialComments,
  {
    // Item 7, the fetch. SOURCE: Instagram Graph API business_discovery — official and free, and it returns a
    // competitor business account's ORGANIC posts (caption, type, permalink, time, likes, comments). The Meta Ad
    // Library API was rejected for this: outside the EU/UK it returns only political and issue ads, so it has
    // nothing on a UAE supplier's commercial or organic content, and the plan is organic only (866). Needs
    // meta_access_token and meta_ig_user_id (the company's own IG business account); until both are set the duty
    // says so and is not due. Weekly; competitors are the rows of public.competitor with social_handles.instagram.
    name: 'competitor_study',
    owner_seat: 'marketing',
    run: async (ctx) => {
      const token = await ctx.sec('meta_access_token');
      const igUser = await ctx.sec('meta_ig_user_id');
      if (!token || !igUser) return { due: false, reason: 'meta_access_token and meta_ig_user_id are not both set' };
      const { data: last } = await ctx.admin.from('market_intel').select('fetched_at').eq('platform', 'instagram')
        .order('fetched_at', { ascending: false }).limit(1).maybeSingle();
      if (last?.fetched_at && ctx.now.getTime() - new Date(last.fetched_at).getTime() < 7 * 86400_000) return { due: false, reason: 'fetched this week' };
      // A DATED FAILURE MARKER: a fetch that failed today is not retried, and not raised again, until tomorrow.
      const today = new Date(ctx.now.getTime() + 4 * 3600_000).toISOString().slice(0, 10);   // Dubai day
      const { data: failedToday } = await ctx.admin.from('marketing_model_run').select('id').eq('step', 'competitor_fetch')
        .eq('outcome', 'failed').eq('run_day', today).limit(1);
      if (failedToday && failedToday.length) return { due: false, reason: 'the fetch failed today; next try tomorrow' };
      const base = await graphBase(ctx);
      const { data: comps } = await ctx.admin.from('competitor').select('id,name,social_handles').not('social_handles->>instagram', 'is', null).limit(25);
      const rows: Record<string, unknown>[] = []; const errors: string[] = [];
      for (const c of (comps || []) as Array<{ id: number; social_handles: Record<string, string> }>) {
        const handle = String(c.social_handles.instagram).replace(/^@/, '');
        const fields = `business_discovery.username(${handle}){media.limit(25){id,caption,media_type,permalink,timestamp,like_count,comments_count}}`;
        const r = await fetch(`${base}/${igUser}?fields=${encodeURIComponent(fields)}&access_token=${encodeURIComponent(token)}`,
          { signal: AbortSignal.timeout(15000) });
        // deno-lint-ignore no-explicit-any
        const j = await r.json().catch(() => null) as any;
        if (!r.ok) { errors.push(handle + ': ' + String(j?.error?.message || r.status).slice(0, 120)); continue; }
        for (const m of j?.business_discovery?.media?.data || []) {
          rows.push({ platform: 'instagram', source: 'business_discovery', external_id: m.id, competitor_id: c.id,
            source_url: m.permalink, posted_at: m.timestamp, caption: m.caption ?? null, media_type: m.media_type,
            metrics: { likes: m.like_count ?? null, comments: m.comments_count ?? null } });
        }
      }
      const { data, error } = await ctx.admin.rpc('fn_marketing_intel_upsert', { p_rows: rows });
      if (error) throw new Error('fn_marketing_intel_upsert: ' + error.message);
      if (errors.length && !rows.length) {
        // recorded once for the day, then raised once (the runtime turns this throw into marketing's IT finding)
        await ctx.admin.from('marketing_model_run').insert({ step: 'competitor_fetch', subject: today, seat: 'marketing',
          task_class: 'deterministic', outcome: 'failed', reason: ('every competitor fetch failed: ' + errors.join('; ')).slice(0, 1000), run_day: today });
        throw new Error('every competitor fetch failed: ' + errors.join('; '));
      }
      return { due: true, competitors: (comps || []).length, posts: rows.length, stored: data, errors };
    },
  },
  {
    // Items 6 (perception), 7 (synthesis), 8 (quality review), 9 (verdict, plan, defence): whatever is due, at
    // most 1 per beat. The CEO's review is never run here: it is a seat_deliberation (founder_instruction 873),
    // advanced by resilience_ping on another model family, and 'plan_loop' below reads its verdict back.
    name: 'judgement',
    owner_seat: 'marketing',
    run: async (ctx) => {
      const { data, error } = await ctx.admin.rpc('fn_marketing_steps_due', { p_at: ctx.now.toISOString() });
      if (error) throw new Error('fn_marketing_steps_due: ' + error.message);
      const due = (data || []) as Array<{ step: Step; subject: string }>;
      const ran = [];
      for (const d of due.slice(0, 1)) ran.push(await runStep(marketingDeps(ctx), 'marketing', d.step, d.subject));
      return { due: due.length, ran };
    },
  },
  {
    // Item 9, the author's side: send a waiting plan into the CEO's review (seat_deliberation), take each CEO
    // verdict back into marketing_plan_review_turn, close the deliberation once agreed, send the brief once.
    name: 'plan_loop',
    owner_seat: 'marketing',
    run: async (ctx) => {
      const { data, error } = await ctx.admin.rpc('fn_marketing_plan_loop_tick');
      if (error) throw new Error('fn_marketing_plan_loop_tick: ' + error.message);
      return data as Record<string, unknown>;
    },
  },
  profileText, trendWatch, geoAudit, reviews,
];
