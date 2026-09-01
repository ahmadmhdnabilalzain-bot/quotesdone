-- THE MARKETPLACE SCORE IS BUILT FROM ALL EIGHT INPUTS (org audit / blueprint s30-marketplace-eight-inputs).
--
-- MEASURED. fn_company_indices emitted only FIVE of the eight marketplace_health dimensions the spec names
-- (supplier_quality, quote_speed, rfq_completion, fraud_clean, ai_confidence); customer_satisfaction,
-- revenue and churn/retention were never computed, so the score was a five-input average and no cron run
-- could ever reach 8/8 — a structural gap, not a freshness one (its sibling s30-single-score is freshness).
--
-- THIS FILE adds the three missing dimensions, all DETERMINISTIC and model-free (no _shared/llm.ts, no
-- ai_gateway), computed from stored rows:
--   customer_satisfaction  mean review rating (1-5) over 90d scaled to 0-100; NULL when there are no
--                          reviews rather than a neutral guess (an unmeasured axis is not a satisfied one).
--   revenue                30-day platform fee income scaled to a 0-100 index; coalesced to 0, an honest
--                          zero on an untraded marketplace (the same way revenue_30d reads 0, not a mock).
--   customer_retention     share of customers active (an inquiry or a reveal) in the last 90 days; NULL
--                          when there are no customers. Matches the spec input 'churn' (regex churn|
--                          retention|lapsed) as its positive form: higher = healthier, consistent with the
--                          other dimensions the score averages.
-- The score now averages all EIGHT (the two nullable axes coalesce to a neutral 50 in the AVERAGE ONLY, the
-- same pattern line 65 already used for m_completion; the dimensions jsonb stores the raw value, so the
-- eight-inputs check honestly counts a dimension present only when it carries a real reading).
--
-- On an empty marketplace this raises coverage from 5/8 to 6/8 (revenue becomes an honest 0); satisfaction
-- and retention light up only once real customers, reviews and transactions exist. It changes no cron, no
-- ownership, no structure. CREATE OR REPLACE preserves the ACL — no grant/revoke here.
--
--   node scripts/apply_sql.mjs scripts/sql/the_marketplace_score_uses_all_eight_inputs.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_company_indices()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d_auto numeric; d_know numeric; d_dec numeric; d_fin numeric; d_cust numeric;
  d_supp numeric; d_sec numeric; d_res numeric; d_inno numeric; d_strat numeric; v_mat numeric;
  e_vel numeric; e_backlog numeric; e_collab numeric; e_knowcreate numeric; e_autorate numeric; v_energy numeric;
  m_quality numeric; m_speed numeric; m_completion numeric; m_fraud numeric; m_conf numeric; v_mh numeric;
  m_satisf numeric; m_revenue numeric; m_retention numeric;
  v_kpis int; v_gaps int;
begin
  select coalesce(100 - round(100.0*count(*) filter (where needs_founder)/nullif(count(*),0),1),100)
    into d_auto from org_tasks where status<>'done';
  select coalesce(round(100.0*count(*) filter (where validation_status not in ('unvalidated','unreviewed'))/nullif(count(*),0),1),0)
    into d_know from agent_knowledge;
  select coalesce(round(100.0*count(*) filter (where verdict='improved')
           /nullif(count(*) filter (where verdict in ('improved','no_change','worse')),0),1),50)
    into d_dec from outcome_record;
  select case when coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) > 0 then 60 else 10 end
    into d_fin from transactions where revealed_at > now()-interval '90 days';
  select case when count(*) > 0 then 50 else 10 end into d_cust from customers;
  select least(100, round(100.0*(select count(*) from v_supply_gap where approved>=10)/86.0,1)) into d_supp;
  select coalesce(round(100.0*count(*) filter (where ok)/nullif(count(*),0),1),50)
    into d_sec from health_checks where check_kind='http' and created_at > now()-interval '7 days';
  select round(100.0*count(*) filter (where last_tested is not null)/nullif(count(*),0),1)
    into d_res from continuity_plan;
  select least(100,(select count(*) from evolution_proposal)*5) into d_inno;
  select count(*) into v_kpis from employee_kpi where active;
  select count(*) into v_gaps from org_tasks where title like 'KPI missed:%' and status<>'done';
  d_strat := greatest(0, round(100.0 - 100.0*v_gaps/nullif(v_kpis,0), 1));

  v_mat := round((d_auto+d_know+d_dec+d_fin+d_cust+d_supp+d_sec+d_res+d_inno+d_strat)/10.0,1);
  insert into company_index (measured_on,index_name,dimensions,score,band)
  values (current_date,'company_maturity',
    jsonb_build_object('automation',d_auto,'knowledge_quality',d_know,'decision_accuracy',d_dec,
      'financial_health',d_fin,'customer_trust',d_cust,'supplier_ecosystem',d_supp,'security',d_sec,
      'operational_resilience',d_res,'innovation',d_inno,'strategic_execution',d_strat), v_mat,
    case when v_mat>=80 then 'mature' when v_mat>=60 then 'developing' when v_mat>=40 then 'early' else 'nascent' end)
  on conflict (measured_on,index_name) do update set dimensions=excluded.dimensions, score=excluded.score, band=excluded.band;

  select count(*) into e_vel from decision_log where created_at > now()-interval '7 days';
  select coalesce(round(100.0 - 100.0*count(*) filter (where created_at < now()-interval '14 days')/nullif(count(*),0),1),100)
    into e_backlog from org_tasks where status<>'done';
  select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1),50)
    into e_collab from review_chain where created_at > now()-interval '30 days';
  select least(100,count(*)) into e_knowcreate from agent_knowledge where updated_at > now()-interval '7 days';
  e_autorate := d_auto;
  v_energy := round((least(100,e_vel)+e_backlog+e_collab+e_knowcreate+e_autorate)/5.0,1);
  insert into company_index (measured_on,index_name,dimensions,score,band)
  values (current_date,'organizational_energy',
    jsonb_build_object('decision_velocity_7d',e_vel,'backlog_freshness',e_backlog,
      'collaboration_efficiency',e_collab,'knowledge_creation_7d',e_knowcreate,'automation_rate',e_autorate),
    v_energy, case when v_energy>=75 then 'high' when v_energy>=50 then 'steady' else 'slowing' end)
  on conflict (measured_on,index_name) do update set dimensions=excluded.dimensions, score=excluded.score, band=excluded.band;

  select coalesce(round(avg(reliability),1),0) into m_quality from supplier_score where reliability is not null;
  select coalesce(round(100.0*count(*) filter (where sent_at is not null and sent_at-created_at < interval '24 hours')
           /nullif(count(*),0),1),0) into m_speed from notifications where created_at > now()-interval '30 days';
  select coalesce(round(100.0*count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id))
           /nullif(count(*),0),1),0) into m_completion from inquiries i where i.created_at > now()-interval '30 days';
  select coalesce(100 - least(100,count(*)*5),100) into m_fraud from fraud_flags;
  select coalesce(round(avg(confidence)*100,1),50) into m_conf from decision_log where confidence is not null;
  -- THE THREE ADDED INPUTS. Deterministic, model-free; null (not a guess) when the axis is unmeasured.
  select round(avg(rating)*20.0, 1) into m_satisf
    from reviews where rating is not null and created_at > now()-interval '90 days';
  -- coalesce the SUM to 0 BEFORE least(): least(100, NULL) is 100 in Postgres (least ignores nulls), which
  -- would read an empty marketplace as maximum revenue. Fold the empty case to 0 inside the aggregate.
  select least(100, round(coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)), 0)/100.0, 1)) into m_revenue
    from transactions where revealed_at > now()-interval '30 days';
  select round(100.0*count(*) filter (where active_recently)/nullif(count(*),0), 1) into m_retention
    from (select c.id,
                 exists(select 1 from inquiries i where i.customer_id=c.id and i.created_at > now()-interval '90 days')
              or exists(select 1 from transactions t where t.customer_id=c.id and t.revealed_at > now()-interval '90 days') as active_recently
          from customers c) z;
  v_mh := round((m_quality+m_speed+coalesce(m_completion,0)+m_fraud+m_conf
                 +coalesce(m_satisf,50)+m_revenue+coalesce(m_retention,50))/8.0,1);
  insert into company_index (measured_on,index_name,dimensions,score,band)
  values (current_date,'marketplace_health',
    jsonb_build_object('supplier_quality',m_quality,'quote_speed',m_speed,'rfq_completion',m_completion,
      'fraud_clean',m_fraud,'ai_confidence',m_conf,
      'customer_satisfaction',m_satisf,'revenue',m_revenue,'customer_retention',m_retention), v_mh,
    case when v_mh>=75 then 'healthy' when v_mh>=50 then 'fragile' else 'unhealthy' end)
  on conflict (measured_on,index_name) do update set dimensions=excluded.dimensions, score=excluded.score, band=excluded.band;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_indices',now(),now(),'ok',
    jsonb_build_object('maturity',v_mat,'energy',v_energy,'marketplace_health',v_mh),
    'Company indices: maturity '||v_mat||', energy '||v_energy||', marketplace health '||v_mh||'.');
  return jsonb_build_object('maturity',v_mat,'energy',v_energy,'marketplace_health',v_mh);
end $function$;

commit;
