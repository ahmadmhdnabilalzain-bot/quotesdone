# Gates 8, 9 and 10 — autonomous sources

## Gate 8 — the inventory reconciles, and the three bridging rows are not what a summary would guess

Reproduced independently from `public.phase_c_source_cutover`, grouping by class, activation and
status rather than reading the builder's totals.

| class | ACTIVE | DISABLED | total |
|---|---|---|---|
| A NEW_WORK_REQUEST | 20 | 8 | **28** |
| B EXISTING_WORKFLOW_SIGNAL | 12 | 2 | **14** |
| C READ_ONLY_MONITOR | 19 | 3 | **22** |
| D RETIRE_OR_HISTORICAL | 3 | 0 | **3** |
| **total** | **54** | **13** | **67** |

Every builder count matches: discovered 67, active 54, inactive 13, and the four class totals.

The disposition roll-up also matches, and it is where the arithmetic question lives:

- `CUT_OVER` 32 = A active 20 + B active 12
- `READ_ONLY` 19 = C active 19
- `RETIRED_OR_INACTIVE` 16 = 13 disabled + D active 3

32 + 19 = 51, against 54 active. **The three rows are the three ACTIVE class-D rows**, derived from
the table before reading any explanation:

| source | status | why it is active yet neither cut over nor read-only |
|---|---|---|
| `dbtrigger:public.company_goals:trg_goal_cascade` | `BUSINESS_SIDE_EFFECT_DISABLED_BEHAVIOUR_OWED` | the trigger still fires and still supersedes objectives; only its task-creating statement is disabled |
| `edge:voice_otp` | `RETIRED` | disabled 18 Jul 2026 on a security finding; the deployed body is a 410 responder |
| `edge:voice_otp_capture` | `RETIRED` | retired the same day, same finding, same 410 responder |

That matches the two shapes the audit brief anticipated — one active-but-business-disabled, two
retired 410 endpoints — but it was derived from the data, not accepted from the builder.

Also measured, over the 32 active class-A/B rows: 0 without a kernel adapter, 0 without a recorded
disposition, 0 without a trace policy, 0 without an accountable role.

### `trg_goal_cascade`, proved inert by execution

Static reading is not enough here: the disabled statement is still present in the body, commented,
so a grep for `insert into org_tasks` matches it. So it was driven, in an aborted transaction:

```
retire one live company goal
  goal                          classification_accuracy
  org_tasks before / after      1066 / 1066
  superseded objectives before / after   0 / 4
raise exception -> rolled back
```

Retiring a goal supersedes its objectives and creates **zero** operational tasks. The trigger body
does not name W02. Wiring gap **#27** is recorded in `phase_b_phase_c_wiring_gap` stating that no
Phase B workflow starts from a goal retirement and that routing it to W02 was rejected on the merits.
Gate 8's `trg_goal_cascade` conditions are all met.

### Where Gate 8 fails

`fn_kernel_trigger_state()`, deployed and live:

```
check_name  active_autonomous_source_not_yet_routing_through_the_inbox
expected    0 of 37 active autonomous sources — NOT MET BY K10
actual      26 of 37 active autonomous sources still start or change business work
            without entering the kernel
ok          false
```

Gate 8's required result is `active source bypassing kernel = 0`. The estate's own board says 26.
The expectation string in the check even names the shortfall: *NOT MET BY K10*.

## Gate 9 — the real autonomous new-work entry path

Gate 9 asks for one currently active `NEW_WORK_REQUEST` source driven through its deployed entry
path, without calling `fn_kernel_workflow_start` by hand, and requires that the path be
source → adapter → trigger inbox → kernel → run → step run → task.

That path exists and is correct where it is wired: `fn_kernel_trigger_submit` calls
`fn_kernel_workflow_start` (measured true), 0 routines read `kernel_trigger_inbox` and create work
without it, 18 database routines call `fn_kernel_source_emit`, and the wrapper reaches past its two
adapters 0 times. `fn_kernel_trigger_state()` also reports 0 of 24 mapped trigger types routing
normal autonomous work through the founder or the Chief of Staff, and W01 is refused as a trigger
target by `a00_kernel_trigger_type_routing_guard` rather than merely being absent.

But it is not the universal path, and Gate 9's premise fails with Gate 8's:

```
fn_kernel_source_cutover_state()
  active_sources_now_calling_a_kernel_adapter
    11 of 32 active class-A/B sources reach the kernel
    (database triggers only — an Edge Function has no prosrc to scan,
     and saying so beats pretending the scan covered it)
```

Eleven of thirty-two, on a measurement that states its own bound honestly. Gate 9 is recorded FAIL
as a consequence of Gate 8, not on a separate defect.

## Gate 10 — existing-workflow signals

Inventory reconciled and green:

| measured | value |
|---|---|
| active class-B sources | 12 |
| active class-B sources not pointed at the signal adapter | 0 of 12 |
| class-B sources whose signal type is not registered | 0 of 14 |
| signal types registered / active | 11 / 6 |
| dispositions | ATTACH_ONLY, CANCEL, COMPLETE_STEP, REVIEW_VERDICT |
| signals that created a workflow run | 0 |
| duplicate signal delivery applied twice | 0 |
| refused signals with no stated reason | 0 of 0 |
| signals attached to a run that does not exist | 0 of 0 |
| signals processed without a trace | 0 of 0 |
| signal service body names `fn_kernel_workflow_start` | 0 — it may not, and does not |

### The four cases, driven per handler

`active_signal_types_are_executable.test.mjs` drives every one of the six active signal types through
all four cases the brief requires, in aborted transactions:

| signal type | disposition | valid | duplicate replay | invalid state | missing workflow |
|---|---|---|---|---|---|
| `clarification.response` | COMPLETE_STEP | accepted | 0 rows added | refused | refused |
| `document.arrived_for_run` | ATTACH_ONLY | accepted | 0 rows added | refused | refused |
| `followup.due` | ATTACH_ONLY | accepted | 0 rows added | refused | refused |
| `provider.callback` | ATTACH_ONLY | accepted | 0 rows added | refused | refused |
| `supplier.acknowledgement` | ATTACH_ONLY | accepted | 0 rows added | refused | refused |
| `supplier.quote_revision` | ATTACH_ONLY | accepted | 0 rows added | refused | refused |

Totals: valid-state accepted **6/6**, invalid-state refused **6/6**, missing-workflow refused **6/6**,
duplicate signals creating work **0**. Alongside: active signal type with no implemented handler **0**,
ACTIVE source targeting an INACTIVE signal type **0**, signal type with no recorded activation reason **0**.

No cutover result here rests on a source-string grep: each row was executed.

**Gate 10: PASS.**
