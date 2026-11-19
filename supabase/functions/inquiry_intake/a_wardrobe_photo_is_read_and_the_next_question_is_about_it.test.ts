// A CUSTOM WARDROBE FROM A STUDIO PHOTO: THE PHOTO IS READ, AND THE NEXT QUESTION IS ABOUT WHAT IT SHOWS (19 Nov 2026,
// sales_engineer; founder ruling 1200: "customer-facing agents must hold adaptive, expert conversations (e.g. custom wardrobe
// from a studio photo: ask dimensions, shelves vs hanging, ...)").
//
// Drives the REAL inquiry_intake handler offline (twilio_free_harness: no network, no paid call). The gateway is a stub: the
// vision call answers a fixed reading of a studio wardrobe recess; the interview model is a stub that FOLLOWS ITS PROMPT (it
// asks the questions the prompt tells it to ask next, and nothing about the photo when the prompt carries none), so the
// question about dimensions and shelves versus hanging can only come from the reading reaching the interview.
// Red on main 2801b0522: inquiry_intake read no `images`, made no vision call, and its first ask promised "attach it and I
// will read the details off it for you instead of asking" whatever happened to a photo.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { PHOTO_ROUTE, claimsPhotoSeen, photoHash, cacheKey } from '../_shared/photo_reading.ts';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-photos-c1@example.invalid';
const II = '00000000-0000-4000-8000-00000000b0b0', CC = '00000000-0000-4000-8000-00000000c1c1';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
// a small JPEG-shaped data URL: hashed and passed to the (stub) model, never decoded here
const STUDIO = 'data:image/jpeg;base64,' + btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xe0, 0x10, 0x20, 0x30, 0x40, 0xff, 0xd9));
const READING = {
  item: 'an empty wall recess for a built-in wardrobe', space: 'a studio flat, sleeping corner',
  dimensions_seen: ['wall roughly 2.4-2.8 m wide, judged from the door beside it'], cues: ['a socket low on the left of the recess'],
  materials: ['painted plaster wall'], unclear: ['the exact width, height and depth', 'shelves versus hanging space', 'door type', 'finish'],
  ask_next: ['How wide and how high is the wall, and how deep can the wardrobe be?', 'Do you want mostly shelves, mostly hanging space, or a mix?', 'Sliding or hinged doors?'],
  confidence: 'medium',
};

type Mode = { vision: 'ok' | 'fail'; interview: 'follows' | 'claims_photo' | 'down' };
function world(mode: Mode, cached: Record<string, string> = {}) {
  const w = { vision: [] as Row[], interview: [] as string[], other: 0, cache: new Map(Object.entries(cached)), stored: [] as string[],
    intake: { id: II, email: EMAIL, status: 'needs_info', turns: [], customer_id: CC, category: null, brief: {}, site_photos: null } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-wardrobe', email: EMAIL },
    rows: { customers: [{ id: CC, locale: 'en' }], category_specs: [{ category: 'general', label: 'General', fields: [] }], sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (u.pathname === '/functions/v1/ai_gateway') {
        const body = await req.clone().json().catch(() => ({})) as Row;
        const parts = JSON.stringify(body.input ?? body.messages ?? '');
        if (body.task_class === PHOTO_ROUTE && parts.includes('image_url')) {
          w.vision.push(body);
          return mode.vision === 'ok' ? J({ ok: true, content: JSON.stringify(READING), model: 'stub/vision' }) : J({ ok: false, error: 'provider_error', detail: 'stub 502' }, 502);
        }
        if (mode.interview === 'down') return J({ ok: false, error: 'provider_error', detail: 'stub: OpenRouter down' }, 503);
        const userMsg = String(((body.input as Row[])?.[0] as Row)?.content ?? '');
        if (body.fn === 'inquiry_intake' && body.response_format && userMsg.startsWith('THIS TURN')) {
          w.interview.push(userMsg);
          // the stub interview model does what its prompt says: the next questions it was told to ask, or a generic one
          const next = userMsg.match(/YOUR NEXT QUESTION[^:]*: ([^\n]*?)\. Never ask/)?.[1];
          const say = mode.interview === 'claims_photo' ? 'ZZ DEMO I can see a lovely recess in your photo. What would you like there?'
            : next ? 'ZZ DEMO Thanks for the photo. ' + next.split(' | ').slice(0, 2).join(' ') : 'ZZ DEMO What would you like done, and where?';
          return J({ ok: true, model: 'stub/interview', content: JSON.stringify({ category: 'general', trades: ['general'], status: 'needs_info', claims_ready: false,
            assistant_message: say, questions: [say], readiness: 20, missing: [], dialect: 'english', trade_codes: [], service_keys: [], checklist_topics: [], site_visit: [],
            photos_asked: false, condition: {}, problem: '', options_offered: [], chosen_option: '', budget: '', brief: { summary: '', details: {} } }) });
        }
        // every other model step (the voice of a code-drafted sentence, the trade reasoning): a reply that claims nothing
        w.other++;
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO I could not read that photo; could you tell me in words what it shows and how wide the wall is?' }), model: 'stub/voice' });
      }
      if (r === 'fn_llm_cache_lookup') { const a = await req.clone().json() as Row; const v = w.cache.get(String(a.p_key)); return J(v ? { hit: true, kind: 'exact', response: v, model: 'photo_reading', similarity: 1 } : { hit: false }); }
      if (r === 'fn_llm_cache_store') { const a = await req.clone().json() as Row; w.cache.set(String(a.p_key), String(a.p_response)); w.stored.push(String(a.p_key)); return J(null); }
      if (r) return J(r === 'rl_check' ? true : null);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json() as Row); return J([]); }
      }
      return undefined;
    },
  };
  return { w, stub };
}
const fnOf = () => loadFunction('inquiry_intake', () => import('./index.ts'));
const lastAssistant = (w: { intake: Row }) => (w.intake.turns as Row[]).filter((t) => t.role === 'assistant').at(-1)!;

Deno.test('custom wardrobe from a studio photo: the photo is read once and the next question asks the dimensions and shelves versus hanging', async () => {
  const { w, stub } = world({ vision: 'ok', interview: 'follows' });
  const r = await invoke(await fnOf(), stub, { intake_id: II, text: 'ZZ DEMO I want a custom wardrobe like this for my studio', images: [STUDIO], turn_id: 't-zz-wardrobe-1', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assertEquals(w.vision.length, 1, 'the photo did not reach a vision model through the gateway');
  assertEquals(w.vision[0].fn, 'inquiry_intake');
  assert(!JSON.stringify([w.vision[0].sys, w.vision[0].input]).includes(EMAIL), 'customer identity went into the vision prompt');
  // the reading joined the interview's context, and the next question is about what it saw
  assertMatch(w.interview[0], /empty wall recess/);
  const said = String(r.json.assistant_message);
  assertMatch(said, /how wide and how high/i, 'the next question does not ask the dimensions: ' + said);
  assertMatch(said, /deep/i);
  assertMatch(said, /shelves/i); assertMatch(said, /hanging/i);
  // the reading is kept on the turn (internal), cached by the photo's hash, and not paid for again
  const stamped = lastAssistant(w).photo_readings as Row[];
  assertEquals(stamped.length, 1);
  assertEquals(stamped[0].hash, await photoHash(STUDIO));
  assertEquals(w.stored, [cacheKey(await photoHash(STUDIO), 'en')]);
  assertEquals(r.json.photos, { read: 1, unread: 0 });
  const again = await invoke(await fnOf(), stub, { intake_id: II, text: 'ZZ DEMO here it is again', images: [STUDIO], turn_id: 't-zz-wardrobe-2', lang: 'en' });
  assertEquals(again.status, 200);
  assertEquals(w.vision.length, 1, 'the same photo was read twice');
  // a later turn without the photo still has the reading in its context
  await invoke(await fnOf(), stub, { intake_id: II, text: 'ZZ DEMO about 2.6 m wide', turn_id: 't-zz-wardrobe-3', lang: 'en' });
  assertMatch(w.interview.at(-1)!, /empty wall recess/, 'the reading was lost after the turn it came with');
});

Deno.test('a photo sent with no words, while the interview model is down: the cached reading still drives the ask', async () => {
  const cached = { [cacheKey(await photoHash(STUDIO), 'en')]: JSON.stringify(READING) };
  const { w, stub } = world({ vision: 'fail', interview: 'down' }, cached);
  const r = await invoke(await fnOf(), stub, { intake_id: II, text: '', images: [STUDIO], turn_id: 't-zz-wardrobe-4', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assertEquals(w.vision.length, 0, 'a cached photo was paid for again');
  const said = String(r.json.assistant_message);
  assertMatch(said, /looked at your photo/); assertMatch(said, /How wide and how high/); assertMatch(said, /shelves/);
});

Deno.test('the vision call fails: nothing is cached, the prompt says the photo was not read, and no reply claims it was', async () => {
  // 1. the interview model is up but writes "I can see ... in your photo": the reply is written again, without the claim
  const { w, stub } = world({ vision: 'fail', interview: 'claims_photo' });
  const r = await invoke(await fnOf(), stub, { intake_id: II, text: 'ZZ DEMO I want a custom wardrobe like this for my studio', images: [STUDIO], turn_id: 't-zz-wardrobe-5', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assertEquals(w.vision.length, 1);
  assertEquals(w.stored, [], 'a failed reading was cached');
  assertMatch(w.interview[0], /could NOT be read/);
  assert(!/empty wall recess/.test(w.interview[0]), 'a reading reached the prompt although none was made');
  assert(!claimsPhotoSeen(String(r.json.assistant_message)), 'the reply claims the photo was read: ' + r.json.assistant_message);
  assert(w.other >= 1, 'the false claim was not sent back to the model to be written again');
  assertEquals(lastAssistant(w).photo_readings, undefined, 'a failure was stamped as a reading');
  assertEquals(r.json.photos, { read: 0, unread: 1 });
  // 2. OpenRouter down too (the model writes nothing): the code draft says the photo could not be read, and never the old promise
  const down = world({ vision: 'fail', interview: 'down' });
  const d = await invoke(await fnOf(), down.stub, { intake_id: II, text: '', images: [STUDIO], turn_id: 't-zz-wardrobe-6', lang: 'en' });
  const said = String(d.json.assistant_message);
  assertMatch(said, /could not read the photo/);
  assert(!claimsPhotoSeen(said), said);
  assert(!/I will read the details off it for you instead of asking/.test(said), 'the old untrue promise is back');
  // 3. no photo at all, model down: the first ask promises only to try, and to say so if it cannot
  const none = world({ vision: 'ok', interview: 'down' });
  const n = await invoke(await fnOf(), none.stub, { intake_id: II, text: '', turn_id: 't-zz-wardrobe-7', lang: 'en' });
  assertEquals(none.w.vision.length, 0);
  assert(!/I will read the details off it for you instead of asking/.test(String(n.json.assistant_message)));
});

Deno.test('only what chat_images accepts is read: a foreign URL is never fetched or sent to a model', async () => {
  const { w, stub } = world({ vision: 'ok', interview: 'follows' });
  const r = await invoke(await fnOf(), stub, { intake_id: II, text: 'ZZ DEMO wardrobe', images: ['https://example.com/x.jpg'], turn_id: 't-zz-wardrobe-8', lang: 'en' });
  assertEquals(r.status, 200);
  assertEquals(w.vision.length, 0);
  assert(!r.calls.some((c) => c.url.startsWith('https://example.com')), 'a foreign URL was fetched');
});
