import { assertEquals } from 'jsr:@std/assert@1';
import { repeatPlan, type Original } from './repeat.ts';
// The function is index.ts plus its modules (9 Nov 2026 split): read all of it, as the node checks do.
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

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
  const src = functionSource('customer_api');
  const list = src.match(/const MUTATING = \[([^\]]*)\]/)?.[1] || '';
  assertEquals(list.includes("'repeat_inquiry'"), true);
});

Deno.test('the sourcing choice is the customer\'s own; nothing is split that was not', () => {
  assertEquals(repeatPlan({ ...base, scope_type: 'turnkey', trades: ['tiling', 'painting'] }).body.scope_type, 'turnkey');
  assertEquals(repeatPlan({ ...base, scope_type: 'multi', trades: ['tiling', 'painting'] }).body.scope_type, 'multi');
  assertEquals(repeatPlan({ ...base, scope_type: 'multi', trades: ['tiling'] }).body.scope_type, 'single');
  assertEquals(repeatPlan({ ...base, scope_type: null }).body.scope_type, 'single');
});

// Release review of #1180: the check runs before any write, and the customer's edits reach the copy.
import { repeatCheck } from './repeat.ts';

Deno.test('a request with no stored answers is refused by the check that runs before the intake insert', () => {
  const p = repeatPlan({ ...base, spec: { quantity: 1 } }, new Date('2026-10-05T10:00:00Z'));
  const c = repeatCheck(p, new Date('2026-10-05T10:00:00Z'));
  assertEquals(c.ok, false);
});

Deno.test('the customer edits summary, budget, emirate and date before posting; the copy links to the original', () => {
  const p = repeatPlan({ ...base, id: 'orig-1' }, new Date('2026-10-05T10:00:00Z'), { summary: 'Tiling 150 m2', budget: '', emirate: 'Sharjah', required_by: '2026-11-30' });
  assertEquals(p.brief.repeat_of, 'orig-1');
  assertEquals([p.body.summary, p.body.budget, p.body.emirate], ['Tiling 150 m2', null, 'Sharjah']);
  assertEquals(p.body.requirement_edits, { required_by: '2026-11-30' });
});

Deno.test('no edits keeps every original value', () => {
  const p = repeatPlan(base, new Date('2026-09-10T10:00:00Z'), {});
  assertEquals([p.body.summary, p.body.budget, p.body.emirate], [base.summary, base.budget, base.emirate]);
});

Deno.test('only allowlisted spec keys are copied: checklist keys and brief keys stay, anything else is dropped', () => {
  const o = { ...base, spec: { ...base.spec, glazing: 'double', injected: '<script>', supplier_note: 'x' } };
  const p = repeatPlan(o, new Date('2026-09-10T10:00:00Z'), {}, ['glazing']);
  assertEquals(p.brief.details, { quantity: 120, finish: 'matt', glazing: 'double' });
});

// Nightly run 077cbbfc (10 Nov 2026): the customer crawl pressed "Repeat" on all four viewports and the preview answered
// HTTP 422 nothing_to_repeat for a request with no stored answers (8 console errors). The button is now offered only when
// the door would build the copy: canRepeat is the door's own repeatCheck, served by my_inquiries, read by the card.
Deno.test('the card offers Repeat only when the door would build it', async () => {
  const { canRepeat, repeatCheck } = await import('./repeat.ts');
  const now = new Date('2026-11-10T22:30:00Z');
  const noAnswers: Original = { ...base, spec: { quantity: 120 } };
  // the same answer the door gives: refused, and never offered
  assertEquals(repeatCheck(repeatPlan(noAnswers, now), now).ok, false);
  assertEquals(canRepeat(noAnswers, now), false);
  // what the door would build is offered, whatever the door says of it
  assertEquals(canRepeat(base, now), repeatCheck(repeatPlan(base, now), now).ok);
  // one trade of a larger request is repeated through its parent (409 repeat_the_whole_request)
  assertEquals(canRepeat({ ...base, parent_inquiry_id: 'p-1' }, now), false);
  // served on every request, and read by the card before it draws the button
  const src = functionSource('customer_api');
  assertEquals(/can_repeat: canRepeat\(i\)/.test(src), true, 'my_inquiries must serve can_repeat');
  const card = await Deno.readTextFile(new URL('../../../src/components/me/requests/InquiryCard.tsx', import.meta.url));
  assertEquals(/inq\.can_repeat !== false && <div/.test(card), true, 'the card must not draw Repeat when can_repeat is false');
});
