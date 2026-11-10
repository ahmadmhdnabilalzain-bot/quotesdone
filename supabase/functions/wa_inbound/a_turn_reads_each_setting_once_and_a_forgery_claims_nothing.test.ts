// Two small defects of the channels audit (R7, it_engineer, 10 Nov 2026). Seat: customer_support (WhatsApp).
// Drives the REAL wa_inbound handler through its signed Twilio form path; every dependency is a stub, the numbers are in the
// reserved fixture block. Red on main: a typed turn read wa_autoreply_enabled (and others) from app_secrets several times, and a
// forged post claimed its MessageSid in wa_inbound_seen before the signature check, so the genuine delivery was then dropped.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
async function sign(params: Record<string, string>, token = TOKEN): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(token), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}
type World = { secretReads: string[]; seen: Set<string>; replies: number };
function stub(w: World): Stub {
  return {
    rpc: { fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false }, fn_wa_lead_id: null,
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } } },
    handle: async (req, u) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      if (u.pathname === '/rest/v1/app_secrets') {
        const k = (u.searchParams.get('key') || '').replace(/^eq\./, ''); w.secretReads.push(k);
        const v: Record<string, string> = { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' };
        return J(req.headers.get('accept')?.includes('vnd.pgrst.object') ? { value: v[k] ?? TOKEN } : [{ value: v[k] ?? TOKEN }]);
      }
      if (u.pathname === '/functions/v1/ai_gateway') { w.replies++; return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO answer', escalate: false }), model: 'stub/model' }); }
      if (u.pathname === '/rest/v1/rpc/fn_identify_contact') return J({ audience: 'customer', name: 'ZZ DEMO Customer', claimed: true });
      if (u.pathname === '/rest/v1/wa_inbound_seen' && req.method === 'POST') {
        const sid = JSON.parse(await req.clone().text()).message_sid;
        if (w.seen.has(sid)) return J({ code: '23505', message: 'duplicate key value violates unique constraint' }, 409);
        w.seen.add(sid); return J([], 201);
      }
      return undefined;
    },
  };
}
async function post(w: World, from: string, body: string, sid: string, token = TOKEN) {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: from, To: 'whatsapp:+14155550100', Body: body, MessageSid: sid, NumMedia: '0', ProfileName: 'ZZ DEMO' };
  const req = new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params, token) },
    body: new URLSearchParams(params).toString() });
  return await invokeRequest(await fn(), stub(w), req, async () => { await Promise.all(pending); });
}

Deno.test('a typed turn reads each setting from app_secrets once', async () => {
  const w: World = { secretReads: [], seen: new Set(), replies: 0 };
  await post(w, 'whatsapp:+971500000091', 'ZZ DEMO how do quotes reach me?', 'SM' + 'a1'.padStart(32, '0'));
  const counts: Record<string, number> = {};
  for (const k of w.secretReads) counts[k] = (counts[k] ?? 0) + 1;
  // cred_fn_wa_inbound is read by _shared/llm.ts's own reader for each gateway call (not wa_inbound's sec): outside this fix.
  const twice = Object.entries(counts).filter(([k, n]) => n > 1 && k !== 'cred_fn_wa_inbound');
  assertEquals(twice, [], 'read more than once in one turn: ' + JSON.stringify(counts));
  assert(w.secretReads.length > 0, 'the turn read its settings (a harness that sees nothing proves nothing)');
});

Deno.test('a forged post claims no MessageSid: the genuine delivery of that message is still answered', async () => {
  const w: World = { secretReads: [], seen: new Set(), replies: 0 };
  const sid = 'SM' + 'b2'.padStart(32, '0');
  await post(w, 'whatsapp:+971500000092', 'ZZ DEMO forged', sid, 'not-the-auth-token');   // Twilio is answered 200 at once; the work refuses it
  assertEquals(w.seen.has(sid), false, 'the forgery claimed the MessageSid');
  const replies = w.replies;
  await post(w, 'whatsapp:+971500000092', 'ZZ DEMO the real message', sid);
  assert(w.seen.has(sid) && w.replies > replies, 'the genuine message was dropped as a redelivery');
});
