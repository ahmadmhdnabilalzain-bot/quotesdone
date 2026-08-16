# Phase C correction — canary results

Every canary below was run against the live project `htdblwldjkcgjvmqkbeh` on 2026-08-16 with
`NO_PAID_AI=true`, `OPENROUTER_DISABLED=true`, `AI_PROVIDER_MODE=mock`. A/B are real authenticated
HTTPS requests to `os_api` as `management@quotesdone.com`; C/D are committed executions of the
canonical runtime; E is an aborted-transaction probe so it leaves nothing behind.

## A — real authenticated founder command

`POST /functions/v1/os_api {action:'founder_command'}` → **HTTP 200**, command **227**.

| Requirement | Result |
|---|---|
| Correct workflow/event | `intent CMD-W20`; outbox 245 = **`EV-W20-STARTED`, workflow `W20`, accountable and consumer `marketing_director`**. The `EV-W01-STARTED` / `ceo` literal is gone |
| Correct primary owner | `primary_role_id = marketing_director`, `command_owner_role_id = chief_of_staff` |
| Atomic tasks | 785–788, all four created in the same transaction as the command and the message |
| Root trace | 509, `state_after = tasks_created`, in step with the command (it read `interpreting` before) |
| Child traces | 510, 511, 512, 513 — one per task, each `parent_trace_id = 509` |
| No side effects | `founder_approval_request` = 0; no publish, no send; outbox row pending, not delivered externally |
| Readback | `founder_command_status` 200, `founder_command_thread` 200, `founder_command_inbox` 200 |
| Idempotency | replay with the same key returned command **227**, zero delta on every counter |

## B — ambiguous founder command

**Command 223** — the one the independent audit left stuck — was resolved through the real
authenticated path, not deleted.

```
POST os_api {action:'founder_command_clarify', command_id:223, answer:'Publish two extra LinkedIn
posts about supplier sourcing this week, held for brand and quality review before publication.
No paid advertising and no paid AI.'}                                              → HTTP 200
```

| Requirement | Result |
|---|---|
| Original founder message preserved | `founder_command_message.raw_text` still reads exactly `Make marketing better.` |
| Clarification response appended | `founder_command_clarification` row 9: question + `answer_text` verbatim + `answered_at 10:35:14` |
| One command id retained | 223 throughout; no second command was created |
| Zero tasks before the reply | measured immediately before: `state = clarification_required`, tasks = **0** |
| Interpretation resumes | `clarification_required → interpreting → accepted → routed → tasks_created`, intent `CMD-W20` |
| Tasks after the reply | 789–792, four canonical owners |
| Event | `EV-W20-STARTED` (outbox 246) — the workflow the clarified instruction actually selected |
| Cancellation works | separate ambiguous command **228** (`Improve things.`): 0 tasks, then `founder_command_control` cancel → **HTTP 200**, `status: cancelled` |
| Trace and audit | root trace 472 advanced with the command; `os_audit_log` records the actor as `management@quotesdone.com` |

## C — autonomous W05 event

`fn_phase_c_event_ingress('EV-W05-STARTED','ZZ-CANARY-RFQ-2026-08-16', …)`

| Requirement | Result |
|---|---|
| Exactly one workflow run | run **94**, W05, accountable `rfq_qualification_manager` |
| Exactly one initial step run | step run **38**, `W05-S01`, state `active` |
| Exactly one accountable task | task **793**, owner `rfq_qualification_manager`, department `marketplace` |
| Canonical event/outbox record | outbox **247**, `EV-W05-STARTED`, trace 519 |
| Chief of Staff absent | tasks owned by `chief_of_staff` or `ceo` on this run: **0** |
| Founder absent | `founder_command` rows created: **0** |
| AI CEO absent | `ceo` appears nowhere in the run, the step run or the task |
| Trace present | run trace 519, task trace 520 (parent 519), step trace 525 |
| No external side effect | no mail, no publish, no payment |
| No paid inference | `llm_attempt` and `ai_cost_log` unchanged |

Step execution: `fn_phase_c_step_advance(94,'W05-S01',…)` with a real structured output →
`ok: true`, **`output_hash = d4fe33d2f0921d…`** (not `e3b0c442…`, the SHA-256 of the empty string),
event **`EV-W05-S01-COMPLETED`** emitted, task 793 walked `queued → assigned → accepted →
in_progress → completed` through the state model, a trace at every hop.

## D — multi-department autonomous event

W02, `ZZ-CANARY-MULTIDEPT-2026-08-16`, handoff `H-W02-01-02`.

| Requirement | Result |
|---|---|
| One coordination owner | run 95, `accountable_role_id = corporate_performance_director` |
| One accountable owner per child task | handoff run 48: sender `corporate_performance_director` (exec) → receiver `data_intelligence_director` (data_intel); `accountable_until_accept` moves to the receiver on accept |
| Explicit handoffs | packet hash, acceptance criteria, SLA-HANDOFF-STANDARD, return owner, all recorded; traces 521 (open) and 522 (accept) |
| No founder approval | `founder_approval_request` = **0** |

## E — refund guards

Aborted-transaction probe; each guard was given the input it must reject.

| Injected | Result |
|---|---|
| non-refund founder approval (`action_class = marketing_publish`) | refused, **23514** |
| refund decision by a non-founder, no founder decision | refused, **28000** |
| executor = reconciler | refused, **23514** |

## Suite

| Check | Result |
|---|---|
| `fn_phase_c_invariants()` | **71 of 71 pass** |
| `phase_c_guards_reject_injected_defects` | **55 of 55 injected defects refused** |
| `phase_c_founder_chain` | FOUNDER CHAIN VERIFIED END TO END |
| `phase_c_command_center_entry_point` | COMMAND CENTER ENTRY POINT VERIFIED |
| `phase_c_invariants.test.mjs` | PHASE C INVARIANTS PASS |
| `phase_b_invariants` | 77 of 77 |
| `sql_files_match_live` | 439 routines, 0 missing, 0 drifted |
| Phase A / Phase B / Phase C baseline drift | 0 / 0 / 0 |
