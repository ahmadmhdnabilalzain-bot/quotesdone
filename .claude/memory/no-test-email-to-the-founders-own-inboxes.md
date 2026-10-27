---
name: no-test-email-to-the-founders-own-inboxes
description: "27 Oct 2026, standing: never send test, seed, placement or warm-up mail to the founder's own mailboxes; GlockApps decides deliverability; the morning seed is retired and its gate fails closed until the GlockApps verdict replaces it"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-27T23:30:00.000Z
---

The founder, 27 Oct 2026 ~22:50Z, verbatim: *"stop doing tests on my email. thats extremely useless"*. Recorded in
`public.founder_instruction` as "no test email to the founder's own inboxes", status `standing`, by
`scripts/sql/no_test_mail_goes_to_the_founders_own_inboxes.sql`.

**His mailboxes:** management@quotesdone.com, ahmadmhdnabilalzain@gmail.com (any +tag or dotted form),
management@doratajewelries.com, djzaino@outlook.com, bookings@djzaino.com, fati.labib@icloud.com, plus whatever
`app_secrets` `founder_email` / `admin_emails` hold.

**How to apply:**
- Never queue a seed, test, placement check or warm-up message to any of them, by script, by SQL or by hand. A
  deliverability question goes to a **GlockApps** test (ledger 1312, 1344), never to him.
- Business mail to him is not a test and is unaffected: founder_brief, the daily supplier list, accountant reports,
  alerts.
- What enforces it (once the file is applied): trigger `a01_notifications_no_test_mail_to_the_founder` raises on any
  `supplier_invite_seed` row, or kind `invite_m365_seed` / `supplier_invite_seed`, addressed to him in to or cc;
  `fn_invite_placement_due` queues nothing; `scripts/invitation_inbox_check.mjs` has no founder allowlist.
- **Resuming invitations has one more step.** `fn_invite_placement_gate` answers `fail:seed_retired` every day,
  because the morning seed that opened it is gone. Resume = replace that gate with a reader of the GlockApps verdict
  (#1649), in the same change that sets `invite_enabled` back to true. Otherwise the batch and the nudges stay held
  and a `deliverability:inbox_placement` (verdict `seed_retired`) finding is filed each open day.
- Prevented by: `scripts/checks/no_test_mail_goes_to_the_founders_own_inboxes.test.mjs`.

Related: [[invitations-resume-only-at-80-percent-outlook-inbox]], [[checkpoint-27-oct-cloud-invitations-held]]
