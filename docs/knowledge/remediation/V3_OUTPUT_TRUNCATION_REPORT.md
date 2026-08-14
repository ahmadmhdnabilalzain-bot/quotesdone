# V3 REMEDIATION — STAGE 6: OUTPUT CONTRACT AND TRUNCATION

**Branch:** `repair/v3-certification-remediation-1` · **Measured:** 2026-08-14, Supabase
`pglpqrhvozwepymcuunn` · **Certification of record:** `V3-COR-0A782DA90B10` (56.97%, 135 output
truncations)

**This document certifies nothing.** Internal work cannot certify a role, a department or a
category. Only an independent evaluator can, and none has run against this branch. Every number
below comes from a query I ran or a file I read; where something could not be measured I say so
instead of estimating.

---

## 1. What the numbers say

`ai_cost_log` carries no `finish_reason` column (checked in `information_schema.columns`). What it
does carry is the gateway's own truncation sentence, written into `model_selected_because` at
`supabase/functions/ai_gateway/index.ts:634-638`. Counting on that string:

| Model | Truncations, all time |
|---|---|
| `anthropic/claude-sonnet-5` | **175** |
| `~anthropic/claude-haiku-latest` | 9 |
| `google/gemini-3.5-flash` | 5 |
| `google/gemini-3.1-flash-lite` | 2 |

191 total; sonnet-5 is 91.6% of them. That independently reproduces the certification's "100% on
`anthropic/claude-sonnet-5`" without reading the register.

The concentration is **not** a property of the route's ceiling. Within one task class,
`general_drafting`, ceiling 900 tokens, same callers, same prompts:

| Model | Calls | Truncated | Rate |
|---|---|---|---|
| `~anthropic/claude-haiku-latest` | 2,093 | 9 | 0.43% |
| `anthropic/claude-sonnet-5` | 238 | 163 | **68.5%** |
| `google/gemini-3.1-flash-lite` | 144 | 0 | 0% |

Same budget, same instruction, a 159× difference in truncation rate. Sonnet-5 writes past 900
tokens where haiku does not. `model_policy` holds **62 rows across 62 distinct task classes** — one
row per class — so `max_tokens` is a property of the task class and **cannot vary by tier**. When
`fn_ai_route` escalates a call from medium to large it changes the model and leaves the budget
where it was: 168 of those sonnet-5 calls were logged at `tier='large'` on a policy row that reads
`tier='medium', max_tokens=900`. Escalation raises verbosity and not the ceiling. That is the
mechanism behind "truncation only on the consequential tier".

---

## 2. The mechanism, precisely

`ai_gateway/index.ts:311`:

```ts
const maxTok = Math.min(Number(body.max ?? route.max_tokens ?? 700), Number(route.max_tokens ?? 4000));
```

Policy always wins; a caller can only ask for **less**. `maxTok` is what goes to OpenRouter
(`:530`), what the truncation sentence quotes (`:635`) and what is returned to the caller (`:685`).
Both halves of that `min` are visible in production:

* **Policy binds.** `agent_train` asks for 1,500 (`supabase/functions/agent_train/index.ts:200`),
  `general_drafting` allows 900, so `min(1500, 900) = 900`. On 14 Aug, 169 `agent_train` answers
  were logged with `output_tokens` of **exactly 900** — 115 at tier large, 48 at tier medium
  sonnet-5, 6 on haiku. Those 169 are 98% of the day's 173 truncations.
* **The caller binds.** `exec_agents` truncated 9 times at exactly 1,800 output tokens on
  `agent_reasoning`, whose policy ceiling is 8,000 — the caller's own `max` was the wall.
  `inquiry_intake` the same at 1,700; `dept_plan` at 1,200 against a 4,000 ceiling;
  `drawing_redact_verify` at 396 against 8,000.

The gateway has detected this correctly since 5 Aug. `:579-581` reads
`choices[0].finish_reason` (falling back to `native_finish_reason`) and writes it to the attempt
ledger; `:684-685` returns `finish_reason`, `truncated: finishReason === 'length'` and `max_tokens`.

**The loss was one line in `_shared/llm.ts`.** Its own header records it
(`supabase/functions/_shared/llm.ts:70-73`): the module ended with
`return typeof j.content === 'string' ? j.content : null;`, which discards `tool_calls`,
`finish_reason` and `truncated`. 31 call sites reach the gateway through this module. A truncated
answer arrived at all of them as an ordinary string with its ending missing, and nothing downstream
could tell it from a complete one.

---

## 3. What is now implemented

**Detection surfaced.** `makeLlmRich` (`_shared/llm.ts:172-320`) returns the whole envelope;
`:298-310` reads `tool_calls`, `finish_reason` and sets
`truncated: j.truncated === true || fr === 'length'` — the gateway's flag first, the reason it
derives from as a fallback.

**The string contract is unchanged.** `makeLlm` (`:332-346`) still returns `string | null` for the
31 callers, but now writes an `output_truncated` row to `agent_runs` when the gateway reports one.

**Fail-closed in `agent_brain`.** `runWithTools` accumulates truncation across every tool step
(`agent_brain/index.ts:120`, `out.truncated = out.truncated || r.truncated`), and `:485-500` is the
gate:

```ts
const incomplete = loop.truncated ? 'truncated' : loop.failClosed ? 'tool_unavailable' : ...
let [clean, acts] = incomplete ? [rawReply, null as any] : splitActions(rawReply);
```

A truncated reply is replaced with a refusal and **never parsed for actions**. Downstream it is
recorded as `status:'error'`, `outcome_status:'blocked'` (`:563-569`, `:630-631`).

**The attempt ledger records it.** `fn_record_llm_attempt` (`ai_gateway:475-486`) carries
`finish_reason` per attempt with a server-assigned `attempt_no`.

---

## 4. Evidence, and its limits

I will not claim zero truncations. Here is the ledger.

`ai_gateway` v33 deployed **2026-08-14T14:05:55Z**, `agent_brain` v51 at 14:01:43Z. Splitting
`ai_cost_log` on the gateway timestamp:

| Window | Calls | Truncations |
|---|---|---|
| Before v33 (24h) | 2,566 | 173 |
| After v33 | **37** | **0** |

Post-deploy: `max(output_tokens) = 5,556` against the 8,000 ceiling, `max(prompt_tokens) = 32,385`.
**37 calls, all from one function, over roughly nine minutes, is not evidence that truncation is
fixed.** It is evidence that nothing truncated in the only window that exists.

`llm_attempt` holds **36 rows** (14:06:18Z → 14:14:31Z): `finish_reason` non-null on all 36 — 27
`tool_calls`, 9 `stop`, **0 `length`**, 0 failures. A zero cannot tell a working detector from an
idle one, so I forced it: inside an **aborted transaction** I called `fn_record_llm_attempt` with
`finish_reason: 'length'`, counted, and raised an exception to roll back. The count went to 1. The
ledger's `length` path works and has simply never been exercised.

`agent_runs` has 16 rows written by the new `agent_brain`. Every one reads `truncated: false`;
`incomplete` is set on 7, all for tool reasons (`tool_loop_exhausted` ×4, `tool_unavailable` ×3),
none for truncation. Context sizes on that path: `stable_chars` 23,370–23,418 (the byte-stable
system half), `volatile_chars` 6,044–13,172, `prompt_chars` 29,449–36,590. `agent_brain` requests
`max: 8000` (`:71`, `:103`, `:119`) against a policy ceiling of 8,000, so `min()` is a no-op there.

`agent_runs` holds **0** rows for the `output_truncated` signal. That is honest, not green: the 169
`agent_train` truncations happened 11:33–13:00Z, before both deploys, and `agent_train` does not use
`_shared/llm.ts` at all — it posts to the gateway directly (`agent_train/index.ts:73-90`).

---

## 5. What is still broken or unverified

* **`agent_train` is truncating today and the remediation does not touch it.** 169 answers cut at
  exactly 900 tokens between 11:33 and 13:00Z. It reads `truncated` (`:85`) and proceeds anyway —
  its grader prompt says "it may be cut off at the end… do not penalise it for stopping mid-sentence"
  (`:230-231`). Every training grade produced today was graded on a mutilated answer. The fix is a
  `model_policy` change (`general_drafting.max_tokens`), not a code change; I did not make it,
  because it changes cost on 2,627 calls and that is a decision to take deliberately.
* **Tier escalation cannot raise the ceiling.** One `model_policy` row per task class. Until that is
  keyed on (task_class, tier), escalating to sonnet-5 will keep buying a longer writer on a shorter
  budget.
* **No continuation protocol.** Nothing anywhere resumes a truncated generation. `agent_brain`
  refuses and asks the user to narrow the question (`:494`). That is safe and it is not recovery.
* **No context compression.** No path trims or summarises the ~23,400-char stable prompt or the
  retrieved slice when the budget is tight. Prompt size is whatever assembly produced.
* **No output-schema validation.** `ai_gateway:537` forwards `response_format` if a caller sends it;
  exactly three do (`supplier_catalog_ingest:167`, `supplier_onboard:157`, `supplier_portal:250`)
  and all three send the bare string `'json'`, not the object shape the OpenAI API defines. I did
  not measure whether the provider honours it. **No agent path sends one at all.** Structure is
  recovered by regex (`splitActions`, `parseJson`), which is exactly what a truncated reply defeats.
* **The regression harness asserts nothing about truncation.** `scripts/checks/v3_remediation_regression.mjs`
  is 437 lines with zero matches for `truncat`, `finish_reason` or `max_tokens`. The fail-closed
  branch at `agent_brain:489` has no runnable check behind it.
* **The 68.5% sonnet-5 rate is measured on `general_drafting` only.** I did not measure per-model
  truncation rates on the other 61 task classes.

**Nothing here is certified.** A re-test must be run by the independent evaluator.
