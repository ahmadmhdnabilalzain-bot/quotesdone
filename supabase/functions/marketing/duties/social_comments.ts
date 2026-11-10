// The social comments duty and the revival of a held comment (split out of duties.ts, 9 Nov 2026; a pure move).
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { call, linkedinComments, processComment, tiktokComments, unhideRequest, youtubeComments, type CommentEvent, type Platform } from '../../_shared/marketing_social_comments.ts';
import { commentClass } from '../../_shared/reasoned_social.ts';
import { accessToken, type SocialPlatform } from '../../_shared/marketing_social_oauth.ts';
import { adminStore, metaPageToken } from '../../_shared/marketing_social_store.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { needsAPerson } from '../../_shared/reasoned_decisions.ts';
import { isolated, Skip } from './shared.ts';
import type { Duty } from './types.ts';

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
