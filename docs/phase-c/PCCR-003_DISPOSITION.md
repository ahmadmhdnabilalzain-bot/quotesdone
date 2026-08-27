# PCCR-003 — FINAL DISPOSITION AS OF 2026-08-27

**Determination: RATIFIED. `AUTHENTICATED_FOUNDER_SESSION` on both ledgers.**

Governance decision **10**, recorded 2026-08-27 13:24:16.321812+00 against founder command
message **48415**, auth event 1614, route `auth.uid()`, subject
`1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14`. `phase_c_change_request` PCCR-003 now reads
`disposition = APPROVED`, `approval_basis = AUTHENTICATED_FOUNDER_SESSION`,
`governance_decision_id = 10` — all of it DERIVED from that decision, none of it written directly.
`fn_phase_c_freeze_drift()` reads **0 red of 11**.

It was never written-instruction-only, never rejected, never superseded and never rolled back. It was
an approval he gave in a verified session on 2026-08-22, recorded in the ledger that existed at the
time; what was missing was a row in the ledger PCCR-006 created three days later, and only he could
supply the sentence that authorised one.

---

## 1. The freeze-board row this was about

`select * from public.fn_phase_c_freeze_drift()` — **1 red row of 11** at 13:00 on 2026-08-27, and
**0 red of 11** at 13:24:

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

The denominator moved from 1 to 2 earlier in the session, because PCCR-007 was ratified through the
door and became APPROVED **with** a decision — a real fix moving the headline the wrong way before it
moved the right way. The numerator was PCCR-003, and is now 0 of 2.

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

## 3. Why the session could not clear it on its own

Three routes were available. Two are refused by design, and the third — the one that worked — is his.

**(a) Write the columns from a migration.** Refused — that is the defect, not the fix, and the brief
says so explicitly. Measured as D9.

**(b) Ratify it through `fn_phase_c_governance_decide`.** Attempted through a real founder session
over real HTTPS at 12:03 and **correctly refused**, because at that moment he had not typed a sentence
naming PCCR-003 and a digest — canary case **GOV-N11** as it stood then:

```
400  22023  fn_phase_c_governance_decide: no founder command message names both PCCR-003 and the
             digest f2a89bebcdf115c7…. The founder approves the document he read, and
             public.founder_command_message is where his words are recorded immutably. A sixty-four
             character hex string that appears in none of them is a value this call chose, not a
             document he approved. (pccr007_governance_digest_never_quoted)
```

`public.founder_command_message` held exactly three approval sentences at that point, and none named
PCCR-003:

| message | received | subject |
|---|---|---|
| 37730 | 2026-08-24 22:47:19+00 | `PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` sha256 `63cf6429…` |
| 40674 | 2026-08-25 16:54:20+00 | `PCCR-006` sha256 `c787bfcf…` |
| 46779 | 2026-08-26 12:35:30+00 | `PCCR-007` sha256 `f2a89beb…` |

The gate was doing exactly its job. A session minted from the management token is the **transport**;
the immutable message he types is the **authorisation**. Supplying the second one on his behalf would
be forging his approval, and this session did not do it — it asked him for the sentence instead, and
he sent it eighty minutes later.

**That case has since been rewritten so it cannot go stale again.** GOV-N11 named PCCR-003 as "the
change request he has never quoted", which stopped being true the moment he quoted it, and the case
came back ACCEPTED — a negative control describing a fact that had moved underneath it. It now
RESOLVES its subject from `public.founder_command_message`: the lowest-numbered change request that
appears in none of his messages beside a 64-character digest.

**(c) Split the board so PCCR-003 is a named, pinned grandfather.** This is a real option and the
26 August change request already wrote it up: the `NOT VALID` CHECK
`phase_c_change_request_approval_is_derived` **already grandfathers exactly this row**, so the
constraint and the board disagree about the same fact. Pinning the board by name — the way
`amendments_approved_on_the_one_time_command_bootstrap` is pinned at exactly one — would make the two
instruments agree without weakening anything: a second unbacked approval would still turn it red.

**It was not done, and the reason is not technical.** It is also no longer needed. `fn_phase_c_freeze_drift` is a mandatory
precondition of `PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` §A (*"every row `ok`"*), and §E of that
frozen standard reserves changing a denominator or a pass condition to the founder, through a change
request named `PHASE_D_ACCEPTANCE_STANDARD_CHANGE_REQUEST` carrying all six required elements
**including his approval**. Route (c) needs a longer sentence from him than route (b) does, for a
weaker result.

---

## 4. What cleared it — and it took four sends

One line in the Command Center, from `management@quotesdone.com`. He sent it at
2026-08-27 13:23:19.583535+00 as message 48415:

> **I approve PCCR-003 founder_authentication, sha256
> 0293839b1d000c326c84a9549323afba39ba67c638173c58d1c87431828df994**

`raw_text_hash` `e20d672171d9bebef072b163e68ba069907f87f3261bb9832f13b8d7ce3a832d`, recomputed on
production with `encode(sha256(convert_to(raw_text,'UTF8')),'hex')` and equal. The digest he
quoted is the file at commit `c645692a71cc2bdaef3306f8a23e9d1bd1f4762a`, and it is also the file
at HEAD — resolved by walking the document's git history, not by hashing the working tree.

**IT TOOK FOUR SENDS, AND THREE OF THEM WENT SOMEWHERE ELSE.** Recorded because the next person
to need a founder approval will hit the same wall:

| 13:14:27 | truncated at the word `sha256` — 115 characters, no digest. Became message 48402 and command 47100, which asked a clarification question |
|---|---|
| 13:17:50 | full sentence WITH the digest — routed into command 47100 as a clarification ANSWER, stored in `founder_command_clarification.answer_text`, never reaching `founder_command_message` |
| 13:20:48 | same again, second answer |
| 13:23:19 | sent as a NEW command — message **48415**, digest present, ratification recorded one minute later |

Two defects fall out of that and are recorded, not fixed here: a Command Center paste that is cut
mid-string, and a console that silently routes every subsequent message into an open clarification
so that the founder types the right words three times and none of them lands where the estate
reads them. The Secretary's reply — *"no registered command intent matches this instruction"* — is
expected and harmless: there is no work-intent for an approval sentence, and the governance door
reads the message, not the classification.

That digest is the file as committed at HEAD (`8db01d6`), recomputed with
`sha256sum docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-003.md`. Then:

```bash
node scripts/phase_d/prove_governance_door.mjs --record --ref=PCCR-003
```

It resolved the digest out of his message, matched it against a committed revision of the document,
drove `fn_phase_c_governance_decide` through a real founder session over HTTPS, and wrote decision
10. The original deployment date (2026-08-21) and the original amendment-ledger approval
(2026-08-22) are carried in the reason text unchanged — the row records a **retrospective
ratification**, not a claim that he approved it today.

The door works: **22 of 22** authorization cases correct on 2026-08-27, twice — once ratifying
PCCR-007 and once PCCR-003. `public.phase_c_governance_decision` now holds two rows, both
`AUTHENTICATED_FOUNDER_SESSION`, both against a digest he typed himself.

---

## 5. Required outcomes, stated against what was measured

| required | result |
|---|---|
| written instruction presented as authenticated session = **0** | **0.** `amendments_approved_on_written_instruction_only` reads 0 of 7. Nothing in this session recorded a written instruction as a session. |
| PCCR-003 cleared by migration-written `approved_by` = **0** | **0.** Refused by `a05_phase_c_change_request_approval_is_derived`, measured (D9). |
| Phase C freeze-board red caused by PCCR-003 = 0 | **NOT MET — 1 red row.** It requires one Command-Center sentence from the founder, given verbatim in §4. This is the only item in this session that is his and not mine. |
