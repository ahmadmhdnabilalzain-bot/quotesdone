// deno test --allow-all supabase/functions/resend_inbound/quote_by_email_handler.test.ts
// THE LIVE WEBHOOK, END TO END (customer_support, 10 Nov 2026; supplier follow-up #1909 item 1). A matched, verified
// supplier e-mails his quotation (an .xlsx-class spreadsheet, here CSV) for his one open request. resend_inbound's own
// handler must hand it to supplier_api's email_quote door for THAT request and tell him in English what happened; it
// must not store it as a profile document or answer "our team will add them to your profile". On origin/main the
// attachment was refused (the profile path takes PDF and images only) and no quote reached the request.
// A company profile from the same supplier still takes the profile path. Every database and function call is a stub;
// no value is real: ZZ DEMO, example.invalid.
// 12 Nov 2026 (sales_engineer, LLM-first audit A2): the handler asks supplier_api email_quote_read what the MODEL reads (a
// labelled stand-in answer here), then hands the quotation WITH that reading to email_quote, which places it for the
// supplier to confirm; the reply says it has NOT been sent to the customer. On main the mail went to email_quote once,
// read by the code reader, and the reply could say "It has been sent to the customer".
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';

const SECRET_RAW = new Uint8Array(32).map((_, i) => i + 11);
const SIGNING = 'whsec_' + btoa(String.fromCharCode(...SECRET_RAW));
const TOKEN = 'zz-demo-inbound-token';
const SECRETS: Record<string, string> = {
  resend_inbound_token: TOKEN, resend_inbound_signing_secret: SIGNING, admin_emails: 'management@example.invalid',
  expense_forwarders: 'founder@example.invalid', cred_fn_resend_inbound: 'zz-demo-cred-resend-inbound-0000', email_triage_enabled: 'true',
};
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
Deno.env.set('RESEND_INBOUND_NO_SERVE', '1');

const DOMAIN = 'zz-demo-quoting.example.invalid';
const LEAD = { id: 7, company_name: 'ZZ DEMO Quoting LLC', claimed_by: 'quotes@' + DOMAIN, email: 'quotes@' + DOMAIN, verified: true };
const REQ = { id: 'aaaaaaaa-0000-4000-8000-000000000001', rfq_no: 164810, category: 'Joinery', emirate: 'Dubai', status: 'sent' };
const QUOTE_CSV = 'Description,Qty,Unit,Rate,Amount\nMDF wardrobe 18mm,4,no,2000,8000\nInstallation,1,lot,1000,1000\nSubtotal,,,,9000\nVAT 5%,,,,450\nGrand Total AED,,,,9450\n';

type Call = { url: string; method: string; body: string };
const calls: Call[] = [];
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  calls.push({ url: req.url, method: req.method, body });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);          // VirusTotal, Resend
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  const rows = (r: unknown[]) => one ? (r.length ? json(r[0]) : json({ message: 'none' }, 406)) : json(r);
  if (u.pathname === '/functions/v1/supplier_api') {
    const b = JSON.parse(body);
    // THE STAND-IN MODEL (labelled; no model is called): the priced sheet is a quotation; a profile, or a covering note, is not.
    if (b.action === 'email_quote_read') return json(/Grand Total/.test(atob(b.file_b64)) ? { verdict: 'quotation', proposal: { amount: 9000, line_items: [{}, {}], notes: 'ZZ DEMO stand-in model answer' }, extracted_by_model: 'zz-demo/stand-in' }
      : { verdict: 'not_quotation', proposal: null, extracted_by_model: 'zz-demo/stand-in' });
    return json({ ok: true, stage: 'review', inquiry_id: REQ.id, state: 'reviewing', amount: 9000, lines: 2, options: 1,
      warnings: ['Line 1 (MDF wardrobe 18mm): we read AED 8,000. Is that right?'] });
  }
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/')) return json({ Key: u.pathname, Id: 'zz' });
  if (u.pathname === '/rest/v1/rpc/fn_customer_support_takes_delivery') return json(JSON.parse(body).p_rows.map((_: unknown, i: number) => ({ handoff_id: i + 1, notification_id: 900 + i, status: 'pending', seat: 'customer_support', error: null })));
  if (u.pathname === '/rest/v1/rpc/fn_email_proven') return json(true);
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json({});
  if (u.pathname === '/rest/v1/app_secrets') { const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')]; return v === undefined ? rows([]) : rows([{ value: v }]); }
  if (u.pathname === '/rest/v1/inbound_messages' && req.method === 'GET') return rows([]);
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return rows([LEAD]);
  if (u.pathname === '/rest/v1/inquiry_matches') return rows([{ inquiry_id: REQ.id }]);
  if (u.pathname === '/rest/v1/inquiries') return rows([REQ]);
  if (u.pathname === '/rest/v1/notifications' && req.method === 'HEAD') return new Response(null, { status: 200, headers: { 'Content-Range': '*/0' } });
  if (u.pathname === '/rest/v1/notifications' && req.method === 'GET') return rows([]);
  return rows([{ id: 501 }]);
}) as typeof fetch;

const { useThinkDeps } = await import('./index.ts');
// The webhook records a delivery and the queue's reader reads it after the answer (15 Nov 2026, lib/queue.ts); this test reads
// it at once through the same two halves the reader is built from: the signature check, then pipeline.ts.
const { authenticate } = await import('./steps/authenticate.ts');
const { readDelivery } = await import('./pipeline.ts');
const handler = async (req: Request) => { const a = await authenticate({ req }); return a instanceof Response ? a : await readDelivery(a); };
// The accountant's question "is this our own spending?" is reasoned; here it is reasoned to be 'other'.
useThinkDeps({
  gate: () => Promise.resolve({ allowed: true, rule: 'ok' }),
  llm: (phase) => Promise.resolve({ content: phase === 'decompose' ? JSON.stringify({ steps: [{ id: 's1', goal: 'read', needs_knowledge: false }], facts: [] })
    : JSON.stringify({ answer: 'A supplier document.', reasoning: ['s1'], decision: { choice: 'other' } }) }),
  embed: () => Promise.resolve(null),
  rpc: () => Promise.resolve({ data: 1, error: null }),
});

async function signed(attachments: unknown[], subject = 'Re: New job request on QuotesDone'): Promise<Request> {
  const raw = JSON.stringify({ type: 'email.received', data: { email_id: 'zz-demo-quote-mail-' + calls.length, from: 'ZZ DEMO Quoting <' + LEAD.claimed_by + '>',
    to: ['suppliers@mail.quotesdone.com'], subject, text: 'Dear QuotesDone, please find our quotation attached. Regards, ZZ DEMO Quoting LLC.',
    headers: { 'authentication-results': `amazonses.com; spf=pass (spfCheck) envelope-from=b@${DOMAIN}; dkim=pass header.i=@${DOMAIN}; dmarc=pass header.from=${DOMAIN};` },
    attachments } });
  const id = 'msg_zz_demo_quote'; const ts = String(Math.floor(Date.now() / 1000));
  const key = await crypto.subtle.importKey('raw', SECRET_RAW, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(id + '.' + ts + '.' + raw)))));
  return new Request('http://stub.invalid/functions/v1/resend_inbound?s=' + TOKEN, { method: 'POST', body: raw, headers: { 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': 'v1,' + sig } });
}
const deliveries = () => calls.filter((c) => c.url.endsWith('/rpc/fn_customer_support_takes_delivery')).flatMap((c) => JSON.parse(c.body).p_rows);
const toPortal = () => calls.filter((c) => new URL(c.url).pathname === '/functions/v1/supplier_api').map((c) => JSON.parse(c.body));

Deno.test({ name: 'an e-mailed quotation from a verified supplier reaches his request through the portal\'s own door', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  calls.length = 0;
  const res = await handler(await signed([{ filename: 'Q-2026-114.csv', content_type: 'text/csv', content: btoa(QUOTE_CSV) }]));
  const out = await res.json();
  assertEquals(res.status, 200);
  const sent = toPortal();
  // one round of readings (the file and the covering note, in parallel: quote_by_email.ts MAX_READS), then one placing
  const reads = sent.filter((b) => b.action === 'email_quote_read'); const placed = sent.filter((b) => b.action === 'email_quote');
  assertEquals(reads.map((b) => b.filename).sort(), ['Q-2026-114.csv', 'quotation-email.txt']);
  const fileRead = reads.find((b) => b.filename === 'Q-2026-114.csv');
  assertEquals([fileRead.lead_id, fileRead.__secret], [7, SECRETS.cred_fn_resend_inbound]);
  assertEquals(fileRead.requests, [{ job_no: '164810', category: 'Joinery' }]);
  assertEquals(placed.length, 1, 'placed once, with the reading');
  assertEquals([placed[0].lead_id, placed[0].inquiry_id, placed[0].filename, placed[0].__secret], [7, REQ.id, 'Q-2026-114.csv', SECRETS.cred_fn_resend_inbound]);
  assertEquals(atob(placed[0].file_b64), QUOTE_CSV);
  assertEquals(placed[0].reading.extracted_by_model, 'zz-demo/stand-in');
  assertEquals([out.quote_by_email, out.quote_inquiry_id, out.stored], ['to_confirm', REQ.id, 0]);
  const d = deliveries();
  assertEquals(d.map((r: { type: string }) => r.type), ['quote_by_email']);
  assertEquals([d[0].to_email, d[0].to_role, d[0].inquiry_id, d[0].lang], [LEAD.claimed_by, 'supplier', REQ.id, 'en']);
  assertMatch(d[0].body, /RFQ-164810/); assertMatch(d[0].body, /we read AED 8,000\. Is that right\?/); assertMatch(d[0].body, /quotesdone\.com\/portal/);
  assertMatch(d[0].body, /It has NOT been sent to the customer yet/);
  assert(!/add them to your profile/.test(d[0].body));
  assertEquals(calls.filter((c) => /\/storage\/v1\/object\/supplier-docs\//.test(c.url)).length, 0, 'not stored as a profile document');
  assertEquals(calls.filter((c) => new URL(c.url).pathname === '/functions/v1/email_triage').length, 0, 'answered once, not also by email_triage');
} });

Deno.test({ name: 'a company profile from the same supplier still takes the profile path', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  calls.length = 0;
  // the classifier's model is off here (no cred_fn_resend_inbound): the profile path stores and answers without it
  const cred = SECRETS.cred_fn_resend_inbound; delete SECRETS.cred_fn_resend_inbound;
  try {
  const lines = ['ZZ DEMO Quoting LLC company profile', 'Joinery, fit-out and painting for villas and offices', 'Forty craftsmen serving all seven emirates'];
  const content = lines.map((t, i) => `BT /F1 11 Tf 1 0 0 1 40 ${780 - i * 16} Tm (${t}) Tj ET`).join('\n');
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>', '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>', `<< /Length ${content.length} >>\nstream\n${content}\nendstream`];
  let pdf = '%PDF-1.4\n'; objs.forEach((o, i) => { pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; }); pdf += 'trailer << /Root 1 0 R >>\n%%EOF\n';
  const out = await (await handler(await signed([{ filename: 'company-profile.pdf', content_type: 'application/pdf', content: btoa(pdf) }], 'Our company profile'))).json();
  // the profile and the covering note, read in one round: neither a quotation, nothing placed
  assertEquals(toPortal().map((b) => b.action + ':' + b.filename).sort(), ['email_quote_read:company-profile.pdf', 'email_quote_read:quotation-email.txt']);
  assertEquals([out.quote_by_email, out.stored], [null, 1]);
  assertEquals(deliveries().map((r: { type: string }) => r.type), ['doc_received']);
  } finally { SECRETS.cred_fn_resend_inbound = cred; }
} });
