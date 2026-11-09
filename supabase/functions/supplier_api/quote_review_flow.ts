// supplier_api/quote_review_flow.ts — THE QUOTATION CONVERSATION: one supplier, one job, one thread
// with the sales engineer, from the first file to the submitted quote. Assigned: sales_engineer.
//
// The founder, 15 Sep 2026: the supplier attaches their quotation; the sales engineer reviews it
// immediately; if it is fine they reply "Quotation approved for submission", if not they list the
// adjustments and clarifications line by line; the supplier can answer in free text or attach a
// revised file; finally the engineer asks whether they will upload a new version or have it generated
// for them; they reply, and once done the quotation is submitted to the inquiry and the conversation
// ends, kept on record. And: "later this will be a mobile app as well" — so every state, every rule and
// every word lives HERE, on the server, behind actions a native app calls exactly as the portal does.
//
//   open ──upload──▶ reviewing ──▶ changes_requested ◀──text / upload──┐
//                                  │ (every point answered)            │
//                                  ▼                                   │
//                            awaiting_choice ──"generate"──▶ the quotation is PRINTED in the thread ─┐
//                                  │                                                                 ▼
//                                  └──"upload"──▶ awaiting_upload ──upload──▶ ready_to_submit ──submit──▶ submitted
//   the customer chooses before we submit ──▶ closed (read-only)
//
// 22 Sep 2026 (finding SP-F-07): "generate" used to go straight to submit. It now ends in
// ready_to_submit like the other road, so the supplier reads the standardised quotation BEFORE the
// customer does and Submit is the approval — the same shape as the spec-hold's approve step.
//
// WHERE THINGS LIVE. The conversation is public.quote_review_messages, the estate's registered
// conversation store (kept, never purged, archived to PDF and Dropbox — scripts/sql/every_conversation_
// is_kept_backed_up_twice_and_readable_by_the_sales_engineer.sql). One review per (inquiry, supplier) is
// public.quote_reviews. Every point the engineer raises is a row of public.quote_review_request, open
// until the supplier answers it or a new review no longer finds it (founder: "nothing is one-way").
//
// SUBMISSION IS submit_quote. The engineer never writes a quote row itself: the approved quotation is
// handed to supplier_api's own submit_quote (the caller's session, in-process), so the hold gate, the
// accept rule, options, VAT, the customer's notice, the comparison and the reveal all run unchanged.
//
// Written against a repository interface, like line_specs/workflow.ts, so the whole conversation runs
// in memory in the test — no database, no network, and no way to reach a real supplier.
// The conversation is split by subject under ./quote_review_flow/; this file keeps every public name importers already use.
export type { ReviewState, Choice, ReviewRow, Attachment, MsgKind, MessageRow, RequestRow, NewRequest, ReviewRepo, Scanned, FileRead, Json, ReviewDeps, Ctx, MessageView, RequestView, ThreadView, Fail } from './quote_review_flow/types.ts';
export { transcriptAsText, readQuotationFile } from './quote_review_flow/reading.ts';
export { QR_HELD_NOTICE } from './quote_review_flow/thread_view.ts';
export { thread, start, upload } from './quote_review_flow/upload.ts';
export { typed, looksTyped } from './quote_review_flow/typed.ts';
export { message } from './quote_review_flow/message.ts';
export { choose } from './quote_review_flow/choose.ts';
export { submit, submitPayload } from './quote_review_flow/submit.ts';
export { supabaseReviewRepo } from './quote_review_flow/repo.ts';
