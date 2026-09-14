// quote_documents.test.ts — the quotation and the comparison report, in English AND Arabic.
// deno test --no-lock supabase/functions/_shared/quote_documents.test.ts
//
// Built from the ZZ DEMO fixture (seven HVAC quotes, one incomplete, one draft) and rendered by the
// real renderer. Each document must: render to a PDF that loads back; carry the strings a customer
// relies on; carry NO supplier identity (name, email, phone, website) before the reveal; and never
// claim only three quotes came in when seven did.
//
// No permissions are granted by run.mjs, so the brand fonts cannot be fetched here and the renderer
// falls back to Helvetica — which cannot draw Arabic. The Arabic assertions therefore run on the
// document CONTENT (what the page is told to say); the glyph assertion runs whenever the fonts are
// reachable (`deno test --allow-net`), and the sample renderer in the PR proves the Arabic pages.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1';
import { quoteDocument, compareDocument, arDuration, arPayment, arUnit, maskContacts, supplierLabel } from './quote_documents.ts';
import { footerLines, FALLBACK } from './doc_template.ts';
import { deterministicCompare, rosterOf } from '../quote_compare/deterministic.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { INQUIRY, liveQuotes, labelled, identities } from './quote_documents.fixture.ts';

const BRAND = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/';
async function fetchBytes(p: string) { try { const r = await fetch(BRAND + p); return r.ok ? new Uint8Array(await r.arrayBuffer()) : null; } catch { return null; } }

function analysisFor(lang: 'en' | 'ar') {
  const lab = labelled();
  // deno-lint-ignore no-explicit-any
  const a: any = deterministicCompare(lab, lang);
  a.all_quotes = rosterOf(lab, a.top3);
  a.total_quotes = lab.length;
  return a;
}
function quoteBody(letterIdx: number, lang: 'en' | 'ar') {
  const q = liveQuotes()[letterIdx];
  return quoteDocument({ quote: q, inquiry: INQUIRY, items: q.items, letter: supplierLabel(letterIdx), lang, maskNames: [q.supplier.company_name, q.supplier.email, q.supplier.phone, q.supplier.website], ...(lang === 'ar' ? { date_ar: '14 سبتمبر 2026' } : { date: '14 September 2026' }) }).body;
}
function compareBody(lang: 'en' | 'ar') {
  return compareDocument({ analysis: analysisFor(lang), inquiry: INQUIRY, lang, maskNames: identities(), portalUrl: 'https://quotesdone.com/me', ...(lang === 'ar' ? { date_ar: '14 سبتمبر 2026' } : { date: '14 September 2026' }) }).body;
}
function assertNoIdentity(body: unknown) {
  const s = JSON.stringify(body);
  for (const id of identities()) assert(!s.includes(id), 'supplier identity reached the page: ' + id);
  assert(!/ZZ DEMO/i.test(s), 'a ZZ DEMO supplier name reached the page');
  assert(!/example\.invalid/i.test(s), 'a supplier email or website reached the page');
  assert(!/\+?971[\s-]?50[\s-]?000/.test(s), 'a supplier phone number reached the page');
}
async function assertRenders(body: Record<string, unknown>, lang: 'en' | 'ar') {
  const out = await renderPdf(body, { fetchBytes });
  assert(out.ok, 'renderer refused: ' + JSON.stringify(!out.ok && out.body));
  if (!out.ok) return;
  assertEquals(new TextDecoder().decode(out.bytes.slice(0, 5)), '%PDF-');
  const doc = await PDFDocument.load(out.bytes);
  assertEquals(doc.getPageCount(), out.meta.pages);
  assert(out.meta.pages >= 1);
  if (lang === 'en') assertEquals(out.meta.glyphs_dropped, 0, 'an English document lost characters: ' + JSON.stringify(out.meta.glyphs_dropped_sample));
  if (lang === 'ar' && out.meta.fonts.arabic) assertEquals(out.meta.glyphs_dropped, 0, 'the Arabic font is embedded yet characters were dropped');
  return out.meta;
}

Deno.test('the legal footer names the company, the DET licence and the TDRA permit', () => {
  const [l1, l2] = footerLines(FALLBACK);
  assertStringIncludes(l1, 'QuotesDone Technologies');
  assertStringIncludes(l1, '1633275');
  assertStringIncludes(l1, 'TDRA NOL-26-100000665');
  assertStringIncludes(l2, 'quotesdone.com');
});

Deno.test('labels: drafts take no letter, the incomplete quote sorts last, seven live quotes', () => {
  const lab = labelled();
  assertEquals(lab.length, 7);
  assertEquals(lab.map((l) => l.label), ['A', 'B', 'C', 'D', 'E', 'F', 'G'].map((x) => 'Supplier ' + x));
  assertEquals(lab[0].price, 78900);
  assertEquals(lab[6].price, null);
});

Deno.test('roster: every quote listed, three shortlisted, the incomplete one held', () => {
  const a = analysisFor('en');
  assertEquals(a.all_quotes.length, 7);
  // deno-lint-ignore no-explicit-any
  const by = (s: string) => a.all_quotes.filter((r: any) => r.status === s);
  assertEquals(by('shortlisted').length, 3);
  assertEquals(by('held').map((r: { label: string }) => r.label), ['Supplier G']);
  assertEquals(by('received').length, 3);
});

Deno.test('Arabic, deterministically: durations, payment terms, units', () => {
  assertEquals(arDuration('2 weeks'), 'أسبوعان');
  assertEquals(arDuration('12 months'), '12 شهرًا');
  assertEquals(arDuration('3 weeks'), '3 أسابيع');
  assertEquals(arDuration('10-14 days'), '10–14 يومًا');
  assertEquals(arDuration('3 working days'), '3 أيام عمل');
  assertEquals(arDuration('1 year'), 'سنة واحدة');
  assertEquals(arDuration('ASAP'), 'فوري');
  assertEquals(arDuration('after the site visit'), null);
  assertEquals(arPayment('50% advance, 50% on completion'), '50% دفعة مقدّمة، 50% عند الإنجاز');
  assertEquals(arPayment('100% advance'), '100% دفعة مقدّمة');
  // Not every part recognised → not translated at all, never half-translated.
  assertEquals(arPayment('LC at sight'), null);
  assertEquals(arPayment('50% advance, balance by LC'), null);
  assertEquals(arUnit('Nos'), 'عدد');
  assertEquals(arUnit('LM'), 'م.ط');
  assertEquals(arUnit('furlong'), null);
});

Deno.test('contacts are masked in supplier free text', () => {
  const s = maskContacts('Call ZZ DEMO Cool Air on +971 50 000 0001, 050 000 0001 or sales1@zzdemo-1.example.invalid / www.zzdemo-1.example.invalid', ['ZZ DEMO Cool Air LLC']);
  assert(!/ZZ DEMO|000 0001|example\.invalid/i.test(s), s);
  // Quantities and model numbers are not phone numbers.
  assertEquals(maskContacts('24 TR, 120 LM, model FDYQ180LA'), '24 TR, 120 LM, model FDYQ180LA');
});

Deno.test('quotation (EN): the right quote, its figures, no identity, renders', async () => {
  const body = quoteBody(0, 'en');
  const s = JSON.stringify(body);
  assertStringIncludes(s, '"supplier_label":"A"');
  assertStringIncludes(s, 'QD-ZZD3M0AA-A');
  assertStringIncludes(s, '78900');
  assertStringIncludes(s, 'Gree ducted split unit 5 TR');
  assertStringIncludes(s, '50% advance, 50% on completion');
  assert(!/[؀-ۿ]/.test(JSON.stringify((body as { quote: unknown }).quote)), 'Arabic in the English quotation');
  assertStringIncludes(s, '"letterhead":true');
  assertNoIdentity(body);
  await assertRenders(body, 'en');
});

Deno.test('quotation (AR): translated terms, supplier text kept and declared, no identity, renders', async () => {
  const body = quoteBody(0, 'ar');
  // deno-lint-ignore no-explicit-any
  const q = (body as any).quote;
  assertEquals(body.lang, 'ar');
  assertEquals(q.lead_time, 'أسبوعان');
  assertEquals(q.warranty, '12 شهرًا');
  assertEquals(q.validity, '30 يومًا');
  assertEquals(q.payment_terms, '50% دفعة مقدّمة، 50% عند الإنجاز');
  assertEquals(q.emirate, 'دبي');
  assertEquals(q.job_category, 'التكييف والتبريد (HVAC)');
  assertEquals(q.items[0].unit, 'عدد');
  assertStringIncludes(q.source_note, 'دون ترجمة');
  assertEquals(q.total, 78900);
  assertNoIdentity(body);
  await assertRenders(body, 'ar');
});

for (const lang of ['en', 'ar'] as const) {
  Deno.test(`comparison report (${lang.toUpperCase()}): top 3, all seven listed, the held quote explained, no identity, renders`, async () => {
    const body = compareBody(lang);
    const s = JSON.stringify(body);
    if (lang === 'en') {
      assertStringIncludes(s, 'Quote comparison report');
      assertStringIncludes(s, 'All quotes received (7)');
      assertStringIncludes(s, '3 of 7');
      assertStringIncludes(s, 'Shortlisted #1');
      assertStringIncludes(s, 'Supplier G is on hold');
      assertStringIncludes(s, 'Recommended');
    } else {
      assertStringIncludes(s, 'تقرير مقارنة العروض');
      assertStringIncludes(s, 'جميع العروض المستلمة (7)');
      assertStringIncludes(s, '3 من 7');
      assertStringIncludes(s, 'المورّد G معلّق');
      assertStringIncludes(s, 'التوصية');
      assert(!s.includes('"Supplier '), 'an untranslated supplier label on the Arabic report');
    }
    // "Only three quotes" must never be said about a request that received seven.
    assert(!/only (3|three) quotes/i.test(s));
    if (lang === 'en') {
      assertStringIncludes(s, 'All 7 quotes are listed in this report; the top 3 are compared in detail.');
      assertStringIncludes(s, 'You can choose any of them');
      assertStringIncludes(s, 'Specifications are not assessed');
    } else {
      assertStringIncludes(s, 'جميع العروض الـ7 مدرجة في هذا التقرير');
      assertStringIncludes(s, 'يمكنك اختيار أي منها');
    }
    // A customer never reads that something of ours is unavailable, and a rules ranking never
    // claims to have matched the specification.
    assert(!/AI adviser|unavailable|المساعد الذكي|غير متاح|strongest \d+ are shown|وعرضت أفضل|من حيث المواصفات/i.test(s), 'internal-failure or spec-match wording reached the report');
    // The method line is said once, not repeated as a "Watch out" bullet.
    assertEquals((s.match(lang === 'en' ? /Specifications are not assessed/g : /لم تُقيَّم المواصفات/g) || []).length, 1);
    assertNoIdentity(body);
    await assertRenders(body, lang);
  });
}
