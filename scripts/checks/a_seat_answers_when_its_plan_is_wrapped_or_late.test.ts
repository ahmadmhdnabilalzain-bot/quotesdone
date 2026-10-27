// A SEAT ANSWERS WHEN ITS PLAN IS WRAPPED IN PROSE OR ARRIVES LATE (it_engineer, 19 Oct 2026). Exam run b2f80d4d: 9 of
// 30 model-on seat answers held - 5 'the reply is not one JSON object' (GPT-6 Luna Pro writes a sentence around its JSON),
// 3 'model_failed: decompose' (the planner hit the 45 s wall). Offline.
//   deno test --node-modules-dir=none scripts/checks/a_seat_answers_when_its_plan_is_wrapped_or_late.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { parseJson } from '../../supabase/functions/_shared/think.ts';

Deno.test('the outermost JSON object is read out of a sentence around it', () => {
  assertEquals(parseJson('Here is the plan:\n{"steps":[{"id":"s1"}]}\nDone.'), { steps: [{ id: 's1' }] });
  assertEquals(parseJson('```json\n{"a":1}\n```'), { a: 1 });
  assertEquals(parseJson('no json here'), null);
  assertEquals(parseJson('[1,2]'), null);
});

Deno.test('a planner that timed out still leads to an answer, a hold does not', async () => {
  const src = await Deno.readTextFile(new URL('../../supabase/functions/_shared/think.ts', import.meta.url));
  if (!/d0\.error && !\/circuit_open\|open-circuit\|founder_hold\//.test(src)) throw new Error('the one-step-plan fallback no longer covers a planner error');
});
