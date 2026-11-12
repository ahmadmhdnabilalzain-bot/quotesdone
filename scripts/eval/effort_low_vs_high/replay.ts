// LOW VS HIGH EFFORT, THE PAID ROUND: the real routines, twice on the same recorded input (it_engineer, 11 Nov 2026; founder
// rulings 1630 and 1618; report docs/reports/2026-11-11-history-and-effort.md section 6). Started only with --paid; without it
// the same code runs every case through the real routine against a model stub and prints the prompt sizes (no window, no spend).
//
// WHAT RUNS. For each case of the cases file (node scripts/eval/effort_low_vs_high.mjs cases: recorded text, anonymised, kept
// outside the repository) the surface's own routine is called once per ARM with the SAME input:
//   wa_inbound.intent_table    whatsappReadings   the live intent table, trade list and menu, the turns the sender had exchanged
//   wa_inbound.greeting_state  menuMeaning        the live menu, not awaiting a problem
//   wa_inbound.needs_a_person  needsAPerson       the message alone, as classification.ts calls it
//   inquiry_intake.trade       tradeOf            every category_specs slug as a candidate, as inquiry_intake/handle.ts calls it
//   inquiry_intake.exact_spec  statedSpecs        the required fields of the trade tradeOf chose for that chat (the high arm's
//                                                 choice; the low arm's when the high arm did not answer)
//   wa_inbound.status_lane     modelSays          eval A's fixed ZZ DEMO status turns (no status ask from a real number is on
//                                                 record), on status_reply with the lane's rules, the references as must
// THE ARMS are low and high, and the effort the surface runs at today when that is neither (medium for a sorting surface and for
// the status lane), so the result also says what ruling 1630 costs where it moved a call from low to medium. The order of
// the arms rotates by case, so no arm is always the one that finds the provider's prompt cache warm.
// THE EFFORT IS FORCED AT THE ONE DOOR: the deps' llm sends `effort` on every call of the arm, whatever the routine asked.
// The gateway honours a caller's effort except that it raises 'low' on a class that DECIDES (effort_policy.ts effortFor);
// every call here is customer_communication or status_reply, which are conversations, and the run refuses to start unless
// effortFor says 'low' stays 'low' for both.
//
// SAFETY. Every call goes through the production gateway under this run's tag, inside a rehearsal window whose cap is the
// run's cap; guardSpend reads ai_cost_log before EVERY call and stops the run before one that would reach the cap. Nothing
// is written to a person or to production state: the deps' rpc lets through only the read-only routines in READ_ONLY and
// answers every other routine (the judgement row, a hold, a knowledge proposal) with a stub, recorded in the result; nothing
// is embedded or retrieved (these decisions hand over an empty plan); no rate key rides, so no sender's bucket is touched.
// What IS written: one rehearsal_window row, and the ai_cost_log / llm_attempt rows the gateway writes for its own calls.
//
// NOT CUT AT THE PRODUCTION CLOCKS. A classification has 20 s in production (wa_inbound/classification.ts CLASSIFY_MS), an
// intake step what is left of the 24 s turn (inquiry_intake/turn_clock.ts), a reply call 25 s (ai_reply.ts PER_CALL_MS). Here
// each call may take the client's own 45 s, so both arms answer and can be compared; `over_clock` counts the calls
// production would have cut.
//
//   deno run --no-lock --node-modules-dir=none -A scripts/eval/effort_low_vs_high/replay.ts --cases <cases.json> --paid
//     [--cap 0.45] [--out docs/reports/effort-low-vs-high-2026-11-11] [--detail <file outside the repository>]
//     [--surfaces a,b] [--limit N] [--arms low,medium,high] [--trade-from <an earlier run's effort_low_vs_high.json>]
import { createHash } from 'node:crypto';
import { AED_PER_USD, arg, CapReached, closeWindow, connect, flag, guardSpend, newTag, openWindow, routeOf, spentUsd, writeJson, type Ctx } from '../model_routing/harness.ts';
import { CASES_A, type CaseA } from '../model_routing/cases_a.ts';
import { CAP_USD, CASES_PER_SURFACE, PRICE, residualIdentity, SHAPE } from '../effort_low_vs_high.mjs';
// TYPES ONLY from the functions tree here. The modules themselves are imported AFTER connect() (below): _shared/e2e_run.ts
// installs the fetch forwarder that carries the run tag only if SUPABASE_URL is set when it is first imported, and connect()
// is what sets it. Imported at the top, the forwarder was never installed: this file's first paid smoke (11 Nov 2026, 5 calls,
// USD 0.0097) reached the gateway with no tag, was booked as ordinary wa_inbound traffic (ai_cost_log 102237, 102244, 102255,
// 102265, 102277) and the spend guard, which reads the run's tagged rows, saw USD 0. Two fences now: the forwarder is
// asserted before the window opens, and a paid call that leaves no tagged cost row stops the run.
import type { PolicyEffort } from '../../../supabase/functions/_shared/effort_policy.ts';
import type { ThinkDeps, Turn } from '../../../supabase/functions/_shared/think.ts';
import type { WaIntent, WaTrade } from '../../../supabase/functions/_shared/reasoned_channels.ts';

type Arm = PolicyEffort;
type Surface = keyof typeof SHAPE;
const ORDER: Surface[] = ['wa_inbound.greeting_state', 'wa_inbound.needs_a_person', 'wa_inbound.intent_table', 'inquiry_intake.trade', 'inquiry_intake.exact_spec', 'wa_inbound.status_lane'];
/** What production cuts a call at, per surface (ms): the header's three clocks. The intake step: 24 s less the 2.5 s reserve. */
export const CLOCK_MS: Record<Surface, number> = { 'wa_inbound.greeting_state': 20_000, 'wa_inbound.needs_a_person': 20_000, 'wa_inbound.intent_table': 20_000,
  'inquiry_intake.trade': 21_500, 'inquiry_intake.exact_spec': 21_500, 'wa_inbound.status_lane': 25_000 };
/** The task class each surface's model call is asked as (think/routing.ts taskClassFor for a customer; status_lane.ts STATUS_CLASS). */
const CLASS_OF: Record<Surface, string> = { 'wa_inbound.greeting_state': 'customer_communication', 'wa_inbound.needs_a_person': 'customer_communication',
  'wa_inbound.intent_table': 'customer_communication', 'inquiry_intake.trade': 'customer_communication', 'inquiry_intake.exact_spec': 'customer_communication',
  'wa_inbound.status_lane': 'status_reply' };
const FN_OF = (s: Surface) => s.startsWith('inquiry_intake') ? 'inquiry_intake' : 'wa_inbound';
/** The routines the deps' rpc lets through to production. Each only reads; every other name is answered by a stub. */
export const READ_ONLY: ReadonlySet<string> = new Set(['fn_ai_route', 'fn_company_context', 'fn_price_brief', 'fn_e2e_run_tag_open']);

/** The arms of a surface: low and high, and between them the effort it runs at today when that is neither. */
export const armsOf = (live: Arm): Arm[] => live === 'low' || live === 'high' ? ['low', 'high'] : ['low', live, 'high'];
/** The live arm is run on a surface's first cases only (low and high run on all): it prices ruling 1630, it does not decide the pass. */
export const LIVE_ARM_CASES = CASES_PER_SURFACE;
/** Nearest-rank percentile of a sample (p in 0..1). With 8 values p95 is the largest. */
export function pct(xs: number[], p: number): number | null {
  const s = xs.filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
  return s.length ? s[Math.min(s.length - 1, Math.max(0, Math.ceil(p * s.length) - 1))] : null;
}
const WESTERN = (t: string) => t.replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d))).replace(/[۰-۹]/g, (d) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)));
const figuresOf = (t: string) => (WESTERN(t).match(/\d+(?:[.,]\d+)*/g) ?? []).map((n) => n.replace(/,/g, ''));
/** The figures a reply states that none of the texts it was given state (the status lane's second, independent check). */
export function ungroundedFigures(reply: string, given: string[]): string[] {
  const known = new Set(given.flatMap(figuresOf));
  return [...new Set(figuresOf(reply).filter((n) => !known.has(n)))];
}
const sha = (t: string) => createHash('sha256').update(t, 'utf8').digest('hex').slice(0, 12);
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

interface Case { id: string; source: string; audience?: string; text?: string; conversation?: Turn[] | string; turns?: number }
interface CostRow { id: number; model_used: string | null; task_class: string | null; prompt_tokens: number | null; output_tokens: number | null; cached_in_tokens: number | null;
  latency_ms: number | null; cost_usd_reported: number | null; cost_aed: number | null; ok: boolean | null }
interface Call { phase: string; task_class: string; wall_ms: number; answered: boolean; model: string | null; error: string | null; rows: CostRow[] }
interface ArmResult { arm: Arm; answered: boolean; outcome: unknown; wall_ms: number; calls: Call[]; usd: number; gateway_ms: number; prompt_tokens: number; cached_tokens: number;
  output_tokens: number; over_clock: number; error: string | null; private?: unknown }

class Untagged extends Error {}
const usdOf = (r: CostRow) => r.cost_usd_reported != null ? Number(r.cost_usd_reported) : Number(r.cost_aed ?? 0) / AED_PER_USD;

if (import.meta.main) {
  const PAID = flag('--paid');
  const CAP = Number(arg('--cap') ?? '0.45');
  if (!(CAP > 0 && CAP <= CAP_USD)) throw new Error(`the cap is at most USD ${CAP_USD} (the brief, ruling 1618's side-by-side)`);
  const OUT = arg('--out') ?? 'docs/reports/effort-low-vs-high-2026-11-11';
  const DETAIL = arg('--detail');
  const LIMIT = Number(arg('--limit') ?? '0');
  const WANT = new Set((arg('--surfaces') ?? ORDER.join(',')).split(',')) as Set<string>;
  const casesFile = arg('--cases');
  if (!casesFile) throw new Error('--cases <file> (made by: node scripts/eval/effort_low_vs_high.mjs cases)');
  const FILE = JSON.parse(await Deno.readTextFile(casesFile)) as { built_at: string; pools: Record<string, number>; cases: Record<string, Case[]> };

  // NOTHING THAT LOOKS LIKE A REAL IDENTITY LEAVES THIS MACHINE: checked again here, on the file as it is, before anything runs
  const texts = Object.values(FILE.cases).flat().flatMap((k) => [k.text ?? '', ...(typeof k.conversation === 'string' ? [k.conversation] : (k.conversation ?? []).map((t) => t.text))]);
  const left = [...new Set(texts.flatMap((t) => residualIdentity(t)))];
  if (left.length) throw new Error('the cases file carries what looks like a real identity; nothing was run: ' + left.length + ' hit(s)');

  const { admin, secret } = await connect();
  // the functions tree, now that SUPABASE_URL is set (the header says why the order matters)
  const { effortFor, surfaceEffort, SURFACES } = await import('../../../supabase/functions/_shared/effort_policy.ts');
  const { defaultDeps } = await import('../../../supabase/functions/_shared/think.ts');
  const { E2E_RUN } = await import('../../../supabase/functions/_shared/e2e_run.ts');
  const { whatsappReadings } = await import('../../../supabase/functions/_shared/reasoned_channels.ts');
  const { needsAPerson, statedSpecs, tradeOf } = await import('../../../supabase/functions/_shared/reasoned_decisions.ts');
  const { menuMeaning } = await import('../../../supabase/functions/_shared/reasoned_menus.ts');
  const { modelSays, WA_RULES } = await import('../../../supabase/functions/wa_inbound/model_says.ts');
  const { laneMust, STATUS_CLASS, STATUS_HISTORY_TURNS, STATUS_RULES } = await import('../../../supabase/functions/wa_inbound/status_lane.ts');
  const { menuItems } = await import('../../../supabase/functions/wa_inbound/menu.ts');
  if (PAID && (globalThis as { __qdE2eFetch?: boolean }).__qdE2eFetch !== true) throw new Error('the run-tag forwarder is not installed (e2e_run.ts was imported before SUPABASE_URL was set): a paid call would go out untagged; nothing was run');
  if (CLASS_OF['wa_inbound.status_lane'] !== STATUS_CLASS) throw new Error('the status lane is asked as ' + STATUS_CLASS + ' now; CLASS_OF is stale');
  // the gateway must leave these arms as asked (it raises a 'low' on a class that decides)
  for (const cls of new Set(Object.values(CLASS_OF))) for (const e of ['low', 'medium', 'high'] as const) {
    if (effortFor(cls, e) !== e) throw new Error(`the gateway would send ${effortFor(cls, e)} for a caller's ${e} on ${cls}: that arm cannot be measured through it`);
  }
  // the reference data each routine is handed in production, read the way production reads it
  const [{ data: intentRows }, { data: tradeRows }, { data: specRows }] = await Promise.all([
    admin.from('wa_reply_intent').select('intent_key,label').eq('active', true).order('sort').order('intent_key'),
    admin.from('taxonomy_trade').select('code,label,label_ar').eq('active', true).order('sort').order('code'),
    admin.from('category_specs').select('category,fields')]);
  const intents = (intentRows ?? []) as WaIntent[]; const trades = (tradeRows ?? []) as WaTrade[];
  const specs = new Map(((specRows ?? []) as { category: string; fields: unknown }[]).map((s) => [String(s.category), Array.isArray(s.fields) ? s.fields as { key?: string; question?: string; required?: boolean }[] : []]));
  const slugs = [...specs.keys()];
  if (!intents.length || !trades.length || !slugs.length) throw new Error(`reference data unread: ${intents.length} intents, ${trades.length} trades, ${slugs.length} slugs`);
  // classification.ts menuOffer: both languages' titles, paired by option id
  const menuOffer = (audience: string) => menuItems('en', audience === 'supplier' ? 'supplier' : 'unknown').map((i) => {
    const ar = menuItems('ar', audience === 'supplier' ? 'supplier' : 'unknown').find((x) => x.id === i.id);
    return { id: i.id, title: i.item + (ar ? ' / ' + ar.item : ''), description: i.description + (ar ? ' / ' + ar.description : '') };
  });
  const routes: Record<string, { model: string | null; fallback: string | null }> = {};
  for (const [cls, seat] of [['customer_communication', 'customer_support'], ['customer_communication', 'sales_engineer'], [STATUS_CLASS, 'customer_support']]) routes[cls + ' / ' + seat] = await routeOf(admin, cls, seat);

  const tag = newTag('evaleff');
  const c: Ctx = { admin, tag, secret, capUsd: CAP };
  const stubbed: Record<string, number> = {};
  let lastCostId = 0; let fatal: Error | null = null;
  const costRows = async (): Promise<CostRow[]> => {
    const { data, error } = await admin.from('ai_cost_log').select('id,model_used,task_class,prompt_tokens,output_tokens,cached_in_tokens,latency_ms,cost_usd_reported,cost_aed,ok')
      .eq('e2e_run_tag', tag).gt('id', lastCostId).order('id');
    if (error) throw new Error('the run\'s cost rows could not be read, the run stops: ' + error.message);
    return (data ?? []) as CostRow[];
  };
  // the next call's worst case for the spend guard: the surface's measured shape with nothing cached, at the arm's output, and
  // the 1.6x this model bills over the estimate (.claude/memory/the-prompt-diet-switches-and-where-the-tokens-go.md)
  const estimate = (s: Surface, arm: Arm) => 1.6 * (SHAPE[s].inTok * PRICE.in + (arm === 'low' ? SHAPE[s].outLow : SHAPE[s].outHigh) * PRICE.out) / 1e6;

  /** The routine's deps for one arm: the production gateway for the model, production for the reads in READ_ONLY, a stub for the rest. */
  const replayDeps = (surface: Surface, arm: Arm, calls: Call[]): ThinkDeps => {
    const live = defaultDeps(admin, FN_OF(surface));
    return {
      gate: () => Promise.resolve({ allowed: true } as never),   // the gateway itself still enforces every hold
      embed: () => Promise.resolve(null), embedFailure: () => 'replay: these decisions retrieve nothing', space: () => Promise.resolve('gte' as const),
      diet: () => live.diet!(),
      rpc: (fn, args) => { if (READ_ONLY.has(fn)) return live.rpc(fn, args); stubbed[fn] = (stubbed[fn] ?? 0) + 1; return Promise.resolve({ data: null, error: null }); },
      llm: async (phase, system, input, o) => {
        if (!PAID) {
          calls.push({ phase, task_class: o.taskClass, wall_ms: 0, answered: false, model: null, error: 'dry run: ' + (system.length + (o.sysShared?.length ?? 0) + (o.sysStable?.length ?? 0)) + ' system + ' + (input.length + (o.history ?? []).reduce((n, h) => n + h.content.length, 0)) + ' input characters', rows: [] });
          return { content: null, model: null, error: 'dry_run' };
        }
        // aiReply answers a throwing llm with "no reply" (its .catch), so a stop is also kept here and re-thrown after the case
        if (fatal) throw fatal;
        try { await guardSpend(c, estimate(surface, arm), `${surface} (${arm})`); } catch (e) { fatal = e as Error; throw e; }
        const t0 = Date.now();
        const r = await live.llm(phase, system, input, { ...o, effort: arm, rateKey: undefined });
        const wall = Date.now() - t0;
        // the gateway writes the call's cost row as it answers; a streamed call's row can land a moment after the body
        let rows: CostRow[] = [];
        for (let i = 0; i < 16 && !rows.length; i++) { rows = await costRows(); if (!rows.length) await new Promise((res) => setTimeout(res, 500)); }
        if (rows.length) lastCostId = rows[rows.length - 1].id;
        // an answer with no tagged cost row means the call was booked outside this run: the guard above would be blind to it
        else if (r.content) { fatal = new Untagged(`a paid ${surface} call was answered but left no ai_cost_log row under qd_run:${tag}; the run stops`); throw fatal; }
        calls.push({ phase, task_class: o.taskClass, wall_ms: wall, answered: !!r.content, model: r.model ?? null, error: r.error ? String(r.error).slice(0, 200) : null, rows });
        return r;
      },
    };
  };

  // ── one case on one arm, per surface ────────────────────────────────────────────────────────────────────────────────
  const phone = (i: number) => 'whatsapp:+9715000000' + String(10 + (i % 90)).padStart(2, '0');
  // exact_spec's category: the trade the HIGH arm chose for the conversation, the LOW arm's when the high arm did not answer;
  // --trade-from <an earlier run's effort_low_vs_high.json> supplies them when the trade surface is not part of this run
  const tradeBy = { high: new Map<string, string | null>(), low: new Map<string, string | null>() };
  if (arg('--trade-from')) {
    const prev = JSON.parse(await Deno.readTextFile(arg('--trade-from')!)) as { results?: Record<string, { rows?: { id: string; arms: Record<string, { outcome: unknown }> }[] }> };
    for (const row of prev.results?.['inquiry_intake.trade']?.rows ?? []) for (const a of ['high', 'low'] as const) {
      const v = row.arms[a]?.outcome; if (typeof v === 'string' && slugs.includes(v)) tradeBy[a].set(row.id, v);
    }
  }
  const statusCases: CaseA[] = (['status', 'invoice', 'report', 'code'] as const).flatMap((kind) => CASES_A.filter((k) => k.kind === kind).slice(0, 2));
  const inRun = <T>(f: () => Promise<T>) => E2E_RUN.run({ tag, secret }, f);
  const runOne = async (surface: Surface, k: Case | CaseA, i: number, arm: Arm): Promise<ArmResult> => {
    const calls: Call[] = []; const deps = replayDeps(surface, arm, calls);
    let answered = false; let outcome: unknown = null; let priv: unknown; let error: string | null = null;
    try {
      await inRun(async () => {
        if (surface === 'wa_inbound.greeting_state') {
          const q = k as Case; const r = await menuMeaning(deps, { text: q.text!, awaitingProblem: false, menu: menuOffer(q.audience ?? 'unknown') });
          answered = r.result.status === 'answered'; outcome = r.value;
        } else if (surface === 'wa_inbound.needs_a_person') {
          const q = k as Case; const r = await needsAPerson(deps, { seat: 'customer_support', surface, message: q.text!.slice(0, 4000),
            audience: q.audience === 'supplier' ? 'supplier' : 'customer', subject: { fixture: true, phone: phone(i), message_sid: null } });
          answered = r.result.status === 'answered'; outcome = r.value;
        } else if (surface === 'wa_inbound.intent_table') {
          const q = k as Case; const r = await whatsappReadings(deps, { message: q.text!, intents, trades, phone: phone(i), messageSid: null,
            audience: (q.audience === 'supplier' ? 'supplier' : q.audience === 'customer' ? 'customer' : 'unknown'), conversation: Array.isArray(q.conversation) ? q.conversation : [], menu: menuOffer(q.audience ?? 'unknown') });
          answered = r.result.status === 'answered'; outcome = { intent: r.intent, needs_person: r.needsPerson, menu: r.menu };
        } else if (surface === 'inquiry_intake.trade') {
          const q = k as Case; const r = await tradeOf(deps, { conversation: String(q.conversation), candidates: slugs.map((slug) => ({ slug, label: slug.replace(/[-_]/g, ' ') })), subject: { fixture: true } });
          answered = r.result.status === 'answered'; outcome = r.value && slugs.includes(r.value) ? r.value : null;
          if (arm === 'high' || arm === 'low') tradeBy[arm].set(q.id, outcome as string | null);
        } else if (surface === 'inquiry_intake.exact_spec') {
          const q = k as Case; const category = tradeBy.high.get(q.id) ?? tradeBy.low.get(q.id) ?? null;
          const fields = (category ? specs.get(category) ?? [] : []).filter((f) => f && f.required && f.key).map((f) => ({ key: String(f.key), question: String(f.question || f.key) }));
          if (!category || !fields.length) { error = 'not run: ' + (category ? 'the trade has no required spec' : 'neither arm chose a trade for this conversation'); return; }
          const r = await statedSpecs(deps, { conversation: String(q.conversation), category, fields });
          answered = r.result.status === 'answered';
          outcome = { category, asked: fields.length, stated: Object.entries(r.value ?? {}).filter(([, v]) => v.value).map(([key]) => key).sort() };
          priv = r.value;
        } else {
          const q = k as CaseA; const must = [...new Set(laneMust('status', String(q.facts ?? ''), q.lang).concat(q.must ?? []))];
          const said = await modelSays(deps, { audience: 'customer', lang: q.lang, message: q.message, situation: q.facts ?? '',
            conversation: (q.history ?? []).map((t) => ({ role: t.role, text: t.text })).slice(-STATUS_HISTORY_TURNS), subject: { fixture: true, phone: phone(i) }, budgetMs: 90_000,
            must, taskClass: STATUS_CLASS, briefInPrompt: false, laneRules: STATUS_RULES, effort: arm });
          answered = !!said.text;
          outcome = { replied: !!said.text, must_missing: must.filter((m) => !said.text.includes(m)).length, ungrounded_figures: ungroundedFigures(said.text, [q.facts ?? '', q.message, WA_RULES, STATUS_RULES, ...(q.history ?? []).map((t) => t.text)]),
            first_draft_sent: said.attempts.length === 1 && said.attempts[0] === 'route:ok', attempts: said.attempts.length, outage: said.outage };
          priv = { text: said.text, attempts: said.attempts, problems: said.problems };
        }
      });
    } catch (e) { if (e instanceof CapReached || e instanceof Untagged) throw e; error = String((e as Error)?.message ?? e).slice(0, 300); }
    if (fatal) throw fatal;
    const rows = calls.flatMap((x) => x.rows);
    // wall_ms is the time the caller waits for the model: the calls' own time, without this harness's spend and cost-row reads
    return { arm, answered, outcome, wall_ms: calls.reduce((n, x) => n + x.wall_ms, 0), calls, usd: rows.reduce((n, r) => n + usdOf(r), 0),
      // a call the gateway cut at its own wall leaves two rows (the attempt and the request), each with the whole wait: one call, its longest row
      gateway_ms: calls.reduce((n, x) => n + x.rows.reduce((m, r) => Math.max(m, Number(r.latency_ms ?? 0)), 0), 0),
      prompt_tokens: rows.reduce((n, r) => n + Number(r.prompt_tokens ?? 0), 0), cached_tokens: rows.reduce((n, r) => n + Number(r.cached_in_tokens ?? 0), 0),
      output_tokens: rows.reduce((n, r) => n + Number(r.output_tokens ?? 0), 0), over_clock: calls.filter((x) => x.wall_ms > CLOCK_MS[surface]).length, error, private: priv };
  };

  // ── the run ─────────────────────────────────────────────────────────────────────────────────────────────────────────
  const results: Record<string, unknown> = {}; const detail: Record<string, unknown> = {}; let stopped = '';
  if (PAID) await openWindow(admin, tag, CAP, 110, 'effort low vs high (rulings 1630/1618): the real routines twice on the same recorded input; nothing sent, writes stubbed');
  console.log(`effort low vs high: ${PAID ? 'PAID, run tag qd_run:' + tag + ', cap USD ' + CAP : 'dry run (no model call)'}; surfaces ${ORDER.filter((s) => WANT.has(s)).join(', ')}`);
  try {
    for (const surface of ORDER.filter((s) => WANT.has(s))) {
      const pool: (Case | CaseA)[] = surface === 'wa_inbound.status_lane' ? statusCases : (FILE.cases[surface] ?? []);
      const cases = LIMIT > 0 ? pool.slice(0, LIMIT) : pool;
      // --arms low,medium,high runs exactly those arms on every case (used to ask whether MEDIUM fits a clock that HIGH does not)
      const live = surfaceEffort(surface); const forced = (arg('--arms') ?? '').split(',').filter((a): a is Arm => a === 'low' || a === 'medium' || a === 'high');
      const arms = forced.length ? forced : armsOf(live);
      if (!arms.includes('low') || !arms.includes('high')) throw new Error('--arms must include low and high: they are the comparison');
      const rows: { id: string; source: string; text_sha: string; arms: Record<string, Omit<ArmResult, 'private' | 'calls'> & { calls: number; models: string[]; errors: string[] }>; agree_low_high: boolean | null }[] = [];
      const kept: unknown[] = [];
      for (const [i, k] of cases.entries()) {
        const mine = arms.filter((a) => a === 'low' || a === 'high' || forced.length > 0 || i < LIVE_ARM_CASES);
        const order = mine.map((_, n) => mine[(n + i) % mine.length]);   // rotate, so no arm always follows a cache-warming one
        const by: Record<string, ArmResult> = {};
        for (const arm of order) by[arm] = await runOne(surface, k, i, arm);
        const lo = by.low, hi = by.high;
        const ran = !lo.error?.startsWith('not run') && !hi.error?.startsWith('not run');
        const agree = !PAID || !ran ? null : lo.answered && hi.answered && same(agreementKey(surface, lo.outcome), agreementKey(surface, hi.outcome));
        const text = 'message' in k ? k.message : (k.text ?? String(k.conversation ?? ''));
        rows.push({ id: k.id, source: 'source' in k ? k.source : 'eval A fixed set (ZZ DEMO, scripted)', text_sha: sha(text), agree_low_high: agree,
          arms: Object.fromEntries(mine.map((a) => [a, { arm: a, answered: by[a].answered, outcome: by[a].outcome, wall_ms: by[a].wall_ms, usd: +by[a].usd.toFixed(6), gateway_ms: by[a].gateway_ms,
            prompt_tokens: by[a].prompt_tokens, cached_tokens: by[a].cached_tokens, output_tokens: by[a].output_tokens, over_clock: by[a].over_clock, error: by[a].error,
            calls: by[a].calls.length, models: [...new Set(by[a].calls.map((x) => x.model).filter((m): m is string => !!m))], errors: by[a].calls.map((x) => x.error).filter((e): e is string => !!e) }])) });
        kept.push({ id: k.id, input: k, arms: Object.fromEntries(mine.map((a) => [a, { outcome: by[a].outcome, private: by[a].private ?? null, calls: by[a].calls }])) });
        console.log(`${surface.padEnd(27)} ${k.id.padEnd(9)} ` + mine.map((a) => `${a}=${JSON.stringify(agreementKey(surface, by[a].outcome)).slice(0, 60)} ${(by[a].wall_ms / 1000).toFixed(1)}s $${by[a].usd.toFixed(4)}`).join(' | ')
          + (agree === null ? '' : agree ? '  SAME' : '  DIFFERENT') + (PAID ? '' : '  ' + (by.low.calls[0]?.error ?? by.low.error ?? '')));
      }
      const compared = rows.filter((r) => r.agree_low_high !== null);
      const agreed = compared.filter((r) => r.agree_low_high).length;
      const per = Object.fromEntries(arms.map((a) => {
        const xs = rows.map((r) => r.arms[a]).filter((x) => x && !x.error?.startsWith('not run'));
        const n = xs.length || 1;
        return [a, { cases: xs.length, answered: xs.filter((x) => x.answered).length, wall_ms_p50: pct(xs.map((x) => x.wall_ms), 0.5), wall_ms_p95: pct(xs.map((x) => x.wall_ms), 0.95),
          gateway_ms_p50: pct(xs.map((x) => x.gateway_ms), 0.5), gateway_ms_p95: pct(xs.map((x) => x.gateway_ms), 0.95), usd_per_case_mean: +(xs.reduce((s, x) => s + x.usd, 0) / n).toFixed(6),
          usd_per_case_p50: pct(xs.map((x) => x.usd), 0.5), calls_per_case_mean: +(xs.reduce((s, x) => s + x.calls, 0) / n).toFixed(2), prompt_tokens_mean: Math.round(xs.reduce((s, x) => s + x.prompt_tokens, 0) / n),
          cached_tokens_mean: Math.round(xs.reduce((s, x) => s + x.cached_tokens, 0) / n), output_tokens_mean: Math.round(xs.reduce((s, x) => s + x.output_tokens, 0) / n),
          calls_over_the_production_clock: xs.reduce((s, x) => s + x.over_clock, 0) }];
      })) as Record<string, { answered: number; cases: number; wall_ms_p50: number | null }>;
      const status = surface === 'wa_inbound.status_lane' ? rows.map((r) => r.arms.low.outcome as { replied: boolean; must_missing: number; ungrounded_figures: string[] }) : [];
      const statusOk = status.every((o) => o && o.replied && o.must_missing === 0 && o.ungrounded_figures.length === 0);
      const notSlower = per.low.wall_ms_p50 != null && per.high.wall_ms_p50 != null && per.low.wall_ms_p50 <= per.high.wall_ms_p50;
      const pass = PAID && compared.length > 0 && agreed / compared.length >= 0.95 && (surface !== 'wa_inbound.status_lane' || statusOk) && notSlower;
      const consequence = SURFACES[surface]?.consequence ?? 'decides';
      results[surface] = { consequence, effort_today: live, arms, cases: rows.length, compared: compared.length, agree_low_high: agreed, low_not_slower: notSlower,
        ...(surface === 'wa_inbound.status_lane' ? { low_carries_every_must_and_no_ungrounded_figure: statusOk } : {}), pass,
        // a surface that decides, or a conversation, is never lowered by this result (effort_policy.ts surfaceEffort)
        may_be_marked_proven_low: pass && consequence === 'sorting', per_arm: per, rows };
      detail[surface] = kept;
    }
  } catch (e) {
    stopped = e instanceof CapReached ? e.message : 'error: ' + String((e as Error)?.message ?? e);
  } finally {
    if (PAID) await closeWindow(admin, tag).catch(() => {});
  }
  if (!PAID) { console.log('dry run: no window was opened and no model was asked. Start the paid round with --paid.'); Deno.exit(stopped ? 2 : 0); }
  const spend = Number((await spentUsd(admin, tag)).toFixed(6));
  const { data: win } = await admin.from('rehearsal_window').select('run_tag,started_at,ended_at,models_allowed,cap_usd').eq('run_tag', 'qd_run:' + tag).maybeSingle();
  const out = { at: new Date().toISOString(), run_tag: 'qd_run:' + tag, cap_usd: CAP, spend_usd: spend, stopped: stopped || null, window: win ?? null, routes,
    pools: FILE.pools, cases_built_at: FILE.built_at, reference: { intents: intents.length, trades: trades.length, category_slugs: slugs.length },
    writes_answered_by_a_stub: stubbed, read_only_routines_let_through: [...READ_ONLY], production_clock_ms: CLOCK_MS, results };
  await writeJson(`${OUT}/effort_low_vs_high.json`, out);
  if (DETAIL) await writeJson(DETAIL, { ...out, detail });
  console.log(JSON.stringify({ run_tag: 'qd_run:' + tag, spend_usd: spend, stopped: stopped || null, window_closed: !!win?.ended_at,
    surfaces: Object.fromEntries(Object.entries(results).map(([k, v]) => { const r = v as { compared: number; agree_low_high: number; pass: boolean; may_be_marked_proven_low: boolean };
      return [k, `${r.agree_low_high}/${r.compared} same, pass ${r.pass}, provenLow ${r.may_be_marked_proven_low}`]; })) }, null, 1));
  Deno.exit(stopped ? 2 : 0);
}

/** What "the low arm answers as the high arm does" compares, per surface: the choice the caller acts on. */
export function agreementKey(surface: string, outcome: unknown): unknown {
  if (surface === 'inquiry_intake.exact_spec') { const o = outcome as { stated?: string[] } | null; return o?.stated ?? null; }
  if (surface === 'wa_inbound.status_lane') { const o = outcome as { replied?: boolean; must_missing?: number; ungrounded_figures?: string[] } | null; return o ? [o.replied === true, o.must_missing ?? 0, (o.ungrounded_figures ?? []).length] : null; }
  return outcome ?? null;
}
