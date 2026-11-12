// supplier_doc_trades — a supplier's document is read by CODE into text, and the MODEL reads all his documents together; code
// only checks what the model says (ruling 1627, 11 Nov 2026). Never a trade or a service from the document's words by code.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/supplier_doc_trades.test.ts
// The reading of several documents together, the six paid cases and the "General Trading" licence are in
// the_model_reads_the_suppliers_documents_together.test.ts.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { mergeEvidence, modelReadText, proposedFrom, readDocForTrades, WORD_READ, type DocEvidence, type TradeResolveDeps } from './supplier_doc_trades.ts';
import { fakeReader } from './supplier_profile_reading.test_reader.ts';
import type { Taxonomy } from './supplier_profile_reading.ts';
import { makeDrawingPdf } from './pdf_measure.fixtures.ts';
import { sourceDocsStoreRpc } from './source_docs_store_stub.ts';

const TAX: Taxonomy = { trades: [
  { code: 'hvac', label: 'HVAC', services: [{ key: 'hvac.chiller_maintenance', label: 'Chiller maintenance' }] },
  { code: 'plumbing', label: 'Plumbing', services: [{ key: 'plumbing.drainage', label: 'Drainage works' }] },
  { code: 'electrical', label: 'Electrical', services: [] },
  { code: 'aluminium', label: 'Aluminium', services: [] },
], adjacent: [] };
/** A model that answers `answer`, given back through the two steps and code's checks (reader @5, supplier_profile_reading.test_reader). */
type Answer = { trades: { code: string; reason?: string; quotes?: { text: string; form?: string }[]; services?: { key: string; quote: string; licence?: string }[] }[];
  supply_only?: boolean | null; licence_activities?: string[]; licence?: 'yes' | 'partly' | 'no' | 'no_licence' };
const model = (answer: Answer, seen: string[] = []): TradeResolveDeps =>
  ({ readProfile: fakeReader(() => ({ trades: answer.trades.map((t) => ({ code: t.code, quote: t.quotes?.[0]?.text ?? '', quotes: (t.quotes ?? []).map((q) => q.text), services: t.services })),
    supply_only: answer.supply_only, licence_activities: answer.licence_activities, licence: answer.licence }), { seen, taxonomy: TAX }) });
const offline = (seen: string[] = []): TradeResolveDeps =>
  ({ readProfile: fakeReader(() => ({ ok: false, error: 'model unavailable (503): offline test' }), { seen }) });
const codes = (h: { code: string }[]) => h.map((x) => x.code).sort();

Deno.test('a PDF with a text layer is read by code, given to the model, and what it understood comes back proven by its line', async () => {
  const pdf = makeDrawingPdf(['ZZ DEMO COMPANY PROFILE', 'HVAC', 'Chiller maintenance for villas and towers'], '');
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'profiles/1/p.pdf', name: 'p.pdf', kind: 'profile', bytes: pdf, mime: 'application/pdf' },
    model({ trades: [{ code: 'hvac', quotes: [{ text: 'HVAC', form: 'heading' }], reason: 'its services heading',
      services: [{ key: 'hvac.chiller_maintenance', quote: 'Chiller maintenance for villas and towers', licence: 'unclear' }] }] }, seen));
  assertEquals([ev.status, ev.format, ev.choice], ['read', 'pdf', 'on']);
  assert(seen[0].startsWith('=== profile: p.pdf ==='), seen[0].slice(0, 80));
  assertEquals(codes(ev.trades), ['hvac']);
  // reader @5: a trade's line is the sentence of the first claim it was read from (the reading quotes services, not headings)
  assertEquals([ev.trades[0].via, ev.trades[0].snippet], ['model_choice', 'Chiller maintenance for villas and towers']);
  assertEquals((ev.services || []).map((x) => [x.key, x.via, x.snippet]), [['hvac.chiller_maintenance', 'model', 'Chiller maintenance for villas and towers']]);
  assert(ev.text?.includes('Chiller maintenance'), 'the text code read travels with the evidence in memory (proposeFromRead strips it before storing)');
});

Deno.test('no model: nothing is guessed from the words; the document says it is still being read', async () => {
  const pdf = makeDrawingPdf(['ZZ DEMO COMPANY PROFILE', 'HVAC', 'Air conditioning and chiller maintenance', 'Plumbing and drainage'], '');
  const ev = await readDocForTrades({ path: 'profiles/1/p.pdf', name: 'p.pdf', kind: 'profile', bytes: pdf, mime: 'application/pdf' }, offline());
  assertEquals([ev.trades, ev.services ?? [], ev.choice], [[], [], 'unavailable']);
  assert(/^still being read: /.test(ev.reason ?? ''), ev.reason);
  const none = await readDocForTrades({ path: 'profiles/1/p.pdf', name: 'p.pdf', kind: 'profile', bytes: pdf, mime: 'application/pdf' }, {});
  assertEquals([none.trades, none.choice], [[], 'unavailable'], 'with no chooser at all nothing is proposed either');
});

Deno.test('the model\'s invented line and a key outside the catalogue are dropped by code, never repaired', async () => {
  const ev = await readDocForTrades({ path: 'profiles/1/p.txt', name: 'p.txt', kind: 'profile', photo_text: 'ZZ DEMO LLC\nOUR SERVICES\nHVAC\nChiller maintenance' },
    model({ trades: [
      { code: 'hvac', quotes: [{ text: 'HVAC', form: 'heading' }], reason: 'r', services: [
        { key: 'hvac.chiller_maintenance', quote: 'Chiller maintenance', licence: 'covered' },
        { key: 'hvac.duct_cleaning', quote: 'Chiller maintenance', licence: 'covered' },            // not a service of hvac in the catalogue
        { key: 'plumbing.drainage', quote: 'Chiller maintenance', licence: 'covered' },             // another trade's service
      ] },
      { code: 'plumbing', quotes: [{ text: 'Plumbing and drainage works', form: 'list_item' }], reason: 'r' },   // not in the document
      { code: 'recording_studios', quotes: [{ text: 'HVAC', form: 'heading' }], reason: 'r' },                // not an active code
    ] }));
  assertEquals(codes(ev.trades), ['hvac']);
  assertEquals((ev.services || []).map((x) => x.key), ['hvac.chiller_maintenance']);
  const why = (ev.rejected || []).map((r) => r.code).sort();
  // reader @5: a trade code that is not ours is read as no trade (never the nearest), so it proposes nothing and is not a refusal
  assertEquals(why, ['hvac.duct_cleaning', 'plumbing', 'plumbing.drainage']);
});

// CORRECTED 12 Nov 2026 (rulings 1663/1664, LLM-first audit A4): "supply only" was a word list over the catalogue's lines (a trading word
// and no installation word); it is the READING's answer now. With no model nothing says supply only; the reading's answer is laid on the
// catalogue as it gave it (the answers below are stand-ins for the model, written for this test).
Deno.test('a catalogue is given to the model without its spec rows or contact lines, and supply only is what the reading says', async () => {
  const text = 'ZZ DEMO GENERAL TRADING LLC\nImporter and wholesaler\nHVAC\nDVR Storage Upto 6TB\nTel +971 4 000 0000';
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'catalogs/1/c.txt', name: 'c.txt', kind: 'catalogue', photo_text: text }, offline(seen));
  assertEquals(ev.supply_only, undefined, 'no model, no answer: nothing says supply only');
  assert(!/6TB|Tel/.test(seen[0]), 'a spec row or a contact line reached the model: ' + seen[0]);
  const trader = await readDocForTrades({ path: 'catalogs/1/c.txt', name: 'c.txt', kind: 'catalogue', photo_text: text },
    model({ trades: [{ code: 'hvac', quotes: [{ text: 'HVAC', form: 'heading' }], reason: 'r' }], supply_only: true }));
  assertEquals(trader.supply_only, true);
  // the audit's input: a "General Trading LLC" that cleans water tanks; the word list said supply only, the reading says it does the work
  const tanks = 'ZZ DEMO Al Noor General Trading LLC – we clean water tanks and do pest control\nWater tank cleaning';
  const words = await readDocForTrades({ path: 'catalogs/1/t.txt', name: 't.txt', kind: 'catalogue', photo_text: tanks },
    model({ trades: [{ code: 'cleaning', quotes: [{ text: 'Water tank cleaning', form: 'heading' }], reason: 'r' }], supply_only: false }));
  assertEquals(words.supply_only, false);
});

Deno.test('a scan with no text layer is needs_ocr, never a false zero, and the model is not asked about it', async () => {
  const scan = makeDrawingPdf([], '0.7 w 100 100 141.73 113.39 re S');
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'catalogs/1/s.pdf', name: 's.pdf', kind: 'catalogue', bytes: scan, mime: 'application/pdf' }, offline(seen));
  assertEquals([ev.status, ev.trades, seen.length], ['needs_ocr', [], 0]);
});

Deno.test('a refused file is unreadable with the reason', async () => {
  const html = new TextEncoder().encode('<html><script>alert(1)</script></html>');
  const ev = await readDocForTrades({ path: 'catalogs/1/x.pdf', name: 'x.pdf', kind: 'catalogue', bytes: html, mime: 'application/pdf' }, offline());
  assertEquals(ev.status, 'unreadable');
  assert(ev.reason && ev.reason.length > 0);
});

Deno.test('a new licence replaces the old one; catalogues accumulate; proposal is the union', () => {
  const e = (path: string, kind: DocEvidence['kind'], c: string[]): DocEvidence =>
    ({ path, name: path, kind, status: 'read', read_at: 'x', choice: 'on', trades: c.map((code) => ({ code, via: 'model_choice', phrases: [code], snippet: code })) });
  const prev = [e('licenses/1/a.pdf', 'licence', []), e('catalogs/1/c1.pdf', 'catalogue', ['hvac'])];
  const merged = mergeEvidence(prev, [e('licenses/1/b.pdf', 'licence', []), e('catalogs/1/c2.pdf', 'catalogue', ['aluminium'])]);
  assertEquals(merged.map((d) => d.path).sort(), ['catalogs/1/c1.pdf', 'catalogs/1/c2.pdf', 'licenses/1/b.pdf']);
  assertEquals(proposedFrom(merged), ['aluminium', 'hvac']);
});

Deno.test('evidence an older reader took from alias words is kept as a record but proposes nothing; a model reading is kept', () => {
  // reader @2 wrote no exact/meaning fields and no model choice; its trades were alias hits
  const old: DocEvidence = { path: 'catalogs/1/old.pdf', name: 'old.pdf', kind: 'catalogue', status: 'read', read_at: 'x',
    trades: [{ code: 'hvac', via: 'model_choice', phrases: ['chiller'], snippet: 'chiller' }] };
  const read: DocEvidence = { ...old, path: 'catalogs/1/new.pdf', choice: 'on' };
  const merged = mergeEvidence([old, read], []);
  assertEquals(merged.map((d) => [d.path, d.trades.length, d.reason ?? null]), [['catalogs/1/old.pdf', 0, WORD_READ], ['catalogs/1/new.pdf', 1, null]]);
  assertEquals(proposedFrom(merged), ['hvac']);
});

// 7 Oct 2026 (sales_engineer, accuracy suite ledger 1162).
import { withoutCredentialLines } from './supplier_doc_trades.ts';
Deno.test('a licence alone is not given to the model: it says what the company may do, not what it does; its activities are kept', async () => {
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'l', name: 'l.jpg', kind: 'licence', photo_text: 'Company Name: ZZ DEMO Hvac Plumbing LLC\nActivities: Electrical, Aluminium' }, offline(seen));
  assertEquals([ev.status, ev.trades, seen.length], ['read', [], 0]);
  assertEquals(ev.activities, ['Electrical', 'Aluminium']);
  assert(/not what it does/.test(ev.reason ?? ''), ev.reason);
});
Deno.test('a certificate the company holds is a credential, not a service; a certification body keeps its line', () => {
  assertEquals(withoutCredentialLines('Plumbing works\nCertifications\n- ISO 9001:2015 quality management\nHVAC'), 'Plumbing works\nHVAC');
  assertEquals(withoutCredentialLines('ISO 9001:2015 certification services for contractors'), 'ISO 9001:2015 certification services for contractors');
});

Deno.test('an image-only profile: what the vision model read is what the reader model is given (ruling 1177)', async () => {
  const scan = makeDrawingPdf([], '0.7 w 100 100 141.73 113.39 re S');
  const seen: string[] = [];
  const prof = await readDocForTrades({ path: 'profiles/1/s.pdf', name: 's.pdf', kind: 'profile', bytes: scan, mime: 'application/pdf',
    photo_text: modelReadText('profile', ['Plumbing', 'HVAC']) },
    model({ trades: [{ code: 'hvac', quotes: [{ text: 'HVAC', form: 'list_item' }], reason: 'r' }, { code: 'plumbing', quotes: [{ text: 'Plumbing', form: 'list_item' }], reason: 'r' }] }, seen));
  // CORRECTED 12 Nov 2026 (review of branch 2): a bare trade name with no service of it ("HVAC") is too broad to list; it is asked
  // (a trade_services card), never put on his list. What this test holds is that the picture's words are what the model is given.
  assertEquals([prof.status, prof.source, codes(prof.trades)], ['read', 'photo_text', []]);
  assert(seen[0].includes('Plumbing\nHVAC'), seen[0]);
  // nothing read -> nothing invented, and the scan stays needs_ocr rather than a false zero
  assertEquals(modelReadText('licence', []), undefined);
  const none = await readDocForTrades({ path: 'licenses/1/s.pdf', name: 's.pdf', kind: 'licence', bytes: scan, mime: 'application/pdf', photo_text: modelReadText('licence', null) }, offline());
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
// ── A KILLED PARSE LEAVES THE DOCUMENT HELD (review of #1404) ───────────────────────────────────────────────────────
import { proposeTradesFromDocs } from './supplier_doc_trades.ts';
Deno.test('a read killed partway (the worker dies at its CPU cap) leaves the document held as "reading"', async () => {
  const writes: { source_docs: { docs: { path: string; status: string; trades: unknown[] }[] } }[] = [];
  const admin = { from: (_t: string) => ({
    select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null }) }) }),
  }), rpc: sourceDocsStoreRpc(() => null, (n) => { writes.push(structuredClone(n) as typeof writes[number]); }), storage: { from: () => ({ upload: async () => ({ error: null }), download: async () => ({ data: null }) }) } };
  // The model never answers: the worker is killed here, so nothing after this point runs (no catch, no final write).
  const killed: TradeResolveDeps = { readProfile: () => new Promise(() => {}) };
  const pdf = makeDrawingPdf(['ZZ DEMO PROFILE', 'Chiller maintenance for villas and towers'], '');
  const run = proposeTradesFromDocs(admin, 7, [{ path: 'profiles/7/p.pdf', name: 'p.pdf', kind: 'profile', bytes: pdf, mime: 'application/pdf' }], killed);
  const outcome = await Promise.race([run.then(() => 'finished'), new Promise((r) => setTimeout(() => r('killed'), 300))]);
  assertEquals(outcome, 'killed');
  assertEquals(writes.length, 1, 'only the mark was written before the kill');
  const d = writes[0].source_docs.docs[0];
  assertEquals([d.path, d.status, d.trades.length], ['profiles/7/p.pdf', 'reading', 0]);
});

// ── THE READING BUDGET AND THE SIZE REFUSAL (review of #1404) ───────────────────────────────────────────────────────
import { pdfjsText, PDFJS_BUDGET_MS } from './doc_read/pdf.ts';
import { LIMITS } from './doc_read/types.ts';
/** A PDF of `n` pages, each printing "Page k fire pumps" in Helvetica. */
function pagesPdf(n: number, line = (k: number) => `Page ${k} fire pumps`): Uint8Array {
  const objs: string[] = ['<< /Type /Catalog /Pages 2 0 R >>', ''];
  const kids: string[] = [];
  for (let k = 1; k <= n; k++) {
    const ops = `BT /F1 12 Tf 72 700 Td (${line(k)}) Tj ET`;
    const page = objs.length + 1; kids.push(`${page} 0 R`);
    objs.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents ${page + 1} 0 R /Resources << /Font << /F1 ${3 + 2 * n} 0 R >> >> >>`);
    objs.push(`<< /Length ${ops.length} >>\nstream\n${ops}\nendstream`);
  }
  objs[1] = `<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${n} >>`;
  objs.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  let pdf = '%PDF-1.4\n'; const at: number[] = [];
  objs.forEach((o, i) => { at.push(pdf.length); pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const x = pdf.length;
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${at.map((v) => String(v).padStart(10, '0') + ' 00000 n \n').join('')}trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${x}\n%%EOF`;
  return new TextEncoder().encode(pdf);
}
Deno.test('the pdf.js read stops starting pages once its CPU budget is spent, and says how far it got', async () => {
  let t = 0; const clock = () => (t += 300);   // every look at the clock costs 300 ms of parse time
  const r = await pdfjsText(pagesPdf(6), 250, PDFJS_BUDGET_MS, clock);
  assertEquals(r.status, 'text');
  assertEquals(r.of, 6);
  assert(r.pages >= 1 && r.pages < 6, `read ${r.pages} of 6`);
  assert(r.text.includes('Page 1 fire pumps') && !r.text.includes('Page 6'), r.text);
  const all = await pdfjsText(pagesPdf(6));
  assertEquals([all.pages, all.of], [6, 6]);
});
Deno.test('a file over 25 MB is refused before pdf.js opens it, and is held unreadable, never read as a scan', async () => {
  const big = new Uint8Array(LIMITS.maxBytes + 1); big.set(new TextEncoder().encode('%PDF-1.4\n'));
  const r = await pdfjsText(big);
  assertEquals([r.status, r.pages], ['failed', 0]);
  assert(/over the .* read limit/.test(r.detail || ''), r.detail);
  // A supplier's paper is read up to 100 MB (19 Oct 2026, LIMITS.maxPaperBytes); past that it is held unreadable too.
  const huge = new Uint8Array(LIMITS.maxPaperBytes + 1); huge.set(new TextEncoder().encode('%PDF-1.4\n'));
  const ev = await readDocForTrades({ path: 'profiles/1/big.pdf', name: 'big.pdf', kind: 'profile', bytes: huge, mime: 'application/pdf' }, offline());
  assertEquals(ev.status, 'unreadable');
  assert(/file_too_large/.test(ev.reason || ''), ev.reason);
});
Deno.test('a busy worker that spends the budget opening the file still reads page 1, never calling a text PDF a scan (N01)', async () => {
  let t = 0; const clock = () => (t += 5_000);   // the open alone is over budget
  const r = await pdfjsText(pagesPdf(6), 250, PDFJS_BUDGET_MS, clock);
  assertEquals(r.status, 'text');
  assert(r.text.includes('Page 1 fire pumps'), r.text);
});

// Review of #1483 held a document whose readings agreed on no trade ('held', a doc_trades_held item), and the supplier was told
// "still reading" for ever (4 of 12 hard profiles, 12 Nov 2026). CORRECTED 12 Nov 2026 (ruling 1647): reader @5 reads once and never
// holds; a reading that names nothing is laid 'on' with no trade, and the reading drafts the question "what does your company do".
Deno.test('a document whose reading names nothing is never held: it is read, and the question "what does your company do" is drafted', async () => {
  const deps = { readProfile: fakeReader(() => ({ trades: [] })) };
  const ev = await readDocForTrades({ path: 'profiles/7/p.pdf', name: 'p.pdf', kind: 'profile', photo_text: undefined, ocr_text: 'ZZ DEMO Doors and Kitchens LLC. '.repeat(10) }, deps);
  assertEquals([ev.status, ev.choice, ev.trades.length, ev.held_readings], ['read', 'on', 0, undefined]);
  const { readTogether } = await import('./supplier_doc_trades.ts');
  const r = await readTogether([{ ...ev, text: 'ZZ DEMO Doors and Kitchens LLC. '.repeat(10) }], deps, 'ZZ DEMO');
  assert(r.ok && r.profile);
  assertEquals(r.profile.questions.map((q) => q.kind), ['nothing']);
});
Deno.test('a scan with a stray text layer is read from the OCR, not from its 20 stray characters (M12)', async () => {
  let seen = '';
  const deps = { readProfile: fakeReader((t: string) => { seen = t; return { trades: [] }; }) } as unknown as TradeResolveDeps;
  const ocr = 'ZZ DEMO Group of Companies. GENERAL CONTRACTING. TURNKEY CONTRACTS. Portable cabins, Camps & Mobile Houses. '.repeat(4);
  // M12's real stray layer, as the reader reads it: "58" and "GLOBAL REACH" - 13 letters and digits, under the 200 threshold
  await readDocForTrades({ path: 'profiles/9/s.pdf', name: 's.pdf', kind: 'profile', bytes: pagesPdf(1, () => '58 GLOBAL REACH'), mime: 'application/pdf', ocr_text: ocr }, deps);
  assert(seen.includes('Portable cabins'), seen.slice(0, 200));
});


Deno.test('a licence keeps its activities as printed, for the licence-vs-profile check, and proposes no service', async () => {
  const lic = makeDrawingPdf(['TRADE LICENCE', 'Licence No: 123456', 'Activities: HVAC'], '');
  const ev = await readDocForTrades({ path: 'licences/1/l.pdf', name: 'l.pdf', kind: 'licence', bytes: lic, mime: 'application/pdf' }, offline());
  assertEquals(ev.status, 'read');
  assert((ev.activities || []).length > 0, 'the activities were not kept: ' + JSON.stringify(ev));
  assertEquals(ev.services, undefined);
});
