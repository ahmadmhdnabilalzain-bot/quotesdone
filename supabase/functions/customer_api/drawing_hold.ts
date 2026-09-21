// drawing_hold — what analyze_drawing hands back about the drawing, decided in one place. Assigned: sales_engineer.
//
// WHY (customer audit 21 Sep 2026, finding 9). A PDF whose title block the server could not box
// (anonymise.titleBlockBoxes: low) went to the model; the gateway refused; drawing_redact recorded
// detect_failed with no pages. customer_api then answered drawing_redacted_paths:[] and the composer
// told the customer to "mark what to hide below" — an editor that no longer opens (the customer's boxes
// stopped counting as verification on 14 Sep). Nothing reached a supplier (inquiries_supplier_safe
// carries no drawing_file_path, measured 21 Sep), but the customer was never told the drawing was HELD,
// and a PARTIAL run's pages were handed back and refused at Send (409 redaction_incomplete): a dead end.
//
// The rule: the supplier copy exists only when EVERY page came back verified. Anything less is a hold —
// no redacted paths leave this function, share_redacted is false, and the hold is said out loud.
export type RedMeta = { redaction_pages_in: number; redaction_pages_out: number; redaction_complete: boolean };

export function drawingHandoff(meta: RedMeta, originalPath: string | null, redacted: string[]) {
  const held = !!originalPath && !meta.redaction_complete;
  return {
    drawing_redacted_paths: meta.redaction_complete ? redacted : [],
    drawing_held: held,
    // The explicit opt-out resolveRedactedPaths already honours: a held drawing shares nothing.
    ...(held ? { share_redacted: false as const } : {}),
  };
}

/** The ledger row for a held drawing (mirrors the 'boq_held' row create_inquiry writes). */
export function heldRun(o: { customerId: string; email: string; sourcePath: string; meta: RedMeta; reason: string }) {
  return {
    customer_id: o.customerId, owner_email: o.email, source_path: o.sourcePath, output_paths: [] as string[],
    pages_in: o.meta.redaction_pages_in, pages_out: o.meta.redaction_pages_out, skipped: Math.max(0, o.meta.redaction_pages_in - o.meta.redaction_pages_out),
    status: 'held', pages_verified: o.meta.redaction_pages_out, verify_failed: Math.max(0, o.meta.redaction_pages_in - o.meta.redaction_pages_out),
    verify_detail: { reason: o.reason },
  };
}
