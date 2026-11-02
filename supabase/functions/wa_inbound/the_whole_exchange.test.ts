// A supplier who has just been sent a code on WhatsApp texts the number: does the exchange work as designed?
// Seat: customer_support (2 Nov 2026). This drives the REAL wa_inbound handler through its Twilio FORM path with a
// correctly SIGNED inbound (HMAC-SHA1 over url + sorted params, the auth token of the stub), from the reserved fixture
// block (+971 50 000 00xx), with an in-memory wa_messages / wa_inbound_seen so a conversation accumulates. The model is
// the stubbed ai_gateway; nothing reaches twilio.com (a fixture is captured, demo_identity.ts). It proves the plumbing and
// what the model is SHOWN; it does not prove what a real model writes (that is the live rehearsal, not this file).
// Known-bad controls: a forged signature is refused; a number with no history shows the model none; the same history
// assertion fails on the pre-fix handler (the PR body records the red run).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';   // every unlisted app_secrets key reads as this
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
const A = 'whatsapp:+971500000031', B = 'whatsapp:+971500000032';

async function sign(params: Record<string, string>, token = TOKEN): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(token), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)));
  return btoa(String.fromCharCode(...mac));
}

type World = { msgs: Record<string, unknown>[]; seen: Set<string>; gateway: Record<string, unknown>[]; rpcs: { fn: string; args: Record<string, unknown> }[]; nextId: number; audience: Record<string, unknown>; replies: string[] };
const world = (audience: Record<string, unknown> = { audience: 'supplier', name: 'ZZ DEMO Glass LLC', claimed: true, approved: true }): World =>
  ({ msgs: [], seen: new Set(), gateway: [], rpcs: [], nextId: 1, audience, replies: [] });

function stubFor(w: World): Stub {
  return {
    rpc: {
      fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false },
      fn_wa_lead_id: w.audience.audience === 'supplier' ? 77 : null,   // the supplier's lead row, so a file goes down the supplier-document path
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } },
    },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    handle: async (req: Request, u: URL) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      const q = (k: string) => (u.searchParams.get(k) || '').replace(/^(eq|lt|gte|lte)\./, '');
      if (u.pathname === '/functions/v1/ai_gateway') {
        const body = JSON.parse(await req.clone().text()); w.gateway.push(body);
        const n = w.replies.length + 1; const text = 'ZZ DEMO reply ' + n;
        return J({ ok: true, content: JSON.stringify({ answer: text, reply: text, lang: 'en', escalate: false }), model: 'stub/model' });
      }
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
      if (rpc) {
        const args = JSON.parse((await req.clone().text()) || '{}'); w.rpcs.push({ fn: rpc[1], args });
        if (rpc[1] === 'fn_identify_contact') return J(w.audience);
        return undefined;
      }
      if (u.pathname === '/rest/v1/wa_inbound_seen' && req.method === 'POST') {
        const sid = JSON.parse(await req.clone().text()).message_sid;
        if (w.seen.has(sid)) return J({ code: '23505', message: 'duplicate key value violates unique constraint' }, 409);
        w.seen.add(sid); return J([], 201);
      }
      if (u.pathname === '/rest/v1/wa_messages') {
        if (req.method === 'POST') {
          const row = { id: w.nextId++, ...JSON.parse(await req.clone().text()) }; w.msgs.push(row);
          if (row.sent === true && row.reply) w.replies.push(String(row.reply));
          return J((req.headers.get('accept') || '').includes('vnd.pgrst.object') ? row : [row], 201);
        }
        if (req.method === 'PATCH') {
          const id = Number(q('id')); const row = w.msgs.find((m) => m.id === id);
          if (row) { Object.assign(row, JSON.parse(await req.clone().text())); if (row.sent === true && row.reply) w.replies.push(String(row.reply)); }
          return J(row ? [row] : [], 200);
        }
        if (req.method === 'GET') {
          const from = q('wa_from'), before = q('created_at');
          const rows = w.msgs.filter((m) => (!from || m.wa_from === from) && (!before || String(m.created_at) < before))
            .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
          return J(rows);
        }
      }
      return undefined;
    },
  };
}

let seq = 0;
async function inbound(w: World, from: string, body: string, extra: Record<string, string> = {}, token = TOKEN) {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: from, To: 'whatsapp:+14155550100', Body: body, MessageSid: 'SM' + (++seq).toString(16).padStart(32, '0'), NumMedia: '0', ProfileName: 'ZZ DEMO', ...extra };
  const req = new Request(URL_SIGNED, { method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params, token) },
    body: new URLSearchParams(params).toString() });
  const before = w.gateway.length;
  const r = await invokeRequest(await fn(), stubFor(w), req, async () => { await Promise.all(pending); });
  return { ...r, sid: params.MessageSid, gw: w.gateway.slice(before) };
}
// The conversation the model was shown on a request: whatever the gateway call carries as history or messages.
const shown = (gw: Record<string, unknown>[]) => JSON.stringify(gw);

Deno.test('a forged signature gets no reply and no model call (known-bad control)', async () => {
  const w = world();
  const r = await inbound(w, A, 'ZZ DEMO hello', {}, 'not-the-auth-token');
  assertEquals(r.gw.length, 0);
  assertEquals(r.twilio.length, 0);
  assertEquals(w.msgs.filter((m) => m.reply).length, 0);
});

Deno.test('a supplier who just had a code asks a question: one reply, stored, nothing sent to twilio.com', async () => {
  const w = world();
  const r = await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
  assertEquals(r.status, 200);
  assertEquals(r.twilio.length, 0, 'a fixture is captured, never handed to Twilio');
  const rows = w.msgs.filter((m) => m.wa_from === A);
  assertEquals(rows.length, 1, 'one row for the turn: the arrival row is completed in place, not doubled');
  assert(String(rows[0].reply).length > 0, 'a reply was written');
  assert(r.gw.length > 0, 'the model was asked');
});

Deno.test('Twilio redelivers the same MessageSid: still one reply (no double reply)', async () => {
  const w = world();
  const params = { From: A, To: 'whatsapp:+14155550100', Body: 'ZZ DEMO Do you cover Sharjah?', MessageSid: 'SM' + 'a'.repeat(32), NumMedia: '0' };
  const go = async () => {
    const pending: Promise<unknown>[] = [];
    (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
    const req = new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) }, body: new URLSearchParams(params).toString() });
    await invokeRequest(await fn(), stubFor(w), req, async () => { await Promise.all(pending); });
  };
  await go(); await go();
  assertEquals(w.msgs.filter((m) => m.wa_from === A && m.reply).length, 1);
});

Deno.test('a Hi from a supplier and a stranger are both answered', async () => {
  const w = world();
  const hi = await inbound(w, A, 'Hi');
  assert(w.msgs.some((m) => m.wa_from === A && m.reply), 'the supplier got an answer');
  const w2 = world({ audience: 'unknown' });
  await inbound(w2, B, 'ZZ DEMO who are you?');
  assert(w2.msgs.some((m) => m.wa_from === B && m.reply), 'the stranger got an answer');
  assert(hi.gw.length >= 0);
});

Deno.test('an Arabic message from a supplier asks the model for English (suppliers always get English)', async () => {
  const w = world();
  const r = await inbound(w, A, 'ZZ DEMO متى أبدأ باستلام الطلبات؟');
  assert(w.msgs.some((m) => m.wa_from === A && m.reply), 'answered');
  assert(/English/i.test(shown(r.gw)), 'the model is told suppliers are answered in English');
});

Deno.test('ten turns: turn 10 reaches the model with turns 1-9 (memory), and a fresh number is shown none', async () => {
  const w = world();
  const said: string[] = [];
  for (let i = 1; i <= 10; i++) {
    const text = i === 1 ? 'ZZ DEMO I supply aluminium windows and glass partitions in Sharjah zq7731'
      : i === 10 ? 'ZZ DEMO and what did I say I supply?' : 'ZZ DEMO question number ' + i;
    said.push(text);
    const r = await inbound(w, A, text);
    if (i === 10) {
      const s = shown(r.gw);
      assert(s.includes('partitions in Sharjah zq7731'), 'turn 1 is in what the model was shown on turn 10');
      assert(s.includes('question number 9'), 'turn 9 too');
      assert(s.includes('ZZ DEMO reply 1'), 'and our own earlier replies');
    }
  }
  assertEquals(w.msgs.filter((m) => m.wa_from === A && m.reply).length, 10, 'ten turns, ten replies, no double');
  const fresh = await inbound(w, B, 'ZZ DEMO and what did I say I supply?');
  assert(!shown(fresh.gw).includes('zq7731'), 'control: a different number is never shown this number\'s turns');
});

Deno.test('a voice note is not told to send a trade licence', async () => {
  const w = world();
  const r = await inbound(w, A, '', { NumMedia: '1', MediaUrl0: 'https://api.twilio.com/2010-04-01/Accounts/AC/Messages/MM/Media/ME', MediaContentType0: 'audio/ogg' });
  assertEquals(r.status, 200);
  const s = shown(r.gw);
  assert(/voice note/i.test(s), 'the model is told it was a voice note');
  assert(!/trade licence as a PDF/i.test(s), 'and is not told to ask for a PDF licence');
});

Deno.test('STOP from a number that is not a lead continues as a normal turn (never swallowed)', async () => {
  const w = world({ audience: 'unknown' });
  await inbound(w, B, 'STOP');
  assert(w.rpcs.some((c) => c.fn === 'fn_wa_supplier_invite_opt_out'), 'the opt-out routine is asked');
  assert(w.msgs.some((m) => m.wa_from === B), 'the message is stored');
});

Deno.test('the founder command channel: a stranger asking to change a setting cannot (no founder rpc is called for an unknown number)', async () => {
  const w = world({ audience: 'unknown' });
  await inbound(w, B, 'ZZ DEMO set the supplier fee to zero');
  assert(!w.rpcs.some((c) => c.fn === 'fn_founder_apply_setting' || c.fn === 'fn_founder_whatsapp_figures'), 'no founder routine ran for a non-founder');
  assert(!w.rpcs.some((c) => c.fn === 'fn_notify_founder'), 'and the founder was not paged');
});
