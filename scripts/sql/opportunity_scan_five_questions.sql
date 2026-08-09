-- ROW #3 s29 — the opportunity scan asks two of the five questions it is supposed to ask.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   s29-scan-five-questions  MISSING  2 of 5 question class(es) appear among 9 opportunit(ies)/90d;
--                                     missing: growing industries, rising keywords, weak competitors
-- 
-- fn_opportunity_scan finds underserved categories and unmet demand — both off v_supply_gap — plus
-- a cost anomaly. Three of the five questions the spec names have never been asked, and the data to
-- ask them has been sitting there:
-- 
--   marketing_category_demand   26 rows: category, inquiries_90d, suppliers, has_seo_page
--   competitor                  27 rows, ALL 27 carrying a written `weakness`, 21 of them at low or
--                               medium threat
--   category_keyword            keyword patterns per category slug
-- 
-- Three blocks are added in exactly the shape of the three already there — `insert … select … where
-- not exists`, deduplicated on the open title, incrementing the same counter.
-- 
-- ── EACH ONE SAYS WHAT THE DATA SAYS, AND NOT MORE ──────────────────────────────────────────────
-- "Growing industries" is the question; the answer available is demand against supply, not a trend.
-- marketing_category_demand carries a 90-day count and a supplier count and no time series, so the
-- proposal states the sector's demand against its supply and calls it under-supplied. It does not
-- say "growing", because nothing here measures growth and a scan that claims a trend it cannot see
-- is worse than one that reports the level it can.
-- 
-- The supply threshold is the company's own: fn_exec_meeting targets 860 approved suppliers as "10
-- in each of 86 categories", so a category below ten is under-supplied by the company's own standard
-- rather than by one invented here.
-- 
-- Measured before writing, so none of the three is dead code: 2 categories have demand and fewer
-- than ten suppliers, 2 have demand and no SEO page, and 21 competitors have a stated weakness at
-- low or medium threat.

CREATE OR REPLACE FUNCTION public.fn_opportunity_scan()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0;
begin
  -- underserved categories that already hold a viable pool: ready demand, no action
  for r in select * from v_supply_gap where status='READY - not yet invited' order by sendable desc limit 10 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'underserved_category','Untapped pool: '||r.name,
      r.name||' holds '||r.sendable||' sendable suppliers and zero invitations sent. The pool is already sufficient for the 10-approved target.',
      jsonb_build_object('slug',r.slug,'sendable',r.sendable,'approved',r.approved),
      least(100, r.sendable/5.0), 'low', 0.8, 'intel_director'
    where not exists (select 1 from opportunity o where o.title='Untapped pool: '||r.name and o.status='open');
    if found then n := n+1; end if;
  end loop;

  -- categories where knowledge exists but no supply: capability ahead of market
  for r in select * from v_supply_gap where status='NO POOL - must source from scratch' limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'unmet_demand','Whitespace: '||r.name,
      'A fully briefed category expert exists for '||r.name||' with zero suppliers anywhere in the pool. Either a genuine market gap worth owning, or a category to retire.',
      jsonb_build_object('slug',r.slug,'sendable',0), 40,'high',0.5,'market_analyst'
    where not exists (select 1 from opportunity o where o.title='Whitespace: '||r.name and o.status='open');
    if found then n := n+1; end if;
  end loop;

  -- cost opportunity
  if (select count(*) filter (where could_be_cheaper) from ai_cost_log where occurred_at>now()-interval '30 days') > 10 then
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'cost_saving','Over-specified AI calls',
      (select count(*) filter (where could_be_cheaper)||' of '||count(*)||' calls in the last 30 days could have been served by a cheaper model.' from ai_cost_log where occurred_at>now()-interval '30 days'),
      '{}'::jsonb, 60,'low',0.9,'optimisation_eng'
    where not exists (select 1 from opportunity where title='Over-specified AI calls' and status='open');
    if found then n := n+1; end if;
  end if;

  -- ── THE THREE QUESTIONS THE SCAN NEVER ASKED ─────────────────────────────────────────────────

  -- GROWING INDUSTRIES — asked as demand against supply, which is what the data supports. Below ten
  -- suppliers is the company's own standard: 860 approved = 10 in each of 86 categories.
  for r in select m.category, coalesce(m.inquiries_90d,0) inq, coalesce(m.suppliers,0) sup
             from marketing_category_demand m
            where coalesce(m.inquiries_90d,0) >= 1 and coalesce(m.suppliers,0) < 10
            order by coalesce(m.inquiries_90d,0) desc, coalesce(m.suppliers,0) asc limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'sector_demand','Sector under-supplied: '||r.category,
      'The '||r.category||' industry drew '||r.inq||' inquir(y/ies) in 90 days against '||r.sup
      ||' supplier(s) on the platform, below the standard of ten per category. Demand in this sector '
      ||'is running ahead of the supply able to answer it.',
      jsonb_build_object('category',r.category,'inquiries_90d',r.inq,'suppliers',r.sup,'target_suppliers',10),
      least(100, r.inq*10.0), 'medium', 0.7, 'market_analyst'
    where not exists (select 1 from opportunity o
                       where o.title='Sector under-supplied: '||r.category and o.status='open');
    if found then n := n+1; end if;
  end loop;

  -- RISING KEYWORDS — search demand that lands on no page. has_seo_page is recorded per category and
  -- category_keyword holds the patterns that point at it.
  for r in select m.category, coalesce(m.inquiries_90d,0) inq,
                  (select count(*) from category_keyword k where k.slug = m.category and not coalesce(k.negative,false)) kw
             from marketing_category_demand m
            where not coalesce(m.has_seo_page,false) and coalesce(m.inquiries_90d,0) >= 1
            order by coalesce(m.inquiries_90d,0) desc limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'search_demand','Keyword demand with no page: '||r.category,
      case when r.kw > 0 then r.kw||' tracked keyword pattern(s) point at '||r.category else 'Search queries for '||r.category end
      ||', which drew '||r.inq||' inquir(y/ies) in 90 days and has no SEO page. The query demand is '
      ||'real and lands nowhere.',
      jsonb_build_object('category',r.category,'inquiries_90d',r.inq,'keyword_patterns',r.kw,'has_seo_page',false),
      least(100, r.inq*8.0), 'low', 0.7, 'market_analyst'
    where not exists (select 1 from opportunity o
                       where o.title='Keyword demand with no page: '||r.category and o.status='open');
    if found then n := n+1; end if;
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
      case lower(r.threat_level) when 'medium' then 55 else 35 end, 'medium', 0.6, 'intel_director'
    where not exists (select 1 from opportunity o
                       where o.title='Weak competitor: '||r.name and o.status='open');
    if found then n := n+1; end if;
  end loop;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('opportunity_scan',now(),now(),'ok',jsonb_build_object('found',n),
    'Opportunity scan: '||n||' new opportunity(ies) detected without being asked.');
  return jsonb_build_object('found',n);
end $function$
;
