-- THE TURNKEY PATH ASKS THE SALES ENGINEER, AND THE KEYWORD MATCHER IS DROPPED.
--
-- Subject: public.match_suppliers_kw(text[],text,text,text,numeric,integer,boolean), the keyword
-- supplier matcher. Owner seat: sales_engineer. 15 Sep 2026.
--
-- FOUNDER RULE: exact trade match or none; no nearest or fuzzy mapping.
--
-- WHAT WAS WRONG. PR #697 took the keyword fallback out of customer_api for the case where the sales
-- engineer errors, but the turnkey path in create_inquiry never asked the sales engineer at all: it
-- called this routine with the customer's keywords plus a hard-coded fit-out word list and shortlisted
-- up to 8 suppliers by keyword hits and sector equality, the nearest-mapping the founder ruled out.
-- customer_api now sends turnkey requests to sales_engineer {action:'match'} like every other request
-- (fn_match_capability; scope_type 'turnkey' is read as the whole_scope need), with the same retry,
-- wait and sales_engineer_match_unavailable finding on error.
--
-- WHY NOTHING ELSE LOSES A CALLER. MEASURED ON PRODUCTION, 15 Sep 2026, before this file:
--   * pg_depend: 0 rows referencing the routine (no view, trigger, default or other object).
--   * pg_proc.prosrc: 0 other routines name it, in any schema.
--   * views and materialized views: 0 definitions name it. cron.job: 0 commands name it.
--   * edge functions: the turnkey call in customer_api was the only rpc to it (grep of
--     supabase/functions); src/ never called it (comments only).
--   * scripts: the portal blueprint scorer probed it by name; those probes now read
--     fn_match_capability. No other script calls it.
-- The 6-argument overload was dropped on 3 Aug 2026
-- (supabase/migrations_history/20260803162356_audit_65f_drop_ambiguous_six_arg_matcher_overload.sql),
-- so this is the last one. The routine is recorded in scripts/sql/DROPPED.txt.
--
-- APPLY ORDER: deploy customer_api first. The deployed customer_api before this change still calls
-- the routine on the turnkey path, so dropping it first would error every turnkey request.
--
-- WHAT THIS DOES NOT CHANGE: fn_match_capability, fn_is_matchable, fn_supplier_product_match (ranks a
-- supplier's own products against an inquiry and selects no supplier), and no table or data.

do $chk$
declare n int;
begin
  select count(*) into n
    from pg_depend d
   where d.refobjid = to_regprocedure('public.match_suppliers_kw(text[],text,text,text,numeric,integer,boolean)');
  if n > 0 then raise exception 'match_suppliers_kw still has % pg_depend row(s) - refusing to drop', n; end if;

  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname not in ('pg_catalog', 'information_schema')
     and p.proname <> 'match_suppliers_kw' and p.prosrc ilike '%match_suppliers_kw%';
  if n > 0 then raise exception 'match_suppliers_kw is still named in % routine body(ies) - refusing to drop', n; end if;
end
$chk$;

drop function if exists public.match_suppliers_kw(text[], text, text, text, numeric, integer, boolean);

do $chk$
begin
  if exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'match_suppliers_kw') then
    raise exception 'an overload of match_suppliers_kw still exists';
  end if;
  if to_regprocedure('public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer)') is null then
    raise exception 'fn_match_capability, the exact matcher every path now uses, is missing';
  end if;
  raise notice 'match_suppliers_kw is gone; fn_match_capability remains';
end
$chk$;
