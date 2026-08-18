# Phase C remediation — what changed after the audit

Branch `fix/phase-c-four-gates`, commit `241ba68`, PR
[#437](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/437).
Every number below was read back from production `htdblwldjkcgjvmqkbeh` after the change.

## Gate movement

| gate | audit verdict | now | evidence |
|---|---|---|---|
| 12 · kernel-only writes | **FAIL** — `kernel_primitives_called_from_outside_the_kernel` 1 of 9 | **PASS** — 0 of 9 | `fn_kernel_retired_path_state()` |
| 15 · event and outbox truth | **FAIL** — one overloaded `CONNECTED`, 287 labelled / 13 observed | **PASS** — structural and runtime separated, runtime derived | `fn_phase_c_event_truth_state()` |
| 1 · frozen baselines (F4) | PASS with a defect — bindings 161 vs handoffs 159, expectation typed | **clean** — 159 = 159, expectation derived | `fn_phase_c_invariants()` |
| 8 / 9 · autonomous sources | **FAIL** — reported 26 of 37 bypass the kernel | **still FAIL** — **19 of 37**, measured rather than claimed, counted, owned and ratcheted | `fn_kernel_trigger_state()` |
| F5 · boards read by a gate | 1 of 7 | **21 of 21**, discovered by signature | `fn_kernel_all_boards()` |

**Phase C remains FAIL, on gates 8 and 9 only.**

## Phase D harness

| criterion | audit | now |
|---|---|---|
| 1 · no deleted-staging dependency | MET | MET |
| 2 · concurrency bounded, no false 429 failures | recorded NOT MET — **that was my error** | **MET** — `run.mjs` already passes `--test-concurrency=1`, added 17 Aug for exactly this reason. I read the flag after writing the assessment. The 502 seen later in this session hit one file, and re-running it alone cleared it, which is the documented discipline working |
| 3 · no nested tree | MET | MET |
| 4 · Phase A/B/C tests pass | NOT MET | **MET** |
| 5 · no unresolved Phase C failure | NOT MET | **MET** for the suite; gates 8/9 remain open as a disclosed, ratcheted number |
| 6 · later-phase tests owned and excluded by profile | NOT MET — no profile existed | **MET** — `scripts/checks/test-profiles.json`, 2 exclusions, each with owner, reason and measurement, guarded by `every_exclusion_still_matches_a_test.test.mjs` |
| 7 · counts reconcile | MET | MET |
| 8 · dedicated zero-cost command | NOT MET | **MET** — `npm run test:phase-d` → **298 tests, 298 pass, exit 0** |

Full suite went from **8 failures to 0**. Categories closed:

- 3 × ROW3_BACKLOG — one cause: `fn_org_role_violations` did not know the founder-approved Phase A deferral list existed. Fixed by reading `org_phase_baseline.deferred`, not by hard-coding a role name. The four items stay visible via `fn_org_role_deferred()` and a stale-deferral check fails if one outlives its subject.
- 2 × TEST_SETUP_DEFECT — assertions pinned to an identifier (`d.alternatives`) and a message that correct fixes had changed. Re-anchored on behaviour and on SQLSTATE + guard identity.
- 1 × PHASE_C_RUNTIME — `every_executor_kind_has_a_runner` demanded an active cron the Phase C hold deliberately holds off, through a filter reading `cron.job.command` after the kernel cutover had moved the value into `phase_c_system_execution_wrapper.original_command`. Now asserts the runner is registered and wrapped; activation is reported, never demanded.
- 2 × KNOWLEDGE_PHASE — excluded through the profile with named owners.

## Two mistakes made during the remediation

Recorded because both are the kinds this estate keeps producing.

**`fn_kernel_all_boards` discovered itself.** It returns the exact signature it searches for, so the first call recursed until the statement timeout killed it. Excluded by name, with the reason left in the file.

**Re-applying an earlier MANIFEST file undid a later one.** Re-applying `kernel_k13_retire_old_runtime.sql` re-granted `EXECUTE` on four kernel primitives to `service_role` — grants that `kernel_k35_retired_paths_lose_the_service_grant.sql` exists to remove. `apply_sql.mjs --apply` reads the **definition** back and matches it, and does not read the ACL, so it printed *"read back and identical to the file"* while the estate's permissions had moved. Caught by `fn_kernel_retired_grant_state` — the board I had just made readable — within minutes, and repaired by re-applying k35.

That is a real gap in the deploy protocol worth naming: **the read-back covers bodies, not grants.** A file that is safe to re-apply for its routine definitions is not necessarily safe to re-apply for its GRANT statements.

## The audit's own number was wrong, and the instrument was why

The audit reported 26 of 37 sources bypassing the kernel. **The true figure is 19, and always was.**

`v_kernel_trigger_source_derived` answered `routes_through_inbox` from live catalogue facts for cron
jobs, database triggers and event triggers — and from `recorded_routes_through_inbox`, a hand-set
boolean, for everything else. Everything else is every edge function and every frontend path: 33
sources, all carrying `false`.

That flag is a claim in both directions. Wiring an edge function would not have moved it, and setting
it without wiring anything would have turned the gate green over nothing.

What is measurable: this estate discharges an edge function through a trigger on the table it writes.
`kernel_k25` created `trg_contact_message_to_kernel` on `contact_messages`, whose body calls
`fn_kernel_source_emit('edge:contact_submit', …)`, and `kernel_k34` records that model explicitly as
`edge:contact_submit → routine:trg_contact_message_to_kernel`. The source key is a quoted literal
inside a deployed routine, and a literal in `prosrc` is a fact.

Seven of the 26 are discharged right now: `edge:contact_submit`, `edge:customer_documents`,
`edge:inbound_email`, `edge:pdpl_request`, `edge:site_assistant`, `edge:sup_dob`, `edge:wa_inbound`.

The view now measures that literal — comments stripped, so a mention in a note is not a discharge —
and consults the recorded flag only where no routine discharges the source. The flag can no longer
contradict a measurement. This makes no gate green; the check must still reach 0. It removes the
ability to move the number by editing a column, and it lowers the ratchet to 19 so the correction
cannot be spent twice.

## What is still open, and what it will take

`fn_kernel_trigger_state` → `active_autonomous_source_not_yet_routing_through_the_inbox` = **19 of 37**
— 12 edge functions, 5 frontend paths, 2 database triggers.

The doors are built. All 24 active trigger types read `ADAPTER_READY_NO_LIVE_SENDER`; `fn_kernel_trigger_submit` calls `fn_kernel_workflow_start`; 18 routines already call `fn_kernel_source_emit`; 0 active class-A/B sources lack an adapter, a disposition, a trace policy or an accountable role. The 26 collapse to **10 adapter trigger types across 9 workflows** — 19 edge functions, 5 frontend paths, 2 database triggers.

Not shipped today, deliberately. Twenty-four cutover specs were drafted and adversarially reviewed; **9 of 18 verdicts came back UNSAFE**, and the two recurring reasons are the two that matter most here:

- **missed second creators** — a table trigger that also creates work, so the kernel and the old path would both open a run. That is what deadlocked 16 of 30 workflows once already.
- **idempotency keys built from surrogate row ids** — e.g. `edge:contact_submit` is *already* cut over by a table trigger, and its key is `NEW.id`, minted fresh at every insert. A double-submitted contact form opens two W18 cases today.

That last one is a defect the audit did not find and the specs did — and it is now **fixed and merged separately**, because it needed no cutover at all. See [PR #438](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/438).

Proved on production in an aborted transaction before touching anything: the same name, email, phone and message inserted twice gave `runs 18 → 19 → 20`, `tasks 52 → 54`, keys `edge:contact_submit:9 || edge:contact_submit:10`. **One contact form, two W18 customer cases, two tasks on customer_support.** The key is now `sha256(email|source|message)` — `source` included because `site_assistant` and `wa_inbound` write the same table, `name` and `phone` excluded so a typo corrected on the retry does not split one arrival in two. Re-probed after:

```
1st arrival              runs 18 -> 19   tasks 52 -> 53
replay, typo corrected   runs 19 -> 19   tasks 53 -> 53    zero additional effects
one character changed    runs 19 -> 20   tasks 53 -> 54    still gets its own case
```

No emitter was added — the trigger already called the door, only the value was wrong — so the two-creators trap does not apply and there is still exactly one creator.

Shipping 26 live customer paths — inquiry intake, Stripe webhooks, supplier quotes — on specs half of which failed review would risk the marketplace to make a number go green. The number is now watched, ratcheted so it cannot grow, and owned in `kernel-boards.json` marked `OPEN`.
