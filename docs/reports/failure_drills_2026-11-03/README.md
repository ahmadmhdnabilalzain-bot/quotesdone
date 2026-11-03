# Failure-injection drills D1–D12, 3 Nov 2026

Owner: **it_engineer**. Source of the drill list: `docs/release/qualification_matrix.md` §5.1. Gate that keeps the
list and the tests in step: `scripts/checks/every_failure_drill_names_a_test_that_exists.test.mjs`.

**What was measured, and what was not.** Every drill is a Deno test of the **real module** with its dependencies
stubbed: the edge function's own `Deno.serve` handler, with `fetch` answering for PostgREST, ai_gateway, OpenRouter,
Resend, Microsoft Graph, Twilio, Stripe, Dropbox, VirusTotal and CloudConvert. D8 and D9 run the real SQL routines
(loaded from the MANIFEST-canonical files, plus the pending D9 fix) on a throwaway Postgres 16 at 127.0.0.1:55433.
Nothing touched production, no real network was reachable (the suite grants net to 127.0.0.1 only), and every
recipient is a demo identity (`+971 50 000 00xx`, `@example.invalid`, `ZZ DEMO`). These runs are **offline**. They do
not prove the deployed commit. Matrix §1.2 still needs each line run against production on the day.

Five things were asserted on every drill:
- **Not lost.** Every inbound message is answered, or held with a reason.
- **No code-written text while a model is up** (founder ruling 1339).
- **Nothing sent twice.**
- **The right seat gets a finding or a handoff.**
- **Recovery needs no manual step.**

## Results

| D | inject | result | defects fixed | test files |
|---|---|---|---:|---|
| D1 | OpenRouter 500/502/503, connection refused, every route open-circuit; model up but returning not-JSON, `''`, `null`, `choices: []`, an HTML page, or a cut-off answer | PASS | 2 | `ai_gateway/drill_provider_faults.test.ts`, `_shared/drill_model_faults.test.ts`, `wa_inbound/drill_inbound_faults.test.ts`, `email_triage/drill_triage_faults.test.ts` |
| D2 | provider hangs past the gateway wall; gateway hangs past the client; the turn deadline; e-mail runs overlapping or killed | PASS | 2 | same four files |
| D3 | Resend 500/502/503, 429 with Retry-After, 422, timeout before and after acceptance, hang on every attempt, overlapping runs | PASS | 3 | `send_outbox/drill_send_faults.test.ts` |
| D4 | the same signed Stripe event twice, two copies at once, events out of order, a stale signature, the wrong secret | PASS | 1 | `stripe_webhook/drill_webhook_replay.test.ts` |
| D5 | Twilio 500/503/429/401, 63016, 63003, 21610, a code-less 503, a timeout after acceptance (customer rows and founder rows) | PASS | 2 | `send_whatsapp/drill_twilio_faults.test.ts` |
| D6 | Dropbox upload 503, network failure, timeout, token refused, verify 503; Graph 401/403/429/503, token endpoint down, sendMail timeout | PASS | 1 | `dropbox_backup/drill_dropbox_down.test.ts`, `send_outbox/drill_send_faults.test.ts` |
| D7 | VirusTotal and CloudConvert answering 503/401, timing out, unreachable | **OPEN** | 0 | `_shared/drill_virustotal_down.test.ts`, `cad_convert/drill_cloudconvert_down.test.ts` |
| D8 | an isolated duty whose own pg_cron job stopped | PASS (that case only) | 0 | `resilience_ping/drill_seat_duty_throws.test.ts` |
| D9 | the `zz_demo_control` duty forced to raise | PASS with the pending SQL | 1 (SQL) | `resilience_ping/drill_seat_duty_throws.test.ts` |
| D10 | PostgREST 500/503 PGRST000, 504 PGRST003, statement timeout 57014, and connection reset on hot-path writes and reads | PASS (client side) | 4 | `inquiry_intake/drill_database_unavailable.test.ts`, `wa_inbound/…`, `send_outbox/…`, `email_triage/…` |
| D11 | bad deploy | NOT DRILLABLE OFFLINE | — | none |
| D12 | `cred_fn_*` rotated between calls and mid-flight; credential verifier unreachable | PASS | 1 | `_shared/drill_model_faults.test.ts`, `ai_gateway/drill_provider_faults.test.ts` |

Every path above is under `supabase/functions/`. In total, 17 defects were fixed. Each one has a test that failed before the fix and passes after it. The
before and after runs were recorded in this session, and each fix's comment names its test (`prevented by:`).

## The 17 defects

| # | D | seat | module | what the drill measured | the fix |
|---:|---|---|---|---|---|
| 1 | D1 | it_engineer | `ai_gateway` | An empty completion left the gateway as the same 502 `all_models_failed` as a provider 5xx. `isOpenRouterDown` read that as an outage, so a code-written notice was licensed while the model was up (ruling 1339). | It now fails as `empty_completion`, and `openrouter_down` reads that as "the model answered". |
| 2 | D1 | it_engineer | `ai_gateway` | A reply cut at `finish_reason: length` was cached, and the next identical request got the fragment as a complete answer. | A truncated answer is never stored. |
| 3 | D2 | customer_support | `email_triage` | think() held the reply question, the direct reply went out, and the replay later answered it again. Result: two replies. | The hold is filed only if no reply went. |
| 4 | D2 | customer_support | `email_triage` | Two overlapping runs both answered the same mail, for known and unknown senders alike. | The triage mark is the claim. |
| 5 | D3 | it_engineer | `send_outbox` | A refused send was retried on the next 2-minute poll, so a ~4-minute Resend outage dead-lettered the queue. | Back-off of 5, then 20 minutes (or Retry-After, up to 1 h). |
| 6 | D3 | it_engineer | `send_outbox` | A 422 invalid recipient was posted twice more before it failed. | 400 and 422 fail at once. |
| 7 | D3 | it_engineer | `send_outbox` | A Resend timeout was marked sent-unconfirmed at once, so a message Resend never received was lost. | Retried under the same Idempotency-Key below the ceiling. |
| 8 | D4 | accountant | `stripe_webhook` | Two copies of one delivery at once: the loser of the unique index logged "PAID BUT NOT RECORDED" and answered 500 for a sale that was recorded. | Fixed on main by #1835 (accountant, `recordRevealSale`) while this drill's fix was in review; this PR takes main's fix, and the drill passes against it. |
| 9 | D5 | customer_support | `send_whatsapp` | A 21610 (the person replied STOP) was followed to SMS. | Final: failed with the reason, no twin, the code stamped on the row. |
| 10 | D5 | customer_support | `send_whatsapp` | A code-less Twilio refusal was logged as "template awaiting Meta approval". | Its own `twilio_unknown_retry` line. |
| 11 | D6 | it_engineer | `send_outbox` (M365 lane) | Graph accepted the send, the "sent" write failed, and the next tick (or the 5-minute claim expiry) sent the supplier a second copy. Graph has no idempotency key. | A `m365-pending:` marker is written before the POST, and a row that returns carrying it is never sent again. |
| 12 | D9 | it_engineer | SQL `fn_seat_duty_health` | A failing duty was raised only at 3 failures, one failure per run, so a daily duty was reported on its third day. | An hourly-or-slower duty is raised on its first failure. This is `scripts/sql/a_failing_daily_duty_opens_its_finding_on_its_first_failure.sql`, **pending: applied at merge**. |
| 13 | D10 | customer_support | `wa_inbound` | Any error on the `wa_inbound_seen` insert was read as a Twilio redelivery. A 500, a timeout or a reset dropped the message: not stored, not answered, logged `ok`. 3 of 3 faults did this. | Only a 409 or 23505 is a duplicate; the arrival rows decide otherwise, and it_engineer gets a finding. |
| 14 | D10 | customer_support | `_shared/wa_history` | A failed history read returned `[]` silently, so the model answered with no memory and nothing said so. | The caller raises an it_engineer finding. The reply still goes. |
| 15 | D10 | sales_engineer | `inquiry_intake` | Both turn-save sites answered `ok: true` with a reply while the database refused the write. | 503 `intake_unavailable`. The resend carries the same `turn_id` and is saved once. |
| 16 | D10 | customer_support | `email_triage` | A failed inbox read closed the run `ok` with every count 0, which looks the same as a quiet inbox. | The run closes as error, with a 500. |
| 17 | D12 | it_engineer | `ai_gateway` | A credential-verifier outage (503) was flattened to 403 "forbidden", so a database blip read as a rotated credential. | The verifier's own status is passed through. |

## Still open

- **D7, P1, needs a decision (sales_engineer with it_engineer).** When VirusTotal is down, `sanitizeAndScan` returns
  `ok: true, cleared: false`. Neither `supplier_catalog_ingest` nor `supplier_api` reads `cleared`, so an unscanned price
  list is stored and read: the drill saw 2 product records made from one. The `_shared/malware.ts` header records this as
  a deliberate choice (option (c)). The matrix expects "held". Separately, nothing re-scans an `unavailable` file once
  VirusTotal returns; the only signal is a `file_unscanned` security event after 24 h. The correct assertion is in the
  drill file with `ignore: true`.
- **D11.** Needs a deploy to a branch function slug and a timed rollback (matrix R2). It is not runnable offline.
- **Parts of D2, D8 and D10 are not drillable offline:**
  - the edge CPU kill (546);
  - the whole tick stopping, where `resilience_ping` itself is not called;
  - a real Postgres restart.
- **Observations, not fixed:**
  - **Turn clock overrun.** A turn's clock can run over its deadline by up to 5 s. llm.ts aborts at `timeoutMs + 5000`, and the gateway wall is that minus 3 s. On WhatsApp, the last call ended 92–95 s after arrival against a 90 s budget, inside the 150 s edge limit.
  - **No fetch timeout on supabase-js.** A database call that hangs, rather than errors, holds a turn until the edge limit. send_outbox rows come back through the 5-minute claim expiry.
  - **No second-reply guard in `fn_inbox_send`.** It does not refuse a second automated reply when `replied_at` is set. The edge side is fixed (#3, #4); a SQL guard would be defence in depth.
  - **Test-mode refund before its sale.** On Stripe, a test-mode refund that arrives before its sale is answered 200 and never retried.
  - **Dropbox give-up.** After 5 attempts (~30 min of outage) Dropbox archive rows wait for the daily listing check, and a refused refresh token needs the app re-authorised.
  - **Opt-out policy.** The 21610 change (#9) is a policy change: an opted-out person is no longer followed to SMS. customer_support owns it.

## How to run

```bash
npm test
```

The drills are `*.test.ts`, so `scripts/checks/run.mjs` runs them with the suite's permission flags. D8 and D9 need
the throwaway cluster, started with the recipe in `supabase/functions/resilience_ping/drill_seat_duty_throws.test.ts`.
Without it they are **ignored**, with `[NOT RUN: …]` in their names. They never pass empty.
