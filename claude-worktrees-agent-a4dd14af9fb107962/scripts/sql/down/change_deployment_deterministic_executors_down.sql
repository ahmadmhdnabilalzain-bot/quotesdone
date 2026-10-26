-- Down for change_deployment_deterministic_executors.sql: re-points change_deployment steps 1, 8, 9 at the
-- action classes they carried on 4 Sep 2026 (recommend / code_selfheal / recommend), removes the three
-- executor rows and drops the routine. Runs already closed by the executor keep their outputs.
begin;
update public.workflow_step set action_class = 'recommend'     where workflow_key = 'change_deployment' and step_no = 1;
update public.workflow_step set action_class = 'code_selfheal' where workflow_key = 'change_deployment' and step_no = 8;
update public.workflow_step set action_class = 'recommend'     where workflow_key = 'change_deployment' and step_no = 9;
delete from public.org_action_executor where action_class in ('change_deploy_baseline','change_deploy_promote','change_deploy_grade');
drop function if exists public.fn_change_deployment_execute(jsonb);
commit;
