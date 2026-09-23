// PER-POST RESULTS AND THE LINK THAT BROUGHT A SUPPLIER (marketing, 23 Sep 2026; founder instruction 865).
//
// The seat read page- and account-level numbers only (marketing_insight_day). The founder asked whether each
// post did a good job, so this module reads each OUR post's results on each platform, at +1d/+3d/+7d/+28d,
// and ties Postiz's post id to the platform's own media id so a number joins back to marketing_post.
// READ-ONLY: every call is a GET except TikTok's video query (a read with a POST body). The fetch is injected; marketing_post_results.test.ts replays recorded
// Graph and Postiz answers for every metric path without a network.
//
// WHAT EACH PLATFORM CAN AND CANNOT GIVE (read from the platforms' own docs, 23 Sep 2026):
//   Instagram  /{ig-media-id}/insights (instagram_basic + instagram_manage_insights + pages_read_engagement)
//              REELS: views, reach, saved, shares, likes, comments, total_interactions; and, marked "in
//              development" by Meta, ig_reels_avg_watch_time, ig_reels_video_view_total_time, reels_skip_rate
//              (asked one at a time so a refusal costs only that metric). FEED: views, reach, saved, shares,
//              likes, comments, total_interactions, follows, profile_visits.
//              NOT AVAILABLE: plays / clips_replays_count / ig_reels_aggregated_all_plays_count (retired for
//              `views`), impressions (retired for media after 2 Jul 2024), a completion rate (no such metric),
//              link clicks on a feed post or reel (link_clicks is STORY only).
//   Facebook   /{video-id}/video_insights (read_insights + a page token with ANALYZE): Reels
//              fb_reels_total_plays, blue_reels_play_count, fb_reels_replay_count, post_impressions_unique,
//              post_video_avg_time_watched, post_video_view_time, post_video_followers; video
//              total_video_views, total_video_complete_views, total_video_avg_time_watched. completion_rate is
//              DERIVED here as total_video_complete_views / total_video_views (Meta counts a complete view at
//              97%+ of length). A post that is not a video falls back to reactions, comments and shares.
//   LinkedIn   through Postiz GET /public/v1/analytics/post/{postiz id}: the series Postiz returns, stored
//   and X      under Postiz's own label (slugged), value = the latest point. {"missing": true} means Postiz
//              has no release id yet; that is recorded as unavailable, never guessed.
//   YouTube    Postiz post analytics first. When Postiz gives nothing and app_secrets.youtube_analytics_token
//              is set (none measured 23 Sep 2026), YouTube Analytics API v2 GET /v2/reports (scope
//              yt-analytics.readonly), filters=video==<id>: views, likes, comments, shares,
//              averageViewDuration, averageViewPercentage, estimatedMinutesWatched, subscribersGained.
//              NOT AVAILABLE: a completion rate (no such metric; averageViewPercentage is the average share
//              of the video watched, stored under its own name, not as completion).
//   TikTok     Postiz post analytics first. When Postiz gives nothing and app_secrets.tiktok_access_token is
//              set (none measured 23 Sep 2026), Display API v2 POST /v2/video/query/ (a READ query that
//              takes its filter in a POST body; scope video.list): view_count, like_count, comment_count,
//              share_count. NOT AVAILABLE through it: average watch time and completion (not video fields
//              of the Display API).
//   Either with neither route: a row marked unavailable with the reason.
//   Followers  per day are already in marketing_insight_day (instagram followers, facebook page_follows,
//              linkedin via Postiz); the scorecard reads the change from there.

export type Fetch = (input: string, init?: RequestInit) => Promise<Response>;
export type Platform = 'facebook' | 'instagram' | 'linkedin' | 'x' | 'youtube' | 'tiktok';
export const CHECKPOINTS = { '1d': 1, '3d': 3, '7d': 7, '28d': 28 } as const;
export type Checkpoint = keyof typeof CHECKPOINTS;

async function readJson(r: Response): Promise<any> {
  const t = await r.text();
  try { return JSON.parse(t); } catch { return { raw: t.slice(0, 200) }; }
}
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

/** Postiz's provider identifier to our channel ('instagram-standalone' -> instagram, 'twitter' -> x). */
export function channelOf(identifier: string): Platform | null {
  const head = identifier.toLowerCase().split('-')[0];
  if (head === 'twitter' || head === 'x') return 'x';
  return (['facebook', 'instagram', 'linkedin', 'youtube', 'tiktok'] as const).find((c) => c === head) ?? null;
}

// (UTM tagging of the links we publish lives in scripts/marketing/utm.mjs and runs at calendar LOAD time.)

// ── the tie: Postiz post id -> platform media id ──────────────────────────────────────────────────────
export interface Release { postiz_post_id: string; platform: Platform; platform_post_id: string | null; permalink: string | null }

/** Postiz's posts in a window: each post's channel, its release id (the platform's own id) and its URL. */
export async function postizReleases(f: Fetch, base: string, key: string, from: Date, to: Date): Promise<Release[]> {
  const r = await f(`${base}/posts?startDate=${encodeURIComponent(from.toISOString())}&endDate=${encodeURIComponent(to.toISOString())}`, { headers: { Authorization: key } });
  const j = await readJson(r);
  const out: Release[] = [];
  for (const p of Array.isArray(j?.posts) ? j.posts : []) {
    const platform = channelOf(String(p.integration?.providerIdentifier || ''));
    if (!platform) continue;
    const rid = p.releaseId && p.releaseId !== 'missing' ? String(p.releaseId) : null;
    out.push({ postiz_post_id: String(p.id), platform, platform_post_id: rid, permalink: p.releaseURL ? String(p.releaseURL) : null });
  }
  return out;
}

/** The Postiz ids our publish call got back (marketing_post.postiz_result.postiz: [{postId, integration}]). */
export function postizIdsOf(postizResult: any): string[] {
  const arr = Array.isArray(postizResult?.postiz) ? postizResult.postiz : [];
  return arr.map((x: any) => String(x?.postId || x?.id || '')).filter(Boolean);
}

// ── Graph ─────────────────────────────────────────────────────────────────────────────────────────────
export interface GraphEnv { graph: string; token: string }
async function g(f: Fetch, env: GraphEnv, path: string, token = env.token) {
  const r = await f(env.graph + path + (path.includes('?') ? '&' : '?') + 'access_token=' + encodeURIComponent(token));
  const body = await readJson(r);
  return { ok: r.ok && !body?.error, status: r.status, body, err: body?.error ? String(body.error.message || 'graph error').slice(0, 160) : (r.ok ? null : 'HTTP ' + r.status) };
}
/** A Graph insights answer as {metric: number}; non-numeric values (breakdown objects) are skipped. */
function numbers(body: any): Record<string, number> {
  const out: Record<string, number> = {};
  for (const m of Array.isArray(body?.data) ? body.data : []) {
    const v = m?.total_value?.value ?? m?.values?.[0]?.value;
    const name = slug(String(m.name || '')); if (name && typeof v === 'number' && Number.isFinite(v)) out[name] = v;
  }
  return out;
}

/** An Instagram media id from its permalink, when Postiz gave a URL but no release id. */
export async function igMediaIdByPermalink(f: Fetch, env: GraphEnv, igUserId: string, permalink: string): Promise<string | null> {
  const r = await g(f, env, `/${igUserId}/media?fields=id,permalink&limit=50`);
  const norm = (u: string) => u.replace(/\/+$/, '').toLowerCase();
  const hit = (Array.isArray(r.body?.data) ? r.body.data : []).find((m: any) => m.permalink && norm(String(m.permalink)) === norm(permalink));
  return hit ? String(hit.id) : null;
}

export const IG_REELS = ['views', 'reach', 'saved', 'shares', 'likes', 'comments', 'total_interactions'];
export const IG_REELS_IN_DEVELOPMENT = ['ig_reels_avg_watch_time', 'ig_reels_video_view_total_time', 'reels_skip_rate'];
export const IG_FEED = ['views', 'reach', 'saved', 'shares', 'likes', 'comments', 'total_interactions', 'follows', 'profile_visits'];
export const FB_REELS = ['fb_reels_total_plays', 'blue_reels_play_count', 'fb_reels_replay_count', 'post_impressions_unique', 'post_video_avg_time_watched', 'post_video_view_time', 'post_video_followers'];
export const FB_VIDEO = ['total_video_views', 'total_video_complete_views', 'total_video_avg_time_watched'];

/**
 * retry: the platform answered 5xx or 429 — a blip, not an answer. The duty writes nothing, so the checkpoint
 * stays open and is read again on a later beat inside its window.
 */
export interface MetricsResult { values: Record<string, number>; unavailable: Record<string, string>; retry?: boolean }
export const transient = (status: number) => status === 429 || status >= 500;

export async function instagramMedia(f: Fetch, env: GraphEnv, mediaId: string): Promise<MetricsResult> {
  const values: Record<string, number> = {}; const unavailable: Record<string, string> = {};
  const kind = await g(f, env, `/${mediaId}?fields=media_product_type,media_type`);
  if (!kind.ok) return { values, unavailable: { '*': 'media unreadable: ' + kind.err }, retry: transient(kind.status) };
  const reels = String(kind.body.media_product_type || '').toUpperCase() === 'REELS';
  const core = reels ? IG_REELS : IG_FEED;
  const r = await g(f, env, `/${mediaId}/insights?metric=${core.join(',')}`);
  if (!r.ok && transient(r.status)) return { values: {}, unavailable: { '*': 'instagram insights: ' + r.err }, retry: true };
  if (r.ok) Object.assign(values, numbers(r.body)); else for (const m of core) unavailable[m] = r.err!;
  if (reels) {
    for (const m of IG_REELS_IN_DEVELOPMENT) {
      const x = await g(f, env, `/${mediaId}/insights?metric=${m}`);
      const v = numbers(x.body)[m];
      if (x.ok && v !== undefined) values[m] = v; else unavailable[m] = x.err || 'no value returned';
    }
  }
  unavailable.completion_rate = 'Instagram has no completion metric';
  return { values, unavailable };
}

export async function facebookPost(f: Fetch, env: GraphEnv, id: string, pageToken: string): Promise<MetricsResult> {
  const values: Record<string, number> = {}; const unavailable: Record<string, string> = {};
  const reels = await g(f, env, `/${id}/video_insights?metric=${FB_REELS.join(',')}`, pageToken);
  const video = await g(f, env, `/${id}/video_insights?metric=${FB_VIDEO.join(',')}`, pageToken);
  if (transient(reels.status) || transient(video.status)) return { values: {}, unavailable: { '*': 'facebook video insights: ' + (reels.err || video.err) }, retry: true };
  if (reels.ok) Object.assign(values, numbers(reels.body));
  if (video.ok) Object.assign(values, numbers(video.body));
  if (values.total_video_views > 0 && values.total_video_complete_views !== undefined) {
    values.completion_rate = Math.round((values.total_video_complete_views / values.total_video_views) * 10000) / 10000;
  }
  if (!reels.ok && !video.ok) {
    // not a video: the counters every post has
    const p = await g(f, env, `/${id}?fields=shares,reactions.summary(true).limit(0),comments.summary(true).limit(0)`, pageToken);
    if (!p.ok) return { values, unavailable: { '*': 'post unreadable: ' + p.err }, retry: transient(p.status) };
    values.reactions = Number(p.body.reactions?.summary?.total_count) || 0;
    values.comments = Number(p.body.comments?.summary?.total_count) || 0;
    values.shares = Number(p.body.shares?.count) || 0;
    unavailable.video = 'not a video: ' + (video.err || reels.err);
  }
  return { values, unavailable };
}

/** LinkedIn and X: Postiz's own per-post analytics. */
export async function viaPostiz(f: Fetch, base: string, key: string, postizPostId: string, days: number): Promise<MetricsResult> {
  const r = await f(`${base}/analytics/post/${encodeURIComponent(postizPostId)}?date=${days}`, { headers: { Authorization: key } });
  const j = await readJson(r);
  if (j?.missing === true) return { values: {}, unavailable: { '*': 'Postiz has no release id for this post yet (posts:missing / posts:connect)' } };
  if (!r.ok || !Array.isArray(j)) return { values: {}, unavailable: { '*': 'postiz post analytics: HTTP ' + r.status }, retry: transient(r.status) };
  const values: Record<string, number> = {}; const unavailable: Record<string, string> = {};
  for (const [i, s] of j.entries()) {
    const pts = Array.isArray(s?.data) ? s.data : [];
    const last = pts[pts.length - 1];
    const name = slug(String(s.label || ''));
    // a label with no latin letters (e.g. an Arabic label) has no metric name: say so, never write an empty name
    if (!name) { unavailable['unnamed_' + (i + 1)] = 'Postiz label has no latin name: ' + String(s.label || '(none)').slice(0, 60); continue; }
    if (last && Number.isFinite(Number(last.total))) values[name] = Number(last.total);
  }
  return { values, unavailable };
}

// ── YouTube and TikTok, directly (only when Postiz gave nothing and a token exists) ───────────────────
export const YT_METRICS = ['views', 'likes', 'comments', 'shares', 'averageViewDuration', 'averageViewPercentage', 'estimatedMinutesWatched', 'subscribersGained'];

/** YouTube Analytics API v2, one video, published day .. today. */
export async function youtubeVideo(f: Fetch, token: string, videoId: string, publishedDay: string, today: string): Promise<MetricsResult> {
  const url = `https://youtubeanalytics.googleapis.com/v2/reports?ids=channel%3D%3DMINE&startDate=${publishedDay}&endDate=${today}`
    + `&metrics=${YT_METRICS.join(',')}&filters=video%3D%3D${encodeURIComponent(videoId)}`;
  const r = await f(url, { headers: { Authorization: 'Bearer ' + token } });
  const j = await readJson(r);
  const unavailable: Record<string, string> = { completion_rate: 'YouTube Analytics has no completion metric (averageViewPercentage is stored under its own name)' };
  if (!r.ok || j?.error) return { values: {}, unavailable: { ...unavailable, '*': 'youtube analytics: ' + String(j?.error?.message || 'HTTP ' + r.status).slice(0, 160) }, retry: transient(r.status) };
  const cols: string[] = (j.columnHeaders || []).map((c: any) => String(c.name));
  const row: unknown[] = Array.isArray(j.rows) && j.rows[0] ? j.rows[0] : [];
  const values: Record<string, number> = {};
  cols.forEach((c, i) => { const v = Number(row[i]); if (row[i] != null && Number.isFinite(v)) values[slug(c.replace(/([A-Z])/g, '_$1'))] = v; });
  return { values, unavailable };
}

/** TikTok Display API v2 video query: a READ that takes its filter in a POST body (scope video.list). */
export async function tiktokVideo(f: Fetch, token: string, videoId: string): Promise<MetricsResult> {
  const unavailable: Record<string, string> = { avg_watch_time: 'not a Display API video field', completion_rate: 'not a Display API video field' };
  const r = await f('https://open.tiktokapis.com/v2/video/query/?fields=id,view_count,like_count,comment_count,share_count', {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify({ filters: { video_ids: [videoId] } }),
  });
  const j = await readJson(r);
  const v = j?.data?.videos?.[0];
  if (!r.ok || (j?.error?.code && j.error.code !== 'ok') || !v) {
    return { values: {}, unavailable: { ...unavailable, '*': 'tiktok video query: ' + String(j?.error?.message || (v ? 'HTTP ' + r.status : 'video not found')).slice(0, 160) }, retry: transient(r.status) };
  }
  const values: Record<string, number> = {};
  for (const k of ['view_count', 'like_count', 'comment_count', 'share_count']) if (Number.isFinite(Number(v[k]))) values[k] = Number(v[k]);
  return { values, unavailable };
}
