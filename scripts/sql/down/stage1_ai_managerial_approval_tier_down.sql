-- Down for stage1_ai_managerial_approval_tier.sql.
--
-- NOTE: the modified dispatcher fn_action_invoke_dispatch (in
-- scripts/sql/the_queue_that_had_nobody_to_hand_it_to.sql) REFERENCES action_approval and
-- fn_action_resolve_approver at runtime. Before running this down, revert that file to its prior
-- commit and re-apply it, or the dispatcher will error when it next sweeps a consequential action:
--   git checkout <pre-Defect-1 commit> -- scripts/sql/the_queue_that_had_nobody_to_hand_it_to.sql
--   node scripts/apply_sql.mjs scripts/sql/the_queue_that_had_nobody_to_hand_it_to.sql --apply --ddl
-- (The dispatcher crons are INACTIVE, so nothing sweeps in the meantime.)

begin;
drop function if exists public.fn_action_head_approve(uuid,text,text,text);
drop function if exists public.fn_action_resolve_approver(text,text);
drop function if exists public.fn_action_authority_rank(text);
drop table if exists public.action_approval;
commit;
