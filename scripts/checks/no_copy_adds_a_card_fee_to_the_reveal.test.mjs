// FOUNDER RULING, ledger 1087 (30 Sep 2026): the reveal fee is 3% of the selected quotation, nothing added
// for paying by card. A card surcharge is unlawful under Cabinet Resolution 66/2023 Art. 5(3); QuotesDone
// absorbs Stripe's fee. The product has charged 3% only since #919, and stripe_checkout refuses a non-zero
// card-fee line (card_surcharge_refused) - but on 30 Sep the home page still said "3% to reveal, plus the card
// fee", the sample reveal button "+ card fee", ServiceDoc "3% of it plus the card processing fee", and seat
// knowledge in five files told agents the card fee was "grossed up" onto the customer.
// company_facts_agree_everywhere reads only the surfaces company_facts.json lists, so none of it was caught.
//
// The wording rule is company_facts.json canonical_statements.no_card_fee.forbid (one source; the production
// probe `node scripts/legal/sync_company_facts.mjs --probe` reads the same rule against the knowledge tables and
// templates). This check widens WHERE it is read: every file a customer, a supplier or a seat can be shown text
// from - messages/, src/, knowledge/ and supabase/functions/. Signed legal versions are history: an old Supplier
// Agreement in src/content/legal.json is what a supplier accepted and is never rewritten, so legal.json is read
// for its CURRENT documents only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { wrongWordings, currentDocs } from '../legal/company_facts.mjs';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const TEXT = /\.(json|md|ts|tsx|mjs|js|html|sql)$/;
// company_facts.json names the forbidden wordings in order to refuse them; legal.json is read below by document.
const SKIP = new Set(['src/content/company_facts.json', 'src/content/legal.json']);

const surcharges = (text) => wrongWordings(String(text).replace(/\\n/g, ' ')).filter((w) => w.rule === 'no_card_fee').map((w) => w.text);

const walk = (dir, out = []) => {
  for (const n of readdirSync(join(ROOT, dir))) {
    const p = `${dir}/${n}`;
    if (n === 'node_modules' || n.startsWith('.')) continue;
    if (statSync(join(ROOT, p)).isDirectory()) walk(p, out);
    else if (TEXT.test(n) && !/\.test\.[mt]s$/.test(n) && !SKIP.has(p)) out.push(p);
  }
  return out;
};

test('the rule catches the wordings found on 30 Sep and lets "no card fee" through', () => {
  for (const bad of ['3% to reveal, plus the card fee', 'Reveal for AED 1,162.50 (3%) + card fee', 'card fees are grossed up',
    'Card-processing charges are added on top', '3% للكشف، مضافًا إليها رسوم البطاقة', 'اكشف (3%) + رسوم البطاقة',
    'وتُضاف رسوم معالجة البطاقة فوقها', 'بما في ذلك رسوم البطاقة المضافة'])
    assert.notEqual(surcharges(bad).length, 0, bad);
  for (const ok of ['3% of the selected quotation, nothing added for paying by card', 'No card fee, no VAT.', 'with no card fee on top',
    'Card fee — none: QuotesDone pays it', 'دون أي مبلغ إضافي على الدفع بالبطاقة', 'رسوم البطاقة — لا شيء: تتحمّلها QuotesDone',
    'وتتحمّل الشركة رسوم Stripe', 'تتحمّل QuotesDone رسوم Stripe'])
    assert.deepEqual(surcharges(ok), [], ok);
});

test('no customer-facing copy or seat knowledge adds a card fee to the reveal', () => {
  const bad = [];
  for (const p of ['messages', 'src', 'knowledge', 'supabase/functions'].flatMap((d) => walk(d)))
    for (const h of surcharges(readFileSync(join(ROOT, p), 'utf8'))) bad.push(`${p}: "${h}"`);
  const legal = JSON.parse(readFileSync(join(ROOT, 'src/content/legal.json'), 'utf8'));
  for (const k of currentDocs(legal)) for (const g of ['en', 'ar'])
    for (const h of surcharges(legal[k][g].html)) bad.push(`legal.json ${k}/${g}: "${h}"`);
  assert.deepEqual(bad, [], 'say "3% of the selected quotation, nothing added for paying by card" (ledger 1087)');
});
