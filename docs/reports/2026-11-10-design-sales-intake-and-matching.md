# Design audit: the customer inquiry conversation (A) and supplier onboarding and matching (B)

Seat: sales_engineer (design audit). Date: 10 Nov 2026. This audit was read-only: I read the code, ran read-only SQL against production (htdblwldjkcgjvmqkbeh), and ran local Deno dry-runs of the repository's own pure functions. I made no model calls and no writes.
Founder expectations: founder_instruction 1572 and 1573 (10 Nov 2026 01:58 UTC). Related ruling: 1253 (18 Oct, "No turn limit on chat memory ... even 500 messages").

---

## 0. Headline

| # | Requirement | Verdict |
|---|---|---|
| A1 | The agent reasons like an expert (condition -> suitable solutions -> asks budget, dimensions...) | **NOT MET** |
| A2 | It keeps going until the inquiry is complete | **PARTLY** |
| A3 | Arabic and English, including Egyptian, Lebanese and Gulf dialects and slang | **PARTLY** (understanding is left to the model; the code detectors miss these dialects; replies are always "formal Gulf Arabic") |
| A4 | Hard limit of 100 messages per inquiry | **NOT MET** (no such limit exists) |
| A5 | Nothing said in message 2 is forgotten by message 30+ | **PARTLY** (whole history is stored and sent, but there are three truncation points and the chat state is not carried into the request) |
| A6 | Use a cheaper model if it holds the quality | **NOT MET / unproven** (every reply runs on Sonnet 5.5; no eval exists) |
| B1 | Read the company profile and trade licence, and understand what the company does | **PARTLY** (built, but **0 documents have ever been read in production**) |
| B2 | Check licence activities against the profile | **NOT MET** (no cross-check exists) |
| B3 | Propose extracted keywords/services that the supplier ticks or adds to | **PARTLY** (trades are proposed; services show as an unticked checklist; the profile's own specific phrases are not proposed as services) |
| B4 | Those keywords drive cross-matching (e.g. "PVC decorative panels" -> that customer) | **PARTLY** (exact code match plus one-level implication; no synonyms or embeddings at match time; the PVC example returns **0 suppliers** today) |

Production carries almost no real traffic, so behaviour cannot be measured from it. Everything in it so far is test traffic:
- inquiry_intake has 18 rows; 14 of them are the same scripted aluminium-windows replay.
- assistant_logs has 60 conversations; the longest has 12 rows and none reaches 30.
- inquiries holds 4 to 6 rows.
- supplier_capabilities has 5 confirmed rows out of 14,750; 0 documents read; 0 trade proposals.

The verdicts above therefore come from the code and from dry-runs. They must be proved by the eval in section 6.

---

## 1. How A is actually built: three customer surfaces, three different designs

There is **no single "sales agent conversation"**. Three surfaces exist, and they share nothing except the stored transcript.

### 1.1 The request chat (`inquiry_intake`; the portal's "New request", src/components/me/NewRequest.tsx)
- **Entry.** `supabase/functions/inquiry_intake/handle.ts` handles one turn. The transcript lives in `inquiry_intake.turns` (jsonb), one row per request.
- **Extraction call.** `handle.ts:276` builds `convo` from **every** turn and sends it whole (`handle.ts:369`, `llm()` -> ai_gateway, json_object, temperature 0.1, max 4000). The model returns a JSON brief. Task class `inquiry_qualification_conversation` runs on anthropic/claude-sonnet-5.5, falling back to openai/gpt-6-luna-pro (from model_policy).
- **Structured state (good).** `slots.ts:193 reconcileSlots` merges `brief.details` into what earlier turns captured, under the checklist's canonical keys (`category_specs.fields`). Status and missing are derived from those slots, not from the model (`slots.ts:231 settleModelTurn`). Each assistant turn is stamped with the state it saved (`slots.ts:323 stampTurn`). Four requirement answers are stored in `brief.req_answers`: material, installation, warranty and required_by (`slots.ts:288`).
- **Reply voice.** `slots.ts:113 intakeVoice` re-writes the code's draft through `aiReply`, using only `conversation.slice(-12)` (`slots.ts:121`). The facts are the draft plus the one question to ask.
- **Repeat questions.**
  - A key that stays open through 3 answered turns is exhausted: `slots.ts:49 MAX_OPEN_TURNS = 3`. The intake is then `held` and handed to sales_engineer (`handle.ts:576 fn_seat_handoff spec.not_sure`).
  - A token-overlap guard drops any question that restates `already_provided` (`handle.ts:532-541`).
- **Knowledge.**
  - `kbFor(slug, text)` runs on the **current message only** (`handle.ts:163`; `knowledge.ts`, kb_query, 3 s budget). It runs only once a trade is stored, so **turn 1 has no field knowledge at all**. Passages are filtered to customer-facing ones (`generated` and `memory` rows withheld under ruling 1338).
  - The fallback is `fn_category_knowledge`.
  - The ordered questions come from `fn_category_questions`.
- **The prompt forbids expert advice.**
  - "on this screen your only job is to collect a complete, accurate brief. Do not pitch" (`handle.ts:283`).
  - "do NOT lecture the customer" (`handle.ts:301`).
  - "assistant_message: 1-2 sentence reply" (`handle.ts:321`).
- **Language.** Taken from `customers.locale` (`handle.ts:109`), not from the message. Rule 4 is "Reply in Arabic/English" (`handle.ts:307`). Dialect is not mentioned anywhere.
- **Truncations.**
  - The two reasoned reads (`tradeOf`, `statedSpecs`) send `conversation.slice(0, 4000)`, i.e. the **first** 4,000 characters (`_shared/reasoned_decisions.ts:69, 89-90`). A late answer in a long chat never reaches them.
  - `raw_input` is stored as `allText.slice(0, 4000)` (`handle.ts:900`).
  - Each message is capped at 4,000 characters (`handle.ts:73`).
- **Limit.** The only limit is `rl_check('intake:'+email, 60, 3600)`, i.e. 60 turns per hour per email (`handle.ts:45`). There is **no per-inquiry message cap**.

### 1.2 The portal assistant chat (`sales_engineer` action `assist`; signed-in portal and widget conversation)
- **History.** `sales_engineer/actions/portal.ts:94` calls `openConversation` -> `_shared/chat_history.ts:loadTranscript`. That reads **every** assistant_logs row of the conv_id, paged. `fitHistory` keeps everything up to 2,000,000 characters (`chat_history.ts:24`), and past that keeps every customer turn verbatim. **This meets ruling 1253 on paper.**
- **State, rebuilt by code every turn from the whole transcript.** Nothing is persisted.
  - `sales_engineer/conversation_plan.ts:284 planState` runs regex slot detectors (`CATALOGUE`, `:78-150`) over normalised Arabic and English.
  - The trade's plan comes from a playbook "Must-haves" line (`knowledge/brief/conversation/*.md`).
  - It works out filled, changed and to-confirm slots and the next must-have.
  - `portal_conversation.ts heldState/heldBlock` puts "ALREADY GIVEN ... never ask again" in front of the model.
  - `replyFilter` drops re-asks sentence by sentence.
  - A bounded `json_extraction` call (gpt-6-luna-pro, 12 s cap, `conversation_plan.ts:442-459`) reads only what the detectors could not.
- **The plan exists only if a trade word matches.** `tradeOf` -> `_shared/conversation_trade.ts:32-80 TRADE_WORDS` (regex). With no match, mode is `none` and no state machine runs; only the general rules apply.
- **Forced summary.** `conversation_plan.ts:244 SUMMARY_AFTER = 6`. After 6 seat replies the reply is the summary, whatever is still open (open slots become "to confirm at site visit", `:362`).
- **Expert behaviour.** The rule `PORTAL_INTAKE` (`portal_conversation.ts`) says: correct a wrong or unsafe spec, ask the two price-driving specs, recommend when the customer is unsure, then summarise. The playbooks carry "Misconceptions to correct". Nothing tells the agent to **propose alternative solutions for the condition the customer describes**.
- **Model.** `customer_portal_assistant` runs on sonnet-5.5, falling back to gpt-6-luna-pro.
- **Handover.** When the chat is done it tells the customer to press **"New request"**. That opens `NewRequest`, a **fresh `inquiry_intake` conversation**: the only seed is the homepage draft (`src/components/me/dashboard/Dashboard.tsx:345 initialText={draft}`). **Everything gathered in the assistant chat is not carried into the request.**

### 1.3 WhatsApp (`wa_inbound`) and the public widget (`site_assistant`)
- **WhatsApp.**
  - The reply gets the whole history (`_shared/wa_history.ts`, 500 rows).
  - The intent decision gets `conversation.slice(-6)` (`_shared/reasoned_channels.ts:97`).
  - No spec state is kept, and nothing writes `inquiry_intake` (grep finds none).
  - Replies are "formal Gulf Arabic" (`wa_inbound/model_says.ts:136`).
- **Widget.** Whole history via `chat_history` (`site_assistant/index.ts:247, 412`). No slot state. Replies are "formal Gulf Arabic" (`site_assistant/index.ts:403`).
- **Supplier onboarding chat.** `supplier_onboard/index.ts:159` slices history to the last 8 turns, but the function is **dormant**: it has no caller in src/ (its own header, lines 4-17).

### 1.4 What the history windows add up to (the brief's list, checked)
| Window | Where | Effect |
|---|---|---|
| `slice(-12)` | `inquiry_intake/slots.ts:121` (reply voice) | The reply writer cannot see turn 2 after turn 14. It is fed the code's draft, so it cannot invent, but it can repeat a resolved question or contradict an early preference. |
| `slice(0,4000)` | `_shared/reasoned_decisions.ts:69,89` | Trade and exact-spec reasoning see only the **start** of a long chat. Late answers are invisible to them. |
| `slice(-6)` | `_shared/reasoned_channels.ts:97` (WhatsApp intent) | Intent can be misread when the topic was set more than 3 exchanges earlier. |
| `slice(-8)` | `supplier_onboard/index.ts:159` | Dormant, no impact today. |
| `SUMMARY_AFTER=6` | `conversation_plan.ts:244` | The portal chat is forced to summarise after 6 replies. |
| `MAX_OPEN_TURNS=3` | `slots.ts:49` | The intake is held after 3 unanswered asks of one key. |
| `kbFor(text)` | `handle.ts:163` | Knowledge is retrieved for the latest message only. |

---

## 2. Measured and dry-run evidence

### 2.1 The founder's example, on the portal state machine
Local Deno run of `planState` and `tradeOf` from `conversation_plan.ts` (script at the scratchpad path `probe/plan_probe.ts`).

| Message | Plan | Mode |
|---|---|---|
| EN: "I have a small customised MDF wall partition, thinking to cover it with PVC panel or a wrap sticker" | **null** | none |
| EN variant with "vinyl wrap or PVC wall panels" | **flooring** (wrong: "vinyl" is a flooring trade word, `conversation_trade.ts:47`) | ask |
| Egyptian: "عندي بارتشن خشب MDF ... بفكر اكسيه بديكور PVC ولا استيكر، تنصحني بايه؟" | **null** | none |
| Lebanese: "عندي قاطع MDF زغير ... عم فكّر لبّسو ألواح PVC أو ستيكر، شو بتنصحني؟" | **null** | none |
| Gulf: "عندي قاطع خشب MDF صغير ... ابي البسه بديكور PVC او ستيكر" | **null** | none |

**The founder's own example gets no plan in any language.** No playbook covers wall panels, cladding or film wrap, so the agent falls back to the generic rules.

### 2.2 Dialect probe of the code's detectors (`probe/dialect_probe.ts`)

**Trade detection:**

| Dialect | Message | Plan |
|---|---|---|
| Egyptian | "عايز ادهن الشقة" | **null** |
| Lebanese | "بدي دهّن البيت" | **null** |
| Gulf | "ابي اصبغ الفيلا" | painting |
| All three | AC not cooling | hvac |
| Egyptian | "محتاج مطبخ" | kitchens |

**"Don't know" detection (UNSURE):**
- Recognised: "ما ادري", "مش متأكد".
- **Not recognised:** "مش عارف", "معرفش", "ما بعرف", "مدري" (Gulf), "انت شايف ايه".

So a customer who says "I don't know" in Egyptian or Lebanese Arabic is not moved to "to confirm" and can be asked the same thing again.

### 2.3 40-turn memory, portal state machine (synthetic)
- Turn 3: "Interior, walls 3 m high, Mirdif, Dubai, Budget AED 15k". Then 36 filler turns.
- At turn 40 the state still holds property, size, location, scope and budget, because it is rebuilt from the whole transcript. **Recall of state is fine.**
- The mode is `summary`, because seatTurns 19 >= 6. The plan stops asking after 6 replies.

### 2.4 Production measurements (read-only SQL)
- **Intake.** 18 rows, 2026-09-14 to 2026-11-10. 14 consumed (all the same aluminium replay, 6 turns each), 3 needs_info, 1 ready.
  - Stamped turns: 42. Dropped details: **0**. Keys asked 2+ times: 1 ("element", twice). Exhausted keys: 0.
  - There is no organic traffic to judge.
- **Portal and widget.** 60 conversations, 276 rows.
  - Median 4 turns, maximum 12, **0 at 30 or more**.
  - 7 reached a summary; **0 confirmed**.
  - Verbatim re-asks: 2 conversations, 3 extra asks.
  - Slot-level re-asks (SQL below): size asked after a measurement was given, 5 times in 3 conversations. These may be a different object, so they are candidates, not proven defects.
  - budget, location and timing: 0.
- **sales_decision_log.** 254 assist rows (9 Sep to 27 Oct): 84 answered, 170 refused, 1.1 citations on average. This is retrieval gating, not conversation quality.
- **100-message limit.** Grep for MAX_TURNS, message_limit or 100-per-inquiry finds **nothing**.

### 2.5 SQL to detect a re-asked spec (reusable; run read-only)

**Intake** (structured, exact). A key the row already held is listed as missing again, or a filled key disappears:
```sql
with t as (
  select i.id, o.ord, o.t from inquiry_intake i,
       jsonb_array_elements(coalesce(i.turns,'[]')) with ordinality o(t, ord)
  where o.t->>'role'='assistant' and o.t ? 'slots'),
k as (select id, ord, key from t, jsonb_object_keys(coalesce(t->'slots'->'details','{}'::jsonb)) key),
reasked as (   -- held at turn a, missing again at a later turn b
  select a.id, a.key, a.ord held_at, b.ord reasked_at from k a join t b on b.id=a.id and b.ord>a.ord
  where (b.t->'slots'->'missing_keys') ? a.key),
dropped as (
  select a.id, a.key, a.ord held_at, min(b.ord) gone_at from k a join t b on b.id=a.id and b.ord>a.ord
  where not ((b.t->'slots'->'details') ? a.key) group by 1,2,3)
select 'reasked' kind, * from reasked union all select 'dropped', id, key, held_at, gone_at from dropped;
```

**Portal, widget and WhatsApp** (text). The seat asks a slot after an earlier customer turn filled it:
```sql
with t as (select id, conv_id, message, reply from assistant_logs where conv_id is not null),
slots(slot, fill_re, ask_re) as (values
 ('size','\d+(\.\d+)?\s*(mm|cm|m|sqm|m2|ft)\b|\d+\s*(x|by|×)\s*\d+|متر|سم','\m(size|dimensions?|width|height|how (big|large|wide|tall))\M|مقاس|قياس|ابعاد|مساحة|عرض|ارتفاع'),
 ('location','\m(dubai|abu dhabi|sharjah|ajman|marina|jvc|jlt|mirdif)\M|دبي|ابوظبي|الشارقة|عجمان','\m(which|what) (emirate|area|location)\M|\mwhere is\M|اي امارة|وين|أين'),
 ('budget','\mbudget\M|\maed\s?\d|\d[\d,]*\s?(k|aed)\M|ميزانية|درهم','\mbudget\M|price range|ميزانية'),
 ('timing','\m(asap|urgent|next week|within)\M|\d+\s*(days?|weeks?|months?)|اسبوع|شهر','\m(when|timeline|by when|how soon)\M|متى|موعد')),
asks as (select t.conv_id, t.id ask_id, s.slot from t join slots s on t.reply ~* ('('||s.ask_re||')[^.?!؟]*[?؟]'))
select a.*, (select min(u.id) from t u join slots s2 on s2.slot=a.slot
             where u.conv_id=a.conv_id and u.id<a.ask_id and u.message ~* s2.fill_re) filled_at
from asks a where exists (select 1 from t u join slots s2 on s2.slot=a.slot
             where u.conv_id=a.conv_id and u.id<a.ask_id and u.message ~* s2.fill_re);
```
This text version is a screen, not a verdict. The durable fix is the structured inquiry state in G2, which makes re-asks a plain key comparison.

---

## 3. How B is actually built

### 3.1 Reading the documents
- **Uploads.** `supplier_api/actions/documents.ts` -> `_shared/supplier_doc_trades.ts` (READER `supplier_doc_trades@3`).
  - Every licence, profile and catalogue is read by code first (`_shared/doc_read`: PDF text layer, Office, zip, CAD).
  - A scan with no text is marked `needs_ocr` or read by the browser's tesseract OCR (`ocr_text`).
  - A scanned profile can be read by a model (`_shared/licence_extract.ts:94 SYS_PROFILE` -> summary, services, products, sectors, lines).
- **Licence fields.**
  - Read by code (`_shared/document_expiry/licence_fields.ts:51`, the activities labels).
  - Read by model for scans (`licence_extract.ts:12 SYS_LICENSE`: activities exactly as printed).
  - Only the **activities line** proposes trades (`supplier_doc_trades.ts:183-194`).
- **What gets proposed.** Trades, never services (`trade_resolve.ts TradeHit`: via exact_code, exact_name, meaning or model_choice, with the snippet as evidence).
  - Stored in `supplier_capabilities.proposed_trades` plus `source_docs.docs[].trades`.
  - "Meaning" = gte-small (English) or e5 multilingual (Arabic) vectors of each line against the stored service vectors. Floor 0.82 for English, 0.83 for Arabic (`service_meaning.ts:63,68`), and the service's head word must appear in the line.
- **"Understands what the company does."** For scans there is a model summary. ServicesTab shows the profile's lines and the **trade names** as keywords (`src/components/portal/supplier/ServicesTab.tsx:221-230`).
- **Licence vs profile cross-check.** **None.** Grep for any comparison of licensed activities with profile services finds nothing. The licence gate (`supplier_api/save_profile`) checks only that the licence is readable and in date.

### 3.2 Confirming keywords and services
- **ServicesTab.**
  - The checklist of prepared trades (source confirmed, on_file, documents or refine) lists every service of each trade **unticked** (`_shared/supplier_services.ts:147-164`).
  - Adding a service is typed or spoken text -> `services_rewrite`:
    - exact name or alias (`service_rewrite.ts:198 exactService`), else
    - meaning (`proposeByMeaning`), else
    - kept as the supplier's own words, which become a `taxonomy_trade_proposal` for the sales engineer.
  - The save goes through `capabilityConfirm` into `supplier_capabilities.trades/services/confirmed_at` and the `supplier_capability_confirmation` ledger.
- **Production.** 8 confirmations; 5 confirmed rows (aluminium 4, gypsum 1, painting 1). 14,737 rows carry directory-derived services such as `{installation}` (`derived_from_directory_v1`). `proposed_trades` is never populated (0). `taxonomy_trade_proposal` has 0 rows.

### 3.3 Matching
`public.fn_match_capability` (STABLE, SQL; definition read from production):
- **Candidate gates:**
  - `confirmed_at is not null`
  - `sc.trades && p_trades` (exact array overlap of trade codes)
  - not an excluded trade
  - fn_is_matchable
  - available
  - role fits the need
  - authority approvals
  - value band
  - emirate
- **Service gate.** When the inquiry names services, the supplier must hit one of them in `fn_services_effective` (stated + **one level** of `service_implication`, 113 curated rows, minus removed). If the supplier holds none of the named trades' services, it passes at trade level.
- **Ranking.** Weights are 40 products, 20 brand, 15 project type, 15 track and 10 size. The products and brands terms are **exact equality** ("A substring is not a match").
- **Inquiry side.** `_shared/service_vocabulary.ts:113 serviceKeysOf` reads the brief exactly or by meaning, **all or nothing**: an incomplete read means no service gate. Trades come from the intake slug, then `fn_taxonomy_trades_for` (exact; `sales_engineer/actions/operator.ts:174`), with a `fn_norm_trades` fallback.
- **Matching technique.**
  - Synonyms: only through curated `aliases` and **exact whole-phrase** equality.
  - Taxonomy: two layers (56 intake slugs in `category_specs`, 1,047 services in `taxonomy_trade_service`). 39 of the 56 slugs are not taxonomy codes and are bridged by `fn_taxonomy_trades_for`.
  - Embeddings: used only to **turn text into codes** (both sides), never at match time.
- **Bug found.** The intake's supplier count calls `fn_match_capability` with the **raw intake slugs** (`inquiry_intake/handle.ts:806`), without `fn_taxonomy_trades_for`. For 39 of 56 trades (e.g. `fitout`, `carpentry-joinery`, `glass`) the count shown on the summary card is 0 even when dispatch would find suppliers.

### 3.4 Dry-run: would a "PVC decorative panels" supplier reach "PVC wall panels for an MDF partition"?
- **Supplier side** (`rewriteServices`/`exactService`, Deno, live alias rows; `probe/svc_probe.ts`):
  - "PVC decorative panels" -> **unmatched** (alias is "decorative panel"; exact match only).
  - "Supply and installation of PVC decorative panels, WPC panels and vinyl wrap" -> three **unmatched** phrases.
  - Only the bare "decorative panel" -> `wallpaper.wall_panels`.
  - Meaning would *probably* rescue "PVC decorative panels" (the head word "panels" agrees with "Wall panels"), but that needs an embedding call, not run here.
- **Inquiry side** (`serviceKeysOf` with exact vocabulary and no embedder):
  - "PVC wall panels for an MDF partition" -> keys [] (`embedding_unavailable`): **no exact hit**, so it depends on meaning.
  - The founder's full sentence -> same.
  - Risk: "a wrap sticker" can land on `packaging.labels` (alias "sticker"), and "vinyl" on flooring.
- **Trade side.** `fn_norm_trades` on both texts -> **null** (no trade code named). The trade depends on the intake model picking a slug. `wallpaper` resolves to `wallpaper`, but `carpentry-joinery` (to `carpentry_joinery, joinery`) or `fitout` (to `fitout, interior_fitout`) would not overlap a supplier filed under `wallpaper`.
- **Matcher, live, read-only:**
  - `fn_match_capability(['wallpaper'], ..., services ['wallpaper.wall_panels'])` = **0**.
  - Trade only = 0. Joinery codes = 0. Fitout codes = 0. Control `['aluminium']` = 4.
  - Counterfactual without the confirmation gate: 259 suppliers carry trade `wallpaper`, 0 state `wall_panels`, 0 matchable unconfirmed.
- **Verdict.** In design, the chain *can* work only when all of these hold:
  - the intake model picks `wallpaper`;
  - meaning maps both phrasings to `wallpaper.wall_panels`;
  - the supplier confirmed trade `wallpaper` with that service ticked.

  Every link is fragile. Today it returns 0. An interior-decoration company (`interior_fitout.decoration` implies `wallpaper.wall_panels`) is still excluded by the trade gate when the inquiry's trade is `wallpaper`.

---

## 4. Verdicts with evidence

### A1 Expert reasoning: NOT MET
- The intake prompt explicitly forbids it: "Do not pitch", "only job is to collect a complete, accurate brief", "do NOT lecture" (`handle.ts:283, 301`), with 1-2 sentence replies.
- The portal rule corrects wrong specs and recommends only when the customer is unsure. It never says "assess the condition and propose suitable options". No playbook covers panels, cladding or film wrap (`knowledge/brief/conversation/*.md`), and the founder's example gets no plan (2.1).
- Customer-facing knowledge on film or vinyl wrap: kb_chunks has 1 non-generated row. The 10 generated rows are withheld (ruling 1338).
- `line_specs` (the material, thickness and finish attributes per trade) is used only after quotes arrive (`sales_engineer/lib/spec_offer.ts`), never in the conversation.

### A2 Until complete: PARTLY
- Intake: completeness is derived from `category_specs` required keys (structured, good), but a key is held after 3 asks (`slots.ts:49`).
- Portal: forced summary after 6 replies (`conversation_plan.ts:244`), and its summary is **not carried into the request** (`Dashboard.tsx:345`), so the customer retells everything in New request.
- Production: 7 summaries reached, 0 confirmed.

### A3 Dialects: PARTLY
- Understanding is delegated to Sonnet 5.5, which plausibly copes, but this is unmeasured.
- The code detectors that steer the portal (TRADE_WORDS, CATALOGUE, UNSURE, ASKS) miss common Egyptian and Lebanese forms (2.2). ASKS has بدي (Levantine) but not عايز/عاوز (Egyptian).
- Replies are fixed to "formal Gulf Arabic" (widget, WhatsApp) or plain "Arabic" (intake). Reply language follows `customers.locale` on the intake, not the customer's message.

### A4 100-message limit: NOT MET
No cap exists per inquiry or per conversation. The only limits are 60 intake turns per hour per email (`handle.ts:45`) and SUMMARY_AFTER=6 replies.

### A5 Turn 2 remembered at turn 30+: PARTLY
- **Good:**
  - The whole transcript is stored (inquiry_intake.turns, assistant_logs by conv_id, wa_messages).
  - The extraction call sees the whole intake transcript.
  - The portal state is rebuilt from the whole transcript (2.3).
  - Intake slots persist on the row.
- **Gaps:**
  - The intake reply voice sees the last 12 turns only.
  - The reasoned trade and exact-spec reads see the first 4,000 characters only.
  - Knowledge is retrieved per latest message.
  - Non-checklist facts ("small", "customised", "MDF", "thinking PVC or wrap") have no structured home on either surface.
  - The portal state is regex-built, so facts stated in dialect or unusual wording are not "held".
  - **Nothing in production has ever run past 12 turns.**

### A6 Cheaper model: NOT MET / unproven
All three surfaces use Sonnet 5.5, with gpt-6-luna-pro behind it. No eval compares tiers.

### B1 Read profile and licence: PARTLY
Built (3.1), but in production 0 documents have been read and 0 trades proposed. The model reads only scans; every other document is read by code alone.

### B2 Licence vs profile check: NOT MET
No routine or code path compares them.

### B3 Propose keywords to tick or add: PARTLY
- Trades are proposed with evidence lines.
- Services appear as an unticked checklist per proposed trade.
- The supplier's specific phrases from the profile (e.g. "PVC decorative panels") are **not** offered as service keywords. Only trade names are shown as keywords (`ServicesTab.tsx:225`).
- Typed or spoken additions work (rewrite), and unmatched words go to a proposal queue (0 rows).

### B4 Keywords drive matching: PARTLY
- The design is sound (confirmed services gate dispatch, exact plus one-level implications).
- Synonym coverage is thin and exact: "PVC decorative panels" fails exact.
- No embeddings at match time.
- The trade gate is exact, so an adjacent trade (fitout or joinery vs wallpaper) excludes capable suppliers.
- The intake supplier count passes un-normalised slugs (bug, 3.3).
- Live result for the founder's example: 0.

---

## 5. Gaps ranked by customer impact, each with a redesign

### G1 The assistant chat does not hand over to the request (customer retells everything) — impact: critical
- **Flow.** Merge the two surfaces. The portal chat *is* the intake.
  - When the plan is confirmed, `sales_engineer` creates the `inquiry_intake` row itself, pre-filled from the conversation state: brief.details under canonical keys, req_answers, the transcript as `turns` or a `source_conv_id`.
  - "New request" opens that row at its summary, not a blank chat.
- **Data.** `inquiry_intake.source_conv_id text`, plus `inquiry_state.intake_id`.
- **Tier.** No model needed; it is a state copy.

### G2 No durable structured inquiry state shared by every surface — impact: critical (the root of A2, A5 and the re-asks)
- **Data model.** New table `inquiry_state`, keyed by the conversation:

  | Column | Holds |
  |---|---|
  | conv_id pk | the conversation key |
  | intake_id | the request row, once created |
  | trade_codes text[] | taxonomy codes, not intake slugs |
  | service_keys text[] | the services named |
  | facts jsonb | key -> {value, said_in_turn, quote, status: stated, inferred, changed, to_confirm} |
  | condition jsonb | the existing object: material, size, state |
  | options_offered jsonb | the solutions proposed and the customer's reaction |
  | budget jsonb | |
  | open_questions jsonb | |
  | asked jsonb | key -> [turn numbers] |
  | message_count int | |
  | updated_at | |

  - It is written each turn by a **small extraction call** (json_extraction tier, cheap: gpt-6-luna-pro or a flash model) that reads *the latest exchange plus the current state* and returns a JSON patch. It does not re-read the whole history.
  - Code merges the patch: a change records `changed_from`, and nothing is deleted.
  - Facts outside the checklist (MDF, small, customised, PVC-or-wrap) get a home under `facts.free`.
- **Flow.** Every surface (portal, widget, WhatsApp, intake) reads and writes this one state. A re-ask then becomes a plain key comparison (`asked[k]` exists and `facts[k].status='stated'`), enforced in code before the reply goes out.
- **Why.** It removes the dependence on regex detectors and on history windows, and makes "message 2 at message 30" a guaranteed property of the data rather than of the prompt.

### G3 No expert solutioning — impact: high (the founder's headline ask)
- **Flow.** Each customer turn becomes three steps.
  1. **Diagnose:** the state patch above adds `condition` (substrate, location, use, moisture, wear) and `intent`.
  2. **Advise:** the reply model gets a "SOLUTION OPTIONS" block, built per trade from a curated **solution catalogue**. It offers 2-3 concrete options with one-line trade-offs (cost band, durability, moisture, look) and recommends one with the reason.
  3. **Qualify:** ask the next price-driving spec, then budget band, then size, then location and timing.
- **Example for MDF partition cladding:**
  - PVC/WPC panels: moisture-proof, fast, a mid-price band; on MDF, check the fixing.
  - Architectural vinyl film / wrap (3M DI-NOC type): thin and cheap, but needs a smooth, sealed MDF surface and edges, and is less durable under impact.
  - Laminate or HPL sheet: most durable.
  - Then ask the partition size (w x h, one or both faces), whether it is a wet area, and the budget band.
- **Data.**
  - `solution_catalogue(trade_code, condition_tags[], option_code, label_en, label_ar, pros, cons, price_band, prerequisites, maps_to_service_key)`.
  - Seed it from the playbooks and from read sources. The generated KB rows are withheld under ruling 1338, so the catalogue must be authored or source-read.
  - `maps_to_service_key` ties advice to matching: if the customer picks "PVC panels", `service_keys += wallpaper.wall_panels`.
- **Prompt.** Lift "Do not pitch / do not lecture" for *options*, keeping the bans on prices and supplier promises. Allow up to 4 sentences when advising.
- **Playbooks.** Add "Wall panels, cladding and film wrap" (wallpaper.wall_panels, wall_cladding, joinery.wood_panelling, doors.window_film) with must-haves: surface, size, faces, wet area, finish/look, budget, location, timing.
- **Tier.** Reply on mid tier (Sonnet 5.5 today). Run the eval to see whether gpt-6-luna-pro or a flash model holds quality on the advising turn (A6).

### G4 History windows and truncations — impact: high for long chats
| Change | Detail |
|---|---|
| `slots.ts:121` | `slice(-12)` -> `fitHistory(conversation)` (prompt-cached history, as ai_reply already does), plus the G2 state block. |
| `reasoned_decisions.ts:69,89` | `slice(0,4000)` -> state facts plus the last N turns, or `fitHistory`. Never the first 4,000 characters. |
| `reasoned_channels.ts:97` | Pass the G2 state summary instead of the last 6 turns. |
| `handle.ts:163` | kb retrieval query = current message + state.condition + trade, not the message alone. Also run it on turn 1 once the model names the trade. |
| `handle.ts:900` | `raw_input` stops truncating at 4,000 characters, or store a `raw_input_full`. |

### G5 No 100-message cap — impact: medium (cost and abuse control, and a founder requirement)
- **Data.** `inquiry_state.message_count`, incremented atomically in one place (a `fn_inquiry_turn_count(conv_id)` RPC); applies to both customer and seat messages.
- **Flow:**
  - At 80: the reply starts converging (summary plus the remaining must-haves).
  - At 95: summary and confirm.
  - At 100: the request is held, an inquiry is created from the state with open items "to confirm at site visit", a sales_engineer handoff is opened (`fn_seat_handoff`), and the customer is told.
- **Retune.** SUMMARY_AFTER=6 and MAX_OPEN_TURNS=3 to sit under this budget: summary when the must-haves are done, not after 6 replies. MAX_OPEN_TURNS stays as a per-key rule.

### G6 Dialect handling — impact: medium-high for the UAE market
- **Detectors.** Stop depending on regex detectors for meaning. With G2, slot filling is the extraction model's job, so detectors become a cheap first pass only.
- **Dialect field.** Add `dialect` (msa, gulf, egyptian, levantine, english, mixed) to the state patch, detected by the extraction call.
- **Reply rule.** Replace "formal Gulf Arabic" with "reply in clear Modern Standard Arabic, mirroring the customer's key dialect terms when they aid clarity, with no slang of our own" (or mirror the dialect, if the founder prefers).
- **Interim patch** (if detectors stay):
  - Egyptian and Levantine forms in UNSURE: مش عارف, معرفش, ما بعرف, مدري, ماني متأكد, شايف ايه, شو رأيك.
  - ASKS: عايز, عاوز, بدّي, حابب.
  - TRADE_WORDS: ادهن/دهن, بارتشن/قاطع, ستيكر/ورق لاصق, PVC/WPC panel, wall panel, cladding, wrap/film.
  - Move "vinyl" out of the bare flooring pattern.
- **Language.** On the intake, follow the conversation's language (turnLang, as the portal does), not `customers.locale`.

### G7 Matching too exact for real wording — impact: high for supply-side reach
| Change | Detail |
|---|---|
| Synonyms and aliases | Grow `taxonomy_trade_service.aliases` for the panel family: "pvc panel(s)", "pvc wall panel(s)", "pvc decorative panel(s)", "wpc wall panel(s)", "fluted panel(s)", "ألواح PVC", "بانوهات PVC", "ديكور PVC". New service `wallpaper.film_wrap` (or `interior_fitout.film_wrap`): "vinyl wrap", "architectural film", "wrap sticker", "ستيكر خشب", "تغليف حراري". Plurals are handled by normalising (singularise) in `exactName`, so "decorative panels" equals "decorative panel". |
| Trade gate | Widen by **adjacency, not similarity**: `taxonomy_trade_adjacent(from_code, to_code, why)`, curated (wallpaper <-> interior_fitout, joinery). `fn_match_capability` takes `p_trades` plus adjacent trades when `p_services` is set, and the service gate still keeps precision. This is how an interior decorator with implied `wall_panels` gets reached. |
| Embeddings at match time | Optional, behind a decision_policy flag, as a ranking **signal** only (never a gate, which keeps ruling 890 and "exact or no match" intact): cosine between `inquiry.service_keys` labels and a supplier's confirmed service labels, for the ordering inside the gated set. |
| Bug | `inquiry_intake/handle.ts:806` passes `fn_taxonomy_trades_for(trades)` before `fn_match_capability`. |
| Advice -> service keys | G3's `maps_to_service_key` makes the customer's chosen option name the exact service, so matching no longer depends on reading prose by meaning. |

### G8 Supplier onboarding: no licence-vs-profile check; profile phrases not proposed as services — impact: medium
- **Flow** (`supplier_doc_trades` + `supplier_services`):
  1. **Licence activities** -> trade codes (exists). Store the activities verbatim in `supplier_capabilities.licence_activities text[]`, plus `licence_trades text[]`.
  2. **Profile lines** -> service keys by exact or meaning. Store these as **`proposed_services text[]`** with evidence, not only trades.
  3. **Cross-check** (new pure function `licenceCovers(licence_trades, proposed_trades)` plus a reasoned check for activity wording). Each proposed trade or service is marked `licensed`, `not_on_licence` or `unclear`. The ServicesTab shows "Your licence lists: ..."; anything not on the licence is shown unticked with "not on your trade licence, upload the licence that covers it". It is stored in `source_docs.licence_check`.
  4. **ServicesTab** shows the proposed services **pre-ticked with their evidence lines**. The founder's phrase "proposes extracted keywords/services the supplier ticks" implies that pre-ticks are proposals; they become the supplier's only on confirm. The current "start unticked" rule should be put to the founder.
  5. The supplier's own unmatched words become `taxonomy_trade_proposal`, plus an alias proposal for the sales engineer to approve. That closes the loop for "PVC decorative panels".
- **Revive or delete** the dormant `supplier_onboard` (which has `slice(-8)`). The ServicesTab path is the live one.
- **Tier.**
  - Licence and profile reading stay code-first; the model is for scans only (json_extraction tier).
  - The activities-vs-profile reasoning is a small mid-tier `think()` decision with the lines as evidence.

### G9 The intake knowledge withheld and blind on turn 1 — impact: medium
Covered by G3 and G4. In addition, author customer-facing trade knowledge for the gaps (film wrap, PVC/WPC panels on MDF, wet-area rules), since the generated rows stay withheld.

---

## 6. What must be proved with a small real-AI eval (later; costs money; not run here)

**Harness.** Extend `scripts/e2e/adaptive_conversation_bank.mjs`: scripted customers driven by a model persona, ZZ DEMO and @example.invalid subjects. Judge each transcript and the final state by rubric.

**Scenarios (each in EN plus Egyptian, Lebanese and Gulf Arabic, and one Arabizi or mixed-script variant):**
1. **MDF partition, PVC panel or wrap.** Must diagnose the surface and edges, offer at least 2 suitable options with trade-offs, recommend one, ask size, faces, wet area and budget band, and map the choice to `wallpaper.wall_panels` or `film_wrap`.
2. **Bathroom leak in an old villa** (waterproofing vs plumbing). Must ask the leak source and propose inspection or a fix route.
3. **Majlis sofa re-upholstery vs new.** Must advise on condition and ask sizes, fabric and budget.
4. **A wrong spec** (6 mm annealed glass for a shower). Must correct it in the first reply and never again.
5. **"I don't know" in dialect** (مش عارف / ما بعرف / مدري). Must recommend and move on, never re-ask.
6. **Change of mind** (PVC at turn 3, film at turn 9). The summary shows only film, with the change noted.

**40-turn memory test.**
- Turn 2 states: dimensions 2.4 x 1.2 m, one face, the location, "budget about 3,000 AED", and "no strong smell, kids' room". Turns 3-38 are distractors: platform questions, a second topic, small talk, a photo.
- At turns 30, 35 and 40 probe: "what size did I say?", "remind me my budget", and the summary.
- **Pass:** every turn-2 fact is correct in the state *and* the reply, 0 re-asks of a stated key across all 40 turns, and no contradiction of the turn-2 constraint (the low-odour product recommended).
- Run on both surfaces (portal chat and request chat) and on WhatsApp.

**Cap test.** Push to 100 messages. Must converge from 80, summarise at 95, hold and hand off at 100, and never send message 101.

**Model-tier A/B (A6).** Run the same bank on Sonnet 5.5, gpt-6-luna-pro and a flash-tier reply model, with the cheap json_extraction tier fixed for the state patch. Report the judge score, re-ask rate, dialect comprehension, cost per conversation and latency p95. Switch only where quality holds within an agreed margin.

**Supplier and matching eval.**
- Five real-style profile and licence pairs (text PDFs plus one scan), including one whose profile claims a trade the licence lacks.
- **Pass:**
  - proposed services include the profile's specific lines (PVC decorative panels -> wall_panels);
  - the licence check flags the mismatch;
  - after confirmation, the MDF/PVC inquiry from scenario 1 matches the PVC-panel supplier through `fn_match_capability` and excludes the packaging-labels supplier;
  - an interior-decoration supplier is reached through adjacency and implication.

**Metrics to log per conversation into `inquiry_state`:** message_count, asked keys and re-ask count, facts by status, options_offered, dialect, completion (confirmed -> inquiry created), and time to complete.

---

## 7. Evidence index (paths)
- **Conversation:**
  - `supabase/functions/inquiry_intake/handle.ts` (lines 45, 73, 109, 163, 276, 283, 301, 307, 369, 576, 806, 900)
  - `supabase/functions/inquiry_intake/slots.ts` (49, 113-129, 193-262, 288, 323)
  - `supabase/functions/inquiry_intake/knowledge.ts`
  - `supabase/functions/_shared/reasoned_decisions.ts` (69, 89-90)
  - `supabase/functions/_shared/chat_history.ts`
  - `supabase/functions/_shared/ai_reply.ts` (229-238)
  - `supabase/functions/sales_engineer/actions/portal.ts` (86-176)
  - `supabase/functions/sales_engineer/conversation_plan.ts` (78-150, 198, 235, 244, 284-374, 408-459)
  - `supabase/functions/sales_engineer/portal_conversation.ts`
  - `supabase/functions/_shared/conversation_trade.ts` (32-91)
  - `supabase/functions/_shared/reasoned_channels.ts:97`
  - `supabase/functions/_shared/wa_history.ts`
  - `supabase/functions/wa_inbound/model_says.ts:136`
  - `supabase/functions/site_assistant/index.ts` (247, 403, 412)
  - `src/components/me/NewRequest.tsx`
  - `src/components/me/dashboard/Dashboard.tsx:345`
  - `knowledge/brief/conversation/*.md`
- **Onboarding and matching:**
  - `supabase/functions/supplier_onboard/index.ts` (dormant; 159)
  - `supabase/functions/_shared/licence_extract.ts` (12, 94)
  - `supabase/functions/_shared/supplier_doc_trades.ts`
  - `supabase/functions/_shared/trade_resolve.ts`
  - `supabase/functions/_shared/service_meaning.ts` (63, 68)
  - `supabase/functions/_shared/service_rewrite.ts` (117, 198, 217)
  - `supabase/functions/_shared/service_vocabulary.ts` (113)
  - `supabase/functions/_shared/supplier_services.ts`
  - `supabase/functions/sales_engineer/actions/operator.ts` (158-176, 270-290)
  - `src/components/portal/supplier/ServicesTab.tsx` (221-230)
  - Production routines: `public.fn_match_capability`, `fn_services_effective`, `fn_taxonomy_trades_for`, `fn_norm_trades`
  - Production tables: `taxonomy_trade_service`, `service_implication`, `supplier_capabilities`
- **Dry-run scripts** (scratchpad): `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/probe/plan_probe.ts`, `dialect_probe.ts`, `svc_probe.ts`, `vocab.json`
