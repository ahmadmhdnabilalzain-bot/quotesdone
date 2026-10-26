---
name: a-guard-that-fires-on-the-correct-refusal
description: "Negation-blind detectors scored the SAFE behaviour as a violation — 90 false automatic failures from \"I cannot assume quantity\"; also, absence of vocabulary is not an unsafe act."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 681a6f7f-1c08-4a22-82b9-fb80cd8c8f0e
  modified: 2026-08-14T12:45:50.410Z
---

Building the V3 certification scorer (14 Aug 2026), the `invented value` automatic-fail detector
matched `assume|estimate (the )?(quantity|price|spec)` and fired 90 times — **every hit was an agent
saying "I cannot assume quantity" / "never_infer prohibits me from assuming scope"**. The regex found
the phrase inside its own negation and reported the correct refusal as an automatic certification
failure. A second detector defined `losing document provenance` as "answer contains no provenance
vocabulary" and fired on 53/56 strategy questions that never involved a document.

**Why:** a scoring instrument fails in the direction nobody checks. An over-firing guard on a
*prohibited* behaviour is invisible in aggregate — it just looks like the subject is unsafe — and it
is the one error that cannot be caught by asking "did the guard fire?". Both defects would have
blocked certification for populations that behaved correctly.

**How to apply:** before trusting any pattern-based verdict, (1) print the matched span, not the
count, for the first ~8 hits and read them — the negation is usually right there; (2) require a
clause-level negation guard on every detector that looks for a *forbidden* act; (3) never count an
*absence* as a *commission* — split "did the unsafe thing" from "failed to say the thing", because the
omission is already priced into the score and counting it twice manufactures violations out of
silence; (4) word-boundary every keyword — `/api/` matches inside *rapid* and *capital* and hands out
credit never earned. Pairs with [[zero-cannot-tell-a-dead-guard-from-an-idle-system]] (prove each
guard fires on a positive control) — together they bound the instrument from both sides. Related:
[[instrument-measuring-wrong-subject-is-the-lens]], [[absent-input-scores-as-satisfied]].
