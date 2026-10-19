-- PROBE for the_sales_engineer_closes_the_loops_a_senior_sales_engineer_closes.sql (sales_engineer, ledger 1003 stage 2).
-- Never applied: it always raises CHK<<...>>, so every row it and the six duties write is rolled back. Run after the
-- file is applied, or concatenated after it in one transaction: node scripts/qsql.mjs <file + this probe>.
-- It seeds ONE ZZ DEMO request (customer and three suppliers all @example.invalid, is_demo) with two complete quotes and
-- one missing its warranty, plus two more requests in the same trade, runs every duty, reads what each one wrote, and
-- asserts that nothing reached the founder and no message went to an address that is not a fixture.
do $probe$
declare n0 bigint := (select count(*) from public.notifications where to_role in ('admin', 'founder'));
  fa0 bigint := (select count(*) from public.founder_alerts);
  h0 bigint := (select coalesce(max(id), 0) from public.agent_actions);
  v_c uuid; v_i uuid; v_l bigint[] := '{}'; v_id bigint; k int; r jsonb := '{}'::jsonb; v_fail text := '';
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  insert into public.customers (email, full_name) values ('zz-demo-se-probe@example.invalid', 'ZZ DEMO SE probe') returning id into v_c;
  for k in 1 .. 3 loop
    insert into public.inquiries (customer_id, category, emirate, trades, status, raw_input, brief_source, created_at)
    values (v_c, 'zz_demo_se_probe', 'Dubai', array['zz_demo_se_probe'], 'open', 'ZZ DEMO probe request ' || k, 'qd_demo_fixture', now() - interval '3 days')
    returning id into v_i;
  end loop;
  for k in 1 .. 3 loop
    insert into public.leads (company_name, email) values ('ZZ DEMO SE probe supplier ' || k, 'zz-demo-se-sup' || k || '@example.invalid')
    returning id into v_id;
    v_l := v_l || v_id;
  end loop;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, price_ex_vat, vat_amount, lead_time, validity, warranty, payment_terms, vat_treatment, created_at) values
    (v_i, v_l[1], 1000, 1000, 50, '2 weeks', '30 days', '12 months', '50/50', 'exclusive', now() - interval '3 days'),
    (v_i, v_l[2], 1200, 1200, 60, '1 week', '30 days', '12 months', '100% on delivery', 'exclusive', now() - interval '3 days'),
    (v_i, v_l[3],  900,  900, 45, '3 weeks', '30 days', null, '30 days credit', 'exclusive', now() - interval '3 days');
  fa0 := (select count(*) from public.founder_alerts);   -- the fixture's own inserts raise masking alerts; only the duties are measured

  r := r || jsonb_build_object('C03', public.fn_sales_engineer_comparison_report());
  r := r || jsonb_build_object('C04', public.fn_sales_engineer_onboarding_conversion());
  r := r || jsonb_build_object('C07', public.fn_sales_engineer_supply_gap_recruitment());
  r := r || jsonb_build_object('C12', public.fn_sales_engineer_negotiation_round());
  r := r || jsonb_build_object('C13', public.fn_sales_engineer_win_loss_review());
  r := r || jsonb_build_object('C14', public.fn_sales_engineer_framework_proposal());
  r := r || jsonb_build_object(
    'demo_report', (select jsonb_build_object('quotes', quotes_n, 'complete', complete_n, 'recommended_is_lowest_complete',
                       recommended_quote_id = (select id from public.quotes where inquiry_id = v_i and supplier_id = v_l[1]), 'delivered', delivered_at is not null)
                      from public.sales_engineer_comparison_report where inquiry_id = v_i),
    'rounds', (select coalesce(jsonb_object_agg(round, n), '{}'::jsonb) from (select round, count(*) n from public.sales_engineer_negotiation_round where inquiry_id = v_i group by round) x),
    'framework_drafted', (select count(*) from public.sales_engineer_framework_proposal where customer_id = v_c),
    'onboarding_week_rows', (select count(*) from public.sales_engineer_onboarding_week),
    -- ruling 1199: fn_seat_handoff files no handoff for a demo row, so a fixture's messages are recorded on the round
    -- and the report but can never be queued for delivery; any message from these duties to a non-fixture address fails
    'demo_handoffs_filed', (select count(*) from public.sales_engineer_negotiation_round where inquiry_id = v_i and handoff_id is not null)
                         + (select count(*) from public.sales_engineer_comparison_report where inquiry_id = v_i and delivery_handoff_id is not null),
    'deliveries_to_a_real_address', (select count(*) from public.agent_actions where id > h0 and kind = 'handoff' and detail->>'type' = 'delivery.request'
                                       and detail->>'msg_type' in ('comparison_ready', 'negotiation_clarify', 'negotiation_best_and_final')),
    'founder_notifications_added', (select count(*) from public.notifications where to_role in ('admin', 'founder')) - n0,
    'founder_alerts_added', (select count(*) from public.founder_alerts) - fa0);
  if (r->>'founder_notifications_added')::int <> 0 or (r->>'founder_alerts_added')::int <> 0 then v_fail := v_fail || 'reached the founder; '; end if;
  if (r->>'deliveries_to_a_real_address')::int <> 0 or (r->>'demo_handoffs_filed')::int <> 0 then v_fail := v_fail || 'wrote to a real address; '; end if;
  if coalesce((r->'demo_report'->>'quotes')::int, 0) <> 3 or not coalesce((r->'demo_report'->>'recommended_is_lowest_complete')::boolean, false)
     or not coalesce((r->'demo_report'->>'delivered')::boolean, false) then v_fail := v_fail || 'the levelled report is wrong; '; end if;
  if coalesce((r->'rounds'->>'clarify')::int, 0) <> 1 or coalesce((r->'rounds'->>'best_and_final')::int, 0) <> 1 then v_fail := v_fail || 'the rounds are wrong; '; end if;
  if (r->>'framework_drafted')::int <> 1 then v_fail := v_fail || 'no framework drafted; '; end if;
  if (r->>'onboarding_week_rows')::int = 0 then v_fail := v_fail || 'no onboarding week; '; end if;
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK ' else 'PROBE FAILED: ' || v_fail end || r::text;
end $probe$;
