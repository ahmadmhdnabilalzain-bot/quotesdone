-- THE SERVICE GATE NEVER EMPTIES A TRADE (23 Sep 2026, agent: sales_engineer, SP-F-01 re-review).
--
-- THE DEFECT, AND IT IS A CLASS. an_inquiry_carries_the_services_it_names.sql made
-- fn_match_capability's p_services gate fire for the first time. The gate read the supplier's WHOLE
-- effective service list: if the inquiry named a service and the supplier's list covered none of it,
-- the supplier was dropped -- even when the supplier had named no service in that trade AT ALL. A
-- supplier who has said nothing at service level about a trade it declares is trade-level for that
-- trade, exactly like a supplier who has not opened the Services tab; the old gate treated silence as
-- a denial, and a whole trade went to zero reachable suppliers while every card still showed it.
--
-- MEASURED ON PRODUCTION, 23 Sep 2026, against the LIVE function (5 confirmed capability rows):
--   trade       reachable, trade level   reachable when the inquiry names that trade's services
--   aluminium              4                      4
--   doors                  4                      0      <-- whole trade unreachable
--   gypsum                 1                      1
--   painting               1                      0      <-- whole trade unreachable
-- doors: suppliers 130889/130890/130891/130895 declare {aluminium,doors} with five aluminium.* keys
-- plus the free-text word "Doors". painting: supplier 126512 declares {gypsum,painting} with five
-- gypsum.* keys plus the word «الدهانات».
--
-- WHY NOT FIX THE ROWS. The first attempt did: it rewrote «الدهانات» to painting.interior for one
-- supplier (a_confirmed_service_is_a_taxonomy_key_not_a_word.sql, which still stands -- a word an
-- active alias names IS that service and belongs in the list as a key). "Doors" cannot be fixed that
-- way and must not be: no active alias of any doors.* service names the bare word "Doors"
-- (they are "wooden door", "fire door", "rolling shutter", "ironmongery", "automatic door"), so
-- picking one would be a nearest-neighbour mapping, which the founder forbids -- exact trade match or
-- none. And "Doors" is not a stale hand-edit: it is the product's own intake vocabulary, offered as an
-- aluminium-interview checklist option (supabase/functions/inquiry_intake/interview.test.ts,
-- supabase/migrations_history/20260724153607_*.sql), so every rehearsal mints it again. A fix that
-- names a supplier and a word patches one row of a class.
--
-- THE FIX. The gate now asks, FOR EACH TRADE the inquiry named a service in and the supplier declares,
-- whether the supplier has named any service in THAT trade. It applies where the supplier has
-- something to say and stays out of the way where it has not. Nothing is loosened where the gate was
-- doing its job: a supplier that named doors.wooden_doors and nothing else is still excluded from a
-- doors.fire_doors inquiry -- it spoke, and it did not name that service. `why` names the trade it
-- passed at trade level in, so a trade-level pass is never mistaken for a service match.
--
-- PER TRADE, NOT PER INQUIRY. The first draft of this file unioned the prefixes of every trade the
-- inquiry named a service in and asked whether the supplier had named ANYTHING in that union. Re-review
-- finding A, 23 Sep 2026: that re-creates the defect for a multi-trade inquiry. A supplier silent on
-- doors but spoken-on for aluminium had a non-empty union, so the relaxation never fired, and
-- {doors.fire_doors, aluminium.tensile_structures} measured doors 6 -> 0. That is not a corner case --
-- it is the normal path. sales_engineer derives ONE key set from one brief across every trade of the
-- inquiry, so the backfilled rows carry keys across three, two and two trades respectively. The
-- single-trade reading would have gone green in the guard while the real path still reached nobody.
--
-- A NON-KEY IN p_services NO LONGER SWITCHES THE GATE OFF (re-review finding B). See the `named` CTE.
--
-- THIS IS A MATCHING-POLICY CHANGE, AND THE FOUNDER HAS NOT RULED ON IT. From 15 Sep 2026 a supplier's
-- silence at service level was read as a denial; from this file it is read as trade level. The founder's
-- own rule is untouched -- exact trade match or none, and no key is ever invented or mapped to a
-- neighbour -- but he decides policy, so this is raised to him rather than presented as a pure repair.
--
-- AFTER, measured 23 Sep 2026 WITHOUT applying anything: this file's body was run against production
-- as a plain read-only query with its parameters substituted as literals, so the numbers below are the
-- new gate's own output over the live rows rather than a prediction --
--   aluminium 4 -> 4, doors 4 -> 4, gypsum 1 -> 1, painting 1 -> 1. No trade falls to zero.
-- painting reaches its supplier again through the trade-level path, on the UNPATCHED row, which is the
-- point: the gate no longer needs a data fix to stop emptying a trade.
--
-- RE-MEASURED 23 Sep 2026 after finding A was fixed, same read-only method, on the set production held
-- at that moment (one confirmed supplier, 126512, declaring {gypsum, painting} with five gypsum keys
-- and the free-text «الدهانات»):
--   per trade                          gypsum   1 -> 1 before, 1 after
--                                      painting 1 -> 0 before, 1 after
--   TWO TRADES {gypsum, painting}, asking the 5 painting services NO confirmed supplier holds:
--                                      trade level 1, before 0, AFTER 1
--                                      why = "trades painting+gypsum · trade level in painting"
--   a non-key p_services {'Doors'}     trade level 1, before 0, after 1   (finding B)
-- The two-trade row is the finding-A case measured on production: the supplier has spoken on gypsum and
-- is silent on painting, so the union reading dropped it and the per-trade reading keeps it, and `why`
-- names painting as the trade it passed at trade level in.
--
-- THE EXCLUSION ARM COULD NOT BE MEASURED ON TODAY'S ROWS, and that is said rather than glossed: it
-- needs a supplier that HAS named services in a trade and is asked for one of that trade's services it
-- does not hold. 126512 holds all five active gypsum services and none of the painting ones, so no such
-- pair exists right now. It is preserved by construction -- the third disjunct requires a DECLARED named
-- trade with no key at all in it, which is false for a trade the supplier has spoken in -- and the
-- re-review verified it directly on the previous draft (aluminium.tensile_structures, 0). After step 3
-- of the apply order, 126512 holds painting.interior and painting.repainting and three painting services
-- become unheld: fn_match_capability(array['painting'], p_services := those three) must then return 0.
--
-- THE ROWS THEMSELVES CHURN, because every confirmed capability in production today is a ZZ DEMO
-- rehearsal supplier that a later rehearsal replaces. A second reading twenty minutes after the one
-- above found a different set (one confirmed supplier per trade instead of four aluminium ones) and
-- read: before, aluminium 1 -> 0, doors 1 -> 0, gypsum 1 -> 1, painting 1 -> 0; after, all four 1 -> 1.
-- The numbers move, the property does not, and the property is what the check asserts.
--
-- The guard is
-- scripts/checks/a_confirmed_trade_is_still_reachable_when_the_inquiry_names_a_service.test.mjs,
-- which measures the two columns above per trade against production and fails if they differ.
--
-- CREATE OR REPLACE, so every existing EXECUTE grant is kept and no new revoke is owed; search_path
-- stays pinned as before. Signature, argument order and return columns are unchanged, so no caller
-- moves. There is no probe in this file: an assertion that raised here would roll back the routine it
-- had just verified, so the assertion lives in the check above.

CREATE OR REPLACE FUNCTION public.fn_match_capability(p_trades text[], p_need text DEFAULT 'executes'::text, p_products text[] DEFAULT '{}'::text[], p_brands text[] DEFAULT '{}'::text[], p_project_type text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_emirate text DEFAULT NULL::text, p_limit integer DEFAULT 12, p_services text[] DEFAULT '{}'::text[])
 RETURNS TABLE(supplier_id bigint, company_name text, score numeric, trades text[], roles text[], product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text, service_hits text[], via_implication text[])
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size
),
req_auth as (
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades)
),
-- THE SERVICES THE INQUIRY ACTUALLY NAMED, and the trades they belong to. Only a value that IS a live
-- taxonomy key counts (23 Sep 2026, re-review finding B): p_services is derived from free text by
-- servicesFromText, and one non-key string such as 'Doors' used to make split_part(...,'.',1) return
-- 'Doors', which is no trade, so the per-trade test below found nothing to apply and the gate switched
-- itself off for the whole inquiry. This is the same filter fn_services_effective applies to what the
-- supplier stored, so both sides of the comparison now admit exactly the same vocabulary.
named as (
  select distinct s as key, split_part(s, '.', 1) as tr
  from unnest(coalesce(p_services, '{}'::text[])) s
  where position('.' in s) > 0
    and exists (select 1 from public.taxonomy_trade_service ts
                where ts.active and ts.trade_code || '.' || ts.code = s)
),
-- HOW MANY REAL SERVICES WERE NAMED. Zero means the gate does not apply at all — whether the inquiry
-- named none or named only words this taxonomy does not know. Trade-level matching, as the column's
-- own contract states ('{}' = derived and no service named).
n as (select count(*)::int as k from named),
-- LOCATION. What the supplier itself STATED: the confirmed capability's coverage list and the
-- registration's service_emirates, as one distinct list with blanks dropped. Empty = no self-imposed
-- limit = the whole UAE (founder, 9 and 14 Sep 2026). Non-empty = the limit is honoured (finding 25).
loc as (
  select sc.supplier_id,
         array(select distinct e from unnest(coalesce(sc.coverage_emirates, '{}'::text[])
                                           || coalesce(l.service_emirates, '{}'::text[])) e
                where nullif(btrim(e), '') is not null) as stated
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
),
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value, sc.coverage_emirates,
         sc.services, sc.services_removed,
         l.company_name, l.emirate as lead_emirate,
         least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0))) as track,
         -- TIE-BREAK between equal scores: the job's emirate is one the supplier named.
         (p_emirate is not null and exists (select 1 from unnest(loc.stated) e where e ilike p_emirate)) as in_emirate,
         cardinality(loc.stated) as stated_n
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  join loc on loc.supplier_id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null                        -- GATE: supplier confirmed their own scope
    and sc.trades && p_trades                              -- GATE: trade intersection
    and not (sc.excluded_trades && p_trades)               -- GATE: declared negative scope
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    and exists (                                            -- GATE: role can actually do this kind of work
      select 1 from public.taxonomy_role r
      where r.code = any(sc.roles)
        and case p_need when 'supplies'    then r.supplies
                        when 'whole_scope' then r.whole_scope
                        else r.executes end
    )
    and not exists (                                        -- GATE: every mandatory authority held
      select 1 from unnest((select codes from req_auth)) a
      where not (sc.authority_approvals ? a)
    )
    and (p_value is null or (                               -- GATE: job size inside their range
          (sc.min_project_value is null or p_value >= sc.min_project_value)
      and (sc.max_project_value is null or p_value <= sc.max_project_value)))
    and (p_emirate is null                                  -- GATE: a stated limit is honoured; none = UAE-wide
      or cardinality(loc.stated) = 0
      or exists (select 1 from unnest(loc.stated) e where e ilike p_emirate))
),
-- GATE: the services the inquiry names, at SERVICE level. Stated + one level of the curated
-- implication map - what the supplier removed. Empty p_services leaves every candidate through.
--
-- ONE DEFINITION OF COVERAGE. eff_services is computed once per candidate by fn_services_effective,
-- and BOTH the hit list and the attribution are derived from it. An earlier draft re-derived the
-- attribution from c.services directly (database review, 18 Sep 2026): a service code the supplier
-- still stores but taxonomy_trade_service no longer marks active was rejected by fn_services_effective
-- and accepted by the attribution, so `why` could name a curated rule that never actually fired.
eff as (
  select c.*,
         case when (select k from n) = 0 then '{}'::text[]
              else public.fn_services_effective(c.services, c.trades, c.services_removed) end as eff_services
  from cand c
),
svc as (
  select e.*,
    array(select unnest(e.eff_services) intersect select key from named) as service_hits,
    -- THE TRADES THIS SUPPLIER IS SILENT IN (23 Sep 2026, SP-F-01 re-review, corrected the same day
    -- after finding A): a trade the inquiry named a service in, that this supplier DECLARES, and in
    -- which it has named no service at all. Per trade, not per inquiry — an earlier draft unioned the
    -- prefixes of every named trade, so a supplier that had spoken on aluminium was treated as having
    -- spoken on doors too, and a {doors.fire_doors, aluminium.tensile_structures} inquiry emptied doors
    -- again. Every real inquiry is this case: the backfill's own three rows carry keys across three,
    -- two and two trades, because sales_engineer derives ONE key set from one brief across all trades.
    array(select t.tr from named t
           where t.tr = any(coalesce(e.trades, '{}'::text[]))
             and not exists (select 1 from unnest(e.eff_services) k where split_part(k, '.', 1) = t.tr)
           group by t.tr order by t.tr) as silent_in,
    -- ponytail: one scan of service_implication per candidate. At 113 curated rows against a
    -- candidate set the gates above have already cut down, this is not measurable; batch it with a
    -- single unnest+join if the map or the candidate count grows an order of magnitude.
    array(
      select distinct i.from_code || ' -> ' || i.implies_trade || '.' || i.implies_code
      from public.service_implication i
      where i.active
        and (i.implies_trade || '.' || i.implies_code) = any(e.eff_services)   -- it really is covered
        and (i.implies_trade || '.' || i.implies_code) in (select key from named)  -- and the inquiry asked
        and not ((i.implies_trade || '.' || i.implies_code) = any(coalesce(e.services, '{}'::text[])))
        and (i.from_code = any(coalesce(e.trades, '{}'::text[]))
          or i.from_code = any(coalesce(e.services, '{}'::text[])))
      order by 1) as via_implication
  from eff e
),
scored as (
  select c.*,
    (select count(distinct pq) from unnest(p_products) pq
      where exists (select 1 from unnest(c.products_norm) pp
                    where pp ilike '%'||pq||'%' or pq ilike '%'||pp||'%'))::int as product_hits,
    (cardinality(p_brands) > 0 and exists (
       select 1 from unnest(p_brands) bq join unnest(c.brands) bb on bb ilike '%'||bq||'%' or bq ilike '%'||bb||'%'
     )) as brand_hit,
    (p_project_type is not null and exists (
       select 1 from unnest(c.project_types) pt
       where pt ilike '%'||p_project_type||'%' or p_project_type ilike '%'||pt||'%'
     )) as ptype_hit,
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known
  from svc c
  -- GATE: the inquiry named services, so the supplier must either cover one of them, or be SILENT in
  -- at least one named trade it declares — silent there means trade level there, and excluding it is
  -- what emptied whole trades. Read per trade: a supplier that has named services in EVERY named trade
  -- it declares and covers none of the named ones is still excluded, which is the gate doing its job.
  where (select k from n) = 0
     or cardinality(c.service_hits) > 0
     or cardinality(c.silent_in) > 0
),
ranked as (
  select s.*,
    round(
        w.w_prod  * (case when cardinality(p_products) > 0
                          then s.product_hits::numeric / cardinality(p_products) else 0 end)
      + w.w_brand * (case when s.brand_hit then 1 else 0 end)
      + w.w_ptype * (case when s.ptype_hit then 1 else 0 end)
      + w.w_track * s.track
      + w.w_size  * (case when s.size_known then 1 else 0.5 end)
    , 1) as score_v
  from scored s, w
)
select r.supplier_id, r.company_name, r.score_v as score,
  r.trades, r.roles, r.product_hits, r.brand_hit, r.ptype_hit, round(r.track,3) as track,
  concat_ws(' · ',
    'trades ' || array_to_string(array(select unnest(r.trades) intersect select unnest(p_trades)), '+'),
    case when cardinality(r.service_hits) > 0 then cardinality(r.service_hits)||'/'||(select k from n)||' services' end,
    -- WHICH trade it passed at trade level in, not merely that it did (re-review finding A): a
    -- multi-trade inquiry can hit a service in one trade and pass on silence in another, and the audit
    -- trail has to say which was which.
    case when cardinality(r.silent_in) > 0
           then 'trade level in ' || array_to_string(r.silent_in, '+') end,
    case when cardinality(r.via_implication) > 0 then 'implied: ' || array_to_string(r.via_implication, ', ') end,
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality(p_products)||' products' end,
    case when r.brand_hit then 'brand match' end,
    case when r.ptype_hit then 'project type' end,
    case when p_emirate is not null then
      case when r.in_emirate then 'in ' || p_emirate else 'UAE-wide (no stated limit)' end end
  ) as why,
  r.service_hits, r.via_implication
from ranked r
order by r.score_v desc, cardinality(r.service_hits) desc, r.in_emirate desc, r.track desc, r.supplier_id
limit greatest(1, p_limit);
$function$
;
[INFO] Recording command outcome: printf

[OK] Command outcome recorded
