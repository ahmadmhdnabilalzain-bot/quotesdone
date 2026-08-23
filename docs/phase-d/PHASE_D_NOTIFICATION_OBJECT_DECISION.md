# Phase D — the notification object, decided

**23 Aug 2026. Decided, not escalated**, per section 4 of the founder's ruling. The reasoning is
here and in the commit that carries it; the mechanism is in
`scripts/phase_d/prove_object_reference_round_trip.mjs`.

---

## The question

Object round trips stood at **55 of 56**. The exclusion was `notification`, whose
`phase_d_business_object_binding.canonical_relation` is `public.notifications` — the outbound queue.
A fixture stage for it had been built, measured clean (30 records written, 0 deliverable, status
forced to the suppression no sender selects) and then **removed**, because two kernel boards refuse
it:

* `fn_phase_d_effect_state.phase_d_write_maps_into_the_outbound_notification_table` — no row of
  `public.phase_d_object_write_map` may target `public.notifications`;
* `fn_phase_d_fixture_state.fixture_stage_targeting_public_notifications` — no fixture stage may
  target an object whose canonical relation is `public.notifications`.

Neither board asks whether the row would be deliverable, and that is deliberate.

The ruling allowed two ways out: change both boards with a stated engineering reason, or prove
`notification`'s creation somewhere other than the fixture factory.

## The decision

**Both boards stay exactly as they are. The object is proved the second way.**

Neither board is disclosed away in `scripts/checks/kernel-boards.json`, neither is weakened, and no
number was moved by changing what a check measures.

## Why that is not a workaround

It is what the frozen contract already says. Measured on `public.phase_d_step_effect`, **all seven
steps of W13 — the governing workflow, and the only steps in the estate whose effect object is
`notification`** — declare:

| column | value |
|---|---|
| `expected_effect_type` | `EXTERNAL_EFFECT_INTENT` |
| `effect_relation` | `public.phase_d_effect_ledger` — **not** `public.notifications` |
| `effect_service` | `public.fn_phase_d_effect_produce(jsonb)` |
| `effect_operation` | `EXTERNAL_INTENT_RECORD` |
| `result_reference` | `phase_d_effect_ledger.effect_id + result_reference` |
| `completion_condition` | "a phase_d_effect_ledger row exists with provider_mode = mock and no provider request id" |

A third board, `notification_effects_not_classified_as_intent`, holds that shape in place: a step
whose effect object is `notification` or `notification_attempt` and whose `expected_effect_type` is
anything other than `EXTERNAL_EFFECT_INTENT` is a red.

So **Phase D's canonical creation of a notification IS the intent record.** The binding's
`canonical_relation` names where a *delivered* notification lives, which is a different subject and
is not Phase D's to write while the automation hold stands. The reference strategy has said the
same thing all along, in its own words:

> `fixture_creation_service`: *no fixture stage creates this object; it is created by a handler
> effect or not at all.*

## What is now proved, and what is not

The prover gained an **intent arm**. For every object with no fixture stage whose declared Phase D
effects are all `EXTERNAL_EFFECT_INTENT` — today exactly `notification` — it drives the governing
workflow through the ordinary doors inside a transaction that ends in `raise exception`, and asserts
on the run's own ledger rows:

* the effect names this object;
* the `result_reference` is present and resolves back to exactly the effect that wrote it;
* `provider_mode` is `mock`, `disabled` or `none`;
* **`public.notifications` gained no row.**

Measured on `htdblwldjkcgjvmqkbeh` before the arm was written, driving W13 directly: seven
`EXTERNAL_EFFECT_INTENT` effects, all naming `notification`, all `provider_mode = mock`, all with a
`result_reference` of the form `external_intent:SUPPRESSED:PHASE_D_FIXTURE_DO_NOT_PUBLISH@example.invalid…`,
and `notifications` delta **0**.

The verdict is reported under its own name, `ROUND_TRIPPED_AS_EXTERNAL_EFFECT_INTENT`, and the
headline says which is which:

> *N frozen business objects have a proved creation path: 55 round-tripped through a canonical
> relation row and 1 through the declared external-effect intent that is the whole of Phase D's
> creation contract for it.*

**The boundary, stated.** This proves the object's Phase D creation path under the hold. It does
**not** prove that a delivered notification row can be written to `public.notifications` by a Phase D
handler, and it is not intended to: that is the delivery layer, it is held, and the two boards are
what hold it. If the hold is ever lifted, the same seven steps would need re-measuring against a
real send, and that is Phase E's subject and not this one's.
