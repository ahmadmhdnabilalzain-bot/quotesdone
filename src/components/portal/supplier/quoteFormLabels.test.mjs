// node --test src/components/portal/supplier/quoteFormLabels.test.mjs
// Walk of 12 Nov 2026, S7 (sales_engineer, built by it_engineer): eleven quote-form boxes were named only by a placeholder that goes as
// he types (w2_iphone_quote_form.jpg: total, lead time, validity, payment, warranty, the four line-item boxes, scope, notes; their
// <Lbl> names were screen-reader only). This fails if the form stops showing those names or the line items lose their heading row.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const form = readFileSync(new URL('./core/QuoteForm.tsx', import.meta.url), 'utf8');

test('the quote form shows the names of its boxes, and the line items have a heading row', () => {
  const shown = /const LABELS_SHOWN = '([^']*)'/.exec(form);
  assert.ok(shown, 'LABELS_SHOWN is gone');
  for (const v of ['[&>label>span.sr-only]', '[&>div>label>span.sr-only]']) assert.ok(shown[1].includes(v + ':not-sr-only'), v);
  assert.match(form, /return <div className=\{cn\('mt-5 flex flex-col gap-4[^']*', LABELS_SHOWN\)\}>/, 'the form container no longer shows its labels');
  assert.match(form, /data-testid="quote-line-heads"/);
  assert.match(form, /const LINE_HEADS = \{ description: 'Description', qty: 'Qty', unit: 'Unit', price: 'Unit price' \}/);
  // the boxes the walk named are still labelled, so showing the labels shows their names
  for (const k of ["t(lang, 'total_aed')", "t(lang, 'lead_time')", "t(lang, 'scope_work')", "t(lang, 'notes_customer')"]) assert.ok(form.includes('<Lbl ' + (k.includes('total') || k.includes('lead') ? 'className="flex-1" ' : '') + 'text={' + k), k);
});

// Second review of the walk fixes, R5: the line items were a 460 px row inside a sideways scroll; at 360 and 390 "Unit" was cut and
// "Unit price" and Remove were off screen. This fails if a line item is given a fixed width wider than a phone again, or stops stacking.
test('a quote line fits a 360 px phone: Description on its own row, then Qty / Unit / Unit price, then Remove', () => {
  const items = form.slice(form.indexOf('data-testid="quote-line-heads"'), form.indexOf('+ Add item'));
  for (const m of items.matchAll(/(?<![\w:-])min-w-\[(\d+)px\]/g)) assert.ok(Number(m[1]) <= 300, 'a line item is ' + m[1] + ' px wide on every screen');
  assert.doesNotMatch(items, /overflow-x-auto/, 'the line items scroll sideways again');
  const row = /\{items\.map\(\(it, ix\) => \(<div key=\{ix\} className="([^"]*)"/.exec(form)[1];
  for (const c of ['grid', 'grid-cols-3', '[&>label:first-of-type]:col-span-3', '[&>button]:col-span-3', 'sm:flex', 'max-sm:[&_input]:max-w-none!', '[&>button]:min-h-11'])
    assert.ok(row.split(/\s+/).includes(c), c);
  assert.match(form, /data-testid="quote-line-heads" className="mb-1 hidden gap-1\.5 sm:flex/);
  assert.match(form, /data-testid="quote-line-heads-phone" className="col-span-3[^"]*sm:hidden"/);
});
