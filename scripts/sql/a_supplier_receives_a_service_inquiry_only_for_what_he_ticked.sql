-- A SUPPLIER RECEIVES A SERVICE INQUIRY ONLY FOR WHAT HE TICKED (23 Sep 2026, agent: sales_engineer,
-- founder instruction 857).
--
-- THE RULING. the_service_gate_never_empties_a_trade.sql (PR #859, applied 23 Sep 2026) changed the
-- matching policy and said so in its header: from 15 Sep a supplier's silence at service level had been
-- read as a denial, and that file read it as trade level. The founder was asked and ruled against it,
-- founder_instruction 857, in his words:
--
--     "if he didnt tick it in the customer portal in his profile then yea it means he didnt confirm
--      that he does it basically"
--
-- So a supplier who declares a trade the inquiry named services in, and ticked NONE of the named
-- services in that trade, has not confirmed he does them and does not receive the inquiry. That was
-- exactly the `silent_in` arm of the gate. It is removed here, and with it the `why` text
-- "trade level in <trade>", which can no longer appear.
--
-- WHAT STAYS, because none of it contradicts him:
--   * NEVER ASKED. When the inquiry named services only in trades the supplier does not declare, and he
--     is admitted through another trade the inquiry names, nothing was asked of him in any trade he
--     does. His ruling is about not ticking what was asked; he failed to tick nothing.
--   * NO SERVICE NAMED. An inquiry that names no service this taxonomy knows still reaches every
--     supplier of the trade, exactly as before. (The never-asked arm alone already implies this --
--     with nothing named, no named trade is declared -- but the explicit test is cheap and reads
--     plainly, so it is kept.)
--   * A HIT. He ticked one of the named services.
--   * Finding B's `named` filter: only live taxonomy keys reach the prefix logic, so a word such as
--     'Doors' in p_services is ignored rather than switching the gate off.
--   * a_confirmed_service_is_a_taxonomy_key_not_a_word.sql: it turned a word the supplier genuinely
--     ticked («الدهانات») into the key it names. That honours his tick; it guesses nothing.
--   * Exact trade match or none. No key is ever invented or mapped to a neighbour.
--
-- THE PREDICATE, MEASURED 23 Sep 2026 from a read-only VALUES list of synthetic candidates against the
-- real taxonomy and the real fn_services_effective (nothing created, nothing written):
--
--   property  candidate                                             ask                               LIVE   THIS
--   1 reach   declares {doors}, ticked doors.fire_doors            {doors.fire_doors}                PASS   PASS
--   1 reach   declares {aluminium,doors}, ticked aluminium.louvres {aluminium.louvres,doors.fire_d.} PASS   PASS
--   2 excl.   declares {aluminium,doors}, aluminium keys + 'Doors' {doors.fire_doors}                PASS   EXCL
--   2 excl.   declares {doors}, ticked nothing                     {doors.fire_doors}                PASS   EXCL
--   2 excl.   declares {doors}, ticked doors.wooden_doors          {doors.fire_doors}                EXCL   EXCL
--   2 excl.   declares {aluminium,doors}, ticked curtain_wall      {aluminium.louvres,doors.fire_d.} PASS   EXCL
--   3 reach   declares {doors}, ticked nothing                     {aluminium.louvres}               PASS   PASS
--   3 reach   declares {doors}, ticked doors.wooden_doors          {aluminium.louvres}               PASS   PASS
--   4 reach   declares {doors}                                     {}                                PASS   PASS
--   4 reach   declares {doors}                                     {'Doors'}                         PASS   PASS
--
-- Against the ruling: the live gate is wrong on 3 rows (every one of them the removed arm), this file on
-- 0. Each remaining arm is load-bearing: this file with never_asked removed is wrong on the two
-- property-3 rows, and with the hit removed on the two property-1 rows.
--
-- THE CONSEQUENCE ON PRODUCTION, measured the same day (live function vs this body run read-only):
-- production holds ONE confirmed capability row, ZZ DEMO 126512, declaring {gypsum, painting}, with all
-- five gypsum services ticked and painting.interior (plus painting.repainting implied). It has a tick in
-- every trade it declares, so the removed arm never fired for it and this change moves no real number:
--
--   trade      trade level   every service named   one service at a time (live -> this)
--   gypsum          1             1 -> 1           acoustic_ceiling, decorative, false_ceiling,
--                                                  partitions, plastering: 1 -> 1 each
--   painting        1             1 -> 1           interior 1 -> 1, repainting 1 -> 1,
--                                                  decorative 0 -> 0, exterior 0 -> 0,
--                                                  protective_coating 0 -> 0
--
-- Three single-service painting inquiries reach ZERO suppliers -- decorative, exterior, protective
-- coating -- before and after alike: the one painting supplier did not tick them. That is the founder's
-- rule working, not this change, but he should know those three reach nobody today.
--
-- WHERE THE RULING WILL BITE. A supplier gets a declared trade with no tick in it when a phrase he typed
-- resolves to a TRADE but names no SERVICE (servicesSaveRewrite adds the trade and keeps the words): the
-- aluminium interview's own "Doors" option does exactly that, and ZZ DEMO rehearsals minted four such
-- suppliers on 23 Sep before they retired. Under this ruling each of them stops receiving any inquiry
-- that names a doors service until he ticks one.
--
-- CREATE OR REPLACE with the signature, argument order, defaults, return columns, LANGUAGE sql, STABLE
-- and the pinned search_path all unchanged, so every EXECUTE grant is kept and no revoke is owed. No
-- probe raises in this file: it would roll back the routine it had just verified. The guard is
-- scripts/checks/a_service_inquiry_reaches_only_suppliers_who_ticked_what_it_names.test.mjs.

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
    -- NEVER ASKED (23 Sep 2026, re-review finding C; kept under founder instruction 857). The inquiry
    -- named services only in trades this supplier does not declare, and it is admitted through another
    -- trade the inquiry names. Nothing was asked of it in any trade it does, so it failed to tick
    -- nothing: the founder's ruling is about not ticking what was ASKED. detectTrades and serviceKeysOf
    -- read one brief independently, so a brief naming two trades and yielding keys in only one is the
    -- normal shape, and without this arm a whole single-trade supplier pool goes to zero on it.
    not exists (select 1 from named t where t.tr = any(coalesce(e.trades, '{}'::text[]))) as never_asked,
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
  -- GATE, three arms (founder instruction 857, 23 Sep 2026: "if he didnt tick it in the customer portal
  -- in his profile then yea it means he didnt confirm that he does it basically"). A supplier that
  -- declares a trade the inquiry named services in, and ticked NONE of the named ones, has not
  -- confirmed he does them and does not receive the inquiry. The "silent in a declared named trade"
  -- arm that let him through is removed; see this file's header.
  where (select k from n) = 0          -- the inquiry named no service this taxonomy knows
     or cardinality(c.service_hits) > 0 -- he ticked one of the services named
     or c.never_asked                   -- the services named are in no trade he declares
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
    -- The never-asked arm populates no service hit, so it needs its own line or the audit trail would
    -- show a candidate with no reason. Only when there was no hit: an implied key can land in a trade
    -- the supplier does not declare, so a row can be admitted on a genuine hit while never_asked is
    -- also true, and "1/1 services" beside "no service named" would contradict itself.
    case when (select k from n) > 0 and r.never_asked and cardinality(r.service_hits) = 0
           then 'trade level (no service named in this supplier''s trades)' end,
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

