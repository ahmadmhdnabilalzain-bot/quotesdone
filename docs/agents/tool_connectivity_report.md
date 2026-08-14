# Tool connectivity report

Measured 14 Aug 2026 · blueprint `runtime_blueprint/TOOL_REGISTRY.yaml`, `TOOL_POLICY_GROUPS.yaml`,
`schemas/tool_result.schema.json`.

## Status: `EXISTING_PARTIAL_REPAIR` — the registry existed and had never reached production

`agent_tool` and `agent_tool_call` did not exist on production until today. `v3_repair_01_tool_registry`
could not be applied because `v3_repair_14_tool_credential` widens `fn_agent_tools`' return type and
the 11-column `CREATE OR REPLACE` was refused — so the file aborted *before* creating its tables, and
`v3_repair_08`, `09` and `14` then each failed on a missing relation. One stale signature held four
files out of production. Fixed by making `01` drop before it creates, exactly as `14` already did.

## Registry, on production

| property | count |
|---|---|
| tools registered | 9 |
| with an adapter (`impl_kind` + `impl_target`) | 9 |
| with an input schema | 9 |
| with timeout and max_attempts | 9 |
| with a declared failure behaviour (fail-closed) | 9 |
| with a required credential | 1 |

`fn_agent_tools('brief')` returns 9 tools and `fn_agent_tool_allowed` answers true on a real tool —
both verified on production after deployment, not asserted from the file.

## Blueprint requirements

| requirement | status | evidence |
|---|---|---|
| no simulated tool result | met, structurally | `agent_tool_call` records `result_hash`, `result_rows`, `result_bytes`; Gate B asserts 0 rows with `status='ok'` and a null `result_hash` |
| no null success | met | same check |
| no all-tools call | met | `fn_agent_tools` returns only the tools the agent's role and department grant; the agent cannot widen its own set from a prompt |
| deterministic required/optional/forbidden selection | partial | selection is deterministic from the registry; the required/optional/forbidden *grouping* from `TOOL_POLICY_GROUPS.yaml` is not yet modelled as three states |
| health, permission, timeout, retry states | met for permission/timeout/retry; health not modelled | `agent_tool` has no health column |
| result IDs/hashes in traces | met | `decision_trace.tool_result_refs` and `agent_tool_call.result_hash` |
| fail closed when required evidence is unavailable | met | `failure_behaviour` set on all 9 |

## Open

- **8 of 9 tools carry no `required_credential`.** Only one is credential-gated. Whether the other
  eight need one is a per-tool decision, not a bulk edit.
- **Tool health state is not modelled.** The blueprint asks for a health state per tool; there is no
  column for it. `MISSING_BUILD`, small.
- **Production has 0 recorded `agent_tool_call` rows**, because the tables landed today and no
  production agent traffic has run since. The path is proven on staging (50 tool calls in the Gate B
  window); on production it is deployed and unexercised. That is the correct state given the
  instruction to stop before production activation.
