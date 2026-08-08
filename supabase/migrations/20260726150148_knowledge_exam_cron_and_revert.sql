-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726150148   name: knowledge_exam_cron_and_revert
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Continuous auto-learning: every 4h, examine the least-recently-tested agent (auto-pick).
select cron.schedule('knowledge_exam_loop', '23 */4 * * *', $$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/knowledge_exam',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('__secret', (select value from app_secrets where key='inbound_secret'), 'generate', 6, 'answer', 8)
  );
$$);

-- Bulk-revert exam-sourced knowledge for an agent (or all) — the escape hatch if auto-fill ever drifts.
create or replace function public.fn_exam_revert(p_agent_key text default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog' as $$
declare n int;
begin
  delete from agent_knowledge
    where topic like 'exam:%' and (p_agent_key is null or agent_key = p_agent_key);
  get diagnostics n = row_count;
  update knowledge_exam_results set filled = false, knowledge_id = null
    where filled and (p_agent_key is null or agent_key = p_agent_key);
  return jsonb_build_object('reverted', n, 'agent', coalesce(p_agent_key,'(all)'));
end $$;
revoke execute on function public.fn_exam_revert(text) from anon, authenticated, public;
