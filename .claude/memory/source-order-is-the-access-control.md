---
name: source-order-is-the-access-control
description: "23 Sep — I claimed a customer could reach an operator action after reading the gate at line 271 and the branch at 524, and missing the cutoff at 482 between them"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-23T01:38:18.390Z
---

23 Sep 2026, my error, corrected to the founder in the same session. I reported that a signed-in
customer could call `sales_engineer action:'match'` on anybody's inquiry, and said I had verified it in
code myself. I had read two things: the `SERVICE_ACTIONS` gate at `index.ts:271` (which restricts only
*service* callers) and the `match` branch at `:524`. I never read between them. **`:482` is
`if (caller.kind === 'customer') return J({error:'forbidden'}, 403)`**, and `match` sits below it, so a
customer never reaches it.

**Why:** in these edge handlers the authorisation is not a decorator or a middleware you can grep for
once — it is a sequence of early returns, and a branch's reachability is decided by every `return`
above it. Grepping for the gate you expect finds the gate you expect and tells you nothing about the
one you did not think of.

**How to apply it:** to claim a caller can reach a branch, read the handler from the top to that branch,
or list every early return above it, and say which kinds survive each. Never reason from two line
numbers far apart. The cheap mechanical version: `grep -n "return J(" <file>` and check every hit before
the branch's line number.

**The same error twice in one report:** I also relayed a review's claim that a PR "added a lever" via
`body.services` in that file. `grep -c body.services` = **0**. I passed on a detail I had not checked
because the rest of the review had been excellent — a good source is not a measurement. See
[[never-state-what-you-have-not-measured]] and [[a-blocker-is-a-claim-too]].

**The consolation, and it is the argument for the standing review rule:** because the brief went to a
builder who checked it instead of straight into a fix, the error was caught and the fix came out better
than the one I specified. The obvious ownership branch **does not compile** —
`Property 'customerId' does not exist on type 'never'` — which is the compiler proving the cutoff
already covers it; writing it anyway with a cast would have read as protection while asserting nothing.
The invariant became a type instead. See [[code-extremely-well-built]].
