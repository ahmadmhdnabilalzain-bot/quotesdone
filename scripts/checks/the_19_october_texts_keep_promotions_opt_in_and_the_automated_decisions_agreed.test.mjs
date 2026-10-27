// Customer Terms v11, Supplier Agreement v16, Privacy 1.7, Refund 1.9, Disclaimer 1.4 (ceo, 19 Oct 2026; legal risk
// review of 19 Oct 2026 and the founder's corrections of the same day). Fails if a later edit brings back an opt-out
// promotion, "legitimate interests", a decision by "the CEO", a promise of review by a person, continued use as
// acceptance, "conclusive" records, the card-fee leftovers, a second liability cap, or an "indicative" revealed quote.
// Article numbers were read on uaelegislation.gov.ae on 19 Oct 2026 (PDPL Arts 4 and 18(2); CTL Art. 92).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const legal = JSON.parse(readFileSync(new URL('../../src/content/legal.json', import.meta.url), 'utf8'));
const text = (k, g) => legal[k][g].html.replace(/<[^>]+>/g, ' ').replace(/&#39;/g, "'").replace(/\s+/g, ' ');
const CURRENT = ['terms', 'supplier-agreement', 'privacy', 'refund-policy', 'disclaimer'];

const MUST = {
  terms: { en: [/only if you tick the separate box to agree, promotional communications/, /Article 18\(2\)\(a\) and \(c\)/, /expressly agree to that processing/, /Federal Decree-Law No\. 14 of 2023/, /Ticking the acceptance box constitutes/],
           ar: [/المربع المستقل المخصص للموافقة/, /الفقرة 2 من المادة 18/, /توافق صراحةً على تلك المعالجة/, /رقم 14 لسنة 2023/] },
  'supplier-agreement': { en: [/only after the Supplier has expressly accepted it/, /only with the Supplier's prior written consent/, /Article 18\(2\)\(a\) and \(c\)/, /Federal Decree-Law No\. 14 of 2023/],
                          ar: [/إلا بعد أن يقبلها صراحةً/, /بموافقة كتابية مسبقة منه/, /الفقرة 2 من المادة 18/] },
  privacy: { en: [/does not provide a general "legitimate interests" ground/, /Article 92 of the Commercial Transactions Law/, /available and known to all by an act of its owner/], ar: [/المادة 92 من قانون المعاملات التجارية/, /متاحة ومعروفة للكافة بفعل صاحبها/] },
  'refund-policy': { en: [/The Reveal Fee is the total you pay/], ar: [/رسوم الكشف هي المبلغ الإجمالي الذي تدفعه/] },
  disclaimer: { en: [/bound by its revealed quotation/, /limited as set out in clause 9 of the Terms of Service/], ar: [/يلتزم المورّد بعرض السعر الذي كُشف عنه/, /البند 9 من شروط الخدمة/] },
};
for (const [k, langs] of Object.entries(MUST)) for (const [g, res] of Object.entries(langs)) {
  test(`${k}/${g} keeps the 19 October clauses`, () => { const t = text(k, g); for (const re of res) assert.match(t, re); });
}

test('no current document keeps a ruled-out wording', () => {
  const NEVER = { en: [/unless you opt out|unless opted out|unless the Supplier opts out/i, /legitimate (business )?interests?\)/i, /QuotesDone's CEO|the CEO's/, /\bhuman\b/i,
    /reconsidered by a person/, /continu(ed|ing) (to )?use[^.]{0,80}(constitutes|acceptance)/i, /conclusive evidence/, /Both amounts|no VAT is charged on either/, /Quotations provided through the Platform are indicative only/, /role address/i],
    ar: [/ما لم تقم بإلغاء الاشتراك|ما لم ينسحب/, /الرئيس التنفيذي/, /من قِبل شخص/, /دليلًا قاطعًا/, /أيٍّ منهما/] };
  for (const k of CURRENT) for (const g of ['en', 'ar']) for (const re of NEVER[g]) assert.doesNotMatch(text(k, g), re, `${k}/${g}: ${re}`);
});

test('the checks above are not vacuous: the archived versions carry the old wording', () => {
  assert.match(text('terms-v10', 'en'), /unless you opt out/);
  assert.match(text('supplier-agreement-v15', 'en'), /unless the Supplier opts out/);
});
