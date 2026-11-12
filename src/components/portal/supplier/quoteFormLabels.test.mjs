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
