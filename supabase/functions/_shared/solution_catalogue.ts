// solution_catalogue — WHAT AN EXPERT PUTS TO A CUSTOMER WHO IS DECIDING WHAT TO DO (10 Nov 2026, sales_engineer; founder
// ledger 1572: "MDF partition -> suggest PVC panels or wrap, ask budget, dimensions"; 1579: "the PVC panel example was only an
// example ... every trade, product and service"; 1586: every trade in the UAE but food and beverage).
//
// MEASURED (design audit of 10 Nov 2026, docs/reports/2026-11-10-design-sales-intake-and-matching.md, A1 NOT MET): the
// request chat's prompt said "Do not pitch ... your only job is to collect a complete, accurate brief" and "do NOT lecture",
// the portal recommended only when the customer was unsure, and nothing anywhere proposed solutions for the condition a
// customer described; the founder's own example got no plan in any language.
//
// WHAT LIVES HERE (pure, tested offline in solution_catalogue.test.ts):
//   * the catalogue (solution_catalogue.json): trade families x common problems x two or three options, each option with
//     the taxonomy service keys that do that work, so a CHOSEN option names the services matching uses;
//   * ADVISE_RULE: the one instruction every surface gives the model (diagnose -> advise -> qualify);
//   * problemsFor: which reference problems a conversation is given. BY TRADE ONLY, never by the customer's words (ruling
//     890: no word matching): the trade the conversation already reasoned (the request chat's category, the portal plan's
//     trade, the state's taxonomy codes) and the problem the state already holds. With no trade yet, problemIndex gives the
//     model one line per problem and it names the one that applies;
//   * readSolution / solutionPatch: the model's answer, kept only where it names a real problem and option, as the state's
//     condition, options_offered, chosen_option, budget and specs.service_keys (_shared/inquiry_state.ts).
// THE CATALOGUE IS SEED KNOWLEDGE, NOT A BOUNDARY (ledger 1586): for a trade it does not cover, the agent advises from the
// trade's packs (inquiry_trades.ts) and its own expertise, and an option outside the catalogue is kept by its own words with
// no service key (problem null). No price, figure, brand or supplier is in it.
// prevented by: supabase/functions/_shared/solution_catalogue.test.ts,
//               scripts/checks/every_solution_option_names_a_taxonomy_service.test.mjs
import DATA from './solution_catalogue.json' with { type: 'json' };
import type { InquiryState, StatePatch } from './inquiry_state.ts';

export interface SolutionOption { code: string; en: string; ar: string; why: string; trade_off: string; check?: string; services: string[] }
export interface Problem { code: string; family: string; situation: string; qualify: string; options: SolutionOption[] }
export interface Family { code: string; en: string; ar: string; trades: string[]; problems: Problem[] }

type RawFamily = Omit<Family, 'problems'> & { problems: Omit<Problem, 'family'>[] };
export const FAMILIES: Family[] = (DATA.families as RawFamily[]).map((f) => ({ ...f, problems: f.problems.map((p) => ({ ...p, family: f.code })) }));
export const PROBLEMS: Map<string, Problem> = new Map(FAMILIES.flatMap((f) => f.problems.map((p) => [p.code, p] as [string, Problem])));
const FAMILY: Map<string, Family> = new Map(FAMILIES.map((f) => [f.code, f]));

/** The taxonomy trade codes a family covers: the trades of the services its options name. */
export function familyCodes(f: Family): Set<string> {
  return new Set(f.problems.flatMap((p) => p.options.flatMap((o) => o.services.map((k) => k.split('.')[0]))));
}
const CODES: Map<string, Set<string>> = new Map(FAMILIES.map((f) => [f.code, familyCodes(f)]));

/** The reference problems for a conversation: the problem the state holds first, then the problems of the families whose
 *  trades include the conversation's slug, then those covering one of its taxonomy codes. At most `max`. */
export function problemsFor(o: { slug?: string | null; codes?: string[] | null; held?: string | null; max?: number }): Problem[] {
  const out: Problem[] = [];
  const add = (p: Problem | undefined) => { if (p && !out.includes(p)) out.push(p); };
  if (o.held) add(PROBLEMS.get(o.held));
  // the families whose FIRST trade is the slug, then the others naming it, in the order they name it
  if (o.slug) {
    const slug = o.slug;
    FAMILIES.filter((f) => f.trades.includes(slug)).sort((a, b) => a.trades.indexOf(slug) - b.trades.indexOf(slug)).forEach((f) => f.problems.forEach(add));
  }
  for (const c of o.codes ?? []) for (const f of FAMILIES) if (CODES.get(f.code)!.has(c)) f.problems.forEach(add);
  return out.slice(0, o.max ?? 6);
}

/** A catalogue option by its "problem/option" key (the form the model is given), or null. */
export function optionOf(key: string | null | undefined): { problem: Problem; option: SolutionOption } | null {
  const [p, o] = String(key ?? '').trim().split('/');
  const problem = PROBLEMS.get(p ?? '');
  const option = problem?.options.find((x) => x.code === o);
  return problem && option ? { problem, option } : null;
}
/** The taxonomy service keys a chosen option names ([] for an option outside the catalogue). */
export function serviceKeysOfChoice(choice: { problem: string | null; option: string } | null | undefined): string[] {
  if (!choice?.problem) return [];
  return optionOf(choice.problem + '/' + choice.option)?.option.services ?? [];
}

// ── what the model is told ───────────────────────────────────────────────────────────────────────────────────────────
/** THE ONE ADVISING RULE (request chat, portal, WhatsApp). Lifts the old "do not pitch / do not lecture" only as far as
 *  putting options to a customer who is deciding; the bans on a pitch, a price and a supplier's name stay. */
export const ADVISE_RULE = 'ADVISE LIKE AN EXPERT WHEN THEY ARE DECIDING (founder ledger 1572 and 1586: reason like an experienced technical salesperson in THIS trade). '
  + '(a) Diagnose from what they describe: the object or service, its material and present condition, where it is (the emirate matters for approvals and limits), what it is used for, and any constraint (a wet area, a children\'s room, heat, access, the budget). '
  + '(b) When they describe a problem or ask what to do and have not chosen a solution, put two or three suitable options to them, one short line each: what it is, why it suits their case, and its honest trade-off; when one is clearly better for their case, say which and why. Use the REFERENCE OPTIONS where they fit; where none fits, use your own expertise in that trade. '
  + '(c) Then ask the one or two details that price it: sizes or quantities, finish or grade, budget, timing, and any approval the location needs. '
  + '(d) Once they have chosen, do not offer options again and never argue for one they turned down; a constraint they gave (a children\'s room, a wet area) stays true for every later recommendation. '
  + 'Never a sales pitch, never volunteer a price, never name a supplier or company, never promise what a supplier will do.';

/** The reference options for a prompt. '' when there are none. */
export function solutionsBlock(problems: Problem[], lang: 'en' | 'ar' = 'en'): string {
  if (!problems.length) return '';
  const lines = ['REFERENCE OPTIONS (common situations in these trades, written by our sales engineers from established practice for YOUR reasoning: adapt them to this customer\'s case, never read them out; no prices are in them). Each option key is problem/option:'];
  for (const p of problems) {
    lines.push(`[${p.code}] when: ${p.situation}`);
    for (const o of p.options) {
      lines.push(`  - ${p.code}/${o.code}: ${o.en}${lang === 'ar' ? ` (Arabic: ${o.ar})` : ''}. Suits: ${o.why}. Trade-off: ${o.trade_off}.${o.check ? ' First: ' + o.check + '.' : ''}`);
    }
    lines.push(`  then qualify: ${p.qualify}.`);
  }
  return lines.join('\n');
}
/** With no trade reasoned yet: one line per problem, so the model can name the one that applies (about 2k tokens). */
export function problemIndex(): string {
  return 'REFERENCE SITUATIONS (name the one that applies in "problem", if any; its options are given once the trade is known):\n'
    + FAMILIES.map((f) => `${f.en}: ` + f.problems.map((p) => `${p.code} (${p.situation.split(/[(,]/)[0].trim()})`).join('; ')).join('\n');
}

/** The solution so far, for a prompt. '' when nothing is held. */
export function solutionStateText(st: Pick<InquiryState, 'condition' | 'options_offered' | 'chosen_option'> | null | undefined, lang: 'en' | 'ar' = 'en'): string {
  if (!st) return '';
  const label = (problem: string | null, option: string) => { const x = problem ? optionOf(problem + '/' + option) : null; return x ? (lang === 'ar' ? x.option.ar : x.option.en) : option; };
  const lines: string[] = [];
  const cond = Object.entries(st.condition ?? {});
  if (cond.length) lines.push('- what they described: ' + cond.map(([k, v]) => `${k.replace(/_/g, ' ')}: "${String(v.value).slice(0, 160)}"` + (v.changed_from ? ` (changed from "${String(v.changed_from).slice(0, 80)}")` : '')).join('; '));
  const offered = st.options_offered ?? [];
  if (offered.length) lines.push('- options already put to them: ' + offered.slice(-9).map((o) => label(o.problem, o.option)).join('; '));
  const c = st.chosen_option;
  if (c?.option) lines.push(`- THEY CHOSE: ${c.label || label(c.problem, c.option)}` + (c.changed_from ? ` (earlier they chose ${label(c.changed_from.problem, c.changed_from.option)}; only the latest counts)` : '') + '. Do not offer options again; qualify this one.');
  return lines.length ? 'THE SOLUTION SO FAR (kept from every message of this conversation):\n' + lines.join('\n') : '';
}

// ── what the model answered ──────────────────────────────────────────────────────────────────────────────────────────
export interface SolutionReading {
  problem: string | null;
  condition: Record<string, string>;
  options_offered: { problem: string | null; option: string }[];
  chosen_option: { problem: string | null; option: string; label: string } | null;
  budget: string | null;
}
const CONDITION_KEYS = ['object', 'material', 'condition', 'location', 'use', 'constraint', 'constraints', 'size', 'quantity'];
const short = (x: unknown, n: number) => (typeof x === 'string' ? x.replace(/\s+/g, ' ').trim().slice(0, n) : '');
/** A key the model wrote: "problem/option" from the catalogue, or its own few words for an option outside it. */
function keyOf(x: unknown): { problem: string | null; option: string; label: string } | null {
  const s = short(x, 120);
  if (!s) return null;
  const hit = optionOf(s);
  if (hit) return { problem: hit.problem.code, option: hit.option.code, label: hit.option.en };
  if (/^[a-z0-9_]+\/[a-z0-9_]+$/.test(s)) return null;   // a catalogue-shaped key that does not exist is a misread, never kept
  return { problem: null, option: s.slice(0, 60), label: s };
}
/** The solution half of a model's JSON answer (request chat) or of the state reader's (portal, WhatsApp). */
export function readSolution(out: unknown): SolutionReading {
  const o = (out && typeof out === 'object' ? out : {}) as Record<string, unknown>;
  const condition: Record<string, string> = {};
  if (o.condition && typeof o.condition === 'object' && !Array.isArray(o.condition)) {
    for (const [k, v] of Object.entries(o.condition as Record<string, unknown>)) {
      const key = k.toLowerCase().replace(/[^a-z_]/g, '_');
      const val = Array.isArray(v) ? v.map((x) => short(x, 80)).filter(Boolean).join(', ') : short(v, 240);
      if (CONDITION_KEYS.includes(key) && val) condition[key === 'constraints' ? 'constraint' : key] = val;
    }
  }
  const offered = (Array.isArray(o.options_offered) ? o.options_offered : []).map(keyOf).filter((x): x is NonNullable<typeof x> => !!x).slice(0, 4)
    .map(({ problem, option }) => ({ problem, option }));
  const chosen = keyOf(o.chosen_option);
  const problem = short(o.problem, 60);
  return { problem: PROBLEMS.has(problem) ? problem : (chosen?.problem ?? offered.find((x) => x.problem)?.problem ?? null),
    condition, options_offered: offered, chosen_option: chosen, budget: short(o.budget, 120) || null };
}
/** The state patch of a reading: condition, options offered, the choice, the budget, and the chosen option's service keys
 *  under specs.service_keys (the same merge keeps an earlier choice's keys in changed_from). */
export function solutionPatch(r: SolutionReading): Pick<StatePatch, 'condition' | 'options_offered' | 'chosen_option' | 'budget' | 'specs'> {
  const keys = serviceKeysOfChoice(r.chosen_option);
  return {
    ...(Object.keys(r.condition).length ? { condition: r.condition } : {}),
    ...(r.options_offered.length ? { options_offered: r.options_offered } : {}),
    ...(r.chosen_option ? { chosen_option: r.chosen_option } : {}),
    ...(r.budget ? { budget: r.budget } : {}),
    ...(keys.length ? { specs: { service_keys: keys.join(', ') } } : {}),
  };
}
/** The service keys the state's choice names (specs.service_keys, else the chosen option's). */
export function stateServiceKeys(st: Pick<InquiryState, 'specs' | 'chosen_option'> | null | undefined): string[] {
  const held = String(st?.specs?.service_keys?.value ?? '').split(',').map((x) => x.trim()).filter((x) => /^[a-z0-9_]+\.[a-z0-9_]+$/.test(x));
  return held.length ? held : serviceKeysOfChoice(st?.chosen_option ?? null);
}
export const familyOf = (problem: string) => FAMILY.get(PROBLEMS.get(problem)?.family ?? '') ?? null;
/** The situation the state is about: the chosen option's, else the latest option offered's, else the one the model named. */
export function heldProblem(st: Pick<InquiryState, 'chosen_option' | 'options_offered' | 'condition'> | null | undefined): string | null {
  return st?.chosen_option?.problem ?? [...(st?.options_offered ?? [])].reverse().find((o) => o.problem)?.problem ?? st?.condition?.problem?.value ?? null;
}
