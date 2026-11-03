// the_arabic_quotation_states_the_same_money.test.ts — the English and the Arabic quotation, rendered through
// the real builder and the real renderer, state the same figures in the same reading order. Seat: sales_engineer.
//
// 23 Sep 2026. The nightly (finding duty:journey:c customer audit:the_Arabic_quotation_states_the_same_money_as_the_English_one)
// read the English quotation as 2,963.00 118,520.00 118,520.00 118,500.00 | 118,520.00 118,500.00 and the Arabic one
// as ... | 118,500.00 118,520.00. The last two are the note "the line amounts add up to X; the quoted total is Y",
// which the Arabic page draws right to left, so a left-to-right extractor reads Y before X. The money was the same;
// the reader went the wrong way. This renders a quotation whose lines do not add up to its total (so that note is
// printed), reads both pages with the nightly's own reader (scripts/e2e/pdf_facts.mjs amountsInReadingOrder), and
// fails if the two languages' figures ever differ, or if the reader stops reading an Arabic line right to left.
// It also fails if the quotation builder formats money anywhere but money.ts (one formatter for both languages).
// No network, no database: fonts are the committed copies in fixtures/brand.
import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import { renderPdf } from './render.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import * as QD from '../_shared/quote_documents.ts';
import * as F from '../_shared/quote_documents.fixture.ts';
import { aed, aedRange, figure } from '../_shared/money.ts';
// @ts-ignore: a plain .mjs module shared with the nightly journey
import { amountsInReadingOrder, moneyVerdict, pdfFactsFromBytes } from '../../../scripts/e2e/pdf_facts.mjs';

type Lang = 'en' | 'ar';
const FONTS = new URL('./fixtures/brand/', import.meta.url);
const fetchBytes = async (p: string) => (/\.ttf$/.test(p) ? await Deno.readFile(new URL(p, FONTS)) : null);

const base = F.liveQuotes()[0];
// Priced lines (the nightly's quotation: 40 x 2,963.00 = 118,520.00) that do not add up to the quoted total,
// so the note naming both figures is printed: the case the nightly failed on.
const items = [{ desc: 'ZZ DEMO aluminium sliding window, Schuco AWS 70', qty: '40', unit: 'Nos', unit_price: 2963, amount: 118520 },
  { desc: 'ZZ DEMO removal of the existing units', qty: '1', unit: 'LS', unit_price: 1250.5, amount: 1250.5 }];
const sum = 118520 + 1250.5;
const TOTAL = 119750;
const quote = { ...base, items, quote_amount: TOTAL, price_ex_vat: TOTAL };

async function renderBytes(lang: Lang) {
  const doc = F.reasoned((arTexts) => QD.quoteDocument({ quote, inquiry: F.INQUIRY, items: quote.items, letter: QD.supplierLabel(0), lang, maskNames: F.identities(), arTexts,
    ...(lang === 'ar' ? { date_ar: '23 سبتمبر 2026' } : { date: '23 September 2026' }) }));
  const r = await renderPdf(doc.body, { fetchBytes });
  assert(r.ok, `refused: ${JSON.stringify((r as { body?: unknown }).body)}`);
  return (r as { bytes: Uint8Array }).bytes;
}
async function render(lang: Lang) {
  const pages = await pdfPages(await renderBytes(lang));
  return pages.flatMap((p, i) => p.runs.filter((x) => !x.vertical).map((x) => ({ text: x.text, page: i + 1, x: x.x, y: x.y, w: x.w })));
}

Deno.test('the Arabic quotation states the same money, in the same order, as the English one', async () => {
  const [en, ar] = [await render('en'), await render('ar')];
  const m = { en: amountsInReadingOrder(en, false, 0.003), ar: amountsInReadingOrder(ar, true, 0.003) };
  // The note with both figures is on both pages, so the case that failed is the case measured.
  for (const l of ['en', 'ar'] as Lang[]) {
    assert(m[l].includes(figure(sum, true)) && m[l].includes(figure(TOTAL, true)), `${l}: the subtotal/total note is missing: ${m[l].join(' ')}`);
  }
  assert(m.en.length >= 4, `too few figures read: ${m.en.join(' ')}`);
  assertEquals(m.ar, m.en, 'the Arabic quotation states different money from the English one');
  // The Arabic page really is right to left: read left to right, its figures come out in another order.
  assertNotEquals(amountsInReadingOrder(ar, false, 0.003), m.en, 'the Arabic figures read the same both ways: this no longer measures reading direction');
});

// 3 Nov 2026. The test above reads draw operations; the nightly reads pdfjs text ITEMS, and pdfjs joins the Arabic
// note into ONE item whose string is already in logical order (sum, then total) with x at the item's left edge.
// amountsInReadingOrder placed the figures by character index and then read them right to left, so it reported
// total-then-sum for a page whose sum sits to the right of its total (measured: the draw operations put the sum at
// x=0.752 and the total at x=0.546). The nightly failed on exactly that from 20 Oct. This reads the two real renders
// with the nightly's own extraction (pdfFactsFromBytes + moneyVerdict), so a reader that misorders them fails here.
Deno.test('the nightlys own reader finds the same money on both quotations', async () => {
  const [en, ar] = [await pdfFactsFromBytes(await renderBytes('en')), await pdfFactsFromBytes(await renderBytes('ar'))];
  const v = moneyVerdict(en, ar);
  assertEquals(v.status, 'PASS', v.why);
});

Deno.test('one money formatter: the two languages differ only in the unit', () => {
  assertEquals(aed(118520, 'en', true), 'AED 118,520.00');
  assertEquals(aed(118520, 'ar', true), '118,520.00 درهم');
  assertEquals(figure(0), '—');
  assertEquals(aedRange(90000, 112000, 'en'), 'AED 90,000–112,000');
  assertEquals(aedRange(124900.5, 130000, 'ar'), '124,900.50–130,000.00 درهم', 'a range drops no fils');
  const src = Deno.readTextFileSync(new URL('../_shared/quote_documents.ts', import.meta.url));
  assertEquals(src.match(/\.toLocaleString\(/g)?.length ?? 0, 0, 'quote_documents.ts formats a number itself; use money.ts');
});
