-- The whole AI workforce was switched off by one secret. fn_role_of already has an AI-employee
-- branch and returned 'guest' for every employee because agent_autonomy_enabled = 'false'.
-- Guest holds zero role_permissions rows, so fn_authorize refused every action and
-- trg_action_gate rewrote every one to needs_review: 1,252 of 1,262 gate decisions in 30 days
-- held, the dominant reason on each being 'role "guest" lacks permission "run_agent_action"'.
-- The arming date (agent_autonomy_from = 2026-07-30) passed eleven days ago.
-- Turning it on grants the 'agent' role: run_agent_action (max_amount_aed 0), send_message,
-- route_inquiry. Anything carrying money is still refused, and issue_refund is not held by the
-- agent role at all, so the founder's one reserved approval stays reserved.
select set_config('app.change_reason',
  'Arming the AI workforce: agent_autonomy_enabled was false, so fn_role_of returned guest for every employee and every action failed closed into the founder approval queue. The founder has stated refunds are his only approval; run_agent_action keeps max_amount_aed 0 and issue_refund is not granted to the agent role.',
  true);
update app_secrets set value = 'true' where key = 'agent_autonomy_enabled';
