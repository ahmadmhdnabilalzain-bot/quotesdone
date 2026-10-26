-- THE OPPORTUNITY SCAN WAS ABOUT TO REPORT DEMO FIXTURES AS MARKET DEMAND.
--
-- Caught at 03:25 UTC on 2026-08-10, twenty-five minutes before opportunity_scan_daily (`50 3 * * *`)
-- ran the NEW body for the first time. Two of its three new question blocks — "growing industries"
-- and "rising keywords" — key off marketing_category_demand.inquiries_90d, and that view counts
-- inquiries with no fixture filter:
--
--     category    inquiries_90d   of which brief_source='qd_demo_fixture'
--     hvac              6                          6
--     aluminium         1                          1
--
-- Seven of seven. The company has had ZERO real inquiries. At 03:50 the scan would have written
-- "Sector under-supplied: hvac — the hvac industry drew 6 inquir(y/ies) in 90 days against 0
-- supplier(s)... Demand in this sector is running ahead of the supply able to answer it" and put it
-- in front of the founder as detected market demand. Acting on it means buying hvac supplier
-- acquisition against demand that does not exist. This estate has already made exactly this mistake
-- repeatedly — every brief before the last one treated the seven fixtures as real demand.
--
-- FIXTURE-EXCLUSION IS CORRECT HERE, AND THE TEST IS THE ONE THE PART-5 BRIEF SET: exclude fixtures
-- from an OPERATIONAL ALERT that pages a human, never from a MEASUREMENT of whether the company
-- works. This is the former — the same call that was right for fn_resilience_watch. It is emphatically
-- not "teaching the scorer to skip fixtures": the scorer is untouched, and this change makes
-- s29-scan-five-questions HARDER. It will stay at 3 of 5 (underserved categories, unmet demand,
-- weak competitors) instead of reading a false 5 of 5 off seeded rows. It reaches 5 of 5 the day a
-- real inquiry arrives, which is the honest trigger.
--
-- Only the two demand-driven blocks change. marketing_category_demand itself is left alone: four
-- routines read it and re-pointing a shared view is a wider blast radius than this defect warrants.
-- The weak-competitor block is untouched — 21 of 27 tracked rivals carry a real recorded weakness.

create or replace function public.fn_opportunity_scan()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
  -- The two demand-driven ones count REAL inquiries. marketing_category_demand.inquiries_90d
  -- includes qd_demo_fixture rows, and all seven inquiries on this platform are fixtures, so the
  -- view's count is entirely seeded. A founder-facing opportunity must not rest on it.

  -- GROWING INDUSTRIES — asked as demand against supply, which is what the data supports. Below ten
  -- suppliers is the company's own standard: 860 approved = 10 in each of 86 categories.
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
      least(100, r.inq*10.0), 'medium', 0.7, 'market_analyst'
    where not exists (select 1 from opportunity o
                       where o.title='Sector under-supplied: '||r.category and o.status='open');
    if found then n := n+1; end if;
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
      least(100, r.inq*8.0), 'low', 0.7, 'market_analyst'
    where not exists (select 1 from opportunity o
                       where o.title='Keyword demand with no page: '||r.category and o.status='open');
    if found then n := n+1; end if;
  end loop;

  -- WEAK COMPETITORS — 27 tracked rivals, every one carrying a written weakness. A low or medium
  -- threat with a stated weakness is the shape of an opening; a high threat is a problem, not one.
  -- Untouched: this one rests on real competitor records, not on inquiries.
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
end $function$;
