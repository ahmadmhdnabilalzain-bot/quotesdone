-- THE OPPORTUNITY SCAN DETECTS FROM MEASURED DATA AND NAMES ITS DETECTOR
--
-- Measured on production 3 Sep 2026: opportunity_scan_daily (job 165) was re-enabled on 2 Sep and
-- has not ticked since; the last body run (16 Aug) found 0; the 19 opportunities on file are all
-- dismissed and the newest is 14 Aug. Row #3 §29 reads "0 detected in 14d, 0 still open".
--
-- Two defects in the body, both fixed here:
--
--   1. DEDUPLICATION ONLY LOOKED AT OPEN ROWS. Every block guarded with `not exists (... status =
--      'open')`, so the day the founder dismissed all 19, the next tick would have re-raised the
--      same five weak competitors and the same three whitespace categories with the same words. A
--      real intelligence director does not re-file a dismissed memo the next morning. A title that
--      is open or pursuing, or was raised in the last 90 days in any status, is not raised again;
--      after 90 days the evidence is re-measured and may be raised afresh.
--
--   2. THE SCAN ONLY KNEW SIX SHAPES, and four of them wait on real inquiries the marketplace has
--      not yet received. Four deterministic detectors are added, each reading a table that carries
--      real rows today or the day the business does the thing:
--        coverage_gap   — v_supply_gap: a category below the company's own ten-approved standard
--                         with sendable suppliers already in the pool (58 categories today).
--        unanswered_rfq — inquiries older than 48h with no quote (0 today; fires on the first
--                         real RFQ nobody answers). Fixtures excluded: brief_source and the
--                         @example.invalid customer convention.
--        licence_expiry — approved suppliers whose trade licence expires within 60 days (0 today;
--                         1 approved supplier, licence to 2027-03-14).
--        kpi_gap        — active employee KPIs measured in the last 14 days below target, grouped
--                         per metric so one metric missed by five roles is one item (12 today).
--        sector_growth  — real inquiries per category, last 30 days against the 30 before; the
--                         "growing industries" question asked as growth, not as level.
--      Every row names its detector in detected_by as <role>/<detector>, so a reader can tell which
--      measurement raised it and which employee owns it.
--
-- No block reads the model. Nothing here is seeded: a detector with nothing to detect writes nothing.

create or replace function public.fn_opportunity_scan()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
-- by_det counts each detection against its detector, so the run says WHICH question produced what.
declare r record; n int := 0; by_det jsonb := '{}'::jsonb;
begin
  -- underserved categories that already hold a viable pool: ready demand, no action
  for r in select * from v_supply_gap where status='READY - not yet invited' order by sendable desc limit 10 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'underserved_category','Untapped pool: '||r.name,
      r.name||' holds '||r.sendable||' sendable suppliers and zero invitations sent. The pool is already sufficient for the 10-approved target.',
      jsonb_build_object('slug',r.slug,'sendable',r.sendable,'approved',r.approved),
      least(100, r.sendable/5.0), 'low', 0.8, 'intel_director/untapped_pool'
    where not exists (select 1 from opportunity o where o.title='Untapped pool: '||r.name
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('untapped_pool', coalesce((by_det->>'untapped_pool')::int,0)+1); end if;
  end loop;

  -- COVERAGE GAP — the company's own standard is ten approved suppliers per category (860 = 10 x 86).
  -- A category below it with sendable suppliers already acquired is a gap the pool can close without
  -- buying a single new lead. Ranked by the size of the pool that is waiting.
  for r in select g.slug, g.name, g.sendable, g.invited, g.approved, g.gap_to_target
             from v_supply_gap g
            where coalesce(g.approved,0) < 10 and coalesce(g.sendable,0) > 0
              and g.status <> 'READY - not yet invited'
            order by g.sendable desc, g.approved asc limit 10 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'underserved_category','Coverage gap: '||r.name,
      r.name||' has '||r.approved||' approved supplier(s) against the standard of ten, with '||r.invited
      ||' invited and '||r.sendable||' sendable suppliers already in the pool. The gap of '
      ||coalesce(r.gap_to_target, 10 - r.approved)||' can be closed from the pool the company already holds.',
      jsonb_build_object('slug',r.slug,'approved',r.approved,'invited',r.invited,'sendable',r.sendable,
                         'gap_to_target',coalesce(r.gap_to_target, 10 - r.approved),'target_approved',10),
      least(100, coalesce(r.gap_to_target, 10 - r.approved) * 10.0), 'medium', 0.8, 'intel_director/coverage_gap'
    where not exists (select 1 from opportunity o where o.title='Coverage gap: '||r.name
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('coverage_gap', coalesce((by_det->>'coverage_gap')::int,0)+1); end if;
  end loop;

  -- categories where knowledge exists but no supply: capability ahead of market
  for r in select * from v_supply_gap where status='NO POOL - must source from scratch' limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'unmet_demand','Whitespace: '||r.name,
      'A fully briefed category expert exists for '||r.name||' with zero suppliers anywhere in the pool. Either a genuine market gap worth owning, or a category to retire.',
      jsonb_build_object('slug',r.slug,'sendable',0), 40,'high',0.5,'market_analyst/whitespace'
    where not exists (select 1 from opportunity o where o.title='Whitespace: '||r.name
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('whitespace', coalesce((by_det->>'whitespace')::int,0)+1); end if;
  end loop;

  -- UNANSWERED RFQ — demand the supply base did not answer. Real inquiries only: the fixture brief
  -- source and the @example.invalid customer convention are both excluded, so a rehearsal never
  -- reads as lost demand. 0 today; this fires on the first real RFQ that waits 48 hours.
  for r in select i.id, i.rfq_no, i.category, i.created_at,
                  round(extract(epoch from (now() - i.created_at))/3600) hours,
                  g.name cat_name, coalesce(g.sendable,0) sendable, coalesce(g.invited,0) invited
             from inquiries i
             left join v_supply_gap g on g.slug = i.category
             left join customers c on c.id = i.customer_id
            where i.created_at < now() - interval '48 hours'
              and i.completed_at is null and i.hired_supplier_id is null
              and coalesce(i.status,'') not in ('closed','cancelled','archived','expired','revealed')
              and coalesce(i.brief_source,'') <> 'qd_demo_fixture'
              and coalesce(c.email,'') not ilike '%@example.invalid'
              and not exists (select 1 from quotes q where q.inquiry_id = i.id)
            order by i.created_at limit 10 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'unmet_demand',
      'Unanswered RFQ: '||coalesce('#'||r.rfq_no::text, left(r.id::text,8))||' ('||coalesce(r.cat_name, r.category, 'uncategorised')||')',
      'RFQ '||coalesce('#'||r.rfq_no::text, left(r.id::text,8))||' in '||coalesce(r.cat_name, r.category, 'an uncategorised trade')
      ||' has waited '||r.hours||' hour(s) with no quote. '||r.sendable||' sendable supplier(s) sit in that pool and '
      ||r.invited||' were invited: the demand is real and the supply base did not answer it.',
      jsonb_build_object('inquiry_id',r.id,'rfq_no',r.rfq_no,'category',r.category,'hours_waiting',r.hours,
                         'sendable',r.sendable,'invited',r.invited),
      least(100, 50 + r.hours/24.0*10), 'medium', 0.9, 'procurement/unanswered_rfq'
    where not exists (select 1 from opportunity o
                       where o.title='Unanswered RFQ: '||coalesce('#'||r.rfq_no::text, left(r.id::text,8))||' ('||coalesce(r.cat_name, r.category, 'uncategorised')||')'
                         and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('unanswered_rfq', coalesce((by_det->>'unanswered_rfq')::int,0)+1); end if;
  end loop;

  -- LICENCE EXPIRY — an approved supplier whose trade licence lapses within 60 days stops being
  -- sendable the day it does (CHAIN-02 suspends on expiry). Re-verifying before that day keeps the
  -- supplier and the category coverage it provides. 0 today: one approved supplier, licence to 2027.
  for r in select l.id, l.company_name, l.license_expiry, coalesce(l.sector,'') sector,
                  (l.license_expiry - current_date) days_left
             from leads l
            where l.approval_status = 'approved' and l.license_expiry is not null
              and l.license_expiry <= current_date + 60
              and coalesce(l.email,'') not ilike '%@example.invalid'
              and coalesce(l.company_name,'') not ilike 'ZZ DEMO%'
            order by l.license_expiry limit 20 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'supplier_retention','Licence expiring: '||coalesce(r.company_name, 'lead '||r.id::text),
      coalesce(r.company_name, 'Lead '||r.id::text)||' is approved and its trade licence '
      ||case when r.days_left < 0 then 'expired '||abs(r.days_left)||' day(s) ago' else 'expires in '||r.days_left||' day(s) ('||r.license_expiry||')' end
      ||'. Re-verify the licence now so the supplier stays sendable and the category keeps its coverage.',
      jsonb_build_object('lead_id',r.id,'license_expiry',r.license_expiry,'days_left',r.days_left,'sector',r.sector),
      least(100, greatest(40, 100 - r.days_left)), 'low', 0.95, 'trust_and_safety/licence_expiry'
    where not exists (select 1 from opportunity o where o.title='Licence expiring: '||coalesce(r.company_name, 'lead '||r.id::text)
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('licence_expiry', coalesce((by_det->>'licence_expiry')::int,0)+1); end if;
  end loop;

  -- KPI GAP — an active KPI measured in the last 14 days and below its target. Grouped per metric,
  -- because "Customer issues resolved within SLA" missed by five roles is one gap, not five. Metrics
  -- whose name says lower-is-better are excluded rather than mis-scored; every KPI on file today is
  -- higher-is-better (percent, counts, AED).
  for r in select k.metric, coalesce(k.unit,'') unit, max(k.target_value) target, max(k.actual_value) actual,
                  count(*) roles, string_agg(distinct k.agent_key, ', ' order by k.agent_key) agents,
                  round(100.0 * (max(k.target_value) - max(k.actual_value)) / nullif(max(k.target_value),0), 1) shortfall_pct
             from employee_kpi k
            where k.active and k.measured_at > now() - interval '14 days'
              and k.actual_value is not null and k.target_value is not null and k.target_value > 0
              and k.actual_value < k.target_value
              and k.metric !~* '(time|hours|days|cost|error|fail|latency|churn|backlog|spend)'
            group by k.metric, coalesce(k.unit,'')
            order by shortfall_pct desc nulls last limit 10 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'kpi_gap','KPI gap: '||r.metric,
      r.metric||' is at '||r.actual||' '||r.unit||' against a target of '||r.target||' '||r.unit
      ||' ('||coalesce(r.shortfall_pct::text,'?')||'% short), held by '||r.roles||' role(s): '||r.agents
      ||'. Closing this gap is the measured improvement the company is not yet getting.',
      jsonb_build_object('metric',r.metric,'unit',r.unit,'target',r.target,'actual',r.actual,
                         'shortfall_pct',r.shortfall_pct,'roles',r.roles,'agents',r.agents),
      least(100, coalesce(r.shortfall_pct, 0)), 'medium', 0.9, 'cpo/kpi_gap'
    where not exists (select 1 from opportunity o where o.title='KPI gap: '||r.metric
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('kpi_gap', coalesce((by_det->>'kpi_gap')::int,0)+1); end if;
  end loop;

  -- cost opportunity
  if (select count(*) filter (where could_be_cheaper) from ai_cost_log where occurred_at>now()-interval '30 days') > 10 then
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'cost_saving','Over-specified AI calls',
      (select count(*) filter (where could_be_cheaper)||' of '||count(*)||' calls in the last 30 days could have been served by a cheaper model.' from ai_cost_log where occurred_at>now()-interval '30 days'),
      '{}'::jsonb, 60,'low',0.9,'optimisation_eng/model_tiering'
    where not exists (select 1 from opportunity where title='Over-specified AI calls'
                        and (status in ('open','pursuing') or created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('model_tiering', coalesce((by_det->>'model_tiering')::int,0)+1); end if;
  end if;

  -- ── THE DEMAND-DRIVEN QUESTIONS ──────────────────────────────────────────────────────────────
  -- These count REAL inquiries. marketing_category_demand.inquiries_90d includes qd_demo_fixture
  -- rows, so it is never read for a founder-facing opportunity; the real count is taken here.

  -- GROWING INDUSTRIES, as level: demand against supply, below the company's ten-per-category standard.
  for r in select m.category, i.real_inq inq, coalesce(m.suppliers,0) sup
             from marketing_category_demand m
             cross join lateral (
               select count(*) real_inq from inquiries q
                where coalesce(nullif(q.category,''),'other') = m.category
                  and q.created_at >= now() - interval '90 days'
                  and coalesce(q.brief_source,'') <> 'qd_demo_fixture') i
            where i.real_inq >= 1 and coalesce(m.suppliers,0) < 10
            order by i.real_inq desc, coalesce(m.suppliers,0) asc limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'sector_demand','Sector under-supplied: '||r.category,
      'The '||r.category||' industry drew '||r.inq||' inquir(y/ies) in 90 days against '||r.sup
      ||' supplier(s) on the platform, below the standard of ten per category. Demand in this sector '
      ||'is running ahead of the supply able to answer it.',
      jsonb_build_object('category',r.category,'inquiries_90d',r.inq,'suppliers',r.sup,'target_suppliers',10),
      least(100, r.inq*10.0), 'medium', 0.7, 'market_analyst/sector_demand'
    where not exists (select 1 from opportunity o where o.title='Sector under-supplied: '||r.category
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('sector_demand', coalesce((by_det->>'sector_demand')::int,0)+1); end if;
  end loop;

  -- GROWING INDUSTRIES, as growth: real inquiries per category in the last 30 days against the 30
  -- before. A category needs at least two in the window and more than the prior window to be called
  -- growing; nothing here extrapolates.
  for r in select x.category, x.now_30, x.prev_30
             from (select coalesce(nullif(q.category,''),'other') category,
                          count(*) filter (where q.created_at >= now() - interval '30 days') now_30,
                          count(*) filter (where q.created_at >= now() - interval '60 days'
                                             and q.created_at <  now() - interval '30 days') prev_30
                     from inquiries q
                     left join customers c on c.id = q.customer_id
                    where q.created_at >= now() - interval '60 days'
                      and coalesce(q.brief_source,'') <> 'qd_demo_fixture'
                      and coalesce(c.email,'') not ilike '%@example.invalid'
                    group by 1) x
            where x.now_30 >= 2 and x.now_30 > x.prev_30
            order by (x.now_30 - x.prev_30) desc, x.now_30 desc limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'sector_growth','Growing industry: '||r.category,
      'The '||r.category||' industry raised '||r.now_30||' real inquir(y/ies) in the last 30 days against '
      ||r.prev_30||' in the 30 days before. Demand in this sector is growing on the platform''s own numbers.',
      jsonb_build_object('category',r.category,'inquiries_30d',r.now_30,'inquiries_prior_30d',r.prev_30),
      least(100, 30 + (r.now_30 - r.prev_30) * 10.0), 'medium', 0.8, 'market_analyst/sector_growth'
    where not exists (select 1 from opportunity o where o.title='Growing industry: '||r.category
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('sector_growth', coalesce((by_det->>'sector_growth')::int,0)+1); end if;
  end loop;

  -- RISING KEYWORDS — search demand that lands on no page. has_seo_page is recorded per category and
  -- category_keyword holds the patterns that point at it.
  for r in select m.category, i.real_inq inq,
                  (select count(*) from category_keyword k where k.slug = m.category and not coalesce(k.negative,false)) kw
             from marketing_category_demand m
             cross join lateral (
               select count(*) real_inq from inquiries q
                where coalesce(nullif(q.category,''),'other') = m.category
                  and q.created_at >= now() - interval '90 days'
                  and coalesce(q.brief_source,'') <> 'qd_demo_fixture') i
            where not coalesce(m.has_seo_page,false) and i.real_inq >= 1
            order by i.real_inq desc limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'search_demand','Keyword demand with no page: '||r.category,
      case when r.kw > 0 then r.kw||' tracked keyword pattern(s) point at '||r.category else 'Search queries for '||r.category end
      ||', which drew '||r.inq||' inquir(y/ies) in 90 days and has no SEO page. The query demand is '
      ||'real and lands nowhere.',
      jsonb_build_object('category',r.category,'inquiries_90d',r.inq,'keyword_patterns',r.kw,'has_seo_page',false),
      least(100, r.inq*8.0), 'low', 0.7, 'market_analyst/search_demand'
    where not exists (select 1 from opportunity o where o.title='Keyword demand with no page: '||r.category
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('search_demand', coalesce((by_det->>'search_demand')::int,0)+1); end if;
  end loop;

  -- WEAK COMPETITORS — 27 tracked rivals, every one carrying a written weakness. A low or medium
  -- threat with a stated weakness is the shape of an opening; a high threat is a problem, not one.
  for r in select c.name, coalesce(c.kind,'unclassified') kind, c.weakness, c.threat_level
             from competitor c
            where coalesce(btrim(c.weakness),'') <> ''
              and lower(coalesce(c.threat_level,'')) in ('low','medium')
            order by c.name limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'competitive_gap','Weak competitor: '||r.name,
      r.name||' ('||r.kind||', threat '||r.threat_level||') has a recorded weakness: '
      ||left(r.weakness, 240),
      jsonb_build_object('competitor',r.name,'threat_level',r.threat_level,'kind',r.kind),
      case lower(r.threat_level) when 'medium' then 55 else 35 end, 'medium', 0.6, 'intel_director/weak_competitor'
    where not exists (select 1 from opportunity o where o.title='Weak competitor: '||r.name
                        and (o.status in ('open','pursuing') or o.created_at > now() - interval '90 days'));
    if found then n := n+1; by_det := by_det || jsonb_build_object('weak_competitor', coalesce((by_det->>'weak_competitor')::int,0)+1); end if;
  end loop;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('opportunity_scan',now(),now(),'ok',jsonb_build_object('found',n,'by_detector',by_det),
    'Opportunity scan: '||n||' new opportunity(ies) detected without being asked'
    ||case when n > 0 then ' — '||(select string_agg(k||' '||v, ', ' order by k) from jsonb_each_text(by_det) e(k,v)) else '' end||'.');
  return jsonb_build_object('found',n,'by_detector',by_det);
end $function$;
