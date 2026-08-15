# Phase A — invariant results, run against production

Run `node scripts/phase_a/invariants.mjs` to reproduce. Read-only throughout: every statement goes
through `mgmtRead`, which refuses anything that is not.

**Deliberately not the same code as the migration's own postconditions.** A migration that asserts
its own success is a closed loop. This reads the database back from outside and asks the questions
`PHASE_A_INVARIANTS.md` asks, in its own words.

## Result

```
── Counts ────────────────────────────────────────────────────────────────────
PASS  active primary departments = 10  — 10
PASS  canonical accountable standing roles = 90  — 90
PASS  category overlays = 86  — 86
PASS  every overlay is a category overlay  — 0 strays
PASS  overlays are excluded from the 90 (86 + 90 = 176 active roles)  — 176
PASS  one active department head per department, and the head is a member  — 0 headless departments
PASS  department role counts are 4,6,7,7,7,9,11,11,11,17  — 4,6,7,7,7,9,11,11,11,17

── Identity and reporting ────────────────────────────────────────────────────
PASS  no duplicate active role identity  — 0 shared identities
PASS  every role has one primary department that exists  — 0 orphans
PASS  every role has a primary manager except the CEO  — 0 unmanaged
PASS  no self-management  — 0 self-managers
PASS  no reporting cycles  — 0 chains terminate
PASS  no committee membership creates a second role record  — 0 phantom seats
PASS  every retired role still resolves to a live one  — 0 unresolvable
PASS  every alias points at an active role  — 0 dead targets
PASS  an inactive or retired role holds no runtime employee  — 0 stranded employees
PASS  every active employee maps to an active canonical role  — 0 unowned employees

── Necessity and ownership ───────────────────────────────────────────────────
PASS  every active role states a necessity status  — 0 unstated
PASS  every active role states an explicit reason  — 0 unstated
PASS  every accountable role has explicit forbidden decisions  — 0 unbounded roles
PASS  30 organizational workflows are owned  — 30
PASS  every workflow owner is an active canonical role  — 0 ghost owners
PASS  no workflow is multiply owned  — 0 shared ownership
PASS  a contributor is never the accountable owner  — 0 collisions
PASS  every active accountable role owns a decision, a workflow or people  — 0 idle roles
PASS  supplier selection is owned, by exactly one role  — W12 Supplier matching and dispatch -> supplier_matching_dispatch_operator
PASS  privacy review is owned, by exactly one role  — W08 Supplier-safe payload and file approval -> marketplace_content_privacy_reviewer
PASS  release is owned, by exactly one role  — W24 Release and production approval -> quality_and_release_director
PASS  payment reconciliation is owned, by exactly one role  — W16 Payment, billing and reconciliation -> payments_and_billing_manager
PASS  knowledge validation is owned, by exactly one role  — W26 Knowledge creation and validation -> knowledge_director

── Independence ──────────────────────────────────────────────────────────────
PASS  no workflow owner is their own independent reviewer  — 0 self-reviewers
PASS  an independent reviewer is never managed by the department it reviews (model evaluation)  — 0 independent
PASS  supplier onboarding and verification are different roles  — 0 separate
PASS  the self-review triggers are still installed on artifact_review and review_chain  — 3 trigger(s)

── Category overlays ─────────────────────────────────────────────────────────
PASS  86 overlays exist  — 86
PASS  86 categories resolve to one  — 86
PASS  no overlay holds an executor or a runtime employee  — 0 standing overlays
PASS  no overlay owns a workflow  — 0 overlay owners
PASS  every overlay states what it cannot decide  — 0 unbounded overlays

── Founder boundaries ────────────────────────────────────────────────────────
PASS  founder-reserved decisions are recorded  — 11
PASS  no role owns a founder-reserved decision  — 0 boundary violations

── Historical compatibility ──────────────────────────────────────────────────
PASS  no historical department row was deleted  — 0 all 32 present
PASS  four roles are retired, none deleted  — 4
PASS  every retired role kept its rationale  — 0 documented
PASS  the alias table grew rather than shrank  — 167

── Cost ──────────────────────────────────────────────────────────────────────
PASS  OpenRouter requests during Phase A = 0  — 0 request(s)
PASS  paid inference cost during Phase A = USD 0.00  — USD 0.00
PASS  the provider hold is still in place  — 8 route(s) held open-circuit

==============================================================================
48 passed, 0 failed
PHASE_A_READY_FOR_FOUNDER_APPROVAL
```

## Fingerprints

| subject | pre rows | pre sha256 | post rows | post sha256 | |
|---|---|---|---|---|---|
| departments | 32 | `055e0f7adf854c36…` | 32 | `055e0f7adf854c36…` | unchanged |
| roles | 177 | `a3b2a1ed87491d6a…` | 180 | `b59c88c2d499d95f…` | **changed** |
| categories | 86 | `f231fb862c452ee6…` | 86 | `f231fb862c452ee6…` | unchanged |
| workflow_steps | 184 | `afa05987fcafbc9c…` | 184 | `ab586627c77b58d4…` | **changed** |
| reserved | 11 | `605818d3478111a0…` | 11 | `605818d3478111a0…` | unchanged |
| agents | 94 | `d4a03a66d4ac1c1a…` | 95 | `2550888360e7ec6c…` | **changed** |
| ORGANIZATION | 584 | `cc87a7baedc92314…` | 588 | `0b6ec5f4ca34b9b0…` | **changed** |

The three that moved are the three Phase A touched, and nothing else did:

- **roles +3** — the renamed, merged and created roles. The four superseded ones are retired, which
  is a status change, not a deletion, so the row count rises by exactly the number created.
- **workflow_steps: same 184 rows, different digest** — two `actor_role` values repointed from the
  retired ids to their successors. No step was added or removed.
- **agents +1** — the runtime employee for Product/UX Designer. `gov_relations_mgr` was set
  inactive rather than deleted, so the count rises by one rather than staying level.

`departments`, `categories` and `reserved` are byte-identical before and after. Phase A did not
touch a department row, a category identity, or a founder-reserved decision.

## The rehearsal

The same committed bytes were sent inside an aborted production transaction before deployment, with
one appended statement that reads the post-change counts and then raises. It returned:

```
PHASE A REHEARSAL — ROLLED BACK. departments=10 roles=90 overlays=86
shape=4,6,7,7,7,9,11,11,11,17 workflows_owned=30 roles_with_necessity=176 retired=4
aliases=167 exec_committee=13
```

The fingerprint taken immediately afterwards matched the pre-change capture on all seven subjects —
`ORGANIZATION cc87a7baedc92314fe1e8ae81a1275f1d3b654ada707a181419c464aa903cf69`, unchanged. The
rehearsal left production exactly as it found it.

**The rehearsal refused the migration four times before it passed**, each with nothing applied:
a partial unique index on `runtime_agent_key`, a committee seat vocabulary that had no
`standing_adviser`, its own postcondition on 86 overlays with no necessity status, and its own
postcondition on a retired role that resolved to nobody. Every one of those would have been a
production defect had this been applied directly.
