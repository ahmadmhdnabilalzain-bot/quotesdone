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
  - The WhatsApp reading is HIGH: one call also decides needs-a-person.
- **The side-by-side was run on 11 Nov (final audit); no surface is proven low.** Results: section 6 of the report and
  `docs/reports/effort-low-vs-high-2026-11-11/`.
  - The menu reading (the only sorting surface with recorded input): low chose as high did on 23 of 26 recorded messages.
    The three misses are all a menu option that high read and low called "other". One of them, a one-word message, was
    asked six times in all: each arm read it two ways, so one run per arm cannot separate effort from chance there.
  - The menu reading is not called on its own in production: it rides the one WhatsApp readings call (0 rows for
    `wa_inbound.greeting_state` in `seat_judgement`). Lowering it would change nothing measurable.
  - **A decision that cannot finish inside its clock decides nothing.** At high (and at medium) the two intake readings
    (`inquiry_intake.exact_spec`, `inquiry_intake.trade`) take 29-48 s and the intake turn gives them 21.5 s. In production
    in the first 12.5 hours of the map, 20 of 28 spec-reader calls failed (8 of 59 in the 7 days before). Only low finished
    in the replay (11-19 s).
    Before raising a surface's effort, measure it against the clock it runs under.
  - `seat_judgement` (surface, made_at, decided_at, status) is the per-surface record of think() decisions: it says how
    long each took and how many were held. `ai_cost_log` has no surface and no effort column.
- **A paid eval imports the functions tree AFTER `connect()`.** `_shared/e2e_run.ts` installs the fetch forwarder that
  carries the run tag only if `SUPABASE_URL` is set when it is first imported. Imported at the top of the replay, the
  forwarder was missing: 5 smoke calls (USD 0.0097) went out untagged, were booked as ordinary `wa_inbound` traffic, and
  the spend guard read USD 0. `effort_low_vs_high/replay.ts` now asserts the forwarder and stops on an untagged call.
- **Notifications carried no dedupe_key** (0 of 731). The seed list went out twice on 10 Nov (6 sent twice).
  - `_shared/outbox_duplicate_guard.ts`, in send_outbox and send_whatsapp, cancels the same message to the same person
    inside `outbox_duplicate_window_min` (default 10).
  - The a00 insert trigger is pending SQL.
- **The case already existed:** support_case, support_customer_profile and fn_support_touch link one person across
  channels. What was missing is the summary and the same-matter decision.
  - Pending SQL: every_support_case_keeps_a_summary_and_the_reply_reads_it.sql. Apply it AFTER the model_policy effort
    file.
  - Code: `_shared/support_case_memory.ts`. The SQL was applied on 11 Nov (#1938).
- **Cases on every channel** (customer_support, branch `customer_support-cases-everywhere`):
  - `_shared/case_context.ts`: each turn calls `loadCaseContext` once before the model and `recordCaseExchange` once
    after the reply. That covers the widget, the customer portal, the supplier quotation chat and the email reply;
    WhatsApp keeps `wa_inbound/case_memory.ts`.
  - An anonymous visitor has no identity, so no case. One person is one `support_customer_profile`.
  - Tests: `_shared/case_context.test.ts`, plus one test per door in `scripts/checks/every_case_keeps_a_summary.test.mjs`.
- **The promise ledger** is `support_case_promise`, written by the one summary writer.
  - Due times are read by code (`_shared/case_promises.ts`, Dubai time). With no date, a promise is due in 48 h
    'assumed'.
  - The hourly duty `customer_support.promise_watch`:
    - keeps a 'quotes' promise when a `new_quote` notice is sent;
    - flags one due within 24 h to its seat (a `support.promise_due` handoff);
    - counts them in the CEO brief (`ceo_brief_line`).
  - The seat marks the rest with `fn_support_case_promise_mark`.
- **Dropbox:** one Markdown file per case at `<person folder>/cases/<case>.md`, re-queued on each version. It is
  rendered by code (`_shared/case_dropbox.ts`) from `dropbox_backup` `renderGenerated`, and needs no PDF.
  - The #1938 seam would not have worked: it queued one row per version with a storage path nothing writes.
  - Deploy `dropbox_backup` BEFORE applying `a_case_summary_is_a_text_file_in_the_persons_dropbox_folder.sql`.
- **fn_contact_timeline does not include assistant_logs** (widget and portal chats). Still not changed: the cases link a
  person through `support_customer_profile`, and the case summary is the cross-channel history the reply reads.
- **A local Postgres 16 stub proved both SQL files.** The scratch builder copies tables and routines from the mirror;
  handoffs need the `a01`/`a02`/`z61` agent_actions triggers and `fn_handoff_summary`, or the note check refuses them.
- **Load-test rows without an e2e_run_tag.** The chat-under-load run of 11 Nov wrote 1,971 assistant_logs rows with
  user_agent `node` and no tag. Exclude them by user agent when measuring.
- **An empty case record is not a broken writer (16 Nov 2026, it_engineer, audit WHO_KNOWS_WHAT item 2).** Production held 30
  cases, 0 summaries, 0 promises. Measured: 16 of the 30 are demo (15 fixture numbers); every real reply predates the writer
  (last 10 Nov); since 11 Nov no identified person was answered on any case door (0 WhatsApp turns, 0 mails replied, widget
  anonymous only). All 29 `case_summary` calls ever were e2e-tagged audit runs, whose 91 versions and 23 promises went with
  their demo cases (fn_demo_support_case_purge). Before calling the writer broken, count real answered exchanges since it shipped.
  - Branch `it_engineer-every-support-case-keeps-its-summary-and-promises`: every open case of the person (one line + open
    promises, newest first, 5 cases / 8 promises) reaches the reply, also with several recorded matters and none named
    (was: no case at all); fn_support_open_cases returns each case's open ledger rows
    (every_open_case_of_a_person_reaches_the_reply_with_its_open_promises.sql); a summary wrapped in prose is read (summaryJson).
