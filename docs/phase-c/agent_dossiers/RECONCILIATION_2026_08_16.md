# Agent-by-agent reconciliation — 16 Aug 2026

Source: `QuotesDone_AGENT_BY_AGENT_REPORTING_AND_OPERATING_DOSSIERS_v2026.08.16`, delivered by the
founder as the detailed interpretation of the founder-approved Phase A organisation and Phase B
workflow ownership.

Every map in the package was compared, row by row, against the live production database
(`htdblwldjkcgjvmqkbeh`). Identities on **both** sides are resolved through `org_role_alias` before
comparison — the package addresses roles by descriptive name (`accounts_payable_specialist`), the
database by physical key (`accounts_payable`), and comparing one resolved side against one raw side
manufactures mismatches that are not there.

## Result

| Map | Rows | Matching |
|---|---:|---:|
| `AGENT_MASTER_INDEX` — identity, department, manager, class, direct reports | 90 | **90 / 90** |
| `AGENT_WORKFLOW_PARTICIPATION` vs `org_workflow_ownership` | 151 | **151 / 151** |
| `AGENT_STEP_RESPONSIBILITY` vs `phase_c_step_binding` | 540 | **540 / 540** |
| `AGENT_HANDOFF_MAP` vs `phase_b_handoff` | 480 | **480 / 480** (161/161 distinct handoffs) |
| `AGENT_EVENT_MAP` vs `phase_b_event` | 632 | **632 / 632** (347/347 distinct events) |
| `AGENT_COMMAND_CENTER_MAP` vs `phase_c_command_intent` | 70 | **70 / 70** |
| `AGENT_AUTHORITY_MAP` vs `phase_c_action_class` | 66 | **54 / 66** — see note |
| `AGENT_SYSTEM_ACTOR_ACCOUNTABILITY` vs `phase_c_system_actor` | 10 | **10 / 10** |
| `AGENT_REVIEW_RELATIONSHIPS` — distinct creator/reviewer identities | 50 | **50 / 50** |
| `OVERLAY_MASTER_INDEX` — 9 governance fields per overlay | 86 | **86 / 86** |
| 90 individual dossiers — reporting path to founder, walked in the live graph | 90 | **90 / 90** |

**Structural corrections made: none.** Nothing in this package required a change. It confirms the
organisation as reconciled to the reporting map earlier the same day (PACR-001).

## The 12 authority rows, and why they are not a mismatch

Four action classes — `supplier_suspension`, `marketing_publish`, `public_claim_publish`,
`production_release` — differ from the dossier in the free-text `review_or_contributors` field, and
in nothing else. The difference is a connector word:

```
live:    "general_counsel; compliance_privacy_officer"
dossier: "general_counsel or compliance_privacy_officer"
```

Resolved through the alias table, the **set of roles named is identical on both sides** in all four
cases. A semicolon where the dossier writes "or" is prose, not structure, and the instruction was to
correct only confirmed structural mismatches. Rewriting it would edit wording, change nothing about
who reviews what, and put a diff in front of a future reader that means nothing.

## Two findings that were mine, not the system's

Recorded because both would have been reported as defects by a less careful pass:

1. **A stale snapshot invented a conflict between two founder packages.** A first run appeared to
   show the dossier package contradicting the reporting map on 23 reporting edges. The snapshot of
   `org_role` had been taken before the PACR-001 corrections were applied. Compared directly, the two
   packages **agree on every manager and every class** — they are consistent documents, and the
   apparent contradiction was entirely an artefact of measuring against yesterday's copy.

2. **A negation-blind keyword scan scored three refusals as violations.** A regex asking "does a role
   own something its dossier forbids" flagged `marketplace_content_privacy_reviewer` (owns *blocking*
   dispatch), `supplier_matching_dispatch_operator` (owns *refusing* to dispatch when a gate fails)
   and `payments_billing_manager` (owns payment *rail configuration*). All three own the authority to
   stop or configure, which is the opposite of the act the dossier forbids. Absence of a commission
   is not a commission. The enforced side agrees: `fn_phase_a_organization_violations()` reports
   `owns_founder_reserved_decision = 0`.

## What was measured, and what was not

The decision arrays (`owned_decisions`, `forbidden_decisions`) were compared **lexically**, and the
wording differs widely from the dossier prose — mean significant-term overlap 41% owned, 14%
forbidden. That number is reported here as what it is: a measure of vocabulary, not of substance.
`accounts_payable` forbids "releasing a payment without the CFO" and "approving a bill it entered"
where its dossier says "approve its own vendor or exceed budget" — the same limit in different words,
and a lexical score cannot tell that from a real divergence. No structural claim is made from it, and
nothing was rewritten: editing 90 roles' decision prose is knowledge work, which this session was
explicitly told not to begin.

## Chain of command, verified by execution

- **Founder command.** `fn_founder_command_submit` executed in an aborted transaction: the command
  is owned by `chief_of_staff`, resolved to a canonical intent, routed to the frozen workflow's own
  accountable owner, and child tasks created for the exact step owners. The Chief of Staff coordinates
  and reports; it does not take ownership from the workflow owner.
- **Autonomous entry.** Of 257 Phase B steps, exactly **4** are owned by the founder or the Chief of
  Staff, and all four are in W01 (founder mandate to company objectives) and W02 (company target miss
  and corrective management) — the two founder-facing workflows. No normal autonomous work routes
  through either. `fn_phase_c_reporting_map_drift()` now enforces this, naming W01 and W02 explicitly
  so a new workflow cannot quietly join the exception.
- **Founder approval.** `refund_decision` is the only action class requiring it, and a partial unique
  index makes a second one unwritable. Proved both ways in an aborted transaction: a non-refund
  `founder_approval_request` is refused with "the founder is not the company's approval queue"; a
  refund one is accepted. `CMD-W17` (W17 = *Refund, dispute and fraud*) carries
  `YES_ONLY_IF_REFUND_DECISION` and `CMD-MULTI` carries `NO_EXCEPT_REFUND_CHILD`; every other intent
  is a plain `NO`.

Zero OpenRouter requests. Zero paid inference.
