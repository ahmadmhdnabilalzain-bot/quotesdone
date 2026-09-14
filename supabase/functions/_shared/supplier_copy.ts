// supplier_copy — the TRUST BOUNDARY for anything a supplier receives from a customer's drawing.
//
// WHY (14 Sep 2026). OCR runs in the customer's browser and redaction boxes are drawn there, so both
// arrive as data the customer controls: tampered, partial, or not sent at all. The supplier copy must
// therefore be decided on the SERVER, from the stored original, and fail closed. These two functions
// are that decision, kept apart from the I/O so a test can prove it without a running function.
//
//   supplierPageReadable — a page may be published only if the server itself can read its text layer
//     (and it is not rotated, which would put every box a quarter turn out). Photos, scans and CAD
//     rasters have no text layer: the server cannot see what is on them, so they are HELD, whatever
//     boxes the customer sent.
//   supplierBoxes — the boxes a supplier copy is painted with are the server's own title-block boxes
//     (anonymise.titleBlockBoxes). The customer's boxes are added as EXTRA cover, never in place of
//     them. When the server's detection is not confident, or left a residual, the answer is null: HOLD.
//
// WHAT IT NEVER DOES: treat a client-supplied box, or client-supplied OCR text, as evidence that a
// page is clean.
type Box = { x: number; y: number; w: number; h: number };

export function supplierPageReadable(page: { runs?: unknown[]; rotate?: number } | undefined, rotated = false): boolean {
  return !!(page && Array.isArray(page.runs) && page.runs.length > 0 && !page.rotate && !rotated);
}

export function supplierBoxes(
  tb: { boxes: Box[][]; confidence: string; residual: string[] },
  client: Box[][] | null,
  pages: number,
): Box[][] | null {
  if (tb.confidence !== 'medium' || tb.residual.length > 0) return null;
  return Array.from({ length: pages }, (_, i) => [...(tb.boxes[i] || []), ...((client && client[i]) || [])]);
}
