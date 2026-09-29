# Postmortem: `watch:run_failure` — a function failed most or all of its attempts in an hour

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class | `watch:run_failure:<function>` — 9 functions |
| Handoffs covered | **15** (12 high, **3 critical**) |
| First / last | 14 Sep 2026 14:45Z / 28 Sep 2026 12:46Z |
| Answering seats | accountant, ceo, customer_support, sales_engineer |

## Timeline (function, handoffs)
`ai_gateway` 6 (14 Sep → 24 Sep; first reading "failed every one of its 106 attempts"), `login_otp` 2 (18 Sep, 33% vs
1% baseline), `pdf_native`, `stripe_confirm`, `compliance_archive` (18 Sep), `resend_inbound` (14 Sep),
`license_extract` (15 Sep), `site_assistant` (21 Sep, 31% vs 0%), `voice_otp_capture` (28 Sep 12:46Z) — 1 each.

## Impact
Mixed. `login_otp`, `site_assistant`, `stripe_confirm` and `voice_otp_capture` are customer-facing; the rest internal.
Each detector finding resolved within about an hour (close notes: "The detector no longer sees it: run_failure resolved …"),
except `voice_otp_capture`, whose finding is **still open** (critical) at the time of writing.

## Root cause
- `ai_gateway`: the founder's OpenRouter hold returns HTTP 503 `circuit_open`, logged as `error` — the hold working, read as a
  failure (`IT_FAILURES_18_21_SEP_2026.md`, "also measured"). Memory: "out of credit looks like model judgement".
- The others: single-hour bursts. Their individual causes were **not determined** in this postmortem; the detector
  recorded no evidence beyond the failure rate.

## Detection
`fn_it_detect` run_failure arm. Worked.

## Fix (found in git)
- `9744feb` (#785): `a_run_the_founders_hold_refused_is_held_not_failed.sql` — a run the hold refused is held, not failed.
- `the_it_detector_evaluates_its_row_rules_as_sets_not_as_function_calls.sql` (same PR): detector correctness.

## Action items
1. **it_engineer** — diagnose `watch:run_failure:voice_otp_capture` (open, critical, since 28 Sep 12:46Z).
2. **it_engineer** — store the first failing run's error text on the finding so a burst's cause survives its resolution.

## Handoff ids covered
`watch:run_failure` (15): 13371, 22215, 27391, 35365, 35366, 35367, 35785, 38792, 40611, 53406, 68136, 69796, 87689, 93514, 101479.
