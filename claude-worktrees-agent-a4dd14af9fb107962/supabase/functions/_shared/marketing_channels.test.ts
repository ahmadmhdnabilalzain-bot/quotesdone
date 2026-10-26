// The marketing seat against a MOCK Postiz and a MOCK Graph (marketing, 22 Sep 2026). No network.
//   deno test supabase/functions/_shared/marketing_channels.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  buildPostizPayload, dubaiDate, measureAccess, publishPost, pullInsights, readAdSpend, stripTokens,
  type Fetch, type MetaEnv, type PublishInput,
} from './marketing_channels.ts';

const TOKEN = 'EAAZZDEMOTOKENVALUE0000000000';
const P = 'https://postiz.example.invalid/public/v1';
const G = 'https://graph.example.invalid/v21.0';
const META: MetaEnv = { graph: G, token: TOKEN, adAccountId: '1234', businessId: '2335064440232533' };
const INTEGRATIONS = [
  { id: 'i-fb', identifier: 'facebook', disabled: false }, { id: 'i-ig', identifier: 'instagram-standalone', disabled: false },
  { id: 'i-li', identifier: 'linkedin-page', disabled: false }, { id: 'i-x', identifier: 'x', disabled: false },
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

const POST: PublishInput = {
  id: 1, text_en: 'ZZ DEMO — get three quotes', text_ar: 'احصل على ثلاثة عروض أسعار', channels: ['facebook', 'instagram', 'linkedin'],
  scheduled_at: '2026-09-22T08:00:00Z', is_demo: true, media: [{ name: 'card.png', type: 'image/png', bytes: new Uint8Array([1, 2, 3]) }],
};

Deno.test('switch off: the scheduler reads Postiz and never POSTs anything', async () => {
  const { f, calls } = mock([[/\/integrations$/, () => INTEGRATIONS]]);
  const r = await publishPost(f, P, 'k', { ...POST, is_demo: false }, false, 'app_secrets.marketing_golive is not true');
  assertEquals(r.mode, 'dry_run');
  assertEquals(calls.filter((c) => c.method !== 'GET'), [], 'a dry run wrote to Postiz');
  if (r.mode === 'dry_run') {
    assertEquals(r.would_send.channels, { facebook: 'facebook', instagram: 'instagram-standalone', linkedin: 'linkedin-page' });
    assertEquals(r.would_send.media, 1);
  }
});

Deno.test('live: uploads the media, then posts EN + AR to every connected channel', async () => {
  let sent: any = null;
  const { f, calls } = mock([
    [/\/integrations$/, () => INTEGRATIONS],
    [/\/upload$/, () => ({ id: 'm1', path: 'https://uploads.example.invalid/m1.png' })],
    [/\/posts$/, (_u, init) => { sent = JSON.parse(String(init?.body)); return [{ postId: 'p1', integration: 'i-fb' }]; }],
  ]);
  const r = await publishPost(f, P, 'k', { ...POST, is_demo: false }, true, '');
  assert(r.mode === 'live' && r.ok);
  assertEquals(calls.map((c) => c.method + ' ' + c.url.replace(P, '')), ['GET /integrations', 'POST /upload', 'POST /posts']);
  assertEquals(sent.posts.length, 3);
  const content = sent.posts[0].value[0].content as string;
  assert(content.includes('get three quotes') && content.includes('ثلاثة'), 'the body carries both languages');
  assertEquals(sent.posts.find((p: any) => p.settings.__type === 'instagram-standalone').value[0].image, [{ id: 'm1', path: 'https://uploads.example.invalid/m1.png' }]);
});

Deno.test('a channel that is not connected is skipped, and instagram without media is skipped', () => {
  const { skipped, resolved } = buildPostizPayload({ ...POST, channels: ['instagram', 'x', 'tiktok'] }, INTEGRATIONS.filter((i) => i.identifier !== 'x'), []);
  assertEquals(resolved, {});
  assertEquals(skipped, ['instagram (needs media)', 'x (not connected in Postiz)', 'tiktok (not a marketing channel)']);
});

Deno.test('a Postiz refusal is a failure with its reason, never a success', async () => {
  const { f } = mock([[/\/integrations$/, () => INTEGRATIONS], [/\/upload$/, () => ({ id: 'm1', path: 'x' })], [/\/posts$/, () => ({ message: 'rate limited' }), 429]]);
  const r = await publishPost(f, P, 'k', { ...POST, is_demo: false }, true, '');
  assert(r.mode === 'live' && !r.ok && r.error === 'rate limited' && r.status === 429);
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
  ]);
  const { rows, errors } = await pullInsights(f, META, { base: P, key: 'k' }, '2026-09-21');
  assertEquals(errors, []);
  const m = Object.fromEntries(rows.map((r) => [`${r.platform}.${r.object_type}.${r.metric}`, r.value]));
  assertEquals(m['facebook.page.page_follows'], 4);
  assertEquals(m['instagram.account.reach'], 30);
  assertEquals(m['instagram.account.followers'], 4);
  assertEquals(m['facebook.post.reactions'], 5);
  assertEquals(m['linkedin.page.page_views'], 6);
  assert(!JSON.stringify(rows).includes('PAGETOKEN-SECRET'));
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
