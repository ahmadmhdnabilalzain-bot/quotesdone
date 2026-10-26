---
name: a-nullable-column-a-trigger-requires
description: "fn_phase_d_fixture_effect_payload builds its key population from mapped columns that are NOT NULL with no default, so a column a TRIGGER requires is invisible to it — declare it in phase_d_fixture_catalogue, scoped to the workflow."
metadata: 
  node_type: memory
  type: reference
  originSessionId: e91f68dd-ccad-4fba-8fd1-3cb4e80753e3
  modified: 2026-08-26T13:45:59.340Z
---

`fn_phase_d_fixture_effect_payload` decides which keys a Phase D handler's effect will carry by
asking the CATALOGUE OF THE DATABASE: a key in the object's `phase_d_object_write_map` whose column
is `attnotnull` with no default — **plus** any key a committed `phase_d_fixture_catalogue` row names
with `scope = 'EFFECT_PAYLOAD'` for that step or workflow (a globally-scoped row, both
`workflow_id` and `step_id` null, does NOT join the population).

So a column that is nullable but which a TRIGGER demands is invisible: on 26 Aug 2026 the W17
handler wrote a refund with `transaction_id` null and was refused `pd_effect_check_violated`,
`dispatches_executed 11 -> 5`.

**The catalogue row is the declared mechanism.** Adding one:

* `fixture_id` is NOT NULL with no default — assign by hand (this session's block is `PDF-5xxx`);
  `expected_result` and `prohibited_external_use` are NOT NULL too, and a non-text value needs
  `marker_exemption` explaining why it cannot carry `PHASE_D_FIXTURE_DO_NOT_PUBLISH`;
* then run `node scripts/phase_d/build_fixture_catalogue.mjs` — the CSV is compared row by checksum
  by `scripts/checks/phase_d_fixture_catalogue_matches_the_file.test.mjs`;
* **the VALUE is a last resort, not the answer.** The resolver asks `fn_phase_d_step_context` first
  and `phase_d_context_key_object` second (`transaction_id` already IDENTIFIES `payment_transaction`),
  so a real drive resolves the row the scenario created. Commit a value that cannot fabricate a
  link — an all-zero uuid is refused by the foreign key rather than pointing at something plausible.

Related: [[a-committed-constant-beat-the-record-it-described]], [[an-identity-is-never-a-fixture]],
[[an-externally-issued-refund-is-a-fact-not-a-request]].
