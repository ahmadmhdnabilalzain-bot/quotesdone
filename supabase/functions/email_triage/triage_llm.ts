// THE TRIAGE OF ONE E-MAIL IS NEVER ANOTHER E-MAIL'S (28 Oct 2026, the supplier-journey audit, founder ledger 1401).
// Assigned: customer_support (email_triage is its surface); found by the sales_engineer's browser audit.
//
// email_triage classifies every mail with one model call (SYS in index.ts: category, summary, draft). The gateway routes
// it to task class intent_detection, whose model_policy.cache_ttl_min is 1440, so ai_gateway answered it from its cache:
// an exact hash, then SEMANTIC similarity over an embedding of the first 400 characters of the system prompt and the first
// 800 of the mail. Every reply to the supplier invitation quotes the invitation, so replies with opposite meanings embed
// alike. Measured on production 28 Oct 2026, 07:48-08:06Z: every invitation reply's triage was a "semantic cache hit"
// at similarity 0.968-0.980 (ai_cost_log 53687, 53699, 53710, 53720, 53726, 53737, 53738), and each was recorded with an
// earlier mail's verdict, "The sender is interested in receiving quote requests for aluminium windows and glass
// partitions": a "Yes, interested", an Arabic "نعم، مهتمين", and a "Please remove me / stop" (inbound_messages 1449,
// triaged supplier_question). The category decides whether a mail is spam (never answered) and whether it asks a person
// to review an automated decision (ruling 1264, filed for review), so a borrowed category can skip either.
//
// ai_gateway lets a call site that knows its request is unrepeatable pass 0 and opt out, and the judgement calls already
// do (think.ts, review_request.ts: cacheTtlMin 0). A mail is never the same mail twice. NOT changed: the class's policy
// for its other callers.
export const TRIAGE_LLM = { max: 700, cacheTtlMin: 0 } as const;
