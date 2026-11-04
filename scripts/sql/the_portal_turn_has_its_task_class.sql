-- THE PORTAL TURN HAS ITS TASK CLASS (customer_support; independent review of #1640, 27 Oct 2026).
--
-- Assigned: customer_support (the portal chat turn is its seat's reply; the route row is the gateway's floor under it).
--
-- WHY. #1640 made the signed-in portal chat turn ONE direct gateway call from sales_engineer/index.ts
-- (answerFromBrief, fn 'sales_engineer', taskClass 'customer_portal_assistant'). Before it, the sales_engineer function
-- had no direct ai_gateway caller, so it never needed a fn_task_class row. MEASURED read-only on production, 27 Oct 2026:
-- public.fn_task_class has NO row for fn 'sales_engineer' (customer_api and messages_api, the other signed-in portal
-- callers, map to customer_portal_assistant with dept_key null). scripts/checks/no_gateway_caller_is_clamped_below_what_it_asks_for.test.mjs
-- fails on the branch for exactly that: "these fn labels reach ai_gateway with no task class: sales_engineer".
--
-- WHAT A MISSING ROW COSTS. A caller-supplied task_class wins in fn_ai_route (the_customer_facing_assistant_was_unmapped.sql),
-- so today's call routes correctly. The row is the floor under that: if a call ever arrives without its task_class it
-- lands on the class written for it instead of general_drafting (UNMAPPED, the cheapest medium model, 900 tokens), and
-- the route's budget lookup by fn finds a row. Same class and dept_key as customer_api and messages_api.
--
-- Data only, no DDL, no routine. Idempotent (on conflict on the primary key fn).
-- PROVED (rolled back): the_portal_turn_has_its_task_class_probe.sql, run in ONE query after this file through
--   node scripts/qsql.mjs: fn_ai_route asked for fn 'sales_engineer' with no task_class routes to customer_portal_assistant.
-- Prevented by: scripts/checks/no_gateway_caller_is_clamped_below_what_it_asks_for.test.mjs (reads this row out of this file).
-- APPLY at merge of #1640 (release operator): node scripts/apply_sql.mjs scripts/sql/the_portal_turn_has_its_task_class.sql --apply,
--   then delete its pending note and append it to the END of scripts/sql/MANIFEST.txt.

insert into public.fn_task_class (fn, task_class, note, active, dept_key)
values ('sales_engineer', 'customer_portal_assistant',
        'The signed-in portal chat turn (#1640: one streamed answerFromBrief call). The caller passes task_class; this row is the floor under it. Same class as customer_api and messages_api.',
        true, null)
on conflict (fn) do update set task_class = excluded.task_class, note = excluded.note, active = true, updated_at = now();
