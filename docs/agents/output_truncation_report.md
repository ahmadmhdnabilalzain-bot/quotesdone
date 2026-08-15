# Output and truncation report

Measured 14 Aug 2026 on staging `pglpqrhvozwepymcuunn` · blueprint
`runtime_blueprint/OUTPUT_AND_TRUNCATION_POLICY.md`.

## Status: `EXISTING_PARTIAL_REPAIR` — detection existed, fail-closed did not

`_shared/llm.ts` already detected `finish_reason=length` and wrote an `output_truncated` log row.
It then **returned the truncated string anyway**. Its own comment said so:

> "The response is missing its ending and this caller uses the string-only contract, so nothing
> downstream can detect it."

So every caller on the string contract received a half-finished answer and had no way to know. The
detector was honest and the handling was not.

## What Gate B measured

| run | model | calls | truncated | rate | max output |
|---|---|---|---|---|---|
| before any change | `google/gemini-3.5-flash` | 60 | **12** | 20% | 996 (ceiling 1000) |
| after raising `max_tokens` 1000 → 2000 | same | 33 | **4** | 12% | 1996 (ceiling 2000) |
| after fail-closed + one repair call | same | 1 probe | 0 fragments returned | — | — |

**Raising the ceiling is not the fix.** In both runs the p90 sat exactly at whatever the ceiling
was — 996, then 1996. That is a *censored* distribution: p90 is not telling you what the work
needs, it is telling you where the answer was cut off. Moving the censor moves the number and
changes nothing about the shape.

Truncation was introduced by this session: `org_reorg_20` routed 23 operations specialists to
`routine_employee_reasoning`, which carries the pack's `max_tokens = 1000`. The routing itself is
correct and stays — 20% truncation is a reason to fix output handling, not a reason to pay four
times as much on every call.

## What was changed

`makeLlm`'s string contract now follows the policy exactly:

1. **Detect** — unchanged, `finish_reason=length`.
2. **One controlled repair call** — the same question is asked again with an explicit brevity
   instruction ("your previous answer was cut off; answer complete and materially shorter, lead with
   the decision or refusal").
3. **Fail closed** — if it is still truncated, return `null` and write
   `output_truncated_failed_closed`, deliberately a different signal from a model refusal, because
   *a refusal is a decision and a fragment is not*.

Verified end to end on staging with `spec_fitout`, one of the twelve roles that truncated:

```
HTTP 200 · reply: "I could not complete this answer — my response hit the output limit and was
cut off. I have not acted on the incomplete reasoning. Please narrow the question..."
```

Three `llm_attempt` rows for the request: the original, the repair, and the fail-closed outcome. No
fragment reached the caller.

## Gate B truncation criterion

**NOT PASSED, and stated as such.** The criterion is *zero truncated successful outputs*. After the
fix, zero truncated outputs are *returned as successful* — which is what the criterion protects
against — but the underlying model answers still hit the ceiling on roughly one call in eight, and
each of those now costs a second call to discover. That is an improvement in safety and a
regression in cost, and both belong in the same sentence.

## Open

- **Reduce the context, not the ceiling.** The policy's first remedy is "reduce irrelevant context".
  Average assembled context is 70 knowledge records per role; the roles that truncate are the ones
  writing long structured briefs. Trimming the assembled context for
  `routine_employee_reasoning` is the next lever and has not been done.
- **Deployed to staging only.** `_shared/llm.ts` is imported by 35 edge functions. Four were
  deployed to staging (`agent_brain`, `dept_plan`, `dept_learn`, `ai_gateway`). Production
  deployment is deliberately not done — the instruction was to stop before production activation.
