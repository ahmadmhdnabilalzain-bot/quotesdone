# The prompt diet: where the ~45,000 tokens per AI call go, and what was cut (it_engineer, 11 Nov 2026)

Assigned: `it_engineer` (cost). Founder rulings **1619** (10 Nov 2026, standing): *"study the whole path of the ~45,000 tokens
per AI call and cut it without affecting quality"*, and **1618**: model choice is IT's, switched only after a side-by-side on
identical inputs shows the difference is minimal.

This pass made **no model call, applied no SQL and deployed nothing.** Production was read with SELECT only
(`supabase_read_only_user` through the management API). Every number below is labelled **measured** (read from
production or computed from the code) or **estimated** (an assumption, named).

**Tokenizer.** Section sizes use one approximation throughout: `approxTokens` in `supabase/functions/_shared/company_brief.ts`
(Latin characters / 2.55, Arabic / 1.9). It was calibrated on Sonnet on 3 Nov 2026 and runs about 2% high. GPT-6 Luna Pro is
**billed about 1.6 times that count** for the same text. This is measured on two pairs. (1) The same brief path:
`wa_inbound` conversation_reply averaged 42.3k tokens on Sonnet 5.5 and 72.7k on Luna Pro, and `reasoned_delivery` 67.5k on Luna
Pro. (2) The marketing plan call: a 34.5k Luna Pro count against roughly 21k approx-tokens of content. I do not know the cause.
The bill follows the reported count: OpenRouter's `cost_usd_reported` matches the registry prices to the cent.

## 1. Spend and calls, last 7 days (measured)

Window: 3 Nov 23:51 to 10 Nov 23:51 UTC. Production only, `e2e_run_tag is null`, `prompt_tokens > 0`.

| model | calls | avg prompt tokens | AED | share |
|---|---:|---:|---:|---:|
| openai/gpt-6-luna-pro | 1,352 | 46,290 | 18.44 | 44% |
| anthropic/claude-sonnet-5.5 | 83 | 39,339 | 18.04 | 43% |
| anthropic/claude-opus-5.5 | 15 | 13,820 | 5.19 | 12% |
| qwen/qwen3.8-flash | 3 | 20,449 | 0.04 | 0% |
| **total** | **1,453** | | **41.71** | |

Two changes landed before this pass, and the week above predates both:

- **3 Nov:** the brief went from all 32 knowledge files to the core plus one trade pack. A reply used to cost 140-150k tokens
  (`wa_inbound` 30-day mean 141,964 on Sonnet).
- **10 Nov:** knowledge_validation moved to Qwen 3.8 Flash under ruling 1571. `model_policy` now reads `qwen/qwen3.8-flash`
  first and Sonnet 5.5 behind it.

On today's routing, the AED 7.99 a week of Sonnet knowledge_validation becomes roughly AED 0.3. So the week at today's
routing is about **AED 34** (estimated).

### 1a. Ranked by AED a week (measured; ≥ AED 0.2)

| # | fn / task class / model | calls | avg in | avg out | cache read / written per call | AED/wk |
|---|---|---:|---:|---:|---|---:|
| 1 | resilience_ping / knowledge_validation / Sonnet 5.5 (the think() review; **moved to Qwen 10 Nov**) | 21 | 36,586 | 236 | 1,474 / 13,794 | 7.74 |
| 2 | resilience_ping / routine_employee_reasoning / Luna Pro (think() **plan** of seat duties) | 468 | 39,443 | 1,932 | 19,188 / 4,555 | 5.67 |
| 3 | sales_engineer / conversation_reply / **Sonnet 5.5, counterpart Luna Pro** (the re-ask's other-family rung) | 20 | 34,893 | 442 | **0 / 0** | 5.45 |
| 4 | resilience_ping / internal_judgement / Luna Pro (think() **answer** of seat duties) | 279 | 61,025 | 1,820 | 22,044 / 6,699 | 5.32 |
| 5 | marketing / internal_judgement / Luna Pro (`marketing.trend_relevance` answer) | 156 | 74,116 | 2,256 | 27,380 / 11,071 | 3.64 |
| 6 | resilience_ping / internal_judgement / Opus 5.5 (the CEO's judgement) | 4 | 38,055 | 1,561 | 0 / 15,992 | 2.93 |
| 7 | wa_inbound / conversation_reply / Sonnet 5.5 | 22 | 42,288 | 347 | 35,985 / 3,602 | 2.17 |
| 8 | site_assistant / visitor_chat / Sonnet 5.5 | 18 | 44,812 | 299 | 39,395 / 5,192 | 1.86 |
| 9 | resilience_ping / seat_deliberation_compare / Opus 5.5 | 8 | 5,537 | 1,855 | 0 / 0 | 1.74 |
| 10 | marketing / routine_employee_reasoning / Luna Pro (`marketing.trend_relevance` plan) | 144 | 34,587 | 1,813 | 14,684 / 3,475 | 1.66 |
| 11 | public_site / customer_communication / Luna Pro | 124 | 23,654 | 1,855 | 16,080 / 1,805 | 0.86 |
| 12 | email_triage / conversation_reply / Sonnet 5.5 | 1 | 38,476 | 415 | 0 / 36,383 | 0.57 |
| 13 | resilience_ping / seat_deliberation_blind / Opus 5.5 | 3 | 3,592 | 1,644 | 0 / 0 | 0.52 |
| 14 | resilience_ping / customer_communication / Luna Pro | 25 | 35,828 | 1,489 | 15,385 / 4,702 | 0.28 |
| 15 | email_triage / knowledge_validation / Sonnet 5.5 | 1 | 23,541 | 488 | 0 / 8,473 | 0.25 |
| 16 | reasoned_delivery / conversation_reply / Luna Pro | 41 | 67,649 | 413 | 61,513 / 1,599 | 0.22 |
| 17 | supplier_api / supplier_communication / Luna Pro | 19 | 53,981 | 1,838 | 37,026 / 1,746 | 0.21 |

### 1b. Ranked by tokens a call (measured)

- **77-97k:** the internal answer in its upper mode. `it_engineer` p50 86k and p90 97k; `marketing` p75 78k; the CEO p75 72k.
- **77.5k:** `sales_engineer` customer_portal_assistant on Luna Pro, 7 calls.
- **74k:** the trend-relevance answer.
- **67-73k:** Luna Pro conversation replies.
- **54k:** `supplier_api`.
- **35-41k:** the plans.
- **~30k:** the lower mode of the internal answer, with few or no sources.
- **28k:** WhatsApp classification.
- **23.6k:** `public_site`.

Two classes of call make up most of the Luna Pro tokens:

- **think() over internal seat duties** (`resilience_ping`, plus `marketing`): about **40M of the week's 62.6M** Luna Pro prompt
  tokens.
- **the conversation brief:** cheap, because it is 90% cache reads.

## 2. What each call carries, section by section (measured from the code and the generated brief; approxTokens)

### 2a. think(): every seat duty, held replay, marketing judgement and WhatsApp classification

`supabase/functions/_shared/think/engine.ts`. Each step sends three things:

- the system prompt: `sysStable` (the settled facts), then the phase prompt;
- a user message holding a JSON payload.

| section | sent in | approx tokens | Luna Pro billed (×1.6) |
|---|---|---:|---:|
| Settled facts, internal (SETTLED_HEADER + company.md + seats.md) | plan, answer, review | 10,562 + header | ~17k |
| The seat's own card (`knowledge/brief/seats/<seat>.md`) | plan, answer, review | 1,948 (sales_engineer) to 6,272 | 3-10k |
| **= the settled facts, per seat** | | **12,563-16,887** | **~20-27k** |
| Settled facts, external audience | plan, answer, review | 8,691 | ~14k |
| Founder RULINGS block | **every** phase prompt (repeated per call, not per block) | ~250 | ~400 |
| Plan prompt / answer prompt / review prompt | its phase | 880 / 804 / 523 | 1.4k / 1.3k / 0.8k |
| Decision options (WhatsApp: ~195 trade options + intents + menu) | answer (classification) | ~8.5k (options) | ~14k |
| Question + context (conversation, case data) | plan, answer | 0.1-6k (marketing ctx avg 9.8k chars) | ≤10k |
| **Retrieved sources: 12 rows a step, up to 6 steps, excerpt ≤ 2,400 chars** | answer (every pass), review | **up to ~25k** | **up to ~40k** |
| Case memory, 3 cases × ≤ 900 chars | answer (internal only) | ≤ 1k | ≤ 1.6k |

**Retrieval, measured** (`reasoning_held_question`, 14 days, 264 answered runs):

- Every retrieval step returned exactly **12 rows**: 927 of 927 steps. `p_k = 6` returns the seat's half plus the general half.
- A run reads this many rows and cites this many sources:

  | seat | rows read | sources cited |
  |---|---:|---:|
  | it_engineer | 55.5 | 2.3 |
  | ceo | 52.5 | 7.1 |
  | marketing | 38.7 | 1.4 |
  | sales_engineer | 21.0 | 1.4 |
  | customer_support | 8.3 | 0.5 |

- The **cited** rows sit at similarity p05 0.814-0.822 (multilingual space). The step's best row has a p50 of 0.856.

### 2b. The conversation reply (aiReply): WhatsApp, the widget, the portal, e-mail, the supplier thread

`_shared/ai_reply.ts` and `_shared/company_brief.ts`. The gateway's system message has three parts:

- `sys_shared`: the core brief, with breakpoint 1;
- `sys_stable`: everything else the brief holds, with breakpoint 2;
- `sys`: the rules, uncached.

After the system message come the history (breakpoint 3, on the turn before the newest), then the facts and the message.

| section | approx tokens | cached? |
|---|---:|---|
| Core: company.md 8,640 · conversation_style 2,552 · uae_contract_practice 4,215 · gulf_arabic_guide 5,226 | 20,719 | bp1, the same for every reply |
| Supplier how-to (supplier readers only) | 4,973 | bp2 |
| ONE trade pack (54 packs) | 7,321-9,717 (p50 8,938) | bp2 |
| Live company block (`fn_company_context`, ≤ 8,000 chars) + price guide (that trade family's lines) | ~3k + ~1-4k (derived: Sonnet replies read ~36k of ~42k from cache) | bp2 |
| Reply rules (`aiSystem`) | 913 | uncached on turn 1; inside bp3 from turn 2 |
| History | conversations are short: 60 in 30 days, **median 4 turns, p99 12, max 12; p99 7.3k chars** (~3k tokens) | bp3 |
| This conversation's facts (≤ 6,000 chars) + the message | ≤ 3k | no |

Measured cache behaviour:

| route | cache reads | read per call |
|---|---:|---|
| Sonnet `wa_inbound` | 85% | 35,985 of 42,288 |
| Sonnet `site_assistant` | 88% | |
| Luna Pro `reasoned_delivery` | 91% | |

So the brief is already the cheap part of a reply. The leftover waste is in **which rung** sends it uncached (§3, W1).

### 2c. WhatsApp classification

It is a lean think() decision: no brief, no planner, no retrieval (`reasoned_channels.ts` waRequest).

- It carries about 9.3k approx-tokens of decision options (the trade list) plus the conversation window.
- On Luna Pro it measured 28.4k billed tokens, of which 24.5k were cache reads (86%).
- It does **not** carry the reply's context. This is not waste.

## 3. The waste found, with evidence

**W1. A review or other-family call to Sonnet is never cached: the flag follows the wrong model.**

- `fn_ai_route_review_for` builds on `fn_ai_route` for the class and swaps only the model. Its `cache` field stays the base
  route's, which is the primary's `supports_cache` (Luna Pro: false).
- On 10 Nov, 15:58-16:06 UTC, there were 20 Sonnet 5.5 conversation_reply calls (fn `sales_engineer`, counterpart Luna Pro), 2-3 a
  minute.
- They carried 32.7-36.2k prompt tokens each, with the same ~33k-token brief prefix.
- **0 tokens were read from the cache and 0 were written: AED 5.45.**
- These were the re-asks of 20 refused WhatsApp turns (`wa_inbound.unwritten_reply`, 20 rows).
- The reverse is wrong too. An Anthropic-primary class whose pick is Qwen or Luna Pro would be sent `cache_control` blocks.

**W2. A cache write that is never read: the settled facts were one block per seat.**

- think() marks the whole settled-facts prefix as one block: about 10.6k shared by every seat plus a 2-6k card of the seat's own.
- On an Anthropic route, a block is read back only from a write of the SAME bytes up to its breakpoint. A seat never reads
  another seat's write.
- Sonnet knowledge_validation, 7 days: about **14k written and 1.5k read a call**. The written size matches the settled facts
  (13.3-16.5k per seat).
- The CEO's Opus judgement: 4 calls, 16k written each, 0 read.
- The calls are minutes to hours apart, and the 5-minute TTL expires between them.
- Over 30 days (which includes the knowledge-exam bursts), caching still paid on every Anthropic class but one. The only net
  loss was knowledge_validation for the CEO: USD −0.13 (reads saved minus the write premium, at registry prices).
- So a blanket "no cache on sparse classes" switch would be wrong. The fix is to give the shared part its own breakpoint.

**W3. A re-pass re-pays the whole payload, because its note sits before the payload.**

- A refused draft, or the reviewer's correction, appended its note to the END of the system prompt, ahead of the user payload
  (the question, the context and every source).
- A provider that caches by prefix (Luna Pro) therefore re-billed the payload at the full rate.
- Measured, 14 days of held runs: **62 re-passes over 366 runs**. marketing had 30 of 44 runs re-pass, it_engineer 28 of 149.

**W4. Retrieval sends 12 rows a step, and the answer uses about 2.**

- From 2a: 21-56 rows read a run against 1.4-7.1 cited.
- The excerpts reach 2,400 chars (about 1,100 on average).
- In the upper-mode internal answer, sources are roughly 55% of the call (estimated from the bimodal sizes: about 30k with
  few sources, 86-97k with them).
- The review is sent every source again, not the ones the answer cites.

**W5. A yes/no headline choice carries the whole think() pipeline.**

- `marketing.trend_relevance` ran 144 times a week: "does this news item matter to QuotesDone? relevant / not relevant, and one
  line why".
- Each run made a 34.5k-token plan call and a 74.1k-token answer call on Luna Pro, with the settled facts and about 40 retrieved
  rows.
- That is ~300 calls, **~16M of the week's 62.6M Luna Pro prompt tokens, AED 5.30 a week**.
- The WhatsApp classification already shows the lean shape for a choice among given options (an empty plan).

**W6. The 46-class Sonnet fallback and the Sonnet reviewer pool rank 1.**

- 46 of 100 `model_policy` rows fall back to Sonnet 5.5, at USD 2.00/10.00 against Luna Pro's 0.10/0.50.
- This week no internal class used that fallback: there are no internal_judgement or plan rows on Sonnet.
- Luna Pro answers 97.5% of attempts (`llm_route_health`), so the fallback is an outage price. During a Luna Pro outage, the
  week's AED 18.44 of Luna Pro work would cost about 20× on Sonnet.
- Five of the 46 are chat classes: conversation_reply, customer_communication, customer_portal_assistant,
  supplier_communication and visitor_chat. **Ledger 1217 keeps customer chat off the small Claude model**, so those keep Sonnet
  whatever an eval says.

**Looked at and NOT waste (measured):**

- **The WhatsApp classification** is lean and 86% cached (2c).
- **Reply history** is short (2b) and cached. The founder's ruling of 18 Oct is "no turn limit, the whole conversation to the
  model", so history was not cut.
- **The English reply's Arabic guide** (5.2k) is a cache read 85-91% of the time: about USD 0.0005 a reply on Sonnet and
  USD 0.00009 on Luna Pro. Cutting it per language would split the one shared Anthropic block into two (more writes), so it is
  not worth it.
- **The planner's settled facts** (~27k on Luna Pro): the plan's copy warms the prefix the answer reads seconds later, so
  removing it moves the cost to the answer's first read. The computed net is about zero, so it was not cut.
- **The JSON schemas:** the answer schema sits in the system prompt, which Luna Pro caches by prefix and aiReply's history
  breakpoint covers from turn 2. On Anthropic think() routes (rare now) it is about 0.8k uncached a call. A fourth breakpoint is
  not worth it.

## 4. What was implemented: the switches (`supabase/functions/_shared/prompt_diet.ts`)

There is one registry with one runtime override: the `decision_policy` row `prompt_diet` (jsonb), read by each worker at most
once a minute. A missing or unreadable row means the defaults.

- **Switch any cut off without a deploy:**
  `insert into public.decision_policy(key,value) values ('prompt_diet','{"retry_notes_ride_after_the_payload":false}')
  on conflict (key) do update set value = excluded.value;`
- **Structural switches** (same words, better caching or ordering) are **ON**.
- **Content switches** (fewer words) are **OFF** until §5 passes.

| switch | kind / default | where | what it does | offline proof (`prevented by`) |
|---|---|---|---|---|
| `review_route_caches_by_the_model_it_calls` | structural / **ON** | `ai_gateway/route_cache.ts`, `handle.ts` | A counterpart call takes the cache flag of the model it CALLS (`model_registry.supports_cache`, cached 10 min per worker). If the read fails, the old flag stays. (W1) | `ai_gateway/route_cache.test.ts`: the 10 Nov input (base false, pick Sonnet) is cached; the reverse is not; the old rule is shown false |
| `settled_facts_ride_as_one_shared_cache_block` | structural / **ON** | `think/settled.ts` splitSettled, `think/deps.ts` cachedHalves | The head every seat shares goes as `sys_shared` (its own breakpoint); the seat card goes as `sys_stable`. **The bytes are unchanged**: shared + stable === the old block, so Luna Pro is sent the identical prefix. (W2) | `_shared/prompt_diet_settled_block.test.ts`: byte identity for 6 seats × 5 audiences; one head for every seat; the founder's facts sit in the head |
| `retry_notes_ride_after_the_payload` | structural / **ON** | `think/engine.ts`, `think/diet.ts` placeRetryNote | The refusal or reviewer note ENDS the input. The re-pass's system prompt and payload are byte-identical to the first pass, so they are a cache prefix. The words are unchanged, and aiReply's rewrites already worked this way. (W3) | `_shared/prompt_diet_think.test.ts` (both notes; switched off, the old placement returns); `think.test.ts` updated to read system + input |
| `retrieval_keeps_the_top_rows_above_a_floor` | content / **OFF**; scope internal_judgement; k 4, delta 0.04 | `think/engine.ts`, `think/diet.ts` keepTopRows | A step sends at most k rows within delta of its best similarity. `best` (and so research and thinness) is still computed over all 12; the step records `rows` and `kept`. (W4) | `_shared/prompt_diet_think.test.ts`: payload < 50% of before; the cited row, the question, the settled facts and the rulings are present; a customer's answer is not in scope |
| `the_reviewer_reads_the_cited_sources_only` | content / **OFF** | `think/engine.ts`, `think/diet.ts` reviewSources | The review gets the sources the answer cites. If it cites none, it gets all of them. The settled facts stay (the 10 Nov routing eval: a judge must see the brief). (W4) | same file: review input < 20% of before; the question, the answer and the settled facts are present |
| `a_trend_relevance_choice_plans_and_retrieves_nothing` | content / **OFF**; scope `marketing.trend_relevance` | `marketing/duties/trends_geo.ts` judgeTrend | The choice gets an empty plan: no plan call and no retrieval. The settled facts, the rulings, the options, the headline and the case recall stay. (W5) | `marketing/trend_relevance_diet.test.ts`: off, the plan and retrieval run; on, one call with < 60% of the characters and every required element present |

**Run:**

- Deno: 18 new tests, plus 259 across the think, reasoned-channels, aiReply, gateway (including `drill_provider_faults`),
  marketing, `model_says` and `voice_draft` suites, all passing.
- `deno check` clean on ai_gateway, marketing, resilience_ping, wa_inbound, sales_engineer and site_assistant.

**Prepared, not applied** (`scripts/sql/claude_haiku_5_5_is_registered_unapproved_until_its_side_by_side_passes.sql` and its
`scripts/sql/pending/` note):

- It adds an `anthropic/claude-haiku-5.5` row: tier medium, USD 0.10/0.50, **approved false, active false**, with unmeasured
  cache, context and modality values left null or false. It ends with a verdict row.
- The model is absent today: the only Haiku row is `~anthropic/claude-haiku-latest`, which no policy routes to.
- No policy row names it. Its live catalogue price must be read before it is applied (the pending note says how).

## 5. The eval for the paid round (prepared, NOT run)

`node scripts/eval/prompt_diet_eval.mjs plan` prints the cost and the rules below (offline).

- `sample` draws the cases **read-only**:
  - recorded internal-duty questions from 10 internal surfaces;
  - public headlines.
- `sample` anonymises before anything leaves the machine: e-mails, phone numbers, the subject and the dedupe ids are replaced.
  It refuses to write inside the repository.
- No demo or fixture rows exist on those surfaces (0 of the 282 rows on the 15 largest internal surfaces), so recorded rows are used.
- `run --paid` starts `scripts/eval/prompt_diet/replay.ts` (Deno):
  - It uses the model-routing harness: a rehearsal window, a tagged ai_cost_log row for every call, and `guardSpend` before
    every call.
  - Calls go to OpenRouter directly, because Haiku 5.5 is not routable yet.
  - Retrieval reads production read-only routines. Every writing routine (case recall's judgement row, holds, decisions) is a
    stub.
  - Both arms of a case share **the same plan and the same retrieved rows**, so the cut is the only difference.
- Guard: `scripts/checks/the_prompt_diet_eval_is_capped_and_anonymised.test.mjs` (the cost is under USD 1.50, it refuses without
  `--paid`, it anonymises).

| part | what | cases | expected USD |
|---|---|---:|---:|
| P1 | retrieval top rows: internal_judgement on Luna Pro, OLD vs NEW, judged by Qwen 3.8 Flash | 16 | 0.353 |
| P2 | trend relevance with no plan: Luna Pro, OLD vs NEW | 16 | 0.359 |
| P3 | reviewer reads cited sources only: Qwen (the live route), real answers + seeded wrong figures | 6 | 0.114 |
| P4 | **reviewer side by side: Haiku 5.5 vs Sonnet 5.5** on eval C's 60 constructed drafts | 60 | 0.290 |
| P5 | **fallback side by side: Haiku 5.5 vs Sonnet 5.5** on P1's NEW answer prompt (internal classes only) | 3 | 0.224 |
| | **total (no cache reads assumed)** | | **1.340** (hard stop 1.45, budget 1.50) |

**Pass rules:**

1. **P1, P2, P5:**
   - The judge (never the author's family) rates NEW equivalent-or-better on **≥ 95%** of cases. With 16 cases that means all
     16, and one "worse" fails the cut.
   - NEW has **zero rule violations**: none listed by the judge, plus code's figure check (no figure NEW states that its sources
     and the settled facts do not print, where OLD's were all grounded).
   - P2 also needs the same relevant/not-relevant choice.
2. **P3:** verdicts agree on ≥ 95% of answers, and the cut misses no seeded defect that the all-sources review caught.
3. **P4:** Haiku flags ≥ 28/30 defects and ≤ 3/30 clean drafts, with 0 unread (eval C's bar), and is no more than 1 below
   Sonnet on either count.
4. **A part that fails, or that the cap stopped,** leaves its switch OFF and its model unrouted.

## 6. The saving

Volumes are this week's. AED 3.6725 to the USD. 10× is linear unless noted.

| item | basis | today, AED/week | at 10×, AED/week |
|---|---|---:|---:|
| Already done 10 Nov (ruling 1571): knowledge_validation Sonnet → Qwen | **measured** 21+1 calls, AED 7.99 → ~0.3 at Qwen's price | 7.7 | 77 |
| W1 `review_route_caches_by_the_model_it_calls` (ON) | **measured** burst (20 calls, AED 5.45, 0 cache); **estimated** 4 writes at 1.25×, 16 reads at 0.05× → ~60% off; assumes one such burst a week | ~3.3 | ~33 |
| W2 `settled_facts_ride_as_one_shared_cache_block` (ON) | **estimated**: the Anthropic think() calls are now few (the reviewer is Qwen); it pays in bursts (exams, evals) and on the Sonnet fallback | ~0.5 | ~5-10 (denser traffic hits more) |
| W3 `retry_notes_ride_after_the_payload` (ON) | **measured** 14% of answer calls are re-passes; **estimated** ~57k payload a re-pass at 0.09/M saved | ~1.2 | ~12 |
| **structural, live at deploy** | | **~5** (≈ 15% of today's routing) | **~50** |
| W4a `retrieval_keeps_the_top_rows_above_a_floor` (OFF → eval) | **estimated** −22k Luna Pro tokens per internal answer (2/3 of the sources) × 279/week, uncached | ~2.3 | ~23 |
| W4b `the_reviewer_reads_the_cited_sources_only` (OFF → eval) | **estimated** −21k tokens a review × ~25/week on Qwen | ~0.3 | ~3 |
| W5 `a_trend_relevance_choice_plans_and_retrieves_nothing` (OFF → eval) | **measured** AED 5.30/week; **estimated** NEW ≈ one ~30k call, AED 0.9-2.2 | 3.1-4.4 | 3.1-4.4 (feed-bound, does not scale with customers) |
| **content, after the eval** | | **~5.7-7** | **~29-30** |
| W6 Haiku 5.5 as the internal fallback and reviewer (after P4/P5) | **measured** ~0 this week (no internal Sonnet fallback rows); **estimated** an outage week saves ~AED 350 (AED 18.44 of Luna Pro work at Sonnet's ×20 vs Haiku's ×1) | ~0 | ~0 (outage insurance) |

**In total**, on top of the 10 Nov move:

- **Today:** about AED 5 a week from the structural switches as soon as they are deployed, and about AED 11-12 a week once the
  three content switches pass. That is roughly a third of today's routing (about AED 34 a week).
- **At 10× volume:** about AED 80 a week.

Most of what is left is the settled facts (~20-27k Luna Pro tokens a think() call) and the sources. The next lever after this
eval is the facts a duty actually needs: one seat card section instead of the whole company file. That is content, so it needs
its own eval.

## 7. Deliberately not done here

- **No model call, no SQL applied, no deploy, no PR.**
- `graphify update .` was not run: graphify is not installed, and the disk has under 1 GB free.
- History summarisation was **not implemented**:
  - nothing in 30 days exceeds 12 turns;
  - the 18 Oct ruling says no turn limit.
- If the founder reads ruling 1619 as overriding the 18 Oct ruling, the cut goes in `fitHistory` with every one of the person's
  own turns kept verbatim.
