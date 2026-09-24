// What each channel did after a post went to Postiz, against RECORDED Postiz answers (marketing + it_engineer,
// 24 Sep 2026). No network.
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/marketing_channel_results.test.ts
// The shapes are Postiz's public API as its source defines them (GET /public/v1/posts: state, releaseURL,
// releaseId, publishDate, integration.providerIdentifier; GET /public/v1/notifications: {notifications:[{id,
// content, link, createdAt}], hasMore}) and the notification texts of its post workflow.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  attributeNotes, classifyChannel, findingItems, noteChannel, overallOutcome, postizIdByChannel, readPostizNotifications, readPostizPosts,
  skippedByChannel, sqlPending, type ChannelResult, type StoredChannel,
} from './marketing_channel_results.ts';
import type { Fetch, Platform } from './marketing_post_results.ts';

const P = 'https://postiz.example.invalid/public/v1';
const SENT = new Date('2026-09-24T13:30:00Z');
const NOW = new Date('2026-09-24T15:00:00Z');
const YT_URL = 'https://www.youtube.com/watch?v=ZZdemo00001';
const IG_URL = 'https://www.instagram.com/reel/ZZdemo00002/';
const iso = (d: Date, minutes = 0) => new Date(d.getTime() + minutes * 60_000).toISOString();

function mock(routes: Array<[RegExp, unknown, number?]>): { f: Fetch; calls: { method: string; url: string }[] } {
  const calls: { method: string; url: string }[] = [];
  const f: Fetch = (url, init) => {
    calls.push({ method: init?.method || 'GET', url });
    for (const [re, body, status] of routes) if (re.test(url)) return Promise.resolve(new Response(JSON.stringify(body), { status: status ?? 200 }));
    return Promise.resolve(new Response('{"message":"no mock"}', { status: 404 }));
  };
  return { f, calls };
}
const post = (id: string, identifier: string, state: string, releaseURL: string | null = null, releaseId: string | null = null, publishDate = SENT.toISOString()) =>
  ({ id, content: '<p>ZZ DEMO caption</p>', publishDate, releaseURL, releaseId, state, group: 'g-' + id, settings: '{}',
     integration: { id: 'int-' + identifier, providerIdentifier: identifier, name: 'QuotesDone', picture: '' } });
const note = (id: string, content: string, at: string, link: string | null = null) => ({ id, content, link, createdAt: at });

// Our post: YouTube + Instagram + Facebook, the ids POST /posts returned.
const POSTIZ_RESULT = { channels: { youtube: 'youtube', instagram: 'instagram-standalone', facebook: 'facebook' }, skipped: [],
  postiz: [{ postId: 'pz-yt', integration: 'int-youtube' }, { postId: 'pz-ig', integration: 'int-instagram-standalone' }, { postId: 'pz-fb', integration: 'int-facebook' }] };
const CHANNELS: Platform[] = ['youtube', 'instagram', 'facebook'];
const one = (id: string, ch: string) => ({ channels: { [ch]: ch }, skipped: [], postiz: [{ postId: id }] });

/** The whole read + classify for one post, as channelResults in marketing_channels/index.ts does it. */
async function run(posts: unknown[], notifications: unknown[], postizResult: any = POSTIZ_RESULT, channels = CHANNELS, now = NOW, sent = SENT) {
  const { f, calls } = mock([[/\/posts\?startDate=/, { posts }], [/\/notifications\?page=0/, { notifications, total: notifications.length, page: 0, limit: 100, hasMore: false }]]);
  const listed = await readPostizPosts(f, P, 'k', new Date(sent.getTime() - 86400_000), new Date(now.getTime() + 86400_000));
  const notes = await readPostizNotifications(f, P, 'k', new Date(sent.getTime() - 600_000));
  assert(listed.ok && notes.ok);
  assertEquals(calls.filter((c) => c.method !== 'GET'), [], 'reading results must never write to Postiz');
  const credited = attributeNotes(notes.notes, listed.posts.values());
  const ids = postizIdByChannel(postizResult, listed.posts);
  const skipped = skippedByChannel(postizResult.skipped);
  const rows: ChannelResult[] = channels.map((ch) => {
    const id = ids[ch];
    return classifyChannel({ channel: ch, postizPostId: id ?? null, skipped: id ? null : skipped[ch] ?? null, post: id ? listed.posts.get(id) ?? null : null,
      notes: id ? credited.mine.get(id) ?? [] : [], ambiguous: id ? credited.ambiguous.get(id) ?? [] : [],
      ageHours: (now.getTime() - sent.getTime()) / 3600_000 });
  });
  return { rows, outcome: overallOutcome(rows.map((r) => r.state)) };
}
const stored = (rows: ChannelResult[], postId = 86, key = 'zz-demo-m1-09'): StoredChannel[] => rows.map((r) => ({ ...r, post_id: postId, ingest_key: key }));
const by = (rows: ChannelResult[], ch: Platform) => rows.find((r) => r.channel === ch)!;

Deno.test('every channel published and nothing reported: the post is published and files nothing', async () => {
  const { rows, outcome } = await run(
    [post('pz-yt', 'youtube', 'PUBLISHED', YT_URL, 'ZZdemo00001'), post('pz-ig', 'instagram-standalone', 'PUBLISHED', IG_URL, '17900001'), post('pz-fb', 'facebook', 'PUBLISHED', 'https://www.facebook.com/1/posts/2', '2')],
    [note('n1', `Your post has been published on Youtube at ${YT_URL}`, iso(SENT, 1)),
     note('n2', `Your post has been published on Instagram-standalone at ${IG_URL}`, iso(SENT, 2))]);
  assertEquals(rows.map((r) => r.state), ['published', 'published', 'published']);
  assertEquals(by(rows, 'youtube').release_url, YT_URL);
  assertEquals(outcome, 'published');
  assertEquals(findingItems(stored(rows)), []);
});

Deno.test('YouTube: the video went up but the thumbnail was not set -> partial, one finding keyed youtube:thumbnail_not_set', async () => {
  // Postiz's YouTube provider sets the thumbnail after the upload with no try/catch: the post is ERROR, no releaseURL.
  const { rows, outcome } = await run(
    [post('pz-yt', 'youtube', 'ERROR', null, 'ZZdemo00001'), post('pz-ig', 'instagram-standalone', 'PUBLISHED', IG_URL), post('pz-fb', 'facebook', 'PUBLISHED', 'https://www.facebook.com/1/posts/2')],
    [note('n3', 'An error occurred while posting on youtube: thumbnail not set (The authenticated user must be verified to set custom thumbnails)', iso(SENT, 2))]);
  const yt = by(rows, 'youtube');
  assertEquals(yt.state, 'partial');
  assertEquals(yt.cause, 'thumbnail_not_set');
  assert(/thumbnail not set/.test(yt.platform_message!), 'the platform message is kept');
  assertEquals(by(rows, 'instagram').state, 'published');
  assertEquals(outcome, 'partial');
  const items = findingItems(stored(rows));
  assertEquals(items.map((i) => i.item), ['youtube:thumbnail_not_set']);
  assertEquals(items[0].owner_seat, 'marketing', 'marketing owns the post and has the handoff kind fn_it_loop_open routes by');
  assertEquals(items[0].evidence.post_ids, [86]);
  assert(/Youtube thumbnail not set on 1 post\(s\) \(zz-demo-m1-09\): .*thumbnail not set/.test(items[0].title));
});

Deno.test('PUBLISHED with a failed first comment (sub-step) is partial, never published', async () => {
  const { rows } = await run([post('pz-yt', 'youtube', 'PUBLISHED', YT_URL)],
    [note('n10', `Your post has been published on Youtube at ${YT_URL}`, iso(SENT, 1)),
     note('n11', 'Error posting comments on youtube for QuotesDone', iso(SENT, 2))], one('pz-yt', 'youtube'), ['youtube']);
  assertEquals(rows[0].state, 'partial');
  assertEquals(rows[0].cause, 'comment_failed');
  assertEquals(rows[0].release_url, YT_URL);
});

Deno.test('instruction 997: a platform lowering resolution / frame rate is partial, cause quality_degraded', async () => {
  const { rows } = await run([post('pz-ig', 'instagram-standalone', 'ERROR', IG_URL)],
    [note('n5', 'An error occurred while posting on instagram-standalone: video was downscaled to 720x1280 at 30 fps', iso(SENT, 3))],
    one('pz-ig', 'instagram-standalone'), ['instagram']);
  assertEquals(rows[0].state, 'partial');
  assertEquals(rows[0].cause, 'quality_degraded');
});

Deno.test('one channel errors outright, the others publish -> that channel failed, the post partial', async () => {
  const { rows, outcome } = await run(
    [post('pz-yt', 'youtube', 'PUBLISHED', YT_URL), post('pz-ig', 'instagram-standalone', 'PUBLISHED', IG_URL), post('pz-fb', 'facebook', 'ERROR')],
    [note('n6', 'An error occurred while posting on facebook: (#200) The user hasn\'t authorized the application to perform this action', iso(SENT, 1))]);
  assertEquals(by(rows, 'facebook').state, 'failed');
  assert(/#200/.test(by(rows, 'facebook').platform_message!));
  assertEquals(outcome, 'partial');
  assertEquals(findingItems(stored(rows)).map((i) => i.item), ['facebook:error']);
});

Deno.test('a channel our send skipped (not connected) is failed, cause not_connected', async () => {
  const pr = { channels: { youtube: 'youtube' }, skipped: ['tiktok (not connected in Postiz)'], postiz: [{ postId: 'pz-yt' }] };
  const { rows, outcome } = await run([post('pz-yt', 'youtube', 'PUBLISHED', YT_URL)], [], pr, ['youtube', 'tiktok']);
  assertEquals(by(rows, 'tiktok').state, 'failed');
  assertEquals(by(rows, 'tiktok').cause, 'not_connected');
  assertEquals(outcome, 'partial');
});

Deno.test('every channel errors -> the post failed, one finding per channel + cause', async () => {
  const { rows, outcome } = await run(
    [post('pz-yt', 'youtube', 'ERROR'), post('pz-ig', 'instagram-standalone', 'ERROR'), post('pz-fb', 'facebook', 'ERROR')],
    [note('n7', 'We couldn\'t post to youtube for QuotesDone because you need to reconnect it. Please enable it and try again.', iso(SENT, 1)),
     note('n8', 'An error occurred while posting on instagram-standalone: Media upload failed', iso(SENT, 1))]);
  assertEquals(rows.map((r) => r.state), ['failed', 'failed', 'failed']);
  assertEquals(outcome, 'failed');
  assertEquals(findingItems(stored(rows)).map((i) => i.item), ['facebook:error', 'instagram:error', 'youtube:channel_disconnected']);
});

Deno.test('Postiz still publishing: pending inside 48 hours, failed (never_published) after', async () => {
  const q = [post('pz-yt', 'youtube', 'QUEUE')];
  const early = await run(q, [], one('pz-yt', 'youtube'), ['youtube']);
  assertEquals(early.rows[0].state, 'pending');
  assertEquals(early.outcome, 'pending');
  assertEquals(findingItems(stored(early.rows)), [], 'a channel still publishing is not a finding');
  const late = await run(q, [], one('pz-yt', 'youtube'), ['youtube'], new Date(SENT.getTime() + 49 * 3600_000));
  assertEquals(late.rows[0].state, 'failed');
  assertEquals(late.rows[0].cause, 'never_published');
});

Deno.test('one ongoing cause on two posts is ONE finding listing both; a re-check refiles the same key; fixed -> gone', async () => {
  const thumb = (id: string) => note('t-' + id, 'An error occurred while posting on youtube: thumbnail not set', iso(SENT, 2));
  const a = await run([post('pz-yt', 'youtube', 'ERROR', null, 'ZZdemo00001')], [thumb('a')], one('pz-yt', 'youtube'), ['youtube']);
  const both = [...stored(a.rows, 86, 'zz-demo-a'), ...stored(a.rows, 91, 'zz-demo-b')];
  const k1 = findingItems(both);
  assertEquals(k1.map((i) => i.item), ['youtube:thumbnail_not_set'], 'not a finding (and a handoff) per post');
  assertEquals(k1[0].evidence.post_ids, [86, 91]);
  assertEquals(k1[0].affected, 2);
  const again = await run([post('pz-yt', 'youtube', 'ERROR', null, 'ZZdemo00001')], [thumb('a')], one('pz-yt', 'youtube'), ['youtube'], new Date(NOW.getTime() + 30 * 60_000));
  assertEquals(findingItems(stored(again.rows)).map((i) => i.item), ['youtube:thumbnail_not_set'], 'fn_it_duty_settle upserts the same key');
  // Fixed in Postiz (republished): PUBLISHED with its URL; the old error note is still listed, the newer success supersedes it.
  const fixed = await run([post('pz-yt', 'youtube', 'PUBLISHED', YT_URL)], [note('n9', `Your post has been published on Youtube at ${YT_URL}`, iso(SENT, 150)), thumb('a')],
    one('pz-yt', 'youtube'), ['youtube']);
  assertEquals(fixed.rows[0].state, 'published');
  assertEquals(findingItems(stored(fixed.rows)), [], 'absent from the items, so fn_it_duty_settle closes it');
});

Deno.test('two posts a day apart: an error arriving after B was sent never marks B partial', async () => {
  const B_SENT = new Date(SENT.getTime() + 24 * 3600_000);
  const B_URL = 'https://www.youtube.com/watch?v=ZZdemo00002';
  const posts = [post('pz-a', 'youtube', 'ERROR', null, null, SENT.toISOString()), post('pz-b', 'youtube', 'PUBLISHED', B_URL, 'ZZdemo00002', B_SENT.toISOString())];
  const notes = [note('b1', `Your post has been published on Youtube at ${B_URL}`, iso(B_SENT, 1)),
                 note('late', 'An error occurred while posting on youtube: quota exceeded', iso(B_SENT, 20))];
  const b = await run(posts, notes, one('pz-b', 'youtube'), ['youtube'], new Date(B_SENT.getTime() + 3600_000), B_SENT);
  assertEquals(b.rows[0].state, 'published', 'B is PUBLISHED in Postiz: an error note is never credited to it');
  assertEquals(b.rows[0].platform_message, null);
  const a = await run(posts, notes, one('pz-a', 'youtube'), ['youtube'], new Date(B_SENT.getTime() + 3600_000), SENT);
  assertEquals(a.rows[0].state, 'failed', 'A is ERROR by Postiz; the note arrived 24h later, past the 6h reach, so it is not A\'s either');
  assert(!/quota/.test(a.rows[0].platform_message || ''));
});

Deno.test('an ambiguous note (two ERROR posts on the channel inside 6h) is a message, never a verdict or a finding', async () => {
  const posts = [post('pz-a', 'youtube', 'ERROR', null, null, SENT.toISOString()), post('pz-b', 'youtube', 'ERROR', null, null, iso(SENT, 120))];
  const notes = [note('amb', 'An error occurred while posting on youtube: thumbnail not set', iso(SENT, 125))];
  const credited = attributeNotes(notes, (await readPostizPosts(mock([[/\/posts/, { posts }]]).f, P, 'k', SENT, NOW)).posts.values());
  assertEquals(credited.mine.size, 0);
  assertEquals([...credited.ambiguous.keys()].sort(), ['pz-a', 'pz-b']);
  const a = await run(posts, notes, one('pz-a', 'youtube'), ['youtube']);
  assertEquals(a.rows[0].state, 'failed', 'ERROR stays authoritative; the ambiguous thumbnail note cannot choose partial');
  assertEquals(a.rows[0].cause, 'error', 'nor name the cause');
  assert(/^Postiz marked this post ERROR|ambiguous/.test(a.rows[0].platform_message!), 'kept as a message');
  // PUBLISHED + an ambiguous comment note: stays published
  const pub = [post('pz-a', 'youtube', 'PUBLISHED', YT_URL, null, SENT.toISOString()), post('pz-b', 'youtube', 'PUBLISHED', null, null, iso(SENT, 60))];
  const p2 = await run(pub, [note('c', 'Error posting comments on youtube for QuotesDone', iso(SENT, 90))], one('pz-a', 'youtube'), ['youtube']);
  assertEquals(p2.rows[0].state, 'published');
  assert(/ambiguous/.test(p2.rows[0].platform_message!));
  assertEquals(findingItems(stored(p2.rows)), []);
});

Deno.test('a post made in Postiz\'s own UI takes its own notes: ours is judged on ours alone', async () => {
  // pz-ui is not ours (no marketing_post row) but is in GET /posts; its error comes 3h after our post was sent.
  const posts = [post('pz-yt', 'youtube', 'ERROR', null, 'ZZdemo00001', SENT.toISOString()), post('pz-ui', 'youtube', 'ERROR', null, null, iso(SENT, 180))];
  const notes = [note('ours', 'An error occurred while posting on youtube: thumbnail not set', iso(SENT, 2)),
                 note('ui', 'An error occurred while posting on youtube: The request cannot be completed because you have exceeded your quota', iso(SENT, 183))];
  const { rows } = await run(posts, notes, one('pz-yt', 'youtube'), ['youtube']);
  assertEquals(rows[0].state, 'partial');
  assertEquals(rows[0].cause, 'thumbnail_not_set');
  // Had only our posts been considered, the quota note would be credited to ours outright. With the UI post in the
  // span it is ambiguous: kept after the 'ambiguous' marker, never in what decided ours.
  const [decided, amb] = rows[0].platform_message!.split(' | ambiguous');
  assert(!/quota/.test(decided), 'the UI post\'s error was credited to our post');
  assert(/quota/.test(amb || ''), 'the ambiguous note is still kept as a message');
});

Deno.test('matching precision: exact URLs, and only the channel in the prefix', () => {
  const posts = [{ id: 'p2', state: 'PUBLISHED', releaseURL: 'https://www.facebook.com/1/posts/2', releaseId: '2', identifier: 'facebook', integrationId: null, publishDate: SENT.toISOString(), error: null },
                 { id: 'p23', state: 'PUBLISHED', releaseURL: 'https://www.facebook.com/1/posts/23', releaseId: '23', identifier: 'facebook', integrationId: null, publishDate: SENT.toISOString(), error: null }];
  const c = attributeNotes([note('s', 'Your post has been published on Facebook at https://www.facebook.com/1/posts/23', iso(SENT, 1))], posts);
  assertEquals([...c.mine.keys()], ['p23'], '/posts/2 must not match /posts/23');
  assertEquals(noteChannel(note('x', 'An error occurred while posting on youtube: link to instagram and facebook invalid', iso(SENT))), 'youtube');
  assertEquals(noteChannel(note('y', 'Weekly digest: instagram grew', iso(SENT))), null, 'a note with no workflow prefix names no channel');
});

Deno.test('truncated notifications: 3 full pages newer than since -> truncated with the oldest read', async () => {
  const page = (p: number) => ({ notifications: Array.from({ length: 100 }, (_, i) => note(`n${p}-${i}`, 'Your post has been published on Facebook at https://x.example/' + i, iso(NOW, -(p * 100 + i)))), hasMore: true });
  const { f } = mock([[/page=0/, page(0)], [/page=1/, page(1)], [/page=2/, page(2)]]);
  const r = await readPostizNotifications(f, P, 'k', new Date(NOW.getTime() - 48 * 3600_000));
  assertEquals(r.truncated, true);
  assertEquals(r.oldestRead!.toISOString(), iso(NOW, -299));
  // the duty holds back every post sent before r.oldestRead (marketing_channels channelResults: heldBack)
  const covered = await readPostizNotifications(f, P, 'k', new Date(NOW.getTime() - 60 * 60_000));
  assertEquals(covered.truncated, false, 'the first page already reaches back past since');
});

Deno.test('deploy order: the SQL not applied yet is a skip, not a failing beat', () => {
  for (const code of ['PGRST202', 'PGRST205', '42883', '42P01']) assert(sqlPending({ code }), code);
  assert(!sqlPending({ code: '23514' }), 'a real error is still an error');
  assert(!sqlPending(null));
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
