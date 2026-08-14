# V3 REMEDIATION — STAGE 7: CROSS-DEPARTMENT HANDOFFS

**Nothing here is a certification.** Internal work cannot certify a role, a department or a
category. Only an independent evaluator can, and none has re-run since `V3-COR-0A782DA90B10`
(56.97% overall, 0 of 96 roles). Everything below is a measurement I took myself on Supabase
project `pglpqrhvozwepymcuunn` on 14 Aug 2026 between 14:13 and 14:20 UTC, or a file I read.

## The bottom line, measured first

`handoff_contract` exists, is fully constrained, and **holds zero rows**. Every one of the
19 `agent_actions` rows with `kind='handoff'` is still contract-less:

```sql
select (select count(*) from handoff_contract) as contracts,
       (select count(*) from agent_actions where kind='handoff') as handoff_actions,
       (select count(*) from v_handoff_without_contract) as without_contract;
-- contracts=0  handoff_actions=19  without_contract=19
```

I watched that middle number rise from **16 → 18 → 19** across three queries I ran during this
session. Two of the new rows I inspected directly — `agent_actions` id 516 (`contract_specialist`
→ `legal`, 14:15:19 UTC) and id 520 (`bi_analyst` → `analytics`, 14:16:21 UTC) — both written by
the live `agent_brain` path, both `target_table` null. Three of the 19 were written after the
stage-7 commit timestamp (50a534a, 14:07:43 UTC). `select count(*) ... where target_table =
'handoff_contract'` returns **0**.

The schema is real and it works. It has no caller. That is the same defect class the certification
named — a capability with no entry point — and it is the top remaining gap.

## 1. The twelve required fields

From `information_schema.columns` (25 columns total; the 12 contract fields mapped):

| Required field | Column | Type | Null? |
|---|---|---|---|
| Originating department | `from_dept` | text | NO |
| Accountable owner | `accountable_owner` | text | NO |
| Receiving department | `to_dept` | text | NO |
| Receiving role | `to_role` | text | NO |
| Purpose | `purpose` | text | NO |
| Evidence included | `evidence` | jsonb, default `'[]'` | NO |
| Requested decision/action | `requested_action` | text | NO |
| Deadline | `deadline` | timestamptz | NO |
| Acceptance criteria | `acceptance_criteria` | text[], default `'{}'` | NO |
| Closure criteria | `closure_criteria` | text[] | NO |
| Escalation conditions | `escalation_conditions` | text | NO |
| Return status | `return_status` | text | YES (null until answered) |

## 2. What actually enforces them

`pg_constraint` returns **16 constraints**: 8 CHECK, 6 FK, 1 PK, 1 UNIQUE. Plus 5 indexes,
1 trigger, RLS enabled, **0 RLS policies**.

* `closure_criteria_check` — `cardinality(closure_criteria) >= 1`. This is the CMP-QA-02 fix
  (7.29%): a handoff that never said what "closed" means cannot be created.
* `purpose_check` / `requested_action_check` — `length(btrim(...)) >= 10`, so a one-word ask fails.
* `escalation_conditions_check` — non-blank. `to_role_check` — non-blank.
* `evidence_check` — must be a JSON array.
* `status_check` — open/accepted/rejected/returned/closed. `return_status_check` — accepted,
  rejected, rejected_incomplete, returned_for_correction, closed.
* FKs to `org_departments(dept_key)` (from and to) and `org_agents(agent_key)` (owner, accepter,
  closer); `action_id` UNIQUE and FK to `agent_actions(id) ON DELETE CASCADE` — 1:1 with transport.
* Partial unique index `handoff_contract_live_idem_idx` on `idempotency_key WHERE status IN
  ('open','accepted','returned')` — the replay guard, CMP-HO-06 (9.38%).
* Trigger `a00_handoff_contract_guard` (`scripts/sql/v3_repair_07_handoff_contract.sql:102-175`) —
  owner validity, the lifecycle, and per-criterion closure proof, enforced against a direct UPDATE.

## 3. The probes — what each one actually did

All nine were `DO` blocks ending in `raise exception`, so every write rolled back. Verified after:
contracts back to 0, `analytics` / `ap_specialist` / `compliance_mgr` / `financial_analyst` all
`active=true` again.

**P1 — clean handoff.** `fn_handoff_open` with all 12 fields returned
`{ok:true, id:41, action_id:510, receiving_agent:"compliance_mgr", complete:true,
rejectable_on_arrival:false}`. The row carried all twelve; the transport row was
`agent=compliance_mgr kind=handoff status=needs_review target_id=41`. Routing picked
`compliance_mgr` from the role string "compliance manager" without being told the key.

**P2 — rejected incomplete.** A request missing four fields was refused outright:
`missing:["requested_action","escalation_conditions","deadline","closure_criteria"]`. A request
that was openable but had no evidence and no acceptance criteria opened with
`rejectable_on_arrival:true`. The receiver's `accept` was **refused** —
`"handoff is incomplete and cannot be accepted"`. `reject` with a reason set
`return_status='rejected_incomplete'`, moved the transport row to `done/rejected`, and wrote
**1** `agent_memory` row to the sender.

**P3 — conflicting departmental advice.** The same question opened to `legal` (id 43) and
`data_intel` (id 44) produced two contracts with different idempotency keys, each accepted and
closed with contradictory proof — "cost offset, IFRS 15" versus "revenue, matches the rebate feed".
A byte-identical replay of the first returned `{duplicate:true, id:43}` instead of opening a third.
So conflict is preserved as two owned, proven records rather than one; the pre-declared tie-break
lives in `escalation_conditions`. **Nothing automatically flags the contradiction** — both rows are
`closed` and `v_handoff_stalled` correctly ignores them.

**P4 — overdue.** A past deadline is refused at open time (`"deadline is already in the past"`).
Aging two live rows produced exactly two view rows: `overdue_never_accepted` at 4.00 days late and
`overdue_accepted_not_closed` at 9.00 days late. `fn_handoff_stalled('legal')` returned 1,
`fn_handoff_stalled(null)` returned 2.

**P5 — failed receiving agent.** With the accepting agent deactivated, both `fn_handoff_close` and
`fn_handoff_respond` refused: *"only an active employee of the receiving department may…"*. With
every `data_intel` agent deactivated, `fn_handoff_open` refused: *"receiving department has no
active employee to accept it"*. When only the **receiver** went inactive, `v_handoff_stalled`
returned **NONE** — the work is frozen and invisible until the deadline passes. When the
**accountable owner** went inactive, the row appeared immediately as `owner_inactive`.

**P6 — returned correction.** Accept → `return` with no reason: refused (*"a return must state
why"*). Return with a reason: `returns_count=1`, `return_status='returned_for_correction'`, sender
notified in their own memory. Amend by a *different* active finance employee: status back to
`open`, `owner_changed:true`, ownership moved to `financial_analyst` and stamped on the transport
row as `amended_by`. Re-accept succeeded. `OWNERLESS_ROWS=0` throughout. An amend attempt by
`ar_specialist` (not on the finance roster) was refused.

**P7 — final closure.** Proof for 1 of 2 criteria: refused, naming
`unproven:["position filed against the Q3 batch"]`. A direct UPDATE with a whitespace-only evidence
string: refused by the trigger, same criterion named. A direct UPDATE to `closed` with no evidence:
refused for both criteria. `status='closed'` with no closer: *"a closure must record who closed it
and when"*. Ownership attacks: blank refused, `nobody_at_all` refused ("not on the roster"),
`compliance_mgr` refused ("belongs to legal, not the originating department finance"). The
legitimate close with both criteria proven succeeded, transport went `done/closed`, and the row
left `v_handoff_stalled`.

**P8 — table-level floors.** Insert with `closure_criteria='{}'` violates the CHECK. Insert with
`acceptance_criteria='{}'` **is allowed** — acceptance criteria are enforced at acceptance time
(P2), not at insert. `open → closed` refused ("illegal transition"); reopening a closed row
refused ("closed is terminal").

**P9 — the legacy path against a contract.** The receiver's actual inbox line was:
`- #527 (0d old, from ap_specialist): Handoff — <purpose> — <requested action>`. No deadline, no
acceptance criteria, no closure criteria, no escalation condition. `fn_handoff_answer` then
returned `{ok:true, asker_notified:true}`, marked the transport row `done` — and left the contract
`status='open'`, `closure_evidence` null. `v_handoff_stalled` caught it as
`transport_closed_contract_open`.

## 4. The acceptance criteria for this stage

* **No task loses ownership** — `accountable_owner` NOT NULL, FK to `org_agents`, plus the guard
  rejecting blank / off-roster / inactive / wrong-department. P6 moved ownership explicitly and
  recorded it; `OWNERLESS_ROWS=0`. **Met at the schema level.**
* **Every handoff has acceptance and closure criteria** — closure criteria enforced by CHECK at
  insert; acceptance criteria enforced at acceptance (P2, P8). **Met, with the asymmetry stated.**
* **Management can identify stalled handoffs** — `v_handoff_stalled` ran and returned the right
  reason in five distinct shapes. On real data it returns **0**, because there are no contracts.
  **The instrument works; it has nothing to watch.**

## 5. Relationship to the existing path — and the top remaining gap

The contract extends the old path rather than replacing it. `fn_handoff_open` still writes the
`agent_actions` row, so `fn_agent_handoff_inbox` is untouched and `tool_id='handoff_inbox'` still
resolves (`supabase/functions/_shared/tools.ts:144`).

**Nothing writes `handoff_contract`.** Measured four ways:

1. Repo-wide search of all `.ts/.tsx/.mjs/.js` for `handoff_contract`, `fn_handoff_open`,
   `fn_handoff_respond`, `fn_handoff_amend`, `fn_handoff_close`: **no matches**.
2. `pg_proc.prosrc ILIKE '%fn_handoff_open%'` outside the function itself: **0**. Other routines
   touching the table: **NONE**.
3. `cron.job` commands mentioning handoff: **NONE**.
4. `handoff_contract` row count: **0**, while 19 handoff transports exist.

The live writer is still `supabase/functions/agent_brain/index.ts:521` — a raw
`agent_actions.insert({kind:'handoff'})` — and the only close verb the model has is
`fn_handoff_answer` (`:536`), which P9 showed leaves the contract open. The model's action grammar
has no accept, reject, return or close.

The read side *is* wired: `handoff_stalled` is registered in `agent_tool`, and `agent_tool_call`
shows 6 real calls — 4 `error` then 2 `ok_empty` after the generic `p_` argument mapping was added
(`tools.ts:147-156`). Management can already ask the question. There are no answers to find.

## 6. Still broken or unverified

1. **No writer — the top gap.** Until `agent_brain` opens contracts instead of raw rows, every
   guard here is unreachable and `CMP-HO-05/06/07` and `CMP-QA-02` remain unimprovable in a re-test.
2. **The inbox never shows the terms.** P9: `fn_agent_handoff_inbox` renders only id, age, sender,
   title and recommendation, capped at 215 chars per line. A receiver could not accept *against*
   the criteria even if a contract existed.
3. **`fn_handoff_answer` silently bypasses closure.** It is still registered and still callable on a
   contracted handoff. Detected after the fact by `v_handoff_stalled`, not prevented.
4. **A deactivated receiver is invisible** until the deadline passes (P5).
5. **Contradictory closures are not flagged** (P3). Only `escalation_conditions` names the tie-break,
   in prose.
6. **No regression coverage.** `scripts/checks/v3_remediation_regression.mjs` contains the string
   "handoff" **0 times**, while the requirement matrix row `CMP-HO-01` points at
   `REG-CROSS_DEPARTMENT-*` and is marked `IN_PROGRESS`.
7. **RLS enabled, 0 policies.** Correct-by-default for service_role, unverified for any other role.
8. **Only project `pglpqrhvozwepymcuunn` was measured.** I did not query the production project and
   state nothing about it.
9. **No behavioural claim.** Every measurement is structural or a probe I ran. Nothing here shows an
   agent reasoning better about a handoff, and no score has moved.
