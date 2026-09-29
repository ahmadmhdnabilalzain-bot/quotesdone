// cad_file_redact — a DXF / DWG drawing, anonymised as a DXF FILE a supplier can open in any CAD program, and
// proved (28 Sep 2026, sales_engineer; founder ledger items 30, 31, 32, 580, 703).
//
// MEASURED BEFORE THIS FILE: doc_read/cad.ts had redactDxf (every free-text value through a caller's `redact`),
// but nothing called it — a CAD drawing reached a supplier only as cad_render.ts's JPEG. The file itself, with
// its layers, blocks and dimensions, was never sent, and nothing checked that a redacted file still counted the
// same. Three identity carriers redactDxf does not touch at all were also open: BLOCK names (a title block named
// after the consultant, a logo block named after the firm), the path of an attached image (IMAGEDEF), and any
// party the customer's seeds did not name (redactDxf only knew what it was told).
//
// WHAT IT DOES — deterministic, no model:
//  1. One ASCII DXF: a DWG is read by LibreDWG (doc_read/dwg.ts; past the edge ceiling the CAD worker reads it),
//     a binary DXF is converted (doc_read/cad.ts binaryDxfToAscii).
//  2. TERMS: the customer's seeds plus everything the file says about its own job (cad_identity.cadIdentityTerms:
//     every TEXT / MTEXT / ATTRIB on a title-block layer or inside a title-block block, ATTRIBs whose tag names a
//     party, "Client:" values, header $PROJECTNAME / $LASTSAVEDBY, DWGPROPS, xref paths).
//  3. NAMES: every layer and block name is rewritten to its CAD vocabulary (cad_identity.neutralCadName — the rule
//     the supplier's BOQ already follows), consistently in the table, in BLOCK/ENDBLK and in every entity that
//     names it, and made unique so two blocks never merge into one count. IMAGEDEF file paths are blanked.
//  4. TEXT: redactDxf with those terms — title-block text and attribute VALUES are emptied (the entity, its
//     insertion point and its tag stay, so nothing moves and nothing is renumbered), header variables blanked.
//  5. VERIFY (verifyCadRedaction): the output opens (our reader and cad_render's parser); every entity type in
//     order and every coordinate / size / angle group (codes 10-59, 110-149, 210-239) is the original's, pair
//     for pair; every take-off quantity is the original's (block counts through the rename map, and the full
//     multiset of quantities and units); and no identity is left in any string of the file. Any failure = hold.
//
// WHAT IT DOES NOT DO: write DWG (the supplier's copy of a DWG is the DXF of the same drawing — every CAD program
// opens it); rename STYLE / LTYPE / DIMSTYLE records (a record named after a party is caught by the residual scan
// and the file is HELD — ponytail: rename them through their reference codes 7 / 6 / 3 when a real file needs it);
// read an embedded OLE logo's bytes (OLE2FRAME code 310 is binary; the frame's layer and position are kept).
// deno-lint-ignore-file no-explicit-any
import { binaryDxfToAscii, readDxf, redactDxf } from './doc_read/cad.ts';
import { readDwg } from './doc_read/dwg.ts';
import { cadIdentityTerms, neutralCadName } from './cad_identity.ts';
import { redactText, residualScan, seedTerms } from './anonymise.ts';
import { parseDxf } from './cad_render.ts';

const isDwg = (b: Uint8Array) => /^AC10\d\d$/.test(new TextDecoder('latin1').decode(b.subarray(0, 6)));
const isBinaryDxf = (b: Uint8Array) => new TextDecoder('latin1').decode(b.subarray(0, 22)).startsWith('AutoCAD Binary DXF');
const KEEP_LAYER = new Set(['0', 'DEFPOINTS']);
const GEOMETRY = (c: number) => (c >= 10 && c <= 59) || (c >= 110 && c <= 149) || (c >= 210 && c <= 239);
const STRING = (c: number) => (c >= 1 && c <= 9) || (c >= 300 && c <= 309) || (c >= 410 && c <= 419) || (c >= 430 && c <= 439) || (c >= 470 && c <= 479) || c === 999 || (c >= 1000 && c <= 1009);

/** The ASCII DXF text of a CAD upload (DWG, binary DXF or ASCII DXF), or a reason it cannot be had here. */
export async function asciiDxfOf(bytes: Uint8Array, maxDwgBytes?: number): Promise<{ ok: true; dxf: string; from: 'dxf' | 'dxf_binary' | 'dwg' } | { ok: false; held: string; detail?: string }> {
  if (isDwg(bytes)) {
    const r = await readDwg(bytes, { filename: 'drawing.dwg', depth: 0 }, maxDwgBytes);
    if (!r.ok) return { ok: false, held: 'dwg_unreadable', detail: r.detail };
    if (!r.dxf_text) return { ok: false, held: 'dwg_not_read_here', detail: r.notes.join(' ').slice(0, 200) };
    return { ok: true, dxf: r.dxf_text, from: 'dwg' };
  }
  if (isBinaryDxf(bytes)) {
    try { return { ok: true, dxf: binaryDxfToAscii(bytes).dxf, from: 'dxf_binary' }; } catch (e) { return { ok: false, held: 'dxf_unreadable', detail: String((e as Error)?.message || e).slice(0, 160) }; }
  }
  const t = new TextDecoder('utf-8').decode(bytes);
  if (!t.slice(0, 4000).includes('SECTION')) return { ok: false, held: 'not_a_cad_file' };
  return { ok: true, dxf: t, from: 'dxf' };
}

type Pair = [number, string];
function pairsOf(dxf: string): { pairs: Pair[]; eol: string } {
  const eol = dxf.includes('\r\n') ? '\r\n' : '\n';
  const l = dxf.split(/\r?\n/);
  const pairs: Pair[] = [];
  for (let i = 0; i + 1 < l.length; i += 2) {
    const c = parseInt(l[i].trim(), 10);
    if (!Number.isFinite(c)) throw new Error(`dxf_unreadable: group code expected at line ${i + 1}`);
    pairs.push([c, l[i + 1]]);
  }
  return { pairs, eol };
}
const joinPairs = (p: Pair[], eol: string) => p.map(([c, v]) => `${String(c).padStart(3)}${eol}${v}`).join(eol) + eol;

/** Walk pairs with the entity type and the section each belongs to. */
function* walk(pairs: Pair[]): Generator<{ i: number; code: number; val: string; ent: string; section: string; table: string }> {
  let ent = '', section = '', table = '', pending = false;
  for (let i = 0; i < pairs.length; i++) {
    const [code, val] = pairs[i];
    if (code === 0) {
      ent = val.trim();
      if (ent === 'SECTION') pending = true; else if (ent === 'ENDSEC') section = '';
      if (ent === 'ENDTAB') table = '';
    } else if (pending && code === 2) { section = val.trim(); pending = false; continue; }
    if (section === 'TABLES' && ent === 'TABLE' && code === 2) table = val.trim();
    yield { i, code, val, ent, section, table };
  }
}

/** Layer and block names: each to its CAD vocabulary, unique, and the same everywhere it is named. */
export function renameMaps(pairs: Pair[]): { layers: Map<string, string>; blocks: Map<string, string> } {
  const layerNames = new Set<string>(), blockNames = new Set<string>();
  for (const w of walk(pairs)) {
    const v = w.val.trim();
    if (w.code === 8) layerNames.add(v);
    if (w.section === 'TABLES' && w.table === 'LAYER' && w.ent === 'LAYER' && w.code === 2) layerNames.add(v);
    if ((w.ent === 'BLOCK' || w.ent === 'INSERT') && w.code === 2) blockNames.add(v);
    if (w.section === 'TABLES' && w.table === 'BLOCK_RECORD' && w.ent === 'BLOCK_RECORD' && w.code === 2) blockNames.add(v);
  }
  const build = (names: Set<string>, keep: (n: string) => boolean, fallback: string) => {
    const m = new Map<string, string>(), used = new Set<string>();
    for (const n of names) if (keep(n)) { m.set(n, n); used.add(n.toUpperCase()); }
    for (const n of [...names].sort()) {
      if (m.has(n)) continue;
      const base = neutralCadName(n);
      let out = base === 'unnamed' ? fallback : base, k = 2;
      while (used.has(out.toUpperCase())) out = `${base === 'unnamed' ? fallback : base}-${k++}`;
      used.add(out.toUpperCase()); m.set(n, out);
    }
    return m;
  };
  return {
    layers: build(layerNames, (n) => KEEP_LAYER.has(n.toUpperCase()), 'LAYER'),
    // Anonymous blocks (*D1, *U2, *Model_Space) are the program's own; they name nobody.
    blocks: build(blockNames, (n) => n.startsWith('*') || n.startsWith('$'), 'BLOCK'),
  };
}

/** A party label written as its own TEXT ("CONSULTANT:") with the party in the next TEXT on the same line:
 *  cadIdentityTerms reads a label and its value only inside one string (measured on the ZZ DEMO sheet: the firm
 *  "ZZ DEMO ORBIT" beside a lone "CONSULTANT:" kept "ZZ DEMO" after redaction). Returns those values. */
export function splitLabelValues(pairs: Pair[]): string[] {
  type T = { x: number; y: number; h: number; s: string };
  const texts: T[] = [];
  let cur: T | null = null;
  for (const [c, v] of pairs) {
    if (c === 0) { if (cur && cur.s) texts.push(cur); cur = /^(?:TEXT|MTEXT)$/.test(v.trim()) ? { x: 0, y: 0, h: 0, s: '' } : null; continue; }
    if (!cur) continue;
    if (c === 10) cur.x = Number(v); else if (c === 20) cur.y = Number(v); else if (c === 40) cur.h = Number(v);
    else if (c === 1 || c === 3) cur.s += v;
  }
  if (cur && cur.s) texts.push(cur);
  const out: string[] = [];
  for (const l of texts) {
    if (!LONE_LABEL.test(l.s.trim())) continue;
    const h = l.h || 1;
    for (const t of texts) if (t !== l && t.x > l.x && t.x - l.x < 40 * h && Math.abs(t.y - l.y) <= 0.6 * h && t.s.trim().length >= 3) out.push(t.s.trim());
  }
  return out;
}
const LONE_LABEL = /^(?:client|owner|employer|customer|consultant|contractor|architect|engineer|developer|project(?:\s*(?:name|title))?|site(?:\s*address)?|location|address|drawn\s*by|checked\s*by|approved\s*by|designed\s*by|prepared\s*by|المالك|العميل|الاستشاري|المقاول|المشروع)\s*[:：]?$/i;

export type CadRedactResult =
  | { ok: true; dxf: string; bytes: Uint8Array; source: 'dxf' | 'dxf_binary' | 'dwg'; before_dxf: string; terms: string[]; layers: Map<string, string>; blocks: Map<string, string>; changed: number }
  | { ok: false; held: string; detail?: string };

const tidy = (s: string) => s.replace(/█+/g, '').replace(/\s{2,}/g, ' ').trim();

/** A CAD upload as an anonymised ASCII DXF. Fails closed (`ok:false`) whenever the file cannot be had or parsed. */
export async function redactCadFile(bytes: Uint8Array, seeds: string[], opts: { maxDwgBytes?: number } = {}): Promise<CadRedactResult> {
  const src = await asciiDxfOf(bytes, opts.maxDwgBytes);
  if (!src.ok) return src;
  try {
    const { pairs, eol } = pairsOf(src.dxf);
    const terms = [...new Set([...seeds, ...seedTerms({ extra: [...cadIdentityTerms(src.dxf), ...splitLabelValues(pairs)] })])];
    const { layers, blocks } = renameMaps(pairs);
    for (const w of walk(pairs)) {
      const v = w.val.trim();
      if (w.code === 8 && layers.has(v)) pairs[w.i][1] = layers.get(v)!;
      else if (w.section === 'TABLES' && w.table === 'LAYER' && w.ent === 'LAYER' && w.code === 2 && layers.has(v)) pairs[w.i][1] = layers.get(v)!;
      else if (w.section === 'TABLES' && w.table === 'BLOCK_RECORD' && w.ent === 'BLOCK_RECORD' && w.code === 2 && blocks.has(v)) pairs[w.i][1] = blocks.get(v)!;
      else if ((w.ent === 'BLOCK' && (w.code === 2 || w.code === 3)) || (w.ent === 'INSERT' && w.code === 2)) { if (blocks.has(v)) pairs[w.i][1] = blocks.get(v)!; }
      else if (w.ent === 'IMAGEDEF' && w.code === 1) pairs[w.i][1] = '';
    }
    // Paper space (code 67 = 1) is where the sheet layout, its title block and plot stamps live; cad_render does
    // not draw it at all. Its text VALUES are emptied here (the entities and their positions stay).
    let start = -1, paper = false;
    const blankPaper = (end: number) => {
      if (!paper || start < 0 || !/^(?:TEXT|MTEXT|ATTRIB|ATTDEF)$/.test(pairs[start][1].trim())) return;
      for (let k = start + 1; k < end; k++) if (pairs[k][0] === 1 || pairs[k][0] === 3) pairs[k][1] = '';
    };
    for (let k = 0; k <= pairs.length; k++) {
      if (k === pairs.length || pairs[k][0] === 0) { blankPaper(k); start = k; paper = false; }
      else if (pairs[k][0] === 67 && pairs[k][1].trim() === '1') paper = true;
    }
    const renamed = new TextEncoder().encode(joinPairs(pairs, eol));
    // Patterns first (e-mail, phone, URL), then the terms: a term that is part of an e-mail ("invalid") would
    // otherwise break the address before the e-mail pattern could see it whole (measured: "zz.site@example.").
    const r = redactDxf(renamed, (s) => tidy(redactText(redactText(s, []).text, terms).text));
    const dxf = new TextDecoder('utf-8').decode(r.bytes);
    return { ok: true, dxf, bytes: r.bytes, source: src.from, before_dxf: src.dxf, terms, layers, blocks, changed: r.changed };
  } catch (e) {
    return { ok: false, held: 'dxf_unreadable', detail: String((e as Error)?.message || e).slice(0, 160) };
  }
}

// ── verification ────────────────────────────────────────────────────────────────────────────────────

export type CadVerify = {
  ok: boolean; problems: string[];
  entities: [number, number]; geometry_pairs: [number, number];
  counts: { before: Record<string, number | null>; after: Record<string, number | null> };
  identity_left: string[];
};

/**
 * Prove a redacted DXF against the original's ASCII DXF: it opens, the geometry and the counts are unchanged,
 * and no identity is left. `maps` are the renames redactCadFile made (block counts are compared through them).
 */
export async function verifyCadRedaction(beforeDxf: string, afterDxf: string, seeds: string[], maps: { layers: Map<string, string>; blocks: Map<string, string> }, identity: string[] = []): Promise<CadVerify> {
  const problems: string[] = [];
  let pb: Pair[] = [], pa: Pair[] = [];
  try { pb = pairsOf(beforeDxf).pairs; } catch (e) { problems.push('the original does not parse: ' + String((e as Error)?.message || e)); }
  try { pa = pairsOf(afterDxf).pairs; } catch (e) { problems.push('the redacted file does not parse: ' + String((e as Error)?.message || e)); }
  try { const p = parseDxf(afterDxf); if (!p.ents.length) problems.push('the redacted file draws no entities'); } catch (e) { problems.push('cad_render cannot open the redacted file: ' + String((e as Error)?.message || e).slice(0, 120)); }
  const enc = new TextEncoder();
  const rb = await readDxf(enc.encode(beforeDxf), { filename: 'before.dxf', depth: 0 });
  const ra = await readDxf(enc.encode(afterDxf), { filename: 'after.dxf', depth: 0 });
  if (!ra.ok) problems.push('the reader cannot open the redacted file: ' + ra.detail);
  // Entities in order, and every geometry pair, identical.
  const ents = (p: Pair[]) => p.filter(([c]) => c === 0).map(([, v]) => v.trim());
  const geo = (p: Pair[]) => p.filter(([c]) => GEOMETRY(c)).map(([c, v]) => `${c}:${v.trim()}`);
  const eb = ents(pb), ea = ents(pa), gb = geo(pb), ga = geo(pa);
  if (eb.join('|') !== ea.join('|')) problems.push(`entity sequence changed (${eb.length} -> ${ea.length})`);
  if (gb.join('|') !== ga.join('|')) problems.push(`geometry changed (${gb.length} -> ${ga.length} coordinate/size/angle pairs)`);
  // Counts: every block count through the rename map, and the whole multiset of quantities.
  const qb = rb.ok ? rb.quantities : [], qa = ra.ok ? ra.quantities : [];
  const blockCounts = (q: typeof qb) => Object.fromEntries(q.filter((x) => /^block /.test(x.description)).map((x) => [x.description.slice(6), x.qty]));
  const cb = blockCounts(qb), ca = blockCounts(qa);
  for (const [n, q] of Object.entries(cb)) { const m = maps.blocks.get(n) ?? n; if (ca[m] !== q) problems.push(`count of block ${n} (now ${m}): ${q} -> ${ca[m] ?? 'missing'}`); }
  const ms = (q: typeof qb) => q.map((x) => `${x.unit}:${x.qty}`).sort().join('|');
  if (ms(qb) !== ms(qa)) problems.push('the take-off quantities changed');
  // Identity: every string value left in the file.
  const strings = pa.filter(([c]) => STRING(c)).map(([, v]) => v.trim()).filter(Boolean).join('\n');
  const terms = [...new Set([...seeds, ...seedTerms({ extra: cadIdentityTerms(beforeDxf) })])];
  const left = [...new Set([...residualScan(strings, terms), ...identity.filter((s) => strings.toLowerCase().includes(s.toLowerCase())).map((s) => 'literal:' + s)])];
  if (left.length) problems.push('identity left: ' + left.join('; '));
  return { ok: problems.length === 0, problems, entities: [eb.length, ea.length], geometry_pairs: [gb.length, ga.length], counts: { before: cb, after: ca }, identity_left: left };
}
