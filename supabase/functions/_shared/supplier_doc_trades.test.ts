// supplier_doc_trades — a supplier's document is read by code and its trades come back with evidence:
// by an exact code or by meaning, never by the document's alias words (ruling 890, ledger 1054).
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/supplier_doc_trades.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { mergeEvidence, modelReadText, proposedFrom, readDocForTrades, WORD_READ, type DocEvidence, type TradeResolveDeps } from './supplier_doc_trades.ts';
import type { MeaningService } from './service_meaning.ts';
import { makeDrawingPdf } from './pdf_measure.fixtures.ts';

// fn_norm_trades over a slice of the live codes (the real routine is run by the check; see trade_resolve.test.ts).
const CODES = new Set(['hvac', 'plumbing', 'electrical', 'aluminium', 'building_materials', 'packaging']);
const exact = async (phrases: string[]) => Object.fromEntries(phrases
  .map((p) => [p, p.trim().toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '_')] as const)
  .filter(([, c]) => CODES.has(c)).map(([p, c]) => [p, [c]]));
const SERVICES: MeaningService[] = [
  { trade_code: 'hvac', code: 'chiller_maintenance', label_en: 'Chiller maintenance', label_ar: 'صيانة المبردات', aliases: [], vec: [1, 0] },
  { trade_code: 'plumbing', code: 'drainage', label_en: 'Drainage works', label_ar: 'أعمال الصرف', aliases: [], vec: [0, 1] },
];
const VEC: Record<string, number[]> = { 'Chiller maintenance': [0.98, 0.05] };   // the clause read from 'Chiller maintenance for villas and towers'
const deps = (o: Partial<TradeResolveDeps> = {}): TradeResolveDeps =>
  ({ normTrades: exact, services: SERVICES, embed: async (t) => VEC[t] ?? [0.5, 0.5], budget: { left: 16 }, ...o });
const codes = (h: { code: string }[]) => h.map((x) => x.code).sort();

Deno.test('a PDF with a text layer is read by code: a heading that IS a code, and a line that MEANS a service', async () => {
  const pdf = makeDrawingPdf(['ZZ DEMO COMPANY PROFILE', 'HVAC', 'Chiller maintenance for villas and towers'], '');
  const ev = await readDocForTrades({ path: 'profiles/1/p.pdf', name: 'p.pdf', kind: 'profile', bytes: pdf, mime: 'application/pdf' }, deps());
  assertEquals(ev.status, 'read');
  assertEquals(ev.format, 'pdf');
  assertEquals([ev.exact, ev.meaning], ['on', 'on']);
  assertEquals(codes(ev.trades), ['hvac']);
  const h = ev.trades[0];
  assertEquals(h.via, 'exact_code');           // the exact code is found first; meaning adds its service
  assertEquals(h.phrases, ['hvac', 'chiller maintenance']);
});

Deno.test('the alias words of a document propose nothing on their own (what trade_words.ts used to do)', async () => {
  const pdf = makeDrawingPdf(['ZZ DEMO COMPANY PROFILE', 'Air conditioning and chiller maintenance', 'Plumbing and drainage'], '');
  const ev = await readDocForTrades({ path: 'profiles/1/p.pdf', name: 'p.pdf', kind: 'profile', bytes: pdf, mime: 'application/pdf' },
    deps({ embed: async () => null }));
  assertEquals(ev.trades, []);
  // ...and it is not a false zero: the evidence says meaning could not be read
  assertEquals(ev.meaning, 'embedding_unavailable');
});

Deno.test('a catalogue is read without its spec rows, and a trader is read as supply-only', async () => {
  const text = 'ZZ DEMO GENERAL TRADING LLC\nImporter and wholesaler\nHVAC\nDVR Storage Upto 6TB\nTel +971 4 000 0000';
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'catalogs/1/c.txt', name: 'c.txt', kind: 'catalogue', photo_text: text },
    deps({ embed: async (t) => { seen.push(t); return null; } }));
  assertEquals(ev.supply_only, true);
  assertEquals(codes(ev.trades), ['hvac']);
  assert(!seen.some((t) => /6TB|Tel/.test(t)), 'a spec row or a contact line was read for meaning: ' + JSON.stringify(seen));
});

Deno.test('a scan with no text layer is needs_ocr, never a false zero', async () => {
  const scan = makeDrawingPdf([], '0.7 w 100 100 141.73 113.39 re S');
  const ev = await readDocForTrades({ path: 'catalogs/1/s.pdf', name: 's.pdf', kind: 'catalogue', bytes: scan, mime: 'application/pdf' }, deps());
  assertEquals(ev.status, 'needs_ocr');
  assertEquals(ev.trades, []);
});

Deno.test('a refused file is unreadable with the reason', async () => {
  const html = new TextEncoder().encode('<html><script>alert(1)</script></html>');
  const ev = await readDocForTrades({ path: 'catalogs/1/x.pdf', name: 'x.pdf', kind: 'catalogue', bytes: html, mime: 'application/pdf' }, deps());
  assertEquals(ev.status, 'unreadable');
  assert(ev.reason && ev.reason.length > 0);
});

Deno.test('a new licence replaces the old one; catalogues accumulate; proposal is the union', () => {
  const e = (path: string, kind: DocEvidence['kind'], c: string[]): DocEvidence =>
    ({ path, name: path, kind, status: 'read', read_at: 'x', exact: 'on', meaning: 'on', trades: c.map((code) => ({ code, via: 'exact_code', phrases: [code], snippet: code })) });
  const prev = [e('licenses/1/a.pdf', 'licence', ['plumbing']), e('catalogs/1/c1.pdf', 'catalogue', ['hvac'])];
  const merged = mergeEvidence(prev, [e('licenses/1/b.pdf', 'licence', ['electrical']), e('catalogs/1/c2.pdf', 'catalogue', ['aluminium'])]);
  assertEquals(merged.map((d) => d.path).sort(), ['catalogs/1/c1.pdf', 'catalogs/1/c2.pdf', 'licenses/1/b.pdf']);
  assertEquals(proposedFrom(merged), ['aluminium', 'electrical', 'hvac']);
});

Deno.test('evidence an older reader took from alias words is kept as a record but proposes nothing', () => {
  // reader @2 wrote no exact/meaning fields; its trades were alias hits
  const old: DocEvidence = { path: 'catalogs/1/old.pdf', name: 'old.pdf', kind: 'catalogue', status: 'read', read_at: 'x',
    trades: [{ code: 'hvac', via: 'exact_code', phrases: ['chiller'], snippet: 'chiller' }] };
  const merged = mergeEvidence([old], []);
  assertEquals(merged.length, 1);
  assertEquals(merged[0].trades, []);
  assertEquals(merged[0].reason, WORD_READ);
  assertEquals(proposedFrom(merged), []);
});

// 7 Oct 2026 (sales_engineer, accuracy suite ledger 1162).
import { withoutCredentialLines } from './supplier_doc_trades.ts';
import { proposeByMeaning } from './service_meaning.ts';
Deno.test('a licence proposes trades from its activities line only, never from the company name', async () => {
  // the text a photo of the licence yields (photo_text): the same path a scan's model-read activities take
  const ev = await readDocForTrades({ path: 'l', name: 'l.jpg', kind: 'licence', photo_text: 'Company Name: ZZ DEMO Hvac Plumbing LLC\nActivities: Electrical, Aluminium' }, deps());
  assertEquals(codes(ev.trades), ['aluminium', 'electrical'], JSON.stringify(ev));
  const none = await readDocForTrades({ path: 'l', name: 'l.jpg', kind: 'licence', photo_text: 'Company Name: ZZ DEMO Hvac LLC' }, deps());
  assertEquals([none.trades.length, none.reason], [0, 'no activities line could be read on the licence']);
});
Deno.test('a certificate the company holds is a credential, not a service; a certification body keeps its line', () => {
  assertEquals(withoutCredentialLines('Plumbing works\nCertifications\n- ISO 9001:2015 quality management\nHVAC'), 'Plumbing works\nHVAC');
  assertEquals(withoutCredentialLines('ISO 9001:2015 certification services for contractors'), 'ISO 9001:2015 certification services for contractors');
});
Deno.test('a trade named in general is accepted by its trade name; a word that names ANOTHER trade decides nothing', () => {
  const S: MeaningService[] = [
    { trade_code: 'plumbing', code: 'maintenance', label_en: 'Plumbing maintenance contracts', label_ar: '', aliases: [], vec: [1, 0] },
    { trade_code: 'non_ferrous_metals', code: 'aluminium_sheet', label_en: 'Aluminium sheet', label_ar: '', aliases: [], vec: [0, 1] },
  ];
  const labels = { plumbing: 'Plumbing & sanitary', aluminium: 'Aluminium & cladding', non_ferrous_metals: 'Aluminium, copper & non-ferrous metals', lighting_fixtures: 'Lighting fixtures' };
  const p = proposeByMeaning([{ text: 'Plumbing works', vec: [0.95, 0.05], space: 'gte' }], [S[0]], { tradeLabels: labels });
  assertEquals(p.map((x) => [x.trade, x.because]), [['plumbing', 'trade_word']]);
  assertEquals(proposeByMeaning([{ text: 'Aluminium works', vec: [0.05, 0.95], space: 'gte' }], S, { tradeLabels: labels }), []);
  assertEquals(proposeByMeaning([{ text: 'Plumbing works', vec: [0.95, 0.05], space: 'gte' }], [S[0]]).length, 0, 'opt-in: the Services tab is unchanged');
});
// 12 Oct 2026 (sales_engineer, accuracy suite: 0 of 9 aluminium suppliers reached). The live shape: the line's three
// nearest services belong to other trades, "aluminium" is a whole part of two trade NAMES, and is the CODE of one.
// codeWords are what fn_norm_trades resolves to ONE trade (trade_resolve.codeWordsOf): the codes, and the stored alias
// 'aluminum' (scripts/sql/aluminum_is_the_aluminium_trade_by_its_us_spelling.sql).
Deno.test('a work line holding a word the database resolves to one trade names it when it also means one of its services', () => {
  const v = (a: number, b: number, c: number) => [a, b, c];
  const S: MeaningService[] = [
    { trade_code: 'machinery_repair', code: 'pm', label_en: 'Preventive maintenance contracts', label_ar: '', aliases: [], vec: v(1, 0, 0) },
    { trade_code: 'general_contracting', code: 'db', label_en: 'Design and build', label_ar: '', aliases: [], vec: v(0.99, 0.14, 0) },
    { trade_code: 'general_contracting', code: 'bc', label_en: 'Building construction', label_ar: '', aliases: [], vec: v(0.98, 0.2, 0) },
    { trade_code: 'non_ferrous_metals', code: 'aluminium_sheet', label_en: 'Aluminium sheet & profiles', label_ar: '', aliases: [], vec: v(0.9, 0, 0.44) },
    { trade_code: 'aluminium', code: 'windows_doors', label_en: 'Aluminium windows & doors', label_ar: '', aliases: [], vec: v(0.85, 0, 0.53) },
    { trade_code: 'glazing', code: 'facades', label_en: 'Glass façades', label_ar: '', aliases: [], vec: v(0.6, 0.8, 0) },
  ];
  const labels = { aluminium: 'Aluminium & cladding', non_ferrous_metals: 'Aluminium, copper & non-ferrous metals', general_contracting: 'General contracting', machinery_repair: 'Machinery repair', glazing: 'Glass & glazing' };
  const codeWords = { aluminium: 'aluminium', aluminum: 'aluminium', glazing: 'glazing' };
  const line = (text: string, vec: number[]) => proposeByMeaning([{ text, vec, space: 'gte' }], S, { tradeLabels: labels, codeWords }).map((x) => [x.trade, x.because]);
  assertEquals(line('Aluminium Works Contracting', v(0.97, 0, 0.24)), [['aluminium', 'trade_code']]);
  assertEquals(line('Aluminum Works Contracting', v(0.97, 0, 0.24)), [['aluminium', 'trade_code']], 'the stored US-spelling alias');
  // a company name and a trader name no work. Measured live: "Legal Name: ZZ DEMO Falcon Glazing LLC" reached a
  // glazing service at 0.821, above the floor - the floor alone would have accepted it; the work gate refuses it.
  assertEquals(line('Legal Name: ZZ DEMO Falcon Glazing LLC', v(0.6, 0.8, 0)).filter(([, b]) => b === 'trade_code'), []);
  assertEquals(line('Aluminium Trading LLC', v(0.97, 0, 0.24)), []);
  // without the database's words nothing is matched by word
  assertEquals(proposeByMeaning([{ text: 'Aluminium Works Contracting', vec: v(0.97, 0, 0.24), space: 'gte' }], S, { tradeLabels: labels }).length, 0);
  // an Arabic line is not confirmed by this rule: the e5 space scores names and metal traders as high as activities
  const ar = S.map((s) => ({ ...s, vec_ml: s.vec }));
  assertEquals(proposeByMeaning([{ text: 'أعمال الألمنيوم', vec: v(0.97, 0, 0.24), space: 'ml' }], ar, { tradeLabels: labels, codeWords }).length, 0);
});

Deno.test('an image-only licence or profile: what the vision model read becomes trades (ruling 1177)', async () => {
  // A scan with NO text layer. Without the model's reading it is needs_ocr; with it (the photo_text every upload path
  // builds through modelReadText) the activities / services go through the same exact-code and meaning rules.
  const scan = makeDrawingPdf([], '0.7 w 100 100 141.73 113.39 re S');
  const lic = await readDocForTrades({ path: 'licenses/1/s.pdf', name: 's.pdf', kind: 'licence', bytes: scan, mime: 'application/pdf',
    photo_text: modelReadText('licence', ['Electrical', 'Aluminium']) }, deps());
  assertEquals([lic.status, lic.source, codes(lic.trades)], ['read', 'photo_text', ['aluminium', 'electrical']], JSON.stringify(lic));
  const prof = await readDocForTrades({ path: 'profiles/1/s.pdf', name: 's.pdf', kind: 'profile', bytes: scan, mime: 'application/pdf',
    photo_text: modelReadText('profile', ['Plumbing', 'HVAC']) }, deps());
  assertEquals(codes(prof.trades), ['hvac', 'plumbing'], JSON.stringify(prof));
  // nothing read -> nothing invented, and the scan stays needs_ocr rather than a false zero
  assertEquals(modelReadText('licence', []), undefined);
  const none = await readDocForTrades({ path: 'licenses/1/s.pdf', name: 's.pdf', kind: 'licence', bytes: scan, mime: 'application/pdf', photo_text: modelReadText('licence', null) }, deps());
  assertEquals(none.status, 'needs_ocr');
});

// ── REAL UAE COMPANY PROFILES (13 Oct 2026, it_engineer; ACCURACY_real_profiles.md) ─────────────────────────────────
// Regression fixtures from the 29 real profiles and catalogues measured that day. The files themselves are real
// companies' publications and stay on the founder's Desktop (real_profiles\, with SOURCES.md and the hand-written
// truth.json); what is committed here is the SHAPE of each failure, names replaced by ZZ DEMO.
import { offerText, SHORT_DOC_LINES } from './supplier_doc_trades.ts';
import { readDocument } from './doc_read/index.ts';

/** A one-page PDF that places every glyph with its own Td, as Canva/InDesign exports do (Maxfire, MAS Paints, Abu Hail). */
function perGlyphPdf(line: string): Uint8Array {
  let ops = 'BT /F1 12 Tf 72 700 Td';
  // Helvetica's own advance widths (1/1000 em) at 12 pt, so the glyphs sit where a real export puts them
  const W: Record<string, number> = { S: 667, p: 556, r: 333, i: 222, n: 556, k: 500, l: 222, e: 556, y: 500, t: 278, m: 833, s: 500, F: 611, u: 556, P: 667, ' ': 278 };
  for (const ch of line) ops += ` (${ch}) Tj ${((W[ch] ?? 556) * 12) / 1000} 0 Td`;   // letters and spaces only
  ops += ' ET';
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    `<< /Length ${ops.length} >>\nstream\n${ops}\nendstream`, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
  let pdf = '%PDF-1.4\n'; const at: number[] = [];
  objs.forEach((o, i) => { at.push(pdf.length); pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const x = pdf.length;
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${at.map((n) => String(n).padStart(10, '0') + ' 00000 n \n').join('')}trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${x}\n%%EOF`;
  return new TextEncoder().encode(pdf);
}

Deno.test('a PDF that places each glyph on its own is read as words, not letters (pdf.js, words-only reads)', async () => {
  const r = await readDocument(perGlyphPdf('Sprinkler Systems Fire Pumps'), 'p.pdf', 'application/pdf', 0, { textOnly: true });
  const text = r.ok ? r.text : '';
  assert(/Sprinkler\s*Systems/.test(text), text);
  assert(!/S p r i n k/.test(text), text);
});

Deno.test('a long profile is read where it states its offer, not in its org chart, insurance or client sections', () => {
  const filler = (k: string, n: number) => Array.from({ length: n }, (_, i) => `${k} ${i + 1}`);
  const doc = [
    'CEO MESSAGE', 'ZZ DEMO Fire LLC is a Dubai based fire protection contractor approved by Civil Defence.',
    ...filler('Our vision line', 20),
    'ORGANIZATION CHART', 'Management 1', 'Marketing 2', 'Estimation 2', 'Foremen 2', ...filler('Staff row', 25),
    'OUR SERVICES', 'Sprinkler Systems', 'Fire Alarm Systems', 'Fire Pumps', 'Clean Agent Systems',
    ...filler('Gallery caption', 30),
    'SECTION 13: INSURANCE DETAILS', 'Workmen compensation', 'OUR CLIENTS', 'ZZ DEMO Packaging, Technopark',
  ].join('\n');
  const o = offerText(doc)!;
  for (const l of ['is a Dubai based fire protection contractor approved by Civil Defence.', 'Sprinkler Systems', 'Fire Alarm Systems', 'Fire Pumps']) assert(o.includes(l), l);
  for (const l of ['Management 1', 'Marketing 2', 'INSURANCE DETAILS', 'Workmen compensation', 'ZZ DEMO Packaging']) assert(!o.includes(l), l);
  // a short document (the synthetic one-page profiles of the suite) is read whole, as before
  assertEquals(offerText(filler('line', SHORT_DOC_LINES).join('\n')), null);
});

Deno.test('on a supplier document a meaning hit stands only when the line holds its TRADE\'s own words', () => {
  const S: MeaningService[] = [
    { trade_code: 'accounting_bookkeeping', code: 'mgmt_accounts', label_en: 'Management accounts', label_ar: '', aliases: ['management'], vec: [1, 0, 0] },
    { trade_code: 'fire_fighting', code: 'sprinklers', label_en: 'Sprinkler systems', label_ar: '', aliases: [], vec: [0, 1, 0] },
    { trade_code: 'testing_labs', code: 'lab_testing', label_en: 'Product lab testing', label_ar: '', aliases: [], vec: [0, 0, 1] },
  ];
  const labels = { accounting_bookkeeping: 'Accounting & bookkeeping', fire_fighting: 'Fire fighting & life safety', testing_labs: 'Testing laboratories' };
  const tradeAliases = { accounting_bookkeeping: ['bookkeeping', 'accountant'], fire_fighting: ['sprinkler', 'fire alarm'], testing_labs: ['laboratory'] };
  const read = (text: string, vec: number[]) => proposeByMeaning([{ text, vec, space: 'gte' }], S, { tradeLabels: labels, tradeAliases }).map((x) => [x.trade, x.because]);
  // measured on real profiles: an org chart's "Management 1" -> accounting (the service's own alias agreed), and
  // " Testing and Commissioning" of an MEP contractor -> testing labs; neither line names the trade
  assertEquals(read('Management 1', [0.95, 0, 0.3]), []);
  assertEquals(read('Testing and Commissioning', [0, 0.2, 0.97]), []);
  assertEquals(read('Sprinkler Systems', [0, 0.99, 0.1]), [['fire_fighting', 'trade_alias']]);
  // without tradeAliases (the Services tab, the RFQ side) nothing changes: the head word still corroborates
  assertEquals(proposeByMeaning([{ text: 'Management 1', vec: [0.95, 0, 0.3], space: 'gte' }], S, { tradeLabels: labels }).map((x) => x.trade), ['accounting_bookkeeping']);
});

// ── ARABIC (review of #1404; measured on the BCG Arabic brochure, 69 pages) ─────────────────────────────────────────
import { arabicLigatureFix } from './doc_read/pdf.ts';
Deno.test('Arabic: the reversed lam-alef at a word start is repaired; an alef-lam inside a word is left alone', () => {
  assertEquals(arabicLigatureFix('االنتهاء من أعمال األساسات'), 'الانتهاء من أعمال الأساسات');
  assertEquals(arabicLigatureFix('أعمال مال سؤال'), 'أعمال مال سؤال');
});
Deno.test('Arabic: a long profile is read under its Arabic offer heading and offer sentences', () => {
  const filler = (k: string, n: number) => Array.from({ length: n }, (_, i) => `${k} ${i + 1}`);
  const doc = ['كلمة رئيس مجلس الإدارة', ...filler('سطر رؤية', 30), 'خدماتنا', 'أعمال الأساسات', 'أعمال الطرق والجسور',
    ...filler('صورة مشروع', 30), 'قائمة العملاء', 'زد زد ديمو للتغليف', 'الشركة متخصصة في أعمال المقاولات العامة'].join('\n');
  const o = offerText(doc)!;
  for (const l of ['أعمال الأساسات', 'أعمال الطرق والجسور', 'متخصصة في أعمال المقاولات العامة']) assert(o.includes(l), l);
  for (const l of ['زد زد ديمو للتغليف', 'سطر رؤية 3']) assert(!o.includes(l), l);
});
Deno.test('Arabic: a meaning hit on an Arabic line stands only with an Arabic alias of its trade', () => {
  const S: MeaningService[] = [{ trade_code: 'fire_fighting', code: 'sprinklers', label_en: 'Sprinkler systems', label_ar: 'رشاشات الحريق', aliases: [], vec: [1, 0], vec_ml: [1, 0] },
    { trade_code: 'accounting_bookkeeping', code: 'mgmt', label_en: 'Management accounts', label_ar: 'حسابات الإدارة', aliases: [], vec: [0, 1], vec_ml: [0, 1] }];
  const labels = { fire_fighting: 'Fire fighting & life safety', accounting_bookkeeping: 'Accounting & bookkeeping' };
  const tradeAliases = { fire_fighting: ['مكافحة حريق', 'رشاشات حريق'], accounting_bookkeeping: ['محاسبة'] };
  const read = (text: string, vec: number[]) => proposeByMeaning([{ text, vec, space: 'ml' }], S, { tradeLabels: labels, tradeAliases }).map((x) => [x.trade, x.because]);
  assertEquals(read('تركيب رشاشات الحريق ضمن أنظمة مكافحة الحريق', [0.99, 0.1]), [['fire_fighting', 'trade_alias']]);
  assertEquals(read('الإدارة العليا', [0.1, 0.99]), []);
  assertEquals(read('رشاشات المياه للحدائق', [0.99, 0.1]), [], 'the service word alone, without the trade, is not enough');
});

// ── A KILLED PARSE LEAVES THE DOCUMENT HELD (review of #1404) ───────────────────────────────────────────────────────
import { proposeTradesFromDocs } from './supplier_doc_trades.ts';
Deno.test('a read killed partway (the worker dies at its CPU cap) leaves the document held as "reading"', async () => {
  const writes: { source_docs: { docs: { path: string; status: string; trades: unknown[] }[] } }[] = [];
  const admin = { from: (_t: string) => ({
    select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null }) }) }),
    upsert: async (row: { source_docs: { docs: { path: string; status: string; trades: unknown[] }[] } }) => { writes.push(structuredClone(row)); return { error: null }; },
  }) };
  // The parse never finishes: the worker is killed here, so nothing after this point runs (no catch, no final write).
  const hang = new Promise<number[] | null>(() => {});
  const killed = deps({ embed: () => hang });
  const pdf = makeDrawingPdf(['ZZ DEMO PROFILE', 'Chiller maintenance for villas and towers'], '');
  const run = proposeTradesFromDocs(admin, 7, [{ path: 'profiles/7/p.pdf', name: 'p.pdf', kind: 'profile', bytes: pdf, mime: 'application/pdf' }], killed);
  const outcome = await Promise.race([run.then(() => 'finished'), new Promise((r) => setTimeout(() => r('killed'), 300))]);
  assertEquals(outcome, 'killed');
  assertEquals(writes.length, 1, 'only the mark was written before the kill');
  const d = writes[0].source_docs.docs[0];
  assertEquals([d.path, d.status, d.trades.length], ['profiles/7/p.pdf', 'reading', 0]);
});
