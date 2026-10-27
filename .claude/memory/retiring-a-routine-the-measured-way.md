---
name: retiring-a-routine-the-measured-way
description: "the proven recipe (3 Sep 2026) for removing dead governance routines without breaking a gate — what 'dead' must be measured against, and the four traps that make a textually-dead routine live"
metadata:
  type: feedback
---

3 Sep 2026: 12 of 271 phase_c/phase_d/kernel routines were retired after a census; the first attempt
failed atomically and two gates went red before the method was complete. The recipe that survived:

**"Dead" must be zero on EVERY axis, measured live:** callers in all ~1,340 routine bodies; cron
commands AND phase_c_system_execution_wrapper.original_command; triggers by `pg_trigger.tgfoid` join
(not text); views; RLS policies; repo execution refs (scripts/checks, supabase/functions,
scripts/phase_c, scripts/phase_d, .github — grep in the POSIX shell, NOT via execSync on Windows, where
`2>/dev/null || true` silently empties the result); then classify scripts/sql mentions CALL vs MENTION
per file (registry/ownership files MENTION every routine).

**Four traps that make a textually-dead routine live:**
1. `fn_kernel_all_boards()` discovers boards BY SIGNATURE — every zero-arg `*_state` fn returning the
   board shape is a live board with no textual caller (17 of the 37 "dead" were boards).
2. `kernel_write_authority` registers entry doors by name (fn_kernel_assert_in_kernel).
3. Operator tools invoked only from migrations (`fn_kernel_wrap_and_enable_cron`, 6 calling files).
4. **pg_depend**: a view depended on fn_phase_c_event_runtime_observation; a text scan of view bodies
   missed it. `pg_depend` is the pre-check, not text. The drop failed atomically — good.

**Mechanics:** `drop function if exists public.f(<exact identity args>)`, no CASCADE; a `do $ctl$`
block that raises if any survive; add each name to `scripts/sql/DROPPED.txt` (`name :: note`) so the
canonical engine records an absence instead of drift; MANIFEST line. A standalone re-apply after the
drops is REFUSED by apply_sql's reference guard (names absent routines) — by design; manifest-order
rebuilds apply it. `DROP FUNCTION` has no SQL down (scripts/sql/down/README.md): recovery is git.

**Then retire the COMPONENT rows too** (they outlive the routine and component ids carry the signature,
`dbfn:name(args)`, so a bare-name registry scan misses them): activation_state='inactive',
classification='INTENTIONALLY_RETIRED', evidence naming the drop — live AND the crosswalk CSV in
lockstep (23-column compare) — and delete the row from `phase_c_component_exposure_scope` if present:
external_entry is NOT NULL, the exposure derivation is null for a missing object, so a dropped routine
can never satisfy that board while it stays in the frozen scope. Related:
[[a-mention-is-not-a-call]], [[promote-carries-the-definition-not-the-grants]], [[wrapping-a-cron-needs-a-role-that-resolves]].
