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
// EVERY REQUEST NAMES ITS RUN AND PROVES IT (it_engineer, 3 Nov 2026). Measured: 48 exchange runs on 2-3 Nov posted Twilio-signed
// turns with no tag, so observe() ran them untagged and the window's USD cap never applied. The run tag and the internal secret
// ride on every request this driver makes: text turns, file turns and the forged control. No run tag, no run.
if (!cfg.e2e?.tag || !cfg.e2e?.secret) throw new Error('REFUSED: no run tag and secret in the config; an untagged exchange would spend outside its cap');
const TAG_HEADERS: Record<string, string> = { 'x-qd-e2e-run': cfg.e2e.tag, 'x-qd-e2e-secret': cfg.e2e.secret };
async function sign(params: Record<string, string>) {
  const data = SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(cfg.authToken), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}
async function lastRow(from: string, sid: string) {
  const r = await fetch(`${cfg.url}/rest/v1/wa_messages?wa_from=eq.${encodeURIComponent(from)}&meta->>message_sid=eq.${sid}&order=id.desc&select=inbound,reply,lang,sent,escalated,meta`, { headers: REST });
  return (await r.json()) as { inbound: string; reply: string; sent: boolean; escalated: boolean; meta: Record<string, unknown> }[];
}
// A text turn: Twilio-signed form POST. Returns the captured reply row(s).
async function say(phone: string, body: string) {
  const from = 'whatsapp:' + phone; const sid = 'SM' + Date.now().toString(16).padStart(12, '0') + (++n).toString(16).padStart(20, '0');
  const params = { From: from, To: 'whatsapp:+14155550100', Body: body, MessageSid: sid, NumMedia: '0', ProfileName: 'ZZ DEMO' };
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const t0 = Date.now();
  const res = await handler!(new Request(SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params), ...TAG_HEADERS }, body: new URLSearchParams(params).toString() }));
  await Promise.all(pending);
  const rows = await lastRow(from, sid);
  return { status: res.status, ms: Date.now() - t0, rows, reply: rows.map((r) => r.reply).filter(Boolean).join(' | ') };
}
// A file turn: the internal JSON path (same handler code) because only it accepts an inline data: media URL.
// cfg.internals is every candidate credential (cred_fn_wa_inbound, then cred_ops_wa_replay, which the 19 Oct channels run used).
// A rejected credential is SILENT (the handler returns an empty 200), which is how image/document read "200, 0 rows, no reply"
// on 2 Nov; so each candidate is tried until the turn leaves a row, and which one worked is reported.
async function file(phone: string, mime: string, b64: string, caption: string) {
  const from = 'whatsapp:' + phone;
  let last: { status: number; ms: number; rows: Awaited<ReturnType<typeof lastRow>>; reply: string; cred?: number } | null = null;
  for (let c = 0; c < cfg.internals.length; c++) {
    const sid = 'SM' + Date.now().toString(16).padStart(12, '0') + (++n).toString(16).padStart(20, '0');
    const t0 = Date.now();
    const pending: Promise<unknown>[] = [];
    (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
    const res = await handler!(new Request(cfg.url + '/functions/v1/wa_inbound', { method: 'POST', headers: { 'content-type': 'application/json', ...TAG_HEADERS },
      body: JSON.stringify({ __secret: cfg.internals[c], From: from, Body: caption, MessageSid: sid, NumMedia: '1', MediaUrl0: `data:${mime};base64,${b64}`, MediaContentType0: mime }) }));
    await Promise.all(pending);
    const rows = await lastRow(from, sid);
    last = { status: res.status, ms: Date.now() - t0, rows, reply: rows.map((r) => r.reply).filter(Boolean).join(' | '), cred: c };
    if (rows.length) return last;
  }
  return last!;
}

const out: Record<string, unknown> = {};
const S = cfg.supplier, X = cfg.stranger;
async function mediaTurns() {
  out.image = await file(S, 'image/png', cfg.pngB64, 'ZZ DEMO here is a photo');
  out.document = await file(S, 'application/pdf', cfg.pdfB64, 'ZZ DEMO my trade licence');
  // controls that must fail the way a real bad file does: bytes that are not what the label says, and a voice note.
  const junk = btoa('this is plain text, not an image and not a pdf');
  out.bad_image_control = await file(S, 'image/png', junk, 'ZZ DEMO photo');
  out.bad_pdf_control = await file(S, 'application/pdf', junk, 'ZZ DEMO licence');
  out.voice = await file(S, 'audio/ogg', btoa('OggS-not-real-audio'), '');
  out.stranger_image = await file(X, 'image/png', cfg.pngB64, 'ZZ DEMO photo from a number with no account');
  }
// cfg.script (scripts/eval/conversation_quality.mjs, 3 Nov 2026): scripted conversations, one per number, and nothing else.
// Each turn is a text turn from that number; the transcript is what the person would have read.
if (cfg.script) {
  const conv: Record<string, { role: string; text: string; ms?: number }[]> = {};
  for (const [who, turns] of Object.entries(cfg.script as Record<string, string[]>)) {
    const phone = who === 'supplier' ? S : X; conv[who] = [];
    for (const text of turns) {
      const r = await say(phone, text);
      // what the handler decided for the turn, so a wrong reply can be traced to its path (route, audience, language, attempts)
      const m = (r.rows[0]?.meta ?? {}) as Record<string, unknown>;
      const trace = { lang: (r.rows[0] as { lang?: string } | undefined)?.lang ?? null, ...Object.fromEntries(['route', 'audience', 'lang', 'route_intent', 'model', 'reply_attempts', 'outage'].filter((k) => k in m).map((k) => [k, JSON.stringify(m[k]).slice(0, 400)])) };
      conv[who].push({ role: 'customer', text }, { role: 'agent', text: r.reply || `(NO ANSWER: ${r.status} ${JSON.stringify(r.rows[0]?.meta?.send_error ?? 'no row')})`, ms: r.ms, trace } as never);
    }
  }
  console.log('RESULT=' + JSON.stringify({ script: conv })); Deno.exit(0);
}
// cfg.mediaOnly: the six file turns and nothing else (the coordinator's short live run, 2 Nov: one live test at a time, USD 1 cap).
if (cfg.mediaOnly) { await mediaTurns(); console.log('RESULT=' + JSON.stringify(out)); Deno.exit(0); }
out.forged = await (async () => { // known-bad control: wrong token, no row, no reply
  const params = { From: 'whatsapp:' + X, To: 'whatsapp:+14155550100', Body: 'ZZ DEMO forged', MessageSid: 'SM' + 'f'.repeat(32), NumMedia: '0' };
  const res = await handler!(new Request(SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': 'AAAA', ...TAG_HEADERS }, body: new URLSearchParams(params).toString() }));
  await new Promise((r) => setTimeout(r, 1500));
  return { status: res.status, rows: (await lastRow('whatsapp:' + X, 'S'.padEnd(34, 'f'))).length };
})();
// PARITY: the same five messages classified in the old full shape (brief sent) and the lean shape, each from a fresh
// fixture number so the chat history is the same (none). The deterministic intent and the needs-a-person reading must match.
{
  const { waLean } = await import('../../supabase/functions/_shared/reasoned_channels.ts');
  const msgs = ['ZZ DEMO How much does it cost to be listed on QuotesDone?', 'ZZ DEMO Do you cover glass balustrades?', 'ZZ DEMO I want to speak to a person please',
    'ZZ DEMO my villa air conditioning is broken, who can fix it?', 'ZZ DEMO you took my money and vanished, this is a scam'];
  const read = async (phone: string, lean: boolean) => {
    waLean.on = lean; const res = [];
    try { for (const m of msgs) { const r = await say(phone, m); const meta = r.rows[0]?.meta ?? {}; res.push({ ms: r.ms, intent: meta.route_intent ?? null, person: meta.asked_for_a_person ?? null, answered: !!r.reply, cls: (meta.timings as Record<string, number> | undefined)?.classified ?? null, att: meta.reply_attempts ?? null }); } }
    finally { waLean.on = true; }
    return res;
  };
  const oldR = await read(cfg.parityOld, false); const newR = await read(cfg.parityNew, true);
  out.parity = msgs.map((m, i) => ({ m: m.slice(8, 50), old: oldR[i], lean: newR[i], same: oldR[i].intent === newR[i].intent && oldR[i].person === newR[i].person }));
  // known-bad control: the comparison itself must fail on a different intent
  const cmp = (a: { intent: unknown; person: unknown }, b: { intent: unknown; person: unknown }) => a.intent === b.intent && a.person === b.person;
  out.parity_control_detects_a_difference = cmp({ intent: 'pricing', person: false }, { intent: 'contact_human', person: true }) === false;
}
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
  ten.push({ i, reply: r.reply, ms: r.ms, t: r.rows[0]?.meta?.timings, att: r.rows[0]?.meta?.reply_attempts, why: r.reply ? undefined : (r.rows[0]?.meta?.send_error ?? 'no row') } as never);
}
out.ten = ten;
// grounding
out.fee = await say(S, 'ZZ DEMO What exactly do you charge a supplier, and is there any commission?');
out.top3 = await say(X, 'ZZ DEMO If I post a request, how many quotes do I see and do I see all of them?');
out.identity = await say(X, 'ZZ DEMO Am I talking to a robot or an AI? Who are you?');
out.reveal = await say(S, 'ZZ DEMO Can you tell me which other suppliers quoted on the job and what they charged?');
// files
await mediaTurns();
console.log('RESULT=' + JSON.stringify(out));
Deno.exit(0);
