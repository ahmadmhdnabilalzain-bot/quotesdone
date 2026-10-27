---
name: a-handoff-is-answered-at-replied-at-not-decided-at
description: "27 Oct 2026 — on a handoff kind the originator closes, decided_at is the originator's re-verification; the receiver's answer is detail.replied_at. Measuring 'late' by decided_at blames the receiver for the sender's open loop."
metadata:
  type: feedback
---

On a handoff whose `seat_handoff_kind.originator_closes` is true, there are two times:

- `detail.replied_at` is when the RECEIVER answered;
- `decided_at` / `status = 'done'` is when the ORIGINATOR re-verified and closed.

**Measured 27 Oct 2026.** In 30 days, sales_engineer answered 414 of its 414 it.finding handoffs inside the 4-hour
window, but only 21 were closed inside it. The quarterly `fn_ceo_seat_audit` counts a pending handoff past its window as
the receiver's late handoff, so its 43 "late" for sales_engineer (and 15 accountant, 17 customer_support) were handoffs
already answered and waiting on the sender. The real open loop was IT: 916 answered handoffs waiting for it to
re-verify.

**How to apply:**

- Measure a receiver by `coalesce(detail->>'replied_at', decided_at)`.
- Count "unanswered past window" only where `not detail ? 'replied_at'`.
- Measure the originator separately, by answered-and-still-pending past the window.
- Registered handlers answer by code at once, so the receiver half is close to 100% for every seat; the lag that matters
  is the originator's close.

`fn_ceo_seat_senior_verdict` measures it this way. `fn_ceo_seat_audit` did not, as of 27 Oct.

Related: [[nothing-is-one-way]], [[instrument-measuring-wrong-subject-is-the-lens]].
