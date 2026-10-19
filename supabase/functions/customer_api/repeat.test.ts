import { assertEquals } from 'jsr:@std/assert@1';
import { repeatPlan, type Original } from './repeat.ts';

const base: Original = {
  category: 'tiling', emirate: 'Dubai', raw_input: 'Porcelain tiles 60x60, 120 m2', summary: 'Tiling 120 m2', budget: '20000',
  scope_type: 'single', trades: ['tiling'], floor: '2', project_id: null, lang: 'ar', created_at: '2026-09-01T08:00:00Z',
  spec: { quantity: 120, finish: 'matt', plausibility: { ok: true }, boq_check: { status: 'confirmed' },
    customer_requirements: { category: 'tiling', required_by: { v: 'date', date: '2026-09-21', text: '2026-09-21' } } },
};

Deno.test('the specs carry over; the model-only and drawing-only keys do not', () => {
  const p = repeatPlan(base, new Date('2026-10-05T10:00:00Z'));
  assertEquals(p.brief.details, { quantity: 120, finish: 'matt' });
  assertEquals(p.brief.requirements, base.spec!.customer_requirements);
  assertEquals(p.body.lang, 'ar');
  assertEquals(p.body.drawing, null);
  assertEquals(p.category, 'tiling');
});

Deno.test('a passed needed-by date moves forward by the original lead time', () => {
  const p = repeatPlan(base, new Date('2026-10-05T10:00:00Z'));
  assertEquals(p.body.requirement_edits, { required_by: '2026-10-25' }); // 20 days, as first given
});

Deno.test('a future date is kept as the customer gave it', () => {
  const p = repeatPlan(base, new Date('2026-09-10T10:00:00Z'));
  assertEquals(p.body.requirement_edits, {});
});

Deno.test('a suspended customer cannot repeat: repeat_inquiry is on the list the suspension gate reads', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const list = src.match(/const MUTATING = \[([^\]]*)\]/)?.[1] || '';
  assertEquals(list.includes("'repeat_inquiry'"), true);
});

Deno.test('the sourcing choice is the customer\'s own; nothing is split that was not', () => {
  assertEquals(repeatPlan({ ...base, scope_type: 'turnkey', trades: ['tiling', 'painting'] }).body.scope_type, 'turnkey');
  assertEquals(repeatPlan({ ...base, scope_type: 'multi', trades: ['tiling', 'painting'] }).body.scope_type, 'multi');
  assertEquals(repeatPlan({ ...base, scope_type: 'multi', trades: ['tiling'] }).body.scope_type, 'single');
  assertEquals(repeatPlan({ ...base, scope_type: null }).body.scope_type, 'single');
});
