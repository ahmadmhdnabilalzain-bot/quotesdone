// What each channel did after a post went to Postiz, against RECORDED Postiz answers (marketing + it_engineer,
// 24 Sep 2026). No network.
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/marketing_channel_results.test.ts
// The shapes are Postiz's public API as its source defines them (GET /public/v1/posts: state, releaseURL,
// releaseId, integration.providerIdentifier; GET /public/v1/notifications: {notifications:[{id, content, link,
// createdAt}], hasMore}) and the notification texts of its post workflow. Ids are the ones production's posts
// 84-87 carry, so a replay reads like the real month.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  classifyChannel, findingItems, notesFor, overallOutcome, postizIdByChannel, readPostizNotifications, readPostizPosts, skippedByChannel,
  type ChannelResult, type StoredChannel,
} from './marketing_channel_results.ts';
import type { Fetch, Platform } from './marketing_post_results.ts';

const P = 'https://postiz.example.invalid/public/v1';
const SENT = new Date('2026-09-24T13:30:00Z');
const NOW = new Date('2026-09-24T15:00:00Z');
const YT_URL = 'https://www.youtube.com/watch?v=ZZdemo00001';
const IG_URL = 'https://www.instagram.com/reel/ZZdemo00002/';

function mock(routes: Array<[RegExp, unknown, number?]>): { f: Fetch; calls: { method: string; url: string }[] } {
  const calls: { method: string; url: string }[] = [];
  const f: Fetch = (url, init) => {
    calls.push({ method: init?.method || 'GET', url });
    for (const [re, body, status] of routes) if (re.test(url)) return Promise.resolve(new Response(JSON.stringify(body), { status: status ?? 200 }));
    return Promise.resolve(new Response('{"message":"no mock"}', { status: 404 }));
  };
  return { f, calls };
}
const post = (id: string, identifier: string, state: string, releaseURL: string | null = null, releaseId: string | null = null) =>
  ({ id, content: '<p>ZZ DEMO caption</p>', publishDate: SENT.toISOString(), releaseURL, releaseId, state, group: 'g1', settings: '{}',
     integration: { id: 'int-' + identifier, providerIdentifier: identifier, name: 'QuotesDone', picture: '' } });
const note = (id: string, content: string, at: string, link: string | null = null) => ({ id, content, link, createdAt: at });

// Our post: YouTube + Instagram + Facebook, the ids POST /posts returned.
const POSTIZ_RESULT = { channels: { youtube: 'youtube', instagram: 'instagram-standalone', facebook: 'facebook' }, skipped: [],
  postiz: [{ postId: 'pz-yt', integration: 'int-youtube' }, { postId: 'pz-ig', integration: 'int-instagram-standalone' }, { postId: 'pz-fb', integration: 'int-facebook' }] };
const CHANNELS: Platform[] = ['youtube', 'instagram', 'facebook'];

/** The whole read + classify for one post, as channelResults in marketing_channels/index.ts does it. */
async function run(posts: unknown[], notifications: unknown[], postizResult: any = POSTIZ_RESULT, channels = CHANNELS, now = NOW) {
  const { f, calls } = mock([[/\/posts\?startDate=/, { posts }], [/\/notifications\?page=0/, { notifications, total: notifications.length, page: 0, limit: 100, hasMore: false }]]);
  const listed = await readPostizPosts(f, P, 'k', new Date(SENT.getTime() - 86400_000), new Date(now.getTime() + 86400_000));
  const notes = await readPostizNotifications(f, P, 'k', new Date(SENT.getTime() - 600_000));
  assert(listed.ok && notes.ok);
  assertEquals(calls.filter((c) => c.method !== 'GET'), [], 'reading results must never write to Postiz');
  const ids = postizIdByChannel(postizResult, listed.posts);
  const skipped = skippedByChannel(postizResult.skipped);
  const urls = [...listed.posts.values()].map((x) => x.releaseURL).filter((u): u is string => !!u);
  const rows: ChannelResult[] = channels.map((ch) => {
    const pz = ids[ch] ? listed.posts.get(ids[ch]!) ?? null : null;
    return classifyChannel({ channel: ch, postizPostId: ids[ch] ?? null, skipped: ids[ch] ? null : skipped[ch] ?? null, post: pz,
      notes: notesFor(notes.notes, ch, new Date(SENT.getTime() - 300_000), new Date(SENT.getTime() + 48 * 3600_000), pz?.releaseURL ?? null, urls.filter((u) => u !== pz?.releaseURL)),
      ageHours: (now.getTime() - SENT.getTime()) / 3600_000 });
  });
  return { rows, outcome: overallOutcome(rows.map((r) => r.state)) };
}
const stored = (rows: ChannelResult[], postId = 86): StoredChannel[] => rows.map((r) => ({ ...r, post_id: postId, ingest_key: 'zz-demo-m1-09' }));
const by = (rows: ChannelResult[], ch: Platform) => rows.find((r) => r.channel === ch)!;

Deno.test('every channel published and nothing reported: the post is published and files nothing', async () => {
  const { rows, outcome } = await run(
    [post('pz-yt', 'youtube', 'PUBLISHED', YT_URL, 'ZZdemo00001'), post('pz-ig', 'instagram-standalone', 'PUBLISHED', IG_URL, '17900001'), post('pz-fb', 'facebook', 'PUBLISHED', 'https://www.facebook.com/1/posts/2', '2')],
    [note('n1', `Your post has been published on Youtube at ${YT_URL}`, '2026-09-24T13:31:10Z'),
     note('n2', `Your post has been published on Instagram-standalone at ${IG_URL}`, '2026-09-24T13:31:40Z')]);
  assertEquals(rows.map((r) => r.state), ['published', 'published', 'published']);
  assertEquals(by(rows, 'youtube').release_url, YT_URL);
  assertEquals(outcome, 'published');
  assertEquals(findingItems(stored(rows)), []);
});

Deno.test('YouTube: the video went up but the thumbnail was not set -> partial, one it_engineer finding with the message', async () => {
  // Postiz's YouTube provider sets the thumbnail after the upload with no try/catch: the post is ERROR, no releaseURL.
  const { rows, outcome } = await run(
    [post('pz-yt', 'youtube', 'ERROR', null, 'ZZdemo00001'), post('pz-ig', 'instagram-standalone', 'PUBLISHED', IG_URL), post('pz-fb', 'facebook', 'PUBLISHED', 'https://www.facebook.com/1/posts/2')],
    [note('n3', 'An error occurred while posting on youtube: thumbnail not set (The authenticated user must be verified to set custom thumbnails)', '2026-09-24T13:32:00Z')]);
  const yt = by(rows, 'youtube');
  assertEquals(yt.state, 'partial');
  assert(/thumbnail not set/.test(yt.platform_message!), 'the platform message is kept');
  assertEquals(by(rows, 'instagram').state, 'published');
  assertEquals(outcome, 'partial');
  const items = findingItems(stored(rows));
  assertEquals(items.length, 1);
  assertEquals(items[0].item, 'post:86:youtube');
  assertEquals(items[0].owner_seat, 'it_engineer');
  assert(/Youtube published only partly for post zz-demo-m1-09: .*thumbnail not set/.test(items[0].title));
  assertEquals(items[0].evidence.channel, 'youtube');
});

Deno.test('YouTube PUBLISHED with a thumbnail complaint is still partial, never published', async () => {
  const { rows } = await run([post('pz-yt', 'youtube', 'PUBLISHED', YT_URL)], [note('n4', 'An error occurred while posting on youtube: thumbnail not set', '2026-09-24T13:32:00Z')],
    { channels: { youtube: 'youtube' }, skipped: [], postiz: [{ postId: 'pz-yt' }] }, ['youtube']);
  assertEquals(rows[0].state, 'partial');
  assertEquals(rows[0].release_url, YT_URL);
});

Deno.test('instruction 997: a platform lowering resolution / frame rate is partial', async () => {
  const { rows } = await run([post('pz-ig', 'instagram-standalone', 'ERROR', IG_URL)],
    [note('n5', 'An error occurred while posting on instagram-standalone: video was downscaled to 720x1280 at 30 fps', '2026-09-24T13:33:00Z')],
    { channels: { instagram: 'instagram-standalone' }, skipped: [], postiz: [{ postId: 'pz-ig' }] }, ['instagram']);
  assertEquals(rows[0].state, 'partial');
});

Deno.test('one channel errors outright, the others publish -> that channel failed, the post partial', async () => {
  const { rows, outcome } = await run(
    [post('pz-yt', 'youtube', 'PUBLISHED', YT_URL), post('pz-ig', 'instagram-standalone', 'PUBLISHED', IG_URL), post('pz-fb', 'facebook', 'ERROR')],
    [note('n6', 'An error occurred while posting on facebook: (#200) The user hasn\'t authorized the application to perform this action', '2026-09-24T13:31:00Z')]);
  assertEquals(by(rows, 'facebook').state, 'failed');
  assert(/#200/.test(by(rows, 'facebook').platform_message!));
  assertEquals(outcome, 'partial');
  assertEquals(findingItems(stored(rows)).map((i) => i.item), ['post:86:facebook']);
});

Deno.test('a channel our send skipped (not connected) is failed, not silently absent', async () => {
  const pr = { channels: { youtube: 'youtube' }, skipped: ['tiktok (not connected in Postiz)'], postiz: [{ postId: 'pz-yt' }] };
  const { rows, outcome } = await run([post('pz-yt', 'youtube', 'PUBLISHED', YT_URL)], [], pr, ['youtube', 'tiktok']);
  assertEquals(by(rows, 'tiktok').state, 'failed');
  assert(/not connected in Postiz/.test(by(rows, 'tiktok').platform_message!));
  assertEquals(outcome, 'partial');
});

Deno.test('every channel errors -> the post failed, one finding per channel', async () => {
  const { rows, outcome } = await run(
    [post('pz-yt', 'youtube', 'ERROR'), post('pz-ig', 'instagram-standalone', 'ERROR'), post('pz-fb', 'facebook', 'ERROR')],
    [note('n7', 'We couldn\'t post to youtube for QuotesDone because you need to reconnect it. Please enable it and try again.', '2026-09-24T13:31:00Z'),
     note('n8', 'An error occurred while posting on instagram-standalone: Media upload failed', '2026-09-24T13:31:00Z')]);
  assertEquals(rows.map((r) => r.state), ['failed', 'failed', 'failed']);
  assertEquals(outcome, 'failed');
  assertEquals(findingItems(stored(rows)).map((i) => i.item), ['post:86:youtube', 'post:86:instagram', 'post:86:facebook']);
});

Deno.test('Postiz still publishing: pending inside 48 hours, failed after', async () => {
  const q = [post('pz-yt', 'youtube', 'QUEUE')];
  const pr = { channels: { youtube: 'youtube' }, skipped: [], postiz: [{ postId: 'pz-yt' }] };
  const early = await run(q, [], pr, ['youtube']);
  assertEquals(early.rows[0].state, 'pending');
  assertEquals(early.outcome, 'pending');
  assertEquals(findingItems(stored(early.rows)), [], 'a channel still publishing is not a finding');
  const late = await run(q, [], pr, ['youtube'], new Date(SENT.getTime() + 49 * 3600_000));
  assertEquals(late.rows[0].state, 'failed');
});

Deno.test('idempotent: a re-check of the same partial channel refiles the SAME key; once fixed the key is gone (closed by the settle)', async () => {
  const bad = await run([post('pz-yt', 'youtube', 'ERROR', null, 'ZZdemo00001')], [note('n3', 'An error occurred while posting on youtube: thumbnail not set', '2026-09-24T13:32:00Z')],
    { channels: { youtube: 'youtube' }, skipped: [], postiz: [{ postId: 'pz-yt' }] }, ['youtube']);
  const again = await run([post('pz-yt', 'youtube', 'ERROR', null, 'ZZdemo00001')], [note('n3', 'An error occurred while posting on youtube: thumbnail not set', '2026-09-24T13:32:00Z')],
    { channels: { youtube: 'youtube' }, skipped: [], postiz: [{ postId: 'pz-yt' }] }, ['youtube'], new Date(NOW.getTime() + 30 * 60_000));
  const k1 = findingItems(stored(bad.rows)).map((i) => i.item), k2 = findingItems(stored(again.rows)).map((i) => i.item);
  assertEquals(k1, ['post:86:youtube']);
  assertEquals(k2, k1, 'one key per post-channel: fn_it_duty_settle upserts it, never a second finding');
  // Fixed in Postiz (republished / thumbnail re-applied): PUBLISHED with its URL and no complaint after it.
  // The old error notification is still in Postiz's list; the newer success supersedes it.
  const fixed = await run([post('pz-yt', 'youtube', 'PUBLISHED', YT_URL)], [note('n9', `Your post has been published on Youtube at ${YT_URL}`, '2026-09-24T16:00:00Z'),
    note('n3', 'An error occurred while posting on youtube: thumbnail not set', '2026-09-24T13:32:00Z')],
    { channels: { youtube: 'youtube' }, skipped: [], postiz: [{ postId: 'pz-yt' }] }, ['youtube']);
  assertEquals(fixed.rows[0].state, 'published');
  assertEquals(findingItems(stored(fixed.rows)), [], 'absent from the items, so fn_it_duty_settle closes it');
});

Deno.test('a comment failing AFTER the success note still makes the channel partial', async () => {
  const { rows } = await run([post('pz-yt', 'youtube', 'PUBLISHED', YT_URL)],
    [note('n10', `Your post has been published on Youtube at ${YT_URL}`, '2026-09-24T13:31:00Z'),
     note('n11', 'An error occurred while posting on youtube: comments are disabled for this video', '2026-09-24T13:31:30Z')],
    { channels: { youtube: 'youtube' }, skipped: [], postiz: [{ postId: 'pz-yt' }] }, ['youtube']);
  assertEquals(rows[0].state, 'partial');
});

Deno.test('a notification about ANOTHER post on the same channel is not ours', () => {
  const other = 'https://www.youtube.com/watch?v=ZZother0001';
  const notes = [note('a', `Your post has been published on Youtube at ${other}`, '2026-09-24T13:40:00Z'),
                 note('b', 'An error occurred while posting on youtube: quota exceeded', '2026-09-26T13:40:00Z'),
                 note('c', 'An error occurred while posting on facebook: nope', '2026-09-24T13:40:00Z')];
  const mine = notesFor(notes, 'youtube', SENT, new Date(SENT.getTime() + 24 * 3600_000), YT_URL, [other]);
  assertEquals(mine.map((n) => n.id), [], 'another post\'s URL, outside the window, or another channel');
});

Deno.test('Postiz unreadable is NOT an answer: ok=false, nothing to classify', async () => {
  const { f } = mock([[/\/posts\?startDate=/, { message: 'Unauthorized' }, 401]]);
  const r = await readPostizPosts(f, P, 'k', SENT, NOW);
  assertEquals(r.ok, false);
  assertEquals(r.posts.size, 0);
});

Deno.test('the post outcome rule', () => {
  assertEquals(overallOutcome(['published', 'published']), 'published');
  assertEquals(overallOutcome(['published', 'partial']), 'partial');
  assertEquals(overallOutcome(['published', 'failed']), 'partial');
  assertEquals(overallOutcome(['partial', 'failed']), 'partial');
  assertEquals(overallOutcome(['failed', 'failed']), 'failed');
  assertEquals(overallOutcome(['published', 'pending']), 'pending');
});
