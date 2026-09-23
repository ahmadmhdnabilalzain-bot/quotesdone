// Per-post results and attribution against RECORDED Graph and Postiz answers (marketing, 23 Sep 2026). No network.
//   deno test supabase/functions/_shared/marketing_post_results.test.ts
// The response shapes are the documented ones (Instagram media insights, Page video_insights, Postiz
// /public/v1/posts and /public/v1/analytics/post/:id). Every metric path has a case, including refusals.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  campaignOf, channelOf, facebookPost, igMediaIdByPermalink, instagramMedia, postizIdsOf, postizReleases, viaPostiz, withUtm,
  IG_FEED, IG_REELS, type Fetch, type GraphEnv,
} from './marketing_post_results.ts';
import { buildPostizPayload, type PublishInput } from './marketing_channels.ts';
import { captureFirstTouch, readFirstTouch, touchFromUrl, FIRST_TOUCH_KEY } from '../../../src/lib/firstTouch.ts';
import { scorecardPeriods } from '../marketing/post_results.ts';

const G = 'https://graph.example.invalid/v21.0';
const P = 'https://postiz.example.invalid/public/v1';
const ENV: GraphEnv = { graph: G, token: 'EAAZZDEMOTOKEN' };

function mock(routes: Array<[RegExp, unknown, number?]>): { f: Fetch; calls: { method: string; url: string }[] } {
  const calls: { method: string; url: string }[] = [];
  const f: Fetch = (url, init) => {
    calls.push({ method: init?.method || 'GET', url });
    for (const [re, body, status] of routes) if (re.test(url)) return Promise.resolve(new Response(JSON.stringify(body), { status: status ?? 200 }));
    return Promise.resolve(new Response(JSON.stringify({ error: { message: 'no mock for ' + url, code: 100 } }), { status: 400 }));
  };
  return { f, calls };
}
const onlyGets = (calls: { method: string }[]) => assertEquals(calls.filter((c) => c.method !== 'GET'), [], 'a results read wrote somewhere');

// ── Instagram ────────────────────────────────────────────────────────────────────────────────────────
Deno.test('instagram reel: core metrics in one call, in-development metrics one by one, refusals recorded not invented', async () => {
  const core = { data: IG_REELS.map((name, i) => ({ name, period: 'lifetime', values: [{ value: (i + 1) * 10 }] })) };
  const { f, calls } = mock([
    [/\/17900001\?fields=media_product_type/, { media_product_type: 'REELS', media_type: 'VIDEO', id: '17900001' }],
    [/\/17900001\/insights\?metric=views,reach/, core],
    [/metric=ig_reels_avg_watch_time&/, { data: [{ name: 'ig_reels_avg_watch_time', values: [{ value: 5400 }] }] }],
    [/metric=ig_reels_video_view_total_time&/, { data: [{ name: 'ig_reels_video_view_total_time', values: [{ value: 810000 }] }] }],
    [/metric=reels_skip_rate&/, { error: { message: '(#100) metric[0] must be one of the following values', code: 100 } }, 400],
  ]);
  const r = await instagramMedia(f, ENV, '17900001');
  assertEquals(r.values.views, 10); assertEquals(r.values.reach, 20); assertEquals(r.values.saved, 30);
  assertEquals(r.values.shares, 40); assertEquals(r.values.total_interactions, 70);
  assertEquals(r.values.ig_reels_avg_watch_time, 5400); assertEquals(r.values.ig_reels_video_view_total_time, 810000);
  assert(!('reels_skip_rate' in r.values)); assert(r.unavailable.reels_skip_rate.includes('#100'));
  assert(r.unavailable.completion_rate, 'completion must be named unavailable on Instagram');
  assert(!('plays' in r.values) && !('impressions' in r.values), 'a retired metric was read');
  onlyGets(calls);
});

Deno.test('instagram feed post: the feed metric set, total_value shape read too', async () => {
  const { f } = mock([
    [/\/17900002\?fields=media_product_type/, { media_product_type: 'FEED', media_type: 'IMAGE' }],
    [/\/17900002\/insights\?metric=views,reach,saved,shares,likes,comments,total_interactions,follows,profile_visits&/,
      { data: IG_FEED.map((name) => ({ name, total_value: { value: 3 } })) }],
  ]);
  const r = await instagramMedia(f, ENV, '17900002');
  assertEquals(Object.keys(r.values).sort(), [...IG_FEED].sort());
  assert(!('ig_reels_avg_watch_time' in r.values));
});

Deno.test('instagram: a whole refusal (permission) leaves every metric named unavailable, no numbers', async () => {
  const { f } = mock([
    [/\/17900003\?fields=media_product_type/, { media_product_type: 'FEED' }],
    [/\/17900003\/insights/, { error: { message: '(#10) Application does not have permission for this action' } }, 403],
  ]);
  const r = await instagramMedia(f, ENV, '17900003');
  assertEquals(r.values, {});
  for (const m of IG_FEED) assert(r.unavailable[m].includes('permission'));
});

Deno.test('instagram: a media id is found from Postiz\'s release URL by permalink', async () => {
  const { f } = mock([[/\/1784\/media\?fields=id,permalink/, { data: [{ id: '1', permalink: 'https://www.instagram.com/reel/AAA/' }, { id: '2', permalink: 'https://www.instagram.com/reel/BBB/' }] }]]);
  assertEquals(await igMediaIdByPermalink(f, ENV, '1784', 'https://www.instagram.com/reel/BBB'), '2');
  assertEquals(await igMediaIdByPermalink(f, ENV, '1784', 'https://www.instagram.com/reel/ZZZ'), null);
});

// ── Facebook ─────────────────────────────────────────────────────────────────────────────────────────
Deno.test('facebook reel/video: video_insights read with the PAGE token, completion rate derived', async () => {
  const { f, calls } = mock([
    [/\/555\/video_insights\?metric=fb_reels_total_plays/, { data: [
      { name: 'fb_reels_total_plays', period: 'lifetime', values: [{ value: 900 }] },
      { name: 'post_video_avg_time_watched', period: 'lifetime', values: [{ value: 6100 }] },
      { name: 'post_video_social_actions', period: 'lifetime', values: [{ value: { share: 2 } }] },   // an object: skipped
    ] }],
    [/\/555\/video_insights\?metric=total_video_views/, { data: [
      { name: 'total_video_views', values: [{ value: 400 }] }, { name: 'total_video_complete_views', values: [{ value: 100 }] },
      { name: 'total_video_avg_time_watched', values: [{ value: 5000 }] },
    ] }],
  ]);
  const r = await facebookPost(f, ENV, '555', 'PAGETOKEN');
  assertEquals(r.values.fb_reels_total_plays, 900); assertEquals(r.values.total_video_views, 400);
  assertEquals(r.values.completion_rate, 0.25);
  assert(!('post_video_social_actions' in r.values));
  assert(calls.every((c) => c.url.includes('access_token=PAGETOKEN')), 'video insights need the page token');
});

Deno.test('facebook: a post that is not a video falls back to reactions, comments, shares', async () => {
  const { f } = mock([
    [/\/777_888\?fields=shares/, { shares: { count: 4 }, reactions: { summary: { total_count: 12 } }, comments: { summary: { total_count: 3 } } }],
  ]);
  const r = await facebookPost(f, ENV, '777_888', 'PT');
  assertEquals(r.values, { reactions: 12, comments: 3, shares: 4 });
  assert(r.unavailable.video.startsWith('not a video'));
});

// ── LinkedIn and X via Postiz ────────────────────────────────────────────────────────────────────────
Deno.test('linkedin / x: Postiz post analytics, latest point per label; {missing:true} is unavailable, not zero', async () => {
  const { f, calls } = mock([
    [/\/analytics\/post\/pz-li\?date=7/, [{ label: 'Impressions', data: [{ total: '120', date: '2026-09-21' }, { total: '310', date: '2026-09-22' }], percentageChange: 5 },
      { label: 'Clicks', data: [{ total: 9, date: '2026-09-22' }] }]],
    [/\/analytics\/post\/pz-x\?date=1/, { missing: true }],
  ]);
  const li = await viaPostiz(f, P, 'k', 'pz-li', 7);
  assertEquals(li.values, { impressions: 310, clicks: 9 });
  const x = await viaPostiz(f, P, 'k', 'pz-x', 1);
  assertEquals(x.values, {}); assert(x.unavailable['*'].includes('release id'));
  onlyGets(calls);
});

// ── the tie ──────────────────────────────────────────────────────────────────────────────────────────
Deno.test('the tie: Postiz post id -> platform and the platform\'s own id', async () => {
  const { f } = mock([[/\/posts\?startDate=/, { posts: [
    { id: 'pz-ig', integration: { providerIdentifier: 'instagram-standalone' }, releaseId: '17900001', releaseURL: 'https://www.instagram.com/reel/AAA/' },
    { id: 'pz-fb', integration: { providerIdentifier: 'facebook' }, releaseId: '555', releaseURL: 'https://facebook.com/555' },
    { id: 'pz-tt', integration: { providerIdentifier: 'tiktok' }, releaseId: 'x' },
    { id: 'pz-x', integration: { providerIdentifier: 'x' }, releaseId: 'missing', releaseURL: null },
  ] }]]);
  const r = await postizReleases(f, P, 'k', new Date(0), new Date());
  assertEquals(r.map((x) => [x.postiz_post_id, x.platform, x.platform_post_id]), [['pz-ig', 'instagram', '17900001'], ['pz-fb', 'facebook', '555'], ['pz-x', 'x', null]]);
  assertEquals(postizIdsOf({ postiz: [{ postId: 'pz-ig', integration: 'i' }, { id: 'pz-fb' }] }), ['pz-ig', 'pz-fb']);
  assertEquals([channelOf('linkedin-page'), channelOf('twitter'), channelOf('youtube')], ['linkedin', 'x', null]);
});

// ── attribution, end to end ──────────────────────────────────────────────────────────────────────────
Deno.test('UTM: our links carry platform, month and post; other sites and hand-made UTMs are untouched', () => {
  const t = 'Get three quotes: https://www.quotesdone.ae/supplier. Read more at https://example.com/x and https://quotesdone.ae/?utm_source=manual';
  const out = withUtm(t, 'linkedin', '2026-09', 'zz-demo-week1');
  assert(out.includes('https://www.quotesdone.ae/supplier?utm_source=linkedin&utm_medium=social&utm_campaign=2026-09&utm_content=zz-demo-week1.'), out);
  assert(out.includes('https://example.com/x '), 'another site was tagged');
  assert(out.includes('https://quotesdone.ae/?utm_source=manual'), 'a hand-made UTM was overwritten');
  assertEquals(campaignOf('2026-09-30T21:00:00Z'), '2026-10');   // Dubai is UTC+4
});

Deno.test('attribution end to end: the published payload\'s link, visited, becomes the registration\'s first touch naming the post', () => {
  const post: PublishInput = { id: 9, ingest_key: 'zz-demo-reel-1', text_en: 'ZZ DEMO — suppliers register at https://www.quotesdone.ae/supplier', text_ar: 'سجّلوا الآن',
    channels: ['facebook', 'x'], scheduled_at: '2026-09-22T08:00:00Z', is_demo: true, media: [] };
  const { payload } = buildPostizPayload(post, [{ id: 'i-fb', identifier: 'facebook' }, { id: 'i-x', identifier: 'x' }], []);
  const content = (payload.posts as any[]).map((p) => p.value[0].content as string);
  const link = content[0].match(/https:\/\/www\.quotesdone\.ae\/supplier\?\S+/)![0];
  assert(content[1].includes('utm_source=x&'), 'each channel names itself');
  // the visitor lands, the browser keeps the first touch, a later untagged visit does not overwrite it
  const mem = new Map<string, string>();
  const store = { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => void mem.set(k, v) };
  captureFirstTouch(link, store);
  captureFirstTouch('https://www.quotesdone.ae/?utm_source=instagram&utm_content=other', store);
  const kept = readFirstTouch(store)!;
  assertEquals([kept.utm_source, kept.utm_medium, kept.utm_campaign, kept.utm_content, kept.landing_path],
    ['facebook', 'social', '2026-09', 'zz-demo-reel-1', '/supplier']);
  assert(mem.has(FIRST_TOUCH_KEY) && !/@|phone|email/i.test(mem.get(FIRST_TOUCH_KEY)!), 'the kept touch carries personal data');
  // what create_company sends is exactly what fn_marketing_first_touch_record reads (utm_content = ingest_key)
  assertEquals(kept.utm_content, post.ingest_key);
});

Deno.test('first touch refuses what is not a tag', () => {
  assertEquals(touchFromUrl('https://www.quotesdone.ae/'), null);
  assertEquals(touchFromUrl('https://www.quotesdone.ae/?utm_source=<script>'), null);
  assertEquals(touchFromUrl('https://www.quotesdone.ae/?utm_source=li&utm_content=a%20b')!.utm_content, null);
});

// ── scorecard clock ──────────────────────────────────────────────────────────────────────────────────
Deno.test('scorecard periods: Monday is weekly, the 1st is last month\'s month-end, Asia/Dubai', () => {
  assertEquals(scorecardPeriods(new Date('2026-09-28T06:00:00Z')), [{ kind: 'weekly', period_key: '2026-W40', month: '2026-09' }]);
  assertEquals(scorecardPeriods(new Date('2026-09-30T21:00:00Z')), [{ kind: 'month_end', period_key: '2026-09-end', month: '2026-09' }]);   // 1 Oct 01:00 Dubai
  assertEquals(scorecardPeriods(new Date('2026-09-23T10:00:00Z')), []);
  assertEquals(scorecardPeriods(new Date('2026-12-28T06:00:00Z'))[0].period_key, '2026-W53');
});
