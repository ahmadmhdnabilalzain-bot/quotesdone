# P2-C1 Stage A — MEP data model, design for implementation

**Design only. Nothing applied. Start from `a71f6e9`.**
This converts the Stage A requirements into concrete schema so the implementing session builds rather than designs. Every table below is additive; no existing table changes shape.

---

## The decision everything else follows from

**A shared answer is stored once and referenced. It is never copied into a workstream.**

The copy design fails in two directions and both are expensive. Over-copying means the customer is asked for the project emirate five times. Under-propagating means one workstream's copy goes stale and a mandatory field reads satisfied when it is not — which flows straight into `overall_dispatch_eligible`. Referencing removes the second failure entirely: there is one value, so there is nothing to fall out of step.

Consequence: completeness is **derived**, never stored. No percentage column anywhere.

## Tables

```
inquiry_workstream_group      -- the customer-facing project. 1:1 with inquiry.
  id · inquiry_id · rfq_mode ('coordinated'|'linked') · created_at

inquiry_workstream            -- one per active or historical trade
  id · group_id · trade_key ('hvac'|'electrical'|'plumbing'|'fire'|'elv'|...)
  route_catalog_num · active bool · activated_at · deactivated_at
  UNIQUE (group_id, trade_key)          -- reactivation flips active, never re-inserts

inquiry_answer                -- THE canonical store. One row per (group, field_key).
  id · group_id · field_key · value · unit
  scope ('inquiry_shared'|'trade_specific'|'trade_subset')
  precedence   -- see below
  source_kind ('customer'|'document'|'deterministic'|'model')
  confirmed_at · confirmed_by
  superseded_by bigint         -- append-only: a new value supersedes, never overwrites
  UNIQUE (group_id, field_key) WHERE superseded_by IS NULL

inquiry_answer_scope          -- which workstreams a trade_subset/trade_specific answer applies to
  answer_id · workstream_id                    -- absent for inquiry_shared: it applies to all

inquiry_answer_document       -- provenance, one row per document-derived value
  answer_id · document_id · page_or_sheet · extraction_confidence
  original_text · assigned_scope · extracted_at

inquiry_answer_conflict       -- unresolved disagreement between sources
  id · group_id · field_key · blocking_scope ('shared'|'trade')
  resolved_at · resolved_by · resolution_reason
inquiry_answer_conflict_value -- every competing value preserved, never discarded
  conflict_id · value · precedence · source_kind · document_id

inquiry_workstream_requirement -- the questions a trade actually owns, materialised on activation
  workstream_id · question_id · field_key · mandatory · applies_when

inquiry_state_audit           -- append-only, same trigger pattern as the expectation ledger
  id · group_id · workstream_id · event · detail jsonb · actor · at
```

## Precedence

```sql
create type answer_precedence as enum (
  'customer_confirmed',      -- 1, highest
  'approved_document',       -- 2
  'document_extracted',      -- 3
  'deterministic_inference', -- 4
  'model_inference',         -- 5
  'unknown'                  -- 6
);
```

Enforced in `fn_inquiry_answer_set`, not by convention: a write whose precedence is lower than the live value does **not** supersede it. It becomes a conflict row instead. That is the rule "a lower-precedence value may not silently overwrite a higher-precedence value", made structural — the word doing the work is *silently*, and a conflict row is the opposite of silent.

`model_inference` may never satisfy a **mandatory** field on its own. It can propose; confirmation promotes it to `customer_confirmed`.

## Conflicts

A conflict blocks by scope, not globally:

- unresolved conflict on a **trade-specific mandatory** field → that workstream is not dispatch-eligible
- unresolved conflict on a **shared mandatory** field → `overall_dispatch_eligible` is false, every workstream affected

Resolution writes `resolved_by` and `resolution_reason`. Competing values are never deleted — `inquiry_answer_conflict_value` keeps all of them, which is what makes "the drawing said 12 units, the customer said 8" answerable three months later.

## Derived views

```
v_workstream_completeness   -- per workstream: required, answered, missing[], blocked_by[]
v_group_completeness        -- shared fields + roll-up across ACTIVE workstreams only
v_workstream_dispatch       -- eligible = all mandatory answered, no unresolved conflict,
                            --            validations pass, regulatory triggers satisfied
v_group_dispatch            -- eligible = shared complete
                            --        AND every active workstream eligible
                            --        AND privacy/redaction gates passed
                            --        AND no unresolved shared conflict
                            --        AND required escalations complete
```

`v_group_dispatch` is an `AND` over active workstreams, so one complete trade can never carry an incomplete one. Deactivating a trade removes it from the roll-up without touching its answers or audit rows — inactive means excluded from the calculation, never deleted.

## Compatibility with existing inquiries

Every existing inquiry is single-route and has no group. Two options, and the second is right:

1. backfill a group per inquiry — touches every row, no benefit
2. **treat "no group" as a single implicit workstream** — views coalesce, existing behaviour unchanged, zero rows written

Nothing customer-visible changes. No production router is touched at Stage A.

## Unresolved design decisions — these need answers before Stage B

1. **Trade taxonomy source.** `trade_key` should map to routes 9, 10, 11, 12, 14 — but MEP's 11 mapped subcategories do not divide cleanly into five trades. Which subcategories belong to which trade needs deciding by hand, and it is the crosswalk question again at one level down.
2. **Field-key collisions across trades.** "pressure rating" means something different in plumbing and fire. Either namespace field keys per trade, or declare an explicit shared-field allowlist. Namespacing is safer; it makes genuinely shared fields explicit rather than accidental.
3. **Reactivation window.** If a trade is removed and re-added six weeks later, are its old answers still valid? Proposed: restore them at their original precedence but mark `stale_since`, so they are visible and re-confirmable rather than silently trusted.
4. **RFQ mode timing.** Is `rfq_mode` chosen by the customer, inferred from trade count, or decided at dispatch? It affects whether the column belongs on the group or on the dispatch record.
5. **Document conflicts within one document.** Two sheets of the same drawing set disagreeing is a different case from drawing-vs-text, and may want a different resolution path.

## Stage A test list

The 14 required tests map to the model above without amendment. Tests 1, 2 and 3 are the reference-not-copy proof; 4 and 5 the precedence and conflict proof; 6 and 7 the lifecycle proof; 8, 9 and 10 the derivation proof; 11 the audit proof; 12, 13 and 14 the safety proof. Test 2 — "updating that answer changes all five workstream views immediately" — is trivially true if the design is right and impossible to pass if it is not, which makes it the single most informative test in the list.
