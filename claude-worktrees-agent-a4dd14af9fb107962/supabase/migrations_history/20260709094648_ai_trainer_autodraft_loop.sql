-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709094648   name: ai_trainer_autodraft_loop
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ai_trainer()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  v_runs int; v_err int; v_run_ok numeric;
  v_open int; v_rej int; v_acc int; v_reject_rate numeric; v_esc_rate numeric;
  v_qa_total int; v_qa_failed int; v_qa_pass numeric;
  v_sat numeric; v_halluc numeric; v_clarif numeric;
  v_quote_q numeric; v_match_cov numeric;
  v_health numeric; v_kpis jsonb; n_rec int; v_weak text; v_secret text; n_drafted int:=0;
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
  v_halluc := round(100.0*(coalesce(v_rej,0)+coalesce(v_qa_failed,0))/nullif(coalesce(v_acc,0)+coalesce(v_rej,0)+coalesce(v_qa_total,0),0),1);
  select round(100.0*count(*) filter (where rfq_ready)/nullif(count(*),0),1) into v_clarif from inquiries where created_at>=now()-interval '90 days';
  select (kpis->>'quote_quality_avg')::numeric, (kpis->>'match_coverage_pct')::numeric into v_quote_q, v_match_cov from agent_evals order by snapshot_at desc limit 1;

  v_kpis := jsonb_build_object(
    'window_days',30,'run_success_pct',v_run_ok,'escalation_rate_pct',v_esc_rate,'rejection_rate_pct',v_reject_rate,
    'qa_pass_pct',v_qa_pass,'qa_cases',v_qa_total,'customer_satisfaction',v_sat,
    'hallucination_proxy_pct',v_halluc,'clarification_efficiency_pct',v_clarif,
    'quote_quality_avg',v_quote_q,'match_coverage_pct',v_match_cov,
    'runs_30d',v_runs,'errors_30d',v_err,'open_escalations',v_open,'rejected',v_rej,'accepted',v_acc);

  insert into agent_evals(snapshot_at, window_days, kpis) values (now(), 30, v_kpis);
  v_health := round(coalesce(v_run_ok,100)*0.30 + (100-coalesce(v_halluc,0))*0.25 + coalesce(v_sat,70)*0.20 + coalesce(v_qa_pass,100)*0.15 + coalesce((select coverage_pct from knowledge_kpis),60)*0.10,1);
  insert into ai_trainer_snapshots(snapshot_date, kpis) values (current_date, v_kpis || jsonb_build_object('ai_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  select string_agg(agent||' ('||coalesce(run_success_pct,0)||'% ok, '||coalesce(rejection_rate_pct,0)||'% rejected)', '; ')
    into v_weak from ai_agent_quality where runs_30d>=20 and (coalesce(run_success_pct,100)<90 or coalesce(rejection_rate_pct,0)>30);
  perform ai_rec('weak_agents', v_weak is not null, 'medium', 'Under-performing agents',
    'These agents need attention: '||v_weak||'. Review their logic/prompt or the knowledge they rely on.');
  perform ai_rec('low_quote_quality', coalesce(v_quote_q,100) < 60, 'medium', 'Quote-review quality is low',
    'Structured quote quality is averaging '||coalesce(v_quote_q,0)||'/100. The Trainer is drafting an improved quote_review prompt for your approval; also strengthening category knowledge helps.');
  perform ai_rec('thin_benchmarks', coalesce(v_qa_total,0) < 20, 'low', 'Add more test benchmarks',
    'The QA suite has only '||coalesce(v_qa_total,0)||' cases. Add benchmark cases (quotes, RFQ qualification, compliance answers) so regressions are caught automatically.');
  perform ai_rec('prompts_unbenchmarked', (select count(*) from prompt_versions where status='active' and eval_score is null)>0, 'low', 'Prompts have no eval score',
    (select count(*)::text from prompt_versions where status='active' and eval_score is null)||' active prompt(s) have never been benchmarked. Run an eval so future changes can be compared objectively.');
  perform ai_rec('accuracy_watch', coalesce(v_halluc,0) > 15, 'high', 'Accuracy watch — high correction rate',
    'The AI was corrected/failed '||coalesce(v_halluc,0)||'% of the time (founder rejections + QA failures). Review the rejected actions to find the pattern and fix the responsible prompt or knowledge.');

  -- CLOSED LOOP: when quote quality is low and no draft is already awaiting approval, ask the LLM to author an improved
  -- quote_review prompt DRAFT (founder still approves before rollout). De-duped so it drafts once per open cycle.
  if coalesce(v_quote_q,100) < 60
     and not exists (select 1 from agent_actions where kind='prompt_approval' and detail->>'key'='quote_review.system' and status in ('pending','needs_review'))
     and not exists (select 1 from prompt_versions where prompt_key='quote_review.system' and status='draft') then
    select value into v_secret from app_secrets where key='inbound_secret';
    perform net.http_post(
      url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/prompt_improve',
      headers:='{"Content-Type":"application/json"}'::jsonb,
      body:=jsonb_build_object('__secret',v_secret,'key','quote_review.system',
        'reason','Structured quote quality is averaging '||coalesce(v_quote_q,0)||'/100 — quotes lack itemised detail (brand/model/spec/unit price) and clear scope; the prompt should require full line-item detail and flag missing fields.'));
    n_drafted := 1;
  end if;

  select count(*) into n_rec from agent_actions where agent='ai_trainer' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'ai_health',v_health,'kpis',v_kpis,'open_recommendations',n_rec,'auto_drafted',n_drafted);
end $fn$;
revoke all on function public.fn_ai_trainer() from anon, authenticated, public;
