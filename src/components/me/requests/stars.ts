// stars.ts — how a 1-5 score is drawn on the customer's comparison card. Seat: sales_engineer. 15 Nov 2026.
//
// THE EVIDENCE (independent review of the comparison branch, 15 Nov 2026, item 7). Comparison.tsx drew
// '★'.repeat(v) + '☆'.repeat(5 - v). With one-decimal scores, '★'.repeat(3.9) is three stars and '☆'.repeat(1.1) one, so
// four symbols; and Supplier A (4.0, failing a requirement he stated) and Supplier B (4.6) both read ★★★★.
// Now the score is rounded to the nearest half and five symbols are always drawn: 4.0 is four full and one empty, 4.6 is
// four full, one half. The card prints the failure beside the stars (Comparison.tsx).
// Prevented by: src/components/me/requests/stars.test.mjs
export type Stars = { full: number; half: boolean; empty: number; rounded: number };
export function starsOf(v: unknown): Stars | null {
  const n = Number(v);
  if (v == null || v === '' || !Number.isFinite(n)) return null;
  const rounded = Math.max(0, Math.min(5, Math.round(n * 2) / 2));
  const full = Math.floor(rounded);
  const half = rounded - full === 0.5;
  return { full, half, empty: 5 - full - (half ? 1 : 0), rounded };
}
