-- PROBE: THE CEO WRITES A ONE-PAGE STRATEGY MEMO EVERY MONTH. Seat: ceo. Instruction 1013 item 4.
--
-- Pure probe: no DDL. Run AFTER the_ceo_writes_a_one_page_strategy_memo_every_month.sql, as ONE query through
-- node scripts/qsql.mjs. Everything is inside a block that always raises, so nothing survives, including the
-- notifications row fn_notify_founder queues (pg_net sends only committed rows) - it cannot reach the founder.
-- Seeds: a ZZ DEMO memo for Jul 2026 betting on suppliers added in the real category 'aluminium-and-glass-suppliers' (lead_category.slug must name a catalogue category), target = what it already had + 1, and two ZZ DEMO
-- suppliers (source qd_demo_fixture, so leads.is_demo) in that category created in Aug 2026.
--
-- PROBE OK only if the Aug 2026 memo (p_include_demo true):
--   1. grades July's bet HIT with measured = what the category already had in Aug 2026 plus 2;
--   2. makes one bet with a metric, a category, and a target above its baseline;
--   3. carries the four sections in its body;
--   4. went through fn_notify_founder with kind ceo_strategy_memo and was emailed (a queued notifications row
--      of that kind exists), never as a WhatsApp page;
--   5. a second call for the same month returns already = true.
do $probe$
declare r jsonb; r2 jsonb; m public.ceo_strategy_memo; v_fail text := ''; v_l1 bigint; v_l2 bigint; v_before int;
begin
  v_before := public.fn_ceo_strategy_measure('suppliers_added', 'aluminium-and-glass-suppliers', date '2026-08-01', date '2026-08-31', true);
  insert into public.ceo_strategy_memo (month, facts, bet, grading, wording_source, body, include_demo)
  values (date '2026-07-01', '{}', jsonb_build_object('metric', 'suppliers_added', 'category', 'aluminium-and-glass-suppliers',
                                                      'baseline', v_before, 'target', v_before + 1, 'wording', 'ZZ DEMO bet'),
          '{"grade":"none"}', 'rule_based (model hold on)', 'ZZ DEMO', true);
  insert into public.leads (company_name, source, created_at) values ('ZZ DEMO Strategy Probe One', 'qd_demo_fixture', timestamptz '2026-08-10 10:00+04') returning id into v_l1;
  insert into public.leads (company_name, source, created_at) values ('ZZ DEMO Strategy Probe Two', 'qd_demo_fixture', timestamptz '2026-08-20 10:00+04') returning id into v_l2;
  insert into public.lead_category (lead_id, slug, is_primary, method) values (v_l1, 'aluminium-and-glass-suppliers', true, 'probe'), (v_l2, 'aluminium-and-glass-suppliers', true, 'probe');

  r := public.fn_ceo_strategy_memo(date '2026-08-01', true);
  select * into m from public.ceo_strategy_memo where month = date '2026-08-01';

  if r#>>'{grading,grade}' <> 'hit' or (r#>>'{grading,measured}')::int <> v_before + 2 then v_fail := v_fail || ' grading ' || coalesce(r->>'grading', 'null') || ';'; end if;
  if r#>>'{bet,metric}' is null or r#>>'{bet,category}' is null or (r#>>'{bet,target}')::int <= (r#>>'{bet,baseline}')::int
    then v_fail := v_fail || ' bet ' || coalesce(r->>'bet', 'null') || ';'; end if;
  if position('1. MARKET CHANGES' in m.body) = 0 or position('2. CATEGORY GROWTH' in m.body) = 0
     or position('3. THE BET FOR' in m.body) = 0 or position('4. LAST MONTH''S BET' in m.body) = 0 then v_fail := v_fail || ' body sections;'; end if;
  if coalesce((r#>>'{notify,emailed}')::boolean, false) is not true or r#>>'{notify,kind}' <> 'ceo_strategy_memo'
    then v_fail := v_fail || ' notify ' || coalesce(r->>'notify', 'null') || ';'; end if;
  if not exists (select 1 from public.notifications where kind = 'ceo_strategy_memo' and channel = 'email' and created_at >= now() - interval '1 minute')
     or exists (select 1 from public.notifications where kind = 'ceo_strategy_memo' and channel = 'whatsapp' and created_at >= now() - interval '1 minute')
    then v_fail := v_fail || ' notifications row;'; end if;
  r2 := public.fn_ceo_strategy_memo(date '2026-08-01', true);
  if coalesce((r2->>'already')::boolean, false) is not true then v_fail := v_fail || ' not idempotent;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: graded ' || (r#>>'{grading,grade}') || ' (' || (r#>>'{grading,measured}')
      || '), bet: ' || (r#>>'{bet,wording}') || ' | chars ' || length(m.body) else 'PROBE FAILED:' || v_fail end;
end $probe$;
