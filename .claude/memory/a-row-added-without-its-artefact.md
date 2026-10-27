---
name: a-row-added-without-its-artefact
description: "A migration that INSERTS a registry row must also extend the committed CSV the invariant check compares against, or repo and production diverge silently."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 425dc308-c03a-4bfb-85e7-0e7c618e1872
  modified: 2026-08-17T19:26:35.164Z
---

17 Aug 2026, the finding that failed the final Phase C re-acceptance.

`scripts/sql/rc4_execution_and_trace_are_atomic.sql` correctly inserted two rows into
`public.phase_c_component` (`dbfn:fn_kernel_signal_submit(jsonb)`,
`dbfn:fn_kernel_trigger_submit(jsonb)`) — the kernel doors were naming component ids that did not
exist. It did not touch `docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv`, which is what
`scripts/checks/phase_c_invariants.test.mjs` compares production against. 1799 vs 1801, exit 1.

**Why it hid:** the check skips loudly without a management token and CI has none, so CI stayed
green. Only a token-holding session sees it. The same is true of `canonical_routines.test.mjs`,
`phase_c_founder_chain.test.mjs` and `phase_c_command_acceptance.test.mjs` — all four exit 1 today.

**How to apply:** after any migration that writes to a REGISTRY table (`phase_c_component`,
`phase_c_source_cutover`, `kernel_signal_type`, `kernel_write_authority`, `org_*`), ask which
committed artefact asserts that table's contents and extend it in the same commit. And run
`npm test` from a session that holds the token before calling a correction closed — CI's green is
not the suite's green. See [[green-pr-does-not-mean-deployable]] and
[[the-sweep-finds-what-the-increment-missed]].

**Third instance, same family, found the same day:** root cause 2 gave
`fn_founder_command_control` a fifth parameter (`p_actor`).
`scripts/checks/phase_c_command_center_entry_point.test.mjs` still passed four, so every run since
raised `function ...(bigint, unknown, text, unknown) does not exist` *before the first assertion* —
and reported a JS `TypeError` instead, because the payload guard checked `!res` but not
`!res.submit`. A whole end-to-end check had stopped executing and nothing said so. **After changing
a routine's SIGNATURE, grep the checks for its name, not just the callers in `supabase/` and `src/`.**

Second shape from the same session: root cause 1 retired `sql_files_match_live.test.mjs` and left
its sibling `canonical_routines.test.mjs` live, so two committed checks now answer the same
source-of-truth question with 0 and 436. When you retire an instrument, grep for the others that
open with the same claim. See [[a-sibling-path-that-never-got-the-lexicon]].
