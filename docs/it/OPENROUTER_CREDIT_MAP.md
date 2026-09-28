# What will consume OpenRouter credit when the hold lifts

Seat: it_engineer. Founder ledger item 704. Measured 28 Sep 2026 (18:50 UTC) against production, read-only;
the model hold was on throughout and was not touched.

## How it was measured

- **Call sites:** every edge function importing `_shared/llm.ts`, calling `ai_gateway` directly, or reasoning through
  `_shared/think.ts` (`defaultDeps`), which reaches the gateway through `llm.ts`.
- **Triggers:** `pg_cron` holds one inactive job (`wa_flush`) and has run nothing since 7 Sep. The scheduled work runs
  from `resilience_ping`, about 97 ticks a day (agent_runs, 24 h), and its `seat_duty` table (42 duties).
  `replayHeld` replays 3 queued reasoning questions per tick.
- **Demand:** there are two kinds.
  - Demand that reaches the gateway is logged under the hold as `ai_cost_log` rows with `model_used='none'`, marked
    `HELD` or `FIXTURE`.
  - Demand that `think()` stops before the gateway is visible only as rows in `reasoning_held_question`, for the
    surfaces that queue. For request-time reasoning, the rate comes from the inbound volumes: `wa_messages`,
    `inbound_messages` and `assistant_logs`.
- **Prices:** from `model_rate` and `model_policy`.
  - `openai/gpt-5.6-sol`: USD 2 in / 10 out per million tokens. It serves every customer, supplier and Arabic class,
    `knowledge_validation` (the verify step) and seat deliberation.
  - `z-ai/glm-5.3-flash`: USD 0.15 in / 0.50 out per million tokens. It serves `routine_employee_reasoning`: plan, research
    and internal answers.
- **Unit costs, assumed:** a planning or internal call is 1.5–4k tokens in and 0.4–0.5k out. A sol answer is 4k in
  and 0.5k out. A sol verify is 4k in and 0.2k out.
  - An internal `think()` costs about USD 0.0013.
  - An internal `think()` with high stakes adds a sol verify and costs about USD 0.011.
  - A customer-facing `think()` costs about USD 0.013, or about USD 0.023 when it is verified.

## The table

At today's idle volume, measured over 24–28 Sep, with the fixes in this PR:

| # | Class | Call site | Trigger and frequency | Tier | Calls/day | USD/day |
|---|---|---|---|---|---|---|
| 1 | Supply gap: "recruit or defer" a trade nobody is waiting on | SQL `fn_sales_engineer_supply_gap` → `fn_seat_duty_reason` (stakes high) → `replayHeld` | duty `sales_engineer.supply_gap`, daily, at most 10 trades a day | GLM plan and decide, sol verify, and a sol cross-family review on "recruit" | 10 reasonings, about 35 calls | **0.24** |
| 2 | Postmortem of each incident | SQL `fn_it_engineer_postmortem` → `replayHeld` | duty `it_engineer.postmortem`, hourly: 10.5/day measured (one per incident id) | GLM (sol verify only when the plan marks it high stakes) | about 21–30 | 0.02–0.12 |
| 3 | Knowledge refresh, exam and distil for 6 seats | SQL knowledge duties, `learning_loop.ts` → `replayHeld` | weekly per seat, about 1.5/day | GLM plus sol verify | about 5 | 0.02 |
| 4 | Competitor page change | `fn_competitor_scan_ingest` → `replayHeld` | hourly scan; files only on a changed page (31 first reads on 24 Sep, since then 0/day) | GLM | 0–1 | ≤0.01 |
| 5 | WhatsApp reply | `wa_inbound`: needs-a-person decision, menu meaning, `supportReply` (781) | per inbound message, 3.6/day | sol answer, GLM plan | about 11 reasonings | 0.16 |
| 6 | E-mail reply | `email_triage`: GLM classify, needs-a-person decision, `think()` with high stakes | per inbound mail, 2.4/day | GLM, sol, sol verify | about 12 | 0.09 |
| 7 | Website widget and portal chat | `site_assistant`, `sales_engineer` assist (`supportReply`, price guidance) | per visitor message, 0.3/day | sol | about 2 | 0.01 |
| 8 | Direct gateway callers | `quote_compare`, `inquiry_intake`, `drawing_boq`, `drawing_redact`, extractors, `ceo_agent`, `marketing` | per real request | sol | **0 real** since 23 Sep (the 75/day "held" `quote_compare` rows stopped on 22 Sep; everything since is `FIXTURE`) | 0.00 |
| 9 | Our own test traffic (nightly journey, post-deploy smokes) | `think()` callers and `llm.ts` callers (listed below) | every deploy and every night; 6.5/day fixture `line_specs.assess` rows measured | sol | 0 after this PR | **0.00** (was about 0.1–0.5) |
| 10 | Embeddings | `ai_gateway {action:'embed'}`, gte-small in-region | most of `fn:ai_gateway`'s 11,330 runs/day | none | – | 0.00 |
| | **Steady idle total** | | | | **about 90–110** | **about 0.55–0.70** |
| 11 | **One-off at the lift**: the held backlog | `replayHeld`, 3 per tick | about 230 real held rows (60 fixture rows expire unrun) | mixed | about 230 reasonings on day one | **about 2.1, once** |

Rows 8 and 9 cover these `llm.ts` and direct callers: `ceo_agent`, `customer_portal`, `drawing_redact`, `email_triage`,
`inquiry_intake`, `marketing/duties`, `resend_inbound`, `quote_compare`, `quote_extract`, `license_extract`,
`doc_extract`, `supplier_api`, `supplier_portal` and `transcribe`. The `think()` users are in the `reasoned_*.ts`
modules, `line_specs/*`, `learning_loop.ts`, `glm_judgements.ts` and the `marketing_*` modules. All of them are
request-driven: at idle their only traffic is ours.

## Flags

- **Fixed in this PR: test traffic would have been paid.**
  - `think()` called the model for a request its caller had marked `subject.fixture`: only the queue skipped it.
  - `llm.ts` never forwarded a subject, so the gateway's fixture check (`fn_ai_subject_is_fixture`) never saw a
    `think()` call or an `llm.ts` call.
  - Now a fixture request is held (`fixture_no_spend`) before any model call, and every `think()` call carries its
    subject to the gateway.
  - Prevented by: `supabase/functions/_shared/think.test.ts` ("704: a fixture never reaches a model…").
- **Not fixed: the one-off backlog of about USD 2.1 on day one.** It goes above USD 1–2 on the day of the lift only;
  it is catch-up, not idle spend.
- **Row 1, the biggest steady class, is cut by rule (in this PR, pending apply at merge).** A trade and area with no
  uninvited lead left cannot be recruited for, so `scripts/sql/a_supply_gap_with_no_leads_left_is_deferred_by_rule.sql`
  defers it in code before any gap is filed for paid reasoning. Only gaps that have leads to recruit still reach the
  model. Prevented by: `scripts/checks/a_supply_gap_with_no_leads_is_never_a_paid_judgement.test.mjs`.
