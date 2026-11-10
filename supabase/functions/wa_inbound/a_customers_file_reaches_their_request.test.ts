// A REGISTERED CUSTOMER'S FILE ON WHATSAPP REACHES THEIR REQUEST (it_engineer, 10 Nov 2026; channels audit R2, HIGH).
// Seat: customer_support (WhatsApp). Drives the REAL wa_inbound handler through its signed Twilio form path; Twilio media,
// drawing_boq, drawing_redact, storage and the model are stubs and the number is in the reserved fixture block.
// Red on main: the customer's DWG was refused by the sanitizer (PDF and images only) and the turn was answered as "a number
// with no account"; nothing was attached to their request.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
// a DWG by its own magic (AC1032 = AutoCAD 2018), declared the way WhatsApp often declares one: application/octet-stream
const DWG = new Uint8Array(4096); DWG.set(new TextEncoder().encode('AC1032'), 0);

async function sign(params: Record<string, string>): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(TOKEN), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}
type World = { docs: Record<string, unknown>[]; inqPatches: Record<string, unknown>[]; intakes: Record<string, unknown>[]; boq: Record<string, unknown>[]; redact: Record<string, unknown>[];
  gateway: string[]; inquiries: Record<string, unknown>[]; jobs: Record<string, unknown>[] };
function stub(w: World): Stub {
  return {
    rpc: { fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false }, fn_wa_lead_id: null,
      fn_whatsapp_owner: { party_kind: 'customer', customer_id: 'c0ffee00-0000-4000-8000-000000000001' },
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } } },
    rows: { customers: [{ id: 'c0ffee00-0000-4000-8000-000000000001', email: 'zz-demo-customer@example.invalid', full_name: 'ZZ DEMO Customer', phone: '+971500000081' }] },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    twilio: (_req, u) => u.hostname === 'api.twilio.com' && u.pathname.includes('/Media/') ? new Response(DWG, { status: 200, headers: { 'content-type': 'application/octet-stream' } }) : undefined,
    handle: async (req, u) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      const body = req.method === 'GET' ? null : await req.clone().text();
      if (u.pathname === '/functions/v1/ai_gateway') { w.gateway.push(body!); return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO noted', escalate: false }), model: 'stub/model' }); }
      if (u.pathname === '/functions/v1/drawing_boq') { w.boq.push(JSON.parse(body!)); return J({ ok: true, kind: 'dwg', boq: { boq: [{ item: 'ZZ DEMO door', qty: 4 }, { item: 'ZZ DEMO window', qty: 6 }] } }); }
      if (u.pathname === '/functions/v1/drawing_redact') { w.redact.push(JSON.parse(body!)); return J({ ok: true, recorded: true, job_id: 'j-1', paths: ['redacted/zz-demo/page-1.png'] }); }
      if (u.pathname === '/rest/v1/rpc/fn_identify_contact') return J({ audience: 'customer', name: 'ZZ DEMO Customer', claimed: true });
      if (u.pathname === '/rest/v1/inquiries' && req.method === 'GET') return J(w.inquiries);
      if (u.pathname === '/rest/v1/inquiries' && req.method === 'PATCH') { w.inqPatches.push(JSON.parse(body!)); return J([{}]); }
      if (u.pathname === '/rest/v1/inquiry_intake' && req.method === 'GET') return J([]);
      if (u.pathname === '/rest/v1/inquiry_intake' && req.method === 'POST') { const row = { id: 'intake-1', ...JSON.parse(body!) }; w.intakes.push(row); return J(row, 201); }
      if (u.pathname === '/rest/v1/documents' && req.method === 'POST') { w.docs.push(JSON.parse(body!)); return J([], 201); }
      if (u.pathname === '/rest/v1/cad_read_jobs' && req.method === 'POST') { w.jobs.push(JSON.parse(body!)); return J({ id: 'job-1' }, 201); }
      return undefined;
    },
  };
}
let seq = 0;
async function send(w: World, caption = '') {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: 'whatsapp:+971500000081', To: 'whatsapp:+14155550100', Body: caption, MessageSid: 'SMC' + (++seq).toString(16).padStart(31, '0'),
    NumMedia: '1', MediaUrl0: 'https://api.twilio.com/2010-04-01/Accounts/AC/Messages/MM/Media/MEC' + seq, MediaContentType0: 'application/octet-stream', ProfileName: 'ZZ DEMO' };
  const req = new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) }, body: new URLSearchParams(params).toString() });
  return await invokeRequest(await fn(), stub(w), req, async () => { await Promise.all(pending); });
}
const world = (inquiries: Record<string, unknown>[]): World => ({ docs: [], inqPatches: [], intakes: [], boq: [], redact: [], gateway: [], inquiries, jobs: [] });

Deno.test('a registered customer\'s DWG on WhatsApp is accepted, read, redacted and attached to their open request', async () => {
  const w = world([{ id: 'inq-zz-1', status: 'open', drawing_file_path: null }]);
  const r = await send(w, 'ZZ DEMO the villa layout');
  assertEquals(r.status, 200);
  assertEquals(w.docs.length, 1, 'the file is named against their request in the vault: ' + JSON.stringify(w.docs));
  assertEquals([w.docs[0].ref_table, w.docs[0].ref_id, w.docs[0].mime], ['inquiries', 'inq-zz-1', 'image/vnd.dwg']);
  assertEquals(w.boq[0]?.mode, 'document', 'the CAD take-off is read the portal way');
  assertEquals(w.redact[0]?.mode, 'cad', 'and drawn for suppliers with the identity left out');
  const p = w.inqPatches.find((x) => 'drawing_file_path' in x);
  assert(p && /^drawings\/c0ffee00/.test(String(p.drawing_file_path)), 'the request gets it as its drawing: ' + JSON.stringify(w.inqPatches));
  assertEquals(p!.drawing_redacted_paths, ['redacted/zz-demo/page-1.png']);
  const told = w.gateway.join(' ');
  assert(/with their request/.test(told) && /2 take-off lines/.test(told), 'the customer is told what was received and where it went');
  assert(!/no account/.test(told), 'never answered as a number with no account');
});

Deno.test('with no open request, an intake is started for the file', async () => {
  const w = world([{ id: 'inq-old', status: 'completed', drawing_file_path: null }]);
  await send(w);
  assertEquals(w.intakes.length, 1);
  assertEquals([w.docs[0].ref_table, w.docs[0].ref_id], ['inquiry_intake', 'intake-1']);
  assertEquals(w.inqPatches.length, 0, 'a closed request is never given the file');
});
