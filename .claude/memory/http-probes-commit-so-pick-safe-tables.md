---
name: http-probes-commit-so-pick-safe-tables
description: "The §8 probe harness exists at scripts/phase_d/run_section8_security_probes.mjs; an HTTP probe COMMITS, so the aborted-transaction discipline does not apply and the fixture table must be chosen by its triggers."
metadata: 
  node_type: memory
  type: project
  originSessionId: b938bfcf-ddcb-45bf-8cf7-2f8b74c71fd5
  modified: 2026-08-19T12:03:38.250Z
---

Built 19 Aug 2026. All seven §8 security probes run over real HTTP —
`scripts/phase_d/run_section8_security_probes.mjs`, 23 assertions, verdicts recorded in
`public.phase_d_section8_probe_result`, read by `fn_phase_d_injected_defect_report()`.

**An HTTP request commits.** Phase D's "drive it in a transaction you abort" is unavailable, so
fixtures must be namespaced canaries deleted in a `finally`, and the table is chosen by measuring
its triggers first:

- SAFE: `auth.users` canaries, `public.customers` (fires `fn_emit` → one deletable `company_event`),
  `public.leads` **only** when `approval_status <> 'approved'` and `verified = false` (otherwise
  `enrich_capability_on_approve` posts HTTP and `fn_assign_founding_rank` consumes a rank).
- FORBIDDEN under the hold: `inquiries` (`trg_inquiry_received` writes a notification whenever the
  customer has an e-mail — and it must, or `customer_api` cannot resolve it), `quotes`
  (`trg_new_quote_sms`), `transactions` (`trg_reveal_receipt`).
- DO NOT CALL: `mobile_otp` action `status` **inserts a customers row for the caller** before
  serving what looks like a pure read. `supplier_api save_profile` reaches the registration branch
  at `supplier_api/index.ts:603` and writes two notifications, one to management@quotesdone.com —
  use `save_settings` for a cross-tenant write test.

Two measurement traps this harness had to fix in itself:

- **PostgREST answers an RLS-invisible table and an EMPTY one with the identical `200 []`.** Count
  every table with the service_role FIRST; `inquiries`, `quotes`, `refunds`, `transactions` are all
  0 rows, so a denial there proves nothing. See [[zero-cannot-tell-a-dead-guard-from-an-idle-system]].
- **`net.http_request_queue` drains**, so a queue length of 0 at the end is not evidence nothing was
  posted. The durable record is `net._http_response`.

Cleanup notes: `storage.protect_delete()` refuses `delete from storage.objects` via SQL — use the
Storage API — and each delete must be its own statement, or one refusal aborts the whole batch and
nothing is cleaned. `public.notifications` has no `customer_id`; it keys on `to_email` / `lead_id`.
