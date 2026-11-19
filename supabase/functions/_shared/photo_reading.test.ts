// A CUSTOMER'S PHOTO IS READ ONCE, BY THE MODEL, AND NEVER CLAIMED WHEN IT WAS NOT (19 Nov 2026, sales_engineer; founder
// ruling 1200: "customer-facing agents must hold adaptive, expert conversations (e.g. custom wardrobe from a studio photo: ask
// dimensions, shelves vs hanging, ...)"). Offline: the gateway and the cache are stubs, no paid call is made.
//   1. ONE CALL PER PHOTO: the same bytes are read once; the second time the cache answers (keyed by the file's SHA-256).
//   2. THE READING IS SHORT AND STRUCTURED: what it is, the space, sizes as estimates, cues, materials, what is unclear, and
//      the next questions; anything that identifies a person or a place is dropped, never kept.
//   3. A FAILED READ IS NEVER CACHED and never told to the customer as read; the first ask says only what is true.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { seedTerms } from './anonymise.ts';
import { claimsPhotoSeen, firstAsk, parseReading, photoHash, photoPromptNote, photoRequest, PHOTO_ROUTE, readPhoto, readPhotos, readingsOf, unreadLead,
  type PhotoDeps } from './photo_reading.ts';

// A 1x1 JPEG-shaped data URL (the bytes are never decoded as an image here; only hashed and passed on).
const JPEG_A = 'data:image/jpeg;base64,' + btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 0xff, 0xd9));
const JPEG_B = 'data:image/jpeg;base64,' + btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xe0, 9, 9, 9, 0xff, 0xd9));
const WARDROBE = {
  item: 'an empty wall recess for a built-in wardrobe', space: 'a studio flat, sleeping corner',
  dimensions_seen: ['wall roughly 2.4-2.8 m wide, judged from the door beside it', 'ceiling about 2.7 m'],
  cues: ['a socket low on the left of the recess', 'skirting board along the wall'],
  materials: ['painted plaster wall', 'light oak-look floor'],
  unclear: ['the exact width, height and depth', 'shelves versus hanging space', 'door type', 'finish'],
  ask_next: ['How wide and how high is the wall, and how deep can the wardrobe be?', 'Do you want mostly shelves, mostly hanging space, or a mix?', 'Sliding or hinged doors?', 'What finish do you like?'],
  confidence: 'medium',
};
function deps(answer: (body: Record<string, unknown>) => { ok: boolean; content?: string; why?: string }) {
  const cache = new Map<string, string>();
  const asked: Record<string, unknown>[] = [];
  const d: PhotoDeps = {
    ask: async (body) => { asked.push(body); return answer(body); },
    cacheGet: async (k) => cache.get(k) ?? null,
    cachePut: async (k, v) => { cache.set(k, v); },
  };
  return { d, cache, asked };
}
const ok = () => ({ ok: true, content: JSON.stringify(WARDROBE) });

Deno.test('one vision call per photo: the same file is read once and then served from the cache by its hash', async () => {
  const { d, cache, asked } = deps(ok);
  const a = await readPhoto(d, JPEG_A, { lang: 'en' });
  assertEquals(a.status, 'read');
  assertEquals(asked.length, 1);
  const again = await readPhoto(d, JPEG_A, { lang: 'en' });
  assertEquals([again.status, again.status === 'read' && again.cached], ['read', true]);
  assertEquals(asked.length, 1, 'the same photo was paid for twice');
  assertEquals(cache.size, 1);
  assertMatch([...cache.keys()][0], /^photo_reading:v1:en:[0-9a-f]{64}$/);
  // a different file is a different call
  await readPhoto(d, JPEG_B, { lang: 'en' });
  assertEquals(asked.length, 2);
  // the hash is the file's, not the string's wrapping: the same bytes with another data URL prefix hash the same
  assertEquals(await photoHash(JPEG_A), await photoHash(JPEG_A.replace('image/jpeg', 'image/png')));
});

Deno.test('the request goes through the gateway on the sales engineer\'s reading route, with the photo as an image part and no identity', async () => {
  const body = photoRequest(JPEG_A, 'en', { email: 'zz-demo@example.invalid', customer_id: 'c-1' });
  assertEquals([body.fn, body.task_class], ['inquiry_intake', PHOTO_ROUTE]);
  assertEquals(PHOTO_ROUTE, 'sales_engineer__document_extraction', 'the route is the model matrix\'s reading class, never a model id');
  assert(!('model' in body), 'a model id was named by the caller');
  const content = ((body.input as { content: { type: string; image_url?: { url: string } }[] }[])[0]).content;
  assertEquals(content.map((c) => c.type), ['text', 'image_url']);
  assertEquals(content[1].image_url!.url, JPEG_A);
  const words = String(body.sys) + JSON.stringify(content[0]);
  assert(!/zz-demo@example\.invalid|c-1\b/.test(words), 'customer identity reached the prompt');
  assertMatch(String(body.sys), /NEVER write anything that identifies a person or a place/);
  assertEquals(photoRequest(JPEG_A, 'en', null, 'wa_inbound').fn, 'wa_inbound');
});

Deno.test('the reading: short fields kept, identity dropped, nothing invented', () => {
  const r = parseReading(JSON.stringify({ ...WARDROBE, cues: [...WARDROBE.cues, 'a sign reading Villa 23, Al Barsha', 'call 050 123 4567'], materials: ['x'.repeat(400)] }), ['ZZ DEMO Customer'])!;
  assert(r, 'a valid reading was refused');
  assertEquals(r.item, WARDROBE.item);
  assertEquals(r.cues, WARDROBE.cues, 'an identifying cue was kept: ' + JSON.stringify(r.cues));
  assert(r.materials.every((m) => m.length <= 160));
  assertEquals(r.ask_next.length, 4);
  // seeds (anonymise.seedTerms of the customer, as the callers pass them): the customer's own name is never kept
  assertEquals(parseReading(JSON.stringify({ ...WARDROBE, item: 'a wardrobe for Zaid Qasimi' }), seedTerms({ name: 'Zaid Qasimi', email: 'zz-demo@example.invalid' }))!.item, '');
  // nothing usable: not a reading
  assertEquals(parseReading('not json', []), null);
  assertEquals(parseReading(JSON.stringify({ item: '', unclear: [], ask_next: [] }), []), null);
});

Deno.test('a failed read is never cached, and says why', async () => {
  const { d, cache } = deps(() => ({ ok: false, why: 'http 502' }));
  const r = await readPhoto(d, JPEG_A, { lang: 'en' });
  assertEquals(r.status, 'failed');
  assertEquals(cache.size, 0, 'a failure was cached');
  const junk = deps(() => ({ ok: true, content: '{"answer":"ZZ DEMO noted"}' }));
  assertEquals((await readPhoto(junk.d, JPEG_A, { lang: 'en' })).status, 'failed');
  assertEquals(junk.cache.size, 0);
  // a thrown cache never stops the read, and a thrown gateway is a failure, not a crash
  const broken: PhotoDeps = { ask: async () => { throw new Error('boom'); }, cacheGet: async () => { throw new Error('x'); }, cachePut: async () => { throw new Error('y'); } };
  assertEquals((await readPhoto(broken, JPEG_A, { lang: 'en' })).status, 'failed');
});

Deno.test('a read slower than the wait is not waited for; it still lands in the cache for the next time', async () => {
  let release: () => void = () => {};
  const gate = new Promise<void>((r) => { release = r; });
  const cache = new Map<string, string>();
  const late: Promise<unknown>[] = [];
  const d: PhotoDeps = { ask: async () => { await gate; return ok(); }, cacheGet: async (k) => cache.get(k) ?? null, cachePut: async (k, v) => { cache.set(k, v); } };
  const reads = await readPhotos(d, [JPEG_A], { lang: 'en', waitMs: 20, keep: (p) => late.push(p) });
  assertEquals(reads.map((r) => [r.status, r.status === 'failed' && r.why]), [['failed', 'late']]);
  release(); await Promise.all(late);
  assertEquals(cache.size, 1, 'the late answer was thrown away');
});

Deno.test('the next question is about what the photo leaves open; an unread photo is never said to be read', () => {
  const read = [{ status: 'read' as const, hash: 'h', reading: parseReading(JSON.stringify(WARDROBE), [])!, cached: false }];
  const note = photoPromptNote(read, [], 'en');
  assertMatch(note, /built-in wardrobe/);
  assertMatch(note, /YOUR NEXT QUESTION/);
  assertMatch(note, /shelves, mostly hanging/);
  const failed = [{ status: 'failed' as const, hash: 'h', why: 'http 502' }];
  const unreadNote = photoPromptNote(failed, [], 'en');
  assertMatch(unreadNote, /could NOT be read/);
  assert(!/built-in wardrobe/.test(unreadNote));
  // an earlier turn's reading stays in the context; the failure of this turn is said once
  const turns = [{ role: 'assistant', text: 'x', photo_readings: [{ hash: 'h0', reading: WARDROBE }] }];
  assertEquals(readingsOf(turns).length, 1);
  assertMatch(photoPromptNote([], turns, 'en'), /built-in wardrobe/);
  // THE FIRST ASK (handle.ts plainAsk, 19 Nov 2026): what is true in each path
  const none = firstAsk([], 'en');
  assert(!/I will read the details off it for you instead of asking/.test(none), 'the old promise is back');
  assertMatch(none, /tell you if I cannot/);
  const seen = firstAsk(read, 'en');
  assertMatch(seen, /looked at your photo/); assertMatch(seen, /How wide and how high/); assertMatch(seen, /shelves/);
  const unread = firstAsk(failed, 'en');
  assertMatch(unread, /could not read the photo/);
  assert(!claimsPhotoSeen(unread), 'the unread ask claims a read: ' + unread);
  assertMatch(firstAsk(failed, 'ar'), /لم أتمكن من قراءة الصورة/);
  assertEquals(unreadLead([], 'en'), '');
  assertMatch(unreadLead(failed, 'en'), /could not read the photo/);
});

Deno.test('claimsPhotoSeen: a reply that says it saw the photo', () => {
  for (const t of ['I can see a recess in your photo.', 'Your photo shows a wall', 'From the photo, the wall looks 2.5 m wide.', 'I have looked at your photo.', 'Looking at the picture, it is a studio.', 'من الصورة يبدو أن الجدار عريض', 'اطلعت على صورتك'])
    assert(claimsPhotoSeen(t), t);
  for (const t of ['How wide is the wall?', 'I could not read the photo you sent; tell me what it shows.', 'If you have a photo, attach it.'])
    assert(!claimsPhotoSeen(t), t);
});
