# PCCR-004 — the complete amendment table

**Status on 23 Aug 2026: RAISED, NOT APPROVED, NOT APPLIED.** `public.fn_kernel_cancel` is running
its frozen body; `public.fn_phase_c_freeze_drift()` reads `frozen_subjects_drifted` **0 of 25** and
`amendments_awaiting_founder_approval` **0 of 5**. Nothing in this session changed the subject, and
nothing in this document is a record of approval.

The narrative and the reasoning are in
[`PCCR_004_CANCELLATION_SERVICE.md`](PCCR_004_CANCELLATION_SERVICE.md). This file is the structured
table the founder asked for, one row per required element, every value measured on
`htdblwldjkcgjvmqkbeh` on 23 Aug 2026.

| element | value |
|---|---|
| **Amendment ID** | PCCR-004 |
| **Frozen Phase C subject** | `canonical_cancellation_service` — row of `public.phase_c_frozen_subject`, `object_kind` routine |
| **Frozen routine signature** | `public.fn_kernel_cancel(p_input jsonb) returns jsonb`, `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path TO 'public','pg_temp'` |
| **Frozen source digest** | `fc59489affbbc6654de56a7aa3012abeb339be4c8ae92a8282662e71d076f8ff` — `phase_c_frozen_subject.digest`, captured 2026-08-18 13:39:21 UTC. Verified live on 23 Aug 2026: `sha256(pg_get_functiondef(oid))` of the running body is the same value, so the subject is undrifted. Live `prosrc` is 13,062 characters. |
| **Proposed source digest** | `8dde28b958fa30132baedd8457043bb27113d1a39b87de53956ab1e408c3744c` — sha256 over the `CREATE OR REPLACE FUNCTION …` text the generator produces (16,535 characters). Generator: `scripts/tmp_diag/gen_j02.mjs`, sha256 `e2e295a3af1c615fa04f59a314ece400965a7448629610eb943a863fd63f59cf`, which splices three anchors into the live body and asserts each matches exactly once. **The digest the freeze board will record as `new_digest` is taken over `pg_get_functiondef` AFTER application** and can only be computed then; the value above is the digest of what is being approved, and the two are stated separately rather than conflated. |
| **Exact current behaviour** | The routine derives `v_command` from the subject it was given, and then — for **every** subject kind, including a workflow run — refuses the whole call if that command's own state model forbids the move. Sections (c) runs, (d) step runs and (f) handoffs scope to `v_runs`; sections (e) tasks, (g) outbox and (h) traces scope to `command_id`. |
| **Exact defective behaviour** | Two halves of one defect — one identifier doing two jobs. **(1)** Two Phase D drives of W01 in one fixture scenario produce runs 47357 and 47358 under founder command 12773. The failure path is driven on the first, moving the **command** to `failed`. `fn_kernel_cancel` is then called on the **second** run, whose own state is `active`, and `public.phase_b_workflow_transition` declares `active -> cancelled`. The result is `{"ok": false, "from": "failed", "to": "cancelled", "error": "transition_not_permitted", "message": "The command state model does not allow this move. Nothing was cancelled."}` and run 47358 is still `active` afterwards. Reproduced on W01, W04 and W24. **(2)** Cancelling ONE run of a multi-run command closes the tasks, outbox rows and traces of its **sibling** runs while leaving those runs open — an active run with cancelled tasks underneath it. |
| **Proposed behaviour** | `v_command` becomes the command the subject *belongs to*: reported, never acted on. A new `v_cmd` is the command this call *may close and sweep*, set only when (a) the caller named the command (`subject_kind = 'founder_command'`) — behaviour unchanged, **including** the early refusal when the command's state model forbids the move, because there the command IS the subject; or (b) the caller named a run, that run is the command's **last open run**, and the command's own state model permits the move. Where `v_cmd` is null the run is still cancelled — that was always what was asked for — and the result carries `command_closed: false` with the reason in `command_note` instead of refusing something the caller never asked about. Sections (a), (b), (e), (g), (h) and the postcondition (i) read `v_cmd`. |
| **Reproducible defect evidence** | `node scripts/phase_d/build_four_mode_result.mjs --only=W01` before the harness correction; the refusal payload above is returned verbatim by `fn_kernel_cancel` and the run's state is read back in the same aborted transaction. `public.phase_c_command_transition` holds no `failed -> cancelled` edge and is right not to: a failed command is not a cancelled one. |
| **Functions affected** | One: `public.fn_kernel_cancel(p_input jsonb)`. No other routine is created, replaced, dropped or re-signed. |
| **Tables affected** | None structurally. The rows the routine writes change: `public.phase_c_task`, `public.phase_c_outbox` and `public.phase_c_trace` are swept for the entitled command only, instead of for every run of the command; `public.phase_c_workflow_run` and `public.phase_c_workflow_step_run` are unchanged in scope. No DDL, no grant, no trigger. |
| **APIs affected** | None. `fn_kernel_cancel` keeps its signature and its result shape; `command_closed` and `command_note` are ADDED keys on a jsonb result, and no existing key changes name, type or meaning. No edge function and no frontend route calls it — measured: `grep -rn "fn_kernel_cancel" supabase/functions src` returns the kernel's own callers only. |
| **Caller impact** | A caller that cancels a **command** sees no change at all. A caller that cancels a **run** stops receiving `transition_not_permitted` for a command it did not name, and receives the run cancelled plus `command_closed:false` where the command is not entitled to close. A caller relying on one run's cancellation to sweep a sibling run's tasks loses that; no such caller exists — no autonomous path cancels one run of a multi-run command today. |
| **Security impact** | None. The routine remains `SECURITY DEFINER` with `search_path` pinned to `public, pg_temp`; no grant changes; no new relation is read or written; the authority checks the routine already performs are untouched. |
| **Privacy impact** | None. No new column is read, no payload is widened, nothing is emitted outward. |
| **Founder-boundary impact** | None. `public.phase_b_founder_boundary` is unchanged and no boundary scopes cancellation. `z00_refund_founder_decision_only` on `public.refunds` is not touched and still refuses a refund without a founder decision. The amendment narrows what a cancellation sweeps; it grants nothing. |
| **Phase A impact** | None. `public.fn_phase_a_baseline_drift()` returns 0 rows before and after; no department, role or overlay is read or written. |
| **Phase B impact** | None. `public.fn_phase_b_baseline_drift()` returns 0 rows before and after. The routine continues to consult `public.phase_b_workflow_transition` for the run's own move; no state, transition, gate, rule, handoff or ownership row is changed. This is not a Phase B change request. |
| **Compatibility** | Backward compatible. Same signature, same result keys plus two additive ones. A caller written against the current behaviour that cancels a command behaves identically; one that cancels a run gets the outcome it asked for instead of a refusal. |
| **Present on a branch** | **No.** The amendment was applied and measured on 23 Aug 2026 and then **reverted**; the migration file was removed. `ls scripts/sql/phase_d_j02*` returns nothing and no branch of this repository carries it. |
| **Present on production** | **No.** `sha256(pg_get_functiondef)` of the live `fn_kernel_cancel` equals the frozen baseline digest, measured 23 Aug 2026. `frozen_subjects_drifted` is 0 of 25. |
| **Migration** | `scripts/sql/phase_d_j02_one_run_was_refused_by_the_state_model_of_a_command_nobody_named.sql`, regenerated on approval by `node scripts/tmp_diag/gen_j02.mjs`, applied by `node scripts/apply_sql.mjs <file> --apply --ddl` (production-direct: the committed bytes are posted and the definition is read back and compared). One `CREATE OR REPLACE FUNCTION`; no DDL and no grant, so no `REVOKE` is required and none is included. The amendment row is then recorded through `public.fn_phase_c_freeze_amendment_approve` — the verified authenticated founder-session path G01 built — carrying the frozen digest above as `prior_digest` and the applied `pg_get_functiondef` digest as `new_digest`. |
| **Exact rollback** | Re-apply the last file before J02 that defines `fn_kernel_cancel`, which restores the frozen body byte-for-byte, then delete the `public.phase_c_freeze_amendment` row for PCCR-004. `create or replace` has no DDL to reverse and the file creates no object, so the classification is `ROUTINE_RESTORE` and no `scripts/sql/down/` file is required — the same treatment every other routine-replacement file in the corpus receives. Verification after rollback: `sha256(pg_get_functiondef)` equals `fc59489a…` and `frozen_subjects_drifted` reads 0 of 25. |
| **Positive tests** | (1) cancel a **command** whose state model permits it → command and every run cancelled, `command_closed:true`; (2) cancel the **last open run** of a command whose state model permits it → run cancelled AND command closed, `command_closed:true`; (3) cancel **one run of two** → that run cancelled, `command_closed:false`, `command_note` states why, and the sibling run's tasks, outbox rows and traces are untouched; (4) `public.fn_phase_c_freeze_drift()` reads 0 red with the amendment recorded. |
| **Negative tests** | (1) cancel a **command** whose state model forbids the move → still refused with `transition_not_permitted`, unchanged behaviour, and nothing is cancelled; (2) cancel a run whose OWN state model forbids `-> cancelled` → still refused; (3) cancel a run of a command already `failed` → the run cancels, the command does **not** move to `cancelled`, and `public.phase_c_command_transition` is never asked to make a move it does not declare; (4) an unknown subject → refused as today; (5) after every case, the sibling runs' step runs, tasks, outbox rows and traces are counted and asserted unchanged. |
| **Consequence of approval** | The kernel can cancel a workflow run without consulting the state model of a command nobody named, and cancellation stops closing derived work belonging to runs it did not cancel. The Phase D cancellation arm stops depending on a harness workaround (see below). `frozen_subjects_drifted` stays 0 because the drift is *amended*, not absent. |
| **Consequence of rejection** | Nothing breaks. No production path cancels one run of a multi-run command, so the defect is not reachable today. Phase D's cancellation measurement stands at **30 of 30** either way — the harness coupling that made it depend on this was fixed separately, in `scripts/phase_d/build_four_mode_result.mjs`, by giving the cancellation arm its own transaction and its own audited fixture scenario so it can no longer inherit the failure arm's command state. The routine keeps a known, recorded, reproducible defect that the freeze protects from being changed without the founder's word. |

---

## The Phase D requirement that cannot be met without PCCR-004

Exactly one, and it is not the cancellation figure.

* **Met without it:** every §2 and §9C cancellation requirement. `build_four_mode_result.mjs`
  measures cancellation **30 of 30 reaching `cancelled`**, with the currently approved frozen
  service, because each arm now has its own transaction and its own scenario.
* **Not met without it:** *cancelling one run of a multi-run founder command, and leaving that
  command's other runs and their derived work intact.* No Phase D deliverable can show that
  behaviour, because the frozen routine cannot produce it. It is recorded as a known defect of the
  frozen subject rather than as a Phase D gap, and it is the only thing PCCR-004 unblocks.

**The amendment is not marked approved because the harness can work around it.** The harness works
around the *measurement*; the routine's behaviour is unchanged and is still wrong.

---

## The founder decision required

Nothing else in this session needs him. One sentence, in writing, in the same form as PCCR-001 to
PCCR-003:

> PCCR-004 Amendment — canonical_cancellation_service. Approval is based on the amendment described
> in `docs/phase-d/PCCR_004_CANCELLATION_SERVICE.md`.

Until that sentence exists, `fn_kernel_cancel` keeps its frozen body, and no migration, script or
document in this repository may record the approval on his behalf.
