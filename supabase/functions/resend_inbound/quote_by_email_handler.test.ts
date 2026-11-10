// deno test --allow-all supabase/functions/resend_inbound/quote_by_email_handler.test.ts
// THE LIVE WEBHOOK, END TO END (customer_support, 10 Nov 2026; supplier follow-up #1909 item 1). A matched, verified
// supplier e-mails his quotation (an .xlsx-class spreadsheet, here CSV) for his one open request. resend_inbound's own
// handler must hand it to supplier_api's email_quote door for THAT request and tell him in English what happened; it
// must not store it as a profile document or answer "our team will add them to your profile". On origin/main the
// attachment was refused (the profile path takes PDF and images only) and no quote reached the request.
// A company profile from the same supplier still takes the profile path. Every database and function call is a stub;
// no value is real: ZZ DEMO, example.invalid.
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
  if (u.pathname === '/functions/v1/supplier_api') return json({ ok: true, stage: 'submit', inquiry_id: REQ.id, accepted: false, held: true,
    missing: [{ label_en: 'Line 1 (MDF wardrobe 18mm): the board brand and grade' }], message: null, code: 'spec_hold', amount: 9000, lines: 2, options: 1 });
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

const { handler, useThinkDeps } = await import('./index.ts');
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
  assertEquals(sent.length, 1, 'the quotation goes to supplier_api once');
  assertEquals([sent[0].action, sent[0].lead_id, sent[0].inquiry_id, sent[0].filename, sent[0].__secret], ['email_quote', 7, REQ.id, 'Q-2026-114.csv', SECRETS.cred_fn_resend_inbound]);
  assertEquals(atob(sent[0].file_b64), QUOTE_CSV);
  assertEquals([out.quote_by_email, out.quote_inquiry_id, out.stored], ['submitted', REQ.id, 0]);
  const d = deliveries();
  assertEquals(d.map((r: { type: string }) => r.type), ['quote_by_email']);
  assertEquals([d[0].to_email, d[0].to_role, d[0].inquiry_id, d[0].lang], [LEAD.claimed_by, 'supplier', REQ.id, 'en']);
  assertMatch(d[0].body, /RFQ-164810/); assertMatch(d[0].body, /board brand and grade/); assertMatch(d[0].body, /quotesdone\.com\/portal/);
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
  assertEquals(toPortal().length, 0, 'a profile is not a quotation');
  assertEquals([out.quote_by_email, out.stored], [null, 1]);
  assertEquals(deliveries().map((r: { type: string }) => r.type), ['doc_received']);
  } finally { SECRETS.cred_fn_resend_inbound = cred; }
} });
