-- TWENTY THOUSAND SUPPLIERS FILED UNDER A VOCABULARY THE MATCHER CANNOT READ.
--
-- The company's own escalation (org_tasks 1309) named the gate: "why the 20,470-supplier directory
-- generates zero RFQs and why supplier approval is stuck at 0/6". This is the first half. The
-- second half - 0/6 - is not real: all six pending rows are ZZ DEMO fixtures on @example.invalid
-- and the approver is correctly refusing companies that do not exist. Real suppliers pending
-- approval: 0. Nobody has ever reached the queue.
--
-- WHAT IS REAL, MEASURED ON PRODUCTION 12 Aug 2026:
--
--   supplier_capabilities            0 rows
--   supplier_opportunity_score       0 rows
--   leads                       20,470 rows, 17,028 carrying invite_trades
--
-- fn_match_capability - the function that turns an inquiry into a shortlist - reads
-- supplier_capabilities and matches on `sc.trades && p_trades`, where p_trades are
-- taxonomy_trade.code values. So with that table empty, a customer arriving today gets nobody. The
-- directory is not a marketplace; it is a spreadsheet.
--
-- THREE SEPARATE THINGS WERE WRONG, AND EACH ONE ON ITS OWN IS ENOUGH TO EXPLAIN ZERO RFQs.
--
-- 1. THE TRADES ARE IN THE WRONG VOCABULARY. leads.invite_trades holds coarse CATEGORY SLUGS, and
--    fn_match_capability matches taxonomy_trade CODES. They share nothing: of the 89 distinct
--    values in invite_trades, ZERO appear in lead_trade_map.catalog_slug, and none is a
--    taxonomy_trade.code. It is also wrong on the merits, not just the encoding - measured, row by
--    row, against what fn_norm_trades computes from the same text:
--
--      #1 Amana Aluminium & Glass Works   stored: interior-fit-out…, manufacturing-by-process
--                                         should be: aluminium, doors, glazing
--      #2 Jama Auto Glass                 stored: facilities-management-and-support-services, …
--                                         should be: cleaning, doors, glazing
--      #4 BOSCO TRADING (Aluminum supplier) stored: interior-fit-out-finishes-and-joinery
--                                         should be: aluminium
--
--    An auto-glass shop filed under facilities management cannot be found by a customer asking for
--    glazing, in any vocabulary.
--
-- 2. THE JOB THAT WOULD FIX IT CAN ONLY TOUCH ROWS THAT DO NOT NEED FIXING. cron job 120,
--    backfill_invite_trades, runs daily and computes exactly the right thing -
--    fn_norm_trades(company_name||categories||sector) - but its WHERE clause is
--    `invite_trades is null`. The 17,028 rows carrying the wrong vocabulary are not null, so it has
--    reported "UPDATE 0" on 10, 11 and 12 August and will report it every day forever. Same shape
--    as the cos_execute stale-reclaim that could only run when the queue was empty: a recovery path
--    guarded by a condition that cannot occur.
--
-- 3. THE ENRICHER RUNS DAILY AND CANNOT SELECT A SINGLE ROW. enrich_capability's batch reads
--    `.eq('approval_status','approved').is('capability_enriched_at',null)` and then filters to
--    `registration_submitted_at || source==='self_registered'`. Approved suppliers: 0.
--    registration_submitted_at: 0 across all 20,470. capability_backfill_daily has "succeeded"
--    every day since it was created, having processed nothing. It also writes
--    leads.capability_summary - NOT supplier_capabilities - so even a full run would leave the gate
--    and the matcher exactly as empty as they are now.
--
-- WHAT THIS CHANGES, AND WHAT IT DELIBERATELY DOES NOT.
--
-- It derives supplier_capabilities from the directory the company already owns, in SQL, with NO
-- model call. That is the founder's own instruction from the same day applied to the same problem:
-- "most internal operations was supposed to be part of the code and not an actual spend on open
-- router". fn_norm_trades is a STABLE sql function over taxonomy aliases; deriving 17,000 rows
-- costs one query, not 17,000 sonnet calls.
--
-- IT INVENTS NOTHING. Every field is a transformation of data already in leads: trades from the
-- company name, categories, sector, services and products; coverage from emirate and
-- service_emirates; products and services split from the text the directory already holds. No
-- field is guessed, and a lead whose text yields no trade is skipped rather than given one.
--
-- THE ROWS ARE WRITTEN UNCONFIRMED AND THAT IS THE POINT. fn_match_capability gates on
-- `sc.confirmed_at is not null` - "GATE: supplier confirmed their own scope" - and this does not
-- touch confirmed_at, does not weaken that gate, and does not make one derived supplier matchable.
-- Deriving a scope is not the same as a supplier standing behind it, and quoting a customer from a
-- scope nobody confirmed is exactly the failure that gate exists to prevent. What changes is that
-- there is now something concrete to ASK them to confirm, per trade, instead of an empty table.
--
-- ZZ DEMO fixtures are excluded by name and by @example.invalid, the convention already in the data.

-- ── 1. the trades, in the vocabulary the matcher actually reads ─────────────────────────────────
-- BOUNDED AND RESUMABLE, BECAUSE THE WHOLE SWEEP IS TEN MINUTES. Measured by aborted probe on
-- production: 20 rows took 698 ms, so the ~16,400 rows in the wrong vocabulary are ~9.5 minutes in
-- one statement - past every timeout on the path, and a lock on the supplier directory for the
-- duration. fn_norm_trades regex-matches every taxonomy alias per row; that is the cost.
--
-- The same probe measured the blast radius, because `leads` carries FOURTEEN triggers and most fire
-- on UPDATE: company_event +0, net.http_request_queue +0, agent_actions +0, notifications +0. They
-- are guarded on approval and registration transitions, and this touches neither. Worth measuring
-- rather than assuming - an executor on this table can email a supplier.
create or replace function public.fn_leads_retrade(p_limit integer default 2000)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_n int; v_left bigint;
begin
  with pick as (
    select l.id from public.leads l
     where not (coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid')
       and l.invite_trades is distinct from public.fn_norm_trades(
             coalesce(l.company_name,'')||' '||coalesce(l.categories,'')||' '||
             coalesce(l.sector,'')||' '||coalesce(l.services,'')||' '||coalesce(l.products,''))
     order by l.id
     limit greatest(coalesce(p_limit, 2000), 1))
  update public.leads l
     set invite_trades = public.fn_norm_trades(
           coalesce(l.company_name,'')||' '||coalesce(l.categories,'')||' '||
           coalesce(l.sector,'')||' '||coalesce(l.services,'')||' '||coalesce(l.products,''))
    from pick where l.id = pick.id;
  get diagnostics v_n = row_count;

  -- PROGRESS IS MEASURED WITH AN ARRAY OVERLAP, NOT BY RE-RUNNING THE NORMALISER. The first cut
  -- recounted `is distinct from fn_norm_trades(...)` over all 20,470 rows to report what was left,
  -- and that scan - not the update - hit the statement timeout and took the whole call down with
  -- it, including the rows it had just fixed. fn_norm_trades regex-matches every taxonomy alias per
  -- row; 2,500 of those is the work, 20,470 is a wall. `&&` against the code list is an array
  -- operation on data already in the row.
  select count(*) into v_left from public.leads l
   where l.invite_trades is not null
     and array_length(l.invite_trades, 1) > 0
     and not (l.invite_trades && (select array_agg(code) from public.taxonomy_trade));

  return jsonb_build_object('renormalised', v_n, 'still_wrong_vocabulary', v_left,
    'in_taxonomy_vocab', (select count(*) from public.leads
                           where invite_trades && (select array_agg(code) from public.taxonomy_trade)));
end
$function$;

comment on function public.fn_leads_retrade(integer) is
  'Re-normalises leads.invite_trades into taxonomy_trade codes via fn_norm_trades, bounded per call '
  'and idempotent (`is distinct from` makes it a no-op once converged). Fixes 17,028 rows stored in '
  'a category-slug vocabulary fn_match_capability cannot read.';

revoke execute on function public.fn_leads_retrade(integer) from public;
grant execute on function public.fn_leads_retrade(integer) to service_role;

-- The daily job now maintains the SAME expression it was already computing, over every stale row
-- instead of only the null ones. Its WHERE was `invite_trades is null`, and the 17,028 rows holding
-- the wrong vocabulary are not null - so it has reported "UPDATE 0" on 10, 11 and 12 August and
-- would have reported it every day forever. A recovery path guarded by a condition that cannot
-- occur, the same shape as the cos_execute stale-reclaim that could only run when the queue was
-- empty.
--
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

-- ── 2. the capability record, derived from the directory ────────────────────────────────────────
create or replace function public.fn_supplier_capability_derive(p_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_written int := 0; v_skipped_no_trade int := 0; v_candidates int := 0;
begin
  -- Candidates: a real (non-fixture) lead whose own text yields at least one taxonomy trade.
  -- A lead that yields none is SKIPPED and counted, never written with an empty scope - an empty
  -- capability row would satisfy a count and match nobody, which is the defect this replaces.
  with cand as (
    select l.id,
           public.fn_norm_trades(
             coalesce(l.company_name,'')||' '||coalesce(l.categories,'')||' '||
             coalesce(l.sector,'')||' '||coalesce(l.services,'')||' '||coalesce(l.products,'')) as trades,
           array_remove(array[nullif(btrim(coalesce(l.emirate,'')),'')]
                        || coalesce(l.service_emirates,'{}'::text[]), null) as emirates,
           -- the directory stores these as free text; split on the separators it actually uses and
           -- bound the result so one pathological row cannot write a thousand-element array
           (select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
              from unnest(string_to_array(regexp_replace(coalesce(l.products,''), '[;|/]', ',', 'g'), ',')) x
             where length(btrim(x)) between 2 and 80) as products_norm,
           (select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
              from unnest(string_to_array(regexp_replace(coalesce(l.services,''), '[;|/]', ',', 'g'), ',')) x
             where length(btrim(x)) between 2 and 80) as services_norm
      from public.leads l
     where not (coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid')
       and coalesce(l.banned, false) = false
       and not exists (select 1 from public.supplier_capabilities s where s.supplier_id = l.id)
     order by l.id
     limit p_limit
  ), ins as (
    insert into public.supplier_capabilities as sc (
      supplier_id, trades, coverage_emirates, products_norm, services,
      extracted_at, updated_at, extractor_version, review_status, completeness,
      missing_fields, source_docs)
    select c.id,
           c.trades,
           c.emirates,
           c.products_norm[1:40],
           c.services_norm[1:40],
           now(), now(), 'derived_from_directory_v1', 'derived',
           -- completeness is the share of the five derivable fields this lead actually supported,
           -- so a thin directory row reads thin instead of reading complete.
           round(( (array_length(c.trades,1) > 0)::int
                 + (array_length(c.emirates,1) > 0)::int
                 + (array_length(c.products_norm,1) > 0)::int
                 + (array_length(c.services_norm,1) > 0)::int )::numeric / 4, 2),
           -- everything the supplier still has to tell us. This is the ask list the registration
           -- flow should be putting in front of them, and it is per-supplier rather than generic.
           array_remove(array[
             case when array_length(c.products_norm,1) is null then 'products' end,
             case when array_length(c.emirates,1)      is null then 'coverage_emirates' end,
             'brands','certifications','team_size','min_project_value','max_project_value'
           ], null),
           jsonb_build_object(
             'derived_from','leads directory (company_name, categories, sector, services, products, emirate)',
             'method','fn_norm_trades over taxonomy_trade aliases - deterministic, no model call',
             'confirmed_by_supplier', false,
             'at', now())
    from cand c
    where array_length(c.trades,1) > 0
    returning 1
  )
  select (select count(*) from ins), (select count(*) from cand),
         (select count(*) from cand where array_length(trades,1) is null)
    into v_written, v_candidates, v_skipped_no_trade;

  return jsonb_build_object(
    'candidates', v_candidates,
    'written', v_written,
    'skipped_no_trade', v_skipped_no_trade,
    'total_capability_rows', (select count(*) from public.supplier_capabilities),
    'confirmed_rows', (select count(*) from public.supplier_capabilities where confirmed_at is not null),
    'note', 'derived rows are UNCONFIRMED on purpose: fn_match_capability still refuses them until '
            'the supplier confirms their own scope. This gives that conversation something to be about.');
end
$function$;

comment on function public.fn_supplier_capability_derive(integer) is
  'Derives supplier_capabilities from the leads directory deterministically (fn_norm_trades over '
  'taxonomy aliases, no model call). Rows are written UNCONFIRMED so fn_match_capability''s '
  'confirmed_at gate is untouched. See '
  'scripts/sql/twenty_thousand_suppliers_filed_under_a_vocabulary_the_matcher_cannot_read.sql.';

-- New SECURITY DEFINER function: granted EXECUTE to PUBLIC on creation, so revoke it here. Revoking
-- from anon alone is a silent no-op while the grant is held through PUBLIC.
revoke execute on function public.fn_supplier_capability_derive(integer) from public;
grant execute on function public.fn_supplier_capability_derive(integer) to service_role;
