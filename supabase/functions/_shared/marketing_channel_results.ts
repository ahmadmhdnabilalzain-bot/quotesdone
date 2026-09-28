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
//              top-level posts (parentPostId null), EVERY source (ours and ones made in Postiz's own UI).
//              state is one of QUEUE | PUBLISHED | ERROR | DRAFT.
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
//   ASSUMED    A notification carries no post id. A success note names its release URL and is matched to the
//              post with EXACTLY that URL. A note without a URL is credited to the Postiz post on the channel its
//              prefix names ("... posting on <provider>", never any other word in the text) with the latest
//              publishDate at or before the note, at most 6 hours before it. Two posts on that channel inside
//              those 6 hours make the note AMBIGUOUS (only posts whose Postiz state can carry the note count: an
//              error / unconfirmed / not-posted note only a post in ERROR, a comment-step note any post): it is kept as a message but never downgrades a PUBLISHED
//              post and never files a finding (review of #965: month-1 calendars put same-channel posts a day
//              apart). The platform's own words reach us only through "An error occurred ... : <message>".
//
// THE RULE (the founder's words, instruction on per-channel results, 24 Sep 2026):
//   channel  published  Postiz says PUBLISHED and nothing credited to that post is a problem.
//            partial    it reached the platform but a sub-step failed or degraded: Postiz says PUBLISHED and an
//                       unambiguous note reported a comment/thread step failing, or says ERROR with evidence it
//                       got there (a release id/URL, "couldn't confirm", a comment/thread step, or a thumbnail /
//                       caption / resolution / quality / frame-rate / audio complaint). Instruction 997's floor is 1080x1920, 60 fps,
//                       ~0.8 Mbps, mono: a platform saying it lowered any of that is partial, never published.
//            failed     never published: skipped at send (not connected, wrong media), Postiz says ERROR with
//                       nothing showing it reached the platform, or still not published 48 hours after sending.
//            pending    Postiz has not finished (QUEUE / DRAFT / not listed yet) inside the 48 hours.
//            Postiz's own state is authoritative: notes only choose between partial and failed on ERROR, and
//            between published and partial on PUBLISHED.
//   post     published only if every channel is published; failed if none is published or partial; partial
//            otherwise; pending while any channel is pending. (The database applies the same rule when it
//            stores the rows: fn_marketing_post_channel_record.)
// FINDINGS are keyed by CHANNEL + CAUSE, duty:postiz_channel_result:<channel>:<cause> (review of #965): one
// ongoing cause -- an unverified YouTube account refusing every thumbnail -- is one finding listing the posts it
// hit, not a finding and a handoff per post. The per-post state stays in marketing_post_channel_result.
//
// Deterministic string rules; no model. READ-ONLY toward Postiz: two GETs, no write. Tested offline in
// marketing_channel_results.test.ts against the recorded shapes above.
import { channelOf, type Fetch, type Platform } from './marketing_post_results.ts';

export type ChannelState = 'pending' | 'published' | 'partial' | 'failed';
export type PostOutcome = ChannelState;
export const RECHECK_HOURS = 48;
/** A URL-less note is credited to a post sent at most this long before it. */
export const NOTE_REACH_HOURS = 6;

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

/**
 * The SQL this reads is not applied yet (the function or table does not exist): PostgREST PGRST202 (no such
 * routine) / PGRST205 (no such table), Postgres 42883 (undefined function) / 42P01 (undefined table). Before the
 * pending file is applied the beat answers {ok:true, skipped:'sql pending'} instead of failing every 15 minutes
 * and filing duty:heartbeat:marketingChannels (review of #965).
 */
export function sqlPending(error: { code?: string | null } | null | undefined): boolean {
  return !!error && ['PGRST202', 'PGRST205', '42883', '42P01'].includes(String(error.code || ''));
}

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

/**
 * GET /public/v1/notifications, newest first, back to `since` (at most `maxPages` pages of 100).
 * truncated: Postiz has more AND the oldest note read is still newer than `since` -- notes older than
 * `oldestRead` were not seen, so a post sent before it must not be re-classified (a missing complaint would read
 * as "published" and close a real finding).
 */
export async function readPostizNotifications(f: Fetch, base: string, key: string, since: Date, maxPages = 3):
    Promise<{ ok: boolean; notes: Note[]; truncated: boolean; oldestRead: Date | null; error?: string }> {
  const notes: Note[] = [];
  let truncated = false;
  for (let page = 0; page < maxPages; page++) {
    let r: Response;
    try { r = await f(`${base}/notifications?page=${page}`, { headers: { Authorization: key } }); }
    catch (e) { return { ok: false, notes, truncated, oldestRead: null, error: 'no answer from Postiz GET /notifications: ' + String((e as Error)?.message || e) }; }
    const j = await readJson(r);
    if (!r.ok || !Array.isArray(j?.notifications)) return { ok: false, notes, truncated, oldestRead: null, error: 'Postiz GET /notifications: HTTP ' + r.status };
    for (const n of j.notifications) notes.push({ id: String(n.id), content: plain(n.content), link: n.link ? String(n.link) : null, createdAt: String(n.createdAt || '') });
    const oldest = j.notifications.length ? Date.parse(String(j.notifications[j.notifications.length - 1].createdAt)) : NaN;
    const coversSince = !(oldest > since.getTime());
    if (!j.hasMore || coversSince) break;
    if (page === maxPages - 1) truncated = true;
  }
  const times = notes.map((n) => Date.parse(n.createdAt)).filter((t) => Number.isFinite(t));
  return { ok: true, notes, truncated, oldestRead: times.length ? new Date(Math.min(...times)) : null };
}

// ── reading a notification ───────────────────────────────────────────────────────────────────────────
const SUCCESS = /^your post has been published on\b/i;
const UNCONFIRMED = /couldn'?t confirm|could not confirm/i;
const SUB_STEP = /error posting comments|posting comments on/i;
// A platform saying it changed or dropped part of what was sent. Instruction 997: resolution, frame rate,
// bitrate and audio below the month-1 floor are degradations, so they are here by name.
const DEGRADED = /thumbnail|cover image|truncat|too long|cut off|resolution|downscal|down-scal|quality|bitrate|bit rate|frame ?rate|\bfps\b|\bmono\b|audio/i;
const NEVER_SENT = /we couldn'?t post to/i;
// The one place a note names its channel: the workflow's own prefix. Any other word in the text (a caption that
// mentions "instagram", an error naming "facebook login") names nothing.
const PREFIX = /^(?:an error occurred while posting on|error posting (?:comments )?on|your post has been published on|your post was sent to|we couldn'?t confirm your post on|we couldn'?t post to)\s+([a-z][a-z0-9-]*)/i;

/** The channel a note is about, from its prefix only. */
export function noteChannel(n: Note): Platform | null {
  const m = n.content.match(PREFIX);
  return m ? channelOf(m[1]) : null;
}
/** The URL a note names, exactly: its link, or the release URL a success note ends with ("... at <url>"). */
export function noteUrl(n: Note): string | null {
  return url(n.link) ?? url(n.content.match(/\bat (https:\/\/\S+)/)?.[1]?.replace(/[.,;)]+$/, ''));
}

/**
 * Credits every note to the Postiz post it is about, over ALL of Postiz's posts (ours and ones made in Postiz's
 * own UI), never only ours:
 *   * a note naming a URL -> the post whose releaseURL is EXACTLY that URL (none: it is about nobody we list);
 *   * a URL-less note -> the post on the note's channel with the latest publishDate at or before the note, at
 *     most NOTE_REACH_HOURS before it, among the posts whose Postiz state can carry that note (below); two or
 *     more such posts in that span -> ambiguous, credited as such to each of them.
 */
export function attributeNotes(notes: Note[], posts: Iterable<PostizPost>): { mine: Map<string, Note[]>; ambiguous: Map<string, Note[]> } {
  const mine = new Map<string, Note[]>(); const ambiguous = new Map<string, Note[]>();
  const add = (m: Map<string, Note[]>, id: string, n: Note) => m.set(id, [...(m.get(id) || []), n]);
  const all = [...posts];
  for (const n of notes) {
    const ch = noteChannel(n);
    if (!ch) continue;
    const u = noteUrl(n);
    if (u) {
      const hit = all.find((p) => p.releaseURL === u && channelOf(p.identifier) === ch);
      if (hit) add(mine, hit.id, n);
      continue;
    }
    const at = Date.parse(n.createdAt);
    if (!Number.isFinite(at)) continue;
    // Postiz's state is authoritative. Its workflow sends "An error occurred while posting", "couldn't confirm"
    // and "We couldn't post to" only together with changeState(ERROR), so such a note is only ever credited to a
    // post Postiz holds in ERROR; only a comment/thread-step failure ("Error posting comments on") can belong to
    // a post that is PUBLISHED.
    const eligible = (p: PostizPost) => SUB_STEP.test(n.content) || p.state === 'ERROR';
    const span = all.filter((p) => channelOf(p.identifier) === ch && p.publishDate && eligible(p))
      .map((p) => ({ p, t: Date.parse(p.publishDate!) }))
      .filter((x) => x.t <= at && at - x.t <= NOTE_REACH_HOURS * 3600_000)
      .sort((a, b) => b.t - a.t);
    if (span.length === 1) add(mine, span[0].p.id, n);
    else for (const x of span) add(ambiguous, x.p.id, n);
  }
  return { mine, ambiguous };
}

// ── one channel ──────────────────────────────────────────────────────────────────────────────────────
export interface ChannelInput {
  channel: Platform;
  postizPostId: string | null;
  skipped: string | null;          // the reason our send left this channel out (postiz_result.skipped)
  post: PostizPost | null;         // Postiz's row for postizPostId, null when not listed
  notes: Note[];                   // attributeNotes(...).mine for this post
  ambiguous?: Note[];              // attributeNotes(...).ambiguous for this post: a message, never a verdict
  ageHours: number;                // since the post was sent
}
export interface ChannelResult {
  channel: Platform; state: ChannelState; cause: string | null; postiz_post_id: string | null; postiz_state: string | null;
  platform_message: string | null; release_url: string | null;
}

/** The cause class of a partial / failed channel: the second half of its finding key. */
export function causeOf(state: ChannelState, message: string | null, skipped: boolean): string | null {
  if (state !== 'partial' && state !== 'failed') return null;
  const t = (message || '').toLowerCase();
  if (skipped) return /not connected/.test(t) ? 'not_connected' : 'not_sent';
  if (/thumbnail|cover image/.test(t)) return 'thumbnail_not_set';
  if (/resolution|downscal|down-scal|quality|bitrate|bit rate|frame ?rate|\bfps\b|\bmono\b|audio/.test(t)) return 'quality_degraded';
  if (/truncat|too long|cut off/.test(t)) return 'caption_truncated';
  if (UNCONFIRMED.test(t)) return 'unconfirmed';
  if (SUB_STEP.test(t)) return 'comment_failed';
  if (NEVER_SENT.test(t)) return 'channel_disconnected';
  if (/hours after it was sent/.test(t)) return 'never_published';
  return 'error';
}

export function classifyChannel(i: ChannelInput): ChannelResult {
  const { basis, ...r } = decide(i);
  // The cause comes from what DECIDED the state, never from an ambiguous note kept alongside it.
  return { ...r, cause: causeOf(r.state, basis ?? r.platform_message, !!i.skipped) };
}

function decide(i: ChannelInput): Omit<ChannelResult, 'cause'> & { basis?: string | null } {
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
  const unsure = (i.ambiguous || []).filter((n) => !SUCCESS.test(n.content) && !(Date.parse(n.createdAt) < since));
  const release = p.releaseURL ?? noteUrl(success ?? { id: '', content: '', link: null, createdAt: '' });
  const said = [p.error, ...problems.map((n) => n.content)].filter(Boolean).join(' | ').slice(0, 900) || null;
  const maybe = unsure.length ? ('ambiguous (two posts on this channel were sent within ' + NOTE_REACH_HOURS + 'h of it): ' + unsure.map((n) => n.content).join(' | ')).slice(0, 900) : null;
  const both = [said, maybe].filter(Boolean).join(' | ').slice(0, 1000) || null;
  if (p.state === 'PUBLISHED') {
    // an ambiguous note is kept as a message and NEVER downgrades a post Postiz says is published
    return { ...base, state: said ? 'partial' : 'published', basis: said, platform_message: both, release_url: release };
  }
  if (p.state === 'ERROR') {
    const text = said || '';
    const reached = !!(p.releaseURL || p.releaseId) || UNCONFIRMED.test(text) || SUB_STEP.test(text) || DEGRADED.test(text);
    const never = NEVER_SENT.test(text) && !(p.releaseURL || p.releaseId);
    return { ...base, state: reached && !never ? 'partial' : 'failed', basis: said ?? '',
      platform_message: both || 'Postiz marked this post ERROR and its public API gives no reason (GET /posts does not return Post.error)', release_url: release };
  }
  // QUEUE, DRAFT or anything Postiz adds later: not finished.
  return expired
    ? { ...base, state: 'failed', basis: 'hours after it was sent', platform_message: (`Postiz still says ${p.state || 'nothing'} ${RECHECK_HOURS} hours after it was sent` + (both ? ': ' + both : '')).slice(0, 1000), release_url: release }
    : { ...base, state: 'pending', platform_message: both, release_url: release };
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
  post_id: number; ingest_key: string; channel: Platform; state: ChannelState; cause: string | null; platform_message: string | null;
  release_url: string | null; postiz_post_id: string | null; postiz_state: string | null; checked_at?: string | null;
}
/**
 * One settle item per CHANNEL + CAUSE over every stored partial / failed row inside the re-check window, for
 * fn_it_duty_settle('postiz_channel_result', items). The key is refiled (one finding, never two) while any post
 * still has that cause on that channel and is absent -- therefore closed -- once none does. owner_seat is
 * marketing: it owns the posts and has the handoff kind fn_it_loop_open routes by; the finding is the
 * it_engineer's (it_engineer_finding, it_playbook class postiz_channel_result).
 */
export function findingItems(rows: StoredChannel[]) {
  const groups = new Map<string, StoredChannel[]>();
  for (const r of rows) {
    if (r.state !== 'partial' && r.state !== 'failed') continue;
    const k = `${r.channel}:${r.cause || 'error'}`;
    groups.set(k, [...(groups.get(k) || []), r]);
  }
  return [...groups.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([item, rs]) => {
    rs.sort((a, b) => a.post_id - b.post_id);
    const latest = [...rs].sort((a, b) => String(b.checked_at || '').localeCompare(String(a.checked_at || '')) || b.post_id - a.post_id)[0];
    const [ch, cause] = item.split(':');
    return {
      item,
      title: `${ch[0].toUpperCase() + ch.slice(1)} ${cause.replace(/_/g, ' ')} on ${rs.length} post(s) (${rs.map((r) => r.ingest_key).join(', ')}): ${latest.platform_message || 'no message from Postiz'}`.slice(0, 300),
      owner_seat: 'marketing', subject: 'postiz', blast: 'customer_facing', affected: rs.length,
      evidence: { channel: ch, cause, post_ids: rs.map((r) => r.post_id), ingest_keys: rs.map((r) => r.ingest_key),
                  states: Object.fromEntries(rs.map((r) => [r.post_id, r.state])), platform_message: latest.platform_message,
                  release_urls: rs.map((r) => r.release_url).filter(Boolean), postiz_post_ids: rs.map((r) => r.postiz_post_id).filter(Boolean) },
    };
  });
}
