-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724142835   name: org_export_and_nightly_github_sync
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Nightly org-as-code export for the GitHub mirror (consumed by the github_sync edge fn)
create or replace function public.fn_org_export()
returns jsonb language sql security definer set search_path to 'public','pg_temp'
as $fn$
select jsonb_build_object(
 'exported_at', now(),
 'org_departments', (select jsonb_agg(to_jsonb(t) order by t.sort) from org_departments t),
 'org_agents', (select jsonb_agg(to_jsonb(t) order by t.agent_key) from org_agents t),
 'org_authority', (select jsonb_agg(to_jsonb(t) order by t.dept_key, t.action_class) from org_authority t),
 'org_onboarding', (select jsonb_agg(to_jsonb(t) order by t.agent_key) from org_onboarding t),
 'decision_policy', (select jsonb_agg(to_jsonb(t) order by t.key) from decision_policy t),
 'policy_rules', (select jsonb_agg(to_jsonb(t) order by t.id) from policy_rules t),
 'canon_eval_questions', (select jsonb_agg(to_jsonb(t) order by t.id) from canon_eval_questions t),
 'agent_knowledge', (select jsonb_agg(jsonb_build_object('agent_key',agent_key,'topic',topic,'layer',layer,'priority',priority,'content',content) order by agent_key, priority desc, topic) from agent_knowledge t),
 'company_vision', (select jsonb_agg(to_jsonb(t)) from company_vision t),
 'ai_constitution', (select jsonb_agg(to_jsonb(t)) from ai_constitution t where active),
 'migrations', (select jsonb_agg(jsonb_build_object('version',version,'name',name) order by version) from supabase_migrations.schema_migrations)
)
$fn$;
revoke execute on function public.fn_org_export() from public, anon, authenticated;

-- Nightly at 04:10 UTC (after the 03:xx snapshot/report jobs)
select cron.schedule('github_org_sync_nightly', '10 4 * * *', $$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/github_sync',
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    headers:='{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds:=120000)
$$);
