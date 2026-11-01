---
name: the-ceo-acts-on-the-supplier-target
description: "Ledger 1438: the CEO owns the 300-400 target. fn_ceo_growth_act holds bounded powers behind ceo_growth_act_golive; brakes and ledger 1231 still win. It supersedes 'never touch the invitation switch' for the CEO routine only."
metadata:
  type: project
  modified: 2026-11-02
---

Founder, 1 Nov (ledger 1438): he gives targets, the CEO acts. Built: `scripts/sql/the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql`.

**How to apply:** change caps, lead order and channel state through `fn_ceo_growth_decide` (pure) and `fn_ceo_growth_act` (daily duty `ceo.supplier_growth`), never a new writer. Every change is a `ceo_growth_action` row with a measured effect. The cap the target needs is reported by `fn_ceo_supplier_goal_status`, and never written past `fn_invite_founder_cap` without a ledger ruling. Founder text stays free of the reserved words (`fn_ceo_founder_text_forbidden`); his one message is `ceo_daily_number`.

**Why it is not 300 yet:** see docs/reports/CEO_SUPPLIER_CHANNELS_2_NOV.md. Measured 2 Nov: about 39 starts at most, only the Google class open, 772 checked leads in it.

Check: scripts/checks/the_ceo_acts_on_the_supplier_target_and_writes_its_effects.test.mjs.
