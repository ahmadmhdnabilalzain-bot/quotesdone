-- A MODEL CALL WHOSE COST IS UNKNOWN IS BOOKED UNKNOWN, NEVER FREE - THE PROBE (sales_engineer, 13 Oct 2026).
-- Replayed after a_model_call_whose_cost_is_unknown_is_booked_unknown_never_free.sql in ONE aborted transaction
-- (scripts/lib/safe_replay.mjs): always raises, verdict in CHK<<...>>. Its two rows are written with fn 'zz_probe_unknown_cost'
-- and never survive. Asserts: a call with no token counts stores NULL tokens, NULL cache tokens and NULL cost_aed;
-- an ordinary priced call on the same model is still booked with its tokens and a cost above 0; the monthly unit
-- economics names the unpriced call; Sonnet 5.5, gemini-3.8-flash:online and perplexity/sonar price a known call above
-- zero; no known call on them is left at AED 0, and the verdict carries what the backfill re-priced (rows, AED); the idle-floor reader selects a consumer with 5 unknown calls (read, not called: it notifies).
do $p$
declare bad text[] := '{}'; r record; v jsonb; i int; m text; c numeric; n_fix int; aed_fix numeric; n_unk int;
begin
  perform public.fn_llm_log('zz_probe_unknown_cost', null, null, 'visitor_chat', 'anthropic/claude-sonnet-5.5', 'probe unknown',
    'large', null, null, false, null, 100, true);
  perform public.fn_llm_log('zz_probe_unknown_cost', null, null, 'visitor_chat', 'anthropic/claude-sonnet-5.5', 'probe priced',
    'large', 15000, 400, false, null, 100, true, null, 14000, 0);

  select * into r from public.ai_cost_log where fn = 'zz_probe_unknown_cost' and model_selected_because = 'probe unknown';
  if r.prompt_tokens is not null or r.output_tokens is not null or r.cached_in_tokens is not null
     or r.cache_write_tokens is not null or r.cost_aed is not null then
    bad := bad || ('unknown call stored ' || coalesce(r.prompt_tokens::text,'null') || '/' || coalesce(r.output_tokens::text,'null')
                   || ' tokens, cost ' || coalesce(r.cost_aed::text,'null'));
  end if;
  select * into r from public.ai_cost_log where fn = 'zz_probe_unknown_cost' and model_selected_because = 'probe priced';
  if r.prompt_tokens is distinct from 15000 or r.cached_in_tokens is distinct from 14000 or coalesce(r.cost_aed, 0) <= 0 then
    bad := bad || ('priced call stored ' || coalesce(r.prompt_tokens::text,'null') || ' tokens, cost ' || coalesce(r.cost_aed::text,'null'));
  end if;

  v := public.fn_accountant_unit_economics(current_date);
  if coalesce((v->>'llm_calls_unpriced')::int, 0) < 1 then bad := bad || 'unit economics does not count the unpriced call'::text; end if;

  for i in 1..4 loop
    perform public.fn_llm_log('zz_probe_unknown_cost', null, null, 'visitor_chat', 'anthropic/claude-sonnet-5.5', 'probe unknown',
      'large', null, null, false, null, 100, true);
  end loop;
  -- fn_it_engineer_model_spend settles findings and may notify, so it is not called here (a probe must be incapable of
  -- paging anyone). Its new selection is run as written in the routine, and the routine is read back to carry it.
  if not exists (select 1 from public.ai_cost_log a
                  where a.occurred_at > now() - interval '24 hours' and a.cost_aed is null and a.cost_usd_reported is null
                    and not a.cached and coalesce(a.model_used, 'none') <> 'none' and a.fn = 'zz_probe_unknown_cost'
                  group by a.fn, a.task_class having count(*) >= 5)
     or pg_get_functiondef('public.fn_it_engineer_model_spend()'::regprocedure) not like '%unpriced:%' then
    bad := bad || 'the idle-floor reader does not name 5 unpriced calls'::text;
  end if;

  -- each of the three models that had no model_rate row now prices a known call above zero
  foreach m in array array['anthropic/claude-sonnet-5.5', 'google/gemini-3.8-flash:online', 'perplexity/sonar'] loop
    c := public.fn_llm_log('zz_probe_unknown_cost', null, null, 'visitor_chat', m, 'probe rate', 'large', 1000, 100, false, null, 100, true);
    if coalesce(c, 0) <= 0 then bad := bad || (m || ' still prices a known call at ' || coalesce(c::text, 'null')); end if;
  end loop;

  -- the backfill (counted by its own marker, so the verdict says what it changed)
  select count(*), coalesce(sum(cost_aed), 0) into n_fix, aed_fix from public.ai_cost_log
   where model_selected_because like '%re-priced 13 Oct 2026 from model_rate%';
  select count(*) into n_unk from public.ai_cost_log where model_selected_because like '%tokens unknown, not zero (13 Oct 2026)%';
  if exists (select 1 from public.ai_cost_log where model_used in ('anthropic/claude-sonnet-5.5', 'google/gemini-3.8-flash:online', 'perplexity/sonar')
              and fn <> 'zz_probe_unknown_cost' and cost_aed = 0 and not cached and (prompt_tokens > 0 or output_tokens > 0)) then
    bad := bad || 'a known call on the three models is still booked at AED 0'::text;
  end if;

  raise exception 'CHK<<%>>', case when cardinality(bad) = 0 then 'PROBE OK' else 'PROBE FAILED ' || array_to_string(bad, '; ') end
    || ' backfill_repriced=' || n_fix || ' backfill_aed=' || round(aed_fix, 4) || ' made_unknown=' || n_unk;
end $p$;
