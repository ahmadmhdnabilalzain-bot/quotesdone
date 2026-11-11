// supplier_api/quote_review.ts — THE SALES ENGINEER REVIEWS A SUPPLIER'S QUOTATION, BY RULE.
// Assigned: sales_engineer (founder, 14 Sep 2026: "its always the sales agent. no other agent is
// involved in customer or supplier portal").
//
// THE FOUNDER, 15 Sep 2026: "this is the most important part in the whole supplier portal". The
// supplier attaches a quotation in a chat with the sales engineer; the engineer reviews it at once
// against our rules and either replies "Quotation approved for submission" or lists, line by line,
// the adjustments and clarifications needed. The supplier answers in the same conversation.
//
// THE RULES, in the order they are checked. Nothing here calls a model (OpenRouter is on hold, and a
// review must say the same thing every time it is asked):
//   1. every line of the job's bill of quantities is priced in the quotation (matched by words);
//   2. the quantity and the unit of each matched line agree with the BOQ;
//   3. every quotation line that states a quantity also states a price;
//   4. the line amounts add up to the total;
//   5. prices are in AED;
//   6. the VAT basis is stated — includes, excludes, or not VAT-registered. A business below the
//      AED 375,000 registration threshold is not registered and needs no TRN, so a TRN is never asked
//      for (founder: "no VAT till AED 375k; never ask again");
//   7. the validity of the prices is concrete (a number of days or a date);
//   8. the exact-specs rules the hold desk already enforces (founder, 14 Sep 2026, "exact specs or the
//      quote is held"): per-line material specification for the trade and for every component the
//      customer named, a concrete delivery date or lead time, installation and warranty when they
//      apply, and the price excluding VAT — _shared/line_specs/assess.ts, called here unchanged, so
//      the chat and the hold gate submit_quote runs can never disagree about what is missing.
//
// WHAT IT DOES NOT DO: it never decides a price is too high or too low, never compares a supplier to
// another supplier, and never tells a supplier anything about the customer beyond the scrubbed
// inquiry the inbox already serves. Pure: no I/O, no clock, no model — except readWorking, which takes its model as deps.
// The review is split by subject under ./quote_review/; this file keeps every public name importers already use.
export { SEAT, issueKey, jobNo } from './quote_review/types.ts';
export type { Lang, BoqRow, SafeInquiry, WLine, Working, IssueCode, Issue, Review } from './quote_review/types.ts';
export { parseQty, foreignCurrency, workingFromProposal } from './quote_review/working.ts';
export { normUnit, matchBoq } from './quote_review/match.ts';
export { readWorking, reviewQuotation, fromMissing } from './quote_review/review.ts';
export type { DeskInputs } from './quote_review/review.ts';
export { jobsIn, greeting, reviewSaid, choiceSaid, awaitingUploadSaid, readyToSubmitSaid, generatedSaid, submittedSaid, unreadableSaid, typedUnreadableSaid, closedSaid } from './quote_review/said.ts';
export type { Said } from './quote_review/said.ts';
export { readPriceClause, readReply } from './quote_review/reply.ts';
export type { Correction, Topic, ReplyRead } from './quote_review/reply.ts';
export { applyCorrections, carryOver } from './quote_review/corrections.ts';
export { sanitizeSpec, sanitizeTermsSpec, tookSaid, answerSaid, notUnderstoodSaid } from './quote_review/sanitize.ts';
