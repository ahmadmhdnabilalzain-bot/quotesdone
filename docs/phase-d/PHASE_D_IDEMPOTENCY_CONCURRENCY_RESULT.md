# Phase D — idempotency and concurrency result

**Every claim below is either backed by a constraint the database enforces, or by an injection
executed on production in an aborted transaction. Where something is asserted by neither, it is
listed in §4 as not proved.**

---

## 1. Idempotency — what the database refuses, not what the code intends

| mechanism | where | proved by |
|---|---|---|
| one effect per (step_run_id, effect_type) | `phase_d_effect_ledger`, 1 unique constraint | D10's `duplicate` case, read from `pg_constraint` rather than typed |
| one delivery per idempotency key | `phase_d_external_attempt`, UNIQUE (idempotency_key, attempt_no) | PD-IDEM-005, PD-NOTIFY-003: two identical sends → **1** delivered row |
| a delivered attempt must carry a result id | CHECK `phase_d_external_attempt_delivered_has_result` | PD-PROV-005: an insert claiming delivery with a null result id is **refused** |
| one supplier assignment per (inquiry, supplier) | UNIQUE `inquiry_matches_inquiry_id_supplier_id_key` | PD-IDEM-003; GATE-015 refuses the duplicate dispatch before the index has to |
| one business record per identity | `fn_phase_d_object_write` | PD-IDEM-001: two writes of one customer identity resolve to **the same row** |
| an APPEND_ONLY correction is a new key | `pd_object_append_only` | the writer refuses a second version by name |

### The defect that made idempotency a claim rather than a property

`UPSERT_STATE` probed `where key_column::text = business_key` unconditionally. For
`supplier_capability` the map points `key_column` at `owner_ref`, so **it read one value and wrote
another and could never find its own row**; for `quotation` and `payment_transaction` it probed a
generated id against a uuid business key, never matched, and always INSERTed — colliding on the
relation's natural key. Proved in isolation on production, no workflow involved:

```
write 1  business_key=KEYPROBE-A  owner_ref=30723 -> supplier_capabilities:supplier_id=30723
write 2  business_key=KEYPROBE-B  owner_ref=30723 -> REFUSED duplicate key ... _pkey
```

Identity is now resolved in two derived passes — the key column using the value that will be
**written** into it, then any other unique index whose columns are all mapped and supplied, carrying
that index's own partial predicate from `pg_get_expr`.

**Not fixed and not hidden: 7 of 10 UPSERT_STATE maps resolve an identity.** The three that do not —
`supplier_account` among them — have a generated key column and no mapped natural key, so their
second write is a new row rather than a state move. `fn_phase_d_object_identity_state()` is **RED**
with an owner. Inventing an identity for `leads` would be the harness deciding what a supplier
account is.

### Replay

`fn_phase_d_external_deliver` on an already-delivered key records a `duplicate_replay` attempt for
the audit trail, returns **the first attempt's result id**, and delivers nothing new. Handoff replay
is proved separately: re-accepting an accepted handoff returns `replay=true` and leaves open tasks
at 1, not 2.

---

## 2. Concurrency — what is proved and by what

| case | result | how |
|---|---|---|
| cancellation races with delivery | **refused** | PD-CONC-004 / PD-OUTBOX-005: a cancelled intent cannot be delivered afterwards (`pd_external_cancelled`) |
| two publishes of one quotation set | **idempotent** | PD-CONC-003: the second returns the first result id and delivers nothing |
| two revisions of one quotation | **both retained, neither overwritten** | `quotation_revision` is IMMUTABLE_REVISION: a second write supersedes as a new revision |
| refund decision races execution | **one immutable decision** | PD-CONC-005: `z00_refund_founder_decision_only` is a ROW trigger, so every approval path — racing or not — must present an active founder identity |
| an APPEND_ONLY object written by two steps | **two rows, not a collision** | D25: the per-(run, object) key cache is skipped for APPEND_ONLY, so each step appends its own |
| a TRANSACTION_RECORD written by five steps | **one current record, four superseded** | D27, proved by control: five writes → 1 current + 4 retained |

### The one that is honestly not proved

**PD-CONC-001, two workers claiming the same task, is NOT_RUN.** A genuine race needs two concurrent
database sessions. Everything in this phase runs inside a single transaction that is aborted, so a
second claimant cannot exist. Executing it needs a harness that opens two connections and **commits**
— which under the automation hold would leave rows behind.

This is stated rather than substituted. Row-level locking exists in the kernel and would probably
win the race; "probably" is not a measurement, and pointing this row at a lock that was never
contended would be the instrument-on-the-wrong-subject defect this estate keeps finding.

---

## 3. What the numbers are

| | |
|---|---|
| IDEMPOTENCY defects executed and refused | **4 / 5** |
| CONCURRENCY defects executed and refused | **4 / 5** |
| unique constraints backing the above | 1 on the effect ledger, 6 on the attempt ledger |
| UPSERT_STATE maps that resolve an identity | **7 / 10** — RED, disclosed, owned |
| external attempt rows surviving a run | **0** |

---

## 4. Not proved, and named

1. **True multi-session concurrency.** No probe in this phase opens a second connection. Every
   concurrency result above is a property of a constraint or a trigger — which holds regardless of
   ordering — rather than an observed race.
2. **Idempotency across an HTTP retry.** The duplicate-webhook case is proved at the adapter, not at
   the endpoint, because no Phase D path issues a request. That is section 8 work.
3. **Three UPSERT_STATE maps** cannot resolve an identity and are RED rather than fixed.

## Boundary of this evidence

Measured on the one project on 2026-08-19 (database clock), in aborted transactions. Constraint
facts are read from `pg_constraint` and `pg_index` at that moment. This is a statement about the
Phase D machinery and the relations it writes; it is **not** a claim about the runtime behaviour of
edge functions or the portal, neither of which this phase exercises.

---

## 2026-08-24 — normalisation lineage, replay, and the publication state

Project `htdblwldjkcgjvmqkbeh`. Driven on production inside transactions that abort.

### PD-QUOTE-005 — a supplier's original values may never be overwritten by normalisation

**BR-018 compared nothing.** Its whole predicate was

```
quote_revision_ref is non-empty AND platform_edited = 'false'
```

which reads the **caller's own claim about itself**: a normalisation that genuinely overwrote the
supplier's figure and reported `platform_edited = false` passed. And there was nothing to overwrite
— the only normalisation in the estate was `leadTimeDays()` in `quote_compare/deterministic.ts`,
computed in memory and never persisted.

`phase_d_o06` builds the derived record and the comparison:

* `public.phase_d_quote_normalisation` — the projection, referencing `source_quote_ref`,
  `source_revision_ref`, `source_payload_sha256`, `schema_version`, `normalised`, `transformation`,
  `actor_role_id`, `capability_ref`, `trace_id`, and its own supersession chain.
  **Replay makes no duplicate**: `UNIQUE (source_revision_ref, source_payload_sha256, schema_version)`
  means the same revision at the same bytes under the same schema version is one normalisation, and
  a second identical run is refused by the index rather than by a caller remembering.
* `public.phase_d_supplier_authored_field` — the eight field keys a projection may never restate,
  as a register rather than a literal in a predicate, so extending it is a row.
* `a10_phase_d_normalisation_shape` — a projection carrying a supplier-authored key at the top level
  of `normalised` is refused `pd_normalisation_restates_original`, and one whose `transformation`
  does not name `source_fields` is refused `pd_normalisation_transformation_absent`. A derived value
  whose derivation nobody recorded is a new number.
* `public.fn_phase_d_quote_original_intact(text)` — what BR-018 now consults. It re-reads the live
  `quotation_revision` payload, digests it, and compares that digest against the one **every live
  normalisation says it was derived from**. An original that moved after it was normalised is
  visible whatever the caller says about itself. Refusal `pd_quote_original_overwritten`.

Driven, one aborted transaction:

| step | result |
|---|---|
| a supplier revision written through the object store | accepted |
| a normalisation beside it, referencing the revision's payload digest | **accepted** |
| the identical normalisation replayed | `IDEMPOTENT_NO_DUPLICATE`; rows `1 -> 1` |
| a projection restating the supplier's `lead_time` under its own name | REFUSED `pd_normalisation_restates_original` |
| a direct overwrite of the original record's payload, past the maintenance door | REFUSED `pd_object_overwrite_refused` |
| the original, re-read | `INTACT` |

The original supplier revision is an `IMMUTABLE_REVISION`-family object: a change creates a new
version and supersedes the old one, and `a00_phase_d_object_policy_guard` refuses an in-place edit.
The lineage is therefore preserved on both sides — the revision chain by supersession, the
projection by `source_revision_ref` plus the digest of the exact bytes it read.

### PD-QUOTE-004 — an unpublished quotation is not a customer's to read

**BR-019 and GATE-018 both tested ownership and called it publication.** Both evaluated
`count(*) from quote_comparisons where id = ? and customer_id = ?` — and no column matching
`publish|visib|reveal` existed on `quote_comparisons` or on `quotes`, so a customer's own
**unpublished** comparison passed both and injecting "unpublished" changed nothing a control could
separate. `GATE-018`'s own refusal code is `gate018_comparison_not_publishable`, which is what the
register said it was measuring.

`phase_d_o06` adds `publication_state` (DRAFT · SUBMITTED · UNDER_REVIEW · REVISION_REQUIRED ·
APPROVED · PUBLISHED · WITHDRAWN · SUPERSEDED), `published_at`, `superseded_by_comparison_id`, and
`public.fn_phase_d_comparison_visible`. **The default is DRAFT**, so a row written by any path that
does not know about publication is invisible to a customer rather than visible — absence fails
closed. A `PUBLISHED` row with no `published_at` is refused by a CHECK: a claim with no moment
attached is not a publication.

`phase_d_o07` gives both predicates the leg, in the same commit — fixing only the rule would leave
the gate green on the same unpublished comparison, which is how a pair of predicates disagrees in
silence. Driven, one aborted transaction, one customer and two comparisons differing in exactly one
respect:

| read | result |
|---|---|
| the owner reading their own **unpublished** comparison | REFUSED `pd_comparison_unpublished` |
| the owner reading their own **published** comparison | **visible** |
| an unrelated customer reading the published one | REFUSED `pd_comparison_not_the_owner` |
| admin reading the draft | **visible** |
| BR-019 passing on the draft | **0 times** |

Ownership is tested **first** and is never skipped for a customer caller, so the third row is the
arm proving the publication leg did not replace the ownership leg.

**What this does not claim.** The customer portal's read path is
`supabase/functions/customer_api/index.ts` on the service_role client, which bypasses RLS and calls
neither predicate; its `quote_pdf` action applies no status filter at all while its list applies
`.neq('status','draft')` — a negative filter that publishes any status a future writer invents.
Wiring that path to `fn_phase_d_comparison_visible` is a frontend/edge change, it is not done here,
and the contract above is the database half only. Said rather than implied.
