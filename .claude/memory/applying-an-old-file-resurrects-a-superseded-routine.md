---
name: applying-an-old-file-resurrects-a-superseded-routine
description: "23 Sep — applying a PR's older SQL file restored a superseded routine definition and broke the IT digest for hours; a definition left in an older file is a live routine waiting for the next apply"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-23T00:19:34.789Z
---

23 Sep 2026, my mistake, reported to the founder as mine. Applying PR #848 re-ran
`the_founder_gets_one_it_digest_per_tick.sql`, which still carried an older definition of
`fn_customer_support_sends_the_it_digest`. That restored a **second overload**, so every call became
ambiguous and the IT digest stopped from 20:01Z; the same apply rolled `fn_it_loop_tick` back to a
body from before its nine steps existed. #849 had the identical trap with `fn_it_detect` and
`fn_it_run_is_refusal`.

**Why:** the canonical routine is the one in the **highest MANIFEST sequence key**, not the one in the
file you happen to be applying. A superseded definition left behind in an older file is not dead — it
is a live routine waiting to be resurrected by the next apply of that file.

**How to apply it:** before applying any file in a PR, list every routine it defines and check whether
a later MANIFEST file also defines it. If one does, apply the **winners in MANIFEST order afterwards**,
then verify — I fixed both by re-applying the winning files in order and proving it with an
aborted-transaction probe returning `ok:true` with all nine steps present. Run
`node scripts/checks/canonical_routine_manifest.mjs` before and after; drift back to 0 is the proof.

Two neighbours of the same trap, both real: a data-only SQL file does nothing at all without `--ddl`
(apply_sql prints "nothing to do" and exits happy), and a file can refuse to re-apply because it
carries its own staleness guard on `md5(prosrc)` — which is exactly the state
`fn_support_knowledge_gap` and `fn_text_did_not_survive_reply` are in now, so re-applying their file
would abort rather than fix them.

Related: [[a-mention-is-not-a-reference]], [[quotesdone-apply-discipline]] in the repo skills,
[[two-applied-prs-deadlock-each-others-database-check]].
