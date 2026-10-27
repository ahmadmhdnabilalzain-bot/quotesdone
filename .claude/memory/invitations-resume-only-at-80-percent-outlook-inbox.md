---
name: invitations-resume-only-at-80-percent-outlook-inbox
description: "Supplier invitations stay paused unless a GlockApps test from supplier@ shows Outlook at 80% inbox or more (27 Oct 2026, instruction 1312)"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-27T06:00:00.000Z
---

The founder, 27 Oct 2026: keep the batch held, so the invitations stay paused, **unless Outlook is
at least 80% inbox** in the GlockApps check of the invitation sent from supplier@quotesdone.com.
Report inbox, spam and promotions for each provider.

**How to apply:**
- `invite_enabled` stays `false` until the rate is measured.
- "Outlook" means the outlook.com, hotmail.com and Office 365 seeds together. If the report splits
  them, quote each one.
- The daily seed to management@quotesdone.com is NOT evidence. It never leaves our tenant.
- A pass is a GlockApps report for the live copy over the M365 lane, measured the same day.
- At or above 80%, resume with the steps in `docs/reports/QuotesDone Campaign/SUPPLIER_WARMUP_PLAN_27_OCT.md`.
- Below 80%, it stays held and the cause gets fixed.
- **27 Oct 2026, first measurement:** GlockApps `id:2026-10-27-09:33:53:634t`, Microsoft 0 of 18 inbox, so FAIL.
  The causes and fixes are in `docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md`. The next
  test is due Wed 4 Nov, through the `deliverability_test` loop.

Related: [[checkpoint-27-oct-cloud-invitations-held]], [[ask-before-the-internal-test-email]]
