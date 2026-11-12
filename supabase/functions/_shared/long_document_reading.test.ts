// A supplier's long profile and its licence are read whole, and what is not read is said (3 Nov 2026, sales_engineer).
// Each test replays a failure measured by scripts/e2e/document_reading_qualification.ts and failed on the code before the fix.
// deno test -A --no-lock --node-modules-dir=auto supabase/functions/_shared/long_document_reading.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { demoPdfPages } from '../../../scripts/lib/demo_pdf.mjs';
import { pdfjsText } from './doc_read/pdf.ts';
import { LIMITS } from './doc_read/types.ts';
import { readDocument } from './doc_read/index.ts';
import { sourceDocsStoreRpc } from './source_docs_store_stub.ts';
import { docPartiallyRead, readDocForTrades, type TradeResolveDeps } from './supplier_doc_trades.ts';
import { CHOICE_TEXT_MAX, inPool, modelText, quoteKey } from './supplier_trade_choice.ts';
import { fakeReader } from './supplier_profile_reading.test_reader.ts';
import { licenceFieldsFromText, readLicenceFields } from './document_expiry.ts';
// malware.ts (imported by supplier_docs_later) builds a client at import; nothing here calls it
Deno.env.set('SUPABASE_URL', Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:1');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? 'test');
const { stuckOf } = await import('./supplier_docs_later.ts');

const filler = (n: number): [string, number][] => [[`PROJECT REFERENCE SHEET ${n}`, 13], ...Array.from({ length: 5 }, (_, k) =>
  [`Project ${n}-${k}: ZZ DEMO Residential Tower, Jumeirah Village Circle, client ZZ DEMO Properties, consultant ZZ DEMO Engineering`, 9] as [string, number])];
const longProfile = (pages: number, at: number, lines: string[]) =>
  new Uint8Array(demoPdfPages(Array.from({ length: pages }, (_, i) => i + 1 === at ? lines.map((l) => [l, 10] as [string, number]) : filler(i + 1))));

Deno.test('a 300-page text profile is read to its last page (the page cap was 250: page 270 was never read)', async () => {
  const r = await pdfjsText(longProfile(300, 270, ['OUR SERVICES', 'Pest control for residential, commercial and food premises']), undefined, 60_000);
  assertEquals([r.status, r.of], ['text', 300]);
  assert(r.text.includes('Pest control for residential'), `read ${r.pages} of ${r.of} pages`);
});

Deno.test('the trade chooser is given the whole document: work stated on page 160 of 300 with no offer heading reaches the model', async () => {
  assertEquals(CHOICE_TEXT_MAX, LIMITS.maxTextChars);   // the model reads what code read, no less
  const line = 'Security systems division: CCTV, access control and intrusion alarms';
  const bytes = longProfile(300, 160, ['ELECTRICAL DIVISION', line]);
  let given = '';
  const deps = { services: [], budget: { left: 0 }, normTrades: async () => null, embed: async () => null,
    readProfile: fakeReader((text: string) => { given = modelText(text); return { trades: [] }; }) } as unknown as TradeResolveDeps;
  const read = await readDocument(bytes, 'p.pdf', 'application/pdf', 0, { textOnly: true, maxBytes: LIMITS.maxPaperBytes });
  assert(read.ok && read.text.includes(line), 'the reader read page 160');
  await readDocForTrades({ path: 'p', name: 'p.pdf', kind: 'profile', bytes, mime: 'application/pdf', read }, deps);
  assert((' ' + quoteKey(given) + ' ').includes(' ' + quoteKey(line) + ' '), `the model was given ${given.length} characters without page 160`);
});

Deno.test('a partial read says so on the document: pages read, pages in the file, and the reason', async () => {
  const deps = { services: [], budget: { left: 0 }, normTrades: async () => null, embed: async () => null,
    readProfile: fakeReader(() => ({ trades: [] })) } as unknown as TradeResolveDeps;
  const read = { ok: true as const, kind: 'pdf', text: 'OUR SERVICES\nPlumbing works', tables: [], quantities: [], children: [], needs: null, notes: [], pages: { read: 120, of: 300 } };
  const ev = await readDocForTrades({ path: 'p', name: 'p.pdf', kind: 'profile', read }, deps);
  assertEquals(ev.pages, { read: 120, of: 300 });
  assert(/read 120 of 300 pages/.test(ev.reason ?? ''), ev.reason);
  // a scan the model was sent only the first pages of (supplier_docs_later.readProfileByModel sets pages_read)
  const scan = await readDocForTrades({ path: 's', name: 's.pdf', kind: 'profile', photo_text: 'Our services\nPlumbing works', pages_read: { read: 30, of: 45 } }, deps);
  assertEquals(scan.pages, { read: 30, of: 45 });
  // a whole read carries no such mark
  const whole = await readDocForTrades({ path: 'w', name: 'w.pdf', kind: 'profile', read: { ...read, pages: { read: 300, of: 300 } } }, deps);
  assertEquals(whole.pages, undefined);
});

Deno.test('a 300-page profile denser than the reader text cap is read in chunks over sweep runs until its last page, nothing dropped', async () => {
  // 300 dense pages (about 1,500 characters each): more than the reader's text cap of 400,000 in one run; the services on page 290
  const dense = (n: number): [string, number][] => n === 290 ? [['OUR SERVICES', 13], ['Pest control for residential, commercial and food premises', 10]]
    : [[`PROJECT REFERENCE SHEET ${n}`, 13], ...Array.from({ length: 12 }, (_, k) =>
      [`Project ${n}-${k}: ZZ DEMO Residential Tower, Jumeirah Village Circle, client ZZ DEMO Properties, consultant ZZ DEMO Engineering`, 9] as [string, number])];
  const bytes = new Uint8Array(demoPdfPages(Array.from({ length: 300 }, (_, i) => dense(i + 1))));
  const given: string[] = [];
  const deps = { services: [], budget: { left: 0 }, normTrades: async () => null, embed: async () => null,
    readProfile: fakeReader((text: string) => { given.push(text); return /Pest control for residential/.test(text)
      ? { trades: [{ code: 'pest_control', quote: 'Pest control for residential, commercial and food premises', reason: 'listed service' }] }
      : { trades: [] }; }) } as unknown as TradeResolveDeps;
  let ev = await readDocForTrades({ path: 'profiles/7/d.pdf', name: 'd.pdf', kind: 'profile', bytes, mime: 'application/pdf' }, deps);
  assert(ev.pages && ev.pages.read < 300 && ev.pages.of === 300 && ev.resume, JSON.stringify([ev.pages, ev.resume]));
  assert(/the rest is being read/.test(ev.reason ?? ''), ev.reason);
  // the sweep continues it (stuckOf), run after run, from the page after the last one read; the ledger only moves forward
  let runs = 1;
  while (ev.resume && runs < 6) {
    const [next] = stuckOf([{ supplier_id: 7, source_docs: { docs: [ev] } }]);
    const doc = next.docs[0];
    assertEquals([doc.from_page, doc.gate], [ev.pages!.read + 1, false]);
    const was = ev.pages!.read;
    ev = await readDocForTrades({ ...doc, bytes, mime: 'application/pdf' }, deps);
    assert(!ev.pages || ev.pages.read > was, 'the ledger moved forward');
    runs++;
  }
  assertEquals([ev.status, ev.pages, ev.resume, runs >= 2], ['read', undefined, undefined, true]);
  assertEquals(ev.trades.map((t) => t.code), ['pest_control']);   // page 290, found in a later run and kept
  assert(given.every((t) => t.length <= LIMITS.maxTextChars + 1000));
});

Deno.test('a scan cut for the model is filed for the sales engineer with the unread pages, once', async () => {
  const deps = { services: [], budget: { left: 0 }, normTrades: async () => null, embed: async () => null,
    readProfile: fakeReader(() => ({ trades: [] })) } as unknown as TradeResolveDeps;
  const ev = await readDocForTrades({ path: 'profiles/7/s.pdf', name: 's.pdf', kind: 'profile', photo_text: 'Our services\nPlumbing works', pages_read: { read: 30, of: 45 } }, deps);
  assertEquals([ev.pages, ev.resume], [{ read: 30, of: 45 }, undefined]);
  const filed: Record<string, unknown>[] = [];
  const admin = { from: () => ({ select: () => ({ eq: () => ({ eq: () => ({ eq: () => ({ limit: async () => ({ data: filed.length ? [{ id: 1 }] : [] }) }) }) }) }),
    insert: async (row: Record<string, unknown>) => { filed.push(row); return {}; } }) };
  await docPartiallyRead(admin, 7, ev);
  await docPartiallyRead(admin, 7, ev);   // never filed twice
  assertEquals(filed.length, 1);
  assertEquals([filed[0].kind, (filed[0].detail as { pages_total: number }).pages_total], ['doc_partially_read', 45]);
});

Deno.test('a licence printing its activities one per line under the label reads every activity (it read none)', () => {
  const f = licenceFieldsFromText(['Licence No: 1100233', '', 'Business Activities:', '', 'Plumbing & Sanitary Installation', '', 'Electrical Fitting Contracting',
    '', 'Air-Conditioning, Ventilation & Air Filtration Systems Installation & Maintenance', '', '', '(fixture)'].join('\n'));
  assertEquals(f.activities, ['Plumbing & Sanitary Installation', 'Electrical Fitting Contracting', 'Air-Conditioning, Ventilation & Air Filtration Systems Installation & Maintenance']);
  // the list ends at the next labelled field
  assertEquals(licenceFieldsFromText('Activities:\nTiling Works\nExpiry Date: 31/08/2027').activities, ['Tiling Works']);
});

// A text PDF whose font is Type0 / Identity-H (two-byte glyph codes, text only through the ToUnicode CMap), built by hand: no font
// program is embedded, which pdf.js reads like any embedded subset (the codes map to letters through ToUnicode alone).
function identityHPdf(lines: string[]): Uint8Array {
  const chars = [...new Set(lines.join(''))];
  const code = (c: string) => (chars.indexOf(c) + 3).toString(16).padStart(4, '0');
  const content = 'BT\n' + lines.map((l, i) => `/F1 11 Tf 1 0 0 1 50 ${780 - 18 * i} Tm <${[...l].map(code).join('')}> Tj\n`).join('') + 'ET\n';
  const cmap = `/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def /CMapName /ZZ def /CMapType 2 def
1 begincodespacerange <0000> <FFFF> endcodespacerange
${chars.length} beginbfchar
${chars.map((c) => `<${code(c)}> <${c.charCodeAt(0).toString(16).padStart(4, '0')}>`).join('\n')}
endbfchar endcmap CMapName currentdict /CMap defineresource pop end end`;
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${content}endstream`,
    '<< /Type /Font /Subtype /Type0 /BaseFont /ZZDemoSans /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 7 0 R >>',
    '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /ZZDemoSans /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 8 0 R /DW 500 >>',
    `<< /Length ${cmap.length} >>\nstream\n${cmap}\nendstream`,
    '<< /Type /FontDescriptor /FontName /ZZDemoSans /Flags 32 /FontBBox [0 -200 1000 900] /ItalicAngle 0 /Ascent 900 /Descent -200 /CapHeight 700 /StemV 80 >>'];
  let pdf = '%PDF-1.4\n'; const offs: number[] = [];
  objs.forEach((o, i) => { offs.push(pdf.length); pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${offs.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('')}trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${pdf.length}\n%%EOF\n`;
  return new TextEncoder().encode(pdf);
}

Deno.test('a text licence written with an embedded (Identity-H) font is read by code (it read 1 of 8 fields)', async () => {
  const f = await readLicenceFields(identityHPdf(['TRADE LICENCE', 'Licence No: 1100236', 'Legal Name: ZZ DEMO Modern Print LLC',
    'Issuing Authority: Dubai Department of Economy and Tourism', 'Expiry Date: 31/08/2027', 'Business Activities: Plumbing & Sanitary Installation']), 'application/pdf');
  assertEquals([f.licence_no, f.legal_name_en, f.authority, f.expiry_date, f.activities], ['1100236', 'ZZ DEMO Modern Print LLC', 'Dubai Department of Economy and Tourism', '2027-08-31', ['Plumbing & Sanitary Installation']]);
});

Deno.test('the chooser asks at most CHOICE_CONCURRENCY parts at once, results in order', async () => {
  let live = 0, peak = 0;
  const out = await inPool([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 5, async (x) => { live++; peak = Math.max(peak, live); await new Promise((r) => setTimeout(r, 5)); live--; return x * 2; });
  assertEquals([peak, out[0], out[11]], [5, 2, 24]);
});

Deno.test('the lam-alef swap pdf.js makes is undone after a one-letter prefix and before a hamza alef (Arabic services reached the model misspelt)', async () => {
  const { arabicLigatureFix } = await import('./doc_read/pdf.ts');
  assertEquals(arabicLigatureFix('أنظمة مكافحة الحريق واإلنذار'), 'أنظمة مكافحة الحريق والإنذار');
  assertEquals(arabicLigatureFix('واالنتهاء'), 'والانتهاء');
  assertEquals(arabicLigatureFix('األساسات'), 'الأساسات');      // the word-start case measured on the BCG brochure, still undone
  assertEquals(arabicLigatureFix('أعمال الحديد'), 'أعمال الحديد');   // a real alef-lam inside a word is left
});

Deno.test('a scan read on a busy worker is a scan after its probe pages, never "could not be read" (it was held unreadable for good)', async () => {
  const blank = new Uint8Array(demoPdfPages(Array.from({ length: 20 }, () => [] as [string, number][])));
  // a budget already spent before the first page: the worst a loaded worker does
  const r = await pdfjsText(blank, undefined, 0);
  assertEquals([r.status, r.pages], ['no_text', 3]);
  const read = await readDocument(blank, 's.pdf', 'application/pdf', 0, { textOnly: true, maxBytes: LIMITS.maxPaperBytes });
  assert(read.ok && read.needs === 'ocr', JSON.stringify(read));
});

// 12 Nov 2026: the one-call chooser is deleted; the two-step reading reads a part that timed out in halves the same way (readInTwoSteps).
Deno.test('a part the gateway cannot answer before its deadline is read in halves, so the document is still read (85 MB brochure, 3 of 5 runs proposed nothing)', async () => {
  const { readInTwoSteps } = await import('./supplier_profile_reading.ts');
  const line = 'Pest control and fumigation for homes, offices and food outlets';
  const text = Array.from({ length: 70 }, (_, k) => `Project reference ${k}: ZZ DEMO tower, client ZZ DEMO Properties`).join('\n') + '\nOUR SERVICES\n' + line;
  const tax = { trades: [{ code: 'pest_control', label: 'Pest control', services: [{ key: 'pest_control.general_pest_control', label: 'General pest control' }] }], adjacent: [] as [string, string][] };
  const seen: number[] = [];
  const r = await readInTwoSteps([{ path: 'p', name: 'p.pdf', kind: 'profile', text }], 'ZZ DEMO Pest LLC', tax, async (step, _sys, t) => {
    if (step === 'map') return { ok: true, content: JSON.stringify({ map: [{ i: 1, keys: ['pest_control.general_pest_control'] }] }) };
    // the gateway refuses a long PART (its context opening aside): the part is what is read in halves
    const part = t.split('[The part to read and quote from:]\n').pop()!;
    seen.push(part.length);
    if (part.length > 3000) return { ok: false, error: 'model unavailable (502): gateway_deadline' };
    return { ok: true, content: JSON.stringify({ summary: '', evidence: t.includes(line) ? [{ words: 'Pest control', quote: line, basis: 'stated', trade: 'pest_control' }] : [], vague: [], also_ask: [], licence: { covers_profile: 'no_licence', note: '' } }) };
  });
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.ok && r.reading.evidence.map((e) => [e.words, e.keys]), [['Pest control', ['pest_control.general_pest_control']]]);
  assert(seen.some((n) => n > 3000) && seen.some((n) => n <= 3000), 'a refused part was retried in halves');
});

Deno.test('a model quote of an Arabic word is found in text where pdf.js swapped its lam-alef (real profile C05: refused 3 of 3)', async () => {
  const { checkReading } = await import('./supplier_profile_reading.ts');
  const text = 'وبصفتنا مقاوال رائدا في الهندسة والمشتريات والبناء\nخدماتنا\nأعمال المقاوالت العامة';
  const r = checkReading(JSON.stringify({ evidence: [{ words: 'General contracting', quote: 'أعمال المقاولات العامة', basis: 'stated', trade: 'general_contracting' }] }),
    [{ path: 'p', name: 'p.pdf', kind: 'profile', text }], new Set(['general_contracting']));
  assert(r.ok);
  assertEquals(r.ok && r.reading.evidence.map((e) => e.trade), ['general_contracting']);
});


Deno.test('a 1,100-page profile is complete at the 1,000-page cap: never selected again, the model never asked about an empty text, the unread pages filed once (review of #1833)', async () => {
  const { proposeTradesFromDocs } = await import('./supplier_doc_trades.ts');
  const { PDFJS_MAX_PAGES } = await import('./doc_read/pdf.ts');
  const OF = 1100, PER_RUN = 400;
  // the page reader, stubbed: at most PER_RUN pages a run, never past the cap, empty text when asked to start beyond it
  const reader = (from: number) => {
    const last = Math.min(from + PER_RUN - 1, PDFJS_MAX_PAGES, OF);
    const text = from > last ? '' : Array.from({ length: last - from + 1 }, (_, k) => `Page ${from + k}: ${from + k === 700 ? 'Pest control for residential premises' : 'ZZ DEMO reference project'}`).join('\n');
    return { ok: true as const, kind: 'pdf', text, tables: [], quantities: [], children: [], needs: null, notes: [], pages: { read: Math.max(last, from - 1), of: OF } };
  };
  let asked = 0;
  const deps = {
    readProfile: fakeReader((text: string) => { asked++; assert(text.trim(), 'the model was asked about an empty text');
      return { trades: /Pest control for residential/.test(text) ? [{ code: 'pest_control', quote: 'Pest control for residential premises', reason: 'listed' }] : [] }; }) } as unknown as TradeResolveDeps;
  // the text read so far is kept beside the file (supplier_doc_trades.saveText) and read with the next pages (ruling 1627)
  const files = new Map<string, string>();
  const storage = { from: () => ({ upload: async (p: string, b: Uint8Array) => { files.set(p, new TextDecoder().decode(b)); return { error: null }; },
    download: async (p: string) => ({ data: files.has(p) ? new Blob([files.get(p)!]) : null }) }) };
  let caps: Record<string, unknown> = {};
  const filed: Record<string, unknown>[] = [];
  const admin = { from: (t: string) => {
    const b: Record<string, unknown> = {};
    Object.assign(b, { select: () => b, eq: () => b,
      maybeSingle: async () => ({ data: t === 'supplier_capabilities' ? caps : t === 'leads' ? { company_name: 'ZZ DEMO Pest LLC' } : null }),
      limit: async () => ({ data: t === 'agent_actions' && filed.length ? [{ id: 1 }] : [] }),
      upsert: async (row: Record<string, unknown>) => { caps = { ...caps, ...row }; return {}; },
      insert: async (row: Record<string, unknown>) => { filed.push(row); return {}; } });
    return b;
  }, storage, rpc: sourceDocsStoreRpc(() => caps, (n) => { caps = { ...caps, ...n }; }) };
  const docs = () => (caps.source_docs as { docs: { status: string; resume?: boolean; pages?: { read: number; of: number }; trades: { code: string }[] }[] }).docs;
  let doc: Record<string, unknown> = { path: 'profiles/7/big.pdf', name: 'big.pdf', kind: 'profile', read: reader(1) };
  let runs = 0;
  for (;;) {
    runs++;
    const r = await proposeTradesFromDocs(admin as never, 7, [doc as never], deps);
    assert(r.ok, JSON.stringify(r));
    const [next] = stuckOf([{ supplier_id: 7, source_docs: caps.source_docs }]);
    if (!next || runs > 6) break;
    const c = next.docs[0];
    doc = { ...c, read: reader(c.from_page!) };
  }
  // 1-400, 401-800, 801-1000: three runs, then nothing is selected
  assertEquals([runs, stuckOf([{ supplier_id: 7, source_docs: caps.source_docs }]).length], [3, 0]);
  assertEquals([docs()[0].pages, docs()[0].resume, docs()[0].trades.map((t) => t.code)], [{ read: 1000, of: 1100 }, undefined, ['pest_control']]);
  assertEquals(filed.length, 1);
  assertEquals([filed[0].kind, (filed[0].detail as { pages_read: number }).pages_read], ['doc_partially_read', 1000]);
  // a continuation from page 1,001 (it reads nothing): no chooser call, resume false, the evidence kept, still filed once
  const askedBefore = asked;
  const again = await proposeTradesFromDocs(admin as never, 7, [{ path: 'profiles/7/big.pdf', name: 'big.pdf', kind: 'profile', from_page: 1001, prev: { ...docs()[0], resume: true } as never, read: reader(1001) }], deps);
  assert(again.ok);
  assertEquals([asked, docs()[0].resume, docs()[0].pages, docs()[0].trades.map((t) => t.code), filed.length], [askedBefore, undefined, { read: 1000, of: 1100 }, ['pest_control'], 1]);
  // a stored `resume` at the cap (written before this fix) is not selected either
  assertEquals(stuckOf([{ supplier_id: 7, source_docs: { docs: [{ ...docs()[0], resume: true }] } }]), []);
});
