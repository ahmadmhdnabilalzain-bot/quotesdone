-- THE TRAINER'S DRAFT PROMPT IS HELD WITH ITS ROLE, NOT THE FOUNDER (6 Sep 2026).
--
-- The low_quote_quality recommendation read "drafting an improved quote_review prompt for your
-- approval" and its cost line said "Rollout stays founder-approved". A prompt_approval
-- agent_action is held with fn_action_holder('prompt_approval','ai_trainer'); nothing but a
-- refund routes to the founder. The prose names the holder.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_ai_trainer_prompt_is_held_with_its_role.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_ai_trainer()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_runs int; v_err int; v_run_ok numeric;
  v_open int; v_rej int; v_acc int; v_reject_rate numeric; v_esc_rate numeric;
  v_qa_total int; v_qa_failed int; v_qa_pass numeric;
  v_sat numeric; v_halluc numeric; v_clarif numeric;
  v_quote_q numeric; v_match_cov numeric;
  v_health numeric; v_kpis jsonb; n_rec int; v_weak text; v_secret text; n_drafted int:=0; v_ref text;
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
    'These agents need attention: '||v_weak||'. Review their logic/prompt or the knowledge they rely on.',
    jsonb_build_array(
      'A failed run means the agent performed badly. Several routines here write status=error to record a real-world FINDING they were built to report, so a watcher doing its job correctly lands in this list.',
      'A founder rejection means the agent was wrong. Rejecting a correct recommendation for a business reason counts identically.',
      'The 20-run floor makes the percentages meaningful, and it also hides every agent below it — an agent that ran three times and failed all three never appears here.'),
    'These are the agents the company relies on unattended. Fixing the prompt or knowledge behind them raises the quality of everything they touch, rather than correcting outputs one at a time.',
    'Model spend to re-benchmark after a change, plus engineering time. The costly mistake is rewriting a prompt for an agent whose real problem is the knowledge it retrieves.');

  perform ai_rec('low_quote_quality', coalesce(v_quote_q,100) < 60, 'medium', 'Quote-review quality is low',
    'Structured quote quality is averaging '||coalesce(v_quote_q,0)||'/100. The Trainer is drafting an improved quote_review prompt, held with '||public.fn_action_holder('prompt_approval','ai_trainer')||' for review before rollout; also strengthening category knowledge helps.',
    jsonb_build_array(
      'The score measures the QUOTES suppliers submit, not the reviewer reading them. A low average can mean suppliers are quoting thinly, and rewriting the review prompt would not move it.',
      'coalesce(v_quote_q,100) treats "never measured" as a perfect 100, so this rule stays silent when there is no evidence at all rather than raising a false alarm — silence here is not a pass.',
      'The average comes from the newest agent_evals snapshot only, so a single bad day moves it.'),
    'Quote quality is what the customer compares. Every point of it is the difference between a buyer who can decide and a buyer who asks all three suppliers to re-quote.',
    'Model spend on the drafted prompt plus a benchmark run. Rollout stays held with the prompt_approval holder, so nothing changes on the strength of this alert alone.');

  perform ai_rec('thin_benchmarks', coalesce(v_qa_total,0) < 20, 'low', 'Add more test benchmarks',
    'The QA suite has only '||coalesce(v_qa_total,0)||' cases. Add benchmark cases (quotes, RFQ qualification, compliance answers) so regressions are caught automatically.',
    jsonb_build_array(
      'Twenty is a chosen floor, not a derived one. Twenty cases covering one path are worth less than five spanning quoting, qualification and compliance.',
      'The count comes from the most recent qa_results row, so a suite that failed to run leaves an old, small number standing and looks like a thin suite rather than a missing run.'),
    'Benchmarks are the only thing that makes a prompt change comparable. Without them every improvement is an opinion and every regression is invisible until a customer finds it.',
    'Model spend per case, per run. Cases are cheap; the cost is writing ones that test something real rather than restating what the model already does well.');

  perform ai_rec('prompts_unbenchmarked', (select count(*) from prompt_versions where status='active' and eval_score is null)>0, 'low', 'Prompts have no eval score',
    (select count(*)::text from prompt_versions where status='active' and eval_score is null)||' active prompt(s) have never been benchmarked. Run an eval so future changes can be compared objectively.',
    jsonb_build_array(
      'A null eval_score means never benchmarked. It would read identically if a benchmark ran and failed to write its score back.',
      'These prompts are live: status=''active'' is what the routines load, so an unbenchmarked prompt is already in production use.'),
    'A score on each active prompt turns the next prompt change from a guess into a comparison. Until then there is no way to tell an improvement from a regression.',
    'Model spend, one eval run per prompt. Small, and it is the precondition for every other improvement on this board being measurable.');

  perform ai_rec('accuracy_watch', coalesce(v_halluc,0) > 15, 'high', 'Accuracy watch — high correction rate',
    'The AI was corrected/failed '||coalesce(v_halluc,0)||'% of the time (founder rejections + QA failures). Review the rejected actions to find the pattern and fix the responsible prompt or knowledge.',
    jsonb_build_array(
      'This is a PROXY, and its name says so where the founder does not read it. It is (founder rejections + QA failures) over (accepted + rejected + QA cases), so a founder rejecting a CORRECT recommendation for a business reason raises it exactly as much as a genuine hallucination.',
      'The denominator mixes two different populations — live agent actions and QA test cases — so the percentage is not a rate of anything that happens in one place.',
      'A high figure means disagreement, which is not the same as inaccuracy. Reviewing the rejected actions, which is what the recommendation asks for, is the only way to tell the two apart.'),
    'If the pattern is real, fixing the prompt or knowledge behind it corrects every future answer of that shape. If it is the founder disagreeing on business grounds, the finding is that the agent''s brief is wrong, not its reasoning — and that is worth as much.',
    'No spend to review. Model spend only if a prompt is redrafted afterwards.');

  -- CLOSED LOOP: when quote quality is low and no draft is already awaiting approval, ask the LLM to author an improved
  -- quote_review prompt DRAFT (the prompt_approval holder approves before rollout; never the founder). De-duped so it drafts once per open cycle.
  if coalesce(v_quote_q,100) < 60
     and not exists (select 1 from agent_actions where kind='prompt_approval' and detail->>'key'='quote_review.system' and status in ('pending','needs_review'))
     and not exists (select 1 from prompt_versions where prompt_key='quote_review.system' and status='draft') then
    select value into v_secret from app_secrets where key='cred_db_internal';
    -- PROMOTE-SAFE REF. This was a literal project ref, which meant this routine's definition
    -- differed between projects and `apply_sql --promote` would have repointed production at
    -- staging. Same lookup fn_action_invoke_dispatch and fn_rfq_redispatch_sweep use.
    select value into v_ref from app_secrets where key='project_ref';
    if v_ref is null then
      select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
        from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
    end if;
    if v_ref is not null then
      perform net.http_post(
        url:='https://'||v_ref||'.supabase.co/functions/v1/prompt_improve',
        headers:='{"Content-Type":"application/json"}'::jsonb,
        body:=jsonb_build_object('__secret',v_secret,'key','quote_review.system',
          'reason','Structured quote quality is averaging '||coalesce(v_quote_q,0)||'/100 — quotes lack itemised detail (brand/model/spec/unit price) and clear scope; the prompt should require full line-item detail and flag missing fields.'));
      n_drafted := 1;
    end if;
  end if;

  select count(*) into n_rec from agent_actions where agent='ai_trainer' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'ai_health',v_health,'kpis',v_kpis,'open_recommendations',n_rec,'auto_drafted',n_drafted);
end $function$;
