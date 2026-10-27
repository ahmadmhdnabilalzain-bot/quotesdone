// customer_support's duty updates (the complaint update, the incident holding and resolved notices) are written by the
// model; the code-written draft goes out ONLY on a true OpenRouter outage (founder_instruction 1339, 27 Oct 2026).
// The writer here is the real aiReply over a stubbed gateway: no network, no paid call, nothing reaches a person.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { type OwedRow, voiceWriter, type VoiceIO, VOICE_RULES, writeOwedDutyMessages } from './duty_voice.ts';
import type { LlmReply, ThinkDeps } from './think.ts';

function gateway(reply: (n: number) => LlmReply) {
  const seen: { system: string; input: string }[] = [];
  const deps = {
    gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
    llm: (_p: string, system: string, input: string) => { seen.push({ system, input }); return Promise.resolve(reply(seen.length)); },
  } as unknown as ThinkDeps;
  return { deps, seen };
}
const say = (answer: string): LlmReply => ({ content: JSON.stringify({ answer }), model: 'stub' } as LlmReply);
const fail = (error: string): LlmReply => ({ content: null, error } as LlmReply);

const COMPLAINT_DRAFT = 'Dear Sara,\n\nYour complaint, reference QD-C-ZZ0001, is now in review. You will have our final response by 2026-11-05. If you have anything to add, reply to this email and quote the reference.\n\nThe QuotesDone team';
const complaint: OwedRow = {
  stage: 'complaint.update', subject_key: 'QD-C-ZZ0001', voice_key: 'complaint.update:QD-C-ZZ0001', to_role: 'customer',
  to_email: 'zz.sara@example.invalid', lang: 'en', subject: 'Your complaint QD-C-ZZ0001: in review', draft: COMPLAINT_DRAFT,
  situation: 'Write the customer an update on their complaint: it is now in review and the final response is due by the date in the facts.',
  facts: 'COMPLAINT REFERENCE: QD-C-ZZ0001\nCUSTOMER NAME: Sara\nSTATUS: in review\nFINAL RESPONSE DUE BY: 2026-11-05', must: ['QD-C-ZZ0001', '2026-11-05'],
};
const HOLD_DRAFT = 'We want to let you know about a temporary problem affecting quotation uploads. Our technical team is working on it now, and your requests and data are safe. We will write again as soon as it is fixed; there is nothing you need to do.\n\nWe are sorry for the inconvenience.\nThe QuotesDone team';
const holding = (n: number): OwedRow => ({
  stage: 'incident.holding', subject_key: '7:zz.p' + n + '@example.invalid', voice_key: 'incident.holding:7:en:customer', to_role: 'customer',
  to_email: 'zz.p' + n + '@example.invalid', lang: 'en', subject: 'QuotesDone: we are fixing a temporary problem', draft: HOLD_DRAFT,
  situation: 'Write a short e-mail about a temporary problem affecting what the facts name.', facts: 'WHAT IS AFFECTED: quotation uploads', must: [],
});

function store(rows: OwedRow[], write: VoiceIO['write']) {
  const sent: [string, string, string, string][] = []; const failed: [string, string][] = [];
  const io: VoiceIO = {
    due: () => Promise.resolve(rows),
    write,
    send: (stage, key, body, by) => { sent.push([stage, key, by, body]); return Promise.resolve({ ok: true }); },
    failed: (_s, key, e) => { failed.push([key, e]); return Promise.resolve(); },
  };
  return { io, sent, failed };
}

Deno.test('1339: the model writes the complaint update when it is up; the draft never goes', async () => {
  const words = 'Dear Sara,\n\nThank you for your patience. Your complaint QD-C-ZZ0001 is now in review, and you will have our final response by 2026-11-05. You can reply to this email with anything you would like to add.\n\nThe QuotesDone team';
  const g = gateway(() => say(words));
  const s = store([complaint], voiceWriter(g.deps));
  const out = await writeOwedDutyMessages(s.io);
  assertEquals([out.written, out.by_model, out.by_outage], [1, 1, 0]);
  assertEquals(s.sent, [['complaint.update', 'QD-C-ZZ0001', 'model', words]]);
  assertMatch(g.seen[0].system, /an e-mail we send them/, 'the model is told the format (VOICE_RULES)');
  assert(g.seen[0].input.includes('FINAL RESPONSE DUE BY: 2026-11-05'), 'the facts reach the model');
  assert(VOICE_RULES.includes('never mention a cause, a system, a provider'));
});

Deno.test('1339: the reference and the due date must be carried: a draft without them is rewritten by the model', async () => {
  const g = gateway((n) => n === 1 ? say('Dear Sara, your complaint is in review and we will answer soon. The QuotesDone team')
    : say('Dear Sara, your complaint QD-C-ZZ0001 is in review; our final response will reach you by 2026-11-05. The QuotesDone team'));
  const s = store([complaint], voiceWriter(g.deps));
  await writeOwedDutyMessages(s.io);
  assertEquals(s.sent[0][2], 'model');
  assert(s.sent[0][3].includes('QD-C-ZZ0001') && s.sent[0][3].includes('2026-11-05'));
  assertMatch(g.seen[1].input, /must appear exactly/);
});

Deno.test('1339: only a TRUE outage (5xx, network, timeout, open circuit) sends the code-written draft', async () => {
  for (const err of ['gateway_http_503', 'gateway_http_502 upstream', 'client_error: error sending request', 'client_timeout_30000ms', 'circuit_open']) {
    const s = store([complaint], voiceWriter(gateway(() => fail(err)).deps));
    const out = await writeOwedDutyMessages(s.io);
    assertEquals([out.by_outage, s.sent], [1, [['complaint.update', 'QD-C-ZZ0001', 'outage_fallback', COMPLAINT_DRAFT]]], err);
  }
});

Deno.test('1339: a 4xx is never an outage: nothing is sent, the attempt is counted and asked again', async () => {
  for (const err of ['gateway_http_400 upstream timeout', 'gateway_http_401', 'gateway_http_429 rate_limited', 'gateway_http_404 connection']) {
    const s = store([complaint], voiceWriter(gateway(() => fail(err)).deps));
    const out = await writeOwedDutyMessages(s.io);
    assertEquals([out.written, out.unwritten, s.sent.length, s.failed.length], [0, 1, 0, 1], err);
    assertMatch(s.failed[0][1], /model is up/);
  }
  // a model that answered and was refused every time is not an outage either
  const s = store([complaint], voiceWriter(gateway(() => say('We will refund you AED 9,999 for this.')).deps));
  await writeOwedDutyMessages(s.io);
  assertEquals([s.sent.length, s.failed.length], [0, 1]);
  // a writer that throws is not an outage
  const t = store([complaint], () => Promise.reject(new Error('companyBrief rpc failed')));
  await writeOwedDutyMessages(t.io);
  assertEquals([t.sent.length, t.failed.length], [0, 1]);
});

Deno.test('1339: customer-safe: an internal sentence the model writes is dropped before it is sent (ledger 1338)', async () => {
  const g = gateway(() => say('Dear customer, quotation uploads are having a temporary problem and our technical team is working on it now; your requests and data are safe. The openrouter provider queue is down. The QuotesDone team'));
  const s = store([holding(1)], voiceWriter(g.deps));
  await writeOwedDutyMessages(s.io);
  assertEquals(s.sent.length, 1);
  assertEquals(/openrouter|provider queue/i.test(s.sent[0][3]), false, s.sent[0][3]);
});

Deno.test('an incident notice is ONE model call for everyone of a side and language; groups are bounded per run', async () => {
  const g = gateway(() => say('Dear customer, quotation uploads have a temporary problem. Our technical team is working on it now, and your requests and data are safe. We will write again once it is fixed. The QuotesDone team'));
  const rows = [holding(1), holding(2), holding(3)];
  const s = store(rows, voiceWriter(g.deps));
  const out = await writeOwedDutyMessages(s.io);
  assertEquals([g.seen.length, out.written, new Set(s.sent.map((x) => x[3])).size], [1, 3, 1]);
  // at most `groups` voice keys in a run
  const many = [complaint, holding(1), { ...complaint, subject_key: 'QD-C-ZZ0002', voice_key: 'complaint.update:QD-C-ZZ0002' }];
  const w: string[] = [];
  const s2 = store(many, (r) => { w.push(r.voice_key); return Promise.resolve({ reply: 'Dear Sara, your complaint QD-C-ZZ0001 is in review until 2026-11-05.', outage: false, attempts: [] }); });
  await writeOwedDutyMessages(s2.io, 2);
  assertEquals(w, ['complaint.update:QD-C-ZZ0001', 'incident.holding:7:en:customer']);
});
