// A PAID REQUEST TAKES NO NEW QUOTATIONS (sales_engineer, 13 Nov 2026; scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql).
// One sentence for both doors: submit_quote's own pre-check, and the database trigger a05 when the payment lands between
// that check and the insert (the race the second review of W2 found: it answered the generic 500). Suppliers read English.
export const REQUEST_REVEALED = {
  error: 'The customer has already opened a quotation on this request, so it is no longer taking new quotations. Thank you, and we will keep matching you to new requests.',
  code: 'inquiry_revealed',
} as const;

/** True when a database error is trigger a05's refusal (raise exception 'REQUEST_REVEALED: ...'). */
export function isRequestRevealed(err: unknown): boolean {
  const m = String((err as { message?: unknown } | null)?.message ?? err ?? '');
  return /^REQUEST_REVEALED\b/.test(m) || m.includes('REQUEST_REVEALED:');
}
