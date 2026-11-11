// think/diet.ts — the prompt-diet cuts think() applies, each a pure function behind its switch (_shared/prompt_diet.ts;
// it_engineer, 11 Nov 2026; measurement and reasoning: docs/reports/2026-11-11-prompt-diet.md).
// prevented by: _shared/prompt_diet_think.test.ts
import type { DietSetting } from '../prompt_diet.ts';

/** RETRY NOTES RIDE AFTER THE PAYLOAD (structural, ON). A re-pass (a refused draft, or the independent reviewer's problems)
 *  added its note to the END OF THE SYSTEM PROMPT, which comes before the payload (the question, the context and every
 *  retrieved source), so on a provider that caches by prefix the whole payload was paid again at full price on the re-pass.
 *  The same note now ends the input: the system prompt and the payload are byte-identical to the first pass, and the note
 *  is the last thing the model reads (as aiReply's rewrites have always done). The words are unchanged. */
export function placeRetryNote(on: boolean, system: string, input: string, note: string): { system: string; input: string } {
  if (!note) return { system, input };
  return on ? { system, input: input + '\n\n' + note.trim() } : { system: system + note, input };
}

type Row = { similarity?: unknown };
/** RETRIEVAL KEEPS THE TOP ROWS ABOVE A FLOOR (content, OFF until the replay passes). A step's rows, best first, cut to at most
 *  `k` and to those within `delta` of the step's best similarity. Measured (14 days, 927 steps): every step returns 12 rows;
 *  a run cites 1.4-7.1 of the 21-56 it reads, and cited rows sit at similarity p05 0.81-0.82 against a step best p50 0.856.
 *  Order among kept rows is the routine's own (it already ranks); a row with no similarity is kept only inside k. */
export function keepTopRows<T extends Row>(rows: T[], s: Pick<DietSetting, 'k' | 'delta'>): T[] {
  const k = Math.max(1, Math.floor(s.k ?? 4));
  const delta = Math.max(0, s.delta ?? 0.04);
  const sim = (r: Row) => Number(r.similarity);
  const best = rows.reduce((m, r) => Number.isFinite(sim(r)) ? Math.max(m, sim(r)) : m, -Infinity);
  return rows.filter((r) => !Number.isFinite(best) || !Number.isFinite(sim(r)) || sim(r) >= best - delta - 1e-9).slice(0, k);
}

type Src = { id: string };
/** THE REVIEWER READS THE CITED SOURCES ONLY (content, OFF until the replay passes). The review checks the answer's limits, sums
 *  and safety statements against what it relies on; the answer must cite every source it relies on (validator.ts requireTrail).
 *  An answer that cites nothing is reviewed against every source, as before: the cut never leaves a reviewer with nothing. */
export function reviewSources<T extends Src>(on: boolean, sources: T[], cited: unknown): T[] {
  if (!on) return sources;
  const ids = new Set((Array.isArray(cited) ? cited : []).map(String));
  const mine = sources.filter((s) => ids.has(s.id));
  return mine.length ? mine : sources;
}
