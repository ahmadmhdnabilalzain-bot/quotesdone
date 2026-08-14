-- THE KEYWORD QUESTION WAS GUARDED ON A TABLE WITH NO ROWS
--
-- Row #3 §29 wants the opportunity scan to cover five named questions. Measured on production:
-- four are covered and "rising keywords" is not, and the reason is not that the question was never
-- written — it was written, in the `search_demand` branch, and it cannot fire.
--
-- That branch requires `i.real_inq >= 1`: at least one non-fixture inquiry in the category in 90
-- days. Production holds 0 inquiries of any kind. The loop has therefore never produced a row and
-- never can, for the same reason the check has never passed. An earlier session was right to refuse
-- to rest a founder-facing opportunity on marketing_category_demand's seeded counts; the cost was
-- that the question stopped being asked at all.
--
-- IT DID NOT NEED THE INQUIRIES. Measured on production today:
--   * category_keyword holds 1,597 positive patterns across all 86 supplier categories
--   * `pages` holds 18 rows and every one is site chrome — home, about, portal, workspace, legal.
--     There is not one category landing page.
--   * seo_categories holds 24 slugs in a different vocabulary ('electrical', 'flooring') from the
--     catalog's ('electrical-suppliers', 'flooring-suppliers'), so it covers none of them either.
-- So 86 of 86 categories carry tracked search keywords and have nowhere for that search to land.
-- That is a present, measurable gap and it needs no demand history to state.
--
-- WHAT IT DOES NOT CLAIM. It does not say the keywords are RISING. A rise is a trend and there is
-- no query-volume series on this platform to draw one from, so claiming it would be inventing a
-- measurement. The opportunity says what is true — patterns tracked, no page — and reports the real
-- 90-day inquiry count beside it, which is 0 today and says so.

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
  -- The demand-driven one counts REAL inquiries. marketing_category_demand.inquiries_90d includes
  -- qd_demo_fixture rows, so the view's count must not carry a founder-facing opportunity on its own.

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

  -- SEARCH KEYWORDS WITH NOWHERE TO LAND. Rewritten 14 Aug 2026: this used to require at least one
  -- real inquiry in the category, on a platform with zero inquiries, so it could not fire. The
  -- question does not need demand history — a tracked keyword pattern pointing at a category that
  -- has no landing page is a gap you can measure today. `pages` and `seo_categories` are BOTH
  -- checked because they are two different vocabularies and neither alone covers the catalog: pages
  -- holds site chrome under slugs like 'home' and 'portal', seo_categories holds 24 consumer trades
  -- ('electrical') that do not match the catalog's supplier slugs ('electrical-suppliers').
  -- The real 90-day inquiry count is carried in the evidence rather than used as a gate, so the
  -- opportunity states the demand it actually has instead of implying one it does not.
  for r in select c.slug, c.name,
                  (select count(*) from category_keyword k
                    where k.slug = c.slug and not coalesce(k.negative,false)) kw,
                  (select count(*) from inquiries q
                    where coalesce(nullif(q.category,''),'other') = c.slug
                      and q.created_at >= now() - interval '90 days'
                      and coalesce(q.brief_source,'') <> 'qd_demo_fixture') inq
             from catalog_supplier_categories c
            where not exists (select 1 from pages p where p.slug = c.slug)
              and not exists (select 1 from seo_categories s where s.slug = c.slug)
            order by 3 desc, c.slug limit 5 loop
    continue when r.kw = 0;
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'search_demand','Keyword demand with no page: '||r.name,
      r.kw||' tracked search keyword pattern(s) point at '||r.name||' and there is no landing page '
      ||'for it — neither a published page nor an SEO category entry. Real inquiries in this '
      ||'category over 90 days: '||r.inq||'. Whether that search volume is RISING is not measured '
      ||'anywhere on this platform, so this is a coverage gap, not a trend claim.',
      jsonb_build_object('category',r.slug,'keyword_patterns',r.kw,'inquiries_90d',r.inq,
                         'has_page',false,'has_seo_category',false,'trend_measured',false),
      least(100, r.kw*2.0), 'low', 0.7, 'market_analyst'
    where not exists (select 1 from opportunity o
                       where o.title='Keyword demand with no page: '||r.name and o.status='open');
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
