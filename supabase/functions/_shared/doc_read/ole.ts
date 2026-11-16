// ole — reads the two OLE2 compound-file formats customers still send: Word 97-2003 (.doc) and
// Outlook (.msg).
//
// WHY (14 Sep 2026). Specifications and BOQs arrive as .doc from older offices and as .msg when a
// customer drags an Outlook email onto the upload box. Both were stored unread. Every model route is
// on hold, so both are read here with the vendored SheetJS CFB (compound-file) reader and plain code.
//
// WHAT IT READS.
//   .doc  The piece table (FIB fcClx/lcbClx at 0x01A2/0x01A6 -> Clx -> Pcdt -> PlcPcd) in the table
//         stream the FIB names (fWhichTblStm, bit 0x0200 at 0x000A: 1Table, else 0Table). A piece is
//         cp1252 at fc/2 when bit 30 of its fc is set, else UTF-16LE at fc. Paragraph marks become
//         newlines; field codes are dropped and their shown result kept; cell marks (0x07) build
//         tables. When the piece table cannot be read (a pre-97 file, a damaged Clx), printable runs of
//         the WordDocument stream are returned with a note that the reading is approximate.
//   .msg  Subject, sender name and address, the plain body (else the HTML body, tags stripped), and
//         every attachment's data handed to ctx.readChild under its long (else short) filename.
//
// WHAT IT NEVER DOES. It refuses a .doc with a macro project (a Macros storage or a _VBA_PROJECT
// stream) or with the fEncrypted flag, and never runs anything. It does not scrub the sender (the
// caller does). Known limits, each noted rather than guessed: a .msg whose body exists only as
// compressed RTF (10090102) yields no body; an attached .msg (embedded storage, 3701000D) is not read;
// in a .doc an EMPTY table cell reads as a row end, because the row-end mark is told apart from a cell
// mark only by paragraph properties this reader does not parse.
// The CFB read itself comes from the registered workbook engine (workbook_engine.ts, 16 Nov 2026): this file does not
// import SheetJS, so a function that registers the remote engine (supplier_api) does not upload it.
import { NO_WORKBOOK_READER, workbookEngine } from './workbook_engine.ts';
import { capText, empty, LIMITS, ok, refuse, type Cell, type ReadContext, type ReadResult, type Refusal } from './types.ts';
import { attacher, stripHtml } from './email.ts';

const dec16 = new TextDecoder('utf-16le');
const dec1252 = new TextDecoder('windows-1252');

/** Every stream and storage keyed by its lowercased path below the root ('worddocument', 'macros/'), or why not. */
async function openOle(bytes: Uint8Array): Promise<Map<string, Uint8Array> | Refusal> {
  const engine = workbookEngine();
  if (!engine) return refuse('unreadable', NO_WORKBOOK_READER);
  let m: Map<string, Uint8Array> | null;
  try { m = await engine.compoundFile(bytes); } catch (e) { return refuse('unreadable', `the compound file could not be read: ${(e as Error).message}`); }
  return m ?? refuse('unreadable_file', 'not an OLE2 compound file');
}

/** The document's characters in CP order, from the piece table; null when it cannot be trusted. */
function pieceText(wd: Uint8Array, table: Uint8Array | undefined): string | null {
  const dv = new DataView(wd.buffer, wd.byteOffset, wd.byteLength);
  // wIdent 0xA5EC and nFib >= 0xC1 is Word 97 or later; Word 6/95 keep the piece table elsewhere.
  if (!table || dv.getUint16(0, true) !== 0xA5EC || dv.getUint16(2, true) < 0xC1) return null;
  const fcClx = dv.getUint32(0x1A2, true), lcbClx = dv.getUint32(0x1A6, true);
  if (!lcbClx || fcClx + lcbClx > table.length) return null;
  const t = new DataView(table.buffer, table.byteOffset + fcClx, lcbClx);
  let i = 0;
  while (i < lcbClx && t.getUint8(i) === 0x01) { const cb = t.getInt16(i + 1, true); if (cb < 0) return null; i += 3 + cb; } // Prc: skipped
  if (i + 5 > lcbClx || t.getUint8(i) !== 0x02) return null;
  const lcb = t.getUint32(i + 1, true), p = i + 5;
  if (lcb < 16 || (lcb - 4) % 12 || p + lcb > lcbClx) return null;
  const n = (lcb - 4) / 12;
  let s = '';
  for (let k = 0; k < n && s.length < LIMITS.maxTextChars; k++) {
    const cp0 = t.getUint32(p + 4 * k, true), cp1 = t.getUint32(p + 4 * (k + 1), true);
    if (cp1 < cp0) return null;
    const raw = t.getUint32(p + 4 * (n + 1) + 8 * k + 2, true);
    const comp = (raw & 0x40000000) !== 0, fc = raw & 0x3FFFFFFF;
    const len = Math.min(cp1 - cp0, LIMITS.maxTextChars);
    const start = comp ? Math.floor(fc / 2) : fc, end = start + (comp ? len : len * 2);
    if (end > wd.length) return null;
    s += (comp ? dec1252 : dec16).decode(wd.subarray(start, end));
  }
  return s;
}

/** Word's special characters to lines and tables: \r paragraph, \x07 cell / row end, \x13-\x15 fields. */
function wordText(raw: string): { text: string; tables: Cell[][][] } {
  const lines: string[] = [], tables: Cell[][][] = [];
  let buf = '', cells: string[] = [], table: string[][] | null = null, afterMark = false;
  const fields: boolean[] = []; // one per open field: false while in its code, true once in its result
  const endTable = () => { if (table) tables.push(table.slice(0, LIMITS.maxTableRows)); table = null; };
  for (const ch of raw) {
    if (ch === '\x13') { fields.push(false); continue; }
    if (ch === '\x14') { if (fields.length) fields[fields.length - 1] = true; continue; }
    if (ch === '\x15') { fields.pop(); continue; }
    if (fields.includes(false)) continue;
    if (ch === '\x07') {
      if (afterMark && !buf) { (table ??= []).push(cells); lines.push(cells.join('\t')); cells = []; afterMark = false; }
      else { cells.push(buf.trim()); buf = ''; afterMark = true; }
      continue;
    }
    if (ch === '\r' || ch === '\x0B' || ch === '\x0C') {
      if (cells.length) { buf += ' '; continue; } // a paragraph break inside a cell
      endTable(); lines.push(buf); buf = ''; afterMark = false; continue;
    }
    if (ch === '\x1E') { buf += '-'; afterMark = false; continue; }
    if (ch < ' ' && ch !== '\t') continue; // object anchors, footnote refs, soft hyphen
    buf += ch; afterMark = false;
  }
  if (cells.length) (table ??= []).push(cells);
  endTable();
  if (buf) lines.push(buf);
  return { text: lines.map((l) => l.trimEnd()).join('\n').replace(/\n{3,}/g, '\n\n').trim(), tables };
}

/** Last resort: printable runs, 8-bit (>= 6 chars) and UTF-16LE at both alignments (>= 4 chars). */
function printableRuns(wd: Uint8Array): string {
  const runs: string[] = [...(dec1252.decode(wd).match(/[\x20-\x7EÀ-ÿ]{6,}/g) ?? [])];
  for (const off of [0, 1]) {
    const b = wd.subarray(off, off + ((wd.length - off) & ~1));
    runs.push(...(dec16.decode(b).match(/[\x20-\x7EÀ-ÿ؀-ۿ]{4,}/g) ?? []));
  }
  return runs.join('\n');
}

export async function readDoc(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  const ole = await openOle(bytes);
  if (!(ole instanceof Map)) return ole;
  const wd = ole.get('worddocument');
  if (!wd || wd.length < 0x1AA) return refuse('unreadable_file', 'no Word 97-2003 WordDocument stream');
  if ([...ole.keys()].some((k) => k.startsWith('macros/') || /(^|\/)_vba_project$/.test(k))) {
    return refuse('unsafe_file_content', 'the document contains a VBA macro project');
  }
  const flags = new DataView(wd.buffer, wd.byteOffset, wd.byteLength).getUint16(0x0A, true);
  if (flags & 0x0100) return refuse('encrypted', 'the document is password-protected (fEncrypted)');

  const out = empty('doc');
  let raw: string | null = null;
  try { raw = pieceText(wd, ole.get(flags & 0x0200 ? '1table' : '0table')); } catch { raw = null; }
  let text: string;
  if (raw !== null) ({ text, tables: out.tables } = wordText(raw));
  else { text = printableRuns(wd); out.notes.push('the piece table could not be read; text was recovered from printable runs and the reading is approximate (order and tables may be lost)'); }
  const parts: string[] = [];
  if (!capText(parts, text, { n: 0 })) out.notes.push(`text truncated at ${LIMITS.maxTextChars} characters`);
  out.text = parts.join('');
  return ok(out);
}

export async function readMsg(bytes: Uint8Array, ctx: ReadContext): Promise<ReadResult> {
  const ole = await openOle(bytes);
  if (!(ole instanceof Map)) return ole;
  if (![...ole.keys()].some((k) => k.startsWith('__substg1.0_'))) return refuse('unreadable_file', 'no Outlook message properties');
  const str = (dir: string, id: string): string => {
    const w = ole.get(`${dir}__substg1.0_${id}001f`);
    if (w) return dec16.decode(w).replace(/\0+$/, '');
    const a = ole.get(`${dir}__substg1.0_${id}001e`);
    return a ? dec1252.decode(a).replace(/\0+$/, '') : '';
  };
  const out = empty('msg');
  const subject = str('', '0037'), name = str('', '0c1a'), email = str('', '5d01') || str('', '0c1f');
  let body = str('', '1000');
  const html = ole.get('__substg1.0_10130102');
  if (!body && html) {
    let h: string;
    try { h = new TextDecoder('utf-8', { fatal: true }).decode(html); } catch { h = dec1252.decode(html); }
    body = stripHtml(h);
  }
  if (!body && ole.has('__substg1.0_10090102')) out.notes.push('the message body is stored only as compressed RTF, which is not read');
  const from = email ? (name ? `${name} <${email}>` : email) : name;
  const head = [subject && `Subject: ${subject}`, from && `From: ${from}`].filter(Boolean).join('\n');
  const parts: string[] = [];
  if (!capText(parts, (head ? head + '\n\n' : '') + body.replace(/\r\n?/g, '\n'), { n: 0 })) out.notes.push(`text truncated at ${LIMITS.maxTextChars} characters`);
  out.text = parts.join('');

  const add = attacher(ctx, out);
  const dirs = [...ole.keys()].filter((k) => /^__attach_version1\.0_#[0-9a-f]{8}\/$/.test(k)).sort();
  for (const [i, d] of dirs.entries()) {
    const fname = str(d, '3707') || str(d, '3704') || `attachment-${i + 1}`;
    const data = ole.get(`${d}__substg1.0_37010102`);
    if (!data) { out.notes.push(`attachment ${fname} is an embedded message or object and was not read`); continue; }
    await add(data, fname);
  }
  return ok(out);
}
