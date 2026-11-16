// office — Word, PowerPoint, OpenDocument and spreadsheet files, read with no model.
//
// WHY. Customers send BOQs as .docx tables, tender packs as .pptx, and Arabic-market offices save
// .odt/.ods from LibreOffice. Before 14 Sep 2026 only spreadsheets and PDF text layers were read.
//
// WHAT IT READS.
//   readDocx     word/document.xml in body order (paragraphs; w:tab -> tab, w:br/w:cr -> newline;
//                w:tbl -> a table AND tab-joined lines), then headers, footnotes and endnotes.
//   readPptx     ppt/slides/slideN.xml in NUMERIC order (slide10 after slide2), a:p text, a:tbl tables.
//   readOdf      content.xml of odt/ods/odp: text:p / text:h lines (text:s, text:tab, text:line-break),
//                table:table rows; number-columns-repeated capped at 1024 cells, trailing blanks and
//                empty repeated rows dropped (an .ods pads a sheet to 1,048,576 rows that way). Kind
//                comes from the `mimetype` entry.
//   readWorkbook xlsx / xls / ods through the REGISTERED workbook engine (workbook_engine.ts; SheetJS 0.20.3,
//                in this isolate or in doc_extract): the first 20 sheets, CACHED cell values only
//                (cellFormula:false), capped at LIMITS.maxTableRows rows via sheetRows.
//
// WHAT IT NEVER DOES. It never evaluates a formula, never loads or runs a macro — a file carrying a
// vbaProject.bin part (xlsm/docm/pptm, whatever it is named) is REFUSED as unsafe_file_content — and
// never resolves an external link, embedded object or template. Password-protected files (an OOXML
// "EncryptedPackage" inside OLE2, an ODF manifest with encryption-data) are refused as 'encrypted'.
// Deleted revisions (w:delText) and field codes (w:instrText) are not text.
// This file does not import SheetJS (16 Nov 2026): supplier_api's upload hit Supabase's limit (413 at 4.70 MB) and SheetJS was
// 503 KB of it. readWorkbook gets the parsed sheets from workbook_engine.ts; with no engine registered it refuses.
import { NO_WORKBOOK_READER, SHEET_LIMITS, workbookEngine, type SheetsRead } from './workbook_engine.ts';
import { looksMacroEnabled } from '../attachment.ts';
import { empty, LIMITS, ok, refuse, type Cell, type ReadContext, type ReadResult, type Refusal } from './types.ts';
import { findAll, local, parseXml, type XmlNode } from './xml.ts';
import { listZip, readZipEntry, type ZipEntry } from './zip.ts';
import { textSink } from './text.ts';

const utf8 = new TextDecoder('utf-8');
const isZip = (b: Uint8Array) => b[0] === 0x50 && b[1] === 0x4b && b[2] === 0x03 && b[3] === 0x04;
const isOle2 = (b: Uint8Array) => b[0] === 0xd0 && b[1] === 0xcf && b[2] === 0x11 && b[3] === 0xe0;
const VBA = /(^|\/)vbaProject\.bin$/i;

/** An OLE2 directory entry name is UTF-16LE; 'EncryptedPackage' is how Office stores a password-protected OOXML file. */
function hasUtf16(b: Uint8Array, s: string): boolean {
  const n = new Uint8Array(s.length * 2);
  for (let i = 0; i < s.length; i++) n[i * 2] = s.charCodeAt(i);
  outer: for (let i = 0; i <= b.length - n.length; i++) {
    for (let j = 0; j < n.length; j++) if (b[i + j] !== n[j]) continue outer;
    return true;
  }
  return false;
}

type Pkg = { entries: ZipEntry[]; text(name: string): Promise<string | null> };

async function openPackage(bytes: Uint8Array, what: string): Promise<Pkg | Refusal> {
  if (isOle2(bytes)) {
    return hasUtf16(bytes, 'EncryptedPackage')
      ? refuse('encrypted', `the ${what} is password-protected; an unprotected copy is needed`)
      : refuse('unsupported_format', `this is a legacy binary Office file, not a ${what} package`);
  }
  if (!isZip(bytes)) return refuse('unsupported_format', `the file is not a ${what} package (no zip signature)`);
  const l = listZip(bytes);
  if (!l.ok) return l;
  const vba = l.entries.find((e) => VBA.test(e.name));
  if (vba) return refuse('unsafe_file_content', `the ${what} contains a VBA macro project (${vba.name}); macro-enabled files are not read`);
  const byName = new Map(l.entries.map((e) => [e.name, e]));
  return {
    entries: l.entries,
    async text(name) { const e = byName.get(name); return e ? utf8.decode(await readZipEntry(bytes, e, LIMITS.maxEntryBytes)) : null; },
  };
}

async function guarded(kind: string, f: () => Promise<ReadResult>): Promise<ReadResult> {
  try { return await f(); } catch (e) { return refuse('unreadable', `the ${kind} could not be read: ${(e as Error).message}`); }
}

function capRows(rows: Cell[][], notes: string[]): Cell[][] {
  if (rows.length <= LIMITS.maxTableRows) return rows;
  notes.push(`a table of ${rows.length} rows stopped at ${LIMITS.maxTableRows}`);
  return rows.slice(0, LIMITS.maxTableRows);
}

/** Direct children named `name`, looking through content-control and row-group wrappers. */
const WRAP = new Set(['sdt', 'sdtContent', 'customXml', 'smartTag', 'table-header-rows', 'table-rows', 'table-row-group']);
function kids(n: XmlNode, name: string): XmlNode[] {
  const out: XmlNode[] = [];
  for (const c of n.children) {
    if (typeof c === 'string') continue;
    const l = local(c.name);
    if (l === name) out.push(c); else if (WRAP.has(l)) out.push(...kids(c, name));
  }
  return out;
}

/** WordprocessingML / DrawingML paragraph text: runs, tabs, breaks; never deleted text, field codes or tab-stop definitions. */
function runText(n: XmlNode): string {
  let s = '';
  const walk = (x: XmlNode) => {
    for (const c of x.children) {
      if (typeof c === 'string') continue;
      const l = local(c.name);
      if (l === 't') for (const t of c.children) s += typeof t === 'string' ? t : '';
      else if (l === 'tab') s += '\t';
      else if (l === 'br' || l === 'cr') s += '\n';
      else if (l !== 'delText' && l !== 'instrText' && l !== 'pPr' && l !== 'rPr') walk(c);
    }
  };
  walk(n);
  return s;
}

const tableOf = (tbl: XmlNode, para: (tc: XmlNode) => XmlNode[]): Cell[][] =>
  kids(tbl, 'tr').map((tr) => kids(tr, 'tc').map((tc) => para(tc).map(runText).join('\n').trim()));

export async function readDocx(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  return guarded('docx', async () => {
    const pkg = await openPackage(bytes, 'docx');
    if ('error' in pkg) return pkg;
    const main = await pkg.text('word/document.xml');
    if (main === null) return refuse('unsupported_format', 'no word/document.xml; this is not a Word document');
    const doc = empty('docx');
    const s = textSink();
    const walk = (n: XmlNode) => {
      for (const c of n.children) {
        if (typeof c === 'string') continue;
        const l = local(c.name);
        if (l === 'p') s.line(runText(c));
        else if (l === 'tbl') {
          const t = tableOf(c, (tc) => kids(tc, 'p'));
          if (!t.length) continue;
          for (const r of t) s.line(r.join('\t'));
          doc.tables.push(capRows(t, doc.notes));
        } else walk(c);
      }
    };
    walk(parseXml(main));
    const extra = pkg.entries.map((e) => e.name).filter((n) => /^word\/(header\d*|footnotes|endnotes)\.xml$/.test(n)).sort();
    for (const n of extra) walk(parseXml((await pkg.text(n)) ?? ''));
    doc.text = s.done(doc.notes);
    return ok(doc);
  });
}

export async function readPptx(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  return guarded('pptx', async () => {
    const pkg = await openPackage(bytes, 'pptx');
    if ('error' in pkg) return pkg;
    const slides = pkg.entries.map((e) => /^ppt\/slides\/slide(\d+)\.xml$/.exec(e.name)).filter((m): m is RegExpExecArray => !!m)
      .sort((a, b) => Number(a[1]) - Number(b[1]));
    if (!slides.length) return refuse('unsupported_format', 'no ppt/slides/slideN.xml; this is not a PowerPoint deck');
    const doc = empty('pptx');
    const s = textSink();
    for (const m of slides) {
      const x = parseXml((await pkg.text(m[0])) ?? '');
      s.line(`# Slide ${m[1]}`);
      for (const p of findAll(x, 'p')) { const t = runText(p); if (t.trim()) s.line(t); }
      for (const tbl of findAll(x, 'tbl')) { const t = tableOf(tbl, (tc) => findAll(tc, 'p')); if (t.length) doc.tables.push(capRows(t, doc.notes)); }
    }
    doc.text = s.done(doc.notes);
    return ok(doc);
  });
}

function odfText(n: XmlNode): string {
  let s = '';
  for (const c of n.children) {
    if (typeof c === 'string') { s += c; continue; }
    const l = local(c.name);
    if (l === 's') s += ' '.repeat(Math.min(Number(c.attrs['text:c']) || 1, 100));
    else if (l === 'tab') s += '\t';
    else if (l === 'line-break') s += '\n';
    else if (l !== 'annotation') s += odfText(c);
  }
  return s;
}

function odfTable(tbl: XmlNode, notes: string[]): Cell[][] {
  const rows: Cell[][] = [];
  for (const tr of kids(tbl, 'table-row')) {
    const row: Cell[] = [];
    for (const tc of tr.children) {
      if (typeof tc === 'string' || !['table-cell', 'covered-table-cell'].includes(local(tc.name))) continue;
      const vt = tc.attrs['office:value-type'];
      const v: Cell = (vt === 'float' || vt === 'percentage' || vt === 'currency') && tc.attrs['office:value'] !== undefined
        ? Number(tc.attrs['office:value']) : kids(tc, 'p').map(odfText).join('\n');
      const rep = Math.min(Number(tc.attrs['table:number-columns-repeated']) || 1, 1024);
      for (let k = 0; k < rep && row.length < 1024; k++) row.push(v);
    }
    while (row.length && row[row.length - 1] === '') row.pop();
    if (!row.length) continue;
    const rep = Number(tr.attrs['table:number-rows-repeated']) || 1;
    for (let k = 0; k < rep && rows.length <= LIMITS.maxTableRows; k++) rows.push(row);
  }
  return capRows(rows, notes);
}

export async function readOdf(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  return guarded('OpenDocument file', async () => {
    const pkg = await openPackage(bytes, 'OpenDocument file');
    if ('error' in pkg) return pkg;
    const mt = ((await pkg.text('mimetype')) ?? '').trim();
    const kind = mt.endsWith('.text') ? 'odt' : mt.endsWith('.spreadsheet') ? 'ods' : mt.endsWith('.presentation') ? 'odp' : 'odf';
    if (((await pkg.text('META-INF/manifest.xml')) ?? '').includes('encryption-data')) {
      return refuse('encrypted', 'the OpenDocument file is password-protected; an unprotected copy is needed');
    }
    const content = await pkg.text('content.xml');
    if (content === null) return refuse('unsupported_format', 'no content.xml; this is not an OpenDocument file');
    const doc = empty(kind);
    const s = textSink();
    const walk = (n: XmlNode) => {
      for (const c of n.children) {
        if (typeof c === 'string') continue;
        const l = local(c.name);
        if (l === 'p' || l === 'h') s.line(odfText(c));
        else if (l === 'table') {
          const t = odfTable(c, doc.notes);
          if (!t.length) continue;
          for (const r of t) s.line(r.join('\t'));
          doc.tables.push(t);
        } else if (l !== 'tracked-changes') walk(c);
      }
    };
    walk(parseXml(content));
    doc.text = s.done(doc.notes);
    return ok(doc);
  });
}

export async function readWorkbook(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  return guarded('workbook', async () => {
    let kind = 'xls';
    if (isZip(bytes)) {
      const l = listZip(bytes);
      if (!l.ok) return l;
      const vba = l.entries.find((e) => VBA.test(e.name));
      if (vba) return refuse('unsafe_file_content', `the workbook contains a VBA macro project (${vba.name}); macro-enabled files are not read`);
      kind = l.entries.some((e) => e.name === 'mimetype') ? 'ods' : l.entries.some((e) => e.name === 'xl/workbook.bin') ? 'xlsb' : 'xlsx';
    } else if (isOle2(bytes)) {
      if (hasUtf16(bytes, 'EncryptedPackage')) return refuse('encrypted', 'the workbook is password-protected; an unprotected copy is needed');
      const m = looksMacroEnabled(bytes, 'application/vnd.ms-excel');
      if (m) return refuse('unsafe_file_content', m);
    }
    const engine = workbookEngine();
    if (!engine) return refuse('unreadable', NO_WORKBOOK_READER);
    let wb: SheetsRead;
    try {
      wb = await engine.sheets(bytes);
    } catch (e) {
      const msg = (e as Error).message;
      return /password|encrypt/i.test(msg) ? refuse('encrypted', 'the workbook is password-protected; an unprotected copy is needed')
        : refuse('unreadable', `the workbook could not be read: ${msg}`);
    }
    const doc = empty(kind);
    const s = textSink();
    if (wb.names.length > SHEET_LIMITS.maxSheets) doc.notes.push(`${wb.names.length} sheets; only the first ${SHEET_LIMITS.maxSheets} were read`);
    for (const [i, name] of wb.names.slice(0, SHEET_LIMITS.maxSheets).entries()) {
      const sheet = wb.rows[i];
      if (!sheet) continue;
      const rows = capRows(sheet, doc.notes);
      if (!rows.length) continue;
      s.line(`# ${name}`);
      for (const r of rows) s.line(r.map((c) => (c ?? '')).join('\t'));
      doc.tables.push(rows);
    }
    doc.text = s.done(doc.notes);
    return ok(doc);
  });
}
