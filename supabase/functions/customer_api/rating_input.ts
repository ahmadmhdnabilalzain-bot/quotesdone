// WHAT A CUSTOMER MAY SEND WHEN RATING A SUPPLIER — the rule, in one testable place.
//
// customer_api:rate_supplier had returned HTTP 500 on every star press (17 Sep 2026: SQLSTATE 23514,
// reviews_reason_required — the widget sends no comment and the constraint demanded one). The
// operator's ruling: stars alone suffice, a comment is optional, and a refusal is said in words a
// customer can read — never a raw 500. This module is that ruling as code; the handler calls it
// before touching the database, and the database constraint (scripts/sql/
// a_customer_is_never_blocked_from_rating.sql) says the same thing a second time, as the last line.
//
// Tested in rating_input.test.ts. The messages here are the fallback; the portal maps `code` to its
// own bilingual text (src/components/me/portalText.ts CODE_KEY), so a customer reads it in their
// language.

/** The comment floor the constraint enforces: a comment, IF GIVEN, must be at least this long. */
export const COMMENT_MIN = 10;
/** Comments are stored at most this long; longer text is cut, never refused. */
export const COMMENT_MAX = 500;

export type RatingInput =
  | { ok: true; rating: number; comment: string | null }
  | { ok: false; code: 'rating_out_of_range' | 'review_comment_too_short'; error: string };

export function parseRatingInput(body: { rating?: unknown; comment?: unknown }): RatingInput {
  const rating = Number(body.rating);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    return { ok: false, code: 'rating_out_of_range', error: 'Rating must be 1 to 5.' };
  }
  // '' and '   ' are "no comment", not a short comment: a customer who tabbed through the optional
  // box must not be told their blank is too short.
  const typed = body.comment == null ? '' : String(body.comment).trim();
  const comment = typed ? typed.slice(0, COMMENT_MAX) : null;
  if (comment && comment.length < COMMENT_MIN) {
    return {
      ok: false, code: 'review_comment_too_short',
      error: `A comment is optional — but if you write one, please make it at least ${COMMENT_MIN} characters.`,
    };
  }
  return { ok: true, rating, comment };
}
