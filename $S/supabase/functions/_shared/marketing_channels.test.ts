// The marketing seat against a MOCK Postiz and a MOCK Graph (marketing, 22-23 Sep 2026). No network.
//   deno test supabase/functions/_shared/marketing_channels.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  assetMismatch, buildPostizPayload, deletePostizPost, dubaiDate, sha256Hex, findInPostiz, isDemoText, measureAccess, publishPost, pullInsights,
  readAdSpend, saveInsights, stripTokens, type Fetch, type InsightRow, type MetaEnv, type PublishInput, type Variant,
} from './marketing_channels.ts';

const TOKEN = 'EAAZZDEMOTOKENVALUE0000000000';
const P = 'https://postiz.example.invalid/public/v1';
const G = 'https://graph.example.invalid/v21.0';
const META: MetaEnv = { graph: G, token: TOKEN, adAccountId: '1234', businessId: '2335064440232533' };
const INTEGRATIONS = [
  { id: 'i-fb', identifier: 'facebook', disabled: false }, { id: 'i-ig', identifier: 'instagram-standalone', disabled: false },
  { id: 'i-li', identifier: 'linkedin-page', disabled: false }, { id: 'i-x', identifier: 'x', disabled: false },
  { id: 'i-yt', identifier: 'youtube', disabled: false }, { id: 'i-tt', identifier: 'tiktok-business', disabled: false },
];

type Call = { method: string; url: string };
function mock(routes: Array<[RegExp, (url: string, init?: RequestInit) => unknown, number?]>): { f: Fetch; calls: Call[] } {
  const calls: Call[] = [];
  const f: Fetch = (url, init) => {
    calls.push({ method: init?.method || 'GET', url });
    for (const [re, body, status] of routes) {
      if (re.test(url)) return Promise.resolve(new Response(JSON.stringify(body(url, init)), { status: status ?? 200 }));
    }
    return Promise.resolve(new Response(JSON.stringify({ error: { message: 'no mock for ' + url } }), { status: 404 }));
  };
  return { f, calls };
}

// The bodies as marketing_post_variant stores them: caption, blank line, hashtags (the generated column).
const v = (platform: Variant['platform'], post_type: Variant['post_type'], caption: string, hashtags: string[], extra: Partial<Variant> = {}): Variant =>
  ({ platform, seq: 1, post_type, body: caption + (hashtags.length ? '\n\n#' + hashtags.join(' #') : ''), hashtags, title: null, alt_text: null, first_comment: null, ...extra });
const VIDEO = { name: '01.mp4', type: 'video/mp4', bytes: new Uint8Array([0, 0, 0, 24]) };
const FRAME = { name: '01.jpg', type: 'image/jpeg', bytes: new Uint8Array([255, 216]) };
const POST: PublishInput = {
  id: 1, ingest_key: 'm1-01', is_demo: false, media: [VIDEO], cover: FRAME,
  variants: [
    v('instagram', 'reel', 'Suppliers: real requests.\n\nالموردون: طلبات حقيقية.', ['UAE', 'Suppliers'], { alt_text: 'A supplier on a phone', first_comment: 'Register: quotesdone.ae' }),
    v('x', 'video', 'Suppliers: real requests.', ['UAE']),
    { ...v('x', 'video', 'الموردون: طلبات حقيقية.', []), seq: 2 },
    v('youtube', 'short', 'Suppliers: real requests from UAE buyers.', ['Shorts', 'UAE'], { title: 'Three quotes, one request' }),
    v('linkedin', 'video', 'Suppliers in the UAE: real requests.', ['Procurement']),
    v('facebook', 'reel', 'Suppliers: real requests.', ['UAE']),
    v('tiktok', 'video', 'Suppliers: real requests. الموردون', ['UAE', 'Suppliers']),
  ],
};

Deno.test('switch off: the scheduler reads Postiz and never POSTs anything', async () => {
  const { f, calls } = mock([[/\/integrations$/, () => INTEGRATIONS]]);
  const r = await publishPost(f, P, 'k', POST, false, 'app_secrets.marketing_golive is not true');
  assertEquals(r.mode, 'dry_run');
  assertEquals(calls.filter((c) => c.method !== 'GET'), [], 'a dry run wrote to Postiz');
  if (r.mode === 'dry_run') {
    assertEquals(r.would_send.channels, { instagram: 'instagram-standalone', x: 'x', youtube: 'youtube', linkedin: 'linkedin-page', facebook: 'facebook', tiktok: 'tiktok-business' });
    assertEquals(r.would_send.variants.length, 7);
  }
});

Deno.test('live: one Postiz post per platform from its variant, hashtags in every text, never a joined EN+AR body', async () => {
  let sent: any = null;
  const { f, calls } = mock([
    [/\/integrations$/, () => INTEGRATIONS],
    [/\/upload$/, (_u, init) => { const n = (init?.body as FormData).get('file') as File; return { id: 'u-' + n.name, path: 'https://uploads.example.invalid/' + n.name }; }],
    [/\/posts$/, (_u, init) => { sent = JSON.parse(String(init?.body)); return [{ postId: 'p1', integration: 'i-ig' }]; }],
  ]);
  const r = await publishPost(f, P, 'k', POST, true, '');
  assert(r.mode === 'live' && r.ok, JSON.stringify(r));
  assertEquals(calls.map((c) => c.method + ' ' + c.url.replace(P, '')), ['GET /integrations', 'POST /upload', 'POST /upload', 'POST /posts']);
  const by = Object.fromEntries(sent.posts.map((p: any) => [p.settings.__type, p]));
  assertEquals(Object.keys(by).sort(), ['facebook', 'instagram-standalone', 'linkedin-page', 'tiktok-business', 'x', 'youtube']);
  // every approved hashtag reaches the text Postiz receives, on every platform
  for (const vv of POST.variants.filter((x) => x.seq === 1)) {
    const id = { instagram: 'instagram-standalone', linkedin: 'linkedin-page', tiktok: 'tiktok-business' }[vv.platform as string] || vv.platform;
    const content: string = by[id].value[0].content;
    assertEquals(content, vv.body, vv.platform + ' got a different text than the approved body');
    for (const h of vv.hashtags) assert(content.includes('#' + h), vv.platform + ' lost #' + h);
  }
  // X is a thread: EN tweet then AR reply, each its own value
  assertEquals(by.x.value.map((x: any) => x.content), ['Suppliers: real requests.\n\n#UAE', 'الموردون: طلبات حقيقية.']);
  assert(by.x.value[0].content.length <= 280);
  // Instagram: a video sent as post_type 'post' is published by Postiz as a Reel; alt text on the media; first comment follows
  assertEquals(by['instagram-standalone'].settings, { __type: 'instagram-standalone', post_type: 'post', collaborators: [] });
  assertEquals(by['instagram-standalone'].value[0].image, [{ id: 'u-01.mp4', path: 'https://uploads.example.invalid/01.mp4', alt: 'A supplier on a phone' }]);
  assertEquals(by['instagram-standalone'].value[1].content, 'Register: quotesdone.ae');
  // YouTube: the calendar's title reaches the settings block; hashtags also as tags; the key frame is the thumbnail
  assertEquals(by.youtube.settings.title, 'Three quotes, one request');
  assertEquals(by.youtube.settings.type, 'public');
  assertEquals(by.youtube.settings.tags, [{ value: 'Shorts', label: 'Shorts' }, { value: 'UAE', label: 'UAE' }]);
  assertEquals(by.youtube.settings.thumbnail, { id: 'u-01.jpg', path: 'https://uploads.example.invalid/01.jpg' });
  assert(by.youtube.value[0].content.includes('#Shorts'));
  // TikTok: DIRECT_POST (UPLOAD would only reach the app inbox), public, no auto music
  assertEquals(by['tiktok-business'].settings, { __type: 'tiktok-business', privacy_level: 'PUBLIC_TO_EVERYONE', duet: true, stitch: true, comment: true,
    autoAddMusic: 'no', brand_content_toggle: false, brand_organic_toggle: false, content_posting_method: 'DIRECT_POST' });
  for (const p of sent.posts) assert(!(p.value[0].content.includes('Suppliers') && p.value[0].content.includes('الموردون') && p.settings.__type === 'x'), 'X got the joined text');
});

Deno.test('reel vs post is the media\'s call: a reel without a video, or YouTube without one, is skipped with the reason', () => {
  const imageOnly = { ...POST, media: [FRAME], cover: null };
  const { skipped, resolved } = buildPostizPayload(imageOnly, INTEGRATIONS.filter((i) => i.identifier !== 'linkedin-page'), [{ id: 'm', path: 'p' }], null);
  assertEquals(resolved, {});
  assert(skipped.includes('instagram (instagram reel needs a video)'), skipped.join('|'));
  assert(skipped.includes('youtube (youtube short needs a video)'), skipped.join('|'));
  assert(skipped.includes('linkedin (not connected in Postiz)'), skipped.join('|'));
});

Deno.test('a Postiz refusal is a failure; no answer or a 5xx is UNCLEAR (reconciled before any resend)', async () => {
  const base: Array<[RegExp, (u: string) => unknown, number?]> = [[/\/integrations$/, () => INTEGRATIONS], [/\/upload$/, () => ({ id: 'm1', path: 'x' })]];
  let r = await publishPost(mock([...base, [/\/posts$/, () => ({ message: 'rate limited' }), 429]]).f, P, 'k', POST, true, '');
  assert(r.mode === 'live' && !r.ok && !r.unclear && r.error === 'rate limited' && r.status === 429);
  r = await publishPost(mock([...base, [/\/posts$/, () => ({ message: 'gateway' }), 502]]).f, P, 'k', POST, true, '');
  assert(r.mode === 'live' && !r.ok && r.unclear);
  const lost = mock(base);
  const f: Fetch = (u, i) => /\/posts$/.test(u) ? Promise.reject(new Error('connection reset')) : lost.f(u, i);
  r = await publishPost(f, P, 'k', POST, true, '');
  assert(r.mode === 'live' && !r.ok && r.unclear && /no answer/.test(r.error));
});

Deno.test('before a resend: a post Postiz already has is found by integration and text, HTML or not', async () => {
  const { f, calls } = mock([[/\/posts\?startDate=/, () => ({ posts: [
    { id: 'z9', content: '<p>Suppliers: real requests.</p><p>#UAE</p>', integration: { id: 'i-x', providerIdentifier: 'x' } },
    { id: 'z8', content: 'something else', integration: { id: 'i-fb', providerIdentifier: 'facebook' } }] })]]);
  const found = await findInPostiz(f, P, 'k', new Date('2026-10-01'), new Date('2026-10-02'),
    [{ integrationId: 'i-x', content: 'Suppliers: real requests.\n\n#UAE' }, { integrationId: 'i-fb', content: 'Suppliers: real requests.\n\n#UAE' }]);
  assertEquals(found, { ok: true, ids: ['z9'] });
  assertEquals(calls.filter((c) => c.method !== 'GET'), []);
  const down = await findInPostiz(mock([[/\/posts\?/, () => ({ message: 'down' }), 503]]).f, P, 'k', new Date(), new Date(), []);
  assertEquals(down.ok, false, 'an unreadable Postiz is never read as "not there"');
});

Deno.test('cancel deletes the post in Postiz; an already-gone post is fine', async () => {
  const { f, calls } = mock([[/\/posts\/p1$/, () => ({ ok: true })], [/\/posts\/gone$/, () => ({ message: 'not found' }), 404]]);
  assertEquals((await deletePostizPost(f, P, 'k', 'p1')).ok, true);
  assertEquals((await deletePostizPost(f, P, 'k', 'gone')).ok, true);
  assertEquals(calls.map((c) => c.method + ' ' + c.url.replace(P, '')), ['DELETE /posts/p1', 'DELETE /posts/gone']);
  const bad = await deletePostizPost(mock([[/\/posts\//, () => ({ message: 'published posts cannot be deleted' }), 400]]).f, P, 'k', 'p2');
  assert(!bad.ok && /cannot be deleted/.test(bad.error!));
});

// Postiz's account "Shortlink Preference" is "Ask every time" (23 Sep 2026). The public API's POST /posts takes
// a top-level boolean `shortLink` (Postiz CLI 2.0.16 builds the same body and DEFAULTS it to true), so the
// publisher states false on every create: our UTM links reach every platform exactly as approved.
Deno.test('every create-post payload says shortLink: false, and the UTM link reaches every platform unchanged', async () => {
  const UTM = 'https://www.quotesdone.ae/suppliers?utm_source=social&utm_medium=organic&utm_campaign=2026-month1';
  const withLink: PublishInput = { ...POST, variants: POST.variants.map((x) => ({ ...x, body: x.body + '\n' + UTM })) };
  let sent: any = null;
  const { f } = mock([[/\/integrations$/, () => INTEGRATIONS], [/\/upload$/, () => ({ id: 'm', path: 'p' })],
    [/\/posts$/, (_u, init) => { sent = JSON.parse(String(init?.body)); return [{ postId: 'p1' }]; }]]);
  const r = await publishPost(f, P, 'k', withLink, true, '');
  assert(r.mode === 'live' && r.ok);
  assertEquals(sent.shortLink, false, 'shortLink must be sent as false, never left to the account default');
  assertEquals(sent.posts.length, 6);
  for (const p of sent.posts) assert(p.value[0].content.includes(UTM), p.settings.__type + ' lost or changed the UTM link');
  assertEquals(buildPostizPayload(withLink, INTEGRATIONS, [], null).payload.shortLink, false, 'the dry run shows the same');
});

Deno.test('a video or key frame whose bytes are not the approved ones is named, and never passes', async () => {
  const V = 'campaigns/c/videos/01.mp4', K = 'campaigns/c/frames/01.jpg';
  const good = { [V]: await sha256Hex(VIDEO.bytes), [K]: await sha256Hex(FRAME.bytes) };
  assertEquals(await assetMismatch([{ path: V, bytes: VIDEO.bytes }, { path: K, bytes: FRAME.bytes }], good), null);
  const swapped = await assetMismatch([{ path: V, bytes: new Uint8Array([9, 9, 9]) }, { path: K, bytes: FRAME.bytes }], good);
  assert(swapped && swapped.startsWith(V + ' is ') && swapped.endsWith('approved ' + good[V]), String(swapped));
  assertEquals(await assetMismatch([{ path: V, bytes: VIDEO.bytes }], good), K + ' was not read', 'an approved key frame that was not read is a mismatch');
});

Deno.test('ZZ DEMO is caught in the TEXT as well as by the flag', () => {
  assert(isDemoText('Hello', 'ZZ DEMO caption'));
  assert(isDemoText('zz-demo'));
  assert(!isDemoText('Hello', null, undefined, 'Dubai'));
});

Deno.test('tokens never survive into anything the seat stores', () => {
  const graph = { data: [{ v: 1 }], paging: { next: G + '/x?access_token=' + TOKEN }, access_token: TOKEN, nested: { url: 'https://h/?access_token=' + TOKEN } };
  const s = JSON.stringify(stripTokens(graph));
  assert(!s.includes(TOKEN), s);
  assert(!s.includes('paging'));
});

function graphRoutes(opts: { business?: string; spendRows?: unknown[]; tokenValid?: boolean } = {}): Array<[RegExp, (url: string) => unknown, number?]> {
  return [
    [/\/debug_token/, () => ({ data: { type: 'SYSTEM_USER', is_valid: opts.tokenValid ?? true, expires_at: 0, data_access_expires_at: 0,
      scopes: ['ads_read', 'read_insights', 'pages_show_list', 'pages_read_engagement', 'instagram_basic', 'instagram_manage_insights'] } })],
    [/\/me\/accounts/, () => ({ data: [{ id: '109', name: 'QuotesDone', tasks: ['ANALYZE', 'ADVERTISE'], instagram_business_account: { id: '178', username: 'official.quotesdone' } }] })],
    [/\/109\?fields=access_token/, () => ({ access_token: 'PAGETOKEN-SECRET', id: '109' })],
    [/\/109\/insights/, () => ({ data: [{ name: 'page_follows', values: [{ value: 4 }] }, { name: 'page_views_total', values: [{ value: 9 }] }], paging: { next: G + '/n?access_token=PAGETOKEN-SECRET' } })],
    [/\/109\/posts/, () => ({ data: [{ id: '109_1', shares: { count: 2 }, reactions: { summary: { total_count: 5 } }, comments: { summary: { total_count: 1 } } }] })],
    [/\/178\/insights/, () => ({ data: [{ name: 'reach', total_value: { value: 30 } }, { name: 'views', total_value: { value: 70 } }] })],
    [/\/178\/media/, () => ({ data: [{ id: 'm9', like_count: 3, comments_count: 0 }] })],
    [/\/178\?fields=/, () => ({ username: 'official.quotesdone', followers_count: 4, media_count: 0 })],
    [/\/act_1234\/insights/, () => ({ data: opts.spendRows ?? [] })],
    [/\/act_1234\?fields=/, () => ({ name: 'quotesdoneads', account_status: 1, currency: 'AED', timezone_name: 'Asia/Dubai', business: { id: opts.business ?? '2335064440232533' }, amount_spent: '0' })],
  ];
}

Deno.test('access check measures every platform with read-only calls and names what is missing', async () => {
  const { f, calls } = mock([[/\/integrations$/, () => INTEGRATIONS.filter((i) => i.identifier !== 'x')], [/\/analytics\//, () => []], ...graphRoutes({ business: '999' })]);
  const checks = await measureAccess(f, { postizBase: P, postizKey: 'k', meta: META, linkedinKeys: [] });
  assertEquals(calls.filter((c) => c.method !== 'GET'), [], 'the access check wrote somewhere');
  const by = Object.fromEntries(checks.map((c) => [c.check_key, c]));
  assert(by['postiz.api'].ok && by['postiz.channel.facebook'].ok && by['linkedin.via_postiz'].ok && by['meta.token'].ok && by['meta.page'].ok && by['meta.instagram'].ok);
  assertEquals(by['meta.token'].detail.expires_at, 'never');
  assert(!by['postiz.channel.x'].ok && /connect/.test(by['postiz.channel.x'].needs!));
  assert(!by['meta.ad_account'].ok && /business portfolio/.test(by['meta.ad_account'].needs!), 'an ad account outside the business is named as the thing to fix');
  for (const c of checks) assert(c.ok || (c.needs && c.needs.trim()), c.check_key + ' failed without naming a need');
  assert(!JSON.stringify(checks).includes(TOKEN));
});

Deno.test('an invalid token is reported as the founder\'s to replace', async () => {
  const { f } = mock([[/\/integrations$/, () => INTEGRATIONS], [/\/analytics\//, () => []], ...graphRoutes({ tokenValid: false })]);
  const checks = await measureAccess(f, { postizBase: P, postizKey: 'k', meta: META, linkedinKeys: [] });
  const t = checks.find((c) => c.check_key === 'meta.token')!;
  assert(!t.ok && /new Quotes Done system-user token/.test(t.needs!));
});

Deno.test('insights: one Dubai day of page, Instagram, post and LinkedIn metrics, and no page token kept', async () => {
  const { f } = mock([
    ...graphRoutes(),
    [/\/integrations$/, () => INTEGRATIONS],
    [/\/analytics\/i-li/, () => [{ label: 'Page Views', data: [{ total: 6, date: '2026-09-21' }, { total: 1, date: '2026-09-20' }] }]],
    [/\/analytics\/i-yt/, () => [{ label: 'Views', data: [{ total: 12, date: '2026-09-21' }] }]],
    [/\/analytics\/i-tt/, () => [{ label: 'Video Views', data: [{ total: 9, date: '2026-09-21' }] }]],
    [/youtube\/v3\/channels/, () => ({ items: [{ statistics: { subscriberCount: '41', viewCount: '900', videoCount: '3' } }] })],
  ]);
  const { rows, errors } = await pullInsights(f, META, { base: P, key: 'k' }, '2026-09-21', { token: 'YT', channelId: 'UC1' });
  assertEquals(errors, []);
  const m = Object.fromEntries(rows.map((r) => [`${r.platform}.${r.object_type}.${r.metric}`, r.value]));
  assertEquals(m['facebook.page.page_follows'], 4);
  assertEquals(m['instagram.account.reach'], 30);
  assertEquals(m['instagram.account.followers'], 4);
  assertEquals(m['facebook.post.reactions'], 5);
  assertEquals(m['linkedin.page.page_views'], 6);
  assertEquals(m['youtube.account.views'], 12);
  assertEquals(m['tiktok.account.video_views'], 9);
  assertEquals(m['youtube.account.subscribers'], 41);
  assert(!JSON.stringify(rows).includes('PAGETOKEN-SECRET'));
});

Deno.test('insights: a channel not connected in Postiz is a named skip, not an error, and the rest still come back', async () => {
  const { f } = mock([
    ...graphRoutes(),
    [/\/integrations$/, () => INTEGRATIONS.filter((i) => i.identifier !== 'tiktok-business')],
    [/\/analytics\/i-li/, () => [{ label: 'Page Views', data: [{ total: 6, date: '2026-09-21' }] }]],
    [/\/analytics\/i-yt/, () => [{ label: 'Views', data: [{ total: 12, date: '2026-09-21' }] }]],
  ]);
  const { rows, errors, skipped } = await pullInsights(f, META, { base: P, key: 'k' }, '2026-09-21');
  assertEquals(errors, [], 'an unconnected channel must not turn the duty red on every run');
  assertEquals(skipped, ['tiktok is not connected in Postiz']);
  assert(rows.some((r) => r.platform === 'linkedin') && rows.some((r) => r.platform === 'facebook'));
});

Deno.test('insights are saved per platform: youtube refused by the CHECK (23514) is a skip, and FB/IG/LinkedIn are still written', async () => {
  const row = (platform: InsightRow['platform'], metric: string): InsightRow => ({ platform, object_type: 'account', object_id: 'o', metric, day: '2026-09-21', value: 1 });
  const rows = [row('facebook', 'a'), row('youtube', 'views'), row('instagram', 'reach'), row('linkedin', 'page_views'), row('youtube', 'subscribers')];
  const stored: InsightRow[] = [];
  const upsert = async (rs: InsightRow[]) => {
    if (rs.some((r) => r.platform === 'youtube')) return { error: { code: '23514', message: 'violates check constraint "marketing_insight_day_platform_check"' } };
    stored.push(...rs); return { error: null };
  };
  const r = await saveInsights(upsert, rows);
  assertEquals(stored.map((x) => x.platform).sort(), ['facebook', 'instagram', 'linkedin']);
  assertEquals(r.written, 3);
  assertEquals(r.skipped, ['youtube: schema not applied (23514)']);
  assertEquals(r.errors, []);
  // a missing table/column is the same skip; any other refusal is an error for that platform only
  assertEquals((await saveInsights(async () => ({ error: { code: '42P01', message: 'x' } }), [row('tiktok', 'v')])).skipped, ['tiktok: schema not applied (42P01)']);
  const other = await saveInsights(async (rs) => rs[0].platform === 'facebook' ? { error: { code: '57014', message: 'timeout' } } : { error: null }, rows);
  assertEquals(other.errors, ['facebook: timeout']);
  assertEquals(other.written, 4);
});

Deno.test('ad spend: per campaign per day, with the business read on the same call so the books can refuse', async () => {
  const spendRows = [
    { campaign_id: 'c1', campaign_name: 'QuotesDone suppliers', spend: '12.50', impressions: '900', clicks: '14', date_start: '2026-09-20', account_currency: 'AED' },
    { campaign_id: 'c1', campaign_name: 'QuotesDone suppliers', spend: '0', date_start: '2026-09-21', account_currency: 'AED' },
  ];
  const { f, calls } = mock(graphRoutes({ spendRows, business: '777' }));
  const r = await readAdSpend(f, META, '2026-09-15', '2026-09-22');
  assert(r.ok);
  assertEquals(r.business_id, '777', 'the business is reported as read, for fn_marketing_ad_spend_record to refuse');
  assertEquals(r.rows[0], { campaign_id: 'c1', campaign_name: 'QuotesDone suppliers', day: '2026-09-20', spend: 12.5, currency: 'AED', impressions: 900, clicks: 14 });
  assertEquals(calls.filter((c) => c.method !== 'GET'), [], 'reading spend wrote to Meta');
  assert(calls.every((c) => !/\/(campaigns|adsets)\b/.test(c.url) || c.method === 'GET'));
});

Deno.test('the Dubai date is UTC+4', () => {
  assertEquals(dubaiDate(new Date('2026-09-21T20:30:00Z')), '2026-09-22');
  assertEquals(dubaiDate(new Date('2026-09-21T19:30:00Z'), -1), '2026-09-20');
});

Deno.test('a beat that sent a live post does nothing heavier after it; an idle or dry-run beat goes on (gap 1, the CPU cap)', async () => {
  const { publishSpentTheBeat, MAX_LIVE_PER_BEAT } = await import('./marketing_channels.ts');
  assertEquals(MAX_LIVE_PER_BEAT, 1);
  assertEquals(publishSpentTheBeat({ published: 1 }), true);
  assertEquals(publishSpentTheBeat({ failed: 1 }), true);
  assertEquals(publishSpentTheBeat({ unconfirmed: 1 }), true);
  assertEquals(publishSpentTheBeat({ published: 0, failed: 0 }), false);
  assertEquals(publishSpentTheBeat(null), false);
});
