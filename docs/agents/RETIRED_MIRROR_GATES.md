# The mirror gates are retired — production proves itself (3 Sep 2026)

## What kept going red

Two CI jobs, "the Phase C kernel gate, against production" and "the Phase D handler gate, against
production", failed on most pushes for weeks. The founder called it a design issue. It was.

Both jobs mixed two kinds of check:

- **Invariants read from production.** Every component has an active owner; no workflow step is
  reviewed inside its own department; a handoff has two parties; the connectivity register is
  empty; the kernel's write guard refuses a bypass; every frozen step executes in an aborted
  drive. These catch real defects. On 3 Sep 2026 they caught three during the org re-carve.
- **Mirrors.** The same truth kept a second time in the repository and compared to production:
  the component crosswalk CSV plus its SQL declaration literals (23 columns × 1,799 rows), the
  routine-ownership ledger's `source_file` pointer, the eight Phase D deliverable CSVs compared
  byte for byte, the Phase A/B baseline digests, the PCCR approval digest. A mirror is right only
  on the day it is emitted. Every real change to the company — a cron re-enabled, a role renamed,
  a department re-carved — made a copy wrong, and the gate went red for bookkeeping.

The measured cost on 3 Sep 2026: the org re-carve was one SQL file and about an hour; making the
mirrors agree again was six files and about four hours, and every push in between reddened the two
jobs. Of the gate findings that day, 3 were defects and about 25 were copies.

## What was retired, and what replaced each

| Retired | What it defended | Replaced by (reads production) |
|---|---|---|
| `phase_c_component_crosswalk.test.mjs` (CSV + SQL literals, two CI jobs) | every component declared and owned; every live entry point registered | `phase_c_components_are_owned.test.mjs`: every component's role is active, its department is active and is the role's, active components carry a trace policy, every active cron / subscription / edge function is a component and no component names a dead job or subscription |
| ownership ledger `source_file` = manifest order (source-of-truth line 6) | which repo file is canonical | the canonical engine already decides that from the manifest (line 7); a lagging pointer is printed as information and repaired with `--emit-ledger-sync` when convenient. A ledger row whose **class** the repository denies still counts. |
| Phase D deliverables "still reproduce byte for byte" | the committed record reflects production | the builder must run clean against production and write a well-formed deliverable (every workflow driven, nothing left behind); the committed CSVs are snapshots, regenerated with `node scripts/phase_d/build_all.mjs`; a stale snapshot is printed with the command |
| `pccr_approval_matches_committed_tables.test.mjs` | the founder signed the amendment document on disk | nothing — the founder removed the freeze-amendment ritual on 2 Sep 2026 |
| Phase A/B baseline-digest recompute (PACR pattern), and the `phase_c_invariants` line that asserted drift = 0 | the frozen org/workflow structure had not moved | `fn_phase_a_organization_violations`, `fn_org_role_violations`, `fn_phase_b_invariants` and the kernel boards, which assert the structure's *properties* rather than its digest; the drift is printed as information |
| `phase_c_invariants` block 3: nine Phase C binding CSVs = their tables, by id set | the founder's deliverable and the runtime registry are one thing | the tables are the registry; the CSVs are snapshots whose lag is printed; ownership and activeness of every binding are asserted by `phase_c_components_are_owned` and `fn_phase_c_invariants` |
| the `fn_kernel_system_trace_state` population "every firing since the epoch" | every wrapped cron firing carries a trace | every firing **since the job was wrapped** carries a trace (`a_trace_is_required_from_the_moment_the_door_exists.sql`) — a firing that predates the kernel door is history; after the wrap nothing may slip |

The Phase C runtime-component crosswalk and the Phase D CSVs used to stay in the tree as the last
emitted snapshots. Nothing gated on them, and on 9 Sep 2026 the whole Phase A–D documentation was
deleted on the founder's instruction; git history still holds every one. The rule they illustrated
is what survives, and it is the rule below.

## The rule going forward

A check may compare production to a **property** (an owner exists, a reviewer is independent, a
step executes). A check may not compare production to a **copy** of itself kept in git. If a new
gate needs the repository at all, it needs it for what only the repository knows: which file is
canonical, what the code says, what the package approved.
