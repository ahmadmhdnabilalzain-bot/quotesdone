-- PROBE: every model call carries its prompt hash and spend is watched by class, against the idle floor and the replay
-- backlog. Pure probe, no DDL: run AFTER its .sql in the SAME query (node scripts/qsql.mjs on a file that concatenates
-- both); it always ends in raise exception CHK<<...>>, so nothing survives. Its rows are ZZ DEMO cost rows (fn
-- 'zz_demo_probe') and ZZ DEMO held questions; no model is called and nothing is sent.
-- PROBE OK only if, after fn_it_engineer_model_spend():
--   1. five paid calls of one prompt raise duty:model_spend:repeat:...; five refusals (model 'none') of another do not;
--   2. a consumer above twice its expected USD a day raises class_spend; the estate above USD 1 raises idle_floor;
--   3. five held questions tried twice raise replay_retries;
--   4. fn_llm_log stores the prompt hash it is given.
do $probe$
declare v_model text; v jsonb; v_fail text := ''; i int;
begin
  select model into v_model from public.model_rate where in_aed_per_mtok > 0 order by in_aed_per_mtok desc limit 1;
  for i in 1..5 loop
    perform public.fn_llm_log('zz_demo_probe', null, 'it_engineer', 'zz_demo_class', v_model, 'ZZ DEMO probe', 'high',
                              400000, 100000, false, null, 10, true, null, 0, 0, null, null, 'zzprobehash_paid_0000');
    perform public.fn_llm_log('zz_demo_probe', null, 'it_engineer', 'zz_demo_class', 'none', 'ZZ DEMO probe refusal', 'none',
                              0, 0, false, null, 10, true, null, 0, 0, null, null, 'zzprobehash_refused_00');
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, attempts, last_attempt_at, dedupe_key)
    values ('it_engineer', 'zz_demo.probe', 'ZZ DEMO probe retried ' || i, '{"seat":"it_engineer"}', '{}', 'probe', 'held', 2,
            now() - interval '1 day', 'zzprobe:retried:' || i);
  end loop;
  if (select count(*) from public.ai_cost_log where prompt_hash = 'zzprobehash_paid_0000') <> 5 then
    v_fail := v_fail || ' fn_llm_log did not store the prompt hash;'; end if;

  v := public.fn_it_engineer_model_spend();

  if not exists (select 1 from public.it_engineer_finding where closed_at is null
                  and issue_key = 'duty:model_spend:repeat:zz_demo_probe:zz_demo_class:zzprobehash_') then
    v_fail := v_fail || ' five paid calls of one prompt raised no repeat;'; end if;
  if exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key like 'duty:model_spend:repeat:%zzprobehash_re%') then
    v_fail := v_fail || ' refusals were counted as paid repeats;'; end if;
  if not exists (select 1 from public.it_engineer_finding where closed_at is null
                  and issue_key = 'duty:model_spend:class_spend:zz_demo_probe:zz_demo_class') then
    v_fail := v_fail || ' a class far above its expected USD raised nothing;'; end if;
  if not exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key = 'duty:model_spend:idle_floor') then
    v_fail := v_fail || ' the estate above USD 1 in 24 h raised nothing;'; end if;
  if not exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key = 'duty:model_spend:replay_retries') then
    v_fail := v_fail || ' five rows tried twice raised nothing;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK model=' || v_model || ' settled=' || (v->'settled')::text
                                     else 'PROBE FAILED:' || v_fail || ' settled=' || coalesce((v->'settled')::text, 'null') end;
end $probe$;
