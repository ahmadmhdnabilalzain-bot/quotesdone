// THE INTAKE'S REPLY-WRITING STEPS, TIMED PER EFFORT (it_engineer, 12 Nov 2026; founder ledger 1642; review of the effort fix,
// finding 4). The intake chat turn writes its reply after the interview call: the held reply (slots.ts heldReply, conversation_reply)
// or the voice (slots.ts intakeVoice, voice_draft). Production, 9-12 Nov (ai_cost_log fn inquiry_intake): the held reply on
// gpt-6-luna-pro p50 9.7 s, p95 15.8 s answered, and 16 calls cut at 16.7-17.1 s; the voice p50 5.7 s, p95 9.1 s. Neither had
// been timed at another effort. This runs the REAL two routines on the recorded portal conversations of the cases file (the
// same anonymised file as replay.ts), once per arm, through the production gateway under one run tag inside a rehearsal window
// whose cap is the run's cap; guardSpend reads ai_cost_log before every call. Nothing is sent to a person: the routines only
// return text, and the deps' rpc lets through only READ_ONLY (replay.ts) and stubs the rest.
//   deno run --no-lock --node-modules-dir=none -A scripts/eval/effort_low_vs_high/held_reply.ts --cases <cases.json> --paid
//     [--cap 0.12] [--arms low,medium] [--reply-ms 15000] [--out <file outside the repository>]
// --reply-ms: each step's deadline from its start, as the turn gives it (turn_clock.ts REPLY_MIN_MS), so a call is cut where
// production cuts it and no fallback rung is paid past it. The first run (evalhelde28857d4) had none: a high held reply ran to
// the 47 s wall and its Sonnet fallback cost USD 0.096 of the 0.109 spent; the guard now prices a held reply call at that.
import { arg, CapReached, closeWindow, connect, flag, guardSpend, newTag, openWindow, writeJson, type Ctx } from '../model_routing/harness.ts';
import { residualIdentity } from '../effort_low_vs_high.mjs';
import type { PolicyEffort } from '../../../supabase/functions/_shared/effort_policy.ts';
import type { ThinkDeps } from '../../../supabase/functions/_shared/think.ts';
import { pct, READ_ONLY } from './replay.ts';

const PAID = flag('--paid');
const CAP = Number(arg('--cap') ?? '0.12');
if (!(CAP > 0 && CAP <= 0.23)) throw new Error('the cap is at most USD 0.34 (what is left of this fix group\'s budget after evalhelde28857d4)');
const REPLY_MS = Number(arg('--reply-ms') ?? '15000');
const ARMS = (arg('--arms') ?? 'low,medium').split(',').filter((a): a is PolicyEffort => a === 'low' || a === 'medium' || a === 'high');
const FILE = JSON.parse(await Deno.readTextFile(arg('--cases') ?? '')) as { cases: Record<string, { id: string; conversation?: string }[]> };
const cases = (FILE.cases['inquiry_intake.exact_spec'] ?? []).filter((k) => typeof k.conversation === 'string' && k.conversation.trim());
const left = [...new Set(cases.flatMap((k) => residualIdentity(String(k.conversation))))];
if (left.length) throw new Error('the cases carry what looks like a real identity; nothing was run: ' + left.length + ' hit(s)');

const { admin, secret } = await connect();
const { effortFor } = await import('../../../supabase/functions/_shared/effort_policy.ts');
const { defaultDeps } = await import('../../../supabase/functions/_shared/think.ts');
const { E2E_RUN } = await import('../../../supabase/functions/_shared/e2e_run.ts');
const { heldReply, intakeVoice } = await import('../../../supabase/functions/inquiry_intake/slots.ts');
if (PAID && (globalThis as { __qdE2eFetch?: boolean }).__qdE2eFetch !== true) throw new Error('the run-tag forwarder is not installed; nothing was run');
for (const cls of ['conversation_reply', 'voice_draft']) for (const e of ARMS) if (effortFor(cls, e) !== e) throw new Error(`the gateway would not send ${e} on ${cls}`);
const { data: spec } = await admin.from('category_specs').select('category,fields').eq('category', 'carpentry-joinery').maybeSingle();
const checklist = (Array.isArray(spec?.fields) ? spec!.fields : []) as { key: string; question: string; required?: boolean }[];
const exhausted = checklist.filter((f) => f.required).slice(0, 2).map((f) => f.key);
if (exhausted.length < 2) throw new Error('the checklist could not be read');

const tag = newTag('evalheld');
const c: Ctx = { admin, tag, secret, capUsd: CAP };
const rows: { id: string; step: string; arm: string; wall_ms: number; answered: boolean; words: number; usd: number; calls: number }[] = [];
const deps = (arm: PolicyEffort, out: { ms: number[] }, step: string): ThinkDeps => {
  const live = defaultDeps(admin, 'inquiry_intake');
  return { ...live, gate: () => Promise.resolve({ allowed: true } as never), embed: () => Promise.resolve(null),
    rpc: (fn, a) => READ_ONLY.has(fn) ? live.rpc(fn, a) : Promise.resolve({ data: null, error: null }),
    llm: async (phase, s, i, o) => {
      if (!PAID) return { content: null, model: null, error: 'dry_run' };
      await guardSpend(c, step === 'held_reply' ? 0.1 : 0.01, step + ' (' + arm + ')');
      const t0 = Date.now(); const r = await live.llm(phase, s, i, { ...o, effort: arm, rateKey: undefined }); out.ms.push(Date.now() - t0); return r;
    } };
};
let stopped = '';
if (PAID) await openWindow(admin, tag, CAP, 60, 'the intake reply steps per effort (ledger 1642, review of the effort fix): the real routines, nothing sent');
try {
  await E2E_RUN.run({ tag, secret }, async () => {
    for (const [n, k] of cases.entries()) {
      const said = String(k.conversation).split('\n').map((x) => x.trim()).filter(Boolean);
      const turns = said.map((text) => ({ role: 'user', text }));
      const message = said[said.length - 1];
      for (const arm of (n % 2 ? [...ARMS].reverse() : ARMS)) {
        for (const step of ['held_reply', 'voice'] as const) {
          const out = { ms: [] as number[] }; const t0 = Date.now();
          const v = step === 'held_reply'
            ? await heldReply(deps(arm, out, step), checklist as never, exhausted, 'en', message, turns.slice(0, -1), Date.now() + REPLY_MS)
            : await intakeVoice(deps(arm, out, step), { draft: 'Thank you. Next we need to know: ' + checklist[0].question, lang: 'en', message, conversation: turns.slice(0, -1), next: { text: checklist[0].question }, deadline: Date.now() + REPLY_MS });
          rows.push({ id: k.id, step, arm, wall_ms: Date.now() - t0, answered: v.by === 'model', words: v.text.split(/\s+/).filter(Boolean).length, usd: 0, calls: out.ms.length });
          console.log(`${step.padEnd(10)} ${k.id.padEnd(8)} ${arm.padEnd(6)} ${((Date.now() - t0) / 1000).toFixed(1)}s ${v.by}`);
        }
      }
    }
  });
} catch (e) { stopped = e instanceof CapReached ? e.message : 'error: ' + String((e as Error)?.message ?? e); }
finally { if (PAID) await closeWindow(admin, tag).catch(() => {}); }
const { data: cost } = await admin.from('ai_cost_log').select('cost_usd_reported').eq('e2e_run_tag', tag);
const spend = (cost ?? []).reduce((s, r: { cost_usd_reported: number | null }) => s + Number(r.cost_usd_reported ?? 0), 0);
const summary: Record<string, unknown> = {};
for (const step of ['held_reply', 'voice']) for (const arm of ARMS) {
  const xs = rows.filter((r) => r.step === step && r.arm === arm);
  summary[step + ' ' + arm] = { n: xs.length, answered: xs.filter((r) => r.answered).length, p50_ms: pct(xs.map((r) => r.wall_ms), 0.5), p95_ms: pct(xs.map((r) => r.wall_ms), 0.95), max_ms: Math.max(0, ...xs.map((r) => r.wall_ms)) };
}
const result = { run_tag: 'qd_run:' + tag, spend_usd: +spend.toFixed(6), stopped: stopped || null, checklist: 'carpentry-joinery', exhausted, summary, rows };
console.log(JSON.stringify({ ...result, rows: undefined }, null, 1));
if (arg('--out')) await writeJson(arg('--out')!, result);
