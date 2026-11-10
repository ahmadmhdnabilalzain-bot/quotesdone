// drawing_identity_gate — the take-off of a drawing is RE-READ after redaction, and nothing that still
// names a party reaches a supplier (23 Sep 2026, sales_engineer; founder instructions 696, 698, 701, 703:
// "verify that identity details are removed perfectly from drawings before any supplier sees them").
//
// MEASURED BEFORE THIS FILE (in process, ZZ DEMO fixtures, drawing_identity_gate.test.ts replays both):
//  * A DXF / DWG take-off went through cad_identity.cadSupplierBoq (redact) and straight out. Nothing
//    re-read the result, so a term the redaction did not know about (a phone in a layer name, a licence
//    number in a block attribute not on a title-block layer) reached supplier_api's inbox as written.
//  * An IFC take-off was not redacted at all: drawing_boq only scrubbed when the reader returned dxf_text.
//    Storey names and type names are the consultant's own words — a storey named "ZZ HARBOUR TOWER L1"
//    became the BOQ section "ZZ HARBOUR TOWER L1" for every matched supplier. IfcPerson, IfcOrganization,
//    IfcTelecomAddress and FILE_NAME's author / organisation were read by nobody.
//  * PDF drawings: the PAGE IMAGES are redacted and verified by drawing_redact (a pixel overlay, then a
//    second model of another family, fail-closed). The PDF's text take-off had no re-read.
//
// WHAT THIS DOES — deterministic, no model:
//  1. terms: what the file itself says identifies the job (cadIdentityTerms for DXF/DWG, "Client: …" style
//     label values from the text layer of anything else).
//  2. redact: every string of the BOQ through anonymise.redactText with those terms (as before for CAD).
//  3. VERIFY: every line is RE-READ with anonymise.residualScan — the file's terms as bare substrings
//     (looser than redaction) plus e-mail, URL, UAE phone, US phone, web host, street address, P.O. Box,
//     plot, Makani, reference / permit number, TRN and trade-licence number. A line with anything left is
//     DROPPED, never shown. Then the rest of the BOQ (summary, notes, assumptions) is re-read; anything
//     left there and the whole take-off is WITHHELD (boq: null). Fail closed: an exception is a withhold.
// Quantities are never changed; a dropped line is counted in missing_info so the customer knows.
import { norm, redactText, residualScan, seedTerms, stripSeeds, titleStrip } from './anonymise.ts';
import { cadIdentityTerms, neutraliseCadLines } from './cad_identity.ts';
import { linesFromRuns, pdfPages, type PdfPage } from './pdf_text_positions.ts';

// Named constant, so src/lib/boqNotes.test.mjs finds it and fails if it has no Arabic.
const GATE_DROPPED_NOTE = (n: number) => `${n} line(s) of the drawing's take-off were withheld because they still named a party after redaction; please add them by hand if they are needed.`;

export const DRAWING_KINDS = new Set(['dxf', 'dwg', 'pdf']);

const LABEL_VALUE = /\b(?:client|owner|employer|customer|consultant|contractor|architect|engineer|developer|project(?:\s*(?:name|title))?|site(?:\s*address)?|location|address|drawn\s*by|checked\s*by|approved\s*by|designed\s*by|prepared\s*by)\s*[:：]\s*([^\n]{2,80})|(?:المالك|العميل|الاستشاري|المقاول|المشروع|اسم\s*المشروع|الموقع|العنوان)\s*[:：]\s*([^\n]{2,80})/gi;

/** Values written after a party label anywhere in a document's text ("Client: ZZ Orbit LLC"). */
export function labelTerms(text: string): string[] {
  const out = new Set<string>();
  for (const m of String(text || '').slice(0, 400_000).matchAll(LABEL_VALUE)) {
    const v = (m[1] || m[2] || '').trim();
    if (v.length >= 4) out.add(v);
  }
  return [...out];
}

/** The identity terms a read file states about its own job. */
export function drawingIdentityTerms(fileText: string, dxfText?: string): string[] {
  const t = new Set<string>(labelTerms(fileText));
  if (dxfText) cadIdentityTerms(dxfText).forEach((x) => t.add(x));
  return [...t];
}

// THE IDENTITY TERMS OF A PDF SET (3 Nov 2026, independent review of #1837; moved here from drawing_boq/cross_check.ts on
// 10 Nov 2026 so customer_api's send gate reads the SAME terms the take-off is gated with). The gate was first fed the text
// the model is sent: runs space-joined per page and cut at 12,000 characters. Joined that way a label runs into the
// next one, so the terms come out as fragments; measured on zzPdfSet: "ZZ DEMO ORBIT ZZ DEMO ORBIT CONSULTING ENGINEERS
// LLC TEL +971 4 000 0017 zz.orbi" and "ZZ DEMO Rashid Kareem PROJECT: ... DR" (the drafter lost, "consulting" a seed),
// where linesFromRuns over every page - what scan_takeoff and pdf_vector_redact read - gives "ZZ DEMO Rashid Kareem",
// "ZZ DEMO Harbour Tower", "ZZ Demo Drafter", "ZZ DEMO ORBIT". The title strip's own names (the seeds drawing_set.ts
// scrubs its lines with) are added, so a party printed only in the strip is gated too - WITHOUT their label: the gate
// splits every term into words (seedTerms), and a whole strip run "drawn by zz demo drafter" made "drawn" a seed, so
// the coded basis "tag FD-1 drawn 7x on P-1.01" reached suppliers as "tag FD-1 █ 7x" (second review, same day). An
// address is left to the contact patterns, which match it whole.
const STRIP_LABEL = /^(?:client|owner|employer|customer|consultant|contractor|developer|architect|engineer|project(?: (?:name|title|location|address|no|number))?|location|site(?: address)?|address|attn|attention|contact|(?:drawn|checked|approved|designed|prepared|reviewed) by|(?:drawing|dwg|sheet|job) (?:no|number)|tel|fax|phone|mob(?:ile)?|e ?mail)\b\s*/i;
export function setIdentityTerms(pages: PdfPage[]): string[] {
  const strip = pages.flatMap((p) => { const s = titleStrip(p); return s ? stripSeeds(p, s) : []; })
    .filter((t) => !t.includes('@')).map((t) => t.replace(STRIP_LABEL, '').trim()).filter((t) => t.length >= 4);
  return [...new Set([...drawingIdentityTerms(linesFromRuns(pages)), ...strip])];
}

/**
 * The identity terms of a stored original, read from its own text layer. `pdf` false: not a PDF (a photo, a sheet, a
 * CAD file - the callers gate those on their own reads). `words` 0: a scan, whose title block no text can name.
 * `terms` null: a PDF whose text layer could not be read at all - the caller holds anything derived from it.
 */
export async function pdfIdentityTerms(bytes: Uint8Array): Promise<{ pdf: boolean; words: number; terms: string[] | null }> {
  const pdf = bytes.length > 4 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46; // %PDF
  if (!pdf) return { pdf: false, words: -1, terms: [] };
  try {
    const pages = await pdfPages(bytes, undefined, { layers: false });
    return { pdf: true, words: pages.reduce((n, p) => n + p.runs.length, 0), terms: setIdentityTerms(pages) };
  } catch (_e) { return { pdf: true, words: -1, terms: null }; }
}

// A MISREAD NAME IS STILL THE NAME (evidence run ea40c830, 10 Nov 2026; docs/reports/2026-11-10-journey-evidence.md, item 2).
// The portal cut analyze_drawing at its 30 s fetch deadline (the read took 39.7 s with the model on), fell back to reading
// the rendered sheet with tesseract in the browser, and the take-off of that OCR text carried the title block's client,
// "Mr. ZZ Demo Owner", as "Mir. 22 Demo Owner". The title strip's own term "zz demo owner" was known to this gate, but a
// term was matched as written: redaction painted "Owner" and left "Mir. 22 Demo", and the re-read found no "zz demo owner"
// in the line, so the line was kept. MEASURED on the live run's 13 OCR lines (drawing_identity_ocr_misread.test.ts): 0
// dropped. A line is now ALSO compared with every term after folding both the way OCR confuses them (0/o, 1/i/l, 2/z,
// 5/s, 8/b, 6/g, rn/m, vv/w; spaces and punctuation out), on the line as it was READ, before redaction, so a half-painted
// line still counts; it is dropped when the term is there folded and NOT there as written (ocrMisreads) - a term written
// out is still redaction's to paint and the line kept, as before (a DXF's FCU line keeps its 24 with the consultant's
// name painted out: drawing_identity_gate.test.ts 1). Only a folded term of FOLD_MIN characters or more is compared: the strip's fragments ("te villa",
// "g 1 priv") are shorter and would drop ordinary lines. A term is also compared without its first and/or its last word
// (two words or more left), because the word OCR mangles is often the honorific or a label beside the name: a strip run
// "Mr. ZZ Demo Owner" is the term "mr zz demo owner", and "Mir. 22 Demo Owner" folds to "mlrzzdemoowner", which holds
// "zzdemoowner" and not "mrzzdemoowner". A single word is never compared on its own ("consultants", "mechanical").
export const FOLD_MIN = 8;
// [as written (normalised), folded] for the term and its trimmed forms.
function foldedForms(term: string): [string, string][] {
  const w = norm(term).split(' ').filter(Boolean);
  const out = new Map<string, string>([[w.join(' '), foldOcr(term)]]);
  for (const [a, b] of [[1, 0], [0, 1], [1, 1]]) if (w.length - a - b >= 2) { const n = w.slice(a, w.length - b).join(' '); out.set(n, foldOcr(n)); }
  return [...out].filter(([, f]) => f.length >= FOLD_MIN);
}
export function foldOcr(s: string): string {
  return norm(String(s ?? '')).replace(/rn/g, 'm').replace(/vv/g, 'w').replace(/[\s\p{P}\p{S}]+/gu, '')
    .replace(/[01i2586]/g, (c) => ({ '0': 'o', '1': 'l', 'i': 'l', '2': 'z', '5': 's', '8': 'b', '6': 'g' } as Record<string, string>)[c] ?? c);
}
/** The terms one of whose OCR-folded forms occurs in the OCR-folded `text` ([] = none). */
export function ocrTwins(text: string, terms: string[]): string[] {
  const t = foldOcr(text);
  if (!t) return [];
  return [...new Set(terms.filter((x) => foldedForms(x).some(([, f]) => t.includes(f))))];
}
/**
 * The terms `text` carries MISREAD: a folded form occurs while that form as written does not (OCR's "Mir. 22 Demo Owner"
 * for "Mr. ZZ Demo Owner", or a term glued into a word). A term present as written is redaction's to paint, as before;
 * only one redaction cannot see is a reason to drop the line or withhold the take-off.
 */
export function ocrMisreads(text: string, terms: string[]): string[] {
  const t = foldOcr(text);
  if (!t) return [];
  const n = ' ' + norm(text) + ' ';
  return [...new Set(terms.filter((x) => foldedForms(x).some(([w, f]) => t.includes(f) && !n.includes(' ' + w + ' '))))];
}

const stringsOf = (v: unknown, out: string[] = []): string[] => {
  if (typeof v === 'string') out.push(v);
  else if (Array.isArray(v)) v.forEach((x) => stringsOf(x, out));
  else if (v && typeof v === 'object') Object.values(v as Record<string, unknown>).forEach((x) => stringsOf(x, out));
  return out;
};

/** Re-read: what identity is still in `v` (every string), as residualScan reasons. [] = clean. */
export function residualIdentity(v: unknown, seeds: string[]): string[] {
  return [...new Set(stringsOf(v).flatMap((s) => residualScan(s, seeds)))];
}

export type GateResult<T> = { boq: T | null; clean: boolean; dropped_lines: number; found: string[] };

/**
 * Redact, then verify, a drawing's supplier-facing BOQ. Lines still carrying identity are dropped; any
 * identity left outside the lines withholds the whole take-off (boq null). Never throws.
 */
export function gateDrawingBoq<T>(boq: T, terms: string[], cad = false): GateResult<T> {
  try {
    if (!boq || typeof boq !== 'object') return { boq, clean: true, dropped_lines: 0, found: [] };
    const seeds = terms.length ? seedTerms({ extra: terms }) : [];
    const walk = (v: unknown): unknown => typeof v === 'string' ? redactText(v, seeds).text
      : Array.isArray(v) ? v.map(walk)
      : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, walk(x)])) : v;
    const pre = (cad ? neutraliseCadLines(boq) : boq) as any;
    const red = walk(pre) as any;
    const found = new Set<string>();
    let dropped = 0;
    const lines = Array.isArray(red) ? red : Array.isArray(red.boq) ? red.boq : [];
    const read = Array.isArray(pre) ? pre : Array.isArray(pre.boq) ? pre.boq : [];
    // A term MISREAD in the line as read (ocrMisreads: OCR-folded, absent as written) drops it, even when redaction painted
    // part of it; reported as a kind, never by value (a term is the customer's own identity).
    const twinsOf = (v: unknown) => ocrMisreads(stringsOf(v).join('\n'), terms).map(() => 'ocr_misread:term');
    const kept = lines.filter((l: unknown, i: number) => {
      const r = [...residualIdentity(l, seeds), ...twinsOf(read[i])];
      if (!r.length) return true;
      r.forEach((x) => found.add(x)); dropped++; return false;
    });
    if (Array.isArray(red)) return { boq: kept as T, clean: found.size === 0, dropped_lines: dropped, found: [...found] };
    const rest = { ...red, boq: [] };
    const restLeft = [...residualIdentity(rest, seeds), ...twinsOf({ ...pre, boq: [] })];
    if (restLeft.length) return { boq: null, clean: false, dropped_lines: dropped, found: [...found, ...restLeft] };
    const out = { ...red, boq: kept };
    if (dropped) out.missing_info = [...(Array.isArray(red.missing_info) ? red.missing_info : []), GATE_DROPPED_NOTE(dropped)];
    return { boq: out as T, clean: found.size === 0, dropped_lines: dropped, found: [...found] };
  } catch (_e) {
    return { boq: null, clean: false, dropped_lines: 0, found: ['gate_exception'] };
  }
}
