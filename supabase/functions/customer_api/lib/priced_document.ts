// priced_document — what analyze_drawing answers for a PRICED document, decided without I/O (13 Nov 2026, sales_engineer;
// founder rulings 1683 and 1686: "prices are hidden as well. Specifications and items, quantities, yeah, they can be, but
// pricing, no"). Extracted from customer_api/actions/documents.ts so the route itself is tested (review of F2: disabling it
// in place was caught by no test).
//  * 'quotation' (the model said so, or code sees a party, priced lines and a total): another supplier's offer, rebuilt as our
//    inquiry by drawing_boq/quotation_gate.ts with the party terms its own text states; the old supplier's names and
//    references are kept for the request's doors (old_supplier_terms); the customer is told what was understood.
//  * 'priced' (money without that structure: the customer's or a consultant's own priced BOQ): the same money gate, said as
//    "rates in the customer's document are not shared", brief_source 'boq', never "another supplier".
//  * either way NO page of it is pictured for a supplier.
//  * null: not priced; the drawing route goes on.
// prevented by: drawing_boq/a_quotation_reaches_suppliers_as_our_inquiry.test.ts
import { pricedDocumentKind, quotationGate, quotationTerms, termsToKeep } from '../../drawing_boq/quotation_gate.ts';
import { understoodMessage } from './what_was_understood.ts';

// deno-lint-ignore no-explicit-any
type Reading = Record<string, any>;
export function pricedRoute(o: { isCad: boolean; pdfLines: string[]; reading: Reading | null }) {
  if (o.isCad) return null;
  const kind = pricedDocumentKind(o.pdfLines, o.reading);
  if (!kind) return null;
  const terms = kind === 'quotation' ? quotationTerms(o.pdfLines) : { parties: [], refs: [], prefixes: [] };
  const qb: Reading = quotationGate({ ...(o.reading || {}) }, terms, kind);
  // a quantity the document prints is the customer's own figure, never our take-off estimate
  if (Array.isArray(qb.boq)) qb.boq = qb.boq.map((l: Reading) => (l.qty == null || l.qty === '' ? l : { ...l, qty_status: 'customer_stated' }));
  const msg = understoodMessage(qb, kind === 'quotation' ? 'quotation' : 'priced');
  if (kind === 'quotation') qb.old_supplier_terms = termsToKeep(terms);
  return { boq: qb, brief_source: kind === 'quotation' ? 'quotation' : 'boq', document_kind: kind === 'quotation' ? 'quotation' : 'boq',
    drawing_redacted_paths: [] as string[], drawing_held: false, share_redacted: false, note: kind === 'quotation' ? 'quotation_rebuilt' : 'priced_rates_withheld',
    ...(msg ? { understood_message: msg.en, understood_message_ar: msg.ar } : {}) };
}
