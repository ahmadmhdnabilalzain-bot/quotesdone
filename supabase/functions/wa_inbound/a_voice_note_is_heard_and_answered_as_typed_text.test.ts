// A VOICE NOTE IS HEARD AND ANSWERED AS TYPED TEXT (it_engineer, 10 Nov 2026). Seat: customer_support (WhatsApp).
// Founder evidence scenario 3: "a customer sending a voice note only" reaches an inquiry end to end.
//
// Drives the REAL wa_inbound handler through its signed Twilio form path with a voice note and nothing else. Twilio's media,
// the speech provider (the ai_gateway 'transcribe' call) and every model are stubs; the number is in the reserved fixture
// block, so nothing reaches twilio.com or a provider. It proves: the speaker is shown their own words back first ("I heard"),
// the transcript becomes the turn's message for the intake/interview turn exactly as typed text would, and with no provider
// configured the honest "please type it" reply stays. Red on main: no voice note was ever heard (hear.ts did not exist).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { oggOpus } from '../_shared/ogg_fixture.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';

async function sign(params: Record<string, string>): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(TOKEN), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}

type World = { msgs: Record<string, unknown>[]; nextId: number; gateway: Record<string, unknown>[]; said: string; provider: string; audience: string };
function stub(w: World): Stub {
  return {
    rpc: {
      fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false },
      fn_wa_lead_id: null,
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } },
    },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100', voice_transcription_provider: w.provider },
    twilio: (_req, u) => u.hostname === 'api.twilio.com' && u.pathname.includes('/Media/')
      ? new Response(oggOpus(6), { status: 200, headers: { 'content-type': 'audio/ogg' } }) : undefined,
    handle: async (req, u) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      const q = (k: string) => (u.searchParams.get(k) || '').replace(/^(eq|lt|gte|lte)\./, '');
      if (u.pathname === '/functions/v1/ai_gateway') {
        const body = JSON.parse(await req.clone().text()); w.gateway.push(body);
        if (body.fn === 'transcribe') return J({ ok: true, content: JSON.stringify({ speech: true, text: w.said }) });
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO answer', reply: 'ZZ DEMO answer', lang: 'en', escalate: false }), model: 'stub/model' });
      }
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
      if (rpc && rpc[1] === 'fn_identify_contact') return J({ audience: w.audience, name: 'ZZ DEMO Customer', claimed: true });
      if (u.pathname === '/rest/v1/wa_messages') {
        if (req.method === 'POST') {
          const row = { id: w.nextId++, ...JSON.parse(await req.clone().text()) }; w.msgs.push(row);
          return J((req.headers.get('accept') || '').includes('vnd.pgrst.object') ? row : [row], 201);
        }
        if (req.method === 'PATCH') {
          const row = w.msgs.find((m) => m.id === Number(q('id')));
          if (row) Object.assign(row, JSON.parse(await req.clone().text()));
          return J(row ? [row] : [], 200);
        }
        if (req.method === 'GET') return J(w.msgs.filter((m) => m.wa_from === q('wa_from') && m.id !== undefined && String(m.created_at) < (q('created_at') || '~')));
      }
      return undefined;
    },
  };
}

let seq = 0;
async function voiceNote(w: World, from: string) {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: from, To: 'whatsapp:+14155550100', Body: '', MessageSid: 'SMV' + (++seq).toString(16).padStart(31, '0'),
    NumMedia: '1', MediaUrl0: 'https://api.twilio.com/2010-04-01/Accounts/AC/Messages/MM/Media/MEV' + seq, MediaContentType0: 'audio/ogg', ProfileName: 'ZZ DEMO' };
  const req = new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) },
    body: new URLSearchParams(params).toString() });
  return await invokeRequest(await fn(), stub(w), req, async () => { await Promise.all(pending); });
}
const world = (over: Partial<World> = {}): World => ({ msgs: [], nextId: 1, gateway: [], provider: 'gateway', audience: 'customer',
  said: 'ZZ DEMO I need a quote for a car park shade at my villa in Dubai Hills, about six by five metres', ...over });

Deno.test('a voice note only: the customer is shown what was heard, and the words are answered as their typed message', async () => {
  const w = world(); const FROM = 'whatsapp:+971500000061';
  const r = await voiceNote(w, FROM);
  assertEquals(r.status, 200);
  assert(w.gateway.some((g) => g.fn === 'transcribe'), 'the voice note was sent to be heard');
  const receipt = w.msgs.find((m) => (m.meta as Record<string, unknown>)?.route === 'voice_heard');
  assert(receipt, 'the heard receipt is recorded: ' + JSON.stringify(w.msgs.map((m) => m.meta)));
  assert(String(receipt!.reply).startsWith('I heard: "' + w.said + '"'), 'their own words shown back: ' + receipt!.reply);
  const asked = JSON.stringify(w.gateway.filter((g) => g.fn !== 'transcribe'));
  assert(asked.includes('car park shade at my villa'), 'the reply is composed on the transcript, as typed text');
  assert(!/cannot be listened to/.test(asked), 'and never told the voice note was not heard');
  const turn = w.msgs.find((m) => m.inbound === w.said && (m.meta as Record<string, unknown>)?.voice);
  assert(turn, 'the turn is stored with the transcript as what they said, marked as heard from a voice note: ' + JSON.stringify(w.msgs.map((m) => [m.inbound, m.meta])));
});

Deno.test('an Arabic voice note is shown back in Arabic', async () => {
  const w = world({ said: 'ZZ DEMO أبغى عرض سعر لمظلة سيارات في الفيلا' });
  await voiceNote(w, 'whatsapp:+971500000062');
  const receipt = w.msgs.find((m) => (m.meta as Record<string, unknown>)?.route === 'voice_heard');
  assert(String(receipt?.reply).includes('سمعتُ منكم'), String(receipt?.reply));
});

Deno.test('known-good control: with no provider configured, nothing is sent to be heard and the honest reply stays', async () => {
  const w = world({ provider: '' });
  await voiceNote(w, 'whatsapp:+971500000063');
  assertEquals(w.gateway.some((g) => g.fn === 'transcribe'), false);
  assert(/cannot be listened to on WhatsApp yet/.test(JSON.stringify(w.gateway)), 'the model is told it was not heard');
});
