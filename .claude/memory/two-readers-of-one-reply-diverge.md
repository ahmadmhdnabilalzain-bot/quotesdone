---
name: two-readers-of-one-reply-diverge
description: The widget kept its own copy of the portal's reply reader and so lost answers the server had stored; a browser proof (Playwright, live, ZZ DEMO) now drives every chat surface - run it after any chat change
metadata:
  type: lesson
---

2 Nov 2026 (customer_support with sales_engineer, ledger 1464, PR 1762). The founder: the widget, the sales engineer in the
portals and customer support must never lose the conversation or start again.

**What the browser proof found** (`.github/workflows/conversation-continuity.yml`, `scripts/e2e/conversation_continuity.mjs`;
run on push of its files or by dispatch; about USD 0.9 a run; artifact `continuity-out`):
- The widget printed its error line over an answer the server HAD stored (a 504 page). The portal looked for the stored
  answer; the widget kept a second copy of the reader without that loop. Now one reader (`portalReply.readReply`) and one loop
  (`lookForStoredAnswer`).
- A turn past the visitor cap was logged without `conv_id`, so it vanished on reload (16 of 30 messages).
- The AED 500 minimum job value lived only in site_assistant's inline facts, not in `knowledge/brief/company.md`; the portal
  said "any size is fine". A fact stated on one surface belongs in the shared brief.
- A slot detector read "AED 300" inside a question as the customer's budget; once the summary was due every reply was the
  read-back, so "what is the fee again?" lost its figure.

**Open at the time of writing:** the portal says it "cannot see your account" (it gets quotes as facts, not the request list);
a portal turn can fail before it is logged while the panel says it is "saved"; a portal reply began "Until then..." (an
opening sentence dropped by the sentence filters).

**For the next chat change:** a second copy of a reader, a log row without `conv_id`, or a fact in one surface's prompt only,
are the three ways this broke. Graders have known-bad controls (`the_continuity_graders_catch_bad_answers.test.mjs`).
Related: [[a-fixs-own-check-measures-the-case-the-fix-handles]].
