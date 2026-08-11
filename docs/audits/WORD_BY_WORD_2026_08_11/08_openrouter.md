# SPEC #8 — `open router.txt` (2,347 lines)

Audited 2026-08-11 15:15–15:45 UTC. The largest file in the contract, in four blocks:

| block | lines | sections |
|---|---|---|
| 1 — cost optimisation | 1–1,278 | **45** techniques |
| 2 — WhatsApp agent | 1,279–1,841 | **19** techniques |
| 3 — email agent | 1,842–2,066 | **6** techniques |
| 4 — website chat | 2,067–2,347 | **17** techniques |

| PRESENT | PARTIAL | ABSENT | CONTRADICTED | total |
|---|---|---|---|---|
| 38 | 47 | 33 | 4 | **122** |

---

## The measurement that governs the whole file

Seven days of `ai_cost_log` to 2026-08-11 12:00 UTC — **1,642 calls, AED 102.01**:

| model | tier | calls | AED | % of calls | % of cost |
|---|---|---|---|---|---|
| `anthropic/claude-sonnet-5` | large | 622 | **85.70** | 37.9% | **84.0%** |
| `~anthropic/claude-haiku-latest` | medium | 595 | 14.24 | 36.2% | 14.0% |
| `google/gemini-3.1-flash-lite` | small | 414 | 1.08 | 25.2% | 1.1% |
| `anthropic/claude-opus-4.8` | large | 4 | 0.77 | 0.2% | 0.8% |
| `google/gemini-3.5-flash` | medium | 6 | 0.22 | 0.4% | 0.2% |
| `none` | none | 1 | 0.00 | 0.1% | 0% |

## §2 Expected Distribution (L128–L138) — **CONTRADICTED**

The contract states the target as a table. This is the most precisely checkable claim in all eight
files, so it is measured exactly:

| level | **spec target** | **actual (by calls)** | gap |
|---|---|---|---|
| No AI | **20%** | **0.1%** | −19.9 pts |
| Cheap AI | **55%** | **25.2%** | −29.8 pts |
| Medium AI | **20%** | **36.6%** | +16.6 pts |
| Premium | **5%** | **38.1%** | **+33.1 pts — 7.6× the target** |

> L138: "This alone can reduce costs 70-90%."

**The distribution is inverted.** Premium is 7.6× its budget and carries 84.8% of the cost. The
saving the contract describes as achievable by this one change is, on these figures, the largest
single lever available — and with the balance at **$8.68** it is the only finding in this audit with
a clock on it.

**Level 0 (No AI) is not measurable at all.** `model_policy.deterministic_alternative` is populated
on **38 of 61** task classes, so the routing *knows* a deterministic path exists for 62% of task
classes — but a deterministic answer never writes an `ai_cost_log` row, so the 20% target has no
instrument. **That is itself a finding: the one level the contract wants biggest is the one nothing
counts.**

---

## Block 1 — the 45 cost techniques

| # | technique | verdict | evidence |
|---|---|---|---|
| 1 | Never use one model for everything | PRESENT | 5 distinct models in 7 days; `fn_ai_route`, `fn_select_model` |
| 2 | 5 AI levels + expected distribution | **CONTRADICTED** | tiers exist (`model_policy`: large 9, medium 24, small 11, none 17; `model_catalog` has 14 `tier_role` values from `Tier 0` to `Tier 4 escalation`). The **distribution** is inverted — see above |
| 3 | AI Decision Engine (classifier, model-selector, cost-manager, memory-manager) | PRESENT | `fn_ai_route`, `fn_select_model`, `fn_ai_spend_guard`/`fn_check_spend`, `fn_agent_context_capped`. All four roles have a routine; they are database functions rather than the `/ai-router` files the spec sketches, which is a shape difference, not a gap |
| 4 | **Model Cascading** — cheap → confidence <80% → medium → premium | **CONTRADICTED** | `fn_ai_route_tier_rank` and `model_fallback` (47 of 61 policies) exist, so the ladder is *configured*. It cannot run: **confidence is reported on 5 of 1,642 calls (0.3%)**, and **0 of 622 sonnet-5 calls**. A confidence-gated cascade with no confidence escalates every time and pays for both models. The output contract has to carry a confidence before cascading can save anything — `agent_brain` returns prose plus an `@@ACTIONS@@` JSON tail and `selfReportedConfidence()` only parses whole-JSON bodies |
| 5 | Token management / conversation compression | PARTIAL | `fn_agent_context_capped`, `max_output_tokens` in policy. **Average input is 11,499 tokens per sonnet-5 call** (7,152,265 / 622) — compression is configured and not biting |
| 6 | Local embeddings | **PRESENT** | in-region `gte-small`, free; `kb_chunks` 120,530 with pgvector. Exactly what §6 asks for, and it costs nothing |
| 7 | **Cache Everything** | **CONTRADICTED** | `llm_cache` exists with `cache_key`, `prompt_hash`, `hits`, `expires_at`, `saved_usd` **and a semantic `embedding_gte` column**; `fn_llm_cache_get/put/lookup/store` all exist; **all 61 policies carry a `cache_ttl_min`**. The table holds **1 row, 2 hits, $0.00 saved.** In 7 days, **2 of 1,642 calls were cache hits (0.12%)**. This is a fully-built, fully-configured cache that is not being written to |
| 8 | Streaming | ABSENT | no streaming path in `_shared/llm.ts` |
| 9 | Token budgets | PRESENT | `fn_ai_spend_guard`, `fn_check_spend`, `fn_budget_available`, `department_budget` 25, `ai_spend_probe` 4,708 rows |
| 10 | Smart file processing (parse → chunk → vector search → send only relevant) | PARTIAL | chunking and vector search are real; **no PDF parser and no OCR**, so the 200MB-PDF path the section describes cannot start |
| 11 | Multiple providers | PARTIAL | OpenRouter is the only gateway. `fn_model_autoswitch` switches *models*, not *providers*. **Single point of failure**, which `scenario_library.openrouter_outage` names and has never rehearsed |
| 12 | Self-host small models | ABSENT | none |
| 13 | AI profiles (Economy / Balanced / Professional) | PARTIAL | `model_policy.tier` + `reasoning_effort` in `model_policy_by_identity` — but that table's 96 `target_employee` rows resolve to nothing (spec #7 §16), so per-identity profiles are dead config |
| 14 | Monitoring dashboard | PRESENT | `ai_cost_log` 2,209, `ai_spend_probe` 4,708, `cost_snapshot` edge function, `fn_ai_cost_attribute`, Health module |
| 15 | OpenRouter settings | PRESENT | `app_secrets.openrouter_api_key`, `openrouter_min_usd` threshold |
| 16 | Recommended OS architecture (9 named components) | PARTIAL | 6 of 9 PRESENT; **conversation compression, response caching and multi-provider fallback** are the three that are configured-but-inert |
| 17 | Separate thinking from answering | PARTIAL | `fn_decide` separates evaluation from execution; no separate intent/planner/execution model tiers |
| 18 | Agent sleep mode — wake on event, sleep after | **PRESENT** | this is exactly what the architecture does: 166 cron jobs and `company_event` triggers wake routines that run and stop. Nothing is alive 24/7 |
| 19 | **Deterministic tools before AI** | PRESENT | `model_policy.deterministic_alternative` on **38 of 61** task classes; `model_policy_by_identity.deterministic_first`. Configured well; unmeasured (see Level 0 above) |
| 20 | Prompt compression | PARTIAL | `fn_agent_context_capped` caps; nothing compresses |
| 21 | Dynamic context window | PRESENT | `p_max_chars` on `fn_agent_context`, used at 3,000–24,000 across callsites |
| 22 | Response length controller (Quick/Normal/Detailed/Expert) | PARTIAL | `max_tokens` per policy and `max_output_tokens` per identity; not a 4-level user-facing control |
| 23 | User behaviour learning → route cheaper | ABSENT | no routine changes a route from observed behaviour |
| 24 | AI quality scoring | PRESENT | `ai_quality_snapshots` 1,115, `fn_ai_quality_watch`, `fn_quality_metrics`, `fn_quality_snapshot_resolve_agent` |
| 25 | Automatic model benchmarking | PRESENT | `prompt_benchmarks` 21, `fn_model_benchmark`, `fn_llm_drift_watch`, `fn_model_catalog_drift` |
| 26 | Batch processing | PARTIAL | `kb_embed` batches — and **batching above 5 returns HTTP 546**, so throughput is raised by adding invocations, never batch size |
| 27 | Queue system (URGENT / NORMAL / BACKGROUND) | PRESENT | `org_tasks` 834 with `tier`, `agent_actions` 2,450, `fn_action_queue_sweep` |
| 28 | AI spending limits | PRESENT | `fn_ai_spend_guard`, `department_budget`, `openrouter_min_usd` alert at $20 (**currently firing — balance $8.68**) |
| 29 | Smart image AI routing | ABSENT | `model_catalog` has an `Image specialist` tier_role registered and **no vision call has ever been made** |
| 30 | Retrieval instead of generation | PRESENT | `fn_kb_retrieve`, `kb_match`, `fn_require_grounding` forces citation |
| 31 | Own knowledge layer | PRESENT | `kb_chunks` 120,530, `ops_knowledge` 3,959, `dept_library` 1,456 |
| 32 | **Semantic cache** (exact match → similar meaning) | **CONTRADICTED** | `llm_cache.embedding_gte` exists — the semantic cache column is built. **1 row.** The most sophisticated cache in the spec, implemented and empty |
| 33 | Early exit system | PARTIAL | `fn_ai_gate` gates on confidence; no early-exit on answer sufficiency |
| 34 | Developer mode optimisation (code index) | ABSENT | `graphify-out/` is a code index for the *assistant*, not for the product's AI |
| 35 | Fine-tuning / distillation | ABSENT | none |
| 36 | Multi-agent cost control — manager activates only needed agents | PARTIAL | `fn_group_dispatch_report`, `fn_chief_of_staff`; no cost-aware agent activation |
| 37 | Internal AI credits | PARTIAL | `department_budget` 25 rows is the credit ledger; **`budgets` and `budget_lines` are 0 rows** |
| 38 | Predict user intent | ABSENT | none |
| 39 | Fail gracefully (primary → fallback) | PRESENT | `model_fallback` on 47 of 61; `llm_calls.fell_back` column |
| 40 | Regional optimisation | ABSENT | none |
| 41 | AI Accountant | PRESENT | `fn_ai_cost_attribute`, `ai_cost_fn_map` 11, `cost_snapshot` weekly email |
| 42 | Human feedback loop → improve routing → lower cost | ABSENT | `kb_operational_route_test` 344 measures routing; nothing feeds an outcome back into a route |
| 43 | Offline mode | ABSENT | none |
| 44 | Background model switching | PRESENT | `fn_model_autoswitch`, `model_registry` 6, `model_catalog` 14 |
| 45 | The ultimate architecture | PARTIAL | roughly two thirds standing; the three inert pieces are cascading, caching and multi-provider |

### The `could_be_cheaper` detector is pointed the wrong way

`ai_cost_log.could_be_cheaper` flagged **179 calls in 7 days**:

- **175 on `gemini-3.1-flash-lite`** — the cheapest model in the fleet, 1.1% of spend
- **4 on `claude-opus-4.8`**
- **0 on `claude-sonnet-5`** — 622 calls, **84% of all spend**

**The one detector built to find waste never looks at the model doing the spending.** This is not a
missing feature; it is an instrument reporting on the wrong subject, which is the same class of
defect as the 152-check score itself.

### Prompt caching, re-measured over the full window

| | tokens |
|---|---|
| cache **write** (`cache_write_tokens`) | **85,342** |
| cache **read** (`cached_in_tokens`) | **9,851** |
| read/write ratio | **0.115** |
| break-even (5-min TTL) | **0.278** |

The previous session measured 0.216 over a 10-hour window and called it "roughly break-even". Over
the **full 7 days the ratio is 0.115 — less than half of break-even.** Provider-side prompt caching
is currently **losing money**, not marginal. (This is OpenRouter's `cache_control`, a different
mechanism from the empty `llm_cache` table above; both are in scope for §7 and both are failing, for
different reasons.)

---

## Block 2 — WhatsApp agent, 19 techniques (L1,279–L1,841)

| # | technique | verdict | evidence |
|---|---|---|---|
| 1 | Control layer before AI (rules → DB → AI router) | PARTIAL | `fn_wa_fanout` sends; **no inbound controller** |
| 2 | Classify every message first | ABSENT | no inbound classification |
| 3 | Personality layers (base + business rules + situation) | PRESENT | `fn_agent_context` LAYER 1 (`company_constitution` 20, `culture_principle` 8) + LAYER 3 live state |
| 4–5 | Conversation memory + memory database | ABSENT | `chat_threads` 0, `messages` 0 |
| 6 | Agents only when needed | PRESENT | event-driven wake, §18 above |
| 7 | Human handoff | PRESENT | `fn_agent_handoff_inbox`, `fn_handoff_answer`, `fn_should_escalate` |
| 8 | Message batching | ABSENT | |
| 9 | Intent prediction | ABSENT | |
| 10 | WhatsApp agent brain | PARTIAL | Twilio wired and `alert_founder` sends WhatsApp on critical; **no conversational agent** |
| 11 | **Product knowledge must NOT be AI generated** | **PRESENT** | `fn_require_grounding`, `kb_revisions` 9,355, `fn_kb_gov_approve`, `agent_knowledge.source_ref`/`validation_status`. The prohibition has an enforcement point |
| 12 | Image handling optimisation | ABSENT | no vision path |
| 13 | Automated sales flow | ABSENT | |
| 14 | Cost control per customer | ABSENT | cost is attributed per function and department, never per customer |
| 15 | Model ladder | PARTIAL | same as §4 — configured, inert |
| 16 | Response templates | PRESENT | `fn_report_skeleton`, notification templates |
| 17 | AI cost dashboard | PRESENT | as §14 |
| 18 | Background AI jobs | PRESENT | 166 cron jobs |
| 19 | Ideal WhatsApp architecture | PARTIAL | outbound only |

**The founder's own standing intent — recorded in memory as "he wants to run the company by texting
his registered number, any request, not a fixed command list" — is ABSENT.** WhatsApp is outbound
alerting only. Nothing receives an inbound message.

---

## Block 3 — email agent, 6 techniques (L1,842–L2,066)

| # | technique | verdict | evidence |
|---|---|---|---|
| 1 | Email agent cost optimisation | PARTIAL | `notifications` + Resend; no inbound processing |
| 2 | Classification before AI | ABSENT | |
| 3 | Read attachments efficiently | PARTIAL | `_shared/attachment.ts` validates type and size; **no extraction** |
| 4 | Email memory system | ABSENT | |
| 5 | Draft generation | PRESENT | `fn_inbox_send`, `fn_notifications_digest`, `fn_founder_brief` |
| 6 | Priority intelligence | PARTIAL | `fn_normalize_founder_alert_level`, `alert_founder` de-dupes 6h and escalates critical to WhatsApp |

Email is **outbound only**, and the 11 Aug measurement stands: of 154 emails in the week to 11 Aug,
**119 went to `@quotesdone.com`** — the system emailing itself.

---

## Block 4 — website chat, 17 techniques (L2,067–L2,347)

| # | technique | verdict | evidence |
|---|---|---|---|
| 7 | Website chat widget | PRESENT | `src/components/ChatWidget.tsx` |
| 8 | **First message should not use AI** — 4 fixed options | PARTIAL | the widget exists; no fixed-option first turn |
| 9 | Website knowledge layer | PRESENT | `company_faq` **484 rows**, `fn_faq_answer` |
| 10 | Visitor intent detection | ABSENT | |
| 11 | AI sales agent | ABSENT | |
| 12 | Visitor memory | ABSENT | `contact_messages` 0 |
| 13 | Prevent AI abuse | PRESENT | `fn_rate_limit`, `rl_check`, `block_disposable_signup`, `is_disposable_email` |
| 14 | **Shared AI router for all agents** | PRESENT | `fn_ai_route` + `model_policy` serve every caller — one router, as specified |
| 15–16 | One identity across WhatsApp / website / email | ABSENT | `fn_identify_contact` exists; there is no cross-channel conversation to unify |
| 17 | **Cost saving estimate: 80–95% reduction** | **CONTRADICTED** | the claim is the file's closing promise. Measured: premium is 38% of calls against a 5% target, cache hit rate 0.12%, cascading inert, prompt-cache ratio 0.115 against 0.278 break-even. **None of the three big levers is currently returning anything**, so the 80–95% reduction has not been realised and the architecture that would deliver it is built but not switched on |

---

## The four CONTRADICTED verdicts, ranked by what they cost

1. **§2 Expected Distribution** — premium at 38% of calls against a 5% target; 84% of spend on one
   model. Largest single lever.
2. **§7 Cache Everything / §32 Semantic Cache** — a complete cache with a semantic embedding column,
   TTLs on all 61 policies, and **1 row / 2 hits / $0.00 saved**. Second-largest lever, and the
   cheapest to fix because nothing needs designing.
3. **§4 Model Cascading** — configured on 47 of 61 policies and unable to run, because confidence
   is reported on 0.3% of calls. **Fixing the output contract to carry a confidence is the
   prerequisite for the cascade, and doing the cascade first would increase cost, not reduce it.**
4. **§17 (block 4) the 80–95% saving** — the promise the file closes on, unrealised.

At **$8.68 remaining and ~$0.27/h**, these are ~32 hours from mattering. Topping up is the founder's
call; the engineering point is that **the three mechanisms that would cut the burn are already
built** and none of them is currently returning anything.
