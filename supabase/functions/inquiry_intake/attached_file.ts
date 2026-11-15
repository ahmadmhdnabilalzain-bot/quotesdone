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
  const what = kind === 'quotation' ? 'their EXISTING QUOTATION from another supplier (its items only kept)' : kind === 'boq' ? 'a bill of quantities' : 'a drawing';
  const s = drawingBoq?.sufficiency && typeof drawingBoq.sufficiency === 'object' ? drawingBoq.sufficiency : null;
  const missing = s && Array.isArray(s.missing) ? s.missing.map((m: unknown) => String(m ?? '').replace(/\s+/g, ' ').trim()).filter(Boolean).slice(0, 8) : [];
  const verdict = s?.verdict === 'sufficient' ? 'Judged sufficient to quote.' : s?.verdict === 'not_yet' ? 'Judged not yet sufficient' + (missing.length ? '; a supplier still needs: ' + missing.join('; ') : '') + '.' : '';
  return `\nAttached: ${what}; ${lines} items read, treat them as provided. ${verdict} Ask, at most two at a time, for what this trade's checklist still needs; never for prices or the old supplier, and never write its name, prices or references. If told to send it as it is, put what is still missing in "unknown_keys".`;
}
