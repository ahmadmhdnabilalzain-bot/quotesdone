-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709093919   name: fn_ai_trainer_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.ai_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='ai_improvement' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('ai_trainer','ai_improvement','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'ai',p_sig);
  end if;
end $$;
revoke all on function public.ai_rec(text,boolean,text,text,text) from anon, authenticated, public;

create or replace function public.fn_ai_trainer()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  v_runs int; v_err int; v_run_ok numeric;
  v_open int; v_rej int; v_acc int; v_reject_rate numeric; v_esc_rate numeric;
  v_qa_total int; v_qa_failed int; v_qa_pass numeric;
  v_sat numeric; v_halluc numeric; v_clarif numeric;
  v_quote_q numeric; v_match_cov numeric;
  v_health numeric; v_kpis jsonb; n_rec int; rec record; v_weak text;
begin
  select count(*), count(*) filter (where status in ('error','failed')) into v_runs, v_err from agent_runs where started_at>=now()-interval '30 days';
  v_run_ok := round(100.0*(v_runs-v_err)/nullif(v_runs,0),1);
  select count(*) filter (where status in ('pending','needs_review')),
         count(*) filter (where status='rejected'),
         count(*) filter (where status in ('approved','done','auto_done'))
    into v_open, v_rej, v_acc from agent_actions where created_at>=now()-interval '30 days';
  v_reject_rate := round(100.0*v_rej/nullif(v_rej+v_acc,0),1);
  v_esc_rate := round(100.0*v_open/nullif(v_open+v_acc+v_rej,0),1);
  select total, failed into v_qa_total, v_qa_failed from qa_results order by run_at desc limit 1;
  v_qa_pass := round(100.0*(coalesce(v_qa_total,0)-coalesce(v_qa_failed,0))/nullif(v_qa_total,0),1);
  select avg_satisfaction into v_sat from customer_kpis;
  -- hallucination PROXY: how often the AI was wrong (founder rejections + QA failures)
  v_halluc := round(100.0*(coalesce(v_rej,0)+coalesce(v_qa_failed,0))/nullif(coalesce(v_acc,0)+coalesce(v_rej,0)+coalesce(v_qa_total,0),0),1);
  -- clarification efficiency PROXY: share of inquiries that reached rfq_ready
  select round(100.0*count(*) filter (where rfq_ready)/nullif(count(*),0),1) into v_clarif from inquiries where created_at>=now()-interval '90 days';
  select (kpis->>'quote_quality_avg')::numeric, (kpis->>'match_coverage_pct')::numeric into v_quote_q, v_match_cov from agent_evals order by snapshot_at desc limit 1;

  v_kpis := jsonb_build_object(
    'window_days',30,'run_success_pct',v_run_ok,'escalation_rate_pct',v_esc_rate,'rejection_rate_pct',v_reject_rate,
    'qa_pass_pct',v_qa_pass,'qa_cases',v_qa_total,'customer_satisfaction',v_sat,
    'hallucination_proxy_pct',v_halluc,'clarification_efficiency_pct',v_clarif,
    'quote_quality_avg',v_quote_q,'match_coverage_pct',v_match_cov,
    'runs_30d',v_runs,'errors_30d',v_err,'open_escalations',v_open,'rejected',v_rej,'accepted',v_acc);

  -- write into the eval framework (populates the previously-null hallucination/satisfaction/clarification) + trainer snapshot
  insert into agent_evals(snapshot_at, window_days, kpis) values (now(), 30, v_kpis);
  v_health := round(coalesce(v_run_ok,100)*0.30 + (100-coalesce(v_halluc,0))*0.25 + coalesce(v_sat,70)*0.20 + coalesce(v_qa_pass,100)*0.15 + coalesce((select coverage_pct from knowledge_kpis),60)*0.10,1);
  insert into ai_trainer_snapshots(snapshot_date, kpis) values (current_date, v_kpis || jsonb_build_object('ai_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  -- IMPROVEMENT PROPOSALS (founder-visible; the Trainer never changes a prompt or agent on its own)
  -- weak agents (enough volume, low reliability or high rejection)
  select string_agg(agent||' ('||coalesce(run_success_pct,0)||'% ok, '||coalesce(rejection_rate_pct,0)||'% rejected)', '; ')
    into v_weak from ai_agent_quality where runs_30d>=20 and (coalesce(run_success_pct,100)<90 or coalesce(rejection_rate_pct,0)>30);
  perform ai_rec('weak_agents', v_weak is not null, 'medium', 'Under-performing agents',
    'These agents need attention: '||v_weak||'. Review their logic/prompt or the knowledge they rely on.');
  -- low quote quality -> prompt + knowledge
  perform ai_rec('low_quote_quality', coalesce(v_quote_q,100) < 60, 'medium', 'Quote-review quality is low',
    'Structured quote quality is averaging '||coalesce(v_quote_q,0)||'/100. Recommend revising the quote_review prompt and strengthening category knowledge (hand to Knowledge Curator).');
  -- thin benchmarks
  perform ai_rec('thin_benchmarks', coalesce(v_qa_total,0) < 20, 'low', 'Add more test benchmarks',
    'The QA suite has only '||coalesce(v_qa_total,0)||' cases. Add benchmark cases (especially for quotes, RFQ qualification and compliance answers) so regressions are caught automatically.');
  -- prompts without an eval score
  perform ai_rec('prompts_unbenchmarked', (select count(*) from prompt_versions where status='active' and eval_score is null)>0, 'low', 'Prompts have no eval score',
    (select count(*)::text from prompt_versions where status='active' and eval_score is null)||' active prompt(s) have never been benchmarked. Run an eval so future changes can be compared objectively.');
  -- hallucination proxy elevated
  perform ai_rec('accuracy_watch', coalesce(v_halluc,0) > 15, 'high', 'Accuracy watch — high correction rate',
    'The AI was corrected/failed '||coalesce(v_halluc,0)||'% of the time (founder rejections + QA failures). Review the rejected actions to find the pattern and fix the responsible prompt or knowledge.');

  select count(*) into n_rec from agent_actions where agent='ai_trainer' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'ai_health',v_health,'kpis',v_kpis,'open_recommendations',n_rec);
end $fn$;
revoke all on function public.fn_ai_trainer() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('ai_trainer','AI Trainer','🧠',true,
  'The meta-agent that improves every other AI. Monitors reliability, accuracy, a hallucination proxy (founder corrections + QA failures), confidence, escalations, customer feedback and weak knowledge; scores per-agent quality and overall AI health; and writes the eval snapshot (including customer satisfaction and hallucination signals). PROPOSES improvements — prompt revisions, new benchmarks, knowledge fixes and playbooks — as founder-visible actions, and hands weak-knowledge areas to the Knowledge Curator. It NEVER changes a prompt, rolls out a new version, or alters an agent on its own; prompt changes go through the founder and the prompt-versioning approval flow.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('ai_trainer_daily','30 5 * * *', $$select public.fn_ai_trainer();$$);
