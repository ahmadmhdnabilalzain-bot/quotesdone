# Model routing per task: design, measured (it_engineer, cost seat; 10 Nov 2026)

Read-only. Production `htdblwldjkcgjvmqkbeh` was read with SQL only. Prices come from the live OpenRouter catalogue
(`https://openrouter.ai/api/v1/models`, fetched 10 Nov 2026 02:03 UTC) and from `model_registry`. No model was called and
nothing was written or deployed.

Labels: **M** means measured (ai_cost_log, model_policy, the registry, the catalogue). **E** means estimated: an
assumption is stated each time. **C** means read in the code at the path given.

Rulings applied: 1571 (simple tasks must not use Sonnet; the session picks the model by measured quality and cost),
1572 (the sales inquiry chat must reason like an expert, cope with Arabic dialects and hold up to 100 messages with
nothing forgotten; a cheaper model is allowed if it holds quality), 1339 (every reply is model-written unless
OpenRouter is down; notifications stay templated), 1241 (Gemini is for voice/audio only), 1240 (the 5.6 generation is
out), 1218 (Pro when the price is the same), 1217 (two excluded models stay out and are not named here), 1219 (Sonnet
for customer chat; 1571 overrides it for simple tasks, and section 2 says where it still applies), and
1056/1107/1108 (Opus for the comparison report and the CEO's hard work, which stays as it is).

---

## 0. The answer in five lines

1. **Spend over 30 days: USD 306.24 (M).** 41% of it was Sonnet on chat (conversation_reply, customer_portal_assistant,
   visitor_chat: USD 128) and 10% was the Sonnet reviewer (knowledge_validation: USD 31.6). Nearly all of it is test
   traffic, because all data is demo (1561).
2. **GPT-6 Luna Pro costs USD 0.10 in, 0.50 out and 0.01 cache-read per Mtok (M, live).** That is 1/20 of Sonnet 5.5.
   It already carries 31,100 production calls with 97.5% OK (llm_route_health, M). Every T1 and T2 task should run on
   it. Its cross-family partner is Qwen 3.8 Flash for simple work and Sonnet 5.5 for customer-quality fallback.
3. **The intake "voice" call is the single most wasteful line.** It sends the ~35k-token company brief to rephrase one
   code-decided sentence, at **USD 0.040 to 0.053 a call on Sonnet (M, 4 and 10 Nov)**. Moving it to Luna Pro without
   the brief brings it to about USD 0.0004 (E).
4. **At 100 customers plus 100 suppliers a month:** about **USD 353/month before**, and **USD 89 to 134 after (E)**,
   depending on the model the inquiry interview passes on. The interview is the only T3 conversation class. Its
   candidates are Luna Pro, then GPT-6.1 Terra Pro, with Sonnet kept if both fail. Per inquiry of 20 customer turns, the
   chat costs **USD 0.93 now** against **USD 0.03 (Luna Pro) or USD 0.20 (Terra Pro)**.
5. **The eval before the switch costs about USD 1.8 expected and USD 2.9 at worst** (section 5). Everything stays under
   the USD 3 cap.

---

## 1. Inventory: last 30 days, production `ai_cost_log` (M)

The window is 11 Oct to 10 Nov 2026: 45,209 rows and USD 306.24 reported by OpenRouter. 1,457 rows carry a model but no
reported cost, so the total is a floor.

The daily series is spiky. The test days are 19 Oct (USD 98.9), 27 Oct (33.1), 2 Nov (38.1) and 3 Nov (62.2). Idle days
run at USD 0.4 to 2.3. **The last 7 days total USD 15.89, about USD 68/month.** "Test %" means rows that carry an e2e
run tag or come from `knowledge_exam` or `resilience_ping`. CF means the class is customer- or supplier-facing.

| task_class (route today: primary → fallback) | fn (via fn_task_class or caller) | CF | calls/30d | /day | avg in / out tok | USD/call | USD/30d | test % |
|---|---|---|---|---|---|---|---|---|
| internal_judgement (luna-pro → sonnet; CEO seat row → **opus-5.5**) | knowledge_exam, resilience_ping, marketing, ceo_agent… | no | 5,116 | 170 | 39,299 / 1,817 | 0.0151 | **77.20** | 82 |
| conversation_reply (**sonnet-5.5** → luna-pro) | wa_inbound, inquiry_intake (voice), supplier_api, site_assistant, email_triage, reasoned_delivery | **yes** | 3,361 | 112 | 117,470 / 275 | 0.0228 | **76.71** | 55 |
| customer_portal_assistant (**sonnet-5.5** → luna-pro) | sales_engineer (portal), site_assistant (signed in) | **yes** | 1,831 | 61 | 144,299 / 310 | 0.0200 | 36.59 | 65 |
| knowledge_validation, the reviewer (**sonnet-5.5** → luna-pro) | knowledge_exam, resilience_ping, email_triage, customer_api… | reviews CF text | 1,341 | 45 | 20,993 / 314 | 0.0236 | 31.64 | 92 |
| visitor_chat (**sonnet-5.5** → luna-pro) | site_assistant (homepage widget) | **yes** | 614 | 20 | 131,907 / 220 | 0.0247 | 15.14 | 35 |
| quote_comparison (**opus-5.5** → luna-pro) | quote_compare, quote_review | **yes** | 96 | 3.2 | 10,934 / 5,460 | **0.1498** | 14.38 | 100 |
| supplier_trade_choice (luna-pro → sonnet) | supplier_doc_trades | supplier | 13,868 | 462 | 36,004 / 951 | 0.0010 | 13.78 | 96 |
| routine_employee_reasoning (luna-pro → sonnet) | think() planning steps, every seat | no | 6,498 | 217 | 19,580 / 1,319 | 0.0018 | 11.43 | 70 |
| inquiry_qualification_conversation, the interview (**sonnet-5.5** → luna-pro) | inquiry_intake | **yes** | 651 | 22 | 4,725 / 859 | 0.0149 | 9.70 | 100 |
| customer_communication (luna-pro → sonnet) | think() steps in wa_inbound, public_site, site_assistant, customer_api | yes (drafts) | 5,066 | 169 | 16,996 / 989 | 0.0013 | 6.82 | 56 |
| document_extraction (luna-pro → sonnet) | supplier_doc_trades | supplier | 1,913 | 64 | 37,250 / 2,527 | 0.0031 | 5.91 | 100 |
| supplier_communication (luna-pro → sonnet) | supplier_api, wa_inbound, email_triage, quote_extract | supplier | 2,023 | 67 | 21,875 / 1,272 | 0.0015 | 3.08 | 55 |
| sales_engineer__document_extraction (luna-pro → sonnet) | license_extract, extract_text, quote_extract, drawing_redact | supplier | 951 | 32 | 21,368 / 643 | 0.0015 | 1.40 | 84 |
| seat_deliberation_compare/_blind (opus-5.5 → luna-pro) | resilience_ping (CEO) | no | 35 | 1.2 | ~4,700 / 1,600 | 0.03–0.04 | 1.22 | 100 |
| ceo__internal_judgement (opus-5.5) | judges in the chat drills | no | 40 | 1.3 | 487 / 317 | 0.0083 | 0.33 | 63 |
| identity_redaction_verify (sonnet-5.5 → luna-pro) | drawing_redact_verify | no | 26 | 0.9 | 2,883 / 181 | 0.0056 | 0.14 | 54 |
| drawing_and_boq_analysis (luna-pro) | drawing_boq | **yes** (BOQ) | 31 | 1 | 18,144 / 3,003 | 0.0027 | 0.08 | 61 |
| json_extraction, intent_detection, marketing_*, GEO, other | various | mixed | ~450 | – | small | ≤0.03 | ~0.6 | – |
| *tier none (vat, kpi, supplier_matching, workflow, money_state_change…)* | – | – | 0 | – | – | 0 | 0 | – |

### What the per-class view hides (M)

- **Prompt size, before and after #1849 (3 Nov, "core plus one trade pack").** The 30-day averages of 117k to 144k
  tokens are mostly from before the fix. After it, on 10 Nov: wa_inbound conversation_reply uses **23,036 in (20,207
  cached) and 159 out, USD 0.0118 a call**, against 143,585 tokens and USD 0.0222 on 3 Nov. The intake voice uses
  **35,568 in and 87 out, USD 0.053**. visitor_chat uses 4,447 in.
  - The brief as measured (`brief.generated.ts`, `approxTokens`): core 20,719 tokens, supplier how-to 4,973, trade packs
    7,319 to 9,716 each, all 88 parts 109,673. The old prompt (core plus every part) was about 130k, which matches the
    pre-fix rows.
- **Since #1849 the voice call costs more per call** (USD 0.030 on 3 Nov, USD 0.040 to 0.053 on 4 and 10 Nov). Per-trade
  packs break the shared prefix, so more of the prompt is uncached, and `ai_reply.ts` asks for a 1-hour Anthropic cache.
  That write is billed at a premium: the measured cost runs about 1.27 times the read-price formula.
- **The idle burn is the heartbeat.** In the last 7 days, resilience_ping CEO ticks on Opus cost USD 1.41 (USD 0.158 a
  call) and the Sonnet reviewer inside resilience_ping cost USD 1.63.
- **On 10 Nov, 13 customer_portal_assistant rows were logged with 0 tokens and no cost, some ok=false.** A portal stream
  either fails or is metered as nothing. This needs a look whatever the routing; it is out of scope here.
- **Registry drift.** deepseek/deepseek-v4.1-flash is registered at 0.30/1.20 but is live at **0.051/0.567**.
  gemini-3.8-flash has no cache price (live 0.0825). gpt-6.1-terra-pro and qwen3.8-flash are not registered.

---

## 2. Tiers

| Tier | What belongs | Classes / paths | Why |
|---|---|---|---|
| **T0: no model** | *Proactive notifications nobody asked for*: the OTP or sign-up code, "your quotation is ready", "your comparison report is ready", payment receipts, sending an invoice PDF with a fixed caption, the submission receipt, the closed-thread notice, Meta-approved template frames | the existing template senders (WhatsApp `wa_template_registry`, e-mail templates); tier-`none` rows (vat, kpi, supplier_matching, workflow_*, money_state_change, date, duplicate) | Ruling 1339 covers **replies**. The memory note on it says notifications stay templated (`the-engineer-and-support-reply-only-through-the-model.md`). Meta requires approved templates outside the 24-hour window anyway. Cost 0. |
| **T1: small and fast** | *Replies to simple asks*: "where is my quote?", "send me my invoice again", "is the comparison ready?", "my verification code didn't arrive", the voicing of a sentence code has already decided (the intake voice, the held/holding notice), intent/email triage, category classification, simple field extraction, summaries, health ping, translation of short text | **new** `status_reply` and `voice_draft` classes; intent_detection, email_triage, category_classification, json_extraction(_text), memory_retrieval, ocr_cleanup, general_drafting, inbound_email, resend_inbound, summarization, health_ping, translation(_general) | Code fixes the content (status row, reference, the one question). The model only words it in the person's language and dialect, which Luna Pro does. **This is how 1339 is honoured cheaply.** The words stay the model's; the prompt is about 2.5k tokens with no brief; `must` carries the reference; `modelOrOutage` keeps the template for a real outage only. About USD 0.0003 a reply (E). 1571 orders this tier off Sonnet, fallback included. |
| **T2: mid** | Normal support replies on WhatsApp, the supplier thread, the portal assistant's Q&A, the homepage visitor widget, e-mail replies, think() draft steps | conversation_reply, customer_portal_assistant, visitor_chat, customer_communication, supplier_communication, routine_employee_reasoning, internal_judgement (non-CEO), support_ai | These need the brief (core plus a pack, about 23k tokens, mostly cached) and policy-safe wording in four language registers. Luna Pro was shortlisted by the founder for customer chat (1217/1218). It scored 8.20 against Sonnet's 8.80 on 13 Oct, but that test used the old 140k prompts. This tier is switched **only after eval A passes** (section 5), because 1219 ("sonnet") is still standing for chat beyond simple tasks and 1571 lets the session overrule it on measured quality. A complicated WhatsApp ask (a new job, drawings, several trades) is sent to the app's request chat, as 1571 allows, with the link in `must`. |
| **T3: strong** | (a) the **sales inquiry interview** (expert reasoning, dialects, 100 messages); (b) **document understanding** of supplier profiles and licences (1573); (c) the **quote comparison**; (d) **CEO decisions, approvals and planning** | (a) inquiry_qualification_conversation; (b) sales_engineer__document_extraction, document_extraction, supplier_trade_choice, drawing_and_boq_analysis; (c) quote_comparison; (d) ceo__internal_judgement, ceo_approval_decision, ceo_strategic_planning, seat_deliberation_*, executive_report | (a) This is the founder's quality bar (1572) and it decides what suppliers receive. The model is chosen by eval B. (b) This already runs on Luna Pro at USD 0.001 to 0.003 a call (M). Keep it there and measure correctness through 1573's verification, not with a stronger model. (c) and (d) stay on **Opus 5.5** under 1107/1108. It is low volume: the comparison is about USD 18/month at scale. GPT-6.1 Sol Pro would halve it (USD 0.076 a report, E), but that is the founder's call, not part of this change. |

### Holding 100 messages (1572), whatever the model (C)

The interview call already sends the whole transcript (`inquiry_intake/handle.ts:276`, `convo = turns.map(...)`).
`fitHistory` keeps everything up to about 500k tokens (`_shared/chat_history.ts:24`). A 100-message intake is about
14k tokens of history, which fits every candidate's 1M window.

The gap is the voice call: `inquiry_intake/slots.ts:121` sends only `conversation.slice(-12)`. That rule says "Never
repeat a question they already answered", and the model cannot keep it for an answer given more than 12 turns back.
The voice is cheap on Luna Pro, so send it the whole history.

---

## 3. Candidates per tier: live OpenRouter prices in USD per Mtok (M, 10 Nov 2026)

| Tier | Candidate (family) | in / out / cache-read | ctx, input | Arabic and dialects | On the estate |
|---|---|---|---|---|---|
| T1 primary | **openai/gpt-6-luna-pro** (OpenAI) | 0.10 / 0.50 / 0.01 | 1.05M, text+image+file | Good: founder-shortlisted for customer chat; carries production WhatsApp customer_communication today | registered, active; 31,100 attempts, 97.5% OK |
| T1 fallback | **qwen/qwen3.8-flash** (Qwen) | 0.15 / 0.47 / 0.016 | 1M, text+image+video | Strong multilingual line (Qwen was the founder's 23 Sep pick for Arabic at the Max size) | **not registered** |
| T1 alternate | deepseek/deepseek-v4.1-flash (DeepSeek) | 0.051 / 0.567 / 0.018 | 1M, text+image | Weaker in Arabic dialects (E); acceptable for internal fallback | registered at a **stale** 0.30/1.20, inactive |
| T2 primary | **openai/gpt-6-luna-pro** (OpenAI) | 0.10 / 0.50 / 0.01 | as above | as above | as above |
| T2 fallback / second rung | **anthropic/claude-sonnet-5.5** (Anthropic) | 2.00 / 10.00 / 0.10 | 1M | Best measured (8.80, 13 Oct) | active; used only when Luna fails (2.5%) or for the cross-family rewrite |
| T3a interview, candidate 1 | **openai/gpt-6-luna-pro** | 0.10 / 0.50 / 0.01 | – | – | eval B decides |
| T3a interview, candidate 2 | **openai/gpt-6.1-terra-pro** (OpenAI; Pro at the same price as Terra, per 1218) | 1.00 / 5.00 / 0.05 | 1.05M, file | Same generation as 6.1 Sol, which was shortlisted (E) | **not registered** |
| T3a control / fallback | anthropic/claude-sonnet-5.5 | 2.00 / 10.00 / 0.10 | – | – | today's route |
| T3b documents | openai/gpt-6-luna-pro, with the cross-family check on Sonnet 5.5 (identity_redaction_verify, drawing_boq_confirm) | – | – | Licences are English/Arabic bilingual | today's route |
| T3c/d comparison and CEO | anthropic/claude-opus-5.5 (4 / 20 / 0.20), fallback openai/gpt-6-luna-pro | – | – | – | today's route, ruling 1107/1108 |
| Reviewer of OpenAI authors (internal) | **qwen/qwen3.8-flash** (Qwen), fallback Sonnet 5.5 | 0.15 / 0.47 | – | – | replaces Sonnet in knowledge_validation and sales_engineer__knowledge_validation; the CEO's own review row stays Sonnet |

**Not considered:** the Gemini text models (1241), the 5.6 generation (1240), and the two models ruled out by 1217. GLM
5.3 Flash is out for customer text because the founder judged its Arabic short of customer quality (844).

**The cross-family rule** (`every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql`, guarded
by `scripts/checks/no_review_class_can_route_to_its_authors_family.test.mjs`) holds under this design:

| Author | Reviewer or second rung |
|---|---|
| Luna Pro (OpenAI) | Qwen 3.8 Flash or Sonnet 5.5 |
| Terra Pro (OpenAI) | Sonnet 5.5 |
| Opus (Anthropic) | Luna Pro |

The active `review_pool` today is Sonnet 1, Opus 2, Luna Pro 3. Add Qwen 3.8 Flash at rank 4, so a review of an OpenAI
author can always find a non-OpenAI, non-Sonnet-priced model.

---

## 4. Monthly cost projection

### 4a. Today's measured volume, re-priced (M tokens, live prices; Luna Pro priced with no cache-write premium)

| Window | Before (reported) | After the class moves | Notes |
|---|---|---|---|
| 30 days, the chat classes on Sonnet (3,148 + 1,736 + 479 calls) | **USD 124.66** | **USD 8.55** (model only) / **USD 2.73** (model and the #1849 cap applied to the pre-fix rows) | The cap alone, on Sonnet, would have given USD 40.55 |
| 30 days, knowledge_validation on Sonnet/Opus (934 calls) | USD 30.44 | USD 2.26 (Qwen 3.8 Flash) | |
| 30 days, the interview (651 calls) | USD 9.70 | USD 0.46 (Luna Pro) / USD 4.49 (Terra Pro) | |
| **30 days, all classes** | **USD 306.24** | **about USD 150 (Terra) to 146 (Luna)** | Opus CEO, Opus comparison and the Luna Pro classes are unchanged |
| **Last 7 days, run rate** | **USD 15.89/week ≈ 68/month** | USD 11.34/week; **≈ USD 10.3/week ≈ 44/month** with the heartbeat input guard (E: −70% of USD 1.41/week of Opus heartbeat) | |

### 4b. Scale: 100 active customers and 100 suppliers onboarding in the month (E)

Unit costs are measured where marked. Volumes are assumptions.

**Volume assumptions (E):**
- 1.5 inquiries per customer (150 inquiries), each with 20 customer turns. That is 3,000 interview calls and 2,010 voice
  calls; the 0.67 voices per interview is the M ratio 329/651 adjusted.
- Portal: 10 turns per customer (1,000).
- WhatsApp: 15 messages per customer and 5 per supplier (2,000), 60% of them status-type.
- 120 comparisons.
- Suppliers: 20 thread messages each (2,000 supplier replies) and 300 quotes.
- Homepage visitors: 1,000 widget turns.
- Reviews on 5% of replies.
- Background seats: USD 84/month before, twice today's idle; USD 46 after.
- Luna Pro lines carry a 10% rewrite overhead plus 2.5% of calls going to the Sonnet second rung.

**Unit costs per call:**
- WhatsApp reply: Sonnet **0.0118 (M)**, Luna Pro 0.00056.
- Status reply: Luna Pro 0.00029.
- Voice: Sonnet **0.045 (M)**, Luna Pro without the brief 0.00037.
- Interview at 6k tokens: Sonnet 0.0164 (M 0.0158 at 4.4k), Terra 0.0082, Luna Pro 0.00083.
- Portal, visitor and supplier thread: Sonnet 0.0145 to 0.0164, Luna Pro about 0.0008.
- Comparison on Opus: **0.1498 (M)**.
- Supplier onboarding documents: **0.071 (M** per-call costs × per-onboarding call ratios, which are test-heavy).

| Line (USD/month) | Before | After: interview on Luna Pro | After: on Terra Pro | After: Sonnet kept for the interview |
|---|---|---|---|---|
| Intake interview | 49.32 | 3.99 | 28.36 | 49.32 |
| Intake voice | **90.45** | 1.12 | 1.12 | 1.12 |
| Portal assistant | 15.46 | 1.26 | 1.26 | 1.26 |
| WhatsApp replies (customers and suppliers) | 23.60 | 1.24 | 1.24 | 1.24 |
| Visitor widget | 14.46 | 1.15 | 1.15 | 1.15 |
| Supplier thread replies | 32.72 | 2.64 | 2.64 | 2.64 |
| think() side calls (Luna Pro, unchanged) | 3.93 | 3.93 | 3.93 | 3.93 |
| Reviews | 12.99 | 1.82 | 1.82 | 1.82 |
| Quote comparison (Opus, unchanged) | 17.98 | 17.98 | 17.98 | 17.98 |
| Supplier onboarding documents (Luna Pro, unchanged) | 7.11 | 7.11 | 7.11 | 7.11 |
| Quote extraction (Luna Pro, unchanged) | 0.90 | 0.90 | 0.90 | 0.90 |
| Background seats | 84.00 | 46.00 | 46.00 | 46.00 |
| **Total** | **≈ 353** | **≈ 89** | **≈ 113** | **≈ 134** |
| Per inquiry (20 turns, chat only) | 0.93 | 0.03 | 0.20 | 0.34 |
| A full 100-message inquiry (interview + voice) | ≈ 2.09 | ≈ 0.05 | ≈ 0.33 | ≈ 0.60 |

### How the prompt-size reductions combine with the model change

No written prompt-size note was found in the scratchpad. The only material there is the brief-measurement scripts
`sizes.ts` and `core.ts`, and their numbers are reproduced in section 1. The reductions combine as follows:

1. **#1849, already live (M).** Core plus one pack, capped at `BRIEF_TOKEN_CAP` 40k. This roughly halved the WhatsApp
   reply on Sonnet (0.0222 → 0.0118), but the voice call rose (above).
2. **The voice without the brief (E).** 35.5k → about 4.5k tokens. On Sonnet alone that is worth about USD 75/month at
   scale. On Luna Pro it is worth USD 0.1.
3. **The status lane (E).** About 2.5k tokens with no brief, for 60% of WhatsApp messages.

**After the model change, prompt size stops being a cost lever for T1 and T2.** A 23k-token cached brief costs
USD 0.0002 a call on Luna Pro. Trimming it further is worth under USD 3/month at this scale. Trim it for latency and
quality, not for money. Prompt size still matters on the classes that stay on Anthropic: the interview if Sonnet is
kept, the CEO, and the comparison.

---

## 5. The change set and the eval that gates each switch

### 5a. SQL: one file, with its probe, MANIFEST line and pending note (quotesdone-apply-discipline)

The proposed file is `scripts/sql/simple_tasks_leave_sonnet_and_every_reply_runs_on_the_model_its_task_needs.sql`.
Apply the steps in order. Each customer-facing step goes in only after its eval passes.

1. **`model_registry`:**
   - Insert `qwen/qwen3.8-flash`: provider qwen, tier small, 0.15/0.47, cache-read 0.016, ctx 1,000,000, vision true,
     audio false, tools true, approved, active, `supports_cache` false.
   - Insert `openai/gpt-6.1-terra-pro`: openai, tier medium, 1.00/5.00, cache-read 0.05, ctx 1,050,000, vision and file
     true.
   - Re-price `deepseek/deepseek-v4.1-flash` to 0.051/0.567/0.018.
   - Set the `gemini-3.8-flash` cache-read to 0.0825.
   - Add `llm_route_health` rows for the two new models, with no hold (1260/1175).
   - `scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs` must be updated to these live figures.
2. **`review_pool`:** add `qwen/qwen3.8-flash` at rank 4, active.
3. **`model_policy`, T1 (no eval needed beyond the smoke run; internal or code-decided content):**
   - Set every Luna-Pro class whose fallback is Sonnet, among intent_detection, email_triage, category_classification,
     json_extraction, json_extraction_text, memory_retrieval, ocr_cleanup, general_drafting, inbound_email,
     resend_inbound, summarization, health_ping, translation and translation_general, to
     `model_fallback = 'qwen/qwen3.8-flash'`.
   - Insert **`status_reply`**: tier small, luna-pro → qwen3.8-flash, max_tokens 300, cache_ttl 0.
   - Insert **`voice_draft`**: tier small, luna-pro → qwen3.8-flash, max_tokens 300.
4. **`model_policy`, reviewers:**
   - `knowledge_validation`: primary `qwen/qwen3.8-flash`, fallback `anthropic/claude-sonnet-5.5`.
   - `sales_engineer__knowledge_validation`: the same pair.
   - `ceo__knowledge_validation` stays on Sonnet.
   - Gate: eval C.
5. **`model_policy`, T2 (gate: eval A):**
   - `conversation_reply`, `customer_portal_assistant` and `visitor_chat`: primary `openai/gpt-6-luna-pro`, fallback
     `anthropic/claude-sonnet-5.5`. This swaps today's pair.
6. **`model_policy`, T3a (gate: eval B):**
   - `inquiry_qualification_conversation`: primary set to the model eval B passes (Luna Pro or Terra Pro), fallback
     `anthropic/claude-sonnet-5.5`.
7. **`it_model_consumer`:** register the two new classes so `fn_it_model_consumer_listed` does not flag them.
8. **`founder_instruction`:** a row recording that 1219 is superseded for T2 by 1571 on eval A's evidence, with the eval
   report path. This is the auditor rule: the decision gets a home.

`fn_task_class` needs no change: the new classes are passed by the caller. `model_policy_by_identity` needs no change.

### 5b. Code (C), with line references from this checkout

- **`_shared/ai_reply.ts`:**
  - Line 29: `REPLY_MODEL = 'anthropic/claude-sonnet-5.5'` must name the new primary (`'openai/gpt-6-luna-pro'`) or be
    read from the route. Line 284 builds the "other family first" re-ask rungs from it, so a stale constant would make
    the re-ask start on Sonnet's counterpart, which is the primary itself.
  - Line 238: add `taskClass?: string` to `AiReplyRequest` and use `r.taskClass ?? REPLY_CLASS` in `opts`.
  - The 1-hour cache: keep it Anthropic-only. It is the write premium seen in the 1.27 factor.
  - Update the header comments at lines 10–12, which still say "gemini behind it", against 1241.
- **`_shared/brief_answer.ts:244`:** the default `counterpart_model` follows `REPLY_MODEL`.
- **`inquiry_intake/slots.ts:113-124` (`intakeVoice`):**
  - Pass `taskClass: 'voice_draft'` and `briefInPrompt: false`. The draft already holds the facts, and the figure guard
    still runs against them.
  - Replace `conversation.slice(-12)` with the whole history (1572).
- **`wa_inbound`, the status lane:**
  - Where `classification.ts` resolves the intent (line 59 returns `r.intent`), add the branch to
    `wa_inbound/model_says.ts:62`.
  - Status, invoice-copy, report-ready and verification intents call `aiReply` with `taskClass: 'status_reply'`,
    `briefInPrompt: false`, the status rows as `facts`, the reference or job number as `must`, and the last 6 turns.
  - New-job, drawing or multi-trade asks get a one-line model reply with the request-chat link in `must` (1571).
  - The template is used only through `modelOrOutage` (1339).
- **No change** to `sales_engineer/actions/portal.ts:173` or `site_assistant/index.ts:419`: the class rows move them.
- **Tests:**
  - `_shared/ai_reply.test.ts` (REPLY_MODEL)
  - `scripts/checks/no_review_class_can_route_to_its_authors_family.test.mjs` (must stay green with Qwen as reviewer)
  - `scripts/checks/replies_are_written_by_the_model_unless_openrouter_is_down.test.mjs`
  - `scripts/checks/the_intake_reply_is_the_models_unless_openrouter_is_down.test.mjs` (the status lane must pass both)
  - a new `_shared/ai_reply_task_class.test.ts`
  - Then `npm run gate`, `graphify update .`, and the release runbook (no CI, ledger 1564).

### 5c. The evals: real models through the real `ai_gateway` path, with OpenRouter on (1260)

**The fixed set.** It is checked in as fixtures under `scripts/eval/model_routing/`. Every party is a ZZ DEMO party,
with probe isolation as in the auditor skill.

Every customer turn is **scripted, not simulated**, so runs are comparable and no model writes the customer's side.
Languages: EN, Gulf (Emirati/Saudi: أبي، وايد، شلون، زين), Egyptian (عايز، إزاي، كده، بكام) and Levantine
(بدي، شو، كتير، هلق), plus Arabizi and code-switching ("3ayez", "yalla", "inshallah").

**Eval A: T2 replies (conversation_reply, the portal and the visitor widget) and the status lane.**

40 cases, 10 per register:
- 12 status questions
- 4 invoice-copy requests
- 4 "is my comparison ready?"
- 4 "my code didn't come"
- 8 support questions (fees, the 3% reveal fee, refunds, how quoting works)
- 4 supplier-thread cases in English
- 4 visitor cases

Each runs through the production path with the live brief, on Luna Pro, and once on Sonnet as the control.

Pass, all of these must hold:
- zero critical errors (wrong status or reference, an invented figure (`moneyFiguresNotInBrief` = 0), the wrong
  language, an identity leak, a deferral);
- `must` present in 100% of cases;
- rewrite rate ≤ 15%, second-rung rate ≤ 5%;
- reply in the person's register in ≥ 95% of cases (script detection plus judge);
- judge mean ≥ 8.0 and ≥ the Sonnet mean − 0.5.

The judge is Sonnet 5.5 (another family), scoring batches of 10 cases per call.

**Eval B: the T3a interview and the voice.**

7 scripted inquiries:
- two of them 20 customer turns each in EN, Gulf, Egyptian and Levantine, making 6 conversations of 20 turns;
- one of 50 customer turns (100 messages) in mixed Gulf/Arabizi.

Each one plants at least 3 facts at turn 2 (for example "ceiling 3.2 m", "villa in Al Barsha", "budget about 15k") and
8 expert probes across the set: MDF partition in a wet area → moisture warning plus PVC panel or wrap alternative, then
budget and dimensions; gypsum vs. cement board in a bathroom; AC tonnage for a room size; outdoor tiles slip rating;
and similar. The run order is Luna Pro first, Terra Pro only if Luna fails, and Sonnet as the control on 2 conversations.

Pass:
- a turn-2 fact re-asked after it was given: ≤ 1 across the set;
- every planted fact present in the final `brief.details`;
- ≥ 7 of 8 expert probes met (keywords plus judge);
- ≥ 6 of 7 inquiries reach `ready` with every required checklist key;
- JSON valid on 100% of turns;
- the register held on ≥ 90% of the judged turns;
- the 100-message run finishes with no lost fact and every turn within `turn_clock`;
- judge mean ≥ the Sonnet control − 0.5.

**Eval C: the reviewer swap.**

60 drafts: 30 seeded with one known defect each (a wrong figure, a policy error, the wrong language, an identity leak, a
deferral) and 30 clean.

Pass: Qwen 3.8 Flash flags ≥ 28 of 30 defects with ≤ 3 false flags. Labels are known by construction, so no control is
needed.

**T1 smoke run:** 20 calls each to `status_reply`, `voice_draft` and a T1 fallback forced onto Qwen, checking JSON and
language.

**Eval cost (E, from the unit costs above):**

| Run | Calls | USD |
|---|---|---|
| A, Luna Pro | 40 (plus about 10% rewrites) | 0.03 |
| A, Sonnet control | 40 | 0.48 |
| A, judge | 8 batches | 0.10 |
| B, Luna Pro (interview + voice) | 170 turns, about 285 calls | 0.20 |
| B, Sonnet control (2 conversations; the interview on Sonnet, the voice on Luna Pro in both arms) | 40 turns | 0.70 |
| B, judge | 9 transcripts | 0.32 |
| C, Qwen reviewer | 60 | 0.20 |
| T1 smoke | 60 | 0.02 |
| **Expected (Luna passes B)** | | **≈ 2.05** |
| B2, Terra Pro, only if Luna fails (4 conversations: the failed registers plus the 100-message one) | about 100 turns | +0.87 |
| B2, judge | 4 transcripts | +0.15 |
| **Worst case** | | **≈ 3.07** |

To stay under USD 3 at worst, run eval A's Sonnet control on 20 of the 40 cases (−0.24). That gives **≈ 1.81 expected
and ≈ 2.83 worst**. The session verification cap (1568, about USD 8 of the USD 20 top-up) covers it.

---

## 6. Recommendations, in order

1. **Now (T1, mandated by 1571, no customer-quality risk):**
   - Register Qwen 3.8 Flash and Terra Pro, and correct the DeepSeek and Gemini prices.
   - Move every T1 fallback off Sonnet.
   - Add the `status_reply` and `voice_draft` classes.
   - Move `intakeVoice` to `voice_draft` without the brief and with the whole history. **This is the largest single
     saving: about USD 89/month at scale, M unit cost.**
2. **After eval A:** move conversation_reply, the portal and the visitor widget to Luna Pro, with Sonnet as the second
   rung. This saves about USD 80/month at scale (E), and the founder_instruction row records the 1219 supersession.
3. **After eval B:** move the interview to the cheapest model that passes: Luna Pro (about −USD 45/month) or Terra Pro
   (about −USD 21/month).
4. **After eval C:** put the internal reviewer on Qwen 3.8 Flash. This saves about USD 11/month at scale and USD 30 over
   the last 30 days of test traffic.
5. **Keep Opus** for the comparison and the CEO's decisions (1107/1108). **Stop the CEO heartbeat's Opus calls when its
   inputs have not changed** (`a-30-day-total-is-not-a-run-rate.md`: guard on the input, not the clock). That is about
   USD 4/month today and doubles at scale.
6. **Separately:**
   - The 10 Nov portal rows with 0 tokens and no cost.
   - The 1,457 rows with no reported cost, which make every total here a floor.
