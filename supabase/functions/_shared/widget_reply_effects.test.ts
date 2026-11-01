// widgetReplyEffects() with stubbed RPCs, and site_assistant's composed-reply exit going through it (review of #1043).
import { assert, assertEquals } from 'jsr:@std/assert';
import { logParty, widgetReplyEffects, type WidgetReplyEffectsInput } from './widget_reply_effects.ts';

function stub() {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = (fn: string, args: Record<string, unknown>) => {
    calls.push({ fn, args });
    if (fn === 'fn_support_knowledge_gap') return Promise.resolve({ data: { ok: true, task_id: 42, reply_en: 'recorded', reply_ar: 'سُجّل' }, error: null });
    return Promise.resolve({ data: { ok: true }, error: null });
  };
  return { rpc, calls };
}
const base: WidgetReplyEffectsInput = {
  message: 'can I speak to someone about your insurance policy for crane hire?', live: false, grounded: false, answered: true,
  refusal: 'reasoned_without_company_knowledge', rateLimited: false, ip: '203.0.113.9', path: '/', askedForAPerson: () => Promise.resolve(true),
};

Deno.test('a composed reply with no company knowledge behind it files the gap, and a person ask reaches the CEO', async () => {
  const s = stub();
  const e = await widgetReplyEffects(s.rpc, base);
  assertEquals(await e.person, true);
  assertEquals(e.gapTaskId, 42);
  const gap = s.calls.find((c) => c.fn === 'fn_support_knowledge_gap');
  assert(gap, 'the knowledge gap was not recorded');
  assertEquals(gap.args.p_refusal, 'reasoned_without_company_knowledge');
  const ceo = s.calls.find((c) => c.fn === 'fn_support_report_to_ceo');
  assert(ceo, 'the visitor asked for a person and the CEO was not told');
  assertEquals(ceo.args.p_source_agent, 'customer_support');
});

Deno.test('a grounded reply files no gap; no person asked, no report; a signed-in person files no gap', async () => {
  for (const o of [{ grounded: true }, { live: true }]) {
    const s = stub();
    const e = await widgetReplyEffects(s.rpc, { ...base, ...o, askedForAPerson: () => Promise.resolve(false) });
    assertEquals(await e.person, false);
    assertEquals(e.gapTaskId, null);
    assertEquals(s.calls.length, 0, JSON.stringify(s.calls));
  }
});

// Review of #1729 (1 Nov 2026): a turn the gateway rate-limited was never read by a model. It is not a gap in company
// knowledge, and fn_support_knowledge_gap opens an org_tasks row per distinct question, so a scripted caller past the
// limit could open one per message. It files nothing, and spends no person-decision model call either.
Deno.test('a turn the gateway rate-limited files no knowledge gap and no person report, even ungrounded and asking for a person', async () => {
  const s = stub();
  let asked = 0;
  const e = await widgetReplyEffects(s.rpc, { ...base, grounded: false, answered: false, refusal: 'rate_limited', rateLimited: true,
    askedForAPerson: () => { asked++; return Promise.resolve(true); } });
  assertEquals(await e.person, false);
  assertEquals(e.gapTaskId, null);
  assertEquals(e.gapReply, null);
  assertEquals(s.calls.length, 0, JSON.stringify(s.calls));
  assertEquals(asked, 0, 'the person decision (a model call) ran for a rate-limited turn');
});

Deno.test('the person decision failing never fails the reply', async () => {
  const s = stub();
  const e = await widgetReplyEffects(s.rpc, { ...base, grounded: true, askedForAPerson: () => Promise.reject(new Error('gateway down')) });
  assertEquals(await e.person, false);
});

// THE WIRING. Every exit of site_assistant that answers a visitor's question (today only the model's brief reply; the
// capability, FAQ, missing-credential and canned exits were removed on 12 Oct) must file the two side
// effects above (fileEffects -> widgetReplyEffects) and write its assistant_logs row before it returns. Two replies
// answer nothing and are exempt from the side effects: the rate limit's, which answers before the question is read at
// all, and the visitor cap's (ruling 18 Oct 2026), which is told not to answer or discuss the message (capRules).
Deno.test('site_assistant: every exit that answers a question files the side effects and its log before returning', async () => {
  const src = await Deno.readTextFile(new URL('../site_assistant/index.ts', import.meta.url));
  assert(/const fileEffects = async [^\n]*\n\s+const fx = await widgetReplyEffects\(rpc, /.test(src), 'fileEffects no longer calls widgetReplyEffects');
  const exits = [...src.matchAll(/return J\(\{ reply\b/g)].map((m) => m.index!);
  const exitLine = (i: number) => src.slice(i, src.indexOf('\n', i));
  // 28 Oct 2026: this count read the visitor cap's exit as a second answering one and failed 2 vs 1 on main from #1658's
  // merge (27 Oct). Nothing was filed twice: a capped turn returns before the brief reply runs, and each road writes
  // one assistant_logs row. The cap's exit is named here and held to its own contract below.
  const capped = exits.filter((i) => /routed: 'visitor_cap'/.test(exitLine(i)));
  const answering = exits.filter((i) => !/RL_REPLY/.test(exitLine(i)) && !capped.includes(i));
  // 12 Oct 2026 (rulings 1195/1196): the capability, FAQ, missing-credential and canned exits were removed; the model's
  // reply is the one exit that answers (a request no model could answer returns an error, with no text).
  assertEquals(answering.length, 1, 'the model-written reply');
  // THE VISITOR CAP: one exit, behind pastVisitorCap, with its turn logged, and no knowledge gap or person report. A
  // capped question went unanswered by design, not for want of company knowledge, so filing it as a gap would open a
  // customer_support task (fn_support_knowledge_gap: "Answer an unanswered support question") for every distinct
  // message sent past the cap.
  assertEquals(capped.length, 1, 'the visitor cap exit');
  const gate = src.lastIndexOf('pastVisitorCap(', capped[0]);
  assert(gate > 0, 'the visitor cap exit is not behind pastVisitorCap');
  const capSeg = src.slice(gate, capped[0]);
  assert(/logWithAttempts\(admin, 'assistant_logs', /.test(capSeg), 'the visitor cap exit returns without writing its log: ' + exitLine(capped[0]));
  assert(!/fileEffects\(|widgetReplyEffects\(/.test(capSeg), 'the visitor cap exit files a gap or a person report for a message it does not answer');
  const defined = src.indexOf('const fileEffects = async');
  let prev = defined;
  for (const i of answering) {
    assert(i > defined, 'an answering exit returns before fileEffects exists: ' + src.slice(i, i + 80));
    const seg = src.slice(prev, i);
    const line = src.slice(i, src.indexOf('\n', i));
    assert(/await fileEffects\(\{ grounded: /.test(seg), 'this exit returns without filing the gap or the person report: ' + line);
    assert(/from\('assistant_logs'\)\.insert\(|logWithAttempts\(admin, 'assistant_logs', /.test(seg), 'this exit returns without writing its log: ' + line);
    prev = i;
  }
});

// THE GATEWAY'S RATE LIMIT ON THE BRIEF ROAD (review of #1729). Its exit comes after fileEffects, so fileEffects must be
// told the turn was rate-limited (widgetReplyEffects then files nothing), and the turn's log row is still written first.
Deno.test('site_assistant: the gateway rate-limit exit tells fileEffects, writes its log, and can never file a gap', async () => {
  const src = await Deno.readTextFile(new URL('../site_assistant/index.ts', import.meta.url));
  assert(/const fileEffects = async \(o: \{[^}]*rateLimited: boolean \}\) => \{\n\s+const fx = await widgetReplyEffects\(rpc, \{[^}]*\.\.\.o \}\)/.test(src),
    'fileEffects does not take rateLimited or does not pass it through to widgetReplyEffects');
  const start = src.indexOf('const reply = a.reply.trim()');
  assert(start > 0, 'the brief reply is gone');
  const road = src.slice(start);
  const decl = road.match(/const rateLimited = !reply && a\.error === 'rate_limited';/);
  assert(decl, "rateLimited is not decided from the gateway's error");
  const call = road.match(/await fileEffects\(\{ grounded: [^\n]*\}\)/);
  assert(call, 'the brief reply no longer files its effects');
  // the decided value itself, by shorthand: 'rateLimited: false' or a second expression would pass the word and not the fact
  assert(/, rateLimited \}\)$/.test(call[0]), 'the brief road files its effects without passing the decided rateLimited: ' + call[0]);
  assert(decl.index! < call.index!, 'rateLimited is decided after the effects are filed');
  const exit = road.indexOf('return J({ reply: RL_REPLY');
  assert(exit > call.index!, 'the rate-limit exit is not on the brief road after the effects');
  assert(/^\s*if \(rateLimited\) $/.test(road.slice(road.lastIndexOf('\n', exit) + 1, exit)), 'the rate-limit exit is not gated by the same rateLimited the effects were told');
  assert(/logWithAttempts\(admin, 'assistant_logs', /.test(road.slice(call.index!, exit)), 'the rate-limited turn returns without writing its log');
});

// Review of #1043: a signed-in widget reply is logged as its party so it attaches to the support case (#1036).
Deno.test('logParty: a signed-in person is customer:<uuid> or supplier:<id> on every exit; a stranger is not a party', () => {
  const uuid = '3f2b8c1e-6a4d-4e2f-9b7a-1c2d3e4f5a6b';
  assertEquals(logParty({ audience: 'customer', id: uuid }, 'customer', 'session', true), 'customer:' + uuid);
  assertEquals(logParty({ audience: 'customer', id: uuid }, 'customer', 'session'), 'customer:' + uuid);
  assertEquals(logParty({ audience: 'supplier', id: '4812' }, 'supplier', 'path', true), 'supplier:4812');
  assertEquals(logParty(null, 'supplier', 'path', true), 'supplier:path:reasoned');
  assertEquals(logParty(null, 'unknown', 'none'), 'unknown');
});

Deno.test('site_assistant: every assistant_logs write names its audience through logParty(who, ...)', async () => {
  const src = await Deno.readTextFile(new URL('../site_assistant/index.ts', import.meta.url));
  const writes = src.match(/(?:from\('assistant_logs'\)\.insert\(|logWithAttempts\(admin, 'assistant_logs', )\{[^\n]*/g) ?? [];
  assert(writes.length >= 1, `expected the widget's reply log, found ${writes.length}`);
  for (const w of writes) assert(/audience: logParty\(who, /.test(w), 'an assistant_logs write does not log the party: ' + w.slice(0, 160));
  const start = src.indexOf('const reply = a.reply.trim()');
  assert(/audience: logParty\(who, audience, source, true\)/.test(src.slice(start, src.indexOf('return J(', start))), 'the composed reply is not logged as its party');
});
