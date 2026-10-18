-- EVERY MODEL CALL CARRIES ITS PROMPT HASH, AND SPEND IS WATCHED BY CLASS, AGAINST THE IDLE FLOOR AND THE REPLAY BACKLOG.
-- Seat: it_engineer. 5 Oct 2026, before the founder lifts the model hold. Source: the LLM burn audit of 5 Oct 2026,
-- "Guards: which exist and which are missing" 1-4. Alerts only, never caps (founder_instruction 987).
--
-- MEASURED (production, 5 Oct 2026, read-only):
--   * the repeats rule of fn_it_engineer_model_spend keys on ai_cost_log.cache_hit_key, which was null on all 3,397
--     rows of the last 30 days (the gateway sets it only for a cacheable route, and think() turns caching off). The
--     rule could never fire. Every row now carries prompt_hash (the gateway's sha256 of fn + system + conversation).
--   * nothing compared a class's USD a day with what it is expected to cost; the daily anomaly check's 14-day p90 is 0
--     at the lift, so its AED 20 floor (~USD 5.4) sits above the USD 1-2 idle ceiling (ruling 986) for the first days.
--   * nothing watched the replay backlog: rows claimed per hour, or rows retried more than once.
--   * the 11,686 ai_gateway runs of 28-29 Sep (R6) had no named caller. Measured from function_edge_logs: one Node
--     client on a du (EITC) address in the UAE, ~1 call a second, HTTP 200 in ~1 s; the 6,198 knowledge rows
--     re-embedded in that window (sales_knowledge 4,706, it_engineer 336, support 308, accountant 284, ceo 282,
--     marketing 282) match scripts/kb/verified_packs.mjs and embed_sales_knowledge.mjs, which call
--     ai_gateway {action:'embed'} - the free in-region gte-small path that writes no ai_cost_log row. Not a paid
--     loop: an embed is never routed to a model, hold or no hold. The gateway now puts the caller's claimed fn and
--     action on every run row (ai_gateway/index.ts), so the next burst names itself.
--
-- WHAT THIS CHANGES
--   1. ai_cost_log.prompt_hash, written by fn_llm_log (p_prompt_hash; the 18-argument signature is replaced, the
--      argument defaults to null so site_assistant's call keeps working unchanged).
--   2. fn_it_engineer_model_spend: repeats keyed on prompt_hash, paid rows only (model 'none' is a refusal, not a
--      purchase); class_spend (24 h USD against it_model_consumer.expected_usd_day, default USD 0.10); idle_floor
--      (USD 1.00 in 24 h estate-wide, below the USD 1-2 ceiling so it speaks first); replay_stalled, replay_slow and
--      replay_retries over reasoning_held_question.
--
-- Deploy order: apply THIS first, then deploy ai_gateway (a gateway that sends p_prompt_hash to the old signature
-- would have its cost rows refused by PostgREST, and rpcSafe would swallow it).
-- Probe: scripts/sql/every_model_call_carries_its_prompt_hash_and_spend_is_watched_by_class_probe.sql
-- Prevented by: scripts/checks/the_repeat_alert_keys_on_a_prompt_hash_every_row_carries.test.mjs

alter table public.ai_cost_log add column if not exists prompt_hash text;
create index if not exists ai_cost_log_prompt_hash_idx on public.ai_cost_log (prompt_hash, occurred_at) where prompt_hash is not null;
alter table public.it_model_consumer add column if not exists expected_usd_day numeric;
comment on column public.it_model_consumer.expected_usd_day is
  'What this consumer is expected to cost in USD a day. fn_it_engineer_model_spend flags a day above twice this (USD 0.10 when unset). An alert, never a cap (founder_instruction 987).';

drop function if exists public.fn_llm_log(text, text, text, text, text, text, text, integer, integer, boolean, text, integer, boolean, numeric, integer, integer, text, numeric);

-- From the_accountant_gets_a_daily_openrouter_ledger_that_names_the_seat_that_spent_it.sql (canonical, byte-equal to
-- production) with one argument and one column added: p_prompt_hash -> ai_cost_log.prompt_hash.
create function public.fn_llm_log(p_fn text, p_dept text, p_agent text, p_task_class text, p_model text, p_because text,
  p_tier text, p_prompt_tokens integer, p_output_tokens integer, p_cached boolean, p_cache_key text, p_latency_ms integer,
  p_ok boolean, p_confidence numeric default null, p_cached_in integer default 0, p_cache_write integer default 0,
  p_generation_id text default null, p_cost_usd_reported numeric default null, p_prompt_hash text default null)
returns numeric
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cr numeric; v_cw numeric;
        v_cheaper boolean := false; v_reason text; v_alt text; v_class text;
        v_plain int; v_read int; v_write int;
        v_alt_model text; v_alt_rate numeric; v_used_rate numeric;
        v_seat text; v_seat_basis text := 'unattributed';
begin
  v_class := coalesce(nullif(trim(coalesce(p_task_class,'')), ''), case
    when p_fn ~* 'agent_brain|dept_plan|exec_agents|reflect|conductor'   then 'agent_reasoning'
    when p_fn ~* 'cos_execute|secretary|chief'                            then 'chief_of_staff_decision'
    when p_fn ~* 'knowledge|kb_|canon_eval|research|exam'                 then 'knowledge_research'
    when p_fn ~* 'extract|parse|ocr'                                      then 'document_extraction'
    when p_fn ~* 'classif|categor|intent|route'                           then 'category_classification'
    when p_fn ~* 'draft|content|blog|marketing|social'                    then 'content_drafting'
    when p_fn ~* 'quote|rfq|supplier|procure'                             then 'procurement_reasoning'
    else 'general_drafting' end);

  -- WHO SPENT IT. Declaration first, standing binding second, honest silence third.
  if nullif(btrim(coalesce(p_agent,'')),'') is not null
     and exists (select 1 from public.org_agents a where a.agent_key = btrim(p_agent)) then
    v_seat := btrim(p_agent); v_seat_basis := 'declared';
  else
    select b.seat into v_seat from public.llm_seat_binding b where b.fn = p_fn;
    if v_seat is not null then v_seat_basis := 'bound'; else v_seat_basis := 'unattributed'; end if;
  end if;

  v_read  := greatest(coalesce(p_cached_in,0), 0);
  v_write := greatest(coalesce(p_cache_write,0), 0);
  v_plain := greatest(coalesce(p_prompt_tokens,0) - v_read - v_write, 0);

  if not coalesce(p_cached,false) then
    select in_aed_per_mtok, out_aed_per_mtok, cache_read_aed_per_mtok, cache_write_aed_per_mtok
      into v_in, v_out, v_cr, v_cw
      from model_rate where model = p_model;
    if v_in is not null then
      v_cost := round( v_plain/1000000.0 * v_in
                     + v_read /1000000.0 * coalesce(v_cr, v_in * 0.10)
                     + v_write/1000000.0 * coalesce(v_cw, v_in * 1.25)
                     + coalesce(p_output_tokens,0)/1000000.0 * v_out, 6);
    end if;
  end if;

  select deterministic_alternative into v_alt from model_policy where task_class = v_class;
  if v_alt is not null and v_alt <> '' then
    v_cheaper := true; v_reason := 'A deterministic path exists for this task class: ' || v_alt;
  elsif not coalesce(p_cached,false) then
    select mr.model, mr.in_aed_per_mtok into v_alt_model, v_alt_rate
      from model_rate mr
     where mr.in_aed_per_mtok is not null
     order by mr.in_aed_per_mtok asc
     limit 1;
    select mr.in_aed_per_mtok into v_used_rate from model_rate mr where mr.model = p_model;
    if v_alt_model is not null and v_used_rate is not null
       and v_alt_rate * 2 <= v_used_rate then
      v_cheaper := true;
      v_reason := v_alt_model || ' costs ' || round(v_used_rate / nullif(v_alt_rate,0), 1)
               || 'x less on input than ' || p_model
               || ' (' || v_alt_rate || ' vs ' || v_used_rate || ' AED/Mtok). '
               || 'Whether it is good enough for this task class is a policy decision, not a fact - '
               || 'this flag is the question, not the answer.';
    end if;
  end if;

  insert into ai_cost_log (fn, dept_key, agent_key, task_class, model_used, model_selected_because,
    tier, prompt_tokens, output_tokens, cached, cache_hit_key, latency_ms, cost_aed,
    could_be_cheaper, cheaper_reason, ok, confidence, cached_in_tokens, cache_write_tokens,
    generation_id, cost_usd_reported, seat, seat_basis, prompt_hash)
  values (p_fn, p_dept, p_agent, v_class, p_model, p_because, p_tier,
    coalesce(p_prompt_tokens,0), coalesce(p_output_tokens,0), coalesce(p_cached,false),
    p_cache_key, p_latency_ms, v_cost, v_cheaper, v_reason, coalesce(p_ok,true),
    case when p_confidence is null then null
         when p_confidence >= 0 and p_confidence <= 1   then p_confidence
         when p_confidence > 1  and p_confidence <= 100 then round(p_confidence / 100.0, 4)
         else null end,
    v_read, v_write,
    nullif(btrim(coalesce(p_generation_id,'')),''), p_cost_usd_reported, v_seat, v_seat_basis,
    nullif(btrim(coalesce(p_prompt_hash, '')), ''))
  -- The generation id is unique. A retried write of the SAME provider charge must not create a
  -- second row that the reconciliation would then count twice.
  on conflict (generation_id) where generation_id is not null do nothing;

  return v_cost;
end $fn$;
revoke execute on function public.fn_llm_log(text, text, text, text, text, text, text, integer, integer, boolean, text, integer, boolean, numeric, integer, integer, text, numeric, text) from public, anon, authenticated;
grant execute on function public.fn_llm_log(text, text, text, text, text, text, text, integer, integer, boolean, text, integer, boolean, numeric, integer, integer, text, numeric, text) to service_role;

-- From every_model_credit_consumer_is_listed_and_a_runaway_is_flagged.sql (canonical). The first two rules are
-- unchanged; the repeats rule keys on prompt_hash; four rules are new. Every one FLAGS through fn_it_duty_settle and
-- nothing here stops, slows or caps a call (founder_instruction 987).
create or replace function public.fn_it_engineer_model_spend()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare x record; v_items jsonb := '[]'::jsonb;
  -- ponytail: USD 0.10 a day is it_engineer's default expectation for a consumer nobody has priced; set
  -- it_model_consumer.expected_usd_day to replace it. USD 1.00 is the idle floor, below ruling 986's USD 1-2 ceiling.
  c_default_usd constant numeric := 0.10; c_idle_floor_usd constant numeric := 1.00;
  v_fx numeric := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);
  v_usd numeric; v_hold boolean; v_held int; v_claimed_1h int; v_claimed_3h int; v_retried int;
begin
  -- a think() surface is listed by construction (it lives in reasoning_held_question); ai_cost_log fn:task_class must be registered
  for x in select a.fn || ':' || coalesce(a.task_class, 'unclassified') k, count(*) n, max(a.seat) seat from public.ai_cost_log a
            where a.occurred_at > now() - interval '24 hours' and a.fn is not null
              and not public.fn_it_model_consumer_listed(a.fn, a.task_class)
            group by 1 loop
    v_items := v_items || jsonb_build_object('item', 'unlisted:' || x.k, 'owner_seat', 'ceo', 'subject', x.k, 'blast', 'internal', 'affected', x.n,
      'title', x.k || ' called a model ' || x.n || ' time(s) in 24 h and is not in the model-consumer inventory (it_model_consumer)',
      'evidence', jsonb_build_object('calls_24h', x.n, 'seat', x.seat));
  end loop;

  for x in with h as (select a.fn || ':' || coalesce(a.task_class, 'unclassified') k,
                             count(*) filter (where a.occurred_at > now() - interval '1 hour') last_hour,
                             count(*) filter (where a.occurred_at <= now() - interval '1 hour') / 168.0 mean_hour
                        from public.ai_cost_log a where a.occurred_at > now() - interval '7 days 1 hour' and a.fn is not null group by 1)
           select h.*, c.owner_seat from h left join public.it_model_consumer c on c.consumer = h.k
            where h.last_hour > greatest(30, 5 * h.mean_hour) loop
    v_items := v_items || jsonb_build_object('item', 'runaway:' || x.k, 'owner_seat', coalesce(x.owner_seat, 'ceo'), 'subject', x.k,
      'blast', 'internal', 'affected', x.last_hour,
      'title', x.k || ' made ' || x.last_hour || ' model calls in the last hour against a usual ' || round(x.mean_hour, 1) || ' an hour: a loop until shown otherwise',
      'evidence', jsonb_build_object('last_hour', x.last_hour, 'mean_hour_7d', round(x.mean_hour, 2)));
  end loop;

  -- REPEATS: the same prompt PAID for 5 or more times in an hour. prompt_hash is on every row (the cache key column was null
  -- on all of them); a refusal (model 'none') and a cache hit are not purchases.
  for x in select a.fn || ':' || coalesce(a.task_class, 'unclassified') k, a.prompt_hash key, count(*) n, max(c.owner_seat) owner_seat
             from public.ai_cost_log a left join public.it_model_consumer c on c.consumer = a.fn || ':' || coalesce(a.task_class, 'unclassified')
            where a.occurred_at > now() - interval '1 hour' and not a.cached and a.prompt_hash is not null and a.model_used <> 'none'
            group by 1, 2 having count(*) >= 5 loop
    v_items := v_items || jsonb_build_object('item', 'repeat:' || x.k || ':' || left(x.key, 12), 'owner_seat', coalesce(x.owner_seat, 'ceo'),
      'subject', x.k, 'blast', 'internal', 'affected', x.n,
      'title', x.k || ' paid for the same prompt ' || x.n || ' times in the last hour',
      'evidence', jsonb_build_object('prompt_hash', x.key, 'calls', x.n));
  end loop;

  -- CLASS SPEND: a consumer's last 24 hours in USD against twice what it is expected to cost a day.
  for x in select a.fn || ':' || coalesce(a.task_class, 'unclassified') k,
                  sum(coalesce(a.cost_usd_reported, a.cost_aed / v_fx)) usd, count(*) n,
                  max(c.owner_seat) owner_seat, max(c.expected_usd_day) expected
             from public.ai_cost_log a left join public.it_model_consumer c on c.consumer = a.fn || ':' || coalesce(a.task_class, 'unclassified')
            where a.occurred_at > now() - interval '24 hours' and a.fn is not null
            group by 1
           having sum(coalesce(a.cost_usd_reported, a.cost_aed / v_fx)) > 2 * coalesce(max(c.expected_usd_day), c_default_usd) loop
    v_items := v_items || jsonb_build_object('item', 'class_spend:' || x.k, 'owner_seat', coalesce(x.owner_seat, 'ceo'), 'subject', x.k,
      'blast', 'internal', 'affected', x.n,
      'title', x.k || ' cost USD ' || round(x.usd, 2) || ' in 24 h against an expected USD ' || coalesce(x.expected, c_default_usd) || ' a day',
      'evidence', jsonb_build_object('usd_24h', round(x.usd, 4), 'calls_24h', x.n, 'expected_usd_day', coalesce(x.expected, c_default_usd),
                                     'expected_is_default', x.expected is null));
  end loop;

  -- THE IDLE FLOOR: the whole estate above USD 1 in 24 hours. The daily anomaly check has no history at the lift (its
  -- p90 is 0, its AED 20 floor is ~USD 5.4), so this is what speaks in the first days.
  select coalesce(sum(coalesce(a.cost_usd_reported, a.cost_aed / v_fx)), 0) into v_usd
    from public.ai_cost_log a where a.occurred_at > now() - interval '24 hours';
  if v_usd > c_idle_floor_usd then
    v_items := v_items || jsonb_build_object('item', 'idle_floor', 'owner_seat', 'it_engineer', 'subject', 'estate', 'blast', 'internal',
      'affected', 1, 'title', 'model spend was USD ' || round(v_usd, 2) || ' in the last 24 hours, above the USD ' || c_idle_floor_usd
        || ' floor set under the USD 1-2 idle ceiling (ruling 986)',
      'evidence', jsonb_build_object('usd_24h', round(v_usd, 4), 'floor_usd', c_idle_floor_usd,
        'top', (select jsonb_agg(t) from (select a.fn || ':' || coalesce(a.task_class, 'unclassified') k,
                  round(sum(coalesce(a.cost_usd_reported, a.cost_aed / v_fx)), 4) usd
                  from public.ai_cost_log a where a.occurred_at > now() - interval '24 hours' group by 1 order by 2 desc limit 5) t)));
  end if;

  -- THE REPLAY BACKLOG: held questions drain once the hold lifts. Stalled = nothing claimed in 3 hours with the gate
  -- open; slow = at the last hour's rate it takes more than 48 hours; retries = 5 or more rows already tried twice.
  v_hold := coalesce(public.fn_kernel_paid_provider_gate('hold-probe/not-a-model') ->> 'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state');
  select count(*) filter (where status = 'held'),
         count(*) filter (where last_attempt_at > now() - interval '1 hour'),
         count(*) filter (where last_attempt_at > now() - interval '3 hours'),
         count(*) filter (where status = 'held' and attempts >= 2)
    into v_held, v_claimed_1h, v_claimed_3h, v_retried
    from public.reasoning_held_question where status = 'held' or last_attempt_at > now() - interval '3 hours';
  if not v_hold and v_held > 0 and v_claimed_3h = 0 then
    v_items := v_items || jsonb_build_object('item', 'replay_stalled', 'owner_seat', 'it_engineer', 'subject', 'reasoning_held_question',
      'blast', 'internal', 'affected', v_held,
      'title', v_held || ' held question(s) wait and none was claimed in 3 hours although the model gate is open',
      'evidence', jsonb_build_object('held', v_held, 'claimed_3h', 0));
  elsif not v_hold and v_claimed_1h > 0 and v_held > 48 * v_claimed_1h then
    v_items := v_items || jsonb_build_object('item', 'replay_slow', 'owner_seat', 'it_engineer', 'subject', 'reasoning_held_question',
      'blast', 'internal', 'affected', v_held,
      'title', v_held || ' held question(s) drain at ' || v_claimed_1h || ' an hour: more than 48 hours to clear',
      'evidence', jsonb_build_object('held', v_held, 'claimed_1h', v_claimed_1h, 'hours_to_clear', round(v_held::numeric / v_claimed_1h, 1)));
  end if;
  if v_retried >= 5 then
    v_items := v_items || jsonb_build_object('item', 'replay_retries', 'owner_seat', 'it_engineer', 'subject', 'reasoning_held_question',
      'blast', 'internal', 'affected', v_retried,
      'title', v_retried || ' held question(s) have been tried twice or more: each try is a full multi-call think()',
      'evidence', jsonb_build_object('retried', v_retried,
        'by_surface', (select jsonb_object_agg(surface, n) from (select surface, count(*) n from public.reasoning_held_question
                        where status = 'held' and attempts >= 2 group by 1) s)));
  end if;

  return jsonb_build_object('settled', public.fn_it_duty_settle('model_spend', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_model_spend() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_model_spend() to service_role;

update public.seat_duty set what = 'Model calls by consumer: an unlisted consumer, a loop (5x its usual hour), a repeated paid prompt, a class above twice its expected USD a day, the estate above the USD 1 idle floor, and a stalled, slow or retrying replay backlog are findings for the owning seat. Alerts only.'
 where duty = 'it_engineer.model_spend';

notify pgrst, 'reload schema';

-- Verdict row (DDL in this file, so no raise).
select case
  when to_regprocedure('public.fn_llm_log(text,text,text,text,text,text,text,integer,integer,boolean,text,integer,boolean,numeric,integer,integer,text,numeric,text)') is null
    then 'PROBE FAILED: fn_llm_log has no p_prompt_hash'
  when (select count(*) from pg_proc where proname = 'fn_llm_log' and pronamespace = 'public'::regnamespace) <> 1
    then 'PROBE FAILED: fn_llm_log has more than one overload'
  when position('a.prompt_hash' in pg_get_functiondef('public.fn_it_engineer_model_spend()'::regprocedure)) = 0
    then 'PROBE FAILED: the repeats rule does not key on prompt_hash'
  else 'PROBE OK' end as verdict;
