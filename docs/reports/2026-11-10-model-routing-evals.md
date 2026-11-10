# Model routing evals A and C: results (it_engineer, cost seat; 10 Nov 2026)

Design and criteria: `docs/reports/2026-11-10-design-model-routing.md` section 5c. Ruling 1571. Scripts:
`scripts/eval/model_routing/` (eval_a.ts, eval_c.ts; eval_b.mjs and eval_b_judge.ts written, not run). Raw results:
`docs/reports/model-routing-evals-2026-11-10/`. Every call ran inside its own tagged rehearsal window on production
`htdblwldjkcgjvmqkbeh`, ZZ DEMO parties and the fixture mobile block only; every window is closed (`ended_at` set,
`models_allowed` false).

## Verdicts

| Eval | Gates | Result | Run used |
|---|---|---|---|
| **C**, Qwen 3.8 Flash as reviewer | knowledge_validation + sales_engineer__knowledge_validation > Qwen | **PASS**: 30/30 defects flagged (each kind 6/6), 0/30 clean flagged, 0 unread | `eval_c.json` (qd_run:evalce5fbe293468) |
| **A**, T2 replies and the status lane on Luna Pro | conversation_reply, customer_portal_assistant, visitor_chat > Luna Pro | **PASS** on run 3, re-judged with the supplier how-to | `eval_a_run3_rejudged.json` (replies qd_run:evala2439cf7ec47, judge qd_run:evalad052de34957) |
| B, the interview | inquiry_qualification_conversation | not run (the intake is being rebuilt) | – |

### Eval A, run 3 against the stated criteria

| Criterion | Bar | Luna Pro |
|---|---|---|
| Critical errors (must left out, invented figure, wrong language, identity leak, deferral, wrong status) | 0 | **0** |
| `must` present | 100% | **100%** (40/40) |
| Rewrite rate | ≤ 15% | **12.5%** (5/40) |
| Second-rung rate (the reply came from the other family) | ≤ 5% | **2.5%** (1/40, lv-s1) |
| Reply in the person's language and register | ≥ 95% | **100%** |
| Judge mean | ≥ 8.0 | **8.58** (40 judged) |
| Judge mean against the Sonnet control, same 20 cases | ≥ control − 0.5 | **8.75 vs 8.30** |

The judge was Sonnet 5.5 through the gateway's review router with `counterpart_model` = Luna Pro (never the model under
test), 10 cases a call, each case's replies blind-labelled in random order. The status-lane cases (24) averaged 8.67.
The second-rung rate was first computed as 0% by a definition that missed lv-s1 (route ok, two refused rewrites, then
the other family answered); it is recomputed from the saved run with "the final reply's model is not the arm's model".

## Why three runs of A, and two of C (each a defect found in the build or the harness, not a retry for a better number)

| Run | What it measured | What was wrong | Fixed in |
|---|---|---|---|
| A1 qd_run:evala0a9b8fd97b2 | FAIL: 7 critical, must 97.5%, rewrites 17.5%, judge 7.63 (control 7.45) | (1) the judge saw only a one-line summary of the facts and marked true brief facts ("no cap", "not VAT-registered") invented, on BOTH arms (control: 5 of 20 "critical"); (2) `support_reply_guard` read the request reference "#5202" beside "4 موردين" as OUR supplier count, refused the sentence, and the rewrite then dropped the reference the reply must carry (3 of 12 status turns) | judge gets the company brief (cached); `NOT_A_COUNT` takes references (`support_reply_guard_internal_number.test.ts` fails on the old guard) |
| A2 qd_run:evala2cf02438201 | FAIL on one criterion: 1 critical (lv-s2), everything else passed (rewrites 0%, judge 8.30, paired 8.05 vs 7.85) | Luna Pro told "the comparison report is prepared once the quotes are in" (3 of 3 in) wrote that the report "is ready now": a real error | `STATUS_RULES`: never state a report ready, a request complete, a quote accepted or anything sent unless the facts say so (`status_lane.test.ts`) |
| A3 qd_run:evala2439cf7ec47 | 1 critical (eg-x1 "invented_figure"), every other criterion passed | the figure is real: "One quote can carry up to 20 options" and "Inquiries received" are in `knowledge/brief/supplier_howto.md`, which the supplier reply had and the judge had not; Sonnet's control got the identical flag | the judge also gets the supplier how-to; A3's replies re-judged, no reply asked again (`--rejudge`) |
| A3 re-judge qd_run:evalafb4e4db30a1 | partial: 1 of 4 batches | the window's own cap refused the next 3 batches (the gateway estimated each at the first batch's 36k-token cache write, USD 0.166) | re-judged in a fresh window, qd_run:evalad052de34957: **PASS** |
| C1 qd_run:evalcb15dab8889e | FAIL: 24/30, 4 false, 10 unread | the eval called Qwen with a flat `max_tokens` 600; Qwen reasons inside it and 10 answers came back empty. The gateway never sends that: `request_shape.ts` adds thinking headroom | the eval builds its request with `shapeRequest` |
| C2 qd_run:evalce5fbe293468 | **PASS** 30/30, 0/30 | – | – |

## Cost line (ai_cost_log, the seven run tags, read after the runs)

| Run tag | Calls | USD |
|---|---:|---:|
| evala0a9b8fd97b2 (A1) | 85 | 0.3719 |
| evala2cf02438201 (A2) | 69 | 0.3476 |
| evala2439cf7ec47 (A3) | 77 | 0.3534 |
| evalafb4e4db30a1 (A3 re-judge, partial) | 4 | 0.1113 |
| evalad052de34957 (A3 re-judge) | 4 | 0.1005 |
| evalcb15dab8889e (C1) | 60 | 0.0131 |
| evalce5fbe293468 (C2) | 60 | 0.0129 |
| **Total** | **359** | **1.3107** (cap USD 1.50) |

Before the runs: llm_attempt held 0 HTTP 402s since the 01:40Z top-up (ledger 1568). Each script read the run's tagged
spend before every call and stopped at its cap; each window carried the same cap at the gateway.

## Findings beyond the gates

- **Luna Pro was not worse than Sonnet on any paired measure.** Paired judge means: A2 8.05 vs 7.85, A3 8.75 vs 8.30.
  Both invent unstated details at a similar rate; the figure guard checks money only, not counts or days
  ("3-5 working days" in A1 lv-v1 was not caught by code).
- **Latency**: Luna Pro averaged 16.8 s a reply in A1 against Sonnet's 11.8 s (brief-path replies with reasoning).
- **lv-s1 in every run**: the figure guard refused "a fee of 1" in a Levantine status reply with one quote. The model's
  draft is not stored by aiReply, so the exact sentence is unknown; it is a false positive of `moneyFiguresNotInBrief`
  to be traced with the draft logged.
- **Eval C went to OpenRouter directly**: Qwen 3.8 Flash is not registered until part 1 is applied, so the gateway cannot
  route to it. The key was read in-process from app_secrets and never printed; every call was written to ai_cost_log
  under its run tag with OpenRouter's reported cost. After part 1 and part 2 are applied, `eval_c.ts --via gateway`
  runs the same set through knowledge_validation and refuses to grade unless Qwen answered.
- **Eval A's arms are routes, not model names**: candidate = customer_communication (Luna Pro > Sonnet today), control =
  conversation_reply / visitor_chat (Sonnet > Luna Pro). The run refuses to start unless fn_ai_route says so. The status
  lane in the eval ran on customer_communication, not status_reply (not on production yet): same primary, max_tokens
  900 instead of 300.
