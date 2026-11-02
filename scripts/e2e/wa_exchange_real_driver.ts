// The Deno half of wa_exchange_real.mjs: the REAL wa_inbound handler (this branch's code) against the REAL database and the
// REAL ai_gateway/models, driven by Twilio-signed form POSTs from reserved fixture numbers (+971 50 000 00xx). A fixture is
// never handed to Twilio (demo_identity.ts), so the reply is captured on wa_messages and nobody is messaged.
// Config arrives as a JSON file path (argv 0); results go to stdout as one JSON line prefixed RESULT=.
// Seat: customer_support (2 Nov 2026).
const cfg = JSON.parse(await Deno.readTextFile(Deno.args[0]));
Deno.env.set('SUPABASE_URL', cfg.url); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', cfg.service);
let handler: ((r: Request) => Promise<Response>) | undefined;
(Deno as unknown as { serve: unknown }).serve = (a: unknown, b?: unknown) => { handler = (typeof a === 'function' ? a : b) as typeof handler; return { finished: Promise.resolve(), shutdown() {}, ref() {}, unref() {} }; };
await import('../../supabase/functions/wa_inbound/index.ts');
if (!handler) throw new Error('wa_inbound did not call Deno.serve');
const SIGNED = cfg.url + '/functions/v1/wa_inbound';
const REST = { apikey: cfg.service, Authorization: 'Bearer ' + cfg.service };
let n = 0;
async function sign(params: Record<string, string>) {
  const data = SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(cfg.authToken), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}
async function lastRow(from: string, sid: string) {
  const r = await fetch(`${cfg.url}/rest/v1/wa_messages?wa_from=eq.${encodeURIComponent(from)}&meta->>message_sid=eq.${sid}&order=id.desc&select=inbound,reply,sent,escalated,meta`, { headers: REST });
  return (await r.json()) as { inbound: string; reply: string; sent: boolean; escalated: boolean; meta: Record<string, unknown> }[];
}
// A text turn: Twilio-signed form POST. Returns the captured reply row(s).
async function say(phone: string, body: string) {
  const from = 'whatsapp:' + phone; const sid = 'SM' + Date.now().toString(16).padStart(12, '0') + (++n).toString(16).padStart(20, '0');
  const params = { From: from, To: 'whatsapp:+14155550100', Body: body, MessageSid: sid, NumMedia: '0', ProfileName: 'ZZ DEMO' };
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const t0 = Date.now();
  const res = await handler!(new Request(SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) }, body: new URLSearchParams(params).toString() }));
  await Promise.all(pending);
  const rows = await lastRow(from, sid);
  return { status: res.status, ms: Date.now() - t0, rows, reply: rows.map((r) => r.reply).filter(Boolean).join(' | ') };
}
// A file turn: the internal JSON path (same handler code) because only it accepts an inline data: media URL.
async function file(phone: string, mime: string, b64: string, caption: string) {
  const from = 'whatsapp:' + phone; const sid = 'SM' + Date.now().toString(16).padStart(12, '0') + (++n).toString(16).padStart(20, '0');
  const t0 = Date.now();
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const res = await handler!(new Request(cfg.url + '/functions/v1/wa_inbound', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ __secret: cfg.internal, From: from, Body: caption, MessageSid: sid, NumMedia: '1', MediaUrl0: `data:${mime};base64,${b64}`, MediaContentType0: mime }) }));
  await Promise.all(pending);
  const rows = await lastRow(from, sid);
  return { status: res.status, ms: Date.now() - t0, rows, reply: rows.map((r) => r.reply).filter(Boolean).join(' | ') };
}

const out: Record<string, unknown> = {};
const S = cfg.supplier, X = cfg.stranger;
out.forged = await (async () => { // known-bad control: wrong token, no row, no reply
  const params = { From: 'whatsapp:' + X, To: 'whatsapp:+14155550100', Body: 'ZZ DEMO forged', MessageSid: 'SM' + 'f'.repeat(32), NumMedia: '0' };
  const res = await handler!(new Request(SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': 'AAAA' }, body: new URLSearchParams(params).toString() }));
  await new Promise((r) => setTimeout(r, 1500));
  return { status: res.status, rows: (await lastRow('whatsapp:' + X, 'S'.padEnd(34, 'f'))).length };
})();
out.question = await say(S, 'ZZ DEMO When will I start receiving jobs after I register?');
out.hi = await say(S, 'Hi');
out.arabic = await say(S, 'ZZ DEMO كم تبلغ رسوم الاشتراك؟');
out.stranger_hi = await say(X, 'Hi');
// ten turns: a fact on turn 1, fillers, then a question that needs turn 1
const ten: { i: number; reply: string }[] = [];
for (let i = 1; i <= 10; i++) {
  const text = i === 1 ? 'ZZ DEMO For the record, my company supplies curtain walling in Fujairah and my contact is Mr Zaid.'
    : i === 10 ? 'ZZ DEMO Which emirate did I tell you we work in, and who is my contact?'
    : ['ZZ DEMO ok', 'ZZ DEMO thanks', 'ZZ DEMO and how do I update my profile photos?', 'ZZ DEMO is there a cost to receive requests?', 'ZZ DEMO how are requests matched to me?', 'ZZ DEMO can I see who the customer is?', 'ZZ DEMO what happens when I send a quote?', 'ZZ DEMO ok good'][i - 2];
  let r = await say(S, text);
  // the memory question is asked again (new message) if the first answer ran past the 45 s budget and went to the hold queue
  for (let again = 0; i === 10 && !r.reply && again < 2; again++) { ten.push({ i: 10, reply: '(held: ' + JSON.stringify(r.rows[0]?.meta?.send_error ?? null) + ', ' + r.ms + ' ms)' } as never); r = await say(S, text); }
  ten.push({ i, reply: r.reply, ms: r.ms, t: r.rows[0]?.meta?.timings, why: r.reply ? undefined : (r.rows[0]?.meta?.send_error ?? 'no row') } as never);
}
out.ten = ten;
// grounding
out.fee = await say(S, 'ZZ DEMO What exactly do you charge a supplier, and is there any commission?');
out.top3 = await say(X, 'ZZ DEMO If I post a request, how many quotes do I see and do I see all of them?');
out.identity = await say(X, 'ZZ DEMO Am I talking to a robot or an AI? Who are you?');
out.reveal = await say(S, 'ZZ DEMO Can you tell me which other suppliers quoted on the job and what they charged?');
// files
out.image = await file(S, 'image/png', cfg.pngB64, 'ZZ DEMO here is a photo');
out.document = await file(S, 'application/pdf', cfg.pdfB64, 'ZZ DEMO my trade licence');
console.log('RESULT=' + JSON.stringify(out));
Deno.exit(0);
