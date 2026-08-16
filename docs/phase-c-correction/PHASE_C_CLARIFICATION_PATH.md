# Phase C correction 7 — a clarification the founder can answer, or close

**Migrations:** `phase_c_34_clarification_path.sql`, `phase_c_40_clarify_action_gate.sql`

## What the audit measured

The system did the right thing with `"Make marketing better."` — one clarification, zero tasks, zero
side effects — and then could not get rid of it. `founder_command_control(223,'cancel')` returned
**HTTP 409**: *"A command in 'clarification_required' cannot be cancelled; the state model does not
allow it."* `phase_c_command_transition` confirmed it: of the eight states, `clarification_required`
was the only one with no terminal exit — its single legal move was back to `interpreting`, and none
of the four control operations performed it. Command 223 was stuck in the founder's inbox
permanently, and so would every future ambiguous command have been.

## What was built

**`public.fn_founder_command_clarify(command_id, answer)`**, exposed as the authenticated Command
Center action **`founder_command_clarify`**, registered in *both* gates: `ACTION_CLASS` in `os_api`
and `public.control_mode_action`. It is `founder_gated`, not `read_only`, because answering a
clarification can create the tasks the original instruction could not safely produce. The pinning
CHECK that stops that class spreading was widened by exactly one name. `src/lib/osClient.ts`
exports `founderCommandClarify`, so there is a control for the instruction to travel through.

| Requirement | Implementation |
|---|---|
| Preserve the original founder message | `founder_command_message.raw_text` is never edited |
| Append the exact clarification response | `founder_command_clarification.answer_text` + `answered_at`, verbatim, on its own row |
| Retain one command ID | the same `command_id` throughout; no second command is created |
| Create no operational task while unresolved | if the combined text is still not routable, a new question is asked and `tasks_created = 0` |
| Resume interpretation after clarification | re-classified through `fn_founder_command_classify` on original + reply — deterministic, no model consulted |
| Allow normal cancellation | `clarification_required → cancelled` added to `phase_c_command_transition` |
| Record trace and audit evidence | the root trace advances with the command via the trigger; `os_audit_log` records the actor |

## On the lifecycle names — a deviation, stated

The brief writes the required path as
`received → clarification_required → interpreting → planned → tasks_created → active → completed`.

This model already implements that shape under the names frozen in `phase_c_command_state`:

| Brief | This model |
|---|---|
| `planned` | `accepted` then `routed` |
| `active` | `in_progress` |

Renaming live states would create a second vocabulary for the same thing — a defect this estate has
paid for before. **The edges the brief requires were added; the names were left alone.** Both
`clarification_required → interpreting` and `clarification_required → cancelled` now exist, and the
invariant `clarification_required_has_an_exit` expects exactly 2.

## Command 223 — resolved through the real authenticated path, not deleted

```
POST /functions/v1/os_api  {action:'founder_command_clarify', command_id:223, answer:'…'}   200
```

- original message: `Make marketing better.` — unchanged
- clarification 9: question asked 10:34, `answer_text` recorded verbatim, `answered_at 10:35:14`
- one command id: **223**
- state: `clarification_required → tasks_created`, intent `CMD-W20`
- tasks: **789, 790, 791, 792** — four canonical owners
- event: `EV-W20-STARTED` (outbox 246)

Cancellation was proved separately on command **228** (`"Improve things."`): 0 tasks, then
`founder_command_control` cancel → **HTTP 200**, `status: cancelled`.
