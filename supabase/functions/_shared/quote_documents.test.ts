// quote_documents.test.ts — the quotation and the comparison report, in English AND Arabic.
// deno test --no-lock supabase/functions/_shared/quote_documents.test.ts
//
// Built from the ZZ DEMO fixtures (HVAC: seven quotes, one incomplete, one draft; FIT-OUT joinery:
// five quotes with material specs, one held for a missing thickness) and rendered by the real
// renderer. Each document must: render to a PDF that loads back; carry its sections, its legal
// footer and its document-control line; carry NO supplier identity before the reveal; carry no VAT
// detail and no TRN; never say "AI" or "assistant"; and — in Arabic — carry no English word in its
// primary text except brands, standards and codes. A person's words reach an Arabic page only as their
// REASONED Arabic (mocked here by F.reasoned; decision point trade_glossary_ar), never substituted and never
// half-translated: a page built without it reports them in `untranslated`. The comparison report must list every quote,
// show a held quote as on hold with none of its details, and never make it a technical column.
//
// No permissions are granted by run.mjs, so the brand fonts cannot be fetched here and the renderer
// falls back to Helvetica — which cannot draw Arabic. The Arabic assertions therefore run on the
// document CONTENT (what the page is told to say); the glyph assertion runs whenever the fonts are
// reachable (`deno test --allow-net`), and the sample renderer in the PR proves the Arabic pages.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { PDFDocument, PDFDict, PDFName } from 'https://esm.sh/pdf-lib@1.17.1';
import { DOC_VERSION, quoteDocument, compareDocument, compareTable, inquiryDocument, jobNoOf, quoteRef, arDuration, arUnit, maskContacts, supplierLabel, stripVat, VAT_LINE, VAT_RE, labelFor, toCsv, type Item } from './quote_documents.ts';
import { footerLines, footerLinesAr, FALLBACK } from './doc_template.ts';
import { deterministicCompare, rosterOf } from '../quote_compare/deterministic.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { pdfPages } from './pdf_text_positions.ts';
import { portalLink } from './site_origins.ts';
import { latinLeaks } from './trade_glossary_ar.test.ts';
import * as F from './quote_documents.fixture.ts';
import { technicalComparison, rendererView } from './line_specs/compare.ts';

// FIXED LABELS ARE ARABIC. A fixed label is what the page itself names: a table's column heads, each
// row's first cell, a key in a key-value block, a section or sub-heading. Supplier free text is not a
// fixed label; it is printed as its reasoned Arabic.
// Measured 14 Sep 2026: a request whose material carried only its key ({component:'glass'}) printed
// "المادة — glass" as a row label in the Arabic comparison.
const cellStr = (c: unknown) => typeof c === 'string' ? c : (c && typeof c === 'object' && 'text' in c) ? String((c as { text: unknown }).text ?? '') : '';
function fixedLabels(body: { blocks?: unknown[] }): string[] {
  const out: string[] = [];
  // deno-lint-ignore no-explicit-any
  for (const b of (body.blocks || []) as any[]) {
    if (b.t === 'table') { out.push(...(b.head || []).map(cellStr)); for (const r of b.rows || []) out.push(cellStr(r[0])); }
    else if (b.t === 'kv') for (const p of b.pairs || []) out.push(cellStr(p[0]));
    else if (b.t === 'section' || b.t === 'h3') out.push(cellStr(b));
  }
  return out.filter(Boolean);
}
Deno.test('every fixed label in the Arabic comparison is Arabic, a material named only by its key included', () => {
  const terms = { lead_time: '21 days', warranty: '2 years — materials and workmanship', scope: 'Supply and install', exclusions: null, conditions: null, notes: null, terms_spec: null, price_ex_vat: 118500 };
  // The line does NOT name the glass: that is the case that printed the bare key (a line naming it
  // maps to the trade's own glass attributes, which were always Arabic).
  const line = { line_no: 1, description: 'Aluminium windows supply and install', qty: 40, unit: 'nos', unit_price: 2962, amount: 118500 };
  const q = (id: string, letter: string, price: number) => ({ quote_id: id, label_en: `Supplier ${letter}`, label_ar: `المورّد ${letter}`, supplier_letter: letter, option_no: 0, lines: [line], terms: { ...terms, price_ex_vat: price } });
  // The REQUEST line names the glass (compare.ts adds a customer's component to the lines that name it).
  const tech = technicalComparison({ category: 'aluminium', request_lines: [{ line_no: 1, description: 'Aluminium windows, double glazed glass', qty: 40, unit: 'nos' }],
    requirements: { materials: [{ component: 'glass', choice: 'double' }] } as never, on_hold: 0, now: new Date('2026-09-14'),
    quotes: [q('q1', 'A', 118500), q('q2', 'B', 124900)] as never });
  const a = { quotes: [{ label: 'Supplier A', price: 118500 }, { label: 'Supplier B', price: 124900 }],
    all_quotes: [{ label: 'Supplier A', quote_id: 'q1', price: 118500, status: 'shortlisted' }, { label: 'Supplier B', quote_id: 'q2', price: 124900, status: 'shortlisted' }],
    top3: [], technical: rendererView(tech, 'ar'), technical_detail: tech, total_quotes: 2 };
  const { body } = F.reasoned((arTexts) => compareDocument({ analysis: a, inquiry: { ...F.INQUIRY, category: 'aluminium' }, lang: 'ar', ...dates('ar') , arTexts }));
  const labels = fixedLabels(body as { blocks?: unknown[] });
  assert(labels.some((l) => l.includes('الزجاج')), 'the glass requirement never reached a row label: ' + JSON.stringify(labels.filter((l) => l.includes('المادة'))));
  assertEquals(labels.flatMap((s) => latinLeaks(s).map((w) => `${w}  ←  ${s}`)), [], 'English in a fixed Arabic label');
});

// Measured 14 Sep 2026 on the e2e harness's comparison (journey c): the commercial table and the CSV
// clipped "Supplier A – Option 1" to "Supplier A – Option…", and the Arabic report kept "Option".
Deno.test('two options of one supplier keep two distinct names, in English and in Arabic', () => {
  assertEquals(labelFor('Supplier A – Option 2', 'ar'), 'المورّد A – الخيار 2');
  const a = { quotes: [{ label: 'Supplier A – Option 1', price: 118500 }, { label: 'Supplier A – Option 2', price: 124900 }], all_quotes: [] };
  assertEquals(compareTable(a, false)!.head.slice(1), ['Supplier A – Option 1', 'Supplier A – Option 2']);
  assertEquals(compareTable(a, true)!.head.slice(1), ['المورّد A – الخيار 1', 'المورّد A – الخيار 2']);
});
Deno.test('compare_csv escapes every spreadsheet formula trigger, tab and carriage return included', () => {
  const csv = toCsv(['h'], [['=1+1'], ['\t=2'], ['\r=3'], ['@a'], ['+b'], ['plain']]);
  assertStringIncludes(csv, "'=1+1");
  assertStringIncludes(csv, "'\t=2");
  assertStringIncludes(csv, "\"'\r=3\"");
  assertStringIncludes(csv, "'@a");
  assertStringIncludes(csv, "\r\nplain\r\n");
});
Deno.test('a lead time counted from the order reads in Arabic', () => {
  assert(arDuration('21 days'));
  assertEquals(arDuration('21 days from order'), arDuration('21 days') + ' من تاريخ الطلب');
  assertEquals(arDuration('4 weeks after approval'), arDuration('4 weeks') + ' من الاعتماد');
  assertEquals(arDuration('21 days from the moon'), null);
});

const BRAND = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/';
async function fetchBytes(p: string) { try { const r = await fetch(BRAND + p); return r.ok ? new Uint8Array(await r.arrayBuffer()) : null; } catch { return null; } }
type Lang = 'en' | 'ar';
const dates = (lang: Lang) => lang === 'ar' ? { date_ar: '14 سبتمبر 2026' } : { date: '14 September 2026' };

const CASES = {
  hvac: { inq: F.INQUIRY, live: F.liveQuotes, lab: F.labelled, ids: F.identities, tech: () => F.HVAC_TECHNICAL, n: 7, held: 'Supplier G' },
  fitout: { inq: F.FITOUT_INQUIRY, live: F.fitoutLive, lab: F.fitoutLabelled, ids: F.fitoutIdentities, tech: F.fitoutTechnical, n: 5, held: 'Supplier B' },
};
type CaseKey = keyof typeof CASES;
function analysisFor(c: CaseKey, lang: Lang, withTech = true) {
  const C = CASES[c]; const lab = C.lab();
  // deno-lint-ignore no-explicit-any
  const a: any = deterministicCompare(lab, lang);
  a.all_quotes = rosterOf(lab, a.top3);
  a.total_quotes = lab.length;
  if (withTech) a.technical = C.tech();
  return a;
}
function quoteBody(c: CaseKey, lang: Lang, idx = 0) {
  const C = CASES[c]; const q = C.live()[idx];
  return F.reasoned((arTexts) => quoteDocument({ quote: q, inquiry: C.inq, items: q.items, letter: supplierLabel(idx), lang, maskNames: C.ids(), requestUrl: portalLink(lang, C.inq.id, q.id), ...dates(lang) , arTexts })).body;
}
function compareBody(c: CaseKey, lang: Lang, withTech = true) {
  const C = CASES[c];
  return F.reasoned((arTexts) => compareDocument({ analysis: analysisFor(c, lang, withTech), inquiry: C.inq, lang, maskNames: C.ids(), portalUrl: portalLink(lang, C.inq.id), linkFor: (qid: string) => portalLink(lang, C.inq.id, qid), ...dates(lang) , arTexts })).body;
}
// BEFORE THE REVEAL THE CUSTOMER CANNOT REACH A SUPPLIER (founder, 14 Sep 2026): QuotesDone holds an
// incomplete quote and the sales engineer asks the supplier through customer_support. So no document
// the customer receives may tell them to ask, contact or confirm something with a supplier. Measured
// 14 Sep 2026: the comparison said "not stated — ask for it" / "اطلبها", the quotation said "Confirm
// the difference with the supplier", and the analysis said "ask the supplier to reconfirm it".
const TELLS_CUSTOMER_TO_ASK = /\bask (for it|them|the supplier)\b|\b(contact|call|email|message) the supplier\b|\bconfirm\b[^.]{0,60}\bwith the supplier\b|\bconfirm before (you pay|paying)\b|اطلبها|اطلبه\b|اسأل المورّ?د|تواصل مع المورّ?د|اتصل بالمورّ?د|مع المورّ?د قبل الدفع|تأكيد[^.]{0,40}مع المورّ?د|أكّد قبل الدفع/i;
Deno.test('no document the customer receives tells them to ask or contact a supplier before the reveal', () => {
  for (const c of Object.keys(CASES) as CaseKey[]) for (const lang of ['en', 'ar'] as Lang[]) {
    const docs: Array<[string, unknown]> = [['comparison', compareBody(c, lang)], ['comparison without the technical section', compareBody(c, lang, false)]];
    for (let i = 0; i < CASES[c].live().length; i++) docs.push([`quotation ${i}`, quoteBody(c, lang, i)]);
    for (const [name, body] of docs) {
      const hit = JSON.stringify(body).match(TELLS_CUSTOMER_TO_ASK);
      assertEquals(hit?.[0] ?? null, null, `${c} ${lang} ${name} tells the customer to ask a supplier`);
    }
  }
  // The pattern itself catches the wording that shipped before this change.
  for (const s of ['Line 1 (x): glass not stated — ask for it.', 'البند 1: غير مذكورة — اطلبها.', 'Confirm the difference with the supplier.', 'This quote has expired — ask the supplier to reconfirm it.', 'Warranty not stated — confirm before paying.', 'أكّد قبل الدفع'])
    assert(TELLS_CUSTOMER_TO_ASK.test(s), 'the guard misses: ' + s);
});

// State (c) on the page: an optional detail one supplier left out is SHOWN as "Not stated (optional)",
// in both languages, and is never turned into a risk line (it is not chased).
Deno.test('an optional detail left out is shown as not stated (optional) and never listed as a risk', () => {
  const terms = { lead_time: '21 days', warranty: '2 years on workmanship', scope: 'Supply and installation of wardrobes by our team', exclusions: null, conditions: null, notes: null, terms_spec: null, price_ex_vat: 6000 };
  const q = (id: string, letter: string, desc: string, price: number) => ({ quote_id: id, label_en: `Supplier ${letter}`, label_ar: `المورّد ${letter}`, supplier_letter: letter, option_no: 0, lines: [{ line_no: 1, description: desc, amount: price }], terms: { ...terms, price_ex_vat: price } });
  const tech = technicalComparison({ category: 'joinery', request_lines: [{ line_no: 1, description: 'Wardrobe 18mm MDF HPL finish', qty: 4, unit: 'nos' }], requirements: null as never, on_hold: 0, now: new Date('2026-09-14'),
    quotes: [q('q1', 'A', 'Wardrobes 18mm MR MDF, HPL finish, 2mm PVC edge banding', 6000), q('q2', 'B', 'Wardrobes 18mm MR MDF, HPL finish', 5500)] as never });
  for (const lang of ['en', 'ar'] as Lang[]) {
    const a = { quotes: [{ label: 'Supplier A', price: 6000 }, { label: 'Supplier B', price: 5500 }],
      all_quotes: [{ label: 'Supplier A', quote_id: 'q1', price: 6000, status: 'shortlisted' }, { label: 'Supplier B', quote_id: 'q2', price: 5500, status: 'shortlisted' }],
      top3: [], technical: rendererView(tech, lang), technical_detail: tech, total_quotes: 2 };
    const s = JSON.stringify(F.reasoned((arTexts) => compareDocument({ analysis: a, inquiry: { ...F.INQUIRY, category: 'joinery' }, lang, ...dates(lang) , arTexts })).body);
    assertStringIncludes(s, lang === 'ar' ? 'غير مذكورة (اختيارية)' : 'Not stated (optional)');
    assert(!/edge band[^"]{0,40}not stated|شريط الحافة[^"]{0,40}غير مذكورة —/i.test(s), `${lang}: an optional gap became a risk line`);
  }
});

function assertNoIdentity(body: unknown, c: CaseKey) {
  const s = JSON.stringify(body);
  for (const id of CASES[c].ids()) assert(!s.includes(id), 'supplier identity reached the page: ' + id);
  assert(!/ZZ DEMO/i.test(s), 'a ZZ DEMO supplier name reached the page');
  assert(!/example\.invalid/i.test(s), 'a supplier email or website reached the page');
  assert(!/\+?971[\s-]?50[\s-]?000/.test(s), 'a supplier phone number reached the page');
}
// VAT: the one neutral line is the only mention; no rate, amount or TRN anywhere, in either language.
function assertNoVat(body: unknown, lang: Lang) {
  const s = JSON.stringify(body);
  assertStringIncludes(s, lang === 'ar' ? VAT_LINE.ar : VAT_LINE.en);
  const rest = s.split(VAT_LINE.en).join('').split(VAT_LINE.ar).join('');
  assert(!VAT_RE.test(rest), 'a VAT or TRN detail reached the customer page: ' + (rest.match(VAT_RE) || [])[0]);
  assert(!/100123456700003/.test(s), 'the supplier TRN reached the page');
}
function assertNoMachinery(body: unknown) {
  const s = JSON.stringify(body);
  assert(!/\bAI\b|assistant|artificial intelligence|الذكاء الاصطناعي|المساعد|AI adviser|unavailable|غير متاح/i.test(s), 'AI / assistant / unavailable wording reached the page');
}
// Every string the Arabic page draws as PRIMARY text (not the "original wording" line, not a link).
const SKIP = new Set(['sub', 'link', 't', 'tone', 'flag', 'lang', 'name', 'ref', 'align', 'options', 'widths', 'fs', 'zebra', 'n', 'size', 'muted', 'bold', 'group', 'cols', 'rank', 'scores', 'overall']);
function primary(v: unknown, key = ''): string[] {
  if (SKIP.has(key)) return [];
  if (typeof v === 'string') return /^(match|differs|missing|optional|na|short|open|hold)$/.test(v) ? [] : [v];
  if (Array.isArray(v)) return v.flatMap((x) => primary(x));
  if (v && typeof v === 'object') return Object.entries(v).flatMap(([k, x]) => primary(x, k));
  return [];
}
function assertFullyArabic(body: Record<string, unknown>) {
  const leaks = primary({ cover: body.cover, blocks: body.blocks, control: body.control, title: body.title }).flatMap((s) => latinLeaks(s).map((w) => `${w}  ←  ${s.slice(0, 90)}`));
  assertEquals(leaks, [], 'English left in the Arabic primary text');
  // The supplier's own words appear only on the labelled secondary line.
  const subs: string[] = [];
  const walk = (v: unknown) => { if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) { if (k === 'sub' && typeof x === 'string') subs.push(x); else walk(x); } };
  walk(body.blocks);
  for (const s of subs) assert(s.startsWith('النص الأصلي من المورد'), 'an unlabelled secondary line: ' + s);
}
async function assertRenders(body: Record<string, unknown>, lang: Lang) {
  const out = await renderPdf(body, { fetchBytes });
  assert(out.ok, 'renderer refused: ' + JSON.stringify(!out.ok && out.body));
  if (!out.ok) return;
  assertEquals(new TextDecoder().decode(out.bytes.slice(0, 5)), '%PDF-');
  const doc = await PDFDocument.load(out.bytes);
  assertEquals(doc.getPageCount(), out.meta.pages);
  assert(out.meta.pages >= 1);
  if (lang === 'en') assertEquals(out.meta.glyphs_dropped, 0, 'an English document lost characters: ' + JSON.stringify(out.meta.glyphs_dropped_sample));
  if (lang === 'ar' && out.meta.fonts.arabic) assertEquals(out.meta.glyphs_dropped, 0, 'the Arabic font is embedded yet characters were dropped');
  return out;
}
// Every URI link annotation in a rendered PDF, read back out of the file itself.
async function linksIn(bytes: Uint8Array): Promise<string[]> {
  const doc = await PDFDocument.load(bytes);
  const out: string[] = [];
  for (const p of doc.getPages()) {
    const annots = p.node.Annots();
    if (!annots) continue;
    for (let i = 0; i < annots.size(); i++) {
      const act = annots.lookup(i, PDFDict).lookupMaybe(PDFName.of('A'), PDFDict);
      // deno-lint-ignore no-explicit-any
      const uri: any = act?.get(PDFName.of('URI'));
      if (uri) out.push(uri.decodeText());
    }
  }
  return out;
}
// The deep link format as a literal: src/lib/portalLink.test.mjs expects the same one.
const deep = (c: CaseKey, lang: Lang, qid: string) => `https://quotesdone.com${lang === 'ar' ? '/ar' : ''}/me?request=${CASES[c].inq.id}&quote=${qid}`;
// deno-lint-ignore no-explicit-any
const blocksOf = (body: any, t: string) => (body.blocks as any[]).filter((b) => b.t === t);
// deno-lint-ignore no-explicit-any
const cellText = (c: any) => typeof c === 'string' ? c : String(c?.text ?? '');

Deno.test('the legal footer names the company, the DET licence and the TDRA permit, in both languages', () => {
  const [l1, l2] = footerLines(FALLBACK);
  assertStringIncludes(l1, 'QuotesDone Technologies'); assertStringIncludes(l1, '1633275'); assertStringIncludes(l1, 'TDRA NOL-26-100000665');
  // 21 Sep 2026 (customer audit, finding 12): the TDRA-permitted host, and the one address the site
  // publishes (src/content/company.json + legal.json, measured 21 Sep 2026). Never quotesdone.com.
  assertEquals(l2.split(' · ').pop(), 'quotesdone.ae'); assertStringIncludes(l2, 'management@quotesdone.com');
  const [a1, a2] = footerLinesAr(FALLBACK);
  assertStringIncludes(a1, 'QuotesDone Technologies'); assertStringIncludes(a1, '1633275'); assertStringIncludes(a1, 'NOL-26-100000665'); assertStringIncludes(a1, 'رخصة');
  assertEquals(a2.split(' · ').pop(), 'quotesdone.ae'); assertStringIncludes(a2, 'management@quotesdone.com');
});

// CUSTOMER AUDIT 21 Sep 2026, FINDING 12 — the audited quotation (two Knauf gypsum lines, AED 25,920)
// as customer_api now hands it in: the per-line spec read from quote_items.spec, the exclusions with
// their commas, and a warranty long enough to overrun a key-figure cell.
const AUDIT_ITEMS: Item[] = [
  { desc: 'Knauf gypsum false ceiling 12.5mm with cove lighting detail', qty: '180', unit: 'm2', unit_price: 95, amount: 17100, specs: { brand: 'Knauf', thickness_mm: '12.5', board_type: 'Knauf standard gypsum board, 12.5 mm' } },
  { desc: 'Knauf gypsum cornice 150mm supplied and fixed', qty: '210', unit: 'm', unit_price: 42, amount: 8820, specs: { brand: 'Knauf', thickness_mm: '150' } },
];
const AUDIT_QUOTE = { id: 'zz-demo-audit-quote', quote_amount: 25920, price_ex_vat: 25920, lead_time: '4 weeks', validity: '30 days', warranty: '2 years materials and workmanship', payment_terms: '50% advance, 50% on completion', exclusions: 'electrical fittings, painting of walls, scaffolding above 4m' };
const AUDIT_INQ = { id: 'zz-demo-audit-inq', category: 'fitout', summary: 'ZZ DEMO villa false ceiling', emirate: 'Dubai' };
for (const lang of ['en', 'ar'] as const) {
  Deno.test(`quotation (audit 21 Sep, ${lang.toUpperCase()}): specs read as stated, exclusions keep their commas, the key-figure strip does not overlap`, async () => {
    // deno-lint-ignore no-explicit-any
    const body: any = F.reasoned((arTexts) => quoteDocument({ quote: AUDIT_QUOTE, inquiry: AUDIT_INQ, items: AUDIT_ITEMS, letter: 'A', lang, ...dates(lang) , arTexts })).body;
    const checks = blocksOf(body, 'checks')[0].items;
    assertEquals(checks[0][1].flag, 'match');
    assertEquals(cellText(checks[0][1]), lang === 'en' ? 'Stated on all 2 lines' : 'مذكورة في جميع البنود (2)');
    const table = blocksOf(body, 'table')[0];
    // English prints the supplier's words; Arabic prints their reasoned Arabic (mocked), whole, never substituted.
    if (lang === 'en') { assertStringIncludes(JSON.stringify(table.rows[0][2]), 'Knauf'); assertStringIncludes(JSON.stringify(table.rows[0][2]), '12.5'); }
    else assertStringIncludes(JSON.stringify(table.rows[0][2]), 'ترجمة السطر');
    const excl = blocksOf(body, 'p').find((p: any) => /Exclusions|الاستثناءات/.test(String(p.label)));
    assert(excl, 'exclusions paragraph');
    // English: the sentence verbatim. Arabic: the WHOLE sentence is handed to reasoning (so its commas reach
    // the translator), and the page prints what reasoning returned for exactly that sentence.
    if (lang === 'en') assertEquals(excl.text, 'electrical fittings, painting of walls, scaffolding above 4m');
    else {
      const un = quoteDocument({ quote: AUDIT_QUOTE, inquiry: AUDIT_INQ, items: AUDIT_ITEMS, letter: 'A', lang, ...dates(lang) }).untranslated;
      assert(un.includes('electrical fittings, painting of walls, scaffolding above 4m'), 'the exclusions sentence is reasoned whole: ' + JSON.stringify(un));
      assertEquals(excl.text, F.mockArabic(un)['electrical fittings, painting of walls, scaffolding above 4m']);
    }
    // The rendered strip: the warranty value stays inside its own quarter of the strip and never
    // crosses into the "Valid for" cell beside it (finding 12: it was drawn on one unwrapped line).
    await assertRenders(body, lang);
    // Measured on the Helvetica render (the brand fonts embed as subsets whose runs the position
    // reader cannot decode; the cell geometry is the same with either font). The value's runs sit
    // on one or two lines inside the third quarter of the strip; none reaches the fourth.
    if (lang === 'en') {
      const plain = await renderPdf(body, { fetchBytes: async () => null });
      assert(plain.ok);
      const page = (await pdfPages(plain.bytes))[0];
      const valid = page.runs.find((r) => r.text === '30 days');
      const warr = page.runs.filter((r) => /workmanship|materials/.test(r.text) && Math.abs(r.y - (valid?.y ?? -1)) < 0.03);
      assert(valid && warr.length >= 1, 'strip values found: ' + JSON.stringify(page.runs.slice(12, 22)));
      for (const w of warr) assert(w.x + w.w <= valid!.x, `warranty run overlaps the validity cell: ${JSON.stringify(w)} vs ${JSON.stringify(valid)}`);
      assert(warr.length <= 2, 'a key figure never takes more than two lines');
    }
  });
}

Deno.test('labels: drafts take no letter, the incomplete quote sorts last, seven live quotes', () => {
  const lab = F.labelled();
  assertEquals(lab.length, 7);
  assertEquals(lab.map((l) => l.label), ['A', 'B', 'C', 'D', 'E', 'F', 'G'].map((x) => 'Supplier ' + x));
  assertEquals(lab[0].price, 78900);
  assertEquals(lab[6].price, null);
});

Deno.test('roster: every quote listed, three shortlisted, the incomplete one held — both cases', () => {
  for (const c of ['hvac', 'fitout'] as const) {
    const a = analysisFor(c, 'en');
    assertEquals(a.all_quotes.length, CASES[c].n);
    // deno-lint-ignore no-explicit-any
    const by = (s: string) => a.all_quotes.filter((r: any) => r.status === s).map((r: any) => r.label);
    assertEquals(by('shortlisted').length, 3, c);
    assertEquals(by('held'), [CASES[c].held], c);
  }
});

Deno.test('Arabic, deterministically: durations and units (payment terms are the supplier words, reasoned)', () => {
  assertEquals(arDuration('2 weeks'), 'أسبوعان');
  assertEquals(arDuration('12 months'), '12 شهرًا');
  assertEquals(arDuration('3 weeks'), '3 أسابيع');
  assertEquals(arDuration('10-14 days'), '10–14 يومًا');
  assertEquals(arDuration('3 working days'), '3 أيام عمل');
  assertEquals(arDuration('1 year'), 'سنة واحدة');
  assertEquals(arDuration('ASAP'), 'فوري');
  assertEquals(arDuration('after the site visit'), null);
  assertEquals(arUnit('Nos'), 'عدد');
  assertEquals(arUnit('LM'), 'م.ط');
  assertEquals(arUnit('furlong'), null);
});

Deno.test('contacts are masked and VAT / TRN sentences are dropped from supplier free text', () => {
  const s = maskContacts('Call ZZ DEMO Cool Air on +971 50 000 0001, 050 000 0001 or sales1@zzdemo-1.example.invalid / www.zzdemo-1.example.invalid', ['ZZ DEMO Cool Air LLC']);
  assert(!/ZZ DEMO|000 0001|example\.invalid/i.test(s), s);
  // Quantities and model numbers are not phone numbers.
  assertEquals(maskContacts('24 TR, 120 LM, model FDYQ180LA'), '24 TR, 120 LM, model FDYQ180LA');
  assertEquals(stripVat('Price includes delivery. Prices exclude 5% VAT; our TRN is 100123456700003.'), 'Price includes delivery.');
  assertEquals(stripVat('Delivery in 2 weeks'), 'Delivery in 2 weeks');
});

for (const c of ['hvac', 'fitout'] as const) {
  for (const lang of ['en', 'ar'] as const) {
    Deno.test(`quotation ${c} (${lang.toUpperCase()}): sections, figures, four checks, no identity, no VAT, renders`, async () => {
      // deno-lint-ignore no-explicit-any
      const body: any = quoteBody(c, lang);
      const s = JSON.stringify(body);
      const q = CASES[c].live()[0];
      const want = lang === 'en'
        ? ['Request and quoting party', 'Scope and technical specification', 'Completeness check', 'Commercial terms', 'Standardised by QuotesDone from the supplier', 'Prepared by the QuotesDone sales engineer', 'Supplier A', 'Material specification, per line', 'Delivery / lead time', 'Installation', 'Warranty — period and coverage']
        : ['الطلب والجهة مقدّمة العرض', 'نطاق العمل والمواصفات الفنية', 'فحص اكتمال العرض', 'الشروط التجارية', 'وحّدته QuotesDone', 'أعدّه مهندس مبيعات QuotesDone', 'المورّد A', 'مواصفات المواد لكل بند', 'التسليم / مدة التنفيذ', 'التركيب', 'الضمان — المدة والتغطية'];
      for (const w of want) assertStringIncludes(s, w);
      assertEquals(blocksOf(body, 'checks')[0].items.length, 4, 'the four completeness checks');
      assertStringIncludes(body.control, DOC_VERSION);
      assertStringIncludes(body.control, lang === 'en' ? 'Prepared by the QuotesDone sales engineer' : 'أعدّه مهندس مبيعات QuotesDone');
      assertStringIncludes(JSON.stringify(body.cover), q.quote_amount!.toLocaleString('en-AE'));
      assertEquals(body.cover.figures.length, 4);
      assertEquals(blocksOf(body, 'link')[0].link, deep(c, lang, q.id));
      if (lang === 'en') assert(!/[؀-ۿ]/.test(s), 'Arabic in the English quotation');
      else assertFullyArabic(body);
      assertNoIdentity(body, c); assertNoVat(body, lang); assertNoMachinery(body);
      const out = await assertRenders(body, lang);
      if (out && out.ok && (lang === 'en' || out.meta.fonts.arabic)) assert((await linksIn(out.bytes)).includes(deep(c, lang, q.id)), 'the quotation links back to its quote');
    });
  }
}

Deno.test('quotation (fit-out): every line carries its specification and its price; totals add up', () => {
  // deno-lint-ignore no-explicit-any
  const body: any = quoteBody('fitout', 'en');
  const t = blocksOf(body, 'table')[0];
  assertEquals(t.head.map(cellText), ['#', 'Description', 'Specification', 'Qty', 'Unit', 'Rate (AED)', 'Amount (AED)']);
  assertStringIncludes(cellText(t.rows[0][2]), 'Thickness: 18 mm');
  assertStringIncludes(cellText(t.rows[0][2]), 'Moisture resistant MDF');
  assertEquals(cellText(t.rows[0][6]), '29,400.00');
  const tot = blocksOf(body, 'totals')[0];
  assertEquals(tot.rows.map((r: string[]) => r[1]), ['AED 62,400.00', 'AED 62,400.00']);
  assertEquals(tot.note, '');
});

for (const c of ['hvac', 'fitout'] as const) {
  for (const lang of ['en', 'ar'] as const) {
    Deno.test(`comparison ${c} (${lang.toUpperCase()}): sections, every quote listed, held quote without details, technical table, no identity, no VAT, renders`, async () => {
      // deno-lint-ignore no-explicit-any
      const body: any = compareBody(c, lang);
      const s = JSON.stringify(body);
      const N = CASES[c].n; const held = CASES[c].held; const heldAr = held.replace('Supplier', 'المورّد');
      const want = lang === 'en'
        ? ['Quote comparison report', 'Executive summary', 'Method and scope of assessment', 'Technical comparison', 'Commercial comparison', `All quotes received (${N})`, 'Risks and clarifications by supplier', `3 of ${N}`, 'Shortlisted #1', `${held} is on hold`, 'Recommended', 'You can choose any of them', 'Matches your request', 'Completeness: the four checks, side by side', 'Prepared by the QuotesDone sales engineer']
        : ['تقرير مقارنة العروض', 'الملخص التنفيذي', 'المنهجية ونطاق التقييم', 'المقارنة الفنية', 'المقارنة التجارية', `جميع العروض المستلمة (${N})`, 'المخاطر والاستيضاحات لكل مورّد', `3 من ${N}`, `${heldAr} معلّق`, 'التوصية', 'يمكنك اختيار أي منها', 'مطابق لطلبك', 'أعدّه مهندس مبيعات QuotesDone'];
      for (const w of want) assertStringIncludes(s, w);
      // "Only three quotes" must never be said about a request that received more.
      assert(!/only (3|three) quotes/i.test(s));
      // Every quote is in the roster; the held one says so and shows no price and no lead time.
      const statusHead = lang === 'en' ? 'Status' : 'الحالة';
      const roster = blocksOf(body, 'table').find((t) => cellText(t.head[3]) === statusHead);
      assertEquals(roster.rows.length, N);
      const heldRow = roster.rows.find((r: unknown[]) => cellText(r[3]) === (lang === 'en' ? 'On hold' : 'معلّق'));
      assert(heldRow, 'the held quote is listed as on hold');
      assertEquals(cellText(heldRow[0]), lang === 'en' ? held : heldAr);
      assertEquals([cellText(heldRow[1]), cellText(heldRow[2])], ['—', '—']);
      // The held quote is never a technical or commercial column.
      for (const t of blocksOf(body, 'table')) if (cellText(t.head[3]) !== statusHead) assert(!t.head.map(cellText).includes(lang === 'en' ? held : heldAr), 'held quote is a column: ' + JSON.stringify(t.head));
      // The line-by-line table: one group row per scope line, one flagged cell per supplier per attribute.
      const spec = blocksOf(body, 'table').find((t) => cellText(t.head[1]) === (lang === 'en' ? 'You asked for' : 'طلبك'));
      assert(spec, 'technical line-by-line table');
      assertEquals(spec.rows.filter((r: unknown[]) => r.length === 1).length, CASES[c].tech().lines.length);
      // deno-lint-ignore no-explicit-any
      const flags = spec.rows.filter((r: unknown[]) => r.length > 1).flatMap((r: any[]) => r.slice(2).map((x) => x.flag));
      assert(flags.includes('match') && flags.includes('differs') && flags.includes('missing'), 'the table marks matches, differences and gaps');
      assertStringIncludes(body.control, DOC_VERSION);
      if (lang === 'ar') { assertFullyArabic(body); assert(!s.includes('"Supplier '), 'an untranslated supplier label on the Arabic report'); }
      assertNoIdentity(body, c); assertNoVat(body, lang); assertNoMachinery(body);
      await assertRenders(body, lang);
    });
  }
}

Deno.test('comparison (fit-out): the others show their differences; the held quote\'s gaps are not detailed', () => {
  // deno-lint-ignore no-explicit-any
  const body: any = compareBody('fitout', 'en');
  const s = JSON.stringify(body);
  assertStringIncludes(s, 'Line 1 (Built-in wardrobe): finish is PU lacquer, high gloss; you asked for PU lacquer, matt.');
  assertStringIncludes(s, 'Line 2 (Kitchen cabinets): thickness is 16 mm; you asked for 18 mm.');
  assert(!s.includes('Line 1 (Built-in wardrobe): thickness not stated'), 'the held quote\'s gaps are not detailed');
});

Deno.test('comparison without a technical comparison says specifications are not assessed — once', () => {
  for (const lang of ['en', 'ar'] as const) {
    const s = JSON.stringify(compareBody('hvac', lang, false));
    assertEquals((s.match(lang === 'en' ? /Specifications are not assessed/g : /لم تُقيَّم المواصفات/g) || []).length, 1, lang);
    assertStringIncludes(s, lang === 'en' ? 'All 7 quotes are listed in this report; the top 3 are compared in detail.' : 'أُدرجت العروض جميعها (7) في هذا التقرير');
  }
});

Deno.test('compare_csv exports the same commercial rows the report shows, markers as text', () => {
  const a = analysisFor('fitout', 'en');
  const t = compareTable(a, false)!;
  // deno-lint-ignore no-explicit-any
  const shortlisted = a.top3.map((x: any) => x.label);
  assertEquals(t.head, ['Compare', ...shortlisted]);
  assert(!t.head.includes('Supplier B'), 'the held quote is not a CSV column');
  const lead = t.rows.find((r) => r[0] === 'Delivery / lead time')!;
  for (const cell of lead.slice(1)) assert(/^[✓≠—] /.test(cell), 'a marker on ' + cell);
});

for (const c of ['hvac', 'fitout'] as const) {
  for (const lang of ['en', 'ar'] as const) {
    Deno.test(`comparison ${c} (${lang.toUpperCase()}): every quote row and every recommendation links to its own quote`, async () => {
      const body = compareBody(c, lang);
      const lab = CASES[c].lab();
      const want = lab.map((l) => deep(c, lang, l.quote_id));
      assertEquals(portalLink(lang, CASES[c].inq.id, lab[0].quote_id), want[0]);
      const s = JSON.stringify(body);
      for (const u of want) assertStringIncludes(s, JSON.stringify(u));
      const out = await assertRenders(body, lang);
      if (!out || !out.ok || (lang === 'ar' && !out.meta.fonts.arabic)) return;
      const links = await linksIn(out.bytes);
      for (const u of want) assert(links.includes(u), 'no link on the page to ' + u + ' - found ' + JSON.stringify(links));
      // A recommended quote links from the "Recommended" table AND "All quotes received" (the first
      // pick also from its recommendation box).
      const a = analysisFor(c, lang);
      // deno-lint-ignore no-explicit-any
      for (const t of a.top3) { const r = a.all_quotes.find((x: any) => x.label === t.label); assert(links.filter((u) => u === deep(c, lang, r.quote_id)).length >= 2, 'recommended ' + t.label); }
      assert(links.includes(portalLink(lang, CASES[c].inq.id)), 'the portal note should open this request');
      // Ids only: the query holds `request` (this inquiry) and, on a quote link, `quote` (a live quote id).
      const ids = new Set(lab.map((l) => l.quote_id));
      for (const u of links) {
        const p = new URL(u).searchParams;
        assertEquals([...p.keys()].filter((k) => k !== 'request' && k !== 'quote'), [], 'a link carries more than ids: ' + u);
        assertEquals(p.get('request'), CASES[c].inq.id);
        if (p.has('quote')) assert(ids.has(String(p.get('quote'))), 'a link names a quote that is not on this request: ' + u);
      }
    });
  }
}

// ── THE INQUIRY DOCUMENT (21 Sep 2026; founder instruction 435) ──────────────────────────────────
// Built from the inbox row the supplier already sees (fixture REQUEST): it must carry the job number,
// the required-by date, the customer's four answers, EVERY BOQ line with its quantity and unit, and
// the attached documents by name; it must mask the contact details the summary carries; in Arabic
// every primary string is Arabic (file names and codes excepted); and it must render and load back.
const SUPPLIER_PORTAL = 'https://quotesdone.com/portal';
function inquiryBody(lang: Lang) { return F.reasoned((arTexts) => inquiryDocument({ inquiry: F.REQUEST, lang, portalUrl: lang === 'ar' ? 'https://quotesdone.com/ar/portal' : SUPPLIER_PORTAL, ...dates(lang) , arTexts })).body; }
const strings = (v: unknown): string[] => typeof v === 'string' ? [v] : Array.isArray(v) ? v.flatMap(strings) : v && typeof v === 'object' ? Object.values(v).flatMap(strings) : [];
Deno.test('inquiry document: job number, deadline, the four answers, every BOQ line and every attachment — both languages', () => {
  for (const lang of ['en', 'ar'] as Lang[]) {
    const body = inquiryBody(lang);
    const all = JSON.stringify(body);
    const { ref, job, drawings } = F.reasoned((arTexts) => inquiryDocument({ inquiry: F.REQUEST, lang , arTexts }));
    assertEquals(job, 'ZZD3M0AA'); assertEquals(ref, 'QD-ZZD3M0AA-RFQ'); assertEquals(drawings, 2);
    assertStringIncludes(all, 'ZZD3M0AA');
    assertStringIncludes(all, lang === 'ar' ? '14 أكتوبر 2026' : '14 October 2026', 'the required-by date');
    // deno-lint-ignore no-explicit-any
    const tables = (body.blocks as any[]).filter((b) => b.t === 'table');
    assertEquals(tables.length, 3, 'requirements, BOQ, documents');
    const [reqT, boqT, docT] = tables;
    assertEquals(reqT.rows.length, 4, 'the four intake answers');
    assertEquals(boqT.rows.length, F.REQUEST.boq!.boq!.length, 'every BOQ line');
    for (const [k, r] of F.REQUEST.boq!.boq!.entries()) {
      const row = boqT.rows[k].map(cellStr);
      assertEquals(row[0], String(k + 1)); assertEquals(row[3], String(r.qty));
      assertEquals(row[4], lang === 'ar' ? (arUnit(r.unit) ?? r.unit) : r.unit);
      if (lang === 'en') assertStringIncludes(row[2], String(r.description));
    }
    assertEquals(docT.rows.length, F.REQUEST.documents.length, 'every attachment');
    for (const d of F.REQUEST.documents) assertStringIncludes(all, d.name);
    assertStringIncludes(all, lang === 'ar' ? 'تعذّر تقديم 1' : '1 drawing page could not be served');
    // deno-lint-ignore no-explicit-any
    const cover = body.cover as any;
    assertEquals(cover.figures.map((f: string[]) => f[1])[1], '6', 'BOQ lines on the cover');
    assertStringIncludes(all, lang === 'ar' ? '24 شهرًا على الأقل' : '24 months minimum', 'the warranty the customer asked for, from the machine field');
    assertNoMachinery(body);
    // deno-lint-ignore no-explicit-any
    assert((body.blocks as any[]).some((b) => b.t === 'link' && String(b.link).startsWith('https://quotesdone.com/')), 'the portal link');
  }
});
Deno.test('inquiry document: the customer\'s contact details in the summary never reach the page', () => {
  for (const lang of ['en', 'ar'] as Lang[]) {
    const all = JSON.stringify(inquiryBody(lang));
    for (const c of F.REQUEST_CONTACTS) assert(!all.includes(c), `${lang}: ${c} reached the page`);
    assert(!/\b0500000099\b|50 000 0099/.test(all), 'the number in another spelling');
  }
});
Deno.test('inquiry document: the Arabic page is Arabic (file names and codes excepted)', () => {
  const body = inquiryBody('ar');
  const leaks = primary({ cover: body.cover, blocks: body.blocks, control: body.control, title: body.title })
    .filter((s) => !/^Job_[A-Z0-9]+_/.test(s))
    .flatMap((s) => latinLeaks(s).map((w) => `${w}  ←  ${s.slice(0, 90)}`));
  assertEquals(leaks, [], 'English left in the Arabic primary text');
  const labels = fixedLabels(body).flatMap((s) => latinLeaks(s).map((w) => `${w}  ←  ${s}`));
  assertEquals(labels, [], 'English in a fixed Arabic label');
  // No half-translated line: the customer's words are reasoned Arabic, and without that Arabic the page is held.
  assertEquals(strings(body.blocks).filter((s) => s.startsWith('النص الأصلي')), []);
  const unreasoned = inquiryDocument({ inquiry: F.REQUEST, lang: 'ar', portalUrl: 'https://quotesdone.com/ar/portal', ...dates('ar') });
  assert(unreasoned.untranslated.some((t) => /90k/.test(t)), 'the budget "around 90k" is a line the page cannot print until it is reasoned');
});
Deno.test('inquiry document: a withheld BOQ and no attachments are said, not hidden', () => {
  const bare = { ...F.REQUEST, boq: null, boq_withheld: true, documents: [], drawing_pages_failed: 0, spec: null };
  for (const lang of ['en', 'ar'] as Lang[]) {
    const body = F.reasoned((arTexts) => inquiryDocument({ inquiry: bare, lang , arTexts })).body;
    const all = JSON.stringify(body);
    // deno-lint-ignore no-explicit-any
    assertEquals((body.blocks as any[]).filter((b) => b.t === 'table').length, 0);
    assertStringIncludes(all, lang === 'ar' ? 'حُجب جدول الكميات' : 'The bill of quantities is held back');
    assertStringIncludes(all, lang === 'ar' ? 'لم تُرفق مستندات' : 'No documents were attached');
    assertStringIncludes(all, lang === 'ar' ? 'لم تُسجَّل إجابات العميل' : 'were not recorded');
    assertStringIncludes(all, lang === 'ar' ? 'غير مذكور' : 'Not stated', 'the deadline when the intake is absent');
  }
});
Deno.test('inquiry document renders to a PDF that loads back, both languages', async () => {
  for (const lang of ['en', 'ar'] as Lang[]) {
    const out = await assertRenders(inquiryBody(lang), lang);
    if (!out) continue;
    assert(strings(out.meta).length >= 0);
    const links = await linksIn(out.bytes);
    assert(links.some((u) => u.startsWith('https://quotesdone.com/')), 'the portal link is written into the file: ' + JSON.stringify(links));
  }
});

// ── ONE JOB NUMBER (supplier audit 21 Sep 2026, finding 7) ──────────────────────────────────────────
// Replays the failing input: job d958e1ea… is rfq 151767; the supplier's documents printed D958E1EA.
Deno.test('job number: every document prints inquiries.rfq_no, the number the customer portal shows', () => {
  const inq = { id: 'd958e1ea-0000-4000-8000-000000000000', rfq_no: 151767 };
  assertEquals(jobNoOf(inq), '151767');
  assertEquals(quoteRef(inq, 'A'), 'QD-151767-A');
  // only a row read WITHOUT rfq_no falls back to the uuid prefix
  assertEquals(jobNoOf({ id: inq.id }), 'D958E1EA');
  for (const lang of ['en', 'ar'] as Lang[]) {
    // the attachment names come from inquiryDocuments (quote_review_actions.ts), which names them by the same jobNo
    const prefix = String(F.REQUEST.id).slice(0, 8).toUpperCase();
    const documents = F.REQUEST.documents.map((d) => ({ ...d, name: d.name.replace(prefix, '151767') }));
    const r = F.reasoned((arTexts) => inquiryDocument({ inquiry: { ...F.REQUEST, rfq_no: 151767, documents }, lang , arTexts }));
    assertEquals(r.job, '151767'); assertEquals(r.ref, 'QD-151767-RFQ');
    assert(!JSON.stringify(r.body).includes(String(F.REQUEST.id).slice(0, 8).toUpperCase()), `${lang}: the uuid prefix is not printed`);
  }
});

// ── THE ARABIC INQUIRY BOQ (finding 26) ─────────────────────────────────────────────────────────────
// The inbox hands the document section_ar / description_ar (_shared/boq_arabic.ts). On the Arabic page a
// line the glossary alone cannot finish prints the sales engineer's Arabic label, with the customer's
// words on the secondary line; the English page is unchanged.
Deno.test('inquiry document: the Arabic page prints the reasoned Arabic of the BOQ section and description', () => {
  const boq = { boq: [{ section: 'Partitions', section_ar: 'القواطع والجدران الداخلية', description: 'Gypsum board partition, 100mm metal stud, both faces, zz-fixture-word', description_ar: 'قواطع ألواح الجبس', qty: 320, unit: 'm2' }] };
  const table = (lang: Lang) => {
    // deno-lint-ignore no-explicit-any
    const t = (F.reasoned((arTexts) => inquiryDocument({ inquiry: { ...F.REQUEST, boq }, lang , arTexts })).body.blocks as any[]).filter((b) => b.t === 'table')[1];
    return t.rows[0];
  };
  // The Arabic cells are the reasoned translation (mocked here), never the word-matched boq_arabic labels.
  const ar = table('ar');
  assertStringIncludes(String(ar[1]), 'ترجمة السطر');
  assertStringIncludes(String(ar[2]), 'ترجمة السطر');
  assert(!JSON.stringify(ar).includes('قواطع ألواح الجبس'), 'a substituted label reached the page');
  const en = table('en');
  assertEquals(cellStr(en[2]), 'Gypsum board partition, 100mm metal stud, both faces, zz-fixture-word');
});

