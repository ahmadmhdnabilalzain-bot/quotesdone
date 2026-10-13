-- A MODEL CALL WHOSE COST IS UNKNOWN IS BOOKED AS UNKNOWN, NEVER AS FREE.
-- Seat: sales_engineer. 13 Oct 2026. Follow-up of #1391 (ai_gateway's streamed calls book their real usage), at the
-- release operator's review.
--
-- WHY. #1391 makes a streamed call write its tokens from the stream's final usage chunk. A stream that ends or is
-- abandoned before that chunk has no usage, and the gateway now passes NULL for its tokens. fn_llm_log coalesced
-- NULL to 0 and priced the call at AED 0, so "unknown" was stored as "free" - exactly what had hidden every streamed
-- Sonnet 5.5 reply (ruling 1219) at AED 0 until #1391.
--
-- WHAT CHANGES
--   1. ai_cost_log.cached_in_tokens and cache_write_tokens accept NULL (defaults 0 kept). prompt_tokens, output_tokens
--      and cost_aed already did.
--   2. fn_llm_log: when BOTH token counts are NULL and the call was not a cache hit, the row stores NULL tokens, NULL
--      cache tokens and NULL cost_aed. Every other call is booked exactly as before.
--   3. fn_record_llm_attempt is NOT changed: llm_attempt already stores prompt/output tokens as given (NULL stays
--      NULL) and prices only when a count is present.
--   4. The spend readers say "unknown", not 0:
--        fn_it_engineer_model_spend (the USD 1 idle floor, ruling 986): a consumer with 5+ unpriced paid calls in 24 h
--          is its own finding (unpriced:<consumer>), so an unknown is never read as idle;
--        fn_accountant_unit_economics (monthly): llm_calls_unpriced, and a 'missing' line saying llm_cost_aed is a
--          lower bound;
--        fn_accountant_weekly_report_figures: ai_and_model_cost.unpriced and the same lower-bound sentence.
--   Read and NOT changed (they already treat NULL as unknown): v_openrouter_call_log marks cost_basis 'unpriced' and
--   cost_usd NULL; the cache ratios (prompt_cache_accounting.sql's v_ai_level_distribution, fn_what_if, and the
--   measuring query in prompt_cache_off_it_is_losing_money.sql) divide sum(cached_in_tokens) by sum(prompt_tokens),
--   and fn_llm_log sets both NULL together, so an unknown row leaves numerator and denominator alike.
--
-- Bodies copied from the live mirror (supabase/schema/full_schema) and changed only where marked. CREATE OR REPLACE
-- keeps every ACL. Applied at merge only; no transaction lines (apply_sql.mjs runs the file as one transaction).

set local lock_timeout = '3s';
alter table public.ai_cost_log alter column cached_in_tokens drop not null;
alter table public.ai_cost_log alter column cache_write_tokens drop not null;

-- 0. THE PRICE ROW #1380 MISSED (found by this file's probe). fn_llm_log prices from model_rate, not model_registry,
--    and anthropic/claude-sonnet-5.5 had no row, so every Sonnet reply (ruling 1219) would be booked at AED 0 even
--    with its tokens known. OpenRouter catalogue, 13 Oct 2026: USD 2.00 in / 10.00 out, cache read 0.10, write 2.50.
insert into public.model_rate
  (model, tier, in_aed_per_mtok, out_aed_per_mtok, usd_per_m_prompt, usd_per_m_output,
   cache_read_aed_per_mtok, cache_write_aed_per_mtok, id_verified, source_url, verified_at, note)
values ('anthropic/claude-sonnet-5.5', 'large', round(2.00 * 3.6725, 6), round(10.00 * 3.6725, 6), 2.00, 10.00,
        round(0.10 * 3.6725, 6), round(2.50 * 3.6725, 6), true, 'https://openrouter.ai/api/v1/models', date '2026-10-13',
        'Converted at 3.6725 AED/USD. Founder ruling 1219: every conversation reply. Without this row fn_llm_log priced '
        || 'every Sonnet 5.5 call at AED 0.')
on conflict (model) do update set in_aed_per_mtok = excluded.in_aed_per_mtok, out_aed_per_mtok = excluded.out_aed_per_mtok,
  usd_per_m_prompt = excluded.usd_per_m_prompt, usd_per_m_output = excluded.usd_per_m_output,
  cache_read_aed_per_mtok = excluded.cache_read_aed_per_mtok, cache_write_aed_per_mtok = excluded.cache_write_aed_per_mtok,
  verified_at = excluded.verified_at, note = excluded.note;

CREATE OR REPLACE FUNCTION public.fn_llm_log(p_fn text, p_dept text, p_agent text, p_task_class text, p_model text, p_because text, p_tier text, p_prompt_tokens integer, p_output_tokens integer, p_cached boolean, p_cache_key text, p_latency_ms integer, p_ok boolean, p_confidence numeric DEFAULT NULL::numeric, p_cached_in integer DEFAULT 0, p_cache_write integer DEFAULT 0, p_generation_id text DEFAULT NULL::text, p_cost_usd_reported numeric DEFAULT NULL::numeric, p_prompt_hash text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cr numeric; v_cw numeric;
        v_cheaper boolean := false; v_reason text; v_alt text; v_class text;
        v_plain int; v_read int; v_write int;
        v_alt_model text; v_alt_rate numeric; v_used_rate numeric;
        v_seat text; v_seat_basis text := 'unattributed';
        -- UNKNOWN IS NOT ZERO (13 Oct 2026, #1391 follow-up): a model call whose provider returned no usage block
        -- (a stream that ended or was abandoned before its usage chunk) is booked with NULL tokens and NULL cost.
        v_unknown boolean := p_prompt_tokens is null and p_output_tokens is null and not coalesce(p_cached, false);
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

  if v_unknown then
    v_cost := null; v_read := null; v_write := null;
  elsif not coalesce(p_cached,false) then
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
    case when v_unknown then null else coalesce(p_prompt_tokens,0) end, case when v_unknown then null else coalesce(p_output_tokens,0) end, coalesce(p_cached,false),
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
end $function$;

CREATE OR REPLACE FUNCTION public.fn_it_engineer_model_spend()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- UNPRICED CALLS (13 Oct 2026): a paid model call with no usage block has cost_aed NULL. sum() skips it, so the
  -- idle floor above would read it as free; it is named here instead, with its count, so unknown never reads as zero.
  for x in select a.fn || ':' || coalesce(a.task_class, 'unclassified') k, count(*) n, max(c.owner_seat) owner_seat
             from public.ai_cost_log a left join public.it_model_consumer c on c.consumer = a.fn || ':' || coalesce(a.task_class, 'unclassified')
            where a.occurred_at > now() - interval '24 hours' and a.cost_aed is null and a.cost_usd_reported is null
              and not a.cached and coalesce(a.model_used, 'none') <> 'none'
            group by 1 having count(*) >= 5 loop
    v_items := v_items || jsonb_build_object('item', 'unpriced:' || x.k, 'owner_seat', coalesce(x.owner_seat, 'it_engineer'), 'subject', x.k,
      'blast', 'internal', 'affected', x.n,
      'title', x.k || ': ' || x.n || ' paid model call(s) in 24 h returned no usage, so their cost is unknown and is not in the spend totals',
      'evidence', jsonb_build_object('calls_24h', x.n));
  end loop;

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
end $function$;

CREATE OR REPLACE FUNCTION public.fn_accountant_unit_economics(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_fx numeric;
  v_reveals int; v_fee numeric; v_gmv numeric; v_charged numeric; v_stripe numeric;
  v_ref_n int; v_ref_aed numeric; v_disp int; v_rfq int; v_llm numeric; v_msg numeric;
  v_sub_n int; v_sub_rev numeric; v_var numeric; v_missing text[] := '{}'; v_llm_unpriced int;
begin
  v_e := (v_m + interval '1 month')::date;
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed';
  select count(*), coalesce(sum(t.reveal_fee), 0), coalesce(sum(t.quote_amount), 0),
         coalesce(sum(t.total_charged), 0), coalesce(sum(t.stripe_fee_fils), 0) / 100.0
    into v_reveals, v_fee, v_gmv, v_charged, v_stripe
    from public.transactions t join public.customers c on c.id = t.customer_id
   where t.fee_status = 'paid' and t.revealed_at >= v_m and t.revealed_at < v_e
     and not (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email));
  select count(*), coalesce(sum(t.refund_amount_aed), 0) into v_ref_n, v_ref_aed
    from public.transactions t join public.customers c on c.id = t.customer_id
   where t.refund_confirmed_at >= v_m and t.refund_confirmed_at < v_e
     and not (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email));
  select count(*) into v_disp from public.stripe_dispute where livemode and first_seen_at >= v_m and first_seen_at < v_e;
  select count(*) into v_rfq from public.inquiries i join public.customers c on c.id = i.customer_id
   where i.created_at >= v_m and i.created_at < v_e and not (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email));
  select coalesce(sum(cost_aed), 0),
         count(*) filter (where cost_aed is null and not cached and coalesce(model_used, 'none') <> 'none')
    into v_llm, v_llm_unpriced from public.ai_cost_log where occurred_at >= v_m and occurred_at < v_e;
  select coalesce(sum(case when upper(currency) = 'USD' then amount * v_fx else amount end), 0) into v_msg
    from public.expense_entries where charged_on >= v_m and charged_on < v_e and vendor ~* '(twilio|resend|whatsapp|meta.*messag)';
  select count(*) into v_sub_n from public.leads where registration_paid_at >= v_m and registration_paid_at < v_e;
  select coalesce(sum(revenue_aed), 0) into v_sub_rev from public.gl_revenue_lines_measured
   where account_code = '4200' and entry_date >= v_m and entry_date < v_e;
  v_var := v_llm + v_msg;
  if v_reveals = 0 then v_missing := v_missing || text 'no paid reveal in the month, so per-reveal figures are undefined'; end if;
  if v_rfq = 0 then v_missing := v_missing || text 'no request in the month, so cost per request is undefined'; end if;
  if v_llm_unpriced > 0 then v_missing := v_missing || (v_llm_unpriced || ' model call(s) returned no usage: their cost is unknown, so llm_cost_aed is a lower bound'); end if;
  if v_sub_n = 0 then v_missing := v_missing || text 'no paid supplier subscription in the month'; end if;
  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'),
    'reveals', v_reveals, 'reveal_fee_revenue_aed', round(v_fee, 2), 'gmv_aed', round(v_gmv, 2),
    'take_rate', case when v_gmv > 0 then round(v_fee / v_gmv, 4) end,
    'revenue_per_reveal_aed', case when v_reveals > 0 then round(v_fee / v_reveals, 2) end,
    'stripe_fees_aed', round(v_stripe, 2), 'gross_charged_aed', round(v_charged, 2),
    'payment_cost_ratio', case when v_charged > 0 then round(v_stripe / v_charged, 4) end,
    'refunds', v_ref_n, 'refunded_aed', round(v_ref_aed, 2),
    'refund_rate', case when v_fee > 0 then round(v_ref_aed / v_fee, 4) end,
    'disputes', v_disp, 'dispute_rate', case when v_reveals > 0 then round(v_disp::numeric / v_reveals, 4) end,
    'requests', v_rfq, 'llm_cost_aed', round(v_llm, 2), 'llm_calls_unpriced', v_llm_unpriced, 'messaging_email_cost_aed', round(v_msg, 2),
    'variable_cost_per_request_aed', case when v_rfq > 0 then round(v_var / v_rfq, 2) end,
    'contribution_per_reveal_aed', case when v_reveals > 0 then round((v_fee - v_stripe - v_ref_aed - v_var) / v_reveals, 2) end,
    'subscriptions_paid', v_sub_n, 'subscription_revenue_aed', round(v_sub_rev, 2),
    'revenue_per_subscription_aed', case when v_sub_n > 0 then round(v_sub_rev / v_sub_n, 2) end,
    'missing', to_jsonb(v_missing),
    'basis', 'Paid reveals by revealed_at, refunds by refund_confirmed_at, ZZ DEMO customers excluded. Stripe fees from transactions.stripe_fee_fils. Variable cost = ai_cost_log.cost_aed + messaging/email vendor expenses (USD at gl_settings usd_to_aed). Contribution per reveal = (fee - Stripe fees - refunds - variable cost) / reveals. Numerators and denominators are all returned.');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_accountant_weekly_report_figures(p_start date, p_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tz text := 'Asia/Dubai';
  v_from timestamptz := (p_start::timestamp) at time zone v_tz;
  v_to   timestamptz := ((p_end + 1)::timestamp) at time zone v_tz;
  -- revenue
  v_txn_all int; v_txn_n int; v_rev numeric;
  v_stripe_all int; v_stripe_n int; v_stripe_last timestamptz;
  -- expenses
  v_ee_all int; v_ee_n int; v_ee_aed numeric;
  v_rcpt_all int; v_rcpt_n int;
  v_exp_all int; v_exp_active int;
  -- refunds
  v_ref_all int; v_ref_n int; v_ref_aed numeric; v_ref_settled int;
  -- payables
  v_ap_all int; v_ap_open int; v_ap_due numeric;
  -- ledger
  v_gl_all int; v_gl_lines int; v_gl_n int; v_dr numeric; v_cr numeric;
  v_cash numeric;
  -- platform cost
  v_ai_all int; v_ai_n int; v_ai_aed numeric; v_ai_models text; v_ai_unpriced int;
  v_lines jsonb;
begin
  select count(*) into v_txn_all from transactions;
  select count(*), coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
    into v_txn_n, v_rev
    from transactions
   where revealed_at >= v_from and revealed_at < v_to
     and coalesce(fee_status,'') <> 'refunded' and coalesce(refund_status,'') <> 'approved';

  select count(*), max(last_seen_at) into v_stripe_all, v_stripe_last from stripe_events;
  select count(*) into v_stripe_n from stripe_events
   where first_seen_at >= v_from and first_seen_at < v_to;

  select count(*) into v_ee_all from expense_entries;
  select count(*), coalesce(sum(amount), 0) into v_ee_n, v_ee_aed
    from expense_entries where charged_on between p_start and p_end;

  -- The receipts that ARRIVED. This is the counter-evidence to a zero on the line above, and it is
  -- why money-out can be 'unknown' rather than a comfortable 0.
  select count(*) into v_rcpt_all from inbound_messages where coalesce(to_email,'') ilike '%expense%';
  select count(*) into v_rcpt_n from inbound_messages
   where coalesce(to_email,'') ilike '%expense%' and created_at >= v_from and created_at < v_to;

  select count(*), count(*) filter (where active) into v_exp_all, v_exp_active from expenses;

  select count(*) into v_ref_all from refunds;
  select count(*), coalesce(sum(amount_fils), 0) / 100.0, count(*) filter (where settled_at is not null)
    into v_ref_n, v_ref_aed, v_ref_settled
    from refunds where requested_at >= v_from and requested_at < v_to;

  select count(*) into v_ap_all from ap_bills;
  select count(*), coalesce(sum(greatest(total - coalesce(amount_paid,0), 0)), 0)
    into v_ap_open, v_ap_due
    from ap_bills where coalesce(status,'') not in ('paid','void','cancelled');

  select count(*) into v_gl_all from gl_journal;
  select count(*) into v_gl_lines from gl_journal_lines;
  select count(*) into v_gl_n from gl_journal where entry_date between p_start and p_end;
  select coalesce(sum(l.debit),0), coalesce(sum(l.credit),0) into v_dr, v_cr
    from gl_journal_lines l join gl_journal j on j.id = l.journal_id
   where j.entry_date between p_start and p_end;
  select coalesce(sum(balance),0) into v_cash from gl_account_balances where code in ('1000','1050');

  select count(*) into v_ai_all from ai_cost_log;
  select count(*), coalesce(sum(cost_aed),0), coalesce(string_agg(distinct coalesce(model_used,'?'), ', '), ''),
         count(*) filter (where cost_aed is null and not cached and coalesce(model_used, 'none') <> 'none')
    into v_ai_n, v_ai_aed, v_ai_models, v_ai_unpriced
    from ai_cost_log where occurred_at >= v_from and occurred_at < v_to;

  v_lines := jsonb_build_object(

    -- MONEY IN -------------------------------------------------------------------------------
    'reveal_fee_revenue', jsonb_build_object(
      'aed', v_rev, 'n', v_txn_n, 'denom', v_txn_all,
      'basis', case when v_txn_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_txn_all = 0
        then 'public.transactions holds 0 rows in total, so no reveal fee has been recorded for this week or any other. The denominator is zero, not the numerator only.'
        else v_txn_n||' reveal(s) settled in the window, of '||v_txn_all||' transaction row(s) on record; refunded and refund-approved rows excluded.' end),

    'stripe_settlement_events', jsonb_build_object(
      'n', v_stripe_n, 'denom', v_stripe_all,
      'basis', case when v_stripe_all = 0 then 'true zero' else 'measured' end,
      -- ZERO CANNOT TELL A DEAD FEED FROM AN IDLE ONE. Say which this is.
      'note', case when v_stripe_all = 0
        then 'public.stripe_events holds 0 rows and has never recorded one, so 0 events this week is NOT evidence that the Stripe webhook is live and the week was quiet. It is equally consistent with the feed never having delivered. Treat the revenue line above as bounded by that.'
        else v_stripe_n||' event(s) first seen in the window, of '||v_stripe_all||' ever recorded; most recent activity '||coalesce(v_stripe_last::text,'unknown')||'.' end),

    -- MONEY OUT ------------------------------------------------------------------------------
    'expenses_filed_to_ledger', jsonb_build_object(
      'aed', v_ee_aed, 'n', v_ee_n, 'denom', v_ee_all,
      'basis', case when v_ee_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ee_all = 0
        then 'public.expense_entries holds 0 rows in total. Nothing has ever been filed against the chart of accounts. This is a statement about the bookkeeping, not about the spending.'
        else v_ee_n||' receipt(s) filed with a charge date in the window, of '||v_ee_all||' entr(ies) on record.' end),

    'receipts_received_at_the_expenses_inbox', jsonb_build_object(
      'n', v_rcpt_n, 'denom', v_rcpt_all,
      'basis', case when v_rcpt_all = 0 then 'true zero' else 'measured' end,
      'note', v_rcpt_n||' message(s) reached the expenses inbox inside the window; '||v_rcpt_all||' have reached it in total. Counted from public.inbound_messages, which records arrival, not amount.'),

    -- THE HONEST ONE. If receipts arrived and none was filed, the amount spent is NOT derivable,
    -- and printing 0 would be false in the direction that flatters the company.
    'cash_out_this_week', case
      when v_rcpt_n > v_ee_n then jsonb_build_object(
        'basis', 'unknown',
        'note', v_rcpt_n||' receipt(s) arrived at the expenses inbox inside this window and '||v_ee_n||
                ' were filed to the ledger, so the amount actually spent cannot be derived from any row. '||
                'It is UNKNOWN. It is not zero, and the gap ('||(v_rcpt_n - v_ee_n)||' unfiled receipt(s)) is the reason.')
      when v_ee_all = 0 and v_rcpt_all > 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'No receipt has ever been filed to the ledger while '||v_rcpt_all||' have arrived at the expenses inbox. '||
                'Spending for this window is UNKNOWN; a zero here would assert the company spent nothing, which the inbox contradicts.')
      when v_ee_all = 0 and v_rcpt_all = 0 then jsonb_build_object(
        'aed', 0, 'basis', 'true zero',
        'note', 'Both public.expense_entries and the expenses inbox hold 0 rows, so nothing was spent as far as any source row can say, over a denominator of zero.')
      else jsonb_build_object(
        'aed', v_ee_aed, 'n', v_ee_n, 'denom', v_ee_all, 'basis', 'measured',
        'note', 'Every receipt that arrived in the window ('||v_rcpt_n||') has a filed entry; the total is the sum of those entries.') end,

    'recurring_cost_schedule', case
      when v_exp_all = 0 and v_rcpt_all > 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'public.expenses holds 0 rows, so no recurring cost is on record -- while the expenses inbox holds '||v_rcpt_all||
                ' vendor receipt(s), which is direct evidence that recurring costs exist. The monthly run rate is UNKNOWN, not zero.')
      when v_exp_all = 0 then jsonb_build_object(
        'n', 0, 'denom', 0, 'basis', 'true zero',
        'note', 'public.expenses holds 0 rows and no receipt has arrived to contradict that.')
      else jsonb_build_object(
        'n', v_exp_active, 'denom', v_exp_all, 'basis', 'measured',
        'note', v_exp_active||' active recurring cost(s) of '||v_exp_all||' on record.') end,

    -- REFUNDS --------------------------------------------------------------------------------
    'refunds_requested', jsonb_build_object(
      'aed', v_ref_aed, 'n', v_ref_n, 'denom', v_ref_all, 'settled', v_ref_settled,
      'basis', case when v_ref_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ref_all = 0
        then 'public.refunds holds 0 rows in total. No refund has ever been requested, so nothing was decided and nothing was declined -- this is an empty table, not a clean queue.'
        else v_ref_n||' requested in the window ('||v_ref_settled||' settled), of '||v_ref_all||' on record. Every refund decision belongs to the CEO (ceo_standing_grant accountant.refund_decision, max_amount_aed 0).' end),

    -- PAYABLES -------------------------------------------------------------------------------
    'outstanding_bills', jsonb_build_object(
      'aed', v_ap_due, 'n', v_ap_open, 'denom', v_ap_all,
      'basis', case when v_ap_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ap_all = 0
        then 'public.ap_bills holds 0 rows, so 0 outstanding means NO BILL HAS BEEN ENTERED -- it is not a statement that nothing is owed. The '||v_rcpt_all||' receipt(s) in the expenses inbox are evidence to the contrary.'
        else v_ap_open||' open bill(s) of '||v_ap_all||' on record, '||to_char(v_ap_due,'FM999,999,990.00')||' AED still due.' end),

    -- CASH -----------------------------------------------------------------------------------
    'cash_position', case
      when v_gl_lines = 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'The general ledger holds 0 posted lines, and the database carries no bank feed or statement balance. The 1000 Cash & Bank and 1050 Stripe Clearing accounts therefore read 0.00 because NOTHING HAS BEEN POSTED, which is the absence of bookkeeping and not a bank balance. Cash position is UNKNOWN.')
      else jsonb_build_object(
        'aed', v_cash, 'denom', v_gl_lines, 'basis', 'measured',
        'note', 'Sum of the 1000 Cash & Bank and 1050 Stripe Clearing balances across '||v_gl_lines||' posted ledger line(s). It is a book balance, not a confirmed bank statement.') end,

    -- LEDGER ---------------------------------------------------------------------------------
    'journal_entries_posted', jsonb_build_object(
      'n', v_gl_n, 'denom', v_gl_all, 'debits', v_dr, 'credits', v_cr,
      'basis', case when v_gl_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_gl_all = 0
        then 'public.gl_journal holds 0 entries. Debits 0.00 equal credits 0.00, and a trial balance that balances across ZERO entries proves nothing about the books -- it proves there are none. 30 accounts and 6 expense mappings are configured and unused.'
        else v_gl_n||' entr(ies) dated inside the window, of '||v_gl_all||' on record; debits '||to_char(v_dr,'FM999,999,990.00')||' against credits '||to_char(v_cr,'FM999,999,990.00')||
             case when v_dr = v_cr then ' -- balanced.' else ' -- OUT OF BALANCE by '||to_char(abs(v_dr-v_cr),'FM999,999,990.00')||'.' end end),

    -- PLATFORM COST --------------------------------------------------------------------------
    'ai_and_model_cost', jsonb_build_object(
      'aed', v_ai_aed, 'n', v_ai_n, 'denom', v_ai_all, 'models', v_ai_models, 'unpriced', v_ai_unpriced,
      'basis', case when v_ai_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ai_all = 0
        then 'public.ai_cost_log holds 0 rows.'
        else v_ai_n||' model call(s) inside the window, of '||v_ai_all||' logged in total, costing '||to_char(v_ai_aed,'FM999,999,990.00')||
             ' AED. Models used: '||coalesce(nullif(v_ai_models,''),'none in this window')||
             case when v_ai_unpriced > 0 then ' '||v_ai_unpriced||' call(s) returned no usage, so their cost is unknown and this total is a lower bound.' else '' end||
             case when v_ai_models = 'none' then '. Every logged call resolved to model_used=''none'', so this zero is a real measured zero: the paid route was refused, not that the work was free.' else '.' end end)
  );

  return jsonb_build_object(
    'window', jsonb_build_object('start', p_start, 'end', p_end, 'timezone', v_tz,
                                 'iso', to_char(p_start,'IYYY-"W"IW')),
    'lines', v_lines,
    'measured_at', now());
end;$function$;

