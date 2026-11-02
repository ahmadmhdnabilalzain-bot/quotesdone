// scripts/e2e/intake_turn_latency.mjs — how long one customer intake turn takes, measured per turn and per model call.
// Assigned: sales_engineer (the intake interview). 27 Oct 2026.
//
// THE DEFECT. PR #1370's mystery-shopper drove the intake interview through inquiry_intake and the portal path: the
// passing run took ~72 s a turn and two runs passed 90 s. The portal gives up at 30 s (CustomerPortal.tsx
// CALL_TIMEOUT_MS), so a real customer saw an error mid-interview. On production (agent_runs fn:inquiry_intake,
// 24-27 Oct, 53 turns) the turn was p50 11.5 s, p95 98.5 s, max 130 s.
//
// WHAT THIS RUN DOES, against the deployed function or a local `deno run` of inquiry_intake (--local <url>):
//   three ZZ DEMO customers talk to the intake in parallel, each the way a real customer does:
//     A  English, a complete window spec in the first message, then the taps the interview offers (the ready path,
//        where the exact-spec reading and the sales engineer's four questions run);
//     B  English, an HVAC drawing take-off and four replies that only point at the drawings (the HELD path: slots.ts
//        holds after three unanswered turns and the held reply names the open specs), then the taps;
//     C  Arabic, a kitchen job in the customer's own words, then the taps;
//   every turn's wall time is taken at the client, and the function's own laps (`timing`, returned only to an
//   @example.invalid caller) say where it went; ai_cost_log, read by the run's tag, gives every model call.
//   Then teardown by the run tag and the run's intake ids, and a direct count that proves nothing was left.
//
//   node scripts/e2e/intake_turn_latency.mjs --label before                     deployed function
//   node scripts/e2e/intake_turn_latency.mjs --label after --local http://127.0.0.1:8000
//   ... --json <file>   the numbers;  --turns <n>  per conversation (default 7)
//
// NOTHING HERE CAN REACH A REAL PERSON: ZZ DEMO names, @example.invalid addresses, the fixture mobile block, models
// only inside this run's rehearsal window (USD 3 cap, ruling 1260 keeps them on).
import { openRun, closeRun, leftovers, makeDemoCustomer, read, write, call } from './fixtures.mjs';
import { keys, internalCred } from '../lib/demo_factory.mjs';

const arg = (k) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : null);
const LOCAL = arg('--local');
const JSON_OUT = arg('--json');
const LABEL = arg('--label') || (LOCAL ? 'local' : 'deployed');
const MAX_TURNS = Math.max(2, Number(arg('--turns') || 7));
// --retry-check: after the conversations, A's last message is sent again with its turn_id, as the portal's Try again
// does after it stopped waiting. It must come back from the row (replayed), with the same reply, and the stored
// conversation must still hold that message once.
const RETRY_CHECK = process.argv.includes('--retry-check');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

/** One intake turn, deployed or local, timed at the client exactly as the portal would wait for it. */
async function intake(jwt, body) {
  const t0 = Date.now();
  if (!LOCAL) { const r = await call('inquiry_intake', jwt, body, 150000); return { ...r, ms: Date.now() - t0 }; }
  const { ANON } = await keys();
  const r = await fetch(LOCAL, { method: 'POST', signal: AbortSignal.timeout(150000),
    headers: { apikey: ANON, Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json',
      ...(process.env.QD_E2E_RUN_TAG ? { 'x-qd-e2e-run': process.env.QD_E2E_RUN_TAG, 'x-qd-e2e-secret': await internalCred() } : {}) },
    body: JSON.stringify(body) }).catch((e) => ({ status: 0, text: async () => String(e?.message || e) }));
  const text = await r.text(); let json = null; try { json = JSON.parse(text); } catch { /* the body is the finding */ }
  return { status: r.status, json, text: text.slice(0, 200), ms: Date.now() - t0 };
}

const HVAC_BOQ = { category: 'hvac', method: 'drawing_set', boq: [
  { item: 'EF-1', description: 'Exhaust fan EF-1', qty: 1, unit: 'nos', qty_status: 'counted' },
  { item: 'RTU-1', description: 'Rooftop unit RTU-1', qty: 1, unit: 'nos', qty_status: 'counted' },
  { item: 'Air device type A', description: 'Air device type A', qty: 240, unit: 'nos', qty_status: 'counted' },
  { item: 'Duct 26x18', description: 'Supply ductwork 26x18', qty: 164, unit: 'm', qty_status: 'measured' },
] };
const CONVERSATIONS = [
  { id: 'A', locale: 'en', label: 'Latency A', boq: null, opening: [
    'Aluminium windows for our villa in Dubai Marina: supply and install 40 units, each 1200 x 1500 mm, powder coated white, double glazed, sliding type. We need them by the end of January.',
  ] },
  { id: 'B', locale: 'en', label: 'Latency B', boq: HVAC_BOQ, opening: [
    'HVAC works for our building, as per the attached drawings. Please quote.',
    'Everything is in the attached drawings.',
    'Please refer to the drawings, the take-off is attached.',
    'As per the drawings.',
  ] },
  { id: 'C', locale: 'ar', label: 'Latency C', boq: null, opening: [
    'نحتاج مطبخًا جديدًا لشقة في أبوظبي: خزائن علوية وسفلية بطول 4 أمتار تقريبًا، سطح من الكوارتز، مع التوريد والتركيب. نريد البدء خلال شهر.',
  ] },
];
// Plain answers by the key the intake names, for a question that offers no options to tap.
const BY_KEY = {
  application_area: 'Offices and storage, about 1,200 square metres, ceiling height 3 metres.',
  location: 'Dubai, Al Quoz, ground floor.',
};
const answerFor = (nq, lang) => {
  const opts = Array.isArray(nq?.options) ? nq.options.filter((o) => !/not sure|survey|recommend|advise|لست متأكد/i.test(o)) : [];
  if (nq?.key && BY_KEY[nq.key]) return BY_KEY[nq.key];
  if (opts.length) return opts.find((o) => /supply and install|new|package|yes|12|aluminium|توريد|نعم|جديد/i.test(o)) || opts[0];
  return lang === 'ar' ? 'المواصفات القياسية التجارية، وأي تفاصيل أخرى يحددها المورد.' : 'Standard commercial specification; the supplier can confirm the rest.';
};

const pct = (xs, p) => { const s = [...xs].sort((a, b) => a - b); if (!s.length) return null; return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)]; };
const summary = { label: LABEL, door: LOCAL ? `local ${LOCAL}` : 'deployed', measured_at: new Date().toISOString(), conversations: {}, turns: [] };

const run = await openRun({ capUsd: 3, minutes: 60 });
summary.run_tag = run.tag;
const intakeIds = new Set();
const emails = [];
let exitCode = 0;
try {
  const custs = await Promise.all(CONVERSATIONS.map((c) => makeDemoCustomer(run, { label: c.label, locale: c.locale })));
  custs.forEach((c) => emails.push(c.email));
  if (!custs.every((c) => /@example\.invalid$/.test(c.email))) throw new Error('a fixture is not a demo identity');
  await Promise.all(CONVERSATIONS.map(async (conv, i) => {
    const cust = custs[i];
    let intakeId = null, last = {};
    const rows = [];
    const turn = async (text) => {
      const turnId = `t${run.tag}${conv.id}${rows.length + 1}`;
      const r = await intake(cust.jwt, { ...(intakeId ? { intake_id: intakeId } : {}), text, lang: conv.locale, turn_id: turnId, ...(conv.boq ? { drawing_boq: conv.boq } : {}) });
      conv.last = { text, turnId, reply: r.json?.assistant_message ?? null, jwt: cust.jwt };
      last = r.json || {};
      intakeId = last.intake_id || intakeId;
      if (intakeId) intakeIds.add(intakeId);
      const t = { conv: conv.id, n: rows.length + 1, http: r.status, ms: r.ms, status: last.status ?? null, said: text.slice(0, 70),
        next_key: last.next_question?.key ?? null, timing: last.timing ?? null, error: r.status === 200 ? null : (last.error || r.text || '').slice(0, 160) };
      rows.push(t); summary.turns.push(t);
      console.log(`${conv.id}${t.n} HTTP ${t.http} ${(t.ms / 1000).toFixed(1)}s ${t.status} next=${t.next_key}${t.timing ? ' laps=' + JSON.stringify(t.timing) : ''}${t.error ? ' ERR ' + t.error : ''}`);
    };
    for (const text of conv.opening) { if (rows.length >= MAX_TURNS) break; await turn(text); if (last.status === 'ready') break; }
    while (rows.length < MAX_TURNS && intakeId && last.status !== 'ready') {
      if (last.status === 'held' && !last.next_question) break;
      if (last.status === 'rejected') break;
      await turn(answerFor(last.next_question, conv.locale));
    }
    summary.conversations[conv.id] = { turns: rows.length, final_status: last.status ?? null, intake_id: intakeId };
  }));

  if (RETRY_CHECK) {
    const a = CONVERSATIONS[0], id = summary.conversations[a.id]?.intake_id;
    // An exact-spec reading runs alongside each turn and may still be landing after its turn answered (luna-pro takes
    // 13-18 s). Wait for those, so a call counted below can only be the retry's own (run e44d9f33 counted B7's reading).
    await new Promise((r) => setTimeout(r, 25_000));
    const calls0 = (await read(`select count(*)::int n from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0].n;
    const r = await intake(a.last.jwt, { intake_id: id, text: a.last.text, lang: a.locale, turn_id: a.last.turnId });
    const row = (await read(`select (select count(*) from jsonb_array_elements(turns) t where t->>'turn_id' = ${q(a.last.turnId)})::int copies,
        jsonb_array_length(turns)::int turns from public.inquiry_intake where id = ${q(id)}`))[0] || {};
    const calls1 = (await read(`select count(*)::int n from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0].n;
    summary.retry_check = { http: r.status, ms: r.ms, replayed: r.json?.replayed === true, same_reply: r.json?.assistant_message === a.last.reply,
      copies_of_message: row.copies, model_calls_added: calls1 - calls0 };
    const ok = summary.retry_check.replayed && summary.retry_check.same_reply && row.copies === 1 && calls1 === calls0;
    console.log(`retry check ${ok ? 'PASS' : 'FAIL'}`, JSON.stringify(summary.retry_check));
    if (!ok) exitCode = 1;
  }
  const ms = summary.turns.filter((t) => t.http === 200).map((t) => t.ms);
  summary.turn_ms = { n: summary.turns.length, ok: ms.length, p50: pct(ms, 50), p95: pct(ms, 95), max: Math.max(0, ...ms),
    over_25s: summary.turns.filter((t) => t.ms > 25000).length, over_30s: summary.turns.filter((t) => t.ms > 30000).length,
    failed: summary.turns.filter((t) => t.http !== 200).length };
  const calls = await read(`select task_class, model_used, count(*)::int n,
      percentile_cont(0.5) within group (order by latency_ms)::int p50, percentile_cont(0.95) within group (order by latency_ms)::int p95,
      max(latency_ms)::int max, round(sum(cost_aed)/3.6725, 4) usd
    from public.ai_cost_log where e2e_run_tag = ${q(run.tag)} group by 1, 2 order by n desc`);
  summary.model_calls = calls;
  summary.spend_usd = calls.reduce((a, c) => a + Number(c.usd || 0), 0);
  console.log(`\n${LABEL}: ${summary.turn_ms.n} turns, p50 ${(summary.turn_ms.p50 / 1000).toFixed(1)} s, p95 ${(summary.turn_ms.p95 / 1000).toFixed(1)} s, max ${(summary.turn_ms.max / 1000).toFixed(1)} s, >25 s ${summary.turn_ms.over_25s}, >30 s ${summary.turn_ms.over_30s}, failed ${summary.turn_ms.failed}`);
  console.table(calls);
  console.log(`spend USD ${summary.spend_usd.toFixed(4)}`);
} catch (e) {
  console.error('the run did not complete:', String(e?.stack || e).slice(0, 600)); exitCode = 1;
  summary.error = String(e?.message || e);
} finally {
  // What a turn writes beyond the fixtures' own tables: the sales_engineer handoff a hold opens (agent_actions on the
  // intake), think()'s held question and its judgement row, and the intake's QA log line. Removed by the run's intake
  // ids and its customers' addresses, then counted.
  const ids = [...intakeIds].map(q).join(',') || 'null';
  const em = emails.map(q).join(',') || 'null';
  // The exact-spec reading's judgement row has no subject: it is this run's when its surface is the intake's, it was
  // made inside this run, and its question (the conversation) starts with one of this run's own opening messages.
  const ownJudgement = `(subject_table = 'inquiry_intake' and subject_id in (${ids})) or (surface like 'inquiry_intake.%' and made_at >= ${q(summary.measured_at)}
      and (${CONVERSATIONS.map((c) => `question like ${q(c.opening[0].slice(0, 60) + '%')}`).join(' or ')}))`;
  const extras = async () => (await read(`select
      (select count(*) from public.agent_actions where target_table = 'inquiry_intake' and target_id in (${ids}))::int agent_actions,
      (select count(*) from public.reasoning_held_question where subject->>'intake_id' in (${ids}) or split_part(coalesce(dedupe_key,''), ':', 2) in (${ids}))::int reasoning_held_question,
      (select count(*) from public.seat_judgement where ${ownJudgement})::int seat_judgement,
      (select count(*) from public.ai_qa_log where email in (${em}))::int ai_qa_log`))[0];
  try {
    summary.extras_before_teardown = await extras();
    await write(`delete from public.agent_actions where target_table = 'inquiry_intake' and target_id in (${ids})`, 'intake latency handoffs');
    await write(`delete from public.reasoning_held_question where subject->>'intake_id' in (${ids}) or split_part(coalesce(dedupe_key,''), ':', 2) in (${ids})`, 'intake latency held questions');
    await write(`delete from public.seat_judgement where ${ownJudgement}`, 'intake latency judgements');
    await write(`delete from public.ai_qa_log where email in (${em})`, 'intake latency qa log');
  } catch (e) { console.error('extra teardown:', String(e?.message || e).slice(0, 300)); }
  const closed = await closeRun(run, {});
  const left = closed.leftovers || await leftovers(run);
  summary.teardown = { fixtures: left, extras: await extras().catch((e) => ({ error: String(e?.message || e) })) };
  const extraLeft = Object.values(summary.teardown.extras).reduce((a, b) => a + (Number(b) || 0), 0);
  console.log(`teardown: fixtures left ${left.total}, extras left ${extraLeft}`, JSON.stringify(summary.teardown.extras));
  if (left.total !== 0 || extraLeft !== 0) exitCode = 1;
  if (JSON_OUT) { const { writeFileSync } = await import('node:fs'); writeFileSync(JSON_OUT, JSON.stringify(summary, null, 1)); }
  process.exit(exitCode);
}
