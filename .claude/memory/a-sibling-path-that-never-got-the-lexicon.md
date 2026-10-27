---
name: a-sibling-path-that-never-got-the-lexicon
description: "When two paths answer the same question, check whether both got the shared resource — discover matched raw words against codes while route_inquiry had used the alias lexicon since it was written."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 66a952a6-eec2-4b4b-9915-b04839a8d384
  modified: 2026-08-13T09:34:39.760Z
---

`taxonomy_trade` carries 40 active codes and **283 aliases** — `marble` is an alias of `flooring`.
`route_inquiry` has resolved customer words through that lexicon since it was written.
`customer_api`'s `discover` action never did: it passed raw typed strings into
`fn_match_capability`, which compares CODES with an exact array overlap. So a customer typing an
ordinary word searched for a trade that cannot exist and got silence.

**Why:** this is [[finished-capability-with-no-entry-point]] rotated one turn — the capability has
an entry point, just not on *every* path that needs it. The lexicon was live, correct and in use;
one of its two consumers simply never called it.

**How to apply:** when two code paths answer the same question for different callers (preview vs
dispatch, portal vs WhatsApp, customer vs staff), diff what each one *resolves* before comparing
what each one *returns*. The one written later usually got the shared resource; the older sibling
is where the silence is. Ask: "does this path go through the same lookup the other one does?"

Found 13 Aug 2026 by typing the screen's own worked example into it and getting zero — see
[[instruments-report-on-the-wrong-subject]] for the empty state that then blamed the wrong thing.
