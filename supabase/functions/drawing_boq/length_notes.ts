// length_notes — the sentences a customer reads about duct and pipe LENGTHS (22 Sep 2026, sales_engineer).
// One home for them because two functions write them: drawing_boq (drawing_set.ts mergeLengths) and
// customer_api (when the lengths call itself dies). They are English at the source, like every reader
// sentence; the customer's screen shows them in Arabic through src/lib/boqNotes.ts (founder instruction
// 586), and src/lib/boqNotes.test.mjs fails on any sentence here without its Arabic rule.
export const NO_LENGTHS_NOTE = 'Duct and pipe LENGTHS are not printed on the drawing and this file carries no CAD layers to measure them from: those lines carry the sizes and ask for the length at the printed scale.';
export const PLAN_LENGTHS_NOTE = 'Duct and pipe lengths are measured in plan from the drawing\'s CAD layers at its printed scale; vertical risers and drops are not in plan and are not included.';
export const LENGTHS_FAILED_NOTE = 'Duct and pipe lengths could not be measured on this upload (the measuring step did not finish): those lines carry the sizes and ask for the length at the printed scale.';
// 22 Sep 2026: a set too big for the edge's lengths call (546 at 40 synthetic sheets) is measured by the
// CAD worker (scripts/cad_read_worker.ts), and the customer's screen replaces the take-off when it is done.
export const LENGTHS_QUEUED_NOTE = 'Duct and pipe lengths for this drawing set are being measured in the background; the lines below carry the sizes until the lengths arrive.';
export const DENSE_NOTE = (sheets: string, max: string) => `Sheet(s) ${sheets} carry more than ${max} duct or pipe lines, more than one reading measures; their lengths were not measured and must be taken off by hand.`;

// A LENGTH WE COULD NOT MEASURE IS SAID ON ITS LINE (17 Nov 2026, sales_engineer; paid proof 14173f94). The note above is
// in missing_info, which the inquiry PDF does not print: the supplier read "Rectangular ductwork, sizes 26x18" with an
// empty quantity, as if the line had none. Every duct or pipe line still without a length now says so in its own words
// and is open (qty_status 'to_confirm', _shared/boq_open_lines.ts), so it is asked and never sent silently blank.
export const LENGTH_TO_CONFIRM = 'length to be confirmed';
export const LENGTH_TO_CONFIRM_AR = 'الطول قيد التأكيد';
// deno-lint-ignore no-explicit-any
export function lengthsToConfirm<L extends Record<string, any>>(boq: L[]): L[] {
  return boq.map((l) => {
    if (!l || !/^(duct|pipe):/.test(String(l.type || '')) || l.qty != null) return l;
    const said = (s: unknown, w: string) => (typeof s === 'string' && s && !s.includes(w) ? `${s} — ${w}` : s);
    return { ...l, description: said(l.description, LENGTH_TO_CONFIRM), ...(l.description_ar ? { description_ar: said(l.description_ar, LENGTH_TO_CONFIRM_AR) } : {}), qty_status: 'to_confirm' };
  });
}

// AN ENLARGED PLAN IS NOT MEASURED TWICE (17 Nov 2026, sales_engineer; drawing_set/enlarged.ts). A length that counts a sheet
// which may be an enlarged plan of an area already measured says so on its line, and is open, never sent as certain.
export const LENGTH_MAY_INCLUDE_ENLARGED = 'an enlarged plan in the set may repeat or add to this length — please confirm';
export const LENGTH_MAY_INCLUDE_ENLARGED_AR = 'قد يكرّر مخطط مكبّر في المجموعة هذا الطول أو يضيف إليه — يُرجى التأكيد';
