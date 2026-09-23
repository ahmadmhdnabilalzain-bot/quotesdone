// The live webhook takes a forwarded Mashreq statement in AS A STATEMENT (15 Sep 2026, agent: accountant).
// Drives resend_inbound's OWN handler with a signed delivery carrying an invented e-statement PDF, over a
// stubbed fetch (PostgREST, storage, VirusTotal). Asserts it goes to fn_accountant_bank_statement_ingest, is
// never HELD as a receipt and never reaches ai_gateway. No value below is real: ZZ DEMO, example.invalid.
import { assert, assertEquals } from 'jsr:@std/assert@1';

const SECRET_RAW = new Uint8Array(32).map((_, i) => i + 1);
const SIGNING = 'whsec_' + btoa(String.fromCharCode(...SECRET_RAW));
const TOKEN = 'zz-demo-inbound-token';
const FOUNDER = 'founder@example.invalid';
const SECRETS: Record<string, string> = {
  resend_inbound_token: TOKEN, resend_inbound_signing_secret: SIGNING,
  admin_emails: 'management@example.invalid', expense_forwarders: FOUNDER, cred_fn_ai: 'zz-demo-ai',
};

Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
Deno.env.set('RESEND_INBOUND_NO_SERVE', '1');

const INVITES_SENT = { n: 0 };
const SEEN_EMAIL_IDS = new Set<string>();
type Call = { url: string; method: string; body: string; prefer: string };
const calls: Call[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init);
  const url = req.url; const body = req.method === 'GET' ? '' : await req.text();
  calls.push({ url, method: req.method, body, prefer: req.headers.get('Prefer') || '' });
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  const u = new URL(url);
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);          // VirusTotal etc.
  if (u.pathname.startsWith('/storage/v1/object/')) return json({ Key: u.pathname, Id: 'zz' });
  if (u.pathname === '/rest/v1/rpc/fn_accountant_bank_statement_ingest') {
    const p = JSON.parse(body);
    return json({ source_ref: p.p_source_ref, lines: p.p_lines.length, new_lines: p.p_lines.length, state: p.p_lines.length ? 'parsed' : 'unreadable' });
  }
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json({ ok: true });
  // "have we ever sent this address an invitation?" -- a HEAD count; INVITES_SENT decides the answer
  if (u.pathname === '/rest/v1/notifications' && req.method === 'HEAD') {
    return new Response(null, { status: 200, headers: { 'Content-Range': '*/' + INVITES_SENT.n } });
  }
  // "is this Resend email already on file?" -- only the ids in SEEN_EMAIL_IDS are
  if (u.pathname === '/rest/v1/inbound_messages' && req.method === 'GET' && u.searchParams.has('provider_email_id')) {
    const id = (u.searchParams.get('provider_email_id') || '').replace(/^eq\./, '');
    return json(SEEN_EMAIL_IDS.has(id) ? [{ id: 77 }] : []);
  }
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  let row: Record<string, unknown> = { id: 1 };
  if (u.pathname === '/rest/v1/app_secrets') {
    const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')];
    if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]);
    row = { value: v };
  }
  return one ? json(row) : json([row]);
}) as typeof fetch;

const { handler } = await import('./index.ts');

// An invented e-statement in the real layout; the bank is named ONLY inside the document.
const LINES = [
  'Mashreqbank PSC is regulated by the Central Bank of the United Arab Emirates.',
  'Current Account Statement',
  'Account No 000111222333 AED',
  'Statement for Period 01/08/2026 to 31/08/2026',
  'Date Transaction Reference no Debit Credit Balance',
  'OPENING BALANCE 0.000 0.000 12,345.670',
  'TRANSFER IN',
  '000000000000ZZ000000000000000000000',
  '07/08/2026 000ZZZZ00000000ZZZ 0.000 2,500.000 14,845.670',
  '- ZZ DEMO SENDER - P_2_P -',
  '000000000000Z00000000000000000000',
  '09/08/2026 Monthly Maintenance Fee 000111222333 0ZZREFAED 00001 150.000 0.000 14,695.670',
  'VALUE DATE: 01-09-2026 Interest',
  '31/08/2026 0ZZCIDAED 00001 0.000 1,234.560 15,930.230',
  '000111222333',
  'CLOSING BALANCE 0.000 0.000 15,930.230',
];

function statementPdf(lines: string[]): Uint8Array {
  const content = lines.map((t, i) => `BT /F1 9 Tf 1 0 0 1 40 ${800 - i * 14} Tm (${t}) Tj ET`).join('\n');
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>',
    '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
  ];
  let pdf = '%PDF-1.4\n';
  objs.forEach((o, i) => { pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  pdf += 'trailer << /Root 1 0 R >>\n%%EOF\n';
  return Uint8Array.from(pdf, (c) => c.charCodeAt(0) & 0xff);
}

async function delivery(pdf: Uint8Array): Promise<Request> {
  const raw = JSON.stringify({ type: 'email.received', data: {
    email_id: 'zz-demo-0001', from: 'ZZ DEMO Founder <' + FOUNDER + '>', to: ['expenses@mail.quotesdone.com'],
    subject: 'statement', text: '',
    attachments: [{ filename: 'eStatement_02 Sep 2026_0000000000.pdf', content_type: 'application/pdf',
                    content: btoa(String.fromCharCode(...pdf)) }] } });
  const id = 'msg_zz_demo'; const ts = String(Math.floor(Date.now() / 1000));
  const key = await crypto.subtle.importKey('raw', SECRET_RAW, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(id + '.' + ts + '.' + raw)))));
  return new Request('http://stub.invalid/functions/v1/resend_inbound?s=' + TOKEN, {
    method: 'POST', body: raw, headers: { 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': 'v1,' + sig } });
}

const ingests = () => calls.filter((c) => c.url.endsWith('/rpc/fn_accountant_bank_statement_ingest')).map((c) => JSON.parse(c.body));
const noReceiptPath = () => {
  assertEquals(calls.filter((c) => /ai_gateway/.test(c.url)).length, 0);                      // never the model
  assertEquals(calls.filter((c) => /fn_receipt_hand_to_bookkeeper/.test(c.url)).length, 0);   // never handed over as a receipt
  assertEquals(calls.filter((c) => /inbound_messages/.test(c.url) && /\[HELD/.test(c.body)).length, 0);
  assertEquals(calls.filter((c) => /expense_entries/.test(c.url) && c.method !== 'GET').length, 0);
};

Deno.test({ name: 'a forwarded Mashreq statement goes to the statement intake, not to receipt-held', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  calls.length = 0;
  const res = await handler(await delivery(statementPdf(LINES)));
  const out = await res.json();
  assertEquals(res.status, 200);
  assertEquals([out.bank_statement, out.receipt, out.lines, out.adds_up], [true, false, 3, true]);
  const [ing] = ingests();
  assertEquals(ing.p_source_ref, 'resend:zz-demo-0001');
  assertEquals(ing.p_statement_month, '2026-08-01');
  assertEquals(ing.p_lines.map((l: { amount_aed: number }) => l.amount_aed), [2500, -150, 1234.56]);
  assertEquals(ing.p_note, null);
  const bal = calls.filter((c) => c.url.endsWith('/rpc/fn_accountant_bank_balance_record')).map((c) => JSON.parse(c.body));
  assertEquals(bal, [{ p_source_ref: 'resend:zz-demo-0001', p_balance_aed: 15930.23, p_on: '2026-08-31' }]);
  noReceiptPath();
} });

Deno.test({ name: 'a statement that does not add up is ingested empty with a finding note, still never a receipt', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  calls.length = 0;
  const bad = LINES.map((l) => l.replace('CLOSING BALANCE 0.000 0.000 15,930.230', 'CLOSING BALANCE 0.000 0.000 15,930.240'));
  const out = await (await handler(await delivery(statementPdf(bad)))).json();
  assertEquals([out.bank_statement, out.lines, out.adds_up], [true, 0, false]);
  const [ing] = ingests();
  assertEquals(ing.p_lines, []);
  assert(/does not add up/.test(ing.p_note));
  assertEquals(calls.filter((c) => /fn_accountant_bank_balance_record/.test(c.url)).length, 0);
  noReceiptPath();
} });

// 21 Sep 2026 (customer_support): the supplier mail's List-Unsubscribe mailto and footer now name
// unsubscribe@mail.quotesdone.com. Before, an unsubscribe by email reached an inbox no code read.
async function signed(data: Record<string, unknown>): Promise<Request> {
  const raw = JSON.stringify({ type: 'email.received', data });
  const id = 'msg_zz_demo_unsub'; const ts = String(Math.floor(Date.now() / 1000));
  const key = await crypto.subtle.importKey('raw', SECRET_RAW, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(id + '.' + ts + '.' + raw)))));
  return new Request('http://stub.invalid/functions/v1/resend_inbound?s=' + TOKEN, {
    method: 'POST', body: raw, headers: { 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': 'v1,' + sig } });
}
const suppressions = () => calls.filter((c) => c.url.includes('/rest/v1/email_suppressions') && c.method === 'POST');

// What SES writes at the top of a mail it authenticated (shape measured on a real inbound mail, 21 Sep 2026).
const SES = (dom: string) => ({ 'authentication-results': `amazonses.com; spf=pass (spfCheck) envelope-from=b@${dom}; dkim=pass header.i=@${dom}; dmarc=pass header.from=${dom};` });
const unsubMail = (from: string, headers?: Record<string, string>) => signed({ email_id: 'zz-demo-unsub-x', from,
  to: ['unsubscribe@mail.quotesdone.com'], subject: 'unsubscribe', text: 'This is a long enough body to skip the fetch.', ...(headers ? { headers } : {}) });
const reviewRows = () => calls.filter((c) => c.url.includes('/rest/v1/inbound_messages') && c.method === 'POST' && /UNSUBSCRIBE REQUEST NOT APPLIED/.test(c.body));

Deno.test({ name: 'a forged From naming an admin or our own domain suppresses nothing and is kept for review', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  INVITES_SENT.n = 5;
  for (const from of ['management@example.invalid', 'management@quotesdone.com', 'ZZ DEMO Founder <' + FOUNDER + '>']) {
    calls.length = 0;
    const out = await (await handler(await unsubMail(from, SES(from.replace(/.*@|>/g, ''))))).json();
    assertEquals([out.unsubscribe, out.suppressed], [true, false], from);
    assertEquals(suppressions().length, 0, from);
    assertEquals(reviewRows().length, 1, from);
  }
} });

Deno.test({ name: 'a forged second Authentication-Results, in any shape, suppresses nothing; the genuine one does', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  INVITES_SENT.n = 5;
  const real = 'amazonses.com; spf=fail; dkim=none; dmarc=fail header.from=example.invalid;';
  const forged = 'amazonses.com; dmarc=pass header.from=example.invalid;';
  const shapes: unknown[] = [
    [real, forged],                              // array[2]
    JSON.stringify([real, forged]),              // how Resend returns a repeated header (measured)
    real + ' ' + forged,                         // joined string
    [real + ' ' + forged],                       // first element carrying an injected block
  ];
  for (const ar of shapes) {
    calls.length = 0;
    const out = await (await handler(await unsubMail('victim@example.invalid', { 'authentication-results': ar as string }))).json();
    assertEquals([out.suppressed, suppressions().length, reviewRows().length], [false, 0, 1], JSON.stringify(ar));
  }
  calls.length = 0;
  const ok = await (await handler(await unsubMail('victim@example.invalid', SES('example.invalid')))).json();
  assertEquals([ok.suppressed, suppressions().length], [true, 1]);
} });

Deno.test({ name: 'an unauthenticated From, or an address we never invited, suppresses nothing', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  INVITES_SENT.n = 5; calls.length = 0;
  let out = await (await handler(await unsubMail('victim@example.invalid'))).json();                       // no SES verdict
  assertEquals([out.suppressed, suppressions().length, reviewRows().length], [false, 0, 1]);
  INVITES_SENT.n = 0; calls.length = 0;
  out = await (await handler(await unsubMail('stranger@example.invalid', SES('example.invalid')))).json();  // authenticated, never mailed
  assertEquals([out.suppressed, suppressions().length, reviewRows().length], [false, 0, 1]);
} });

Deno.test({ name: 'an email to the unsubscribe mailbox suppresses its sender and keeps an existing bounce record', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  calls.length = 0; INVITES_SENT.n = 1;
  const out = await (await handler(await unsubMail('ZZ DEMO Supplier <Supplier.Owner@example.invalid>', SES('example.invalid')))).json();
  assertEquals([out.unsubscribe, out.suppressed], [true, true]);
  const [s] = suppressions();
  const row = JSON.parse(s.body);
  assertEquals(Array.isArray(row) ? row[0] : row, { email: 'supplier.owner@example.invalid', reason: 'unsubscribe', source: 'reply' });
  assert(s.url.includes('on_conflict=email'));
  assert(/resolution=ignore-duplicates/.test(s.prefer), 'an existing hard-bounce or complaint row is never relabelled');
  assertEquals(calls.filter((c) => /ai_gateway|leads/.test(c.url) && c.method !== 'GET').length, 0);   // no model, no supplier record touched
} });

Deno.test({ name: 'a supplier document email that mentions stopping is not an unsubscribe', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  calls.length = 0;
  await handler(await signed({ email_id: 'zz-demo-unsub-2', from: 'ZZ DEMO Supplier <owner@example.invalid>',
    to: ['docs@mail.quotesdone.com'], subject: 'Re: licence renewal', text: 'Please do not stop the tender. Licence attached next week.' }));
  assertEquals(suppressions().length, 0);
} });

// A REDELIVERY IS NOT A NEW EMAIL (it_engineer, 22 Sep 2026, founder instruction 705). Resend retries any
// non-2xx; an email already on file under its Resend id must not reach a reader or the model again.
Deno.test({ name: 'a redelivered email already on file is answered before any reader or model runs', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  SEEN_EMAIL_IDS.add('zz-demo-0001'); calls.length = 0;
  try {
    const res = await handler(await delivery(statementPdf(LINES)));
    const out = await res.json();
    assertEquals([res.status, out.duplicate, out.inbound_message_id], [200, true, 77]);
    assertEquals(calls.filter((c) => /ai_gateway|license_extract|\/rpc\/fn_accountant/.test(c.url)).length, 0);
    assertEquals(calls.filter((c) => /\/rest\/v1\/(inbound_messages|expense_entries)/.test(c.url) && c.method !== 'GET').length, 0);
  } finally { SEEN_EMAIL_IDS.delete('zz-demo-0001'); }
} });

// HIS REPLY TO THE MONTHLY SOCIAL CALENDAR (marketing, 23 Sep 2026, founder_instruction 872). The handler reads
// the token, the sender, SES's verdict and the words; fn_marketing_calendar_reply decides (its checks are proved
// by the aborted-transaction probe). Here: the reply reaches it and ONLY it, with the right verdict.
const CAL_TOKEN = '0123456789abcdef0123456789abcdef';
const calReply = (text: string, headers?: Record<string, string>, to = `calendar+${CAL_TOKEN}@mail.quotesdone.com`, from = 'ZZ DEMO Founder <management@example.invalid>') =>
  signed({ email_id: 'zz-demo-cal-' + Math.random(), from, to: [to], subject: 'Re: Social calendar October 2026: 12 posts for your approval', text, ...(headers ? { headers } : {}) });
const calCalls = () => calls.filter((c) => c.url.endsWith('/rpc/fn_marketing_calendar_reply')).map((c) => JSON.parse(c.body).p);

Deno.test({ name: 'a calendar reply goes to fn_marketing_calendar_reply with the SES verdict and its intent, and nowhere else', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  calls.length = 0;
  let out = await (await handler(await calReply('Approve\n\nOn Tue QuotesDone wrote:\n> the calendar', SES('example.invalid')))).json();
  assertEquals(out.calendar_reply, true);
  assertEquals(calCalls(), [{ token: CAL_TOKEN, from_email: 'management@example.invalid', authenticated: true, message_id: calCalls()[0].message_id, intent: 'approve' }]);
  assertEquals(calls.filter((c) => /ai_gateway|fn_receipt_hand_to_bookkeeper|fn_accountant|email_suppressions|\/leads/.test(c.url) && c.method !== 'GET').length, 0);
  // forged: no SES pass -> authenticated false (the function refuses it)
  calls.length = 0;
  await handler(await calReply('approve'));
  assertEquals(calCalls()[0].authenticated, false);
  // Arabic approval; an ambiguous reply is 'unclear'
  calls.length = 0;
  await handler(await calReply('موافق', SES('example.invalid')));
  assertEquals(calCalls()[0].intent, 'approve');
  calls.length = 0;
  await handler(await calReply('looks fine but change the third video', SES('example.invalid')));
  assertEquals(calCalls()[0].intent, 'unclear');
  // the token also comes from the subject when the client replied to another address
  calls.length = 0;
  out = await (await handler(await signed({ email_id: 'zz-demo-cal-s', from: 'management@example.invalid', to: ['info@quotesdone.com'],
    subject: `Re: Social calendar [ref ${CAL_TOKEN}]`, text: 'approved', headers: SES('example.invalid') }))).json();
  assertEquals([out.calendar_reply, calCalls()[0].token], [true, CAL_TOKEN]);
} });
