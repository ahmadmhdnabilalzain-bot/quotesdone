# Decision trace coverage

Measured 14 Aug 2026 · blueprint `runtime_blueprint/DECISION_TRACE_CONTRACT.md`,
`schemas/decision_trace.schema.json`.

## Status: `EXISTING_PARTIAL_REPAIR`

`decision_trace` carries the full contract shape already — 48 columns including `correlation_id`,
`proposed_by`, `decided_by`, `policy_keys`, `knowledge_refs`, `evidence_refs`, `alternatives`,
`assumptions`, `risk`, `confidence`, `authority_result`, `tools_requested`, `tools_executed`,
`tool_result_refs`, `company_objective`, `department_objective`, `relevant_kpi`, `escalation_decision`,
`model`, `input_tokens`, `output_tokens`, `estimated_cost_aed` and `sealed_at`.

It is append-only by trigger (`a00_decision_trace_immutable`), and that trigger reached production
today with `v3_repair_02` / `11` / `12` / `13`.

## Measured

| | staging | production |
|---|---|---|
| trace rows total | 23 in the Gate B window alone | 8 |
| traces with `decided_by` and `decision` both set | 23/23 | 8/8 |
| traces in the last 7 days | 23+ | 4 |
| append-only trigger present | yes | yes |

**Gate B measured 23 traces for 23 agents — one per executing agent, non-null, 100%.**

## The honest boundary

Production shows **8 traces in total**. That is not a coverage failure of the trace writer; it is
that the writer and its tables only reached production today, and no production agent traffic has
run since. The instruction was to stop before production activation, so this is the expected state:
deployed, verified by the same behavioural suite that runs against both projects, and unexercised.

Claiming "100% trace coverage on production" from 8 rows would be claiming a rate from a population
that has not happened yet. What is proven is:

- the contract exists and is enforced append-only on both projects;
- every agent that executed under Gate B produced a non-null trace;
- the readers are connected — `fn_management_decision_review` reads traces for management review,
  and it reached production today with `v3_repair_10`.

## Open

- **`knowledge_refs` is `jsonb` but is not always an array.** A coverage query using
  `jsonb_array_length` errors on those rows (`cannot get array length of a non-array`). Either the
  writer should always write an array or the contract should say what else is allowed. Small, real,
  and it will bite the next person who writes a coverage query.
- Trace coverage as a *percentage of consequential actions* cannot yet be computed on production,
  because the denominator — consequential actions since the trace path landed — is zero.
