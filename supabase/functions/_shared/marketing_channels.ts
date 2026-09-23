// THE MARKETING SEAT'S CALLS TO POSTIZ AND META (marketing, 22 Sep 2026).
//
// Every HTTP call the seat makes lives here, with the fetch INJECTED, so the tests replay Postiz and
// Graph without a network (marketing_channels.test.ts). The edge function (marketing_channels/index.ts)
// only reads the database, calls these, and writes what they return.
//
// THREE PROPERTIES THE TESTS HOLD, because each one is a way this seat could hurt the company:
//   1. publishPost never POSTs to Postiz unless `live` is true -- and the caller passes live only when
//      app_secrets.marketing_golive is 'true' AND the post is not a ZZ DEMO post. Switched off, it
//      returns the payload it WOULD have sent, which is the dry run the founder can read.
//   2. Nothing an access token can hide in is returned. Graph puts the token into every paging.next URL
//      (measured 22 Sep 2026), so paging is never kept and every value passes through stripTokens.
//   3. readAdSpend reports the business the account sits in, on the same read, so the database can
//      refuse spend from an account that is not the company's (fn_marketing_ad_spend_record).
//
// Nothing here writes to Meta. Reads only: /me, /debug_token, /me/accounts, page and Instagram insights,
// ad account insights. The only writes are to Postiz, and only through publishPost with live=true.

import { campaignOf, withUtm } from './marketing_post_results.ts';

export type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

export const CHANNELS = ['facebook', 'instagram', 'linkedin', 'x'] as const;
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

/** The post text: English, then Arabic. Both are required by marketing_post. */
export function postBody(p: { text_en: string; text_ar: string }): string {
  return `${p.text_en.trim()}\n\n${p.text_ar.trim()}`;
}

// ── Postiz ────────────────────────────────────────────────────────────────────────────────────────
export interface PostizIntegration { id: string; identifier: string; name?: string; disabled?: boolean; refreshNeeded?: boolean }

export async function postizIntegrations(f: Fetch, base: string, key: string): Promise<{ status: number; list: PostizIntegration[]; error?: string }> {
  const r = await f(base + '/integrations', { headers: { Authorization: key } });
  const j = await readJson(r);
  if (!r.ok || !Array.isArray(j)) return { status: r.status, list: [], error: String(j?.message || j?.error || j?.raw || 'not a list') };
  return { status: r.status, list: j.map((x: any) => ({ id: String(x.id), identifier: String(x.identifier || ''), name: x.name, disabled: !!x.disabled, refreshNeeded: !!x.refreshNeeded })) };
}

/** The Postiz channel that serves one of our channels ('instagram-standalone' serves instagram, 'linkedin-page' linkedin). */
export function integrationFor(list: PostizIntegration[], ch: Channel): PostizIntegration | undefined {
  const live = list.filter((x) => !x.disabled && !x.refreshNeeded);
  return live.find((x) => ch === 'x' ? (x.identifier === 'x' || x.identifier === 'twitter') : (x.identifier === ch || x.identifier.startsWith(ch + '-')));
}

export interface PublishInput {
  id: number; ingest_key?: string; text_en: string; text_ar: string; channels: string[]; scheduled_at: string; is_demo: boolean;
  media: { name: string; type: string; bytes: Uint8Array }[];
}

/** Builds the Postiz payload. `images` are the uploaded Postiz media ({id, path}); in a dry run they are placeholders. */
export function buildPostizPayload(post: PublishInput, list: PostizIntegration[], images: { id: string; path: string }[]) {
  const posts: unknown[] = []; const skipped: string[] = []; const resolved: Record<string, string> = {};
  for (const raw of post.channels) {
    const ch = raw as Channel;
    if (!CHANNELS.includes(ch)) { skipped.push(raw + ' (not a marketing channel)'); continue; }
    const it = integrationFor(list, ch);
    if (!it) { skipped.push(ch + ' (not connected in Postiz)'); continue; }
    if (it.identifier.startsWith('instagram') && !images.length) { skipped.push(ch + ' (needs media)'); continue; }
    const settings: Record<string, unknown> = { __type: it.identifier };
    if (it.identifier.startsWith('instagram')) settings.post_type = 'post';
    if (it.identifier === 'x') settings.who_can_reply_post = 'everyone';
    // every quotesdone link names the platform, the month and the post (marketing_post_results.ts withUtm)
    const content = post.ingest_key ? withUtm(postBody(post), ch, campaignOf(post.scheduled_at), post.ingest_key) : postBody(post);
    posts.push({ integration: { id: it.id }, value: [{ content, image: images }], settings });
    resolved[ch] = it.identifier;
  }
  return { payload: { type: 'now', date: new Date().toISOString(), shortLink: false, tags: [], posts }, skipped, resolved };
}

export type PublishResult =
  | { mode: 'dry_run'; reason: string; would_send: { channels: Record<string, string>; skipped: string[]; body_chars: number; media: number } }
  | { mode: 'live'; ok: true; postiz: unknown; channels: Record<string, string>; skipped: string[] }
  | { mode: 'live'; ok: false; error: string; status?: number; skipped: string[] };

/**
 * Publishes one due post through Postiz. With live=false NOTHING is written to Postiz -- no upload, no post:
 * the integrations are read (GET) so the dry run shows which channels would resolve, and that is all.
 */
export async function publishPost(f: Fetch, base: string, key: string, post: PublishInput, live: boolean, whyNot: string): Promise<PublishResult> {
  const ints = await postizIntegrations(f, base, key);
  if (!live) {
    const placeholders = post.media.map((m, i) => ({ id: 'dry-run-' + i, path: m.name }));
    const { skipped, resolved } = buildPostizPayload(post, ints.list, placeholders);
    if (ints.error) skipped.push('postiz integrations unreadable: HTTP ' + ints.status);
    return { mode: 'dry_run', reason: whyNot, would_send: { channels: resolved, skipped, body_chars: postBody(post).length, media: post.media.length } };
  }
  if (ints.error) return { mode: 'live', ok: false, error: 'postiz integrations unreadable: ' + ints.error, status: ints.status, skipped: [] };
  const images: { id: string; path: string }[] = [];
  for (const m of post.media) {
    const fd = new FormData();
    fd.append('file', new Blob([m.bytes as unknown as BlobPart], { type: m.type }), m.name);
    const r = await f(base + '/upload', { method: 'POST', headers: { Authorization: key }, body: fd });
    const j = await readJson(r);
    const o = Array.isArray(j) ? j[0] : j;
    if (!r.ok || !o?.id) return { mode: 'live', ok: false, error: 'media upload refused: ' + String(o?.message || o?.error || r.status), status: r.status, skipped: [] };
    images.push({ id: String(o.id), path: String(o.path || o.url || '') });
  }
  const { payload, skipped, resolved } = buildPostizPayload(post, ints.list, images);
  if (!(payload.posts as unknown[]).length) return { mode: 'live', ok: false, error: 'no channel of this post is connected in Postiz', skipped };
  const r = await f(base + '/posts', { method: 'POST', headers: { Authorization: key, 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  const j = await readJson(r);
  if (!r.ok) return { mode: 'live', ok: false, error: String(j?.message || j?.error || j?.raw || 'HTTP ' + r.status), status: r.status, skipped };
  return { mode: 'live', ok: true, postiz: stripTokens(j), channels: resolved, skipped };
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
export interface InsightRow { platform: 'facebook' | 'instagram' | 'linkedin'; object_type: 'page' | 'account' | 'post'; object_id: string; metric: string; day: string; value: number }

export const PAGE_METRICS = ['page_post_engagements', 'page_follows', 'page_views_total'];
export const IG_METRICS = ['reach', 'views', 'profile_views', 'accounts_engaged', 'total_interactions'];
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

/** Dubai day bounds as unix seconds: Graph's since/until for one Asia/Dubai day (UTC+4, no DST). */
export function dubaiDayBounds(day: string): { since: number; until: number } {
  const since = Date.parse(day + 'T00:00:00+04:00') / 1000;
  return { since, until: since + 86400 };
}

/** One Asia/Dubai day of page, Instagram and LinkedIn metrics, plus a snapshot of recent post counters. */
export async function pullInsights(f: Fetch, env: MetaEnv, postiz: { base: string; key: string } | null, day: string): Promise<{ rows: InsightRow[]; errors: string[] }> {
  const rows: InsightRow[] = []; const errors: string[] = [];
  const { since, until } = dubaiDayBounds(day);
  const pg = await metaPage(f, env);
  if (!pg.page) errors.push('meta page unreadable: ' + (pg.error || 'no page'));
  if (pg.page) {
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
    const li = integrationFor(ints.list, 'linkedin');
    if (li) {
      const r = await f(`${postiz.base}/analytics/${li.id}?date=7`, { headers: { Authorization: postiz.key } });
      const j = await readJson(r);
      if (!r.ok || !Array.isArray(j)) errors.push('linkedin analytics via postiz: HTTP ' + r.status);
      for (const series of Array.isArray(j) ? j : []) {
        const pt = (series.data || []).find((x: any) => String(x.date) === day);
        if (pt) rows.push({ platform: 'linkedin', object_type: 'page', object_id: li.id, metric: slug(String(series.label || 'metric')), day, value: Number(pt.total) || 0 });
      }
    }
  }
  return { rows, errors };
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
