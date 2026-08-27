# PCCR-003 — FINAL DISPOSITION AS OF 2026-08-27

**Determination: `AUTHENTICATED_FOUNDER_SESSION` on the amendment ledger, and
`PRE_LEDGER — AWAITING ONE COMMAND-CENTER LINE` on the governance ledger.**

It is **not** written-instruction-only. It is **not** rejected, superseded or rolled back. It is an
approval he gave in a verified session, recorded in the ledger that existed at the time, and there is
exactly one thing left to do about it — and only he can do it.

---

## 1. The freeze-board row this is about

`select * from public.fn_phase_c_freeze_drift()` — **1 red row of 11**, 2026-08-27:

```
approved_change_requests_with_no_verified_governance_decision
  expected 0
  actual   1 of 2 approved
  ok       false
```

The predicate:

```sql
select count(*) from public.phase_c_change_request cr
 where cr.disposition = 'APPROVED'
   and not exists (select 1 from public.phase_c_governance_decision d
                    where d.decision_id = cr.governance_decision_id
                      and d.change_request_ref = cr.change_request_ref
                      and d.decision = 'APPROVED')
```

The denominator moved from 1 to 2 this session because PCCR-007 was ratified through the door and is
now APPROVED **with** a decision. The numerator is unchanged and is PCCR-003.

---

## 2. What PCCR-003's approval actually is

Two rows, two different facts, and conflating them is how this stayed unclear.

**`public.phase_c_freeze_amendment` amendment 36 — a real verified founder session.**

| field | value |
|---|---|
| subject | `founder_authentication` |
| object | `fn_phase_c_require_founder(p_actor text)` |
| deployed | `2026-08-21 20:20:33.073784+00` |
| approved_at | `2026-08-22 21:55:32.166844+00` |
| approval_basis | `AUTHENTICATED_FOUNDER_SESSION` |
| approval_route | `auth.uid()` |
| approval_auth_subject | `1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14` |
| approved_amendment_table_digest | `969830f0495bc68067bb8ba3732976bb9f2945d913bcad3815d74472b35603a2` |
| approved_amendment_table_path | `docs/phase-d/PHASE_D_PCCR_AMENDMENT_TABLES.md` |

That is a bearer token GoTrue issued for an active founder identity, recorded through
`fn_phase_c_freeze_amendment_approve`, with a negative control in the same run proving the identical
call from `service_role` was refused. `fn_phase_c_freeze_drift`'s own
`amendments_approved_on_written_instruction_only` reads **0 of 7** and always has for this row.

**`public.phase_c_change_request` PCCR-003 — a migration backfill, and it says so.**

```
approved_by      management@quotesdone.com
approved_at      2026-08-21 20:20:33.073784+00
approval_basis   NULL
approval_route   NULL
approval_auth_subject  NULL
governance_decision_id NULL
disposition_reason
  "Approved by management@quotesdone.com on 2026-08-21. Backfilled by phase_d_o15: the column was
   added by phase_d_o09 and defaulted to RAISED on a request that already carried an approver."
```

Those approval columns were written by a migration deriving them from the amendment. That is the
practice PCCR-006 exists to end, and PCCR-006 ended it: `a05_phase_c_change_request_approval_is_derived`
now refuses every writer of those columns except a governance decision in the same transaction —
measured this session as case **D9**, `42501 pccr_governance_decision_required`.

**`public.phase_c_governance_decision` — the ledger PCCR-006 created on 2026-08-25, three days after
he approved PCCR-003.** It held 0 rows until 2026-08-27 12:03 UTC. PCCR-003 could not have a row in
it: the ledger did not exist.

---

## 3. Why this session did not clear the row, and would not have been right to

Three routes were available. Two are refused by design and the third is his.

**(a) Write the columns from a migration.** Refused — that is the defect, not the fix, and the brief
says so explicitly. Measured as D9.

**(b) Ratify it through `fn_phase_c_governance_decide`.** Attempted through a real founder session
over real HTTPS and correctly refused — canary case **GOV-N11**:

```
400  22023  fn_phase_c_governance_decide: no founder command message names both PCCR-003 and the
             digest f2a89bebcdf115c7…. The founder approves the document he read, and
             public.founder_command_message is where his words are recorded immutably. A sixty-four
             character hex string that appears in none of them is a value this call chose, not a
             document he approved. (pccr007_governance_digest_never_quoted)
```

`public.founder_command_message` holds exactly three approval sentences, and none names PCCR-003:

| message | received | subject |
|---|---|---|
| 37730 | 2026-08-24 22:47:19+00 | `PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` sha256 `63cf6429…` |
| 40674 | 2026-08-25 16:54:20+00 | `PCCR-006` sha256 `c787bfcf…` |
| 46779 | 2026-08-26 12:35:30+00 | `PCCR-007` sha256 `f2a89beb…` |

The gate is doing exactly its job. A session minted from the management token is the **transport**;
the immutable message he typed is the **authorisation**. Supplying the second one on his behalf would
be forging his approval, and this session did not do it.

**(c) Split the board so PCCR-003 is a named, pinned grandfather.** This is a real option and the
26 August change request already wrote it up: the `NOT VALID` CHECK
`phase_c_change_request_approval_is_derived` **already grandfathers exactly this row**, so the
constraint and the board disagree about the same fact. Pinning the board by name — the way
`amendments_approved_on_the_one_time_command_bootstrap` is pinned at exactly one — would make the two
instruments agree without weakening anything: a second unbacked approval would still turn it red.

**It was not done, and the reason is not technical.** `fn_phase_c_freeze_drift` is a mandatory
precondition of `PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` §A (*"every row `ok`"*), and §E of that
frozen standard reserves changing a denominator or a pass condition to the founder, through a change
request named `PHASE_D_ACCEPTANCE_STANDARD_CHANGE_REQUEST` carrying all six required elements
**including his approval**. Route (c) needs a longer sentence from him than route (b) does, for a
weaker result.

---

## 4. What clears it, exactly

One line in the Command Center, from `management@quotesdone.com`:

> **I approve PCCR-003 — founder_authentication — as set out in
> `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-003.md`, sha256
> `0293839b1d000c326c84a9549323afba39ba67c638173c58d1c87431828df994`.**

That digest is the file as committed at HEAD (`8db01d6`), recomputed with
`sha256sum docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-003.md`. Then:

```bash
node scripts/phase_d/prove_governance_door.mjs --record --ref=PCCR-003
```

which resolves the digest out of his message, verifies it matches a committed revision of that
document, drives `fn_phase_c_governance_decide` through a real founder session, and writes the
governance-ledger row. The original deployment date (2026-08-21) and the original approval date
(2026-08-22) are carried in the reason text unchanged — the ledger row records a **retrospective
ratification**, not a claim that he approved it today.

Everything on this side of that sentence is built, deployed and proved. The door works: PCCR-007 went
through it 22 of 22 cases correct on 2026-08-27.

---

## 5. Required outcomes, stated against what was measured

| required | result |
|---|---|
| written instruction presented as authenticated session = **0** | **0.** `amendments_approved_on_written_instruction_only` reads 0 of 7. Nothing in this session recorded a written instruction as a session. |
| PCCR-003 cleared by migration-written `approved_by` = **0** | **0.** Refused by `a05_phase_c_change_request_approval_is_derived`, measured (D9). |
| Phase C freeze-board red caused by PCCR-003 = 0 | **NOT MET — 1 red row.** It requires one Command-Center sentence from the founder, given verbatim in §4. This is the only item in this session that is his and not mine. |
