// THE SEAT EXAM, THROUGH think(): the same questions and the same grade as scripts/eval/seat_qualification_exam.mjs, but
// each question goes through think() itself, so the planner first reads the question's trade and kind and retrieval is
// asked for that area (knowledge_lookup_goes_to_the_trade_first.sql). Seat: sales_engineer, 28 Sep 2026.
//
// TWO MODES.
//   retrieval (default) Only the planner (decompose) runs; the run is stopped at synthesis. PASS = in the first 5 rows of
//                       ANY retrieval call think() made there is an expected entry whose excerpt (the 1,200 characters
//                       the seat sees) holds every expected fact: grade() of the exam.
//   --answer            (ceo, 19 Oct 2026, ledger 1003 stage 2 / 894) think() runs end to end on the seat's REAL models
//                       (OpenRouter stays on for every test, ledger 1260) and the full answer is written out. Nothing
//                       here grades the answer with a model: a reader (the CEO session) judges each answer against the
//                       item's `answer_must` and records the verdict in docs/audits (no paid judge). `facts_in_answer`
//                       is printed only as a hint for the reader.
//   --trace             (with --answer) also write, per item, the ids of the sources think() returned and its steps.
//   --reworded          ask each item's q_reworded instead of q_en: the exam is passed on meaning, not on the wording
//                       its knowledge entry happens to use.
//
// The subject is a fixture, so a held question is never queued in the seat's work queue.
//
//   deno run -A --node-modules-dir=none scripts/eval/seat_exam_through_think.ts --seat ceo [--answer] [--reworded]
//     [--tag <run>] [--exam file.json] [--concurrency 4] [--limit 10] [--out r.json]
import { createClient } from 'jsr:@supabase/supabase-js@2';
import type { ThinkDeps } from '../../supabase/functions/_shared/think.ts';

const REF = 'htdblwldjkcgjvmqkbeh';
const arg = (f: string) => { const i = Deno.args.indexOf(f); return i >= 0 ? Deno.args[i + 1] : null; };
const seat = arg('--seat') ?? 'sales_engineer';
const limit = Number(arg('--limit') ?? 1e9);
const ANSWER = Deno.args.includes('--answer');
const REWORDED = Deno.args.includes('--reworded');
const TRACE = Deno.args.includes('--trace');
// --ids a,b,c or --ids @file (one id per line): only these items (a re-run of the ones that failed).
const idArg = arg('--ids');
const IDS = idArg ? (idArg.startsWith('@') ? await Deno.readTextFile(idArg.slice(1)) : idArg).split(/[\s,]+/).filter(Boolean) : null;
const home = Deno.env.get('USERPROFILE') ?? Deno.env.get('HOME') ?? '';
const mgmt = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? await Deno.readTextFile(`${home}/.supabase/access-token`)).trim();
const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: `Bearer ${mgmt}` } })).json();
const service = keys.find((k: { name: string }) => k.name === 'service_role')?.api_key;
if (!service) throw new Error('no service_role key from the management API');
const admin = createClient(`https://${REF}.supabase.co`, service, { auth: { persistSession: false } });
// The gateway client (llm.ts) and the run-tag fetch forwarder (e2e_run.ts) read these at import, so they are set first.
Deno.env.set('SUPABASE_URL', `https://${REF}.supabase.co`);
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', service);
const { think, defaultDeps } = await import('../../supabase/functions/_shared/think.ts');
const { E2E_RUN } = await import('../../supabase/functions/_shared/e2e_run.ts');
// --tag <run>: a rehearsal_window 'qd_run:<run>' the operator opened (models_allowed, capped). A fixture question
// reasons only inside such a window (think.fixtureInOpenWindow); without one every item is held fixture_no_spend.
const TAG = arg('--tag');
// The gateway admits only a caller holding its own credential (app_secrets.cred_fn_<fn>). The exam calls as
// knowledge_exam, the credential that exists for exactly this, so exam spend is never booked as a seat's live work.
const inRun = <T>(f: () => Promise<T>) => (TAG ? E2E_RUN.run({ tag: TAG, secret: null }, f) : f());

type Item = { id: string; checklist: string; q_en: string; q_reworded?: string; answer_must?: string[]; expected_entry_ids: string[]; expected_facts: string[] };
const exam = JSON.parse(await Deno.readTextFile(arg('--exam') ?? `knowledge/exams/${seat}.json`)) as { items: Item[] };
const has = (t: unknown, f: string) => String(t ?? '').toLowerCase().includes(f.toLowerCase());
class Stop extends Error {}

const out: Record<string, unknown>[] = [];
let pass = 0, held = 0;
// --concurrency N: items run N at a time (a full think() answer takes 30-90 s).
const items = exam.items.filter((x) => !IDS || IDS.includes(x.id)).slice(0, limit);
let next = 0;
async function worker() { while (next < items.length) await one(items[next++]); }
async function one(it: Item) {
  const question = REWORDED ? it.q_reworded : it.q_en;
  if (!question) { out.push({ id: it.id, status: 'no q_reworded' }); held++; return; }
  const live = defaultDeps(admin, 'knowledge_exam');
  const errors: string[] = [];
  const calls: { args: Record<string, unknown>; top: { id: string; excerpt: string }[] }[] = [];
  const deps: ThinkDeps = {
    ...live,
    llm: ANSWER ? async (phase, ...rest) => { const r = await live.llm(phase, ...rest); if (r.error) errors.push(`${phase}: ${r.error}`); return r; } : (phase, ...rest) => (phase === 'decompose' ? live.llm(phase, ...rest) : Promise.reject(new Stop('stopped before ' + phase))),
    rpc: async (fn, args) => {
      const r = await live.rpc(fn, args);
      if (/^fn_reason_retrieve/.test(fn)) calls.push({ args: { ...args, p_embedding: undefined, p_embedding_gte: undefined }, top: (Array.isArray(r.data) ? r.data : []).slice(0, 5) });
      return r;
    },
  };
  let status = 'stopped', answer = '', model: string | null = null, trace: unknown = null;
  try {
    const r = await inRun(() => think(deps, { seat: seat as never, surface: 'think.answer', question, context: { audience: 'internal' }, subject: { fixture: true } as never }));
    status = r.status === 'held' ? 'held: ' + ((r as { reason?: string }).reason ?? '') : r.status; answer = r.answer; model = r.model ?? null;
    if (TRACE) trace = { sources: r.sources.map((s) => s.id), steps: r.steps.map((s) => ({ id: s.id, status: s.status, detail: s.detail })) };
  } catch (e) { if (!(e instanceof Stop)) status = 'error: ' + (e as Error).message; }
  const retrieved = calls.some((c) => c.top.some((r) => it.expected_entry_ids.includes(r.id) && it.expected_facts.every((f) => has(r.excerpt, f))));
  if (ANSWER) {
    if (status !== 'answered') held++;
    out.push({ id: it.id, checklist: it.checklist, question, answer_must: it.answer_must ?? [], status, model, retrieved, errors, facts_in_answer: it.expected_facts.filter((f) => has(answer, f)).length + '/' + it.expected_facts.length, answer, ...(TRACE ? { trace } : {}) });
    console.log(`${it.id} ${status} model=${model ?? '-'} retrieved=${retrieved}${errors.length ? ' errors=' + errors.join('; ') : ''}`);
    return;
  }
  if (!calls.length) { held++; out.push({ id: it.id, status: status === 'stopped' ? 'no retrieval' : status }); return; }
  if (retrieved) pass++;
  out.push({ id: it.id, pass: retrieved, trade: calls[0].args.p_trade ?? null, kind: calls[0].args.p_kind ?? null, top: calls.map((c) => c.top.map((r) => r.id)) });
  console.log(`${it.id} ${retrieved ? 'PASS' : 'fail'} trade=${calls[0].args.p_trade ?? '-'} kind=${calls[0].args.p_kind ?? '-'}`);
}
await Promise.all(Array.from({ length: Number(arg('--concurrency') ?? 1) }, worker));
out.sort((a, b) => String(a.id).localeCompare(String(b.id), 'en', { numeric: true }));
const n = items.length;
console.log(ANSWER ? `${seat}: answered ${n - held}/${n} (to be judged by a reader)` : `${seat}: pass ${pass}/${n}; not run (held / no retrieval) ${held}`);
if (arg('--out')) await Deno.writeTextFile(arg('--out')!, JSON.stringify({ seat, mode: ANSWER ? 'answer' : 'retrieval', reworded: REWORDED, pass, held, items: out }, null, 1));
