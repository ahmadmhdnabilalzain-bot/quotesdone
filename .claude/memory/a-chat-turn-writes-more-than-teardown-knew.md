---
name: a-chat-turn-writes-more-than-teardown-knew
description: "27 Oct 2026: a harness chat turn writes assistant_logs, sales_decision_log, support_reply_readability, a support profile+case, and (unanswered) a knowledge gap + org_task. Teardown now removes them by audience, run tag and run email; a rehearsal files no gap or task."
metadata:
  type: lesson
  seat: customer_support
---

Measured 27 Oct 2026 (PR #1635, conversation bank, ~270 portal turns): after closeRun, 273 assistant_logs, 269
sales_decision_log, 273 support_reply_readability (demo=false) and 97 sales_knowledge_gap + 97 org_tasks remained.
Separately, z50_support_wire_widget turns every `customer:<id>` assistant_logs row into a support profile + case:
76 ZZ DEMO profiles (74 orphaned) and 113 cases had piled up since 12 Oct, invisible to staleRunTags because their
customer rows were gone.

**Why:** teardown and leftovers() listed only the marketplace tables (customers, inquiries, quotes, money). The chat
road writes elsewhere, and leftovers() could not see what it never counted, so every run read "clean".

**How to apply:**
- A rehearsal is known in the database by `fn_e2e_rehearsal_tag()` (service-role header or app.e2e_run_tag, naming a
  rehearsal_window). `a00_chat_row_e2e_run_tag` stamps `e2e_run_tag` on the three chat tables; readability rows become
  demo. fn_sales_assist / fn_support_knowledge_gap file NO gap/task for a rehearsal
  (`scripts/sql/a_rehearsal_files_no_knowledge_gap_and_its_chat_rows_carry_its_run_tag.sql`).
- Teardown (`scripts/lib/demo_factory.mjs`) removes assistant_logs by audience and tag, the other two by tag, and the
  support chain by the run's own email/ids. closeRun counts gaps a run filed BEFORE teardown (the tagged decision rows
  are the only link) and fails the run on any.
- When a new feature writes a row per chat turn, add it to teardown AND leftovers() in the same PR, or the harness
  will keep reporting clean while it leaks. Ask "what does one turn write?" by reading triggers on the table too.

Check: `scripts/checks/a_rehearsal_leaves_no_chat_rows_and_files_no_task.test.mjs`.
