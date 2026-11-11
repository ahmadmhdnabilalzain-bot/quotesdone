// The prompt-diet switch registry (_shared/prompt_diet.ts): the default follows the kind, an override is read defensively and
// scoped by class, and a failed read is the defaults. No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DIET_DEFAULTS, DIET_TTL_MS, dietOn, dietSetting, parseDiet, readDiet, type DietSwitch } from './prompt_diet.ts';

const NAMES = Object.keys(DIET_DEFAULTS) as DietSwitch[];

Deno.test('a structural switch is ON by default and a content switch is OFF until its eval passes', () => {
  assert(NAMES.length >= 6);
  for (const n of NAMES) {
    const d = DIET_DEFAULTS[n];
    assertEquals(d.on, d.kind === 'structural', n);
    assert(d.measured.length > 40 && d.where.length > 0, n + ' names its measurement and where it acts');
  }
});

Deno.test('the override row switches a cut on or off by name; unknown names and bad shapes are ignored', () => {
  const o = parseDiet({ retry_notes_ride_after_the_payload: false, retrieval_keeps_the_top_rows_above_a_floor: { on: true, k: 3, classes: ['internal_judgement'] },
    not_a_switch: true, the_reviewer_reads_the_cited_sources_only: 'yes', settled_facts_ride_as_one_shared_cache_block: { k: -2, delta: 'x' } });
  assertEquals(dietOn(o, 'retry_notes_ride_after_the_payload', 'internal_judgement'), false);
  assertEquals(dietOn(o, 'retrieval_keeps_the_top_rows_above_a_floor', 'internal_judgement'), true);
  assertEquals(dietSetting(o, 'retrieval_keeps_the_top_rows_above_a_floor').k, 3);
  assertEquals(dietSetting(o, 'retrieval_keeps_the_top_rows_above_a_floor').delta, 0.04, 'an unset parameter keeps its default');
  assertEquals(dietOn(o, 'the_reviewer_reads_the_cited_sources_only'), false, 'a string is not a switch value');
  assertEquals(dietSetting(o, 'settled_facts_ride_as_one_shared_cache_block').on, true, 'a bad k or delta changes nothing');
  assert(!('not_a_switch' in o));
  for (const bad of [null, 1, 'x', '[1]', [], '{"retry_notes_ride_after_the_payload": false']) assertEquals(parseDiet(bad), {}, String(bad));
  assertEquals(parseDiet('{"retry_notes_ride_after_the_payload": false}'), { retry_notes_ride_after_the_payload: false }, 'jsonb read back as text');
});

Deno.test('a switch scoped to classes applies only to those classes; an unscoped one to every call', () => {
  assertEquals(dietOn({ retrieval_keeps_the_top_rows_above_a_floor: true }, 'retrieval_keeps_the_top_rows_above_a_floor', 'internal_judgement'), true);
  assertEquals(dietOn({ retrieval_keeps_the_top_rows_above_a_floor: true }, 'retrieval_keeps_the_top_rows_above_a_floor', 'customer_communication'), false);
  assertEquals(dietOn({ retrieval_keeps_the_top_rows_above_a_floor: true }, 'retrieval_keeps_the_top_rows_above_a_floor', null), false);
  assertEquals(dietOn({ retrieval_keeps_the_top_rows_above_a_floor: { on: true, classes: null } }, 'retrieval_keeps_the_top_rows_above_a_floor', 'customer_communication'), true);
  assertEquals(dietOn({}, 'retry_notes_ride_after_the_payload', 'anything'), true);
  assertEquals(dietOn(null, 'review_route_caches_by_the_model_it_calls', null), true);
});

Deno.test('the row is read once a minute per client, and a failed or missing read is the defaults', async () => {
  let reads = 0;
  const admin = (value: unknown, fail = false) => ({ from: (t: string) => { assertEquals(t, 'decision_policy'); return { select: () => ({ eq: (_k: string, key: string) => {
    assertEquals(key, 'prompt_diet'); reads++;
    return { maybeSingle: () => fail ? Promise.reject(new Error('down')) : Promise.resolve({ data: value === undefined ? null : { value }, error: null }) };
  } }) }; } });
  const a = admin({ retry_notes_ride_after_the_payload: false });
  const t0 = 1_000_000;
  assertEquals(await readDiet(a, t0), { retry_notes_ride_after_the_payload: false });
  await readDiet(a, t0 + DIET_TTL_MS - 1);
  assertEquals(reads, 1, 'inside the minute the row is not read again');
  await readDiet(a, t0 + DIET_TTL_MS);
  assertEquals(reads, 2);
  assertEquals(await readDiet(admin(undefined), t0), {});
  assertEquals(await readDiet(admin(null, true), t0), {});
});
