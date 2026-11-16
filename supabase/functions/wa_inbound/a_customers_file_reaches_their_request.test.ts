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
  gateway: string[]; inquiries: Record<string, unknown>[]; jobs: Record<string, unknown>[]; media?: Uint8Array; fileHeld?: boolean;
  /** fn_site_photos_record calls, and the record they built (the database's one statement, stubbed) */
  photoRpcs?: Record<string, unknown>[]; photoRecord?: { photos: Record<string, unknown>[] }; photosToday?: number };
function stub(w: World): Stub {
  return {
    rpc: { fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false }, fn_wa_lead_id: null,
      fn_whatsapp_owner: { party_kind: 'customer', customer_id: 'c0ffee00-0000-4000-8000-000000000001' },
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } } },
    rows: { customers: [{ id: 'c0ffee00-0000-4000-8000-000000000001', email: 'zz-demo-customer@example.invalid', full_name: 'ZZ DEMO Customer', phone: '+971500000081' }] },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    twilio: (_req, u) => u.hostname === 'api.twilio.com' && u.pathname.includes('/Media/') ? new Response((w.media ?? DWG) as BodyInit, { status: 200, headers: { 'content-type': 'application/octet-stream' } }) : undefined,
    handle: async (req, u) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      const body = req.method === 'GET' ? null : await req.clone().text();
      if (u.pathname === '/functions/v1/ai_gateway') { w.gateway.push(body!); return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO noted', escalate: false }), model: 'stub/model' }); }
      if (u.pathname === '/functions/v1/drawing_boq') { w.boq.push(JSON.parse(body!)); return J({ ok: true, kind: 'dwg', boq: { boq: [{ item: 'ZZ DEMO door', qty: 4 }, { item: 'ZZ DEMO window', qty: 6 }] } }); }
      if (u.pathname === '/functions/v1/drawing_redact') {
        const b = JSON.parse(body!); w.redact.push(b);
        if (b.mode === 'file' && w.fileHeld) return J({ ok: true, recorded: true, job_id: 'j-2', paths: [], status: 'failed', held_reason: 'pdf_no_text_layer', redaction_complete: false });
        return J({ ok: true, recorded: true, job_id: 'j-' + w.redact.length, paths: [b.mode === 'file' ? 'redacted/zz-demo/page_drawing.' + (w.media ? 'pdf' : 'dxf') : 'redacted/zz-demo/page_p0.jpg'], redaction_complete: true });
      }
      if (u.pathname === '/rest/v1/rpc/fn_identify_contact') return J({ audience: 'customer', name: 'ZZ DEMO Customer', claimed: true });
      if (u.pathname === '/rest/v1/inquiries' && req.method === 'GET') return J(w.inquiries);
      if (u.pathname === '/rest/v1/inquiries' && req.method === 'PATCH') { w.inqPatches.push(JSON.parse(body!)); return J([{}]); }
      if (u.pathname === '/rest/v1/inquiry_intake' && req.method === 'GET') return J([]);
      if (u.pathname === '/rest/v1/inquiry_intake' && req.method === 'POST') { const row = { id: 'intake-1', ...JSON.parse(body!) }; w.intakes.push(row); return J(row, 201); }
      if (u.pathname === '/rest/v1/documents' && req.method === 'POST') { w.docs.push(JSON.parse(body!)); return J([], 201); }
      if (u.pathname === '/rest/v1/cad_read_jobs' && req.method === 'POST') { w.jobs.push(JSON.parse(body!)); return J({ id: '0b0b0b0b-0000-4000-8000-00000000000' + w.jobs.length }, 201); }
      if (u.pathname === '/rest/v1/cad_read_jobs' && (req.method === 'HEAD' || req.method === 'GET')) return new Response(req.method === 'HEAD' ? null : '[]', { status: 200, headers: { 'content-type': 'application/json', 'content-range': '*/' + (w.photosToday ?? 0) } });
      if (u.pathname === '/rest/v1/rpc/fn_site_photos_record') {
        const a = JSON.parse(body!); (w.photoRpcs ??= []).push(a);
        w.photoRecord = { photos: [...(w.photoRecord?.photos ?? []), ...a.p_photos.map((p: Record<string, unknown>) => ({ ...p, via: a.p_via }))] };
        return J({ asked: [], ...w.photoRecord });
      }
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
  // The preview decides, and the anonymised DXF rides with it (the portal's order, lib/drawings.redactCad).
  assertEquals(w.redact.map((x) => x.mode), ['cad', 'file']);
  assertEquals(p!.drawing_redacted_paths, ['redacted/zz-demo/page_p0.jpg', 'redacted/zz-demo/page_drawing.dxf']);
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

// ANONYMITY AUDIT B, FINDING I3 (13 Nov 2026, sales_engineer): a PDF drawing sent on WhatsApp went onto the open request
// with no redaction run at all. It now goes through drawing_redact mode 'file' (the anonymised, verified vector PDF), and
// a path is attached only from a recorded, complete run; a held one attaches NOTHING.
const PDF = new TextEncoder().encode('%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n');
Deno.test('a PDF drawing on WhatsApp reaches suppliers only as the anonymised, verified file', async () => {
  const w = world([{ id: 'inq-zz-2', status: 'open', drawing_file_path: null }]); w.media = PDF;
  await send(w, 'ZZ DEMO pool drawing');
  assertEquals(w.redact.map((x) => x.mode), ['file'], 'the PDF is redacted the portal\'s file way: ' + JSON.stringify(w.redact.map((x) => x.mode)));
  const p = w.inqPatches.find((x) => 'drawing_file_path' in x);
  assertEquals(p!.drawing_redacted_paths, ['redacted/zz-demo/page_drawing.pdf']);
});
Deno.test('a PDF the redaction holds attaches nothing: suppliers see no page of it', async () => {
  const w = world([{ id: 'inq-zz-3', status: 'open', drawing_file_path: null }]); w.media = PDF; w.fileHeld = true;
  await send(w, 'ZZ DEMO scanned drawing');
  const p = w.inqPatches.find((x) => 'drawing_file_path' in x);
  assertEquals(p!.drawing_redacted_paths, null);
  // Review item 13 (13 Nov 2026): the reply is true - a held drawing is never described as shown to suppliers.
  const told = w.gateway.join(' ');
  assert(/NOT shown to suppliers yet/.test(told) && !/suppliers are shown it only with/.test(told), 'the reply describes a held drawing as shared: ' + told.slice(0, 300));
});

// REVIEW OF bf8b9ea45, ITEM 4 (15 Nov 2026, sales_engineer): a WhatsApp photo is recorded on the open request by the database's one
// statement (fn_site_photos_record), never by reading the spec and writing it back whole, which lost one of two photos sent together
// and overwrote a chat turn saved in between. A customer past the day's cap is not queued.
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xda, 0, 2, 1, 2, 3, 0xff, 0xd9]);
const INQ = '1a1a1a1a-0000-4000-8000-000000000001';
Deno.test('a WhatsApp photo is queued and recorded on the open request in one statement; the spec is never written whole', async () => {
  const w = world([{ id: INQ, status: 'open', drawing_file_path: null }]); w.media = JPEG;
  await send(w, 'ZZ DEMO the outdoor unit');
  await send(w, 'ZZ DEMO the indoor unit');
  assertEquals(w.jobs.map((j) => j.why), ['site_photo_check', 'site_photo_check']);
  assertEquals((w.photoRpcs ?? []).map((a) => [a.p_table, a.p_id, a.p_via]), [['inquiries', INQ, 'whatsapp'], ['inquiries', INQ, 'whatsapp']]);
  assertEquals(w.photoRecord?.photos.length, 2, 'one of two photos was lost');
  assert(!w.inqPatches.some((x) => 'spec' in x || 'brief' in x), 'the spec was read and written back whole: ' + JSON.stringify(w.inqPatches));
  assert(/checked first/.test(w.gateway.join(' ')), 'the customer is not told the photo is checked first');
});
Deno.test('a customer past the day\'s photo cap is not queued, and is told the photo is not sent to suppliers', async () => {
  const w = world([{ id: INQ, status: 'open', drawing_file_path: null }]); w.media = JPEG; w.photosToday = 24;
  await send(w, 'ZZ DEMO one more');
  assertEquals(w.jobs.length, 0);
  assert(/not sent to suppliers/.test(w.gateway.join(' ')));
});
