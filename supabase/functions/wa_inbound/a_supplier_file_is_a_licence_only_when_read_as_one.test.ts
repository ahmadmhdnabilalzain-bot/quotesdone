// A SUPPLIER'S FILE IS A LICENCE ONLY WHEN IT READS AS ONE (R1 of the channels audit, it_engineer, 10 Nov 2026).
// Seat: customer_support (WhatsApp), the supplier-registration path (the founder's priority 1).
//
// On main, media.ts handleSupplierDoc filed ANY image or PDF a supplier lead sent on WhatsApp as their trade licence: it
// replaced license_doc_path and cleared trade_license_no, license_authority, license_expiry and licence_legal_name whatever
// the reader saw, so a product photo took a registered supplier's licence off their record. This drives the REAL wa_inbound
// handler through its signed Twilio form path with one attachment; Twilio media, license_extract, storage and the model are
// stubs (nothing leaves the process, the number is in the reserved fixture block).
// Red on main: the product photo PATCHes leads with license_doc_path and four nulls, and fn_wa_attach_document is never called.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
const FROM = 'whatsapp:+971500000051';
const PNG = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='), (c) => c.charCodeAt(0));

async function sign(params: Record<string, string>): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(TOKEN), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}

type World = { leadPatches: Record<string, unknown>[]; reviews: Record<string, unknown>[]; rpcs: { fn: string; args: Record<string, unknown> }[];
  gateway: string[]; doc: Record<string, unknown> | null; intake: Record<string, unknown>; actions?: Record<string, unknown>[] };

function stub(w: World): Stub {
  return {
    rpc: {
      fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false },
      fn_wa_lead_id: 77,
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } },
    },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    twilio: (_req, u) => u.hostname === 'api.twilio.com' && u.pathname.includes('/Media/')
      ? new Response(PNG, { status: 200, headers: { 'content-type': 'image/png' } }) : undefined,
    handle: async (req, u) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      if (u.pathname === '/functions/v1/license_extract') return J(w.doc ? { ok: true, mode: 'license', doc: w.doc } : { error: 'extract_unreadable' }, w.doc ? 200 : 502);
      if (u.pathname === '/functions/v1/ai_gateway') {
        w.gateway.push(await req.clone().text());
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO noted', reply: 'ZZ DEMO noted', lang: 'en', escalate: false }), model: 'stub/model' });
      }
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
      if (rpc) {
        w.rpcs.push({ fn: rpc[1], args: JSON.parse((await req.clone().text()) || '{}') });
        if (rpc[1] === 'fn_identify_contact') return J({ audience: 'supplier', name: 'ZZ DEMO Glass LLC', claimed: true, approved: true });
        if (rpc[1] === 'fn_wa_attach_document') return J(w.intake);
        return undefined;
      }
      if (u.pathname === '/rest/v1/leads' && req.method === 'PATCH') { w.leadPatches.push(JSON.parse(await req.clone().text())); return J([{ id: 77 }]); }
      if (u.pathname === '/rest/v1/doc_reviews' && req.method === 'POST') { w.reviews.push(JSON.parse(await req.clone().text())); return J([], 201); }
      if (u.pathname === '/rest/v1/agent_actions' && w.actions) {
        if (req.method === 'POST') { const b = JSON.parse(await req.clone().text()); w.actions.push(...(Array.isArray(b) ? b : [b])); return J([], 201); }
        const eq = (k: string) => (u.searchParams.get(k) || '').replace(/^eq\./, '');
        return J(w.actions.filter((a) => a.kind === eq('kind') && a.target_id === eq('target_id')
          && (!u.searchParams.get('detail->>file_sha') || (a.detail as Record<string, unknown>).file_sha === eq('detail->>file_sha'))).map(() => ({ id: 1 })));
      }
      if (u.pathname === '/rest/v1/leads' && req.method === 'GET' && w.actions) return J({ license_doc_path: null });
      return undefined;
    },
  };
}

let seq = 0;
async function sendFile(w: World, caption = '') {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: FROM, To: 'whatsapp:+14155550100', Body: caption, MessageSid: 'SMR1' + (++seq).toString(16).padStart(30, '0'),
    NumMedia: '1', MediaUrl0: 'https://api.twilio.com/2010-04-01/Accounts/AC/Messages/MM/Media/ME' + seq, MediaContentType0: 'image/png', ProfileName: 'ZZ DEMO' };
  const req = new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) },
    body: new URLSearchParams(params).toString() });
  return await invokeRequest(await fn(), stub(w), req, async () => { await Promise.all(pending); });
}
const world = (doc: Record<string, unknown> | null): World => ({ leadPatches: [], reviews: [], rpcs: [], gateway: [], doc,
  intake: { ok: true, intake_id: 9, lead_id: 77, classified_as: 'unknown', confidence: 'low', attached: false } });
const LICENCE_FIELDS = ['license_doc_path', 'trade_license_no', 'license_authority', 'license_expiry', 'licence_legal_name'];
const UNREADABLE = { legal_name: '', license_number: '', confidence: 'low', unreadable: true };

Deno.test('a product photo from a supplier never touches the licence record; it is kept pending and the supplier is told', async () => {
  const w = world(UNREADABLE);
  const r = await sendFile(w);
  assertEquals(r.status, 200);
  const touched = w.leadPatches.flatMap((p) => Object.keys(p)).filter((k) => LICENCE_FIELDS.includes(k));
  assertEquals(touched, [], 'no licence field may be written for a file that did not read as a licence: ' + JSON.stringify(w.leadPatches));
  const attach = w.rpcs.find((c) => c.fn === 'fn_wa_attach_document');
  assert(attach, 'the file goes to fn_wa_attach_document as a pending document');
  assert(/^inbound\/77\//.test(String(attach!.args.p_storage_path)) && !/licen/i.test(String(attach!.args.p_storage_path)), 'stored under a neutral name: ' + attach!.args.p_storage_path);
  assertEquals(w.reviews.length, 1);
  assertEquals(w.reviews[0].status, 'pending');
  assertEquals(w.reviews[0].auto_applied, false);
  assert(w.reviews[0].ai_category !== 'trade_license', 'not filed as a trade licence: ' + w.reviews[0].ai_category);
  const told = w.gateway.join(' ');
  assert(/did NOT read as a trade licence/.test(told) && /were NOT changed/.test(told), 'the supplier is told what was received and that nothing changed');
});

Deno.test('a caption that says "licence" does not make a photo a licence; the reader decides', async () => {
  const w = world(UNREADABLE);
  await sendFile(w, 'ZZ DEMO here is my trade licence');
  assertEquals(w.leadPatches.flatMap((p) => Object.keys(p)).filter((k) => LICENCE_FIELDS.includes(k)), []);
  assertEquals(w.rpcs.find((c) => c.fn === 'fn_wa_attach_document')?.args.p_caption, null, 'a licence caption is not passed on to be filed as a licence');
});

Deno.test('a low-confidence licence-like read and a failed read are both kept pending, never applied', async () => {
  for (const doc of [{ legal_name: '', legal_name_ar: 'ZZ DEMO زجاج', license_number: '20840', confidence: 'low', unreadable: false }, null]) {
    const w = world(doc);
    await sendFile(w);
    assertEquals(w.leadPatches.flatMap((p) => Object.keys(p)).filter((k) => LICENCE_FIELDS.includes(k)), [], JSON.stringify(doc));
    assertEquals(w.reviews[0]?.status, 'pending');
  }
});

Deno.test('known-good control: a licence read with confidence is applied as the portal applies one', async () => {
  const w = world({ legal_name: 'ZZ DEMO Glass LLC', license_number: 'ZZ-123456', license_authority: 'Dubai DET', expiry_date: '2027-05-01', confidence: 'high', unreadable: false });
  await sendFile(w);
  const p = w.leadPatches.find((x) => 'license_doc_path' in x);
  assert(p, 'the licence record is updated: ' + JSON.stringify(w.leadPatches));
  assertEquals(p!.trade_license_no, 'ZZ-123456');
  assertEquals(p!.license_expiry, '2027-05-01');
  assertEquals(w.rpcs.some((c) => c.fn === 'fn_wa_attach_document'), false);
  assertEquals(w.reviews[0].ai_category, 'trade_license');
});

// Review of #1996, R2 (13 Nov 2026, ruling 1681): a file the reader NAMES (here more pages than any licence) is told to him in the reader's
// own words, and recorded like every other door (one finding per file, with its SHA-256), so the same file sent twice opens one ceo task.
Deno.test('WhatsApp: a named file is quoted to him word for word and recorded; the same file twice opens one ceo task', async () => {
  const SENTENCE = 'This file has 12 pages. A trade licence is a short document, usually 1 to 4 pages, so this is not one. Please attach your trade licence here on its own. If this is your company profile, it goes in the Company profile box below. If your licence is inside this file, please attach just the licence pages. If this is your trade licence, reply to our e-mail or write to management@quotesdone.com and we will check it.';
  const doc = { ...UNREADABLE, wrong_document: { kind: 'long_file', why: 'the file has 12 pages', message: SENTENCE, file_sha: 'b'.repeat(64) }, held_for_person: null };
  const w = { ...world(doc), actions: [] as Record<string, unknown>[] };
  assertEquals((await sendFile(w)).status, 200);
  const touched = w.leadPatches.flatMap((p) => Object.keys(p)).filter((k) => LICENCE_FIELDS.includes(k));
  assertEquals(touched, [], 'a named file never touches the licence record');
  assert(w.gateway.some((g) => g.includes(JSON.stringify(SENTENCE).slice(1, -1))), 'the reply to him does not carry the reader\'s sentence');
  assertEquals(w.actions.filter((a) => a.kind === 'licence_wrong_document').length, 1);
  assertEquals(((w.actions[0].detail as Record<string, unknown>).file_sha), 'b'.repeat(64));
  assertEquals(w.rpcs.filter((c) => c.fn === 'fn_ceo_task_open').length, 0, 'the first refusal asks no one');
  w.rpcs.length = 0;
  assertEquals((await sendFile(w)).status, 200);
  assertEquals([w.actions.filter((a) => a.kind === 'licence_wrong_document').length, w.actions.filter((a) => a.kind === 'licence_refused_twice').length,
    w.rpcs.filter((c) => c.fn === 'fn_ceo_task_open').length], [2, 1, 1]);
});
