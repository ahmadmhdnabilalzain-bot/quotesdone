// set_before_model — a PDF drawing set whose text layer code can count is counted by code BEFORE the vision model is
// asked (27 Oct 2026, sales_engineer; founder ledger 580). Measured on production that day: with the model on, the
// 8-sheet ZZ DEMO mechanical set came back from the model with 6 lines, two of them doubled and three items missing,
// while boqFromDrawingSet read every item exactly. This fails if the early set path is removed or moved after the key.
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/drawing_boq/set_before_model.test.ts
import { assert } from 'jsr:@std/assert@1';

Deno.test('drawing_boq counts a PDF set by code before it reads the AI key or calls the model', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const early = src.indexOf("fallback_reason: 'code_counted_the_set'");
  const key = src.indexOf("const key = await sec('cred_fn_ai');\n    if (!key || body.deterministic");
  assert(early > 0, 'the early drawing-set path is gone');
  assert(key > 0, 'the model path moved: re-anchor this test on it');
  assert(early < key, 'the drawing set must be tried before the model path');
});
