// RULINGS 1207 AND 1208 ON THE CUSTOMER'S DOCUMENTS (13 Oct 2026). A ZZ DEMO quotation with a discount and VAT:
//   - the quotation and the comparison print "AED 2,000, after discount AED 1,700" — the supplier's own figures;
//   - the supplier's VAT is printed as stated (AED 85; AED 1,785 with VAT), never the TRN;
//   - "Prices shown exclude VAT" is never printed beside a supplier price; "no VAT" appears only beside our fee;
//   - the fee basis line reads "Our fee: 3% of AED 1,700 = AED 51; no card fee, no VAT on our fee";
//   - the not-responsible clause is on both documents in English and Arabic;
//   - the comparison ranks on the after-discount ex-VAT price (the fee base), so a discounted quote ranks on 1,700.
// Both documents render to a PDF; with QD_DEMO_PDF_OUT=<dir> set the PDFs are written there (attached to the PR).
//   deno test --no-lock --node-modules-dir=auto -A supabase/functions/_shared/quote_documents_stated_price.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { compareDocument, quoteDocument, VAT_LINE, type Item } from './quote_documents.ts';
import { NOT_RESPONSIBLE } from './stated_price.ts';
import { deterministicCompare, rosterOf } from '../quote_compare/deterministic.ts';
import { renderPdf } from '../pdf_native/render.ts';
import * as F from './quote_documents.fixture.ts';

type Lang = 'en' | 'ar';
// The brand fonts from the repo's fixtures (as customer_api/arabic_documents.test.ts): no network, no project ref.
const BRAND = new URL('../pdf_native/fixtures/brand/', import.meta.url);
const fetchBytes = async (p: string) => /\.ttf$/.test(p) ? await Deno.readFile(new URL(p, BRAND)) : null;
// CI runs without --allow-env: the demo output directory is read only when env access is granted, else unset.
const demoOut = () => Deno.permissions.querySync({ name: 'env', variable: 'QD_DEMO_PDF_OUT' }).state === 'granted' ? Deno.env.get('QD_DEMO_PDF_OUT') : undefined;
const INQ = { id: 'zzd3m0dd-1207-4f00-9a00-000000001207', rfq_no: 'ZZ1207', category: 'gypsum', summary: 'ZZ DEMO: gypsum partition for an office in Business Bay, 20 sqm.', emirate: 'Dubai' };
const ITEMS: Item[] = [{ desc: 'Gypsum board partition, 12.5mm board, 75mm metal stud', qty: '20', unit: 'sqm', unit_price: 100, amount: 2000, specs: { board_thickness: '12.5 mm', stud: '75 mm metal' } }];
// The supplier stated: subtotal 2,000; special discount 15% (AED 300); net 1,700; VAT 5% AED 85; total 1,785.
const QUOTE = { id: 'zz-q-1207', quote_amount: 1700, price_ex_vat: 1700, gross_amount: 2000, discount_amount: 300, discount_label: 'Special discount 15%',
  vat_treatment: 'exclusive', vat_amount: 85, amount_as_stated: 1785, lead_time: '2 weeks', validity: '30 days', warranty: '12 months',
  payment_terms: '50% advance, 50% on completion', scope: 'Supply and install.', conditions: null, exclusions: 'Painting.', notes: 'Prices exclude 5% VAT; our TRN is 100123456700003.' };
const dates = (lang: Lang) => lang === 'ar' ? { date_ar: '13 أكتوبر 2026' } : { date: '13 October 2026' };

function quoteBody(lang: Lang, revealRate: number | null = 0.03) {
  return F.reasoned((arTexts) => quoteDocument({ quote: QUOTE, inquiry: INQ, items: ITEMS, letter: 'A', lang, ...dates(lang), arTexts, revealRate })).body;
}

Deno.test('the fee line prints the rate it is given (pricing_config) and no rate when none was read', () => {
  assertStringIncludes(JSON.stringify(quoteBody('en', 0.04)), 'Our fee: 4% of AED 1,700 = AED 68');
  const s = JSON.stringify(quoteBody('en', null));
  assert(!s.includes('Our fee: '), 'a fee figure was printed with no rate read');
  assertStringIncludes(s, 'No card fee, no VAT on our fee.');
});
function compareBody(lang: Lang) {
  const lab = [
    { quote_id: 'zz-q-1207', label: 'Supplier A', price: 1700, gross_amount: 2000, discount_amount: 300, vat_treatment: 'exclusive', vat_amount: 85, lead_time: '2 weeks', warranty: '12 months', payment_terms: '50/50', validity: '30 days', itemised: true, completeness: { score: 90, passed: true, missing_mandatory: 0 } },
    { quote_id: 'zz-q-1208', label: 'Supplier B', price: 1800, vat_treatment: 'not_registered', lead_time: '2 weeks', warranty: '12 months', payment_terms: '50/50', validity: '30 days', itemised: true, completeness: { score: 90, passed: true, missing_mandatory: 0 } },
  ];
  // deno-lint-ignore no-explicit-any
  const a: any = deterministicCompare(lab, lang); a.all_quotes = rosterOf(lab, a.top3); a.total_quotes = 2;
  return F.reasoned((arTexts) => compareDocument({ analysis: a, inquiry: INQ, lang, ...dates(lang), arTexts })).body;
}

for (const lang of ['en', 'ar'] as const) {
  Deno.test(`quotation (${lang}): the price, discount and VAT exactly as stated; fee basis; not responsible; renders`, async () => {
    const body = quoteBody(lang); const s = JSON.stringify(body);
    // deno-lint-ignore no-explicit-any
    const cover = (body.cover as any).figures[0][1];
    assertEquals(cover, lang === 'en' ? 'AED 2,000, after discount AED 1,700' : '2,000 درهم، وبعد الخصم 1,700 درهم');
    for (const w of lang === 'en'
      ? ['Price before discount, as stated', 'Special discount 15%', 'Total quoted after discount, excluding VAT', 'AED 1,700.00', 'VAT, as stated by the supplier', 'AED 85.00', 'AED 1,785.00', 'Our fee: 3% of AED 1,700 = AED 51; no card fee, no VAT on our fee.', NOT_RESPONSIBLE.en]
      : ['السعر قبل الخصم كما ذكره المورّد', 'إجمالي العرض بعد الخصم غير شامل الضريبة', '1,700.00 درهم', '85.00 درهم', '1,785.00 درهم', 'رسومنا 3% من 1,700 درهم = 51 درهم', NOT_RESPONSIBLE.ar]) assertStringIncludes(s, w);
    assert(!s.includes(VAT_LINE.en) && !s.includes(VAT_LINE.ar), 'the blanket ex-VAT line is printed beside a supplier price');
    assert(!s.includes('100123456700003'), 'the supplier TRN reached the page');
    const out = await renderPdf(body, { fetchBytes });
    assert(out.ok, JSON.stringify(!out.ok && out.body));
    const dir = demoOut();
    if (dir && out.ok) await Deno.writeFile(`${dir}/ZZDEMO-ruling-1207-quotation-${lang}.pdf`, out.bytes);
  });

  Deno.test(`comparison (${lang}): "after discount" in the table, VAT as stated, ranked on the fee base; renders`, async () => {
    const body = compareBody(lang); const s = JSON.stringify(body);
    assertStringIncludes(s, lang === 'en' ? 'AED 2,000, after discount AED 1,700' : '2,000 درهم، وبعد الخصم 1,700 درهم');
    assertStringIncludes(s, lang === 'en' ? '+ VAT AED 85 (AED 1,785 with VAT)' : '+ ضريبة 85 درهم (1,785 درهم شاملًا الضريبة)');
    assertStringIncludes(s, lang === 'en' ? 'Not VAT-registered' : 'غير مسجّل في الضريبة');
    assertStringIncludes(s, lang === 'en' ? NOT_RESPONSIBLE.en : NOT_RESPONSIBLE.ar);
    assertStringIncludes(s, lang === 'en' ? 'no card fee, no VAT on our fee' : 'بلا رسوم بطاقة ولا ضريبة قيمة مضافة على رسومنا');
    assert(!s.includes(VAT_LINE.en) && !s.includes(VAT_LINE.ar));
    const out = await renderPdf(body, { fetchBytes });
    assert(out.ok, JSON.stringify(!out.ok && out.body));
    const dir = demoOut();
    if (dir && out.ok) await Deno.writeFile(`${dir}/ZZDEMO-ruling-1207-comparison-${lang}.pdf`, out.bytes);
  });
}

Deno.test('the comparison ranks on the after-discount ex-VAT price: 1,700 (gross 2,000) is cheaper than 1,800', () => {
  // deno-lint-ignore no-explicit-any
  const a: any = deterministicCompare([
    { label: 'Supplier A', price: 1700, gross_amount: 2000, discount_amount: 300, completeness: { score: 90, passed: true, missing_mandatory: 0 } },
    { label: 'Supplier B', price: 1800, completeness: { score: 90, passed: true, missing_mandatory: 0 } },
  ], 'en');
  assertEquals(a.cheapest_label, 'Supplier A');
});
