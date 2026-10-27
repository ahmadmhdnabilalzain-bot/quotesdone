# A held drawing intake asked nothing (ledger 580): measured and fixed, 27 Oct 2026

Seats: sales_engineer (intake, take-off) with customer_support (conversation). Every subject is ZZ DEMO with
`@example.invalid` addresses. OpenRouter stayed on (ruling 1260), each run inside a USD 3 rehearsal window on
production `htdblwldjkcgjvmqkbeh`. Nothing was deployed or applied; the fixed `inquiry_intake` ran locally
(`deno run`) against the same project. Branch `sales_engineer/drawing-intake-asks-27-oct`.

## The defect, on production

- **Run 6dd2316c (27 Oct 07:52-07:54 UTC, agent_runs `inquiry_intake`):** three `needs_info` turns asked 4, 4 and 3
  questions, then seven turns answered `status_computed=held`, `questions=0`, readiness 55 to 80. create_inquiry
  answered 428 `intake_required`: no inquiry id, no BOQ PDF.
- **Reproduced today on the deployed function** (`scripts/e2e/held_intake_asks_the_open_specs.mjs`, run d61c6df5):
  a customer who only points at the drawings for four turns. Turn 4: `held`, `questions=0`, `next_question=null`,
  held_reason `specs_unanswered: system_type,application_area,new_or_replace,scope,location`. 3 checks failed.
- **The same four messages as 6dd2316c did not always hold:** replayed at 10:05 UTC (run 6e7828da) the model filed
  `new_or_replace` on turn 4 and the intake reached ready. Whether the hold is reached depends on the model; what it
  does once reached does not. The harness's opening is therefore written to reach the hold every time.

## Root cause

`inquiry_intake/slots.ts` holds an intake when every open required key has stayed open through `MAX_OPEN_TURNS` (3)
answered turns. That hold is the founder's rule (exact specs or nothing goes to a supplier) and stays. But its branch
cleared `questions` and `missing`, `index.ts` left `next_question` null, and no asked key was stored. The portal
(`NewRequest.tsx`) renders `next_question` and `remaining_questions`, so it had nothing to show, and an answer the
customer typed was never read back by code. Every later turn was the same hold.

## The fix

- A held turn carries every held spec in plain words in `questions` and `missing`, and `next_question` is the first
  held spec with the checklist's own options (`slots.ts heldAsk`).
- `asked_key` and `asked_on_hold` are stored. The next message is read by code for that key first
  (`readHeldAnswer`, the deterministic interview's targeted `parseAnswer`). A bare "not sure" fills nothing; an option
  the trade lists (such as "Not sure - need site survey") is recorded as the answer.
- The fallback held reply now names the open questions.

## End to end after the fix (local `inquiry_intake`, run a2af1892)

| turn | status | asked | open keys |
|---|---|---|---|
| 1-3 | needs_info | the model's questions | all five |
| 4 | held | `system_type`, 8 options | 5 |
| 5 | held | `application_area` | 4 |
| 6 | held | `new_or_replace`, 4 options | 3 |
| 7 | held | `scope`, 3 options | 2 |
| 8 | held | `location` | 1 |
| 9-12 | needs_info | the four sales-engineer questions (materials, warranty, date) | 0 |
| 13 | ready | | 0 |

- create_inquiry (deployed customer_api): HTTP 200, RFQ 160576, the 7-line drawing take-off on the inquiry.
- Routed: 3 matches, all ZZ DEMO, 0 real suppliers. 0 notices about the inquiry addressed outside `@example.invalid`.
  The guards that make this so already existed (`scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql`:
  a demo inquiry and a real supplier are never paired, and every notice about a demo row is captured as suppressed).
- The ZZ DEMO HVAC supplier downloaded the BOQ PDF: HTTP 200, 99,968 bytes, `%PDF-`.
- All 16 checks passed.

## vision_count

`drawing_boq` mode `vision_count` (19 Oct 2026, route `drawing_vision_count`, flag ON) had no caller. Its design
says it runs on the redacted page of a photo or scan, after redaction. On the edge a photo's or scan's pages are
always held (no text layer, so no server boxes), and they are redacted later by the CAD worker's OCR. So:

- analyze_drawing records the legend request (types, template counts, loop size) on the queued scan job;
- `cad_read_status` runs the vision count once the worker's run is recorded, on that verified page, and caches the
  reply on the job;
- the portal's `pollScan` adopts the counted take-off. The counts stay `to_confirm`.

Proved by `customer_api/vision_count_wire.test.ts` (5 tests). **Not proved live:** no photo was pushed through the CAD
worker in this session. GitHub Actions is off, so the worker runs only when the sales_engineer starts it.

## Spend and cleanup

Spend and cleanup figures are in the PR description, measured after every teardown.
