// text — plain text, CSV and RTF, read with no model and no dependency.
//
// WHY. A BOQ pasted into Notepad, exported from an estimating tool as CSV, or saved from Word as RTF
// carries the same lines a customer would type. UAE files arrive in three encodings in practice:
// UTF-8, UTF-16 (Excel's "Unicode text") and windows-1256 (Arabic Windows' ANSI), so all three are
// decoded; a file that is not valid UTF-8 and whose high bytes read as Arabic under 1256 is 1256,
// otherwise windows-1252.
//
// WHAT IT READS. TXT: the decoded text. CSV: RFC 4180 fields (quotes, doubled quotes, line breaks in
// quotes), delimiter ',' ';' or tab chosen by count on line 1. RTF: body text, \par/\line breaks,
// \tab, \trowd...\cell...\row tables, \'hh bytes in the document codepage (\ansicpg, overridden per
// font by \fcharset — Word writes Arabic as \fcharset178 bytes under \ansicpg1252), \uN with its \ucN
// fallback skip.
//
// WHAT IT NEVER DOES. RTF: it skips every {\* } destination, font/colour/style tables, info, pictures,
// objects, field instructions (where HYPERLINK targets live — the visible field result is kept),
// headers and footers. Nothing is followed, embedded objects are not opened. Text stops at
// LIMITS.maxTextChars and tables at LIMITS.maxTableRows, each with a note.
import { capText, empty, LIMITS, ok, refuse, type Cell, type ReadContext, type ReadResult } from './types.ts';

/** Collects lines under the LIMITS.maxTextChars cap; `done()` adds the note when it bit. */
export function textSink() {
  const parts: string[] = [], used = { n: 0 };
  let capped = false;
  return {
    line(s: string) { if (!capped && !capText(parts, s + '\n', used)) capped = true; },
    done(notes: string[]) {
      if (capped) notes.push(`text stopped at ${LIMITS.maxTextChars} characters; the rest of the file was not read`);
      return parts.join('').replace(/\n$/, '');
    },
  };
}

/** Bytes to text: BOM first, then strict UTF-8, then windows-1256 if it reads as Arabic, else windows-1252. */
export function decodeText(b: Uint8Array): { text: string; encoding: string } {
  if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) return { text: new TextDecoder('utf-8').decode(b.subarray(3)), encoding: 'utf-8' };
  if (b[0] === 0xff && b[1] === 0xfe) return { text: new TextDecoder('utf-16le').decode(b.subarray(2)), encoding: 'utf-16le' };
  if (b[0] === 0xfe && b[1] === 0xff) return { text: new TextDecoder('utf-16be').decode(b.subarray(2)), encoding: 'utf-16be' };
  try { return { text: new TextDecoder('utf-8', { fatal: true }).decode(b), encoding: 'utf-8' }; } catch { /* legacy codepage */ }
  const ar = new TextDecoder('windows-1256').decode(b);
  let high = 0, arabic = 0;
  for (const x of b) if (x >= 0x80) high++;
  for (let i = 0; i < ar.length; i++) { const c = ar.charCodeAt(i); if (c >= 0x600 && c <= 0x6ff) arabic++; }
  return arabic * 2 >= high ? { text: ar, encoding: 'windows-1256' } : { text: new TextDecoder('windows-1252').decode(b), encoding: 'windows-1252' };
}

export async function readTxt(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  const { text, encoding } = decodeText(bytes);
  const doc = empty('txt', encoding === 'utf-8' ? [] : [`decoded as ${encoding}`]);
  const s = textSink();
  for (const l of text.split(/\r\n|\r|\n/)) s.line(l);
  doc.text = s.done(doc.notes);
  return ok(doc);
}

/** RFC 4180 rows; delimiter by count on line 1; stops at LIMITS.maxTableRows rows. */
export function parseDelimited(text: string): string[][] {
  const counts: Record<string, number> = { ',': 0, ';': 0, '\t': 0 };
  for (let i = 0, q = false; i < text.length && (q || (text[i] !== '\n' && text[i] !== '\r')); i++) {
    if (text[i] === '"') q = !q; else if (!q && text[i] in counts) counts[text[i]]++;
  }
  const d = [',', ';', '\t'].reduce((a, c) => (counts[c] > counts[a] ? c : a), ',');
  const rows: string[][] = [];
  let row: string[] = [], f = '', q = false;
  const endRow = () => { row.push(f); f = ''; if (row.length > 1 || row[0] !== '') rows.push(row); row = []; };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c !== '"') f += c;
      else if (text[i + 1] === '"') { f += '"'; i++; }
      else q = false;
    } else if (c === '"' && f === '') q = true;
    else if (c === d) { row.push(f); f = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      endRow();
      if (rows.length >= LIMITS.maxTableRows) return rows;
    } else f += c;
  }
  if (f !== '' || row.length) endRow();
  return rows;
}

export async function readCsv(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  const { text, encoding } = decodeText(bytes);
  const rows = parseDelimited(text);
  const doc = empty('csv', encoding === 'utf-8' ? [] : [`decoded as ${encoding}`]);
  if (rows.length >= LIMITS.maxTableRows) doc.notes.push(`table stopped at ${LIMITS.maxTableRows} rows`);
  const s = textSink();
  for (const r of rows) s.line(r.join('\t'));
  doc.text = s.done(doc.notes);
  if (rows.length) doc.tables.push(rows);
  return ok(doc);
}

// ── RTF ─────────────────────────────────────────────────────────────────────────────────────────
const SKIP = new Set(['fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object', 'objdata', 'fldinst', 'header', 'headerl', 'headerr', 'headerf',
  'footer', 'footerl', 'footerr', 'footerf', 'listtable', 'listoverridetable', 'revtbl', 'rsidtbl', 'themedata', 'colorschememapping', 'datastore',
  'latentstyles', 'xmlnstbl', 'generator', 'filetbl', 'nonshppict', 'shpinst', 'bkmkstart', 'bkmkend', 'annotation', 'atnid', 'atnauthor']);
const SYMBOL: Record<string, string> = { par: '\n', line: '\n', sect: '\n', page: '\n', tab: '\t', emdash: '—', endash: '–', bullet: '•',
  lquote: '‘', rquote: '’', ldblquote: '“', rdblquote: '”', emspace: ' ', enspace: ' ', qmspace: ' ' };
const CHARSET_CP: Record<number, number> = { 128: 932, 129: 949, 134: 936, 136: 950, 161: 1253, 162: 1254, 163: 1258, 177: 1255, 178: 1256, 186: 1257, 204: 1251, 222: 874, 238: 1250 };
const decoders = new Map<number, TextDecoder>();
function decoderFor(cp: number): TextDecoder {
  if (!decoders.has(cp)) {
    const label = cp === 932 ? 'shift_jis' : cp === 936 ? 'gbk' : cp === 949 ? 'euc-kr' : cp === 950 ? 'big5' : cp === 10000 ? 'macintosh' : `windows-${cp}`;
    let d: TextDecoder;
    try { d = new TextDecoder(label); } catch { d = new TextDecoder('windows-1252'); }
    decoders.set(cp, d);
  }
  return decoders.get(cp)!;
}

type Group = { skip: boolean; fonttbl: boolean; uc: number; font: number | null };

export async function readRtf(bytes: Uint8Array, _ctx: ReadContext): Promise<ReadResult> {
  let src = '';
  for (let i = 0; i < bytes.length; i += 8192) src += String.fromCharCode(...bytes.subarray(i, i + 8192));
  if (!src.startsWith('{\\rtf')) return refuse('not_rtf', 'the file does not start with {\\rtf');
  const doc = empty('rtf');
  const s = textSink();
  let ansi = 1252, deff = 0, curFont = 0, ucSkip = 0;
  const fontCp = new Map<number, number>();
  const stack: Group[] = [{ skip: false, fonttbl: false, uc: 1, font: null }];
  const g = () => stack[stack.length - 1];
  let line = '', cellBuf = '', intbl = false, cells: string[] = [], table: Cell[][] = [];
  let hex: number[] = [];
  const flushHex = () => {
    if (!hex.length) return;
    const f = g().font ?? deff;
    emit(decoderFor(fontCp.get(f) ?? ansi).decode(new Uint8Array(hex)));
    hex = [];
  };
  const endTable = () => {
    if (!table.length) return;
    if (table.length > LIMITS.maxTableRows) { doc.notes.push(`an RTF table stopped at ${LIMITS.maxTableRows} rows`); table.length = LIMITS.maxTableRows; }
    doc.tables.push(table); table = [];
  };
  function emit(t: string) {
    if (g().skip) return;
    if (intbl) { cellBuf += t; return; }
    if (table.length && t.trim()) endTable();
    for (const ch of t) { if (ch === '\n') { s.line(line); line = ''; } else line += ch; }
  }
  const word = /\\([a-zA-Z]{1,32})(-?\d{1,10})? ?/y;
  for (let i = 0; i < src.length;) {
    const c = src[i];
    if (c === '{') { flushHex(); stack.push({ ...g() }); i++; continue; }
    if (c === '}') { flushHex(); if (stack.length > 1) stack.pop(); i++; continue; }
    if (c === '\r' || c === '\n') { i++; continue; }
    if (c !== '\\') {
      flushHex();
      if (ucSkip > 0) ucSkip--; else emit(c);
      i++; continue;
    }
    const nx = src[i + 1];
    if (nx === "'") {
      const v = parseInt(src.slice(i + 2, i + 4), 16);
      i += 4;
      if (ucSkip > 0) { ucSkip--; continue; }
      if (Number.isFinite(v) && !g().skip) hex.push(v);
      continue;
    }
    if (nx === '*') { g().skip = true; i += 2; continue; }
    if (nx === '\\' || nx === '{' || nx === '}') { flushHex(); if (ucSkip > 0) ucSkip--; else emit(nx); i += 2; continue; }
    if (nx === '~') { flushHex(); emit(' '); i += 2; continue; }
    if (nx === '_') { flushHex(); emit('-'); i += 2; continue; }
    if (nx === '\n' || nx === '\r') { flushHex(); emit('\n'); i += 2; continue; }
    word.lastIndex = i;
    const m = word.exec(src);
    if (!m) { i += 2; continue; }
    i = word.lastIndex;
    flushHex();
    const w = m[1], n = m[2] === undefined ? null : Number(m[2]);
    if (ucSkip > 0 && w !== 'u') { ucSkip--; continue; }
    const grp = g();
    if (w === 'fonttbl') { grp.fonttbl = true; grp.skip = true; continue; }
    if (grp.fonttbl) {
      if (w === 'f' && n !== null) curFont = n;
      else if (w === 'fcharset' && n !== null && CHARSET_CP[n]) fontCp.set(curFont, CHARSET_CP[n]);
      continue;
    }
    if (SKIP.has(w)) { grp.skip = true; continue; }
    switch (w) {
      case 'bin': i += Math.max(0, n ?? 0); break;
      case 'ansicpg': if (n) ansi = n; break;
      case 'deff': deff = n ?? 0; break;
      case 'f': grp.font = n; break;
      case 'uc': grp.uc = n ?? 1; break;
      case 'u': { const cp = (n ?? 0) < 0 ? (n ?? 0) + 65536 : (n ?? 0); emit(String.fromCharCode(cp)); ucSkip = grp.uc; break; }
      case 'pard': intbl = false; break;
      case 'intbl': intbl = true; break;
      case 'cell': case 'nestcell': if (!grp.skip) { cells.push(cellBuf.trim()); cellBuf = ''; } break;
      case 'row': case 'nestrow':
        if (!grp.skip && cells.length) { if (line) { s.line(line); line = ''; } table.push(cells); s.line(cells.join('\t')); }
        cells = []; cellBuf = ''; break;
      default: if (SYMBOL[w] !== undefined) emit(SYMBOL[w]);
    }
  }
  flushHex();
  if (line) s.line(line);
  endTable();
  doc.text = s.done(doc.notes).split('\n').map((l) => l.trimEnd()).join('\n').replace(/\n{3,}/g, '\n\n').trim();
  return ok(doc);
}
