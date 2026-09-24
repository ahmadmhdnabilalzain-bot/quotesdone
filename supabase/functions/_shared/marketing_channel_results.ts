// WHAT ACTUALLY HAPPENED ON EACH CHANNEL AFTER A POST WENT TO POSTIZ (marketing + it_engineer, 24 Sep 2026).
//
// MEASURED BEFORE THIS: marketing_channels/index.ts set marketing_post.status = 'published' the moment Postiz
// answered POST /public/v1/posts with 2xx. That answer means "Postiz accepted the job", not "every platform took
// it": Postiz publishes afterwards, per channel, and a channel can fail or half-succeed (the founder's example:
// YouTube reported the thumbnail was not set). Nothing read that back, so a half-published post read as done.
// Production, 24 Sep 2026: posts 84-87 (linkedin, facebook, youtube, instagram) are all 'published' with
// postiz_result holding only the ids Postiz returned on the POST -- no per-channel outcome anywhere.
//
// WHAT POSTIZ'S PUBLIC API GIVES (read from the Postiz source, gitroomhq/postiz-app main, 24 Sep 2026;
// docs.postiz.com was unreachable from the build environment):
//   CONFIRMED  GET /public/v1/posts?startDate&endDate -> { posts: [{ id, content, publishDate, releaseURL,
//              releaseId, state, group, settings, integration: { id, providerIdentifier, ... } }] }, only
//              top-level posts (parentPostId null). state is one of QUEUE | PUBLISHED | ERROR | DRAFT.
//   CONFIRMED  Post.error (the reason text) exists in Postiz's database but GET /posts does NOT select it; the
//              per-post timeline (GET /public/v1/debug/posts/:id) is super-admin only. So the reason text on the
//              public API comes from notifications. `error` is still read below if Postiz ever returns it.
//   CONFIRMED  GET /public/v1/notifications?page=N -> { notifications: [{ id, content, link, createdAt }], total,
//              page, limit: 100, hasMore }, newest first. `content` is the MESSAGE of the in-app notification.
//              The post workflow's messages (orchestrator post.workflow.v1.1.2.ts):
//                "Your post has been published on <Provider> at <releaseURL>"
//                "An error occurred while posting on <provider>[: <the platform's message>]"
//                "Error posting comments on <provider>" (subject form; a thread reply / first comment failed)
//                "Your post was sent to <Provider>, but we couldn't confirm it was published. ..."
//                "We couldn't post to <provider> for <name> because you need to reconnect it / it's disabled"
//   CONFIRMED  YouTube's provider sets the thumbnail after the upload with no try/catch, so a refused thumbnail
//              throws after the video exists: Postiz marks the post ERROR (markUnconfirmed / the error branch),
//              releaseURL is not written, and the video is live without its thumbnail.
//   ASSUMED    A notification carries no post id. It is tied to a channel by the provider name in its text and
//              by time: from the moment the post was sent until the next post on the same channel (at most 48
//              hours), and never when its text names another post's release URL. A platform's own message
//              reaches us only through "An error occurred while posting on <provider>: <message>".
//
// THE RULE (the founder's words, instruction on per-channel results, 24 Sep 2026):
//   channel  published  Postiz says PUBLISHED and nothing it said about that channel is a problem.
//            partial    it reached the platform but a sub-step failed or degraded: Postiz says PUBLISHED and
//                       reported an error for it, or says ERROR with evidence it got there (a release id/URL,
//                       "couldn't confirm", a comment/thread step, or a thumbnail / caption / resolution /
//                       quality / frame-rate / audio complaint). Instruction 997's floor is 1080x1920, 60 fps,
//                       ~0.8 Mbps, mono: a platform saying it lowered any of that is partial, never published.
//            failed     never published: skipped at send (not connected, wrong media), Postiz says ERROR with
//                       nothing showing it reached the platform, or still not published 48 hours after sending.
//            pending    Postiz has not finished (QUEUE / DRAFT / not listed yet) inside the 48 hours.
//   post     published only if every channel is published; failed if none is published or partial; partial
//            otherwise; pending while any channel is pending. (The database applies the same rule when it
//            stores the rows: fn_marketing_post_channel_record.)
// Every partial / failed channel is one it_engineer finding keyed duty:postiz_channel_result:post:<id>:<channel>,
// refiled on every re-check under the same key and closed by fn_it_duty_settle when a re-check no longer finds it.
//
// Deterministic string rules; no model. READ-ONLY toward Postiz: two GETs, no write. Tested offline in
// marketing_channel_results.test.ts against the recorded shapes above.
import { channelOf, type Fetch, type Platform } from './marketing_post_results.ts';

export type ChannelState = 'pending' | 'published' | 'partial' | 'failed';
export type PostOutcome = ChannelState;
export const RECHECK_HOURS = 48;

export interface PostizPost {
  id: string; state: string; releaseURL: string | null; releaseId: string | null;
  identifier: string; integrationId: string | null; publishDate: string | null; error: string | null;
}
export interface Note { id: string; content: string; link: string | null; createdAt: string }

async function readJson(r: Response): Promise<any> {
  const t = await r.text();
  try { return JSON.parse(t); } catch { return { raw: t.slice(0, 200) }; }
}
/** Postiz may store HTML; everything is compared as plain text. */
export const plain = (s: unknown) => String(s ?? '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();
const url = (s: unknown) => (typeof s === 'string' && /^https:\/\//.test(s) ? s : null);

/** GET /public/v1/posts over a window: every post by id with its state. ok=false means NOT READ (never "absent"). */
export async function readPostizPosts(f: Fetch, base: string, key: string, from: Date, to: Date): Promise<{ ok: boolean; posts: Map<string, PostizPost>; error?: string }> {
  const posts = new Map<string, PostizPost>();
  let r: Response;
  try { r = await f(`${base}/posts?startDate=${encodeURIComponent(from.toISOString())}&endDate=${encodeURIComponent(to.toISOString())}`, { headers: { Authorization: key } }); }
  catch (e) { return { ok: false, posts, error: 'no answer from Postiz GET /posts: ' + String((e as Error)?.message || e) }; }
  const j = await readJson(r);
  if (!r.ok || !Array.isArray(j?.posts)) return { ok: false, posts, error: 'Postiz GET /posts: HTTP ' + r.status };
  for (const p of j.posts) {
    posts.set(String(p.id), {
      id: String(p.id), state: String(p.state || '').toUpperCase(), releaseURL: url(p.releaseURL),
      releaseId: p.releaseId && p.releaseId !== 'missing' ? String(p.releaseId) : null,
      identifier: String(p.integration?.providerIdentifier || ''), integrationId: p.integration?.id ? String(p.integration.id) : null,
      publishDate: p.publishDate ? String(p.publishDate) : null, error: typeof p.error === 'string' && p.error.trim() ? plain(p.error) : null,
    });
  }
  return { ok: true, posts };
}

/** GET /public/v1/notifications, newest first, back to `since` (at most `maxPages` pages of 100). */
export async function readPostizNotifications(f: Fetch, base: string, key: string, since: Date, maxPages = 3): Promise<{ ok: boolean; notes: Note[]; error?: string }> {
  const notes: Note[] = [];
  for (let page = 0; page < maxPages; page++) {
    let r: Response;
    try { r = await f(`${base}/notifications?page=${page}`, { headers: { Authorization: key } }); }
    catch (e) { return { ok: false, notes, error: 'no answer from Postiz GET /notifications: ' + String((e as Error)?.message || e) }; }
    const j = await readJson(r);
    if (!r.ok || !Array.isArray(j?.notifications)) return { ok: false, notes, error: 'Postiz GET /notifications: HTTP ' + r.status };
    for (const n of j.notifications) notes.push({ id: String(n.id), content: plain(n.content), link: n.link ? String(n.link) : null, createdAt: String(n.createdAt || '') });
    const oldest = j.notifications.length ? Date.parse(String(j.notifications[j.notifications.length - 1].createdAt)) : NaN;
    if (!j.hasMore || !(oldest > since.getTime())) break;
  }
  return { ok: true, notes };
}

// ── reading a notification ───────────────────────────────────────────────────────────────────────────
const SUCCESS = /^your post has been published on\b/i;
const UNCONFIRMED = /couldn'?t confirm|could not confirm/i;
const SUB_STEP = /error posting comments|posting comments on/i;
// A platform saying it changed or dropped part of what was sent. Instruction 997: resolution, frame rate,
// bitrate and audio below the month-1 floor are degradations, so they are here by name.
const DEGRADED = /thumbnail|cover image|truncat|too long|cut off|resolution|downscal|down-scal|quality|bitrate|bit rate|frame ?rate|\bfps\b|\bmono\b|audio/i;
const NEVER_SENT = /we couldn'?t post to/i;

const PROVIDER_WORDS: Record<Platform, string[]> = {
  facebook: ['facebook'], instagram: ['instagram'], linkedin: ['linkedin'], x: ['x', 'twitter'], youtube: ['youtube'], tiktok: ['tiktok'],
};
/** Does this notification's text name this channel? "on <provider>" / "to <provider>", provider as Postiz spells it. */
export function namesChannel(n: Note, ch: Platform): boolean {
  const t = n.content.toLowerCase();
  return PROVIDER_WORDS[ch].some((w) => new RegExp(`\\b(on|to) ${w}(-[a-z]+)?\\b`).test(t));
}

/**
 * The notifications that belong to one channel of one post: names the channel, created inside [from, to), and
 * does not name another post's release URL. A success note naming THIS post's release URL is always kept.
 */
export function notesFor(notes: Note[], ch: Platform, from: Date, to: Date, ownUrl: string | null, otherUrls: string[]): Note[] {
  return notes.filter((n) => {
    if (!namesChannel(n, ch)) return false;
    if (ownUrl && (n.content.includes(ownUrl) || n.link === ownUrl)) return true;
    const at = Date.parse(n.createdAt);
    if (!(at >= from.getTime() && at < to.getTime())) return false;
    return !otherUrls.some((u) => u && (n.content.includes(u) || n.link === u));
  });
}

// ── one channel ──────────────────────────────────────────────────────────────────────────────────────
export interface ChannelInput {
  channel: Platform;
  postizPostId: string | null;
  skipped: string | null;          // the reason our send left this channel out (postiz_result.skipped)
  post: PostizPost | null;         // Postiz's row for postizPostId, null when not listed
  notes: Note[];                   // notesFor(...) for this channel
  ageHours: number;                // since the post was sent
}
export interface ChannelResult {
  channel: Platform; state: ChannelState; postiz_post_id: string | null; postiz_state: string | null;
  platform_message: string | null; release_url: string | null;
}

export function classifyChannel(i: ChannelInput): ChannelResult {
  const base = { channel: i.channel, postiz_post_id: i.postizPostId, postiz_state: i.post?.state ?? null };
  const expired = i.ageHours >= RECHECK_HOURS;
  if (i.skipped) return { ...base, state: 'failed', platform_message: 'not sent: ' + i.skipped, release_url: null };
  const p = i.post;
  if (!p) {
    return expired
      ? { ...base, state: 'failed', platform_message: `Postiz has no post ${i.postizPostId ?? '(no id returned)'} for this channel ${RECHECK_HOURS} hours after it was sent`, release_url: null }
      : { ...base, state: 'pending', platform_message: null, release_url: null };
  }
  // The newest success note supersedes every problem reported BEFORE it: a post republished (or fixed) in Postiz
  // after an error must read published on the re-check, or its finding could never close. A problem reported
  // AFTER the success (a first comment or thread reply failing once the post is up) still stands.
  const success = i.notes.filter((n) => SUCCESS.test(n.content)).sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))[0];
  const since = success ? Date.parse(success.createdAt) : -Infinity;
  const problems = i.notes.filter((n) => !SUCCESS.test(n.content) && !(Date.parse(n.createdAt) < since));
  const release = p.releaseURL ?? url(success?.link) ?? url(success?.content.match(/\bat (https:\/\/\S+)/)?.[1]);
  const said = [p.error, ...problems.map((n) => n.content)].filter(Boolean).join(' | ').slice(0, 1000) || null;
  if (p.state === 'PUBLISHED') {
    return { ...base, state: said ? 'partial' : 'published', platform_message: said, release_url: release };
  }
  if (p.state === 'ERROR') {
    const text = said || '';
    const reached = !!(p.releaseURL || p.releaseId) || UNCONFIRMED.test(text) || SUB_STEP.test(text) || DEGRADED.test(text);
    const never = NEVER_SENT.test(text) && !(p.releaseURL || p.releaseId);
    return { ...base, state: reached && !never ? 'partial' : 'failed',
      platform_message: said || 'Postiz marked this post ERROR and its public API gives no reason (GET /posts does not return Post.error)', release_url: release };
  }
  // QUEUE, DRAFT or anything Postiz adds later: not finished.
  return expired
    ? { ...base, state: 'failed', platform_message: `Postiz still says ${p.state || 'nothing'} ${RECHECK_HOURS} hours after it was sent` + (said ? ': ' + said : ''), release_url: release }
    : { ...base, state: 'pending', platform_message: said, release_url: release };
}

/** The post from its channels. Same rule as fn_marketing_post_channel_record in the database. */
export function overallOutcome(states: ChannelState[]): PostOutcome {
  if (!states.length) return 'pending';
  if (states.includes('pending')) return 'pending';
  if (states.every((s) => s === 'published')) return 'published';
  if (!states.some((s) => s === 'published' || s === 'partial')) return 'failed';
  return 'partial';
}

/** "youtube (not connected in Postiz)" -> { youtube: "youtube (not connected in Postiz)" }. */
export function skippedByChannel(skipped: unknown): Partial<Record<Platform, string>> {
  const out: Partial<Record<Platform, string>> = {};
  for (const s of Array.isArray(skipped) ? skipped : []) {
    const ch = channelOf(String(s).split(/[\s(]/)[0] || '');
    if (ch && !out[ch]) out[ch] = String(s).slice(0, 300);
  }
  return out;
}

/** Postiz's post id for each channel of our post: the ids our POST got back, placed by the channel Postiz lists them on. */
export function postizIdByChannel(postizResult: any, listed: Map<string, PostizPost>): Partial<Record<Platform, string>> {
  const out: Partial<Record<Platform, string>> = {};
  const channels: Record<string, string> = postizResult?.channels && typeof postizResult.channels === 'object' ? postizResult.channels : {};
  for (const x of Array.isArray(postizResult?.postiz) ? postizResult.postiz : []) {
    const id = String(x?.postId || x?.id || ''); if (!id) continue;
    const seen = listed.get(id);
    let ch = seen ? channelOf(seen.identifier) : null;
    // Not listed yet: when the post went to one channel only, that is the channel.
    if (!ch && Object.keys(channels).length === 1) ch = channelOf(String(Object.values(channels)[0]));
    if (ch && !out[ch]) out[ch] = id;
  }
  return out;
}

// ── the it_engineer finding ──────────────────────────────────────────────────────────────────────────
export interface StoredChannel {
  post_id: number; ingest_key: string; channel: Platform; state: ChannelState; platform_message: string | null;
  release_url: string | null; postiz_post_id: string | null; postiz_state: string | null;
}
/**
 * One settle item per partial / failed channel, for fn_it_duty_settle('postiz_channel_result', items). Built from
 * EVERY stored row on every call, so the key is refiled (one finding, never two) while it stands and is absent --
 * therefore closed -- once a re-check stores the channel as published.
 */
export function findingItems(rows: StoredChannel[]) {
  return rows.filter((r) => r.state === 'partial' || r.state === 'failed').map((r) => ({
    item: `post:${r.post_id}:${r.channel}`,
    title: `${r.channel[0].toUpperCase() + r.channel.slice(1)} ${r.state === 'partial' ? 'published only partly' : 'did not publish'} for post ${r.ingest_key}: ${r.platform_message || 'no message from Postiz'}`.slice(0, 300),
    owner_seat: 'it_engineer', subject: 'postiz', blast: 'customer_facing', affected: 1,
    evidence: { post_id: r.post_id, ingest_key: r.ingest_key, channel: r.channel, state: r.state, platform_message: r.platform_message,
                release_url: r.release_url, postiz_post_id: r.postiz_post_id, postiz_state: r.postiz_state, post_owner_seat: 'marketing' },
  }));
}
