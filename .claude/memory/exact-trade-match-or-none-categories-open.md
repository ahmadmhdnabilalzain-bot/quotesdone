---
name: exact-trade-match-or-none-categories-open
description: "Routing a request to suppliers is exact trade match or no match — never \"nearest\"; the category/trade list is open to new trades"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T10:59:09.167Z
---

Founder, 14 Sep 2026: "there is nothing called nearest match. either exact match or no match" and "our categories are not finalized. if a supplier comes tomorrow and register for packaging services he is welcomed".

**Why:** a request sent to a neighbouring trade reaches suppliers who can't quote it; and the catalogue grows with whoever registers.
**REFINED 15 Sep 2026 (founder_instruction 439):** "make sure the sales engineer is smart in cross matching. for example someone who does decoration is definitely able to do flooring even through words cross matching is not there."
- "No nearest" still means no fuzzy or similarity guessing.
- Matching DOES use a curated, auditable capability-implication map, e.g. decoration → flooring. It is one level only, and every rule has an EN+AR reason.
- Implied services are shown pre-included in the sales engineer's rewrite, and the supplier can remove any of them.
- The confirmed list drives matching, and each match records which implication rule produced it.

**How to apply:** category→trade maps hold only identical trades (synonyms/translations allowed). No match → no one is invited and support tells the customer honestly (see [[no-exact-spec-offer-alternatives]]). Never close trade registration to a fixed enum; a new trade is accepted and becomes routable for the same-named category.
