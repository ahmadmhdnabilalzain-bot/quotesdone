// Customer Terms v10 and Supplier Agreement v15 (6 Oct 2026, ceo; founder rulings 1155, 1156 and the addendum
// "just make sure we are protected in all cases"). Fails if a later edit drops the intermediary/no-liability
// clauses, a carve-out the law forces, or the "a court refused it" condition on the supplier fallback cap -- or if
// the text cites an article of the REPEALED Civil Code (Federal Law 5/1985), whose "Art. 296" is now Art. 257 of
// Federal Decree-Law 25/2025. Basis: the research memo quoted in the PR (official texts read 6 Oct 2026).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const legal = JSON.parse(readFileSync(new URL('../../src/content/legal.json', import.meta.url), 'utf8'));
const text = (k, g) => legal[k][g].html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

const MUST = {
  terms: {
    en: [/not a party to that contract/, /Articles 252 and 265 of the Commercial Transactions Law/, /inaccurate, misleading or untrue/,
      /Your remedy for any of these matters lies against the Supplier/, /Article 334\(2\)/, /Article 257/, /Articles 21 and 24/,
      /Late notice does not bar the claim/, /This sub-clause does not apply to consumers/, /Entire agreement/, /Article 236/],
    ar: [/ولا تكون QuotesDone طرفًا فيه/, /المادتين 252 و265/, /مضللًا أو غير صحيح/, /ويكون رجوعك في هذه المسائل على المورّد/,
      /المادة 334\(2\)/, /المادة 257/, /المادتان 21 و24/, /ولا يُسقط الإخطار المتأخر المطالبة/, /ولا يسري هذا البند الفرعي على المستهلك/],
  },
  'supplier-agreement': {
    en: [/portal and introducer only/, /gives no warranty/, /Only if, and to the extent that, a competent court refuses to give effect to clause 18\(a\)/,
      /greater of \(i\) the fees .* and \(ii\) AED 5,000/, /shall indemnify QuotesDone/, /Article 334\(2\)/, /Article 257/, /Late notice does not bar the claim/],
    ar: [/بوابة ووسيط تعريف فقط/, /إذا رفضت محكمة مختصة إعمال البند 18\(أ\)/, /5,000 درهم إماراتي/, /يعوّض المورّد QuotesDone/, /المادة 334\(2\)/, /المادة 257/],
  },
};

for (const [k, langs] of Object.entries(MUST)) for (const [g, res] of Object.entries(langs)) {
  test(`${k}/${g} keeps the intermediary exclusions and the carve-outs the law forces`, () => {
    const t = text(k, g);
    for (const re of res) assert.match(t, re);
  });
}

test('no current document cites the repealed Civil Code numbering or a contractual shorter limitation period', () => {
  for (const k of ['terms', 'supplier-agreement']) for (const g of ['en', 'ar']) {
    const t = text(k, g);
    assert.doesNotMatch(t, /(Article|Art\.|المادة) ?296\b/, `${k}/${g}: Art. 296 is the repealed numbering (now Art. 257)`);
    assert.doesNotMatch(t, /(Article|Art\.) ?\d+[^.]{0,60}Federal Law No\.? 5 of 1985/, `${k}/${g}: cites an article of the repealed Civil Code`);
    // Civil Transactions Law Art. 443(1): an agreed period other than the legal one is void. The notice clause must never bar a claim.
    assert.doesNotMatch(t, /claim(s)? (is|are|shall be) (time-)?barred|shall be deemed waived if not/i, `${k}/${g}: a contractual bar on claims`);
  }
});

test('the checks above are not vacuous: the archived versions lack the new clauses', () => {
  assert.doesNotMatch(text('terms-v9', 'en'), /Your remedy for any of these matters lies against the Supplier/);
  assert.doesNotMatch(text('supplier-agreement-v14', 'en'), /refuses to give effect to clause 18\(a\)/);
});
