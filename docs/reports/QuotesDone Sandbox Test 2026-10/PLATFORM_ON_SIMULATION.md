# Platform-on simulation, 19 Oct 2026 (QA lead)

**Verdict: FAIL. The platform is NOT perfect.** The full three-person scenario was **not** completed.
This file reports only what was run and measured. Nothing below is inferred from reading code
unless it says so.

## What was actually run
- One harness run, `node scripts/e2e/run.mjs` (journeys a–h), against production `htdblwldjkcgjvmqkbeh`,
  00:16–00:36 UTC. It opened its own rehearsal window with models allowed. At the start, 3 other
  windows with models allowed were already open (`6135be46`, `ad372b3c`, `fb1f4c30`) from parallel agents.
- Full report and screenshots: `e2e/2026-10-19T00-16-39/report.md`
- Result: **25 PASS, 12 FAIL, 9 SKIP.** Journeys c, d, e, h, f and g were skipped because the
  harness's 20-minute deadline ran out.
- Cleanup: the harness reported zero leftovers, and its window closed.
- No LLM grader was used. Every judgement below comes from DB rows, logs and screenshots.

## Customer A (English, desktop): office fit-out
| Step | Result | Evidence |
|---|---|---|
| Sign in, portal renders | PASS | en-desktop nav visible |
| Overview data loads in under 2.5 s | **FAIL** | 4127 ms. `sales_engineer:support_rating_due` alone took 3104 ms |
| Sales-engineer interview reaches ready | **FAIL** | 8 turns, then status=held, readiness=0. The reply was "reviewing it now to identify exactly the right trade" (a_intake.png) |
| 25+ turn chat, reload and tab reopen keep the memory (ruling 1255) | NOT RUN | PR #1438 (chat memory) is still OPEN, so the reload-loss risk stays unproven either way |
| BOQ PDF, DWG/DXF and photo reads | NOT RUN | |
| Routed to suppliers, quotes, comparison PDF | **FAIL** (routing) | 0 of 3 demo suppliers matched by the product. The harness invited them directly |
| Reveal and pay (TEST), invoice, refund, rating | NOT RUN | journeys skipped by the deadline |

## Customer B (Arabic, mobile 375px, then WhatsApp)
| Step | Result | Evidence |
|---|---|---|
| Arabic portal renders right-to-left (desktop and mobile) | PASS | 79/79 Arabic sitemap pages are rtl |
| Overview under 2.5 s (ar-mobile) | PASS | 1206 ms |
| Voice note, vague specs, smart Arabic questions, missing specs held | NOT RUN | The coordinator noted there is no voice-note upload; voice is live speech-to-text only |
| WhatsApp continuation through the signed webhook, context carried over | NOT RUN | |

## Supplier S (English, tablet) and the second supplier
| Step | Result | Evidence |
|---|---|---|
| Demo suppliers complete the mandatory six (licence, profile, agreement v15) | PASS | fixtures A, B and C |
| Registration from an invite with OTP, 20 MB+ profile, catalogue, terms certificate | NOT RUN | PR #1487 (upload over 20 MB) is still OPEN |
| Sees the invitation, en desktop and en mobile | PASS | |
| Sees the invitation, ar desktop and ar mobile | **FAIL** | the "الاستفسارات الواردة" tab did not open within 15 s |
| Invitation is anonymised (UI and API) | PASS | 0 of 4 customer identifiers shown; no customer_id field |
| Incomplete quote is HELD | **FAIL** | HTTP 500, no hold row, no notice → **PR #1497** |
| Two options become two quotations | **FAIL** | HTTP 500 (same cause) |
| Preflight on the complete quote | **FAIL** | would_hold=true, missing glass_type/profile_system/... |
| Complete quote accepted | PASS | HTTP 200 |
| Held quote not ranked | **FAIL** | HTTP 409 |

## Back office (read at 00:15 and 00:35 UTC)
- **cron:** 105 runs in the hour, 0 failed.
- **Safety:** nothing the run caused was dispatched (3 email and 3 WhatsApp rows, all suppressed).
- **Stale-fixture sweep: FAIL.** It hit a foreign-key error, `inbound_messages_lead_id_fkey`, while
  deleting leads. At 00:40 no demo lead had any inbound_messages row left, so the most likely cause is
  a concurrent insert by a parallel run. It is not reproduced and not fixed. Old fixtures that survive
  a sweep can take the matcher's per-trade cap of 3 and cause "routing 0/3".
- **Handoffs:** the release operator confirmed `demo_activity_files_no_seat_task_or_handoff.sql`
  (applied about 04:30 Dubai) makes `fn_seat_handoff` return NULL for demo work. That is the root cause
  of the 500 above. It probably also explains the demo intake staying held at readiness 0 and routing
  0/3, but that is not confirmed. The release operator has routed it to the #1493 fix agent.
  Production rehearsals of demo flows cannot prove handoff, hold or routing paths until this is resolved.

## Model calls (ai_cost_log, last 2 h, all callers, not only this run)
| fn | model | calls | failed | AED | avg ms |
|---|---|---|---|---|---|
| site_assistant | claude-sonnet-5.5 | 11 | 0 | 1.814 | 4282 |
| wa_inbound | claude-sonnet-5.5 | 5 | 0 | 2.265 | 5984 |
| inquiry_intake | claude-sonnet-5.5 | 1 | 0 | 0.058 | 6199 |
| site_assistant / public_site / wa_inbound / extract_text / license_extract / resilience_ping | gpt-6-luna | 114 | 0 | 0.213 | 4.3–10.8 s |
| resilience_ping, public_site | **gemini-3.8-flash** | 5 | 0 | 0.262 | 18–23 s |

- **Observation: Gemini was used outside voice.** All 5 Gemini calls were fallbacks "from
  openai/gpt-6-luna" under matrix v2. Matrix v2 allows that, but it conflicts with the
  "Gemini only for voice" rule in the brief. The Luna failures that triggered the fallback are not
  logged as failed rows. Four of the five also hit the 900-token ceiling (TRUNCATED). This needs a
  ruling, so no PR was opened.
- Luna replies averaged 5–11 s, and chat replies on Sonnet averaged 4.3–6 s. WhatsApp replies were
  under 45 s on average; no p95 was measured.

## Correction (root causes confirmed after the run)
- **This run's own window had `models_allowed=false`** (`qd_run:39514e1e`). The harness was run from
  the main checkout's stale working tree, whose `openRun` predates the 18 Oct ruling. As a result, every
  intake call was answered `fixture_no_spend` (agent_runs: "the trade could not be reasoned
  (fixture_no_spend)"). That alone explains the intake held at readiness 0, routing 0/3 and the preflight
  `would_hold`. It is a **harness/operator error, not a product defect**. origin/main's openRun already
  opens the window with `models_allowed=true`.
- The Arabic supplier tab failure was also stale-harness behaviour. origin/main uses the English tab
  name under ruling 1008.
- The model-quality rows above therefore say nothing about this run's own model use. This run made no
  paid model calls.

## Defects and PRs
| # | Defect | Seat | PR |
|---|---|---|---|
| 1 | A held demo quote returns HTTP 500 (the delivery door returns a null notification for demo work) | customer_support | **#1497** (head e486335; the demo row is suppressed explicitly and keeps its dedupe_key; chosen as main's fix) |
| 2 | Demo intake held at readiness 0, and routing 0/3 | — | not a product defect: the stale harness opened its window with models_allowed=false (see Correction) |
| 3 | Customer overview took 4.1 s; `support_rating_due` took 3.1 s on a cold function (the RPC takes 3 ms) | sales_engineer | **#1502** |
| 4 | Arabic supplier tab | — | stale harness; already fixed on main |
| 5 | Stale-run sweep failed on an inbound_messages FK | it_engineer | **#1500** |
| 6 | Gemini used as a Luna fallback outside voice, with truncation at 900 tokens | ceo (matrix) | no PR. Needs a ruling |
| 7 | Chat memory across reload not yet merged (#1438), widget sign-up link (#1480), upload over 20 MB (#1487) | — | existing open PRs |

## Not done (honest hand-over)
The three concurrent people, the 25-turn chat, document-read accuracy against the files, voice,
WhatsApp carry-over, supplier registration with OTP and certificate, Stripe TEST pay, invoice, refund,
rating, the backups and terms checks, and the 5-minute watch loop were **not executed** in this session.
The demo-handoff root cause (#1497 / #1493) blocks most of these paths in the sandbox anyway, so they
should run after that fix is merged and applied.

---

# Run 2: platform-on, ledger 1121 (19 Oct 2026, 10:50–12:44 UTC)

**Verdict: FAIL: 33 of 427 checks failed.** Run tag `qd_run:0a717394`, origin/main `c117ca5`.
`scripts/e2e/stage2.mjs --run --keep --cap-usd 15` was run with real models in one models-allowed window
and no other window open. The window was closed by the harness (0 open at 12:44 UTC). Spend was **USD 2.621**
(cap 15). Every reply, document read and match was graded from rows, logs and screenshots by the harness's
deterministic assertions and by me. No paid judge was used. Full log: `stage2_0a717394.log`. Evidence:
`INDEX.html`, `chats/`, `documents/`, `notifications/`, `browser/`, `scenario_log.json`, `coverage.json`.

Ledger 1121 fixtures: 13 ZZ DEMO suppliers in 10 trades (aluminium x4, electrical, plumbing, hvac, flooring,
joinery, glazing, painting, waterproofing, landscaping), each with its own trade licence and company profile
(exported under `documents/`), and 10 ZZ DEMO customers in EN and AR across several emirates.

**Demo rows are KEPT** (`--keep`, per the release operator: the teardown fails 0A000 since #1496 until #1537
lands). The release operator runs `sweepStaleRuns` after #1537. **0 remaining demo rows is NOT yet confirmed.**

## Failures (measured)
| # | Area | What failed | Evidence | Root cause |
|---|---|---|---|---|
| R1 | Matching (S06) | 6 of 9 requests (electrical, plumbing, flooring, joinery, glazing, landscaping) matched **0** suppliers: `no_capable_supplier`, 0 candidates before the floor | inquiries.routing at 10:57–11:09. The same `fn_match_capability` call made later (11:25) returns the run's own supplier for every one of these trades and emirates | **not confirmed.** The inputs are identical (scope_type single, no budget, same emirate); something time-dependent gated them out at routing time |
| R2 | Matching | The aluminium request fanned out to **13** suppliers, including demo suppliers of EARLIER runs (146512–146514; painting matched 126512) | inquiry_matches | fixtures leaked by the broken teardown (0A000 since #1496; fix #1537). Not a matcher fault, but it pollutes every run until swept |
| R3 | Intake (S04) | C9 waterproofing (EN, Abu Dhabi) held: `specs_unanswered: area`, readiness 70, `missing=[]` | scenario log | held on a spec the readiness list says is not missing: an inconsistency, not yet traced |
| R4 | Comparison (S09) | Arabic comparison report: HTTP 504 on the Opus route | S09 | gateway or edge timeout on the Opus comparison in Arabic, not traced |
| R5 | Reveal (S10/S24) | The Arabic customer could not reveal (quote 404 on electrical); 0 Arabic reveal_receipt | S10 | follows R1 (no electrical supplier was matched, so there was no quote) |
| R6 | Model matrix (S19) | `intent_detection` ran on **openai/gpt-6-luna** (plain, not Luna Pro) | S19 | off-matrix route row. Ledger 1218 says Pro |
| R7 | Supplier documents (S21) | 10 of the real-profile fixtures: the profile's trades proposed for matching are **incomplete or empty** (for example proposed [] against truth plumbing/waterproofing/hvac); one licence stayed `pending (documents_being_read)` | S21 | profile trade extraction under-reads. Separately, S21 crashed on `leads_claimed_company_name_uidx` (a duplicate demo company name, likely from the leaked fixtures) |
| R8 | Terms (S22) | `customer_api accept_terms` returned HTTP 401 UNAUTHORIZED_ASYMMETRIC_JWT | S22 | the harness JWT is refused by the asymmetric-JWT gate, not traced |
| R9 | Browser (S26) | **Arabic customer: "New request" could not be opened at 1440 and 1366 px**; the Arabic terms re-accept prompt was not clickable | browser/ | consistent with the coordinator's lead that the **customer portal does not fully switch to Arabic**. Not root-caused |
| R10 | Browser (S26) | Customer journeys: "no request of this customer has a quote on screen" | browser/ | follows R1 |
| R11 | Supplier registration (S26) | licence and company profile upload with the licence-expiry read failed (en/desktop) | browser/ | not traced |

## Passed (selection)
Fixtures (mandatory six, own licence and profile), demo safety (nothing reached a real person),
the elevators request HELD with no nearest match (exact trade or none), hvac/painting/aluminium routing,
the supplier quote hold → fill → regenerate → release walk with English supplier notices, model routes on
matrix v2 for every scenario except S19, duties ran on demo scope writing 0 real rows (S18), the abandoned
sign-up purge (S25), and the browser portal walk at 307 PASS / 20 FAIL.

## Not run in this window
- The dedicated customer-portal **language toggle** check and the **"Request again"** walk (EN/AR) were not run
  as separate steps. R9 is the closest measured evidence for the toggle.
- The 25+ turn chat with reload, WhatsApp carry-over, and the over-20 MB profile upload were not run as named
  steps either; stage2 covers chats in `chats/`.

No PRs were opened in this window. R1, R3, R4, R6, R7, R8, R9 and R11 need root causes before a fix.
