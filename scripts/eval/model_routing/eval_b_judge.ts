// EVAL B's JUDGE (it_engineer, 10 Nov 2026; design 5c). Reads eval_b.mjs's transcripts and grades each inquiry with a model of
// ANOTHER FAMILY than the interview's (knowledge_validation with counterpart_model = the interview's model, through the live
// gateway's review router), inside its own capped window; the cap is enforced here before every call too.
// Grades per inquiry: expert probes met (judge), register held on the judged turns (%), and a 0-10 expert score.
// PASS adds to eval_b.mjs's code grades: >= 7 of 8 probes met by the judge, register >= 90%, mean >= the Sonnet control - 0.5
// (--control <eval_b control json>).
//   deno run -A --node-modules-dir=none scripts/eval/model_routing/eval_b_judge.ts --in <eval_b.json> [--control <file>] --cap 0.40
import { arg, CapReached, closeWindow, connect, guardSpend, newTag, openWindow, writeJson, type Ctx } from './harness.ts';
import { JUDGE_FN } from './harness.ts';

const IN = arg('--in'); const CONTROL = arg('--control'); const CAP = Number(arg('--cap') ?? '0.40');
if (!IN) throw new Error('--in <eval_b.json> is required');
type Turn = { n: number; said: string; reply: string; asked: string };
type Result = { id: string; lang: string; turns: Turn[]; probes: { at: number; said: string }[]; models: string[] };
const data = JSON.parse(await Deno.readTextFile(IN)) as { results: Result[] };
const { admin, secret } = await connect();
const { defaultDeps } = await import('../../../supabase/functions/_shared/think.ts');
const { E2E_RUN } = await import('../../../supabase/functions/_shared/e2e_run.ts');
const tag = newTag('evalbj');
const c: Ctx = { admin, tag, secret, capUsd: CAP };
await openWindow(admin, tag, CAP, 45, 'eval B judge, model routing (ruling 1572)');
const SYS = `You judge a procurement sales interview by the standard of an expert UAE fit-out and MEP sales engineer (ruling 1572: reason like an
expert, e.g. MDF partition in a wet area -> moisture warning and a PVC panel or wrap alternative, then budget and dimensions; Arabic and English
including Gulf, Egyptian and Levantine dialects and Arabizi; nothing said early may be forgotten later). Return ONE JSON object:
{"score": <0-10>, "probes": [{"at": <turn>, "met": <bool>, "why": "<short>"}], "register_held_pct": <0-100>, "forgotten": ["<fact asked again or contradicted>"], "why": "<two sentences>"}`;
const graded: Record<string, unknown>[] = []; let stopped = '';
try {
  for (const r of data.results) {
    await guardSpend(c, 0.08, 'judge ' + r.id);
    const author = r.models.find((m) => m.includes('/')) ?? 'anthropic/claude-sonnet-5.5';
    const transcript = r.turns.map((t) => `#${t.n} CUSTOMER: ${t.said}\n#${t.n} AGENT: ${t.reply}${t.asked ? ' [asks: ' + t.asked + ']' : ''}`).join('\n').slice(0, 60_000);
    const res = await E2E_RUN.run({ tag, secret }, () => defaultDeps(admin, JUDGE_FN).llm('verify', SYS,
      JSON.stringify({ inquiry: r.id, language: r.lang, probes: r.probes, transcript }), { taskClass: 'knowledge_validation', seat: 'it_engineer', counterpartModel: author, max: 2000, subject: { fixture: true } }));
    let v: Record<string, unknown> = {};
    try { const t = String(res.content ?? ''); v = JSON.parse(t.slice(t.indexOf('{'), t.lastIndexOf('}') + 1)); } catch { v = { unread: String(res.content ?? res.error).slice(0, 200) }; }
    graded.push({ id: r.id, author, judge: res.model ?? null, ...v });
    console.log(r.id, res.model, JSON.stringify(v).slice(0, 200));
  }
} catch (e) { stopped = e instanceof CapReached ? e.message : 'error: ' + String((e as Error)?.message ?? e); }
finally { await closeWindow(admin, tag).catch(() => {}); }
const probes = graded.flatMap((g) => (g.probes as { met: boolean }[] | undefined) ?? []);
const mean = (xs: number[]) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN;
const scores = graded.map((g) => Number(g.score)).filter((x) => !Number.isNaN(x));
const control = CONTROL ? JSON.parse(await Deno.readTextFile(CONTROL)).graded as { score: number }[] : null;
const m = { judged: graded.length, probes_met: probes.filter((p) => p.met).length, probes: probes.length,
  register_min_pct: Math.min(...graded.map((g) => Number(g.register_held_pct ?? 0))), mean: mean(scores),
  control_mean: control ? mean(control.map((x) => Number(x.score))) : null, run_tag: 'qd_run:' + tag, stopped: stopped || null };
const pass = !stopped && m.judged === data.results.length && m.probes_met >= 7 && m.register_min_pct >= 90 && (m.control_mean == null || m.mean >= m.control_mean - 0.5);
await writeJson(IN.replace(/\.json$/, '') + '_judged.json', { pass, metrics: m, graded });
console.log(JSON.stringify({ pass, ...m }, null, 1));
Deno.exit(pass ? 0 : 1);
