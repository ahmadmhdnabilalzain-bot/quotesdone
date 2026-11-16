-- PROBE (pure, no DDL, writes nothing) for the_supplier_outreach_duty_never_slows_a_suppliers_page.sql (it_engineer, 16 Nov 2026).
-- Run after that file is applied (or with it in one rolled-back transaction on the LOCAL database). It only reads, and always
-- ends in raise exception 'CHK<<json>>'; the json carries counts and milliseconds, never a name or an address.
--   1. fn_supplier_invite_candidates carries enable_nestloop=off; the twin rule is plpgsql; enqueue counts the pool from the set.
--   2. The twin rule answers exactly as the rule written out as a query: on every claimed company, on every listing that shares a
--      claimed company's name key (the only listings that can have a twin), on 500 other listings, and on a name with no key.
--   3. The set rule and the per-row rule count the same pool (enqueue's number did not move).
--   4. The candidates call over every class returns inside 3 s (it took 9.3-13.2 s on production before; 0.7 s LOCAL after),
--      and none of its rows has a registered twin.
do $$
declare fail text := ''; v_cfg text[]; v_lang text; v_enq text; v_checked int; v_differ int; v_set int; v_row int;
        v_t0 timestamptz; v_ms int; v_cands int; v_twins int;
begin
  select p.proconfig into v_cfg from pg_proc p where p.oid = 'public.fn_supplier_invite_candidates(integer,text[])'::regprocedure;
  if not ('enable_nestloop=off' = any (coalesce(v_cfg, '{}'))) then fail := fail || 'fn_supplier_invite_candidates lost enable_nestloop=off; '; end if;
  select l.lanname into v_lang from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = 'public.fn_supplier_listing_has_registered_twin(bigint,text)'::regprocedure;
  if v_lang <> 'plpgsql' then fail := fail || 'the twin rule is ' || v_lang || ', so it is re-planned per listing again; '; end if;
  v_enq := pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure);
  if v_enq not like '%select count(*) into v_pool from public.fn_supplier_invite_eligible_ids();%' then
    fail := fail || 'enqueue_supplier_invites does not count the pool from the set rule; '; end if;

  -- 2. the rule as a query, against the routine
  with keys as (select public.fn_company_registration_name_key(o.company_name) as k from public.leads o
                 where o.claimed and not coalesce(o.is_demo, false)),
       probe as (
         select l.id, l.company_name from public.leads l where l.claimed
         union
         select l.id, l.company_name from public.leads l
          where public.fn_company_registration_name_key(l.company_name) in (select k from keys where k is not null)
         union
         (select l.id, l.company_name from public.leads l where not coalesce(l.claimed, false) order by l.id limit 500)
         union all
         select -1, '...' union all select -1, null)
  select count(*),
         count(*) filter (where public.fn_supplier_listing_has_registered_twin(p.id, p.company_name) is distinct from
           (public.fn_company_registration_name_key(p.company_name) is not null
            and exists (select 1 from public.leads o
                         where o.claimed and o.id is distinct from p.id and not coalesce(o.is_demo, false)
                           and public.fn_company_registration_name_key(o.company_name) = public.fn_company_registration_name_key(p.company_name))))
    into v_checked, v_differ from probe p;
  if v_differ <> 0 then fail := fail || v_differ || ' listing(s) where the twin rule answers differently from its own statement; '; end if;
  if v_checked < 502 then fail := fail || 'only ' || v_checked || ' listings checked (expected at least 502); '; end if;

  -- 3. the pool, both ways
  select count(*) into v_set from public.fn_supplier_invite_eligible_ids();
  select count(*) into v_row from public.leads l where public.fn_supplier_invite_eligible(l);
  if v_set <> v_row then fail := fail || 'the pool counts differ: set ' || v_set || ', row ' || v_row || '; '; end if;

  -- 4. the candidates call, timed
  v_t0 := clock_timestamp();
  select count(*), count(*) filter (where public.fn_supplier_listing_has_registered_twin(c.lead_id, c.company_name))
    into v_cands, v_twins from public.fn_supplier_invite_candidates(100000, null) c;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  if v_ms > 3000 then fail := fail || 'fn_supplier_invite_candidates took ' || v_ms || ' ms (bar 3,000); '; end if;
  if v_twins <> 0 then fail := fail || 'a candidate has a registered twin; '; end if;
  if v_cands = 0 and v_set > 0 then fail := fail || 'the candidate list is empty while the pool is not; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'twin_listings_checked', v_checked, 'pool_set', v_set, 'pool_row', v_row, 'candidates', v_cands, 'candidates_ms', v_ms);
end $$;
