// A QUOTATION RE-PRICED BY WHATSAPP CHANGES THE PRICE THE CUSTOMER SEES (10 Nov 2026, customer_support; the supplier-quoting
// audit after #1901, founder ruling 1608).
//
// fn_supplier_apply_change (wa_inbound supplier_directive) set quotes.quote_amount alone and told the supplier "The customer sees
// the new price from now on", while quote_compare shows the customer price_ex_vat ?? quote_amount: the customer kept the old
// price, the reveal fee (app_fee, generated from quote_amount) moved, and the VAT amount stayed the old one. This fails if the
// re-price stops writing through fn_quote_reprice, or fn_quote_reprice stops moving every price column together. Bodies from the
// definition that wins the apply order, -- comments removed. Behaviour: the probe of the same name (rolled back on production).
//   node --test scripts/checks/a_quotation_re_priced_by_whatsapp_changes_the_price_the_customer_sees.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const SQL = 'scripts/sql/';
const FIX = 'a_quotation_re_priced_by_whatsapp_changes_the_price_the_customer_sees.sql';
const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = (f) => existsSync(SQL + 'pending/' + f.replace(/\.sql$/, '.txt'));
const defRe = (fn) => new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'i');
function winning(fn) {
  const defines = (f) => existsSync(SQL + f) && defRe(fn).test(readFileSync(SQL + f, 'utf8'));
  if (pending(FIX) && defines(FIX)) return FIX;
  const listed = manifest.filter(defines);
  assert.ok(listed.length, `no file defines ${fn}`);
  return listed[listed.length - 1];
}
function body(fn) {
  const src = readFileSync(SQL + winning(fn), 'utf8');
  const open = src.search(defRe(fn));
  const m = /\bas\s+(\$[a-z_]*\$)/i.exec(src.slice(open));
  assert.ok(m, `${fn} has no dollar-quoted body`);
  const start = open + m.index + m[0].length;
  return src.slice(start, src.indexOf(m[1], start)).replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');
}

test('the WhatsApp re-price writes through the one re-price, never quote_amount alone', () => {
  const b = body('fn_supplier_apply_change');
  assert.match(b, /perform public\.fn_quote_reprice\(v_q\.id, v_num\);/);
  assert.doesNotMatch(b, /update public\.quotes set quote_amount/, 'a re-price that sets quote_amount alone leaves the customer the old price');
  assert.match(b, /excluding VAT/, 'the supplier must be told which basis his figure was read on');
});

test('the re-price moves the price the customer compares, the reveal fee base and the VAT together', () => {
  const b = body('fn_quote_reprice');
  for (const c of ['quote_amount = p_amount', 'price_ex_vat = p_amount', 'amount_as_stated = p_amount'])
    assert.ok(b.includes(c), `fn_quote_reprice does not set ${c}`);
  assert.match(b, /vat_amount = case when v_q\.vat_amount is not null and coalesce\(v_q\.quote_amount, 0\) > 0\s+then round\(v_q\.vat_amount \* p_amount \/ v_q\.quote_amount, 2\) end/);
  assert.match(b, /gross_amount = null, discount_amount = null, discount_label = null/);
  const src = readFileSync(SQL + winning('fn_quote_reprice'), 'utf8');
  assert.match(src, /revoke execute on function public\.fn_quote_reprice\(uuid, numeric\) from public, anon, authenticated;/);
});

// 15 Nov 2026 (accountant): the comparison now ranks on comparedPrice = feeBaseOf, which reads quote_amount (and price_ex_vat
// only to know a held VAT basis). fn_quote_reprice moves both columns together, so the customer still sees the new price.
test('the customer compares the fee base, comparedPrice (if this moves, the re-price must follow it)', () => {
  const src = readFileSync('supabase/functions/quote_compare/index.ts', 'utf8');
  assert.match(src, /price: comparedPrice\(q\)/);
  assert.match(readFileSync('supabase/functions/quote_compare/deterministic.ts', 'utf8'), /export const comparedPrice = \(q: PriceRow\): number \| null => feeBaseOf\(q\);/);
});
