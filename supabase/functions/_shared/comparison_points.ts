// comparison_points.ts — the one name of a comparison point in the supplier's quotation conversation. Seat: sales_engineer.
// 15 Nov 2026 (CEO, under founder ruling 1696; final review of the comparison branch, FIX 1). quote_compare hands the points
// a quote leaves open to the sales engineer (request_fit.ts pointsHandoff); the hand-over's handler records each one in
// public.quote_review_request with this code (scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer.sql).
// supplier_api reads the code to keep these points out of the review's auto-close and to take the supplier's answer, so it
// lives here, small, rather than pulling the whole comparison module into the supplier's conversation.

/** quote_review_request.code of a point the comparison asked the supplier to confirm. */
export const POINT_CODE = 'comparison_point';
