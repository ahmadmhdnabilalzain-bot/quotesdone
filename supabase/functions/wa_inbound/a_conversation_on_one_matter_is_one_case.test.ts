// Ruling 1635 on WhatsApp, measured against the final audit's oracle (12 Nov 2026, W3). On production on 11 Nov the case read
// raced a same-matter decision that took p50 8.7 s against 4 s: 0 summaries from 29 replies, 0 promises, 17 cases for 7 people
// (one supplier 8 in 12 minutes). The oracle: a 12-message conversation on one matter is ONE case with a summary version per
// exchange; an unrelated question opens a second case; the next message about the first matter goes back to it.
// The database is an in-memory support_case that does what fn_support_touch (on arrival), fn_support_open_cases,
// fn_support_case_route and fn_support_case_summary_write do; the model is a stub that decides by the words of the matter.
// The reply's read never waits on a model: a decision that takes 10 s does not delay it (last test).
import { assert, assertEquals } from 'jsr:@std/assert@1';
(Deno.env as unknown as { get: (k: string) => string | undefined }).get = (k) => ({ SUPABASE_URL: 'https://db.invalid', SUPABASE_SERVICE_ROLE_KEY: 'stub-service-role' } as Record<string, string>)[k];
const { recordWaExchange, startWaCase, waCaseMemory } = await import('./case_memory.ts');
import type { LlmReply, ThinkDeps, Turn } from '../_shared/think.ts';
import type { WaTurn } from './turn.ts';

type Case = { case_ref: string; title: string | null; summary_text: string | null; summary_version: number; last_activity_at: string; state: string; inbound: number };
function store(o: { decisionMs?: number } = {}) {
  const cases: Case[] = [];
  const versions: { ref: string; version: number; promised: unknown[] }[] = [];
  let n = 0, clock = Date.now() - 600_000;
  const tick = () => new Date(clock += 1_000).toISOString();
  const open = () => cases.filter((c) => c.state !== 'closed').sort((a, b) => b.last_activity_at.localeCompare(a.last_activity_at));
  const opened = () => { const c: Case = { case_ref: 'QD-S-T' + String(++n).padStart(5, '0'), title: null, summary_text: null, summary_version: 0, last_activity_at: tick(), state: 'open', inbound: 0 }; cases.push(c); return c; };
  /** fn_support_touch on the arrival row: the newest open case, or a new one */
  const touch = () => { const c = open()[0] ?? opened(); c.inbound++; c.last_activity_at = tick(); };
  const calls = { decisions: 0, summaries: 0 };
  const d = {
    embed: () => Promise.resolve(null),
    rpc: (fn: string, a: Record<string, unknown>) => {
      if (fn === 'fn_support_open_cases') return Promise.resolve({ data: { profile: 7, cases: open().slice(0, 5).map(({ state: _s, inbound: _i, ...c }) => c) }, error: null });
      if (fn === 'fn_support_case_route') {
        if (a.p_choice === 'new') { const c = opened(); return Promise.resolve({ data: { ok: true, case_ref: c.case_ref, opened: true }, error: null }); }
        const c = open().find((x) => x.case_ref === a.p_case_ref);
        if (!c) return Promise.resolve({ data: { ok: false }, error: null });
        c.last_activity_at = tick();
        return Promise.resolve({ data: { ok: true, case_ref: c.case_ref, opened: false }, error: null });
      }
      if (fn === 'fn_support_case_summary_write') {
        const c = cases.find((x) => x.case_ref === a.p_case_ref)!;
        if (c.summary_version !== a.p_expected_version) return Promise.resolve({ data: { ok: false, reason: 'stale' }, error: null });
        c.summary_version++; c.summary_text = String(a.p_summary_text); c.title = String(a.p_title || c.title || '');
        versions.push({ ref: c.case_ref, version: c.summary_version, promised: ((a.p_summary as { promised?: unknown[] }).promised) ?? [] });
        return Promise.resolve({ data: { ok: true, version: c.summary_version }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
    llm: async (_p: string, system: string, input: string, opts: Record<string, unknown>) => {
      if (opts.taskClass === 'case_summary') {
        calls.summaries++;
        const their = /THEIR MESSAGE:\n([\s\S]*?)\n\nOUR REPLY:/.exec(input)?.[1] ?? '';
        const before = /THE SUMMARY SO FAR:\n([\s\S]*?)\n\n/.exec(input)?.[1] ?? '';
        const matter = /clean/i.test(their) || /clean/i.test(before) ? 'a cousin\'s cleaning company registering as a supplier' : 'quotes for 12 aluminium windows for a villa in Dubai';
        return { content: JSON.stringify({ title: matter, asked: matter, said_or_did: 'we answered', promised: [], open: [] }), model: 'stub' } as LlmReply;
      }
      calls.decisions++;
      if (o.decisionMs) await new Promise((r) => setTimeout(r, o.decisionMs));
      const q = String(JSON.parse(input).question ?? '');
      const options = [...system.matchAll(/continue:(QD-[A-Z0-9-]+) \(the same matter as case [^:]+: ([^;]*)\)/g)].map((m) => ({ ref: m[1], meaning: m[2] }));
      const same = options.find((x) => (/clean/i.test(q) ? /clean/i : /window|door|glaz|aluminium/i).test(x.meaning));
      return { content: JSON.stringify({ answer: 'x', decision: { choice: same ? 'continue:' + same.ref : 'new' } }), model: 'stub' } as LlmReply;
    },
  } as unknown as ThinkDeps;
  return { d, cases, versions, touch, calls, open };
}

const FROM = 'whatsapp:+971500000061';
const conv: Turn[] = [];
async function exchange(s: ReturnType<typeof store>, body: string, i: number) {
  s.touch();   // the arrival row's trigger attaches the message first, as on production
  const t = { From: FROM, Body: body, MessageSid: 'SM' + String(i).padStart(32, '0') } as unknown as WaTurn;
  void startWaCase(t, s.d);
  const mem = await waCaseMemory(t, 'customer', 1_500, s.d);
  const reply = 'Thank you, noted (' + i + ').';
  await recordWaExchange(t, 'customer', 'en', reply, conv, s.d);
  return mem;
}
const WINDOWS = ['Hi', 'I need quotes for aluminium windows for my villa in Dubai', '12 windows, double glazed', 'They are about 1.5 by 1.2 metres each',
  'Sliding, not casement', 'Bronze frames please', 'Delivery before 20 December', 'Do I need to send drawings?', 'OK I will send photos instead',
  'Can I also add one sliding door to the same request?', 'Installation included please', 'Thanks, that is everything for the windows'];

Deno.test('a 12-message conversation on one matter is ONE case, with a summary written after every exchange', async () => {
  const s = store();
  for (const [i, m] of WINDOWS.entries()) await exchange(s, m, i);
  assertEquals(s.cases.length, 1, 'one case for one matter: ' + s.cases.map((c) => c.case_ref).join(', '));
  assertEquals(s.versions.length, 12, 'a summary version per exchange');
  assert(s.cases[0].title?.includes('aluminium windows'));
});

Deno.test('an unrelated question opens a second case; the next message about the windows goes back to the first', async () => {
  const s = store();
  for (const [i, m] of WINDOWS.slice(0, 4).entries()) await exchange(s, m, i);
  await exchange(s, 'Different question: my cousin runs a cleaning company in Sharjah. How can he register as a supplier?', 10);
  assertEquals(s.cases.length, 2, 'the unrelated question is its own case');
  const cleaning = s.cases.find((c) => /clean/.test(String(c.title)))!;
  const windows = s.cases.find((c) => /window/.test(String(c.title)))!;
  assert(cleaning && windows && cleaning.case_ref !== windows.case_ref);
  const before = s.versions.filter((v) => v.ref === windows.case_ref).length;
  const mem = await exchange(s, 'How many quotes will I see for my windows?', 11);
  assertEquals(s.cases.length, 2, 'no third case');
  assertEquals(s.versions.filter((v) => v.ref === windows.case_ref).length, before + 1, 'the windows case got this exchange');
  assert(mem, 'the reply had a case to read');
});

Deno.test('the reply never waits for the same-matter decision: a decision that takes 2 s leaves the read instant, and the case is still recorded', async () => {
  const s = store({ decisionMs: 2_000 });
  await exchange(s, WINDOWS[0], 0);   // the opening: decided by code (nothing recorded yet), summary v1
  await exchange(s, WINDOWS[1], 1);   // the job after the opening: by code too (their only case, one exchange), summary v2
  s.touch();
  const t = { From: FROM, Body: 'Bronze frames please', MessageSid: 'SM' + '9'.repeat(32) } as unknown as WaTurn;
  const t0 = Date.now();
  const mem = await waCaseMemory(t, 'customer', 1_500, s.d);
  assert(Date.now() - t0 < 500, 'the read took ' + (Date.now() - t0) + ' ms');
  assert(mem?.summaryText.includes('aluminium windows'), 'the reply works from the case summary');
  await recordWaExchange(t, 'customer', 'en', 'Noted: bronze frames.', conv, s.d);
  assertEquals([s.cases.length, s.versions.length, s.calls.decisions], [1, 3, 1], 'one case, three versions, one model decision');
});

Deno.test('the founder is not a case; an empty reply records nothing', async () => {
  const s = store();
  const t = { From: FROM, Body: 'hi', MessageSid: 'SMx' } as unknown as WaTurn;
  assertEquals(await waCaseMemory(t, 'founder', 1_500, s.d), null);
  assertEquals(recordWaExchange(t, 'founder', 'en', 'ok', conv, s.d), null);
  assertEquals(recordWaExchange(t, 'customer', 'en', '   ', conv, s.d), null);
});
