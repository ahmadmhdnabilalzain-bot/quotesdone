# Phase C — Identity Resolution

**Measured on the one project `htdblwldjkcgjvmqkbeh`, 15 Aug 2026.** Every number below came from
a query run in the same session as this sentence; nothing is quoted from the package.

## The boundary

There is one resolver and it is the only sanctioned way to turn an actor token into a canonical
identity:

```sql
public.fn_phase_c_resolve_actor(p_token text)
  -> (kind, role_id, department_id, system_actor_id, reason)
```

It returns a **row**, always populated, never a bare null. That shape is deliberate. A resolver
that returned null for both "I have never heard of this" and "I know it and it is inactive" makes
those two facts indistinguishable to the caller, and a caller that reads null as "no restriction"
is the defect this estate has already paid for more than once. `kind` is one of:

| kind | meaning | may own work |
| --- | --- | --- |
| `canonical` | an active standing employee | yes |
| `overlay` | a category overlay | no — advises, never owns |
| `founder` | the external decision boundary | refund decisions only |
| `system_actor` | a registered executor | no — executes, never owns |
| `inactive` | a known role that is not active | no, and the reason says so |
| `unknown` | nothing in the estate answers to this | no |
| `refused` | empty token | no |

`fn_phase_c_actor_may_own(token)` is the single boolean most callers want. It is **true only for
`canonical`**. An overlay, the founder, a system actor, an inactive role and an unknown token all
return false, and that is checked by five separate injected-defect cases.

## What the package addressed, and what resolved

`scripts/phase_c/validate_package.mjs` reads the 52 checksum-verified package files and resolves
every role, department and overlay token they name against the live organization.

| | addressed | resolved before this session | resolved after |
| --- | --- | --- | --- |
| role tokens | 91 | 82 | 91 |
| department tokens | 10 | 1 | 10 |
| overlay tokens | 86 | 0 | 86 |

The nine that did not resolve were not organizational defects. They were naming:

- **Nine department names.** The package uses long descriptive keys (`finance_payments`,
  `people_company_operations`, …); Phase A uses short ones (`finance`, `people_ops`, …). Nine rows
  in `public.org_department_alias`.
- **86 overlay route keys.** The package addresses overlays as `opcat-001` … `opcat-086`. The live
  overlay role is `category_overlay_<NNN>_<slug>`, and `public.org_category_identity` already held
  the mapping between them. The 86 alias rows are **derived from that table**, not typed, so a
  drift in either shows up as a missing alias rather than as a wrong one.
- **One role spelling.** `fpa_analyst`. Phase A's role is `fpna_analyst`; Phase B loaded the alias
  `fp_a_analyst`; the Phase C acceptance cases introduce a third spelling. One row.

**These are aliases, not organization changes.** `org_role_alias` and `org_department_alias` carry
no Phase A frozen digest and no `z90_phase_a_freeze` trigger — which is how Phase B loaded 237
alias rows without moving `fn_phase_a_baseline_drift()` off zero. It is still zero.

`org_role_alias` now holds **324 rows** (237 + 86 overlays + 1 spelling), of which 226 carry
`kind = 'packaged_role_id'`; `org_department_alias` holds **34** (25 + 9).

## Package errata

Eight cells in the checksummed package say something other than what a runtime can read. The bytes
are **not edited** — they are checksummed and must stay verifiable. Each is recorded in
`public.phase_c_package_erratum` with its evidence, its decided correction and the reason, and the
correction is applied where the registry is loaded.

| id | file | cell | defect |
| --- | --- | --- | --- |
| PCE-001 | authority matrix | `supplier_suspension.review_or_contributors` | prose: "fraud_reviewer **or** supplier_verification_reviewer" |
| PCE-002 | authority matrix | `marketing_publish.review_or_contributors` | prose disjunction |
| PCE-003 | authority matrix | `production_release.review_or_contributors` | conditional clause inside a role list |
| PCE-004 | authority matrix | `public_claim_publish.review_or_contributors` | prose disjunction |
| PCE-005 | authority matrix | `routine_operational_decision.accountable_role_id` | placeholder `accountable_canonical_role` |
| PCE-006 | authority matrix | `routine_operational_decision.review_or_contributors` | prose "manager/reviewer per Phase A/B" |
| PCE-007 | acceptance cases | `CC-002.expected_child_roles` | "category overlay opcat-004" |
| PCE-008 | acceptance cases | `CC-005.expected_child_roles` | third spelling of `fpna_analyst` |

PCE-005 and PCE-006 are worth reading closely: `routine_operational_decision` is deliberately
generic — "any ordinary department decision inside policy/authority". It has no single owner **by
construction**, so it is registered as an explicit `DYNAMIC:` scope resolved from the workflow or
step in play, rather than bound to an invented role. Inventing one would have been the easier fix
and a false one.

## Where the resolver is mandatory

Every Phase C write path calls it before doing anything else. The ones enforced by a trigger, so
they cannot be forgotten:

| write | guard | refuses |
| --- | --- | --- |
| `phase_c_task` insert/update | `z20_phase_c_task_state_guard` | an owner that is not an active canonical role |
| `phase_c_task` insert/update | `z10_phase_c_overlay_not_accountable` | an overlay as owner |
| `phase_c_handoff_run` insert | `z30_phase_c_handoff_sender_retains` | a sender or receiver that does not resolve |
| `phase_c_component` insert | `phase_c_component_no_generic_owner_ck` | `Director`, `service_role`, `pg_cron`, `postgres`, `system`, `admin`, `code_runner`, `unknown`, empty |

## Reviewer independence is on effective identity

`fn_phase_c_reviewer_independent(creator, reviewer)` resolves **both sides before comparing**, so
two spellings of one employee collide. Injected and refused: a task whose reviewer is an
`org_role_alias` of its own owner.

## System actors versus accountable roles

Ten registered system actors execute; none owns. Each names the canonical role that is accountable
for what it does, which is the master spec's §3.5 rule rather than an invention.

| system actor | accountable role (package spelling) | resolves to | components it executes |
| --- | --- | --- | --- |
| `system.task_engine` | `chief_of_staff` | `chief_of_staff` | 852 |
| `system.workflow_engine` | `coo` | `chief_operating_officer` | 455 |
| `system.scheduler` | `coo` | `chief_operating_officer` | 367 |
| `system.event_dispatcher` | `it_operations_site_reliability_engineer` | `it_operations_engineer` | 60 |
| `system.command_router` | `chief_of_staff` | `chief_of_staff` | 27 |
| `system.provider_adapter` | `solution_architect` | `solution_architect` | 19 |
| `system.notification_dispatcher` | `lifecycle_channel_operations_specialist` | `lifecycle_channel_operations` | 9 |
| `system.webhook_receiver` | `backend_engineer` | `backend_engineer` | 6 |
| `system.health_monitor` | `it_operations_site_reliability_engineer` | `it_operations_engineer` | 4 |
| `system.storage_trigger` | `it_operations_site_reliability_engineer` | `it_operations_engineer` | **0** |

The registry stores the package's spelling and the resolver maps it — that is the alias mechanism
doing its job rather than a second copy of the organization.

`system.storage_trigger` executes **nothing**. That is stated rather than hidden: no storage
trigger with business behaviour was found in the inventory, so the actor is registered and idle.
An idle registered actor is a different fact from a missing one, and the count says which.

## What this did not look at

- It did not audit the **legacy** identity paths (`org_agent_alias`, 236 rows; `org_role_identity`,
  127). They still resolve for historical reads and Phase C did not change them. New writes use
  canonical ids only; that is asserted by the guards above, not by a sweep of old rows.
- It did not check that every one of the 1,000 database routines resolves an actor before acting.
  Phase C made the resolver mandatory at the **Phase C** boundary — task, command, step, handoff,
  trace, authority. Routines outside that boundary are classified and owned, not rewritten.
