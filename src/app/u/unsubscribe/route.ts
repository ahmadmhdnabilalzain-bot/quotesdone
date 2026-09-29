// /u/unsubscribe — the unsubscribe link in every supplier mail (24 Sep 2026, marketing, ledger 993).
//
// MEASURED 24 Sep 2026: this path was a next.config.mjs rewrite straight to the `unsubscribe` edge
// function, and Supabase serves every edge-function response on *.supabase.co as `text/plain` with
// `X-Content-Type-Options: nosniff`, whatever Content-Type the function sets. So a supplier who clicked
// "Unsubscribe" saw the page's raw HTML source, with no button they could press, and the only way out
// left was a mail client's one-click POST. The rewrite could not fix the header; this handler can.
//
// It forwards the method, the query string and the form body to the function unchanged (so the RFC 8058
// one-click POST and the confirm button still reach it, and the function keeps every rule: token check,
// GET is safe, POST suppresses), and returns the function's own status and body as HTML.
// 29 Sep 2026: the forwarding moved to ../forwardToFunction.ts, shared with /u/followup, unchanged.
import { forwardToFunction } from '../forwardToFunction';

export const dynamic = 'force-dynamic';
const forward = forwardToFunction('unsubscribe');
export const GET = forward;
export const POST = forward;
