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
import { call, linkedinTarget, processComment, unhideRequest, type CommentEvent, type Platform } from '../_shared/marketing_social_comments.ts';
import { commentClass } from '../_shared/reasoned_social.ts';
import { adminStore, metaPageToken } from '../_shared/marketing_social_store.ts';
import { postizIntegrations, type PostizIntegration } from '../_shared/marketing_channels.ts';
import { defaultDeps } from '../_shared/think.ts';
import { needsAPerson } from '../_shared/reasoned_decisions.ts';

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

// SOCIAL COMMENTS (instruction 866; founder rulings of 23 Sep 2026). Instagram and Facebook comments arrive by
// Meta webhook at marketing_social_inbox; this duty
//   1. retries every Instagram/Facebook comment an earlier run left unfinished (no outcome after 10 minutes);
//   2. un-hides what a reviewing seat said was not abuse, and closes each social.* handoff the receiving seat
//      has answered (the originator closes: fn_marketing_social_handoffs_close);
//   3. YouTube: through the founder's Postiz YouTube connection only — skipped, and SAYS so, until it is there;
//   4. LinkedIn: the QuotesDone company page only (linkedinTarget) — a personal profile is refused.
// X is removed (founder, 23 Sep 2026: no paid X API).
export const socialComments: Duty = {
  name: 'social_comments',
  owner_seat: 'marketing',
  async run({ admin, sec, now }) {
    const gateway = Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway';
    const metaToken = (ev: { platform: Platform; accountId: string }) =>
      ev.platform === 'youtube' ? Promise.resolve(null) : metaPageToken(admin, timedFetch, ev.platform, ev.accountId);
    let postiz: PostizIntegration[] | null = null;
    const integrations = async () => {
      if (postiz) return postiz;
      const key = await sec('postiz_api_key');
      if (!key) throw new Skip('no postiz_api_key');
      const r = await postizIntegrations(timedFetch, (await sec('postiz_api_url')) || 'https://api.postiz.com/public/v1', key);
      if (r.error) throw new Error('postiz integrations HTTP ' + r.status + ': ' + r.error);
      return (postiz = r.list.filter((x) => !x.disabled && !x.refreshNeeded));
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
        // release() handed it back, or a run died before its question was filed) is re-run the same way, so no held
        // comment can wait for a replay that will never come. A row the platform already accepted a reply for
        // (send_status 'sent', marked at the send) is never re-sent.
        // A rotating window over the oldest first, sized to the backlog: with 50 or fewer every tick covers all of
        // them; with more, ceil(n/50) ticks cover all, so rows waiting on an OPEN question (skipped below) never starve
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
        const counts: Record<string, number> = {};
        for (const r of stale || []) {
          if (r.send_status === 'sent') {
            // The platform accepted the reply but the run died before recording it: finish it as answered, never re-send.
            await admin.from('social_message').update({ outcome: 'replied' }).eq('id', r.id).eq('outcome', r.outcome);
            counts['finalized_sent'] = (counts['finalized_sent'] || 0) + 1;
            continue;
          }
          if (String(r.outcome).startsWith('replaying:')) {
            const at = Date.parse(String(r.outcome).slice('replaying:'.length));
            if (!(at < now.getTime() - 10 * 60_000)) continue;
            const { data: won } = await admin.from('social_message').update({ outcome: 'held_classify' }).eq('id', r.id).eq('outcome', r.outcome).select('id');
            if (!won?.length) continue;
          } else {
            // This comment's own questions only: the exact key, or it followed by ':' (a retry) — LIKE's _ and % escaped.
            // This comment's own open class questions, by the subject every one of them carries (exact equality on
            // platform + message id): no LIKE or key range, so nothing in an id can act as a wildcard, and collation
            // (which ignores ':' in the database's locale, measured 23 Sep 2026) plays no part.
            const { data: open } = await admin.from('reasoning_held_question').select('id').eq('status', 'held')
              .eq('surface', 'marketing_social.comment_classify').eq('subject->>platform', r.platform)
              .eq('subject->>message_id', r.meta_message_id).limit(1);
            if (open?.length) continue;
          }
          const ev: CommentEvent = { platform: r.platform, accountId: r.conversation?.account_id, commentId: r.meta_message_id,
            authorId: r.conversation?.user_id, handle: r.conversation?.handle ?? null, text: r.body, at: new Date(r.occurred_at), threadId: r.parent_id || r.meta_message_id };
          const cls = (await commentClass(defaultDeps(admin, 'marketing'), { platform: ev.platform, commentId: ev.commentId, authorId: ev.authorId,
            text: String(ev.text || ''), retry: 'retry:' + now.toISOString() })).value;
          const o = await processComment(adminStore(admin, timedFetch, metaToken, gateway), ev, cls)
            .catch((e) => 'error:' + String(e?.message || e).slice(0, 60));
          counts['revived:' + o] = (counts['revived:' + o] || 0) + 1;
        }
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
        const yt = (await integrations()).find((x) => x.identifier === 'youtube');
        if (!yt) throw new Skip('youtube not connected in Postiz');
        // Measured 23 Sep 2026 (docs.postiz.com/llms.txt): Postiz's public API has no comment read or reply and
        // hands out no platform token, and the founder ruled out our own Google OAuth keys. Nothing is read.
        throw new Skip('youtube connected in Postiz (' + yt.id + '), but Postiz exposes no comment endpoint or token');
      },
      async linkedin() {
        const ours = await sec('linkedin_company_page_integration_id');
        const page = (await integrations()).find((x) => linkedinTarget(x, ours));
        if (!page) throw new Skip('the company page named by linkedin_company_page_integration_id is not connected in Postiz (personal profiles are refused)');
        throw new Skip('linkedin company page connected, but Postiz exposes no comment endpoint');
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
// competitor_study, judgement, plan_loop: the judgement duties (instructions 865-867, above).
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
];
