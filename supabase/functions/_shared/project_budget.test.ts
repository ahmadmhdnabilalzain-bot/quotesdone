// project_budget.test.ts — a project's budget is a positive, bounded AED amount, and project_api enforces it.
// deno test --no-lock --allow-read supabase/functions/_shared/project_budget.test.ts
//
// MEASURED 21 Sep 2026 (customer-portal journey audit): project_api stored Number(body.budget_total)
// as given — negatives, any size, and NaN for free text. The last test fails if either write path in
// project_api stops routing the budget through parseBudget (the server is the trust boundary; the
// form's check is only a courtesy).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { BUDGET_MAX_AED, parseBudget } from './project_budget.ts';

Deno.test('empty means no budget; a plain positive AED amount is kept', () => {
  for (const v of [undefined, null, '', '  ']) assertEquals(parseBudget(v), { ok: true, value: null });
  assertEquals(parseBudget('250000'), { ok: true, value: 250000 });
  assertEquals(parseBudget(180000), { ok: true, value: 180000 });
  assertEquals(parseBudget('1,250,000.50'), { ok: true, value: 1250000.5 });
  assertEquals(parseBudget(BUDGET_MAX_AED), { ok: true, value: BUDGET_MAX_AED });
});

Deno.test('negative, zero, absurd, free text, NaN, Infinity and exponents are refused with EN and AR words', () => {
  for (const v of ['-5000', -1, 0, '0', BUDGET_MAX_AED + 1, '1e12', 'abc', 'about 50k', 'NaN', NaN, 'Infinity', Infinity, '12.345', {}, [1]]) {
    const r = parseBudget(v);
    assert(!r.ok, 'accepted: ' + String(v));
    if (!r.ok) {
      assertEquals(r.code, 'budget_invalid');
      assert(/[A-Za-z]/.test(r.en) && !/[؀-ۿ]/.test(r.en), 'English message is not English: ' + r.en);
      assert(/[؀-ۿ]/.test(r.ar), 'Arabic message is not Arabic: ' + r.ar);
    }
  }
  const neg = parseBudget('-5000'); assert(!neg.ok && /more than AED 0/.test(neg.en), 'a negative is not told it must be positive');
  const big = parseBudget('5000000000'); assert(!big.ok && /1,000,000,000/.test(big.en));
});

Deno.test('project_api bounds the budget on create AND update, and never stores a raw Number(body.budget_total)', async () => {
  const src = await Deno.readTextFile(new URL('../project_api/index.ts', import.meta.url));
  assertEquals((src.match(/parseBudget\(body\.budget_total\)/g) || []).length, 2, 'create and update must both call parseBudget(body.budget_total)');
  assert(!/Number\(body\.budget_total\)/.test(src), 'project_api converts the budget without the bound');
  assertEquals((src.match(/budget_total: budget\.value|patch\.budget_total = budget\.value/g) || []).length, 2, 'a write path stores something other than the checked value');
});
