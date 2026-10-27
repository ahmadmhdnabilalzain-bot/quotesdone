---
name: the-ceo-seat-has-tools-but-no-runtime
description: "The CEO agent owns zero edge functions — its typed tools exist in SQL with nothing to dispatch them, and the founder knows"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T01:20:51.420Z
---

Measured 8 Sep 2026, after the 137-function deletion: `function_owner` holds 68 rows — **53 website,
15 customer_support, 0 ceo.** The CEO seat owns no edge function at all.

Its v1.2 tools exist and are correct (`fn_ceo_request_decision`, `fn_ceo_decide_refund`,
`fn_ceo_standing`, `fn_ceo_context`, `fn_ceo_accept_support_report`, `fn_refund_execute_authorized`),
but nothing calls them: `secretary_act`, the old Chief-of-Staff dispatcher, was deleted with the
department era it belonged to (it carried `query_platform` over 10 departments, `ask_agent` to 12
department agents, objective routing, Postiz publishing).

The founder's position, in his words on 8 Sep: **"the CEO is totally different from the old CEO. so
edge functions should be different"**, "the files and folders for the CEO today should remain", and
"i truly doubt that you built the CEO fully anyway. we dint finish the testing of the customer
support agent thats why. once done we will start testing the CEO we build today."

So: the order of work is customer-support testing first, then the CEO. Do NOT rebuild
`secretary_act` or anything shaped like it — the new CEO gets its own edge function, designed for
the two-seat company.

The same gap exists one level down for support: `fn_support_receive_document`,
`fn_support_deliver_artifact`, `fn_support_open_identity_challenge` etc. are built and tested by the
§15 harness, but `site_assistant` and `wa_inbound` do not call them yet.

**These 68 routines are deliberately exempt from any dead-code sweep** — see
[[a-mention-is-not-a-reference]]. They are unreachable because their caller has not been built yet,
which is the opposite of the old estate's reason.
