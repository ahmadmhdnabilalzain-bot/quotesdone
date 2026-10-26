---
name: coverage-credited-per-function-not-per-table
description: "An edge function credited as \"cut over\" because ONE of its write tables carries a kernel trigger — customer_api and inquiry_intake both create public.customers, which reaches nothing."
metadata: 
  node_type: memory
  type: project
  originSessionId: f9a36089-6fc5-4d31-8137-ab97b324a4b4
  modified: 2026-08-24T21:07:56.110Z
---

`routes_through_inbox` is decided **per edge function**: if any table it writes carries a
kernel-routing trigger, the whole function reads as cut over. `edge:customer_api` reads `true`
because it writes `inquiries` (`trg_inquiry_received_a`), `quotes`, `leads`, `notifications`,
`transactions`. It **also** INSERTs `public.customers` — and `public.customers` carries four
triggers, **none** of which calls `fn_kernel_trigger_submit` / `_signal_submit` / `_source_emit`.
`trg_emit_customer_registered` calls `fn_emit(...)`, a domain-event emit, not a kernel submit.

So a `customer_account` — a frozen Phase B business object governed by W04 — is created with no
workflow run, no task, no accountable owner and no trace, from two live authenticated paths
(`edge:inquiry_intake`, and `customer_api`'s `me` handler). Measured 24 Aug 2026; `public.customers`
was at 0 rows, so the blast radius is future, not past.

The committed cutover matrix says `edge:inquiry_intake` is
`COVERED_BY_A_CUT_OVER_TABLE_TRIGGER — routine:trg_inquiry_received`. That is true about the
**inquiry** and silent about the **customer**.

**Why:** function-level attribution hides an uncovered write behind a covered sibling, and the
disposition text then repeats the half-truth.

**How to apply:** attribute coverage per (function, table), not per function. When a cutover row
claims coverage, ask *which of its writes does that trigger actually sit on?* The durable fix is a
kernel-routing trigger on the **table**, so every creator is covered — see
[[a-sibling-path-that-never-got-the-lexicon]] and [[reading-who-you-are-must-not-create-it]].
