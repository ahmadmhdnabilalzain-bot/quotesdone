// A REGISTERED CUSTOMER'S PHOTO ON WHATSAPP IS READ, AND THE REPLY ASKS ABOUT WHAT IT SHOWS (19 Nov 2026, sales_engineer;
// founder ruling 1200: "customer-facing agents must hold adaptive, expert conversations (e.g. custom wardrobe from a studio
// photo: ask dimensions, shelves vs hanging, ...)"). Drives the REAL wa_inbound handler through its signed Twilio form path, as
// a_customers_file_reaches_their_request.test.ts does; Twilio media, storage and every model are stubs (no paid call).
// Red on main 2801b0522: the photo was stored and queued for its supplier check, and the reply was only told "it is with their
// request"; no model saw the photo.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { PHOTO_ROUTE } from '../_shared/photo_reading.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xda, 0, 2, 7, 7, 7, 0xff, 0xd9]);
const INQ = '1a1a1a1a-0000-4000-8000-0000000000aa';
const READING = { item: 'an empty wall recess for a built-in wardrobe', space: 'a studio flat', dimensions_seen: ['wall roughly 2.5 m wide'], cues: [], materials: ['painted plaster'],
  unclear: ['width, height and depth', 'shelves versus hanging'], ask_next: ['How wide and how high is the wall, and how deep can the wardrobe be?', 'Mostly shelves, mostly hanging space, or a mix?'], confidence: 'medium' };

async function sign(params: Record<string, string>): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(TOKEN), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}
type World = { vision: Record<string, unknown>[]; said: string[]; stored: string[]; jobs: number; ok: boolean; photosToday?: number };
function stub(w: World): Stub {
  const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
  return {
    rpc: { fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false }, fn_wa_lead_id: null,
      fn_whatsapp_owner: { party_kind: 'customer', customer_id: 'c0ffee00-0000-4000-8000-000000000002' },
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } } },
    rows: { customers: [{ id: 'c0ffee00-0000-4000-8000-000000000002', email: 'zz-demo-c2@example.invalid', full_name: 'Zaid Qasimi', phone: '+971500000082' }] },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    twilio: (_req, u) => u.hostname === 'api.twilio.com' && u.pathname.includes('/Media/') ? new Response(JPEG as BodyInit, { status: 200, headers: { 'content-type': 'image/jpeg' } }) : undefined,
    handle: async (req, u) => {
      const body = req.method === 'GET' ? null : await req.clone().text();
      if (u.pathname === '/functions/v1/ai_gateway') {
        const b = JSON.parse(body!);
        if (b.task_class === PHOTO_ROUTE && body!.includes('image_url')) { w.vision.push(b); return w.ok ? J({ ok: true, content: JSON.stringify(READING), model: 'stub/vision' }) : J({ ok: false, error: 'provider_error' }, 502); }
        w.said.push(body!);
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO noted', escalate: false }), model: 'stub/model' });
      }
      if (u.pathname === '/rest/v1/rpc/fn_identify_contact') return J({ audience: 'customer', name: 'ZZ DEMO Customer', claimed: true });
      if (u.pathname === '/rest/v1/rpc/fn_llm_cache_lookup') return J({ hit: false });
      if (u.pathname === '/rest/v1/rpc/fn_llm_cache_store') { w.stored.push(JSON.parse(body!).p_key); return J(null); }
      if (u.pathname === '/rest/v1/inquiries' && req.method === 'GET') return J([{ id: INQ, status: 'open', drawing_file_path: null }]);
      if (u.pathname === '/rest/v1/documents' && req.method === 'POST') return J([], 201);
      if (u.pathname === '/rest/v1/cad_read_jobs' && req.method === 'POST') { w.jobs++; return J({ id: '0b0b0b0b-0000-4000-8000-0000000000' + String(10 + w.jobs) }, 201); }
      if (u.pathname === '/rest/v1/cad_read_jobs' && (req.method === 'HEAD' || req.method === 'GET')) return new Response(req.method === 'HEAD' ? null : '[]', { status: 200, headers: { 'content-type': 'application/json', 'content-range': '*/' + (w.photosToday ?? 0) } });
      if (u.pathname === '/rest/v1/rpc/fn_site_photos_record') { const a = JSON.parse(body!); return J({ asked: [], photos: a.p_photos.map((p: Record<string, unknown>) => ({ ...p, via: a.p_via })) }); }
      return undefined;
    },
  };
}
let seq = 0;
async function send(w: World, caption: string) {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: 'whatsapp:+971500000082', To: 'whatsapp:+14155550100', Body: caption, MessageSid: 'SMP' + (++seq).toString(16).padStart(31, '0'),
    NumMedia: '1', MediaUrl0: 'https://api.twilio.com/2010-04-01/Accounts/AC/Messages/MM/Media/MEP' + seq, MediaContentType0: 'image/jpeg', ProfileName: 'ZZ DEMO' };
  const req = new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) }, body: new URLSearchParams(params).toString() });
  return await invokeRequest(await fn(), stub(w), req, async () => { await Promise.all(pending); });
}
const world = (ok: boolean): World => ({ vision: [], said: [], stored: [], jobs: 0, ok });

Deno.test('a studio photo on WhatsApp is read once, and the reply is told to ask the dimensions and shelves versus hanging', async () => {
  const w = world(true);
  const r = await send(w, 'ZZ DEMO a wardrobe for this wall please');
  assertEquals(r.status, 200);
  assertEquals(w.vision.length, 1, 'the photo did not reach a vision model');
  assertEquals(w.vision[0].fn, 'wa_inbound');
  const prompt = JSON.stringify([w.vision[0].sys, w.vision[0].input]);
  assert(!/Zaid|Qasimi|zz-demo-c2|971500000082/.test(prompt), 'customer identity went into the vision prompt');
  const told = w.said.join(' ');
  assertMatch(told, /We looked at the photo they sent/); assertMatch(told, /empty wall recess/);
  assertMatch(told, /How wide and how high/); assertMatch(told, /shelves/);
  assertMatch(told, /checked first/, 'the supplier check of the photo is no longer said');
  assertEquals(w.stored.length, 1, 'the reading was not cached by the photo\'s hash');
});

Deno.test('a photo the vision call cannot read: nothing cached, and the reply is told never to say it looked at it', async () => {
  const w = world(false);
  await send(w, 'ZZ DEMO a wardrobe for this wall please');
  assertEquals(w.vision.length, 1);
  assertEquals(w.stored, []);
  const told = w.said.join(' ');
  assertMatch(told, /could not be read by us/);
  assert(!/We looked at the photo|empty wall recess/.test(told), 'a reading reached the reply although none was made');
});

Deno.test('a photo past the day\'s check cap is not read either (the cap bounds the paid reads too)', async () => {
  const w = world(true); w.photosToday = 24;
  await send(w, 'ZZ DEMO one more');
  assertEquals([w.jobs, w.vision.length], [0, 0]);
});
