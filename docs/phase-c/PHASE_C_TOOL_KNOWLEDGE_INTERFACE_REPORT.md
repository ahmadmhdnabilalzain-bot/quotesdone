# Phase C — Tool and Knowledge Interfaces

**Phase C connects interfaces, not professional intelligence.** No embedding was computed, no model
was called, and no knowledge content was created, changed or certified. That boundary is what the
zero-cost rule depends on, and it held.

Measured on `htdblwldjkcgjvmqkbeh`, 15 Aug 2026.

## The tool boundary

`public.agent_tool` holds **10** registered adapters, and it already carries most of what the tool
contract requires: `tool_id`, `purpose`, `kind`, `action_class`, `impl_kind`, `impl_target`,
`authorised_roles`, `authorised_departments`, `min_authority`, `required_credential`,
`input_schema`, `output_schema`, `timeout_seconds`, `max_attempts`, `backoff`,
`failure_behaviour`, `audit_behaviour`, `requires_current_data`, `stub_permitted`, `active`.
`public.agent_tool_call` holds 22 recorded invocations.

Phase C adds the authorization boundary:

```sql
public.fn_phase_c_tool_authorized(role, tool)
  -> (authorized boolean, reason text, side_effecting boolean)
```

- An **unregistered tool fails closed** — `authorized = false`, "not in the registry — fail
  closed". Injected and refused.
- An **unresolved identity** cannot use any tool. Injected and refused.
- A **registered but inactive** tool is refused with that reason, which is a different fact from
  "unknown" and says so.
- Two independent grants are consulted: the tool's own `authorised_roles`, and the role's
  `org_role.tools` list. Either is sufficient; **neither present is a refusal**.

That last clause is deliberate. An empty `authorised_roles` array means *nobody yet*, not
*everybody*. A permission check that treats an empty allow-list as "no restriction" is the same
defect shape as a resolver returning null for both unknown and inactive, and it is stated in the
function rather than left to a reader.

### Null is not success

The contract requires explicit `success | empty | refused | timeout | provider_error |
invalid_result` states, and that a role cannot claim a tool result without a stored one.

`fn_phase_c_output_validate` enforces the general form of this and is asserted four ways:

| fixture | verdict |
| --- | --- |
| `null` | **invalid** — "null output is not a successful result" |
| `{"status":"ok"}` | **invalid** — "required fields missing [output]" |
| `{"status":"ok","output":"partial","truncated":true}` | **invalid** — explicit truncation marker |
| `{"status":"ok","output":"x","stop_reason":"length"}` | **invalid** — output-limit marker |

`agent_tool_call` is where a result id and hash live; `TRACE-TOOL` links a claim to it. Phase C
wires the boundary and does not fabricate calls to populate it.

### What was not done here

No adapter was invoked. No provider was contacted. The tool inventory is a **connection and a
contract**, and proving each adapter's behaviour against a recorded fixture is Phase D work. That
is the declared Phase C boundary in the tool contract itself: *"Phase C acceptance uses mocks and
fixtures … any outbound request to a paid inference provider is a test failure."* There were none.

## The knowledge scope interface

```sql
public.fn_phase_c_knowledge_scope(role, workflow, category)
  -> jsonb
```

Input: canonical role, workflow, category overlay. Output: the permitted scopes, the exclusions,
and — the part that matters — the **missing or orphan mappings**, named individually:

```json
{
  "ok": false,
  "role_id": "...", "department_id": "...", "workflow_id": "W05", "category_overlay": "...",
  "company_core_scopes":  ["company_policy", "founder_boundaries", "authority_matrix"],
  "department_scopes":    ["dept:marketplace"],
  "role_scopes":          [...],
  "category_scopes":      ["overlay:category_overlay_004_..."],
  "exclusions":           ["other_departments_private_scopes", "v3_certification_answer_keys"],
  "missing_or_orphan":    ["role_has_no_declared_knowledge_scope:..."],
  "retrieval_performed":  false,
  "note": "Phase C connects the scope interface only. No embedding or model call is made here."
}
```

`retrieval_performed: false` is in the payload on purpose. A caller reading this cannot mistake a
scope resolution for a retrieval.

An unresolved identity returns `ok: false` with `unresolved_identity`, not an empty scope list —
because an empty scope list and "I do not know who you are" must not look the same.

`v3_certification_answer_keys` is in the exclusion list of every response. Phase C did not read
them, and the interface will not hand them to anyone.

## Role context

`fn_phase_c_role_context(role)` returns the assembled context boundary for an employee: role,
display name, department, manager, authority level, owned and forbidden decisions, tools,
knowledge scopes, the workflows they own, and `paid_model_route: "DISABLED_PHASE_C"`.

It resolves the identity first and refuses an unresolved one.

## Category overlays

All **86** overlays are bound with an invocation path and a return path:

```sql
public.fn_phase_c_overlay_invoke(overlay_id, ctx)
```

Returns `overlay_id`, `live_role_id`, `inquiry_id`, `retrieved_fields`, `never_infer_checks`,
`missing_fields`, `return_owner`, `may_dispatch: false`, `status`, `trace_id`.

`never_infer_checks` names the four things an overlay must never invent — quantity, specification,
delivery date, budget — and `may_dispatch` is hard-coded false. The trigger
`z10_phase_c_overlay_not_accountable` refuses an overlay as a task owner independently, so the flag
and the guard would both have to be wrong.

**Zero orphan overlay mappings**: the invariant `overlay_bindings_resolve = 0` checks that every
bound `live_role_id` is an active `knowledge_overlay` role in `org_role`.

## Zero paid inference

| measurement | value |
| --- | --- |
| provider routes registered | 8 |
| routes held open-circuit | **8 of 8** |
| held until | 2126-08-15 02:51:36 UTC |
| last paid AI call in the estate | 2026-08-15 **02:51:33** UTC — before Phase C began |
| paid inference calls during Phase C | **0** |
| paid inference cost during Phase C | **AED 0.00 = USD 0.00** |

Measured from `public.llm_route_health.open_until` and `public.ai_cost_log.occurred_at`, not
inferred from a caught query error.

One thing worth recording about the cost query: the column is `cost_aed`, **not** `cost_usd`.
Naming it wrong returns an error, but a nearby wrong-column query that happened to parse would have
produced a zero that measures nothing while reading exactly like a zero that measures cost.
