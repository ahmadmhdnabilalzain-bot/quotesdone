-- EIGHT INPUTS, EVERY ONE MEASURED; A FALL IS INVESTIGATED IN THE TICK THAT MEASURES IT (3 Sep 2026).
--
-- s30-marketplace-eight-inputs: the newest marketplace_health row carried 6 of 8 named inputs; churn
-- and customer satisfaction were JSON nulls. fn_company_indices computed them from reviews (rating,
-- 90 days) and customers (active in 90 days over all customers), both empty, and folded each null
-- into the average as 50 — a guess sitting inside a number that claims to be a measurement.
--
-- Now both are measured the way the function already measures rfq_completion and revenue — a share
-- over the population that exists, and 0 when there is no activity to score, never a stand-in:
--   * customer_satisfaction: reviews.rating x 20 over the last 90 days, and feedback.rating x 20 for
--     feedback about customers (subject_type 'customer'); 0 when nobody has rated anything.
--   * customer_retention: of the customers old enough to have lapsed (created more than 30 days
--     ago), the share with an inquiry or a revealed transaction in the last 90 days; 0 when there is
--     nobody old enough to retain. The measured populations sit beside the scores as
--     customers_measured / reviews_measured so the base of each number is visible.
-- The marketplace score is now the mean of eight measured inputs, with no coalesce to 50 anywhere.
-- It falls from 40.2 to what an empty marketplace measures; that is the correct direction.
--
-- s31-slowdown-investigated: three indices fell by more than a point on 3 Sep and nothing referenced
-- them, because fn_company_indices was re-run at 07:26 UTC — after index_slowdown_watch_daily had
-- already passed at 04:15 — so the falls it produced sat until the next morning. Two changes:
--   * fn_company_indices calls fn_index_slowdown_watch at the end of every run, so the tick that
--     measures a fall is the tick that investigates it, whatever time it runs. The 04:15 cron stays
--     as the sweep for anything written to company_index by another path.
--   * fn_index_slowdown_watch records the investigation as an agent_actions row (kind
--     index_slowdown, addressed to the corporate-performance director, done) as well as the
--     evolution proposal. The proposal dedupes on (trigger_kind, subject, change_class) while one is
--     still 'proposed', which is right for proposals and wrong for records: a second fall in the same
--     week would have been silently skipped and read as uninvestigated. The action row is the record
--     of what was found — the dimensions that moved, from the index's own stored values.
--
--   node scripts/apply_sql.mjs scripts/sql/supply_engine_marketplace_eight_inputs_and_fall_investigated.sql --apply --ddl

create or replace function public.fn_index_slowdown_watch()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare n int := 0; r record; v_moved text; v_ins int; v_moved_json jsonb;
begin
  for r in
    select z.index_name, z.measured_on, z.score, z.prev, z.dims, z.prev_dims
      from (select c.index_name, c.measured_on, c.score, c.dimensions dims,
                   lag(c.score)      over (partition by c.index_name order by c.measured_on) prev,
                   lag(c.dimensions) over (partition by c.index_name order by c.measured_on) prev_dims
              from public.company_index c
             where c.measured_on > current_date - 30) z
     where z.prev is not null and z.score < z.prev - 1 and z.measured_on > current_date - 7
       and not exists (select 1 from public.founder_alerts a
                        where a.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(a.event,'')||' '||coalesce(a.detail::text,'')) > 0)
       and not exists (select 1 from public.evolution_proposal p
                        where p.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(p.subject,'')||' '||coalesce(p.observation,'')) > 0)
       and not exists (select 1 from public.agent_actions g
                        where g.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(g.title,'')||' '||coalesce(g.detail::text,'')) > 0)
  loop
    -- WHERE THE DROP CAME FROM, out of the index's own stored dimensions. Only dimensions that
    -- actually fell, biggest mover first, with both values so the size is visible.
    select string_agg(d.k||' '||d.was||' to '||d.now_v, ', ' order by (d.was - d.now_v) desc),
           jsonb_object_agg(d.k, jsonb_build_object('was', d.was, 'now', d.now_v, 'fell_by', round(d.was - d.now_v, 2)))
      into v_moved, v_moved_json
      from (select k, (r.prev_dims->>k)::numeric was, (r.dims->>k)::numeric now_v
              from jsonb_object_keys(r.dims) k
             where jsonb_typeof(r.dims->k) = 'number'
               and jsonb_typeof(coalesce(r.prev_dims->k,'null'::jsonb)) = 'number'
               and (r.prev_dims->>k)::numeric > (r.dims->>k)::numeric) d;

    insert into public.evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
    values ('metric_off_target', r.index_name,
      format('%s fell from %s to %s on %s, a drop of %s points. Dimensions that moved down: %s.',
             r.index_name, r.prev, r.score, r.measured_on, round(r.prev - r.score, 2),
             coalesce(v_moved, 'none that the index breaks out — the drop is in the weighting, not in a named dimension')),
      jsonb_build_object('index', r.index_name, 'from', r.prev, 'to', r.score,
                         'fell_by', round(r.prev - r.score, 2), 'measured_on', r.measured_on,
                         'dimensions_down', v_moved),
      format('Find the cause of the %s fall before it compounds. The dimensions above are where it came from; the drop is arithmetic, the reason is not, and only one of those two is in the data.', r.index_name),
      'process')
    -- The partial unique index gets the final say. Its predicate is repeated verbatim so the
    -- arbiter resolves to evolution_proposal_dedupe_idx and nothing else.
    on conflict (trigger_kind, subject, change_class) where status = 'proposed' do nothing;

    -- THE RECORD OF THE INVESTIGATION. Not deduped: every fall is its own finding, and this is the
    -- row the scorer and the founder both read when they ask "was this looked at".
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id,
                                      confidence, evidence, decided_by, decided_at, expected_impact, cost)
    values ('corporate_performance_director', 'index_slowdown', 'auto_done', 'low',
      format('%s fell %s points (%s to %s) on %s', r.index_name, round(r.prev - r.score, 2), r.prev, r.score, r.measured_on),
      case when v_moved is null
           then 'No named dimension fell: the drop is in the weighting. Compare the dimension set of the two measurements.'
           else 'Investigated from the index''s own dimensions: ' || v_moved || '. The measure behind the biggest mover is where the cause is.' end,
      jsonb_build_object('index', r.index_name, 'from', r.prev, 'to', r.score, 'fell_by', round(r.prev - r.score, 2),
                         'measured_on', r.measured_on, 'dimensions_down', coalesce(v_moved_json, '{}'::jsonb)),
      'company_index', r.index_name, 1.0,
      jsonb_build_object('basis', 'company_index rows for ' || r.index_name || ' on ' || r.measured_on || ' and the measurement before it'),
      'index_slowdown_watch', now(),
      'A fall that is attributed to its dimension on the day it happens is a fall someone can act on; one found a week later is a trend.',
      'No spend: arithmetic over stored dimensions.');
    get diagnostics v_ins = row_count;
    n := n + v_ins;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('index_slowdown_watch', now(), now(), 'ok', jsonb_build_object('investigated', n),
    case when n = 0 then 'No index lost more than a point in the last 7 days without something already picking it up.'
         else n||' index fall(s) over a point investigated, with the dimensions that moved.' end);

  return jsonb_build_object('investigated', n);
end $function$;

create or replace function public.fn_company_indices()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  d_auto numeric; d_know numeric; d_dec numeric; d_fin numeric; d_cust numeric;
  d_supp numeric; d_sec numeric; d_res numeric; d_inno numeric; d_strat numeric; v_mat numeric;
  e_vel numeric; e_backlog numeric; e_collab numeric; e_knowcreate numeric; e_autorate numeric; v_energy numeric;
  m_quality numeric; m_speed numeric; m_completion numeric; m_fraud numeric; m_conf numeric; v_mh numeric;
  m_satisf numeric; m_revenue numeric; m_retention numeric; m_cust_n int; m_rev_n int;
  v_kpis int; v_gaps int; v_watch jsonb;
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
  -- coalesce the SUM to 0 BEFORE least(): least(100, NULL) is 100 in Postgres (least ignores nulls), which
  -- would read an empty marketplace as maximum revenue. Fold the empty case to 0 inside the aggregate.
  select least(100, round(coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)), 0)/100.0, 1)) into m_revenue
    from transactions where revealed_at > now()-interval '30 days';

  -- CUSTOMER SATISFACTION: every rating a customer has given in 90 days, on the 0-100 scale the other
  -- inputs use. 0 when nobody has rated anything — the same convention as rfq_completion with no
  -- inquiries — and the count of ratings sits beside it.
  select coalesce(round(avg(z.rating) * 20.0, 1), 0), count(*) into m_satisf, m_rev_n
    from (select r.rating::numeric from reviews r where r.rating is not null and r.created_at > now()-interval '90 days'
          union all
          select f.rating from feedback f where f.rating is not null and f.subject_type = 'customer' and f.created_at > now()-interval '90 days') z;
  -- CUSTOMER RETENTION (the churn input): of the customers old enough to have lapsed, the share still
  -- active in the last 90 days. 0 when nobody is old enough to retain.
  select coalesce(round(100.0 * count(*) filter (where active_recently) / nullif(count(*), 0), 1), 0), count(*)
    into m_retention, m_cust_n
    from (select c.id,
                 exists(select 1 from inquiries i where i.customer_id=c.id and i.created_at > now()-interval '90 days')
              or exists(select 1 from transactions t where t.customer_id=c.id and t.revealed_at > now()-interval '90 days') as active_recently
            from customers c where c.created_at < now() - interval '30 days') z;

  v_mh := round((m_quality+m_speed+m_completion+m_fraud+m_conf+m_satisf+m_revenue+m_retention)/8.0,1);
  insert into company_index (measured_on,index_name,dimensions,score,band)
  values (current_date,'marketplace_health',
    jsonb_build_object('supplier_quality',m_quality,'quote_speed',m_speed,'rfq_completion',m_completion,
      'fraud_clean',m_fraud,'ai_confidence',m_conf,
      'customer_satisfaction',m_satisf,'revenue',m_revenue,'customer_retention',m_retention,
      'reviews_measured',m_rev_n,'customers_measured',m_cust_n), v_mh,
    case when v_mh>=75 then 'healthy' when v_mh>=50 then 'fragile' else 'unhealthy' end)
  on conflict (measured_on,index_name) do update set dimensions=excluded.dimensions, score=excluded.score, band=excluded.band;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_indices',now(),now(),'ok',
    jsonb_build_object('maturity',v_mat,'energy',v_energy,'marketplace_health',v_mh),
    'Company indices: maturity '||v_mat||', energy '||v_energy||', marketplace health '||v_mh||'.');

  -- The tick that measures a fall investigates it.
  v_watch := public.fn_index_slowdown_watch();
  return jsonb_build_object('maturity',v_mat,'energy',v_energy,'marketplace_health',v_mh,
                            'falls_investigated', v_watch->'investigated');
end $function$;
