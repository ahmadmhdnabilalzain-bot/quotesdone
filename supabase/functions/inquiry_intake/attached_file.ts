// attached_file — what the intake is told about a file the customer attached: what it IS, how many lines were read, and the
// reading's sufficiency verdict (13 Nov 2026, sales_engineer; founder ruling 1683: "Did the sales engineer actually verify that
// quotation is actually sufficient to be shared with the suppliers?"; for drawings: "Are they sufficient by themselves to create
// the quote?"). The verdict and its missing list are the model's (drawing_boq SYS); this only frames them for the intake turn,
// which asks for what is missing, framed by the trade's checklist, one or two at a time.
// prevented by: drawing_boq/a_quotation_reaches_suppliers_as_our_inquiry.test.ts
/** The attached file, as the intake reads it: what it is, how many lines, and the reading's sufficiency verdict. */
// deno-lint-ignore no-explicit-any
export function drawingNoteOf(drawingBoq: any): string {
  const lines = Array.isArray(drawingBoq?.boq) ? drawingBoq.boq.length : 0;
  const kind = drawingBoq?.document_kind === 'quotation' || drawingBoq?.brief_source === 'quotation' ? 'quotation' : (drawingBoq?.document_kind === 'boq' ? 'boq' : 'drawing');
  const what = kind === 'quotation' ? 'their EXISTING QUOTATION from another supplier (rebuilt as our inquiry: its items only, no prices, no names, no references)' : kind === 'boq' ? 'a bill of quantities' : 'a drawing';
  const s = drawingBoq?.sufficiency && typeof drawingBoq.sufficiency === 'object' ? drawingBoq.sufficiency : null;
  const missing = s && Array.isArray(s.missing) ? s.missing.map((m: unknown) => String(m ?? '').replace(/\s+/g, ' ').trim()).filter(Boolean).slice(0, 8) : [];
  const verdict = s?.verdict === 'sufficient' ? 'The reading judged it SUFFICIENT for a supplier of the trade to quote from.'
    : s?.verdict === 'not_yet' ? 'The reading judged it NOT YET sufficient for a supplier of the trade to quote from' + (missing.length ? '; a supplier would still need: ' + missing.join('; ') : '') + '.'
    : 'The reading gave no sufficiency verdict: judge it yourself against the checklist above.';
  return `\nThe customer also attached ${what}, from which we read ${lines} line items. Treat quantities and specifications from it as already provided. ${verdict} Before the request is ready, ASK the customer for each thing still missing that this trade's checklist above needs, in plain words, at most two at a time; never ask for prices or for the old supplier, and never write the old supplier's name, its prices, its references or its terms into the summary, the scope or the details. If the customer says to send it as it is, stop asking: put each item still missing in "unknown_keys" (or say it in the brief as not known) and set status by the rules above.`;
}
