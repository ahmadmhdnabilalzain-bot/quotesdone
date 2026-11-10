import type { PdfPage, TextRun } from '../../_shared/pdf_text_positions.ts';
import { titleStrip, type Box } from '../../_shared/anonymise.ts';
import { cx, cy, EQUIPMENT, FIXTURE, inBox, parseTag, SHEET_NO, size } from './vocabulary.ts';
import type { Consumed, Diffuser, TagHit } from './types.ts';

/** A tag drawn as a LEGEND sample: under a LEGEND / KEY / SYMBOLS heading in the same column (within a quarter of the
 *  sheet), with a description of two or more words beside it on its own line. */
const LEGEND_HEAD = /^(?:(?:electrical|fire\s*alarm|symbols?)\s+)?(?:legend|key|symbols?)(?:\s+(?:of\s+)?symbols?)?\s*:?$/i;
function legendSample(r: TextRun, runs: TextRun[]): boolean {
  if (!runs.some((h) => LEGEND_HEAD.test(h.text.trim()) && h.y < r.y && r.y - h.y < 0.25 && Math.abs(r.x - h.x) < 0.05)) return false;
  return runs.some((o) => o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.6 && o.x > r.x + r.w && o.x - (r.x + r.w) < 0.06 && /[A-Za-z]{3,}\s+\S{2,}/.test(o.text));
}

/** Every tag on one sheet, drawing area only (the title strip is excluded by the caller). */
export function tagsOnSheet(p: PdfPage, pi: number, strip: Box | null, airTypes: Iterable<string> = []): { hits: TagHit[]; diffusers: Diffuser[]; consumed: Consumed } {
  const runs = p.runs.filter((r) => !inBox(r, strip));
  const consumed: Consumed = new Set();
  const hits: TagHit[] = [];
  // 1. Single-run tags. A legend's sample tag is not work (founder 580): the drawing bench counted one extra of
  //    every tag its legend listed.
  for (const r of runs) {
    const t = parseTag(r.text); if (!t) continue;
    if (legendSample(r, runs)) { consumed.add(r); continue; }
    hits.push({ tag: t.tag, type: t.type, status: t.status, page: pi + 1, x: cx(r), y: cy(r) }); consumed.add(r);
  }
  // 2. Tag bubbles: a type code with its number directly below (same centre line, within 1.8 heights).
  for (const r of runs) {
    if (consumed.has(r)) continue;
    const code = r.text.trim().toUpperCase();
    if (!(EQUIPMENT[code] || FIXTURE[code]) || r.vertical) continue;
    const below = runs.filter((o) => !consumed.has(o) && o !== r && /^\d{1,3}[A-Z]?$/.test(o.text.trim()) && Math.abs(cx(o) - cx(r)) < Math.max(r.w, 0.004) && o.y > r.y && o.y - r.y < r.h * 1.8)
      .sort((a, b) => a.y - b.y)[0];
    if (!below) continue;
    const t = parseTag(`${code}-${below.text.trim()}`); if (!t) continue;
    hits.push({ tag: t.tag, type: t.type, status: t.status, page: pi + 1, x: cx(r), y: cy(r) }); consumed.add(r); consumed.add(below);
  }
  // 3. Air devices: letter, then (right) neck size over airflow.
  const diffusers: Diffuser[] = [];
  const NECK = /^(\d{1,2}\s*x\s*\d{1,2}|\d{1,2}"?\s*(?:Ø|DIA|RD))$/i, CFM = /^(\d{2,4}|--|-)$/;
  for (const r of runs) {
    if (consumed.has(r) || r.vertical || !/^[A-Z]$/.test(r.text.trim())) continue;
    const near = runs.filter((o) => o !== r && !consumed.has(o) && o.x >= r.x + r.w * 0.5 && o.x - (r.x + r.w) < 0.012 && Math.abs(cy(o) - cy(r)) < r.h * 1.2);
    const neck = near.find((o) => NECK.test(o.text.trim()) && cy(o) <= cy(r) + r.h * 0.2);
    const cfm = near.find((o) => CFM.test(o.text.trim()) && cy(o) >= cy(r) - r.h * 0.2);
    // A letter with its airflow below-right is a device even when the neck is not written (measured on
    // the mechanical set: type F carries "110" and no neck); a lone neck size is not enough.
    if (!cfm || (!neck && !/^\d{2,4}$/.test(cfm.text.trim()))) continue;
    diffusers.push({ letter: r.text.trim(), neck: neck ? neck.text.trim().replace(/\s+/g, '') : '', cfm: cfm.text.trim(), x: cx(r), y: cy(r) });
    consumed.add(r); if (neck) consumed.add(neck); consumed.add(cfm);
  }
  // 4. The same letters drawn bare (a return grille tagged "G" with no airflow beside it). Only a letter
  //    already known as an air device — seen with its stack on this sheet, or a row of the air device
  //    schedule — and only at the same text height as those tags, so a grid bubble or a damper "M" is not.
  //    A letter that only CONTINUES the series (G after A..F, measured on the mechanical set: six circled
  //    "G" return grilles, no airflow written, the schedule itself a raster) is counted as inferred, and
  //    the line says so and stays 'to_confirm' unless the schedule names that letter.
  const known = new Set([...diffusers.map((d) => d.letter), ...airTypes]);
  const top = known.size ? Math.max(...[...known].map((l) => l.charCodeAt(0))) : 0;
  const series = new Set(Array.from({ length: Math.max(0, top + 2 - 64) }, (_, i) => String.fromCharCode(65 + i)).filter((l) => !known.has(l) && l !== 'I' && l !== 'O'));
  const hs = diffusers.map((d) => runs.find((r) => cx(r) === d.x && cy(r) === d.y)?.h || 0).filter(Boolean).sort((a, b) => a - b);
  const hRef = hs.length ? hs[Math.floor(hs.length / 2)] : 0;
  if (hRef) for (const r of runs) {
    const t = r.text.trim();
    if (consumed.has(r) || r.vertical || !/^[A-Z]$/.test(t) || !(known.has(t) || series.has(t)) || Math.abs(r.h - hRef) > hRef * 0.15) continue;
    diffusers.push({ letter: t, neck: '', cfm: '', x: cx(r), y: cy(r), ...(series.has(t) ? { inferred: true } : {}) }); consumed.add(r);
  }
  return { hits, diffusers, consumed };
}

/** Runs on a plan that are SHAPED like a tag but that tagsOnSheet did not read: one run "IDU-4" / "(E)CRAC-2", or a
 *  2-4 letter code with a number directly below it (the bubble geometry of tagsOnSheet step 2) whose code is not in the
 *  vocabulary. These are what the reader would miss: a type it has no word for. A legend sample is already consumed. */
const TAG_SHAPE = /^(?:\((?:E|R|N|D|ER|EX)\)\s*)?[A-Z]{1,4}(?:\/[A-Z]{1,3})?-?\d{1,3}[A-Z]?(?:-\d{1,2})?(?:-H)?$/;
// A SERIES (independent review of 29dda0b5a, 27 Oct 2026): TAG_SHAPE alone let a plan through with 2 of 14 units read
// when the 12 it missed were spelled IDU-GF-01, IDU 1, IDU-1001, VRF-IDU-1, SPLIT-1 or IDU-1.01 (floor codes, a space,
// four digits, a hyphenated or five-letter type, a dotted number: all common on UAE MEP sets). Any one of those shapes
// written once is too close to a room label ("OFFICE 101") to call a tag, but the SAME letter prefix written with two or
// more different numbers is a tagged series, and an unread series means the count is incomplete.
// set_before_model.test.ts holds each spelling.
const SERIES = /^(?:\((?:E|R|N|D|ER|EX)\)\s*)?([A-Z]{1,6}(?:[-\/][A-Z]{1,4})?)[\s.\-]*((?:[A-Z]{0,2}\d{0,2}[-.])?\d{1,4}[A-Z]?(?:[-.]\d{1,3})?)$/;
export function unreadTagLike(p: PdfPage, strip: Box | null, consumed: Consumed): number {
  const all = p.runs.filter((r) => !inBox(r, strip));
  const runs = all.filter((r) => !consumed.has(r) && !legendSample(r, all));
  let n = 0;
  const used = new Set<TextRun>();
  for (const r of runs) if (TAG_SHAPE.test(r.text.trim().toUpperCase())) { n++; used.add(r); }
  const series = new Map<string, { nums: Set<string>; runs: TextRun[] }>();
  for (const r of runs) {
    const s = r.text.trim().toUpperCase();
    const m = SERIES.exec(s); if (!m || SHEET_NO.test(s)) continue; // "M-5.01" is a sheet reference, not a unit
    const e = series.get(m[1]) || { nums: new Set<string>(), runs: [] }; e.nums.add(m[2]); e.runs.push(r); series.set(m[1], e);
  }
  for (const e of series.values()) if (e.nums.size >= 2) for (const r of e.runs) if (!used.has(r)) { n++; used.add(r); }
  for (const r of runs) {
    if (used.has(r) || r.vertical || !/^[A-Z]{2,4}$/.test(r.text.trim())) continue;
    const below = runs.find((o) => !used.has(o) && o !== r && /^\d{1,3}[A-Z]?$/.test(o.text.trim()) && Math.abs(cx(o) - cx(r)) < Math.max(r.w, 0.004) && o.y > r.y && o.y - r.y < r.h * 1.8);
    if (below) { n++; used.add(r); used.add(below); }
  }
  return n;
}

/** Keyed notes of a sheet ("4. DEMO AND REMOVE …", continuation lines joined) and the bubbles carrying each number. */
export function keyedNotes(p: PdfPage, strip: Box | null, consumed: Consumed): { n: number; text: string; bubbles: number; outlined: boolean }[] {
  const runs = p.runs.filter((r) => !inBox(r, strip) && !r.vertical);
  const heads = runs.filter((r) => /^\d{1,2}\.$/.test(r.text.trim()));
  if (!heads.length) return [];
  const notes = new Map<number, { text: string; x: number; y: number }>();
  const headSet = new Set(heads);
  for (const h of heads) {
    const n = Number(h.text.trim().slice(0, -1));
    const first = runs.find((o) => !headSet.has(o) && Math.abs(cy(o) - cy(h)) < h.h * 0.6 && o.x > h.x && o.x - (h.x + h.w) < 0.012);
    if (!first) continue;
    // continuation lines: same left edge, directly below, until the next numbered head
    const nextHead = heads.filter((o) => Math.abs(o.x - h.x) < 0.01 && o.y > h.y).sort((a, b) => a.y - b.y)[0];
    const cont = runs.filter((o) => !headSet.has(o) && o !== first && Math.abs(o.x - first.x) < 0.004 && o.y > first.y && o.y < (nextHead ? nextHead.y - h.h * 0.3 : first.y + 0.03))
      .sort((a, b) => a.y - b.y);
    if (!notes.has(n)) notes.set(n, { text: [first, ...cont].map((o) => o.text.trim()).join(' ').replace(/\s+/g, ' '), x: h.x, y: h.y });
  }
  if (!notes.size) return [];
  const colX = Math.min(...[...notes.values()].map((v) => v.x));
  const max = Math.max(...notes.keys());
  const count = new Map<number, number>();
  // A keyed-note BUBBLE is the number inside a small closed outline (a box, a hexagon, a circle). When
  // the PDF carries its drawn outlines (CAD layers), only an enclosed number counts. Measured 22 Sep
  // 2026: without the outline test a room number, a dimension or a tag digit that happens to equal a
  // note number was counted as a bubble, so every keyed-note line had to stay 'to_confirm'.
  const marks = (p.marks || []).filter((m) => !inBox({ x: m.x + m.w / 2, y: m.y + m.h / 2, w: 0, h: 0, text: '' }, strip));
  // The outline is a closed path (a mark) or four straight edges drawn one by one (a box built of lines).
  const edges = p.lines || [];
  const boxed = (r: TextRun) => {
    const x = cx(r), y = cy(r), s = size(r), reach = s * 2.5;
    const side = (f: (l: typeof edges[number]) => boolean) => edges.some(f);
    return side((l) => l.x1 === l.x2 && l.x1 < x && x - l.x1 < reach && l.y1 < y && l.y2 > y && l.y2 - l.y1 < s * 5)
      && side((l) => l.x1 === l.x2 && l.x1 > x && l.x1 - x < reach && l.y1 < y && l.y2 > y && l.y2 - l.y1 < s * 5)
      && side((l) => l.y1 === l.y2 && l.y1 < y && y - l.y1 < reach && l.x1 < x && l.x2 > x && l.x2 - l.x1 < s * 5)
      && side((l) => l.y1 === l.y2 && l.y1 > y && l.y1 - y < reach && l.x1 < x && l.x2 > x && l.x2 - l.x1 < s * 5);
  };
  const enclosed = (r: TextRun) => marks.some((m) => cx(r) > m.x && cx(r) < m.x + m.w && cy(r) > m.y && cy(r) < m.y + m.h && Math.max(m.w, m.h) < size(r) * 5 && Math.min(m.w, m.h) > size(r) * 0.8) || boxed(r);
  const candidates = runs.filter((r) => !consumed.has(r) && /^\d{1,2}$/.test(r.text.trim()) && notes.has(Number(r.text.trim())) && r.x < colX - 0.005);
  // Outlines decide only when the sheet draws them: a sheet whose bubbles are text alone falls back to
  // the word-beside test below, and its lines stay 'to_confirm'.
  const outlined = candidates.some(enclosed);
  for (const r of runs) {
    if (consumed.has(r)) continue;
    const t = r.text.trim(); if (!/^\d{1,2}$/.test(t)) continue;
    const n = Number(t); if (!notes.has(n) || n > max) continue;
    if (r.x >= colX - 0.005) continue;                                          // the notes column itself
    if (outlined) { if (enclosed(r)) count.set(n, (count.get(n) || 0) + 1); continue; }
    // A number with a word right beside it on its line is a dimension or a size, not a bubble.
    const beside = runs.some((o) => o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.5 && ((o.x > r.x + r.w && o.x - (r.x + r.w) < 0.003) || (o.x + o.w < r.x && r.x - (o.x + o.w) < 0.003)) && !/^\(TYP\)$/i.test(o.text.trim()));
    if (beside) continue;
    count.set(n, (count.get(n) || 0) + 1);
  }
  return [...notes.entries()].sort((a, b) => a[0] - b[0]).map(([n, v]) => ({ n, text: v.text, bubbles: count.get(n) || 0, outlined }));
}


/** Tag counts that must survive redaction: identical on the original and on what the supplier sees. */
export function tagCounts(pages: PdfPage[], keep: (pageIndex: number, r: TextRun) => boolean = () => true): Record<string, number> {
  const out: Record<string, number> = {};
  pages.forEach((p, i) => {
    const strip = titleStrip(p);
    const q = { ...p, runs: p.runs.filter((r) => keep(i, r)) };
    const { hits, diffusers } = tagsOnSheet(q, i, strip);
    for (const h of hits) out[h.tag] = (out[h.tag] || 0) + 1;
    for (const d of diffusers) out['air:' + d.letter] = (out['air:' + d.letter] || 0) + 1;
  });
  return out;
}
