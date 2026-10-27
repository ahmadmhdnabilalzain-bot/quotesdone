---
name: a-chat-turn-names-no-customer-so-it-carries-the-run-tag
description: A sandbox run's chat turns (assistant_logs, sales_decision_log, support_reply_readability) name no customer, so teardown missed them and their gaps opened unconfirmed tasks; they carry e2e_run_tag and test traffic files no gap.
metadata:
  type: lesson
---

27 Oct 2026 (it_engineer). One sandbox run left 273 assistant_logs, 269 sales_decision_log, 273
support_reply_readability, 97 sales_knowledge_gap and 97 org_tasks after its teardown said clean. They were removed
by hand. The 97 tasks broke "no task unless the founder confirmed it", and existing gaps had their ask counters bumped.

**Why it was missed:** teardown and `--verify-clean` scope by customer, lead, inquiry and quote ids. These four
tables carry none of them. A scope built from ids cannot see a table that names nobody.

**What holds now** (`scripts/sql/a_harness_chat_turn_carries_its_run_tag_and_files_no_gap_or_task.sql`, applied
at merge):
- The three log tables get `e2e_run_tag`. It is stamped at insert by `fn_ai_cost_log_e2e_run_tag`, the same function
  as ai_cost_log, from the request's proven run tag.
- `fn_sales_assist` and `fn_support_knowledge_gap` file nothing for test traffic: `fn_e2e_run_tag_current()` is set,
  or `fn_seat_work_is_demo` matches the text. Nothing is filed, no counter is bumped and no task is opened.
- `demo_factory.chatTurnSql` is the one scope. `teardown()` deletes by it, and stage2 `verifyClean` counts by it.

**For the next table a turn writes:** stamp it with the same trigger and add it to `CHAT_TURN_TABLES`. Do not build
a new marker. Prevented by `scripts/checks/a_harness_chat_turn_files_no_gap_and_is_torn_down_by_its_tag.test.mjs`.
Its replay runs teardown's own statements in an aborted transaction.

Related: [[demo-fixture-convention]], [[no-job-or-task-without-an-agent]].
