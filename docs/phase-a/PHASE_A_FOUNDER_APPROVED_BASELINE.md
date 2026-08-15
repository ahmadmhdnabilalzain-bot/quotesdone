# Phase A — founder-approved baseline, FROZEN

**Approved by the founder on 15 August 2026 at 06:00 UTC.** Recorded in the database as
`org_phase_baseline` where `phase = 'A'`, and tagged `phase-a-founder-approved-2026-08-15`.

Phase A is closed. **No further organizational change may be made** unless a later finding produces
a formal Phase A change request with evidence and founder approval. That is not a note — the
database enforces it; see *The freeze guard* below.

---

## The approved organisation

| | |
|---|---|
| active primary departments | **10** |
| canonical accountable roles | **90** |
| on-demand category overlays | **86** |
| department heads | **10** |
| organizational workflows, one accountable owner each | **30** |
| retired roles, all still resolving | **4** |
| **Phase A organization violations** | **0** |
| reporting cycles · self-management · creator/reviewer collisions | **0 · 0 · 0** |
| unowned or multiply-owned workflow steps | **0** |
| orphan overlays · founder-boundary conflicts · unresolved Phase A decisions | **0 · 0 · 0** |

## Provenance

| | |
|---|---|
| production project | `htdblwldjkcgjvmqkbeh` |
| **approved organisation commit** | `d5107300fbb4cb1a334c886ae4cb7448bb7bd936` |
| approval timestamp | `2026-08-15T06:00:00Z` |
| git tag | `phase-a-founder-approved-2026-08-15` |

The tag points at the commit that **records** the freeze; `final_commit` above is the commit whose
**organisation** the founder approved. They are different commits and both are stated, because
conflating them is how a baseline stops meaning anything.

## Checksums

Every registry is checksummed **twice**, from two independent sources: the live database and the
committed CSV in `docs/phase-a/`. They are different digests of the same organisation by design —
one pins the database, the other pins the artefact a reader would open. If a pair ever disagrees,
it says *which side moved* rather than only that something did.

### Organization fingerprint

`231e0389902aa6c7ea30983463996bf6133182eef45c6e3e51043246eb235a01` — 588 rows across departments,
roles, category identities, workflow steps, founder-reserved decisions and agents.

Computed by `scripts/phase_a/freeze.mjs` and **cross-checked against `scripts/phase_a/fingerprint.mjs`**,
a separate implementation written earlier in the session. Both produced the same value.

### Registries

| registry | rows | database SHA-256 | committed artefact SHA-256 |
|---|---|---|---|
| departments | 10 | `03542ee0121c3dd5e9a2d79b3a9608ca298c2142aa1ba7114ee6778cf1c3399d` | `ae4a0d5fcf759fe368591deb6277fcfbde21d7a9e756e8cc36298962e39b19b3` |
| canonical roles | 90 | `18f27e1d006448dc9d82962468258eb6adf33eb75bd871fde7f7afe4df177b59` | `b2b097af00efef9c1536ee8efc879be6f736794dad78cc8969435056c8a7a839` |
| reporting graph | 90 | `4c8af326127d5d1521a5eb470dfa9d7f6c6bf76bae19bbb0e5bd1be75d7b32c5` | `3b273215747402257bd9d301f58371c777d1cceec82edec7e9e6a00fddbd9eff` |
| category overlays | 86 | `7a77bd1a2de6eb7916a3824585aff2251d6057020f34653dfb8207d1045dc3f1` | `62df01deb38870ee7527d7f194c6abc10d86468d72d23f0089f53447a4f12cc0` |
| workflow ownership | 30 | `9e2c8bb7592ca3e349d42d9a5557797bd278aefe2053d948290b3a49acff3b08` | `8f6df87683bdd6b516698e990534ff456b31e709581477535c917a7eebd14473` |
| founder-reserved decisions | 11 | `c9e1ce14850f4dddff1521c21ede31748d4a07178011b1658b5699fcd1dd1297` | `3c2f619ca6c5c6c2ba3f252ee30749f5c0afc5239a107728e761e4b214b3721b` |

### Production migrations

| version | SHA-256 | file |
|---|---|---|
| 20260815050000 | `5d9b7067adf8bf1e59c173e3342ce1f6ad22700a62131ca380471b0a2c013bd9` | `_phase_a_organization_closure.sql` |
| 20260815051500 | `d0a302542bf4dc4a21079e5fcf17c29873e901fc88a9fec12d654d84869eab7d` | `_phase_a_followup_orphaned_work_and_evaluation.sql` |
| 20260815052500 | `d650f1fd06a9f59442915ed1adbaf7cf77ae5b0e1baa6dcccdadb5ac91fdde07` | `_phase_a_the_role_resolved_but_the_employee_did_not.sql` |
| 20260815053000 | `1c5a651885532f2d66fa6ada62633b1bdc7b40f0e20ab8c1c57b4adf569c826a` | `_phase_a_the_new_role_had_no_identity_and_no_caller.sql` |
| 20260815060000 | `72b97977f3dab396abe6a0ed12af971c8e6984432e8f34c660cb834a45c16ae6` | `_phase_a_closure_corrections.sql` |
| 20260815061500 | `043fce931a7aec8f9a28e02eded4b30963848216502599f86484b3b83cb632a9` | `_phase_a_the_merge_left_a_stale_identity.sql` |

**These were applied by the production-direct protocol** — `scripts/apply_sql.mjs` posts the
committed bytes and reads the definitions back — **not by the Supabase migration runner.** They are
therefore deliberately absent from `supabase_migrations.schema_migrations`. Inventing runner rows
would claim a provenance that did not happen; the file digest above is the version that means
anything here.

### Rollbacks

| file | SHA-256 |
|---|---|
| `scripts/sql/phase_a_rollback.sql` | `a0f77dca0ee7e07632f9b8685f022b122a8f7b18219d478f936bc6d45b0fde71` |
| `scripts/sql/phase_a_closure_rollback.sql` | `cd4ce93f9dfca7437cbabe4504b4f40fd5e45ea74365595327d3d5232c19b48f` |
| `scripts/sql/phase_a_freeze_rollback.sql` | *(removes the freeze only; touches no part of the organisation)* |

---

## The freeze guard

`z90_phase_a_freeze` on `org_role` and `org_departments`. Statement-level, because the question is
what the counts are *after* the statement and a row trigger cannot see that.

**It is scoped to the counts, and that is the whole design decision.** A guard refusing every write
to `org_role` would be a stronger-sounding freeze and a worse one: `knowledge_scopes` and `tools`
are *columns on `org_role`*, so it would block the exact four deferred items intended for a later
phase. The frozen thing is the **shape**, not every attribute of every row.

- Change a role's tools, knowledge, KPI binding, title or manager — **permitted**.
- Change how *many* departments, roles or overlays exist — **refused**, unless the change request is
  stated in the same transaction:

```sql
set local app.phase_a_change_reason = 'PACR-nnn: <finding, evidence, approver>';
```

That is the same shape as `fn_org_authority_guard`'s `app.change_reason`, which this estate already
uses for raised authority grants. It is not an obstacle; it is the formal change request, recorded
where the change happens.

**The guard is proven, not asserted.** The migration retires a role, catches the refusal, and fails
if the refusal did not come — a guard never observed refusing anything is a guard nobody has tested.
It also proves an ordinary column update still passes.

Safe to install because **nothing in this database writes `org_role` from a routine or a cron job** —
both measured at zero before the guard was written.

## Checking the freeze

```sql
select * from public.fn_phase_a_baseline_drift();
```

Zero rows means frozen. Any row names the subject, what was approved, and what is live.

---

## Explicitly deferred — not Phase A defects, not to be hidden or marked complete

Four runtime-readiness items on `product_ux_designer`, listed by `fn_phase_a_deferred_items()` as
`DEFERRED_TO_LATER_PHASES`:

`no_kpi` · `no_knowledge` · `no_authority` · `no_tools`

`fn_org_role_violations()` still reports them, unweakened and untouched. The role is organizationally
complete — 9 owned decisions, 7 forbidden, 5 principal outputs, and it owns step 2 of W22 — and
`org_role.runtime_enabled` is `false`, which is the declared statement that it is not yet activated.
`model_policy` is null, so it could not make a paid call even if something invoked it.

## Also approved in this baseline

- **Product/UX Designer** organizational definition.
- **Chief Product & Technology Officer** title and scope, retaining the stable key `cto`.
- **UAE tax ownership and escalation**: the Financial Controller owns routine VAT and corporate-tax
  coordination; complex, material, disputed or current-interpretation questions escalate to
  authoritative current sources, Legal/Compliance and an external UAE tax professional. Recorded as
  an approved row in `decision_record`. **No 91st role.**

## Cost

**0 OpenRouter requests. USD 0.00.** Every provider route remained open-circuit in
`llm_route_health` throughout Phase A; none was released.
