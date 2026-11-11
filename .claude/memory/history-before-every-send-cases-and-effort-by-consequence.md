---
name: history-before-every-send-cases-and-effort-by-consequence
description: "11 Nov 2026, rulings 1630/1631/1634/1635: one effort map (_shared/effort_policy.ts), the outbox duplicate guard, the case model (support_case summary + same-matter decision), what is pending SQL."
metadata:
  type: project
  modified: 2026-11-11
---

Report: docs/reports/2026-11-11-history-and-effort.md (it_engineer, branch it_engineer-history-and-effort).

- **Effort lives in ONE map:** `supabase/functions/_shared/effort_policy.ts`.
  - The gateway applies it to every call that names no effort, and raises a caller's 'low' on a class that decides.
  - Never write `effort: 'low'` at a call site. `scripts/checks/the_effort_policy_is_one_map.test.mjs` fails on it.
  - A sorting surface becomes low only by flipping `provenLow`, after `scripts/eval/effort_low_vs_high.mjs` passes.
    That eval was prepared but not run (USD 0.13 expected).
  - The WhatsApp reading is HIGH: one call also decides needs-a-person.
- **Notifications carried no dedupe_key** (0 of 731). The seed list went out twice on 10 Nov (6 sent twice).
  - `_shared/outbox_duplicate_guard.ts`, in send_outbox and send_whatsapp, cancels the same message to the same person
    inside `outbox_duplicate_window_min` (default 10).
  - The a00 insert trigger is pending SQL.
- **The case already existed:** support_case, support_customer_profile and fn_support_touch link one person across
  channels. What was missing is the summary and the same-matter decision.
  - Pending SQL: every_support_case_keeps_a_summary_and_the_reply_reads_it.sql. Apply it AFTER the model_policy effort
    file.
  - Code: `_shared/support_case_memory.ts`, wired into WhatsApp only. It returns null until the SQL is live.
  - Dropbox: a seam, switched off, until pdf_native renders `gen_kind case_summary`.
- **fn_contact_timeline does not include assistant_logs.** Widget and portal chats are invisible to WhatsApp and email.
  Not changed here.
- **Load-test rows without an e2e_run_tag.** The chat-under-load run of 11 Nov wrote 1,971 assistant_logs rows with
  user_agent `node` and no tag. Exclude them by user agent when measuring.
