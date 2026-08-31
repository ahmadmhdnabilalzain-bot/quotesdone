-- TWO INDEPENDENT APPROVALS FOR SPEND AND CONTRACT — no one commits money or a contract alone.
--
-- The founder's loop: marketing needs funding, so it talks to finance, and finance approves the
-- payment thinking long-term about the AED 1,000,000 target. That is a SECOND, independent sign-off
-- on top of the requesting department's own head — a two-person rule for spend and contract.
--
-- Today fn_action_invoke_dispatch dispatches a consequential action on a SINGLE head's approval
-- (action_approval, one row). This adds the second authority:
--   * org_action_executor.second_authority — the role_id that must ALSO approve a spend/contract
--     executor before it can dispatch (NULL keeps the single-approval behaviour for everything else).
--   * action_approval gains the second approver's columns.
-- fn_action_head_approve (edited in stage1_ai_managerial_approval_tier.sql) now records EITHER the
-- primary head's decision OR the second authority's, refusing anyone who is neither and refusing a
-- second who is the same identity as the primary or the author. fn_action_invoke_dispatch (edited in
-- the_queue_that_had_nobody_to_hand_it_to.sql) dispatches only when BOTH are approved.
--
-- Applied first (the functions reference these columns). No LLM.
--
--   node scripts/apply_sql.mjs scripts/sql/dual_approval_for_spend_and_contract.sql --apply --ddl

begin;

alter table public.org_action_executor
  add column if not exists second_authority text;

alter table public.action_approval
  add column if not exists second_authority text,
  add column if not exists second_approver_role text,
  add column if not exists second_approval_decision text,
  add column if not exists second_decided_at timestamptz;

-- The dispatchable consequential money action in the estate today: a customer/vendor dispute the
-- finance head opens. It carries a legal dimension, so the General Counsel (runtime agent 'legal') is
-- the independent second signatory — never the finance head who requests it. Stored as the runtime
-- AGENT key, the same identity space fn_action_resolve_approver returns the primary approver in, so
-- the two are comparable. Management sets this per executor as real spend and contract executors are
-- added (an ad-spend commit -> 'cfo', a contract -> 'legal').
update public.org_action_executor
   set second_authority = 'legal'
 where action_class = 'dispute_open';

commit;
