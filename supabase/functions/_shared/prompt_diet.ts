// THE PROMPT DIET: every cut to what a model call carries, each behind its own switch (it_engineer, 11 Nov 2026; founder
// ruling 1619, 10 Nov 2026: "study the whole path of the ~45,000 tokens per AI call and cut it without affecting quality").
// The measurement and the reasoning for each switch: docs/reports/2026-11-11-prompt-diet.md.
//
// TWO KINDS OF SWITCH, AND THE DEFAULT FOLLOWS THE KIND:
//   - structural: the model is sent the same words; only where they sit (which cache block, which message) changes, so a
//     provider cache can read them back. ON by default.
//   - content: the model is sent fewer words (fewer retrieved rows, no planner, a shorter review). OFF until the paired
//     replay of scripts/eval/prompt_diet_eval.mjs passes on the same model (judge equivalent-or-better on >= 95% of cases,
//     zero rule violations), then switched on by the override row below, never by editing a default here.
//
// THE OVERRIDE (switch any cut off or on without a deploy): one decision_policy row, key 'prompt_diet', whose value names
// switches by name, e.g. {"retry_notes_ride_after_the_payload": false} or
// {"retrieval_keeps_the_top_rows_above_a_floor": {"on": true, "classes": ["internal_judgement"], "k": 4, "delta": 0.04}}.
// A missing row, an unreadable row or an unknown name means the defaults below. Each reader keeps what it read for
// DIET_TTL_MS per worker, so a change reaches every worker within a minute.
// prevented by: _shared/prompt_diet.test.ts

export const PROMPT_DIET_KEY = 'prompt_diet';
export const DIET_TTL_MS = 60_000;

export type DietSwitch =
  | 'review_route_caches_by_the_model_it_calls'
  | 'settled_facts_ride_as_one_shared_cache_block'
  | 'retry_notes_ride_after_the_payload'
  | 'retrieval_keeps_the_top_rows_above_a_floor'
  | 'the_reviewer_reads_the_cited_sources_only'
  | 'a_trend_relevance_choice_plans_and_retrieves_nothing';

/** classes: the task classes (or, where named so, the think() surfaces) the switch applies to; null = every one. */
export interface DietSetting { on: boolean; classes: string[] | null; k?: number; delta?: number }
export interface DietDefault extends DietSetting { kind: 'structural' | 'content'; where: string; measured: string }

export const DIET_DEFAULTS: Readonly<Record<DietSwitch, DietDefault>> = {
  review_route_caches_by_the_model_it_calls: {
    kind: 'structural', on: true, classes: null, where: 'ai_gateway/route_cache.ts',
    measured: 'fn_ai_route_review_for returns the BASE route\'s cache flag (its primary\'s supports_cache) with another model: 20 Sonnet 5.5 '
      + 'conversation_reply calls on 10 Nov 15:58-16:06 (counterpart Luna Pro), 32.7-36.2k prompt tokens each, 0 read and 0 written',
  },
  settled_facts_ride_as_one_shared_cache_block: {
    kind: 'structural', on: true, classes: null, where: 'think/deps.ts (settled.ts splitSettled)',
    measured: 'think() marked the whole settled-facts prefix (company + seats + the seat\'s own card, ~16.9k tokens) as ONE block, so '
      + 'no seat ever read another seat\'s write: knowledge_validation on Sonnet, 7 days, ~14k written and ~1.5k read a call',
  },
  retry_notes_ride_after_the_payload: {
    kind: 'structural', on: true, classes: null, where: 'think/engine.ts',
    measured: 'a re-pass appended its note to the SYSTEM prompt, ahead of the sources payload, so the payload was never a cache '
      + 'read on the re-pass: 30 of 44 marketing runs and 28 of 149 it_engineer runs had a second pass (14 days)',
  },
  retrieval_keeps_the_top_rows_above_a_floor: {
    kind: 'content', on: false, classes: ['internal_judgement'], k: 4, delta: 0.04, where: 'think/engine.ts',
    measured: 'every retrieval step returns 12 rows (927 of 927 steps, 14 days); a run reads 21-56 rows and cites 1.4-7.1; cited rows '
      + 'sit at similarity p05 0.81-0.82 against a step best p50 0.856',
  },
  the_reviewer_reads_the_cited_sources_only: {
    kind: 'content', on: false, classes: null, where: 'think/engine.ts',
    measured: 'the independent review is sent every retrieved source (the same payload the author read), not the ones the answer cites',
  },
  a_trend_relevance_choice_plans_and_retrieves_nothing: {
    kind: 'content', on: false, classes: ['marketing.trend_relevance'], where: 'marketing/duties/trends_geo.ts',
    measured: '144 relevant/not-relevant headline choices a week, each a 34.5k-token plan and a 74k-token answer on Luna Pro '
      + '(~300 calls, ~16M of the week\'s 62.6M Luna Pro prompt tokens)',
  },
};

export type DietOverrides = Partial<Record<DietSwitch, boolean | Partial<DietSetting>>>;

/** The override row's value, read defensively: anything that is not an object of known names is ignored. */
export function parseDiet(value: unknown): DietOverrides {
  const v = typeof value === 'string' ? (() => { try { return JSON.parse(value); } catch (_e) { return null; } })() : value;
  if (!v || typeof v !== 'object' || Array.isArray(v)) return {};
  const out: DietOverrides = {};
  for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
    if (!(k in DIET_DEFAULTS)) continue;
    if (typeof x === 'boolean') { out[k as DietSwitch] = x; continue; }
    if (!x || typeof x !== 'object' || Array.isArray(x)) continue;
    const o = x as Record<string, unknown>; const s: Partial<DietSetting> = {};
    if (typeof o.on === 'boolean') s.on = o.on;
    if (o.classes === null || (Array.isArray(o.classes) && o.classes.every((c) => typeof c === 'string'))) s.classes = o.classes as string[] | null;
    if (typeof o.k === 'number' && Number.isFinite(o.k) && o.k >= 1) s.k = Math.floor(o.k);
    if (typeof o.delta === 'number' && Number.isFinite(o.delta) && o.delta >= 0) s.delta = o.delta;
    out[k as DietSwitch] = s;
  }
  return out;
}

/** The setting in force: the default, with the override laid over it. */
export function dietSetting(overrides: DietOverrides | null | undefined, name: DietSwitch): DietSetting {
  const d = DIET_DEFAULTS[name]; const o = overrides?.[name];
  const base: DietSetting = { on: d.on, classes: d.classes, ...(d.k !== undefined ? { k: d.k } : {}), ...(d.delta !== undefined ? { delta: d.delta } : {}) };
  if (o === undefined) return base;
  if (typeof o === 'boolean') return { ...base, on: o };
  return { ...base, ...o };
}

/** Whether `name` applies to `cls` (a task class or a surface). A switch scoped to classes applies to no unnamed call. */
export function dietOn(overrides: DietOverrides | null | undefined, name: DietSwitch, cls?: string | null): boolean {
  const s = dietSetting(overrides, name);
  if (!s.on) return false;
  if (!s.classes) return true;
  return !!cls && s.classes.includes(cls);
}

// deno-lint-ignore no-explicit-any
type From = { from: (t: string) => any };
const memo = new WeakMap<object, { at: number; p: Promise<DietOverrides> }>();
/** The override row, read at most once per DIET_TTL_MS per client. Never throws: a failed read is the defaults. */
export function readDiet(admin: From, now = Date.now()): Promise<DietOverrides> {
  const hit = memo.get(admin);
  if (hit && now - hit.at < DIET_TTL_MS && now >= hit.at) return hit.p;
  const p = (async () => {
    try {
      const { data, error } = await admin.from('decision_policy').select('value').eq('key', PROMPT_DIET_KEY).maybeSingle();
      return error ? {} : parseDiet(data?.value);
    } catch (_e) { return {}; }
  })();
  memo.set(admin, { at: now, p });
  return p;
}
