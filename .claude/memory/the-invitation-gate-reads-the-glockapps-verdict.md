---
name: the-invitation-gate-reads-the-glockapps-verdict
description: "27 Oct 2026: supplier invitations are gated per mailbox provider by the latest GlockApps verdict for supplier@, which a session records from the GlockApps connector (no API key in Supabase); bar in public.invite_placement_bar; applies after #1696"
metadata:
  node_type: memory
  type: project
  modified: 2026-10-27T23:59:00.000Z
---

**What decides whether an invitation goes** (once `scripts/sql/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql`
is applied, right after #1696's `no_test_mail_goes_to_the_founders_own_inboxes.sql`):

- **The verdict is recorded, not fetched.** The GlockApps key lives only in the session's connector (ledger 1344); never
  ask the founder for it. Run the test through the connector, save `get_results` (`detail: 'providers'`) to the
  scratchpad, then `node scripts/record_inbox_placement_verdict.mjs --file <answer.json>` (`--dry-run` first). It stores
  counts (`public.deliverability_test`, `deliverability_test_provider`); every rate is computed from them.
- **The bar is data**, one row in `public.invite_placement_bar`: Microsoft inbox ≥ 80% (1312); Google spam ≤ 20% and
  inbox + Promotions ≥ 80%; Yahoo/AOL inbox ≥ 80% (no bar of his, so the Microsoft one); 7 days; sender supplier@.
- **Per mailbox provider** (ledger 1377, "Outlook inbox bar is the session's job; resume is delegated once the bar is met",
  relayed by the coordinator with this scope; the relay said 1376, which does not exist). A recipient's class comes from its first cached MX host in
  `email_domain_mx`. A class that passes is invited, a failing one is skipped, and `other` follows Microsoft.
  `fn_invite_placement_gate(provider)` answers for one class. The no-argument form answers the STRICT verdict,
  `fn_invite_placement_open_providers` returns the classes that pass, and the batch, tick and nudges use that list.
- **Eligible pool by class** (probe, 27 Oct): other 10,188, microsoft 3,152, google 2,794, yahoo_aol 1,267.
- **The 27 Oct test, recorded, opens Google only** (5 inbox + 20 Promotions of 25), until 3 Nov 09:33Z.
- **GlockApps' provider rows do not cover every seed.** On 27 Oct, `stats` covered 111 tracked seeds, while the
  `providerRollup` rows add up to 106. The overall figure is GlockApps' own figure, and `overall.unclassified` holds the
  difference.
- A pass turns nothing on. `invite_enabled` stays his switch, and nothing in the gate, the recorder, the probe or the
  check writes `app_secrets`.
- Prevented by: `scripts/checks/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.test.mjs`.

Related: [[no-test-email-to-the-founders-own-inboxes]], [[invitations-resume-only-at-80-percent-outlook-inbox]],
[[checkpoint-27-oct-night-merge-train-and-the-held-queue]]
