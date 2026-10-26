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
import { redactText, residualScan, seedTerms } from './anonymise.ts';
import { cadIdentityTerms, neutraliseCadLines } from './cad_identity.ts';

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
    const red = walk(cad ? neutraliseCadLines(boq) : boq) as any;
    const found = new Set<string>();
    let dropped = 0;
    const lines = Array.isArray(red) ? red : Array.isArray(red.boq) ? red.boq : [];
    const kept = lines.filter((l: unknown) => {
      const r = residualIdentity(l, seeds);
      if (!r.length) return true;
      r.forEach((x) => found.add(x)); dropped++; return false;
    });
    if (Array.isArray(red)) return { boq: kept as T, clean: found.size === 0, dropped_lines: dropped, found: [...found] };
    const rest = { ...red, boq: [] };
    const restLeft = residualIdentity(rest, seeds);
    if (restLeft.length) return { boq: null, clean: false, dropped_lines: dropped, found: [...found, ...restLeft] };
    const out = { ...red, boq: kept };
    if (dropped) out.missing_info = [...(Array.isArray(red.missing_info) ? red.missing_info : []), GATE_DROPPED_NOTE(dropped)];
    return { boq: out as T, clean: found.size === 0, dropped_lines: dropped, found: [...found] };
  } catch (_e) {
    return { boq: null, clean: false, dropped_lines: 0, found: ['gate_exception'] };
  }
}
