---
name: seat-qualification-audit-10-nov-break-even
description: "10 Nov 2026 (ledger 1609): the six seats audited against break-even by 30 Jun 2027; not reachable on e-mail alone; the every-trade launch rule blocks revenue; the CEO's brakes were held by a switch; the placement verdict expires 26 Nov"
metadata:
  type: project
  modified: 2026-11-10
---

Report: `docs/reports/2026-11-10-seat-qualification-audit.md`, on branch `ceo-seat-qualification-audit` (4 pending SQL
commits, not applied).

**Numbers a future session should not re-derive:**
- Cost to cover by 30 Jun 2027 is AED 42,545 to 46,931. That is the founder's AED 19,000 + measured recurring AED 2,733 a
  month + OpenRouter AED 181-753 a month + the licence renewal on 24 Jun 2027 (AED 1,200). GL expenses read AED 18,386.82.
- Net per reveal is 0.9643 × 0.03 × Q − 1.05. The supplier subscription earns nothing before supplier #1,001.
- Measured funnel: 137 sent, 1 start, 0 registered; 0.79 % start rate of delivered; 30-day bounce 11 of 97.

**Things that bite:**
- **The CEO's launch rule needs all 223 trades at 10 suppliers** (`fn_ceo_launch_readiness`, from 1 Dec). Until per-category
  launch is ruled (proposal P1), no revenue can start.
- **The GlockApps verdict of 27 Oct is the only placement verdict, and it is valid for 30 days.** On 26 Nov ~22:50Z no mailbox
  class is open, so invitations stop. Only a session with the GlockApps connector can re-test.
- **A switch that can only stop a brake is a safety limit pointing the wrong way.** `ceo_growth_act_golive` held 8 days of
  bounce-brake cuts. Fixed by the pending `the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.sql`:
  the safety side applies; the raising side still waits.
- **The `founder_brief` kind carried other mail.** The CEO note (`fn_ceo_daily_run`, 7 in 14 days) was sent under it, and
  `fn_ceo_launch_readiness` and `fn_ceo_month_plan` still send under it. When counting what reaches the founder, split
  each kind by subject.
- **All six seats are self-graded `junior`** (`ceo.senior_verdict`). Every `seat_self_review` reads `no_exam`, because
  `knowledge/exams/*.json` were never loaded.

Related: [[the-ceo-acts-on-the-supplier-target]], [[the-invitation-gate-reads-the-glockapps-verdict]], [[seat-audit-senior-human-standard]].
