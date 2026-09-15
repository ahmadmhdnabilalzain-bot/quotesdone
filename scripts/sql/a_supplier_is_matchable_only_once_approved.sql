-- A SUPPLIER IS MATCHABLE ONLY ONCE APPROVED.
--
-- Assigned: sales_engineer. fn_is_matchable is the one predicate match_suppliers_kw,
-- fn_match_capability, fn_supplier_market, fn_supplier_twin, fn_supplier_quote_recommend,
-- fn_public_site_counters and fn_os_health all call (measured 15 Sep 2026). Its only definition was in
-- supabase/migrations_history/20260803181750_matching_single_predicate.sql; this file now owns it.
--
-- WHAT WAS WRONG: the approval clause was `approval_status not in ('action_required','rejected')`, so a
-- NULL or 'pending' supplier with verified=true passed. The founder's rule is that the sales engineer
-- verifies a supplier before anything reaches them, and 'approved' is the only state that says so.
-- MEASURED 15 Sep: the only matchable leads were ZZ DEMO rehearsal rows, all approved (none lost by
-- this); 22,264 unclaimed listings are verified=false and were never matchable. The change closes the
-- door for the future and moves nothing now. The probe below prints the count at apply time.
--
--   node scripts/apply_sql.mjs scripts/sql/a_supplier_is_matchable_only_once_approved.sql --apply

create or replace function public.fn_is_matchable(p_verified boolean, p_banned boolean, p_matching_blocked boolean,
                                                  p_approval_status text, p_permanently_closed boolean, p_chat_strikes integer)
returns boolean language sql stable parallel safe set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(p_verified, false)                                        -- verified
     and coalesce(p_approval_status, '') = 'approved'                       -- and approved by the sales engineer
     and coalesce(p_banned, false) = false
     and coalesce(p_matching_blocked, false) = false                        -- expired documents, reconciled daily by
                                                                            -- fn_sales_engineer_supplier_documents_tick
     and coalesce(p_permanently_closed, false) = false                      -- never RFQ a closed business
     and coalesce(p_chat_strikes, 0) < public.fn_matching_strike_limit();   -- the no-response exception
$fn$;

do $probe$
begin
  if public.fn_is_matchable(true, false, false, null, false, 0)
     or public.fn_is_matchable(true, false, false, 'pending', false, 0)
     or not public.fn_is_matchable(true, false, false, 'approved', false, 0)
     or public.fn_is_matchable(false, false, false, 'approved', false, 0) then
    raise exception 'fn_is_matchable probe FAILED: only verified AND approved may pass';
  end if;
  raise notice 'fn_is_matchable probe ok: null and pending refused, verified+approved passes; % leads matchable',
    (select count(*) from public.leads l where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes));
end $probe$;
