// THE MARKETING SEAT'S CALLS TO POSTIZ AND META (marketing, 22 Sep 2026).
//
// Every HTTP call the seat makes lives here, with the fetch INJECTED, so the tests replay Postiz and
// Graph without a network (marketing_channels.test.ts). The edge function (marketing_channels/index.ts)
// only reads the database, calls these, and writes what they return.
//
// THREE PROPERTIES THE TESTS HOLD, because each one is a way this seat could hurt the company:
//   1. publishPost never POSTs to Postiz unless `live` is true -- and the caller passes live only when
//      the emergency stop app_secrets.marketing_publishing_enabled is not 'false', the post is not a ZZ DEMO post (flag OR text), and the
//      database's publish gate (fn_marketing_post_refusal: the founder's approval of the month) says yes.
//      Switched off, it returns the payload it WOULD have sent, which is the dry run the founder can read.
//   2. Nothing an access token can hide in is returned. Graph puts the token into every paging.next URL
//      (measured 22 Sep 2026), so paging is never kept and every value passes through stripTokens.
//   3. readAdSpend reports the business the account sits in, on the same read, so the database can
//      refuse spend from an account that is not the company's (fn_marketing_ad_spend_record).
//
// Nothing here writes to Meta. Reads only: /me, /debug_token, /me/accounts, page and Instagram insights,
// ad account insights. The only writes are to Postiz: publishPost with live=true (upload, post) and
// deletePostizPost (a cancel). 23 Sep 2026: posts are built from marketing_post_variant, one per platform.

export type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

// YouTube is connected in Postiz (measured 22 Sep 2026); TikTok was connected on 23 Sep 2026 (founder).
export const CHANNELS = ['facebook', 'instagram', 'linkedin', 'x', 'youtube', 'tiktok'] as const;
export type Channel = typeof CHANNELS[number];

// ── shared helpers ────────────────────────────────────────────────────────────────────────────────
const TOKEN_KEYS = new Set(['access_token', 'accesstoken', 'token', 'refresh_token', 'appsecret_proof']);

/** Removes every token-bearing value: keys named like a token, any URL carrying access_token=, and paging. */
export function stripTokens<T>(v: T): T {
  if (Array.isArray(v)) return v.map((x) => stripTokens(x)) as unknown as T;
  if (v && typeof v === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
      if (TOKEN_KEYS.has(k.toLowerCase()) || k === 'paging') continue;
      out[k] = stripTokens(x);
    }
    return out as T;
  }
  if (typeof v === 'string' && /access_token=/i.test(v)) return '[url with a token removed]' as unknown as T;
  return v;
}

async function readJson(r: Response): Promise<any> {
  const t = await r.text();
  try { return JSON.parse(t); } catch { return { raw: t.slice(0, 300) }; }
}

/** ZZ DEMO in any of the texts: the second direction of the demo rule (the database holds the same one). */
export function isDemoText(...texts: Array<string | null | undefined>): boolean {
  return /zz[ _-]?demo/i.test(texts.filter(Boolean).join(' '));
}

// ── Postiz ────────────────────────────────────────────────────────────────────────────────────────
export interface PostizIntegration { id: string; identifier: string; name?: string; disabled?: boolean; refreshNeeded?: boolean; inBetweenSteps?: boolean }

export async function postizIntegrations(f: Fetch, base: string, key: string): Promise<{ status: number; list: PostizIntegration[]; error?: string }> {
  const r = await f(base + '/integrations', { headers: { Authorization: key } });
  const j = await readJson(r);
  if (!r.ok || !Array.isArray(j)) return { status: r.status, list: [], error: String(j?.message || j?.error || j?.raw || 'not a list') };
  return { status: r.status, list: j.map((x: any) => ({ id: String(x.id), identifier: String(x.identifier || ''), name: x.name, disabled: !!x.disabled, refreshNeeded: !!x.refreshNeeded, inBetweenSteps: !!x.inBetweenSteps })) };
}

/** The Postiz channel that serves one of our channels ('instagram-standalone' serves instagram, 'linkedin-page' linkedin). */
export function integrationFor(list: PostizIntegration[], ch: Channel): PostizIntegration | undefined {
  return list.filter((x) => !x.disabled && !x.refreshNeeded && !x.inBetweenSteps).find((x) => servesChannel(x, ch));
}
const servesChannel = (x: PostizIntegration, ch: Channel) =>
  ch === 'x' ? (x.identifier === 'x' || x.identifier === 'twitter') : (x.identifier === ch || x.identifier.startsWith(ch + '-'));

// ── THE IT ENGINEER'S INTEGRATION WATCH (it_engineer, 24 Sep 2026, founder instruction 979) ──────────
// "The IT engineer should have been notified when Facebook disconnected from Postiz, and about any similar
// issue." Measured before this: marketing_connection_check held postiz.channel.<ch> once a Dubai day and no
// routine read it into a finding, so a dead channel was silent until a post skipped it. These build the items
// fn_it_integration_settle files (duty:integration_social:<item>) every beat. Pure: tested offline.
export const POSTIZ_RECONNECT_URL = 'https://platform.postiz.com/launches';
export type ChannelState = 'ok' | 'missing' | 'disabled' | 'refresh_needed' | 'in_between_steps';
/** What Postiz says about one of our channels: ok when a live integration serves it, else the flag it carries. */
export function channelState(list: PostizIntegration[], ch: Channel): { state: ChannelState; integration?: PostizIntegration } {
  const live = integrationFor(list, ch);
  if (live) return { state: 'ok', integration: live };
  const dead = list.filter((x) => servesChannel(x, ch));
  const r = dead.find((x) => x.refreshNeeded), b = dead.find((x) => x.inBetweenSteps), d = dead.find((x) => x.disabled);
  if (r) return { state: 'refresh_needed', integration: r };
  if (b) return { state: 'in_between_steps', integration: b };
  if (d) return { state: 'disabled', integration: d };
  return { state: 'missing' };
}
const SAY: Record<Exclude<ChannelState, 'ok'>, string> = {
  refresh_needed: 'is disconnected in Postiz (its login expired: refreshNeeded)',
  in_between_steps: 'is half-connected in Postiz (the connection was started and never finished: inBetweenSteps)',
  disabled: 'is disabled in Postiz',
  missing: 'is not connected in Postiz at all',
};
export interface IntegrationItem {
  item: string; title: string; owner_seat: string; subject: string; blast: string; affected: number;
  evidence: Record<string, unknown>; carried?: boolean;
}
export type YoutubeAuth = { state: 'ok' | 'not_connected' | 'refresh_failed' | 'unknown'; error?: string };
/** One item per dead channel. When Postiz cannot be read: one item for the API and every channel CARRIED (held as
 *  it stood, never closed on a reading nobody took). YouTube's own OAuth token (comment replies) is its own item. */
export function socialIntegrationItems(ints: { status: number; list: PostizIntegration[]; error?: string } | null, youtube: YoutubeAuth): IntegrationItem[] {
  const out: IntegrationItem[] = [];
  const base = { owner_seat: 'marketing', subject: 'postiz', blast: 'customer_facing', affected: 1 };
  if (!ints || ints.error) {
    out.push({ ...base, item: 'postiz:api',
      title: `Postiz refused the company's API key (HTTP ${ints?.status ?? 'none'}), so no channel can be published or checked. Reconnect: a new Public API key at ${POSTIZ_RECONNECT_URL} (Settings > Public API)`,
      evidence: { http_status: ints?.status ?? null, error: ints?.error ?? 'no key stored', reauth: true, reconnect_url: POSTIZ_RECONNECT_URL } });
    for (const ch of CHANNELS) out.push({ ...base, item: 'postiz:' + ch, title: 'not measured this beat', evidence: {}, carried: true });
  } else {
    for (const ch of CHANNELS) {
      const s = channelState(ints.list, ch);
      if (s.state === 'ok') continue;
      out.push({ ...base, item: 'postiz:' + ch,
        title: `${ch[0].toUpperCase() + ch.slice(1)} ${SAY[s.state]}; its scheduled posts are paused until it is reconnected. Reconnect: ${POSTIZ_RECONNECT_URL}`,
        evidence: { channel: ch, state: s.state, identifier: s.integration?.identifier ?? null, integration_id: s.integration?.id ?? null,
                    name: s.integration?.name ?? null, reauth: true, reconnect_url: POSTIZ_RECONNECT_URL, pauses_channel: ch,
                    action: `open Postiz, find the ${ch} channel${s.integration?.name ? ' (' + s.integration.name + ')' : ''} and ${s.state === 'missing' ? 'add it' : 'click Reconnect'}` } });
    }
  }
  const yt = { owner_seat: 'marketing', subject: 'youtube_oauth', blast: 'agent_facing', affected: 1, item: 'youtube:oauth' };
  if (youtube.state === 'not_connected' || youtube.state === 'refresh_failed') {
    out.push({ ...yt,
      title: youtube.state === 'refresh_failed'
        ? `YouTube's sign-in for comment replies was refused on refresh (${(youtube.error || '').slice(0, 120)}). Reconnect with the one-time link in this message`
        : 'YouTube is not signed in for comment replies. Reconnect with the one-time link in this message',
      evidence: { state: youtube.state, error: youtube.error ?? null, reauth: true, reconnect_link: 'youtube' } });
  } else if (youtube.state === 'unknown') {
    out.push({ ...yt, title: 'not measured this beat', evidence: {}, carried: true });
  }
  return out;
}

/** One platform post as marketing_post_variant stores it; `body` is the exact text (caption + hashtags). */
export interface Variant {
  platform: Channel; seq: number; post_type: 'reel' | 'short' | 'post' | 'video'; body: string; hashtags: string[];
  title: string | null; alt_text: string | null; first_comment: string | null;
}
export interface Media { name: string; type: string; bytes: Uint8Array }
export interface PublishInput { id: number; ingest_key: string; is_demo: boolean; variants: Variant[]; media: Media[]; cover: Media | null }
type Uploaded = { id: string; path: string };

/**
 * Postiz's per-provider settings block (`__type` is the integration identifier; the shapes are the ones the
 * Postiz agent skill documents for the public API, read 23 Sep 2026). What is not a setting Postiz knows is
 * silently discarded by Postiz, so only documented keys are sent.
 *   instagram*: post_type 'post' -- Postiz publishes a VIDEO sent as 'post' as a Reel and an image as a feed
 *               post; 'story' is never used. So reel vs post is decided by the media, and checked below.
 *   youtube:    title (required), type 'public', tags from the hashtags, thumbnail = the key frame when uploaded.
 *   x:          who_can_reply_post 'everyone'.   linkedin-page: no carousel.   facebook: none needed.
 *   tiktok:     content_posting_method 'DIRECT_POST' (the skill's Rule 3), public, no auto-music, not branded.
 */
export function settingsFor(identifier: string, v: Variant, thumb: Uploaded | null): Record<string, unknown> {
  const s: Record<string, unknown> = { __type: identifier };
  if (identifier.startsWith('instagram')) { s.post_type = 'post'; s.collaborators = []; }
  else if (identifier === 'youtube') {
    s.title = v.title; s.type = 'public'; s.selfDeclaredMadeForKids = 'no';
    s.tags = v.hashtags.map((h) => ({ value: h, label: h }));
    if (thumb) s.thumbnail = thumb;
  } else if (identifier === 'x') s.who_can_reply_post = 'everyone';
  else if (identifier === 'linkedin-page') s.post_as_images_carousel = false;
  // TikTok (Postiz identifier 'tiktok-business', measured 23 Sep 2026): DIRECT_POST publishes (UPLOAD only drops the video in the app's inbox while Postiz reports success);
  // public, duet/stitch/comments allowed, no auto music over the founder's own track, not branded/paid content.
  else if (identifier.startsWith('tiktok')) Object.assign(s, { privacy_level: 'PUBLIC_TO_EVERYONE', duet: true, stitch: true, comment: true,
    autoAddMusic: 'no', brand_content_toggle: false, brand_organic_toggle: false, content_posting_method: 'DIRECT_POST' });
  return s;
}

/** Reel vs post is the media's call: a video makes reel/short/video, an image makes post. A mismatch is refused. */
export function kindMismatch(v: Variant, media: Array<{ type: string; name: string }>): string | null {
  const video = media.some((m) => m.type === 'video/mp4' || /\.mp4$/i.test(m.name));
  const image = media.some((m) => /^image\//.test(m.type) || /\.(png|jpe?g|webp)$/i.test(m.name));
  if (['reel', 'short', 'video'].includes(v.post_type) && !video) return `${v.platform} ${v.post_type} needs a video`;
  if (v.post_type === 'post' && (v.platform === 'instagram') && !image) return 'instagram post needs an image';
  if ((v.platform === 'youtube' || v.platform === 'tiktok') && !video) return v.platform + ' needs a video';
  return null;
}

/**
 * Builds the Postiz payload from the variants: one Postiz post per platform, never a joined EN+AR text. The
 * variants of a platform in seq order are its thread (X: EN tweet, AR reply); a first comment follows them.
 * Media go on the first value; alt text rides on each image (documented `alt`).
 */
export function buildPostizPayload(post: PublishInput, list: PostizIntegration[], media: Uploaded[], thumb: Uploaded | null) {
  const posts: unknown[] = []; const skipped: string[] = []; const resolved: Record<string, string> = {};
  const byPlatform = new Map<Channel, Variant[]>();
  for (const v of post.variants) {
    if (!CHANNELS.includes(v.platform)) { skipped.push(v.platform + ' (not a marketing channel)'); continue; }
    byPlatform.set(v.platform, [...(byPlatform.get(v.platform) || []), v].sort((a, b) => a.seq - b.seq));
  }
  for (const [ch, vs] of byPlatform) {
    const it = integrationFor(list, ch);
    if (!it) { skipped.push(ch + ' (not connected in Postiz)'); continue; }
    const bad = kindMismatch(vs[0], post.media);
    if (bad) { skipped.push(ch + ' (' + bad + ')'); continue; }
    const images = media.map((m) => (vs[0].alt_text ? { ...m, alt: vs[0].alt_text } : m));
    const value: Array<Record<string, unknown>> = vs.map((v, i) => ({ content: v.body, image: i === 0 ? images : [] }));
    if (vs[0].first_comment) value.push({ content: vs[0].first_comment, image: [] });
    posts.push({ integration: { id: it.id }, value, settings: settingsFor(it.identifier, vs[0], thumb) });
    resolved[ch] = it.identifier;
  }
  // shortLink: false ALWAYS. POST /public/v1/posts takes a top-level boolean `shortLink`; Postiz's own CLI
  // defaults it to true and the account preference is "Ask every time" (23 Sep 2026), so it is stated here:
  // the approved UTM links reach the platforms unchanged.
  return { payload: { type: 'now', date: new Date().toISOString(), shortLink: false, tags: [], posts }, skipped, resolved };
}

export type PublishResult =
  | { mode: 'dry_run'; reason: string; would_send: { channels: Record<string, string>; skipped: string[]; variants: Array<{ platform: string; seq: number; chars: number }>; media: number } }
  | { mode: 'live'; ok: true; postiz: unknown; channels: Record<string, string>; skipped: string[] }
  // unclear: the POST may have been accepted (no answer, 5xx, unreadable 2xx). The post goes to 'unconfirmed'
  // and is reconciled against GET /posts before anything is sent again -- never retried blind.
  | { mode: 'live'; ok: false; unclear: boolean; error: string; status?: number; skipped: string[] };

async function upload(f: Fetch, base: string, key: string, m: Media): Promise<Uploaded | string> {
  const fd = new FormData();
  // The bytes come from the PRIVATE bucket through the service role and go to Postiz as a multipart upload:
  // no signed or public URL of our bucket is ever handed to Postiz.
  fd.append('file', new Blob([m.bytes as unknown as BlobPart], { type: m.type }), m.name);
  const r = await f(base + '/upload', { method: 'POST', headers: { Authorization: key }, body: fd });
  const j = await readJson(r);
  const o = Array.isArray(j) ? j[0] : j;
  if (!r.ok || !o?.id) return 'media upload refused: ' + String(o?.message || o?.error || r.status);
  return { id: String(o.id), path: String(o.path || o.url || '') };
}

/**
 * Publishes one due post through Postiz. With live=false NOTHING is written to Postiz -- no upload, no post:
 * the integrations are read (GET) so the dry run shows which channels would resolve, and that is all.
 */
export async function publishPost(f: Fetch, base: string, key: string, post: PublishInput, live: boolean, whyNot: string): Promise<PublishResult> {
  const ints = await postizIntegrations(f, base, key);
  if (!live) {
    const placeholders = post.media.map((m, i) => ({ id: 'dry-run-' + i, path: m.name }));
    const { skipped, resolved } = buildPostizPayload(post, ints.list, placeholders, null);
    if (ints.error) skipped.push('postiz integrations unreadable: HTTP ' + ints.status);
    return { mode: 'dry_run', reason: whyNot, would_send: { channels: resolved, skipped, media: post.media.length,
      variants: post.variants.map((v) => ({ platform: v.platform, seq: v.seq, chars: v.body.length })) } };
  }
  if (ints.error) return { mode: 'live', ok: false, unclear: false, error: 'postiz integrations unreadable: ' + ints.error, status: ints.status, skipped: [] };
  const media: Uploaded[] = [];
  for (const m of post.media) {
    const u = await upload(f, base, key, m);
    if (typeof u === 'string') return { mode: 'live', ok: false, unclear: false, error: u, skipped: [] };
    media.push(u);
  }
  let thumb: Uploaded | null = null;
  if (post.cover && post.variants.some((v) => v.platform === 'youtube')) {
    const u = await upload(f, base, key, post.cover);
    if (typeof u === 'string') return { mode: 'live', ok: false, unclear: false, error: 'thumbnail ' + u, skipped: [] };
    thumb = u;
  }
  const { payload, skipped, resolved } = buildPostizPayload(post, ints.list, media, thumb);
  if (!(payload.posts as unknown[]).length) return { mode: 'live', ok: false, unclear: false, error: 'no channel of this post can be published: ' + skipped.join('; '), skipped };
  let r: Response;
  try {
    r = await f(base + '/posts', { method: 'POST', headers: { Authorization: key, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  } catch (e) {
    return { mode: 'live', ok: false, unclear: true, error: 'no answer from Postiz to POST /posts: ' + String((e as Error)?.message || e), skipped };
  }
  const j = await readJson(r);
  if (r.status >= 500) return { mode: 'live', ok: false, unclear: true, error: 'Postiz answered HTTP ' + r.status + ' to POST /posts', status: r.status, skipped };
  if (!r.ok) return { mode: 'live', ok: false, unclear: false, error: String(j?.message || j?.error || j?.raw || 'HTTP ' + r.status), status: r.status, skipped };
  if (j?.raw !== undefined) return { mode: 'live', ok: false, unclear: true, error: 'Postiz accepted POST /posts but the answer was unreadable', status: r.status, skipped };
  return { mode: 'live', ok: true, postiz: stripTokens(j), channels: resolved, skipped };
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes as unknown as BufferSource))].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * The first asset whose bytes are not the approved ones (review of #874): `expected` maps a storage path to the
 * sha256 the calendar carried (and the approval hash covers). A path with an expected hash that does not match
 * -- or an expected hash with no bytes at all -- is named; null means every approved asset is byte-identical.
 */
export async function assetMismatch(assets: Array<{ path: string | null | undefined; bytes: Uint8Array }>, expected: Record<string, string | null | undefined>): Promise<string | null> {
  for (const [path, want] of Object.entries(expected)) {
    if (!path || !want) continue;
    const a = assets.find((x) => x.path === path);
    if (!a) return path + ' was not read';
    const got = await sha256Hex(a.bytes);
    if (got !== want.toLowerCase()) return `${path} is ${got}, approved ${want}`;
  }
  return null;
}

/** Postiz's post ids from its POST /posts answer ([{postId, integration}]). */
export function postizIds(answer: unknown): string[] {
  return (Array.isArray(answer) ? answer : []).map((x: any) => String(x?.postId || x?.id || '')).filter(Boolean);
}

const plain = (s: unknown) => String(s ?? '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();

/**
 * Is this post already in Postiz? GET /posts over [from, to], matched by integration and by the text of its
 * first value (Postiz may store it as HTML, so both sides are compared as plain text). Used before any resend
 * of an unclear attempt and by the watchdog, so a post Postiz accepted is never published twice.
 * ok=false means Postiz could not be read -- the caller must NOT treat that as "not there".
 */
export async function findInPostiz(f: Fetch, base: string, key: string, from: Date, to: Date,
                                   targets: Array<{ integrationId: string; content: string }>): Promise<{ ok: boolean; ids: string[]; error?: string }> {
  let r: Response;
  try { r = await f(`${base}/posts?startDate=${encodeURIComponent(from.toISOString())}&endDate=${encodeURIComponent(to.toISOString())}`, { headers: { Authorization: key } }); }
  catch (e) { return { ok: false, ids: [], error: String((e as Error)?.message || e) }; }
  const j = await readJson(r);
  if (!r.ok || !Array.isArray(j?.posts)) return { ok: false, ids: [], error: 'HTTP ' + r.status };
  const ids: string[] = [];
  for (const t of targets) {
    const hit = j.posts.find((p: any) => String(p.integration?.id || '') === t.integrationId && plain(p.content) === plain(t.content));
    if (hit) ids.push(String(hit.id));
  }
  return { ok: true, ids };
}

/** Deletes a post in Postiz (cancel). Postiz's public API has no reschedule: we keep our own clock, see marketing_channels/index.ts. */
export async function deletePostizPost(f: Fetch, base: string, key: string, id: string): Promise<{ ok: boolean; status: number; error?: string }> {
  const r = await f(`${base}/posts/${encodeURIComponent(id)}`, { method: 'DELETE', headers: { Authorization: key } });
  if (r.ok || r.status === 404) { await r.body?.cancel().catch(() => {}); return { ok: true, status: r.status }; }
  const j = await readJson(r);
  return { ok: false, status: r.status, error: String(j?.message || j?.error || j?.raw || 'HTTP ' + r.status) };
}

/** Postiz posts in a window, reduced to what fills permalinks: {postiz id -> {channel, releaseURL}}. */
export async function postizReleases(f: Fetch, base: string, key: string, from: Date, to: Date): Promise<Map<string, { identifier: string; url: string | null }>> {
  const r = await f(`${base}/posts?startDate=${encodeURIComponent(from.toISOString())}&endDate=${encodeURIComponent(to.toISOString())}`, { headers: { Authorization: key } });
  const j = await readJson(r);
  const out = new Map<string, { identifier: string; url: string | null }>();
  for (const p of Array.isArray(j?.posts) ? j.posts : []) out.set(String(p.id), { identifier: String(p.integration?.providerIdentifier || ''), url: p.releaseURL ? String(p.releaseURL) : null });
  return out;
}

// ── Graph ─────────────────────────────────────────────────────────────────────────────────────────
export interface MetaEnv { graph: string; token: string; adAccountId: string | null; businessId: string }

async function graphGet(f: Fetch, env: MetaEnv, path: string, token = env.token): Promise<{ status: number; body: any }> {
  const r = await f(env.graph + path + (path.includes('?') ? '&' : '?') + 'access_token=' + encodeURIComponent(token));
  return { status: r.status, body: await readJson(r) };
}
const gErr = (b: any) => b?.error ? String(b.error.message || 'graph error').slice(0, 200) : null;

export const REQUIRED_META_SCOPES = ['ads_read', 'read_insights', 'pages_show_list', 'pages_read_engagement', 'instagram_basic', 'instagram_manage_insights'];

export interface ConnectionCheck {
  check_key: string; platform: 'postiz' | 'meta' | 'linkedin'; ok: boolean; http_status: number | null;
  credential_keys: string[]; detail: Record<string, unknown>; needs: string | null;
}

/** The page the seat reports on and the ids behind it, from the system user's own view (GET /me/accounts). */
export async function metaPage(f: Fetch, env: MetaEnv) {
  const acc = await graphGet(f, env, '/me/accounts?fields=id,name,tasks,instagram_business_account{id,username}');
  const page = Array.isArray(acc.body?.data) ? acc.body.data[0] : undefined;
  return { status: acc.status, error: gErr(acc.body), page: page ? { id: String(page.id), name: String(page.name || ''), tasks: page.tasks || [], ig: page.instagram_business_account ? { id: String(page.instagram_business_account.id), username: page.instagram_business_account.username } : null } : null };
}

/** READ-ONLY access measurement. Every check is a real call; nothing is inferred from a key existing. */
export async function measureAccess(f: Fetch, p: { postizBase: string; postizKey: string | null; meta: MetaEnv | null; linkedinKeys: string[] }): Promise<ConnectionCheck[]> {
  const out: ConnectionCheck[] = [];
  // Postiz
  if (!p.postizKey) {
    out.push({ check_key: 'postiz.api', platform: 'postiz', ok: false, http_status: null, credential_keys: [], detail: {}, needs: 'app_secrets.postiz_api_key (Postiz Settings > Public API)' });
  } else {
    const ints = await postizIntegrations(f, p.postizBase, p.postizKey);
    out.push({ check_key: 'postiz.api', platform: 'postiz', ok: !ints.error, http_status: ints.status, credential_keys: ['postiz_api_key'],
      detail: { base: p.postizBase, channels: ints.list.map((x) => ({ identifier: x.identifier, disabled: x.disabled, refresh_needed: x.refreshNeeded })) },
      needs: ints.error ? 'Postiz refused app_secrets.postiz_api_key (HTTP ' + ints.status + '): a new Public API key' : null });
    if (!ints.error) {
      for (const ch of CHANNELS) {
        const it = integrationFor(ints.list, ch);
        out.push({ check_key: 'postiz.channel.' + ch, platform: 'postiz', ok: !!it, http_status: ints.status, credential_keys: ['postiz_api_key'],
          detail: it ? { identifier: it.identifier, integration_id: it.id } : {}, needs: it ? null : `connect (or reconnect) ${ch} in Postiz` });
      }
      const li = integrationFor(ints.list, 'linkedin');
      if (li) {
        const r = await f(`${p.postizBase}/analytics/${li.id}?date=7`, { headers: { Authorization: p.postizKey } });
        await r.body?.cancel().catch(() => {});
        out.push({ check_key: 'linkedin.via_postiz', platform: 'linkedin', ok: r.ok, http_status: r.status, credential_keys: ['postiz_api_key'],
          detail: { route: 'Postiz linkedin-page channel (publishing and analytics)', direct_api_keys: p.linkedinKeys },
          needs: r.ok ? null : 'reconnect the LinkedIn page in Postiz (its analytics answered HTTP ' + r.status + ')' });
      } else {
        out.push({ check_key: 'linkedin.via_postiz', platform: 'linkedin', ok: false, http_status: null, credential_keys: ['postiz_api_key'],
          detail: { direct_api_keys: p.linkedinKeys }, needs: 'connect the LinkedIn company page in Postiz' });
      }
    }
  }
  // Meta
  if (!p.meta) {
    out.push({ check_key: 'meta.token', platform: 'meta', ok: false, http_status: null, credential_keys: [], detail: {}, needs: 'app_secrets.meta_access_token (a Quotes Done system-user token)' });
    return out;
  }
  const env = p.meta;
  const dbg = await graphGet(f, env, '/debug_token?input_token=' + encodeURIComponent(env.token));
  const d = dbg.body?.data || {};
  const scopes: string[] = Array.isArray(d.scopes) ? d.scopes : [];
  const missing = REQUIRED_META_SCOPES.filter((s) => !scopes.includes(s));
  const tokenOk = dbg.status === 200 && d.is_valid === true && missing.length === 0;
  out.push({ check_key: 'meta.token', platform: 'meta', ok: tokenOk, http_status: dbg.status, credential_keys: ['meta_access_token'],
    detail: { type: d.type ?? null, is_valid: d.is_valid ?? null, expires_at: d.expires_at === 0 ? 'never' : (d.expires_at ? new Date(d.expires_at * 1000).toISOString() : null),
              data_access_expires_at: d.data_access_expires_at === 0 ? 'never' : (d.data_access_expires_at ? new Date(d.data_access_expires_at * 1000).toISOString() : null),
              scopes, missing_scopes: missing, error: gErr(dbg.body) },
    needs: tokenOk ? null : (d.is_valid === false || dbg.status !== 200 ? 'a new Quotes Done system-user token in app_secrets.meta_access_token' : 'grant these scopes to the system user: ' + missing.join(', ')) });
  const pg = await metaPage(f, env);
  const analyze = !!pg.page && (pg.page.tasks as string[]).includes('ANALYZE');
  out.push({ check_key: 'meta.page', platform: 'meta', ok: analyze, http_status: pg.status, credential_keys: ['meta_access_token'],
    detail: pg.page ? { page_id: pg.page.id, name: pg.page.name, tasks: pg.page.tasks } : { error: pg.error },
    needs: analyze ? null : 'assign the QuotesDone Facebook page to the system user with the Analyze task (Business settings > Pages)' });
  const ig = pg.page?.ig;
  if (ig) {
    const r = await graphGet(f, env, `/${ig.id}?fields=username,followers_count,media_count`);
    out.push({ check_key: 'meta.instagram', platform: 'meta', ok: r.status === 200, http_status: r.status, credential_keys: ['meta_access_token'],
      detail: r.status === 200 ? { ig_user_id: ig.id, username: r.body.username, followers: r.body.followers_count, media: r.body.media_count } : { error: gErr(r.body) },
      needs: r.status === 200 ? null : 'grant instagram_basic and instagram_manage_insights on the Instagram account to the system user' });
  } else {
    out.push({ check_key: 'meta.instagram', platform: 'meta', ok: false, http_status: pg.status, credential_keys: ['meta_access_token'], detail: {},
      needs: 'link the Instagram professional account to the QuotesDone Facebook page' });
  }
  if (!env.adAccountId) {
    out.push({ check_key: 'meta.ad_account', platform: 'meta', ok: false, http_status: null, credential_keys: [], detail: {}, needs: 'app_secrets.meta_ad_account_id' });
  } else {
    const act = 'act_' + env.adAccountId.replace(/^act_/, '');
    const r = await graphGet(f, env, `/${act}?fields=name,account_status,currency,timezone_name,business,amount_spent`);
    const b = r.body || {};
    const inBusiness = b?.business?.id === env.businessId;
    const ok = r.status === 200 && b.account_status === 1 && inBusiness;
    out.push({ check_key: 'meta.ad_account', platform: 'meta', ok, http_status: r.status, credential_keys: ['meta_access_token', 'meta_ad_account_id'],
      detail: r.status === 200 ? { account: act, name: b.name, account_status: b.account_status, currency: b.currency, timezone: b.timezone_name, business_id: b?.business?.id ?? null, amount_spent: b.amount_spent } : { error: gErr(b) },
      needs: ok ? null : r.status !== 200 ? 'give the system user access to ad account ' + act + ' (ads_read)'
        : !inBusiness ? 'add ad account ' + act + ' to the Quotes Done business portfolio (' + env.businessId + ')'
        : 'the ad account is not active (account_status ' + b.account_status + '): settle it in Ads Manager' });
  }
  return out;
}

// ── insights ──────────────────────────────────────────────────────────────────────────────────────
export interface InsightRow { platform: 'facebook' | 'instagram' | 'linkedin' | 'youtube' | 'tiktok'; object_type: 'page' | 'account' | 'post'; object_id: string; metric: string; day: string; value: number }

export const PAGE_METRICS = ['page_post_engagements', 'page_follows', 'page_views_total'];
export const IG_METRICS = ['reach', 'views', 'profile_views', 'accounts_engaged', 'total_interactions'];
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

/** Dubai day bounds as unix seconds: Graph's since/until for one Asia/Dubai day (UTC+4, no DST). */
export function dubaiDayBounds(day: string): { since: number; until: number } {
  const since = Date.parse(day + 'T00:00:00+04:00') / 1000;
  return { since, until: since + 86400 };
}

/** One Asia/Dubai day of every channel's numbers: Facebook page and Instagram (Graph), LinkedIn, YouTube and TikTok
 *  (Postiz analytics for each channel connected there), the YouTube channel's own counters (Data API, with the channel
 *  owner's token from the one connect link), plus a snapshot of recent post counters. A channel not connected is
 *  named in `errors`; the others still come back. */
export async function pullInsights(f: Fetch, env: MetaEnv | null, postiz: { base: string; key: string } | null, day: string,
  youtube: { token: string; channelId: string } | null = null): Promise<{ rows: InsightRow[]; errors: string[]; skipped: string[] }> {
  // skipped: a channel that is simply not connected is a named skip, not an error; the duty stays green for the rest.
  const rows: InsightRow[] = []; const errors: string[] = []; const skipped: string[] = [];
  const { since, until } = dubaiDayBounds(day);
  const pg = env ? await metaPage(f, env) : { page: null, error: 'meta_access_token is not in app_secrets' };
  if (!pg.page) errors.push('meta page unreadable: ' + (pg.error || 'no page'));
  if (env && pg.page) {
    const pt = await graphGet(f, env, `/${pg.page.id}?fields=access_token`);
    const pageToken: string | undefined = pt.body?.access_token;
    if (!pageToken) errors.push('page token unavailable: ' + (gErr(pt.body) || 'HTTP ' + pt.status));
    else {
      const r = await graphGet(f, env, `/${pg.page.id}/insights?metric=${PAGE_METRICS.join(',')}&period=day&since=${since}&until=${until}`, pageToken);
      if (gErr(r.body)) errors.push('page insights: ' + gErr(r.body));
      for (const m of Array.isArray(r.body?.data) ? r.body.data : []) {
        const v = (m.values || []).reduce((s: number, x: any) => s + (Number(x.value) || 0), 0);
        rows.push({ platform: 'facebook', object_type: 'page', object_id: pg.page.id, metric: slug(m.name), day, value: v });
      }
      const posts = await graphGet(f, env, `/${pg.page.id}/posts?fields=id,shares,reactions.summary(true).limit(0),comments.summary(true).limit(0)&limit=25`, pageToken);
      if (gErr(posts.body)) errors.push('page posts: ' + gErr(posts.body));
      for (const p of Array.isArray(posts.body?.data) ? posts.body.data : []) {
        rows.push({ platform: 'facebook', object_type: 'post', object_id: String(p.id), metric: 'reactions', day, value: Number(p.reactions?.summary?.total_count) || 0 });
        rows.push({ platform: 'facebook', object_type: 'post', object_id: String(p.id), metric: 'comments', day, value: Number(p.comments?.summary?.total_count) || 0 });
        rows.push({ platform: 'facebook', object_type: 'post', object_id: String(p.id), metric: 'shares', day, value: Number(p.shares?.count) || 0 });
      }
    }
    const ig = pg.page.ig;
    if (ig) {
      const r = await graphGet(f, env, `/${ig.id}/insights?metric=${IG_METRICS.join(',')}&period=day&metric_type=total_value&since=${since}&until=${until}`);
      if (gErr(r.body)) errors.push('instagram insights: ' + gErr(r.body));
      for (const m of Array.isArray(r.body?.data) ? r.body.data : []) {
        rows.push({ platform: 'instagram', object_type: 'account', object_id: ig.id, metric: slug(m.name), day, value: Number(m.total_value?.value) || 0 });
      }
      const acct = await graphGet(f, env, `/${ig.id}?fields=followers_count`);
      if (acct.status === 200) rows.push({ platform: 'instagram', object_type: 'account', object_id: ig.id, metric: 'followers', day, value: Number(acct.body.followers_count) || 0 });
      const media = await graphGet(f, env, `/${ig.id}/media?fields=id,like_count,comments_count&limit=25`);
      if (gErr(media.body)) errors.push('instagram media: ' + gErr(media.body));
      for (const m of Array.isArray(media.body?.data) ? media.body.data : []) {
        rows.push({ platform: 'instagram', object_type: 'post', object_id: String(m.id), metric: 'likes', day, value: Number(m.like_count) || 0 });
        rows.push({ platform: 'instagram', object_type: 'post', object_id: String(m.id), metric: 'comments', day, value: Number(m.comments_count) || 0 });
      }
    }
  }
  if (postiz) {
    const ints = await postizIntegrations(f, postiz.base, postiz.key);
    for (const ch of ['linkedin', 'youtube', 'tiktok'] as const) {
      const it = integrationFor(ints.list, ch);
      if (!it) { skipped.push(ch + ' is not connected in Postiz'); continue; }
      const r = await f(`${postiz.base}/analytics/${it.id}?date=7`, { headers: { Authorization: postiz.key } });
      const j = await readJson(r);
      if (!r.ok || !Array.isArray(j)) errors.push(ch + ' analytics via postiz: HTTP ' + r.status);
      for (const series of Array.isArray(j) ? j : []) {
        const pt = (series.data || []).find((x: any) => String(x.date) === day);
        if (pt) rows.push({ platform: ch, object_type: ch === 'linkedin' ? 'page' : 'account', object_id: it.id, metric: slug(String(series.label || 'metric')), day, value: Number(pt.total) || 0 });
      }
    }
  }
  if (youtube) {
    // The channel's running totals, read as the owner (youtube.force-ssl covers channels.list).
    const r = await f('https://www.googleapis.com/youtube/v3/channels?part=statistics&id=' + encodeURIComponent(youtube.channelId), { headers: { Authorization: 'Bearer ' + youtube.token } });
    const j = await readJson(r);
    const st = j?.items?.[0]?.statistics;
    if (!r.ok || !st) errors.push('youtube channel statistics: HTTP ' + r.status);
    else for (const [k, metric] of [['subscriberCount', 'subscribers'], ['viewCount', 'views_total'], ['videoCount', 'videos']] as const) {
      if (st[k] != null) rows.push({ platform: 'youtube', object_type: 'account', object_id: youtube.channelId, metric, day, value: Number(st[k]) || 0 });
    }
  }
  return { rows, errors, skipped };
}

/** Postgres/PostgREST codes that mean "this platform's rows have no home yet" (the SQL is not applied): a CHECK that does
 *  not admit the platform (23514), a missing table (42P01) or column (42703), or PostgREST's schema-cache misses. */
const SCHEMA_NOT_APPLIED = new Set(['23514', '42P01', '42703', 'PGRST204', 'PGRST205']);
export type InsightUpsert = (rows: InsightRow[]) => Promise<{ error: { code?: string; message: string } | null }>;
/** Saves insight rows ONE PLATFORM AT A TIME, so a platform the database cannot hold yet never loses the others'
 *  day (each run fetches only yesterday, so a lost day is lost for good). A platform refused because its schema is
 *  not applied is a named skip; any other refusal is an error for that platform only. */
export async function saveInsights(upsert: InsightUpsert, rows: InsightRow[]): Promise<{ written: number; skipped: string[]; errors: string[] }> {
  const by = new Map<string, InsightRow[]>();
  for (const r of rows) by.set(r.platform, [...(by.get(r.platform) || []), r]);
  let written = 0; const skipped: string[] = []; const errors: string[] = [];
  for (const [platform, group] of by) {
    let error: { code?: string; message: string } | null;
    try { ({ error } = await upsert(group)); } catch (e) { error = { message: String((e as Error)?.message || e) }; }
    if (!error) { written += group.length; continue; }
    if (SCHEMA_NOT_APPLIED.has(String(error.code || ''))) skipped.push(`${platform}: schema not applied (${error.code})`);
    else errors.push(`${platform}: ${error.message}`);
  }
  return { written, skipped, errors };
}

// ── ad spend ──────────────────────────────────────────────────────────────────────────────────────
export interface SpendRow { campaign_id: string; campaign_name: string; day: string; spend: number; currency: string; impressions: number | null; clicks: number | null }

/**
 * Spend per campaign per day for [since, until] (Asia/Dubai dates; the account's timezone was measured
 * Asia/Dubai). Also returns the account's business and currency FROM THE SAME READ, so the database can
 * refuse spend from an account outside the company. Read-only.
 */
export async function readAdSpend(f: Fetch, env: MetaEnv, since: string, until: string): Promise<{ ok: boolean; account: string; business_id: string | null; currency: string | null; rows: SpendRow[]; error?: string }> {
  const act = 'act_' + String(env.adAccountId || '').replace(/^act_/, '');
  const a = await graphGet(f, env, `/${act}?fields=currency,business,timezone_name`);
  if (a.status !== 200) return { ok: false, account: act, business_id: null, currency: null, rows: [], error: gErr(a.body) || 'HTTP ' + a.status };
  const currency = String(a.body.currency || '');
  const rows: SpendRow[] = [];
  let path: string | null = `/${act}/insights?level=campaign&time_increment=1&time_range=${encodeURIComponent(JSON.stringify({ since, until }))}&fields=campaign_id,campaign_name,spend,impressions,clicks,date_start,account_currency&limit=500`;
  for (let page = 0; path && page < 10; page++) {
    const r = await graphGet(f, env, path);
    if (r.status !== 200) return { ok: false, account: act, business_id: a.body?.business?.id ?? null, currency, rows: [], error: gErr(r.body) || 'HTTP ' + r.status };
    for (const x of Array.isArray(r.body?.data) ? r.body.data : []) {
      rows.push({ campaign_id: String(x.campaign_id), campaign_name: String(x.campaign_name || ''), day: String(x.date_start), spend: Number(x.spend) || 0,
                  currency: String(x.account_currency || currency), impressions: x.impressions != null ? Number(x.impressions) : null, clicks: x.clicks != null ? Number(x.clicks) : null });
    }
    // The next page is followed by its cursor, never by paging.next (that URL carries the token).
    const after = r.body?.paging?.next ? r.body?.paging?.cursors?.after : null;
    path = after ? `/${act}/insights?level=campaign&time_increment=1&time_range=${encodeURIComponent(JSON.stringify({ since, until }))}&fields=campaign_id,campaign_name,spend,impressions,clicks,date_start,account_currency&limit=500&after=${encodeURIComponent(after)}` : null;
  }
  return { ok: true, account: act, business_id: a.body?.business?.id ?? null, currency, rows };
}

/** Asia/Dubai calendar date, offset by `days`. */
export function dubaiDate(now: Date, days = 0): string {
  return new Date(now.getTime() + 4 * 3600_000 + days * 86400_000).toISOString().slice(0, 10);
}

// ONE HEAVY PHASE PER BEAT (24 Sep 2026, GAPS.md marketing gap 1). marketingChannels returned HTTP 546 (the edge
// CPU cap) 9 times up to 23 Sep: one 'duties' call could download and sha256 up to five approved videos, render a
// calendar PDF with its frames plus the XLSX, and run the daily reads. A beat now does at most ONE live post; a beat
// that sent one does nothing heavier after it, and a calendar render ends the beat too. The rest waits 15 minutes.
export const MAX_LIVE_PER_BEAT = 1;
export function publishSpentTheBeat(p: { published?: number; failed?: number; unconfirmed?: number; refused_by_database?: number } | null | undefined): boolean {
  return ((p?.published || 0) + (p?.failed || 0) + (p?.unconfirmed || 0) + (p?.refused_by_database || 0)) > 0;
}
