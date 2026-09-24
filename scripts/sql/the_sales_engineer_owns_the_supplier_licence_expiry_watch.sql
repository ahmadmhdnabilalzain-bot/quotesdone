-- THE SALES ENGINEER OWNS THE SUPPLIER LICENCE-EXPIRY WATCH; THE IT ENGINEER NO LONGER HOLDS IT.
-- Seat: sales_engineer. 24 Sep 2026, founder_instruction 898 and ledger 983, on the seat ownership the founder
-- gave on 24 Sep (the sales_engineer owns suppliers: verification, documents, matching) and the 9 Sep ruling
-- that a supplier's licence is the sales engineer's.
--
-- WHAT WAS MEASURED (24 Sep 2026, repository): the_it_engineer_watches_licences_and_every_seats_knowledge.sql
-- (#903) registered it_engineer.licence_expiry_watch. Its work is supplier work end to end: the 30/14/7-day
-- renewal asks (fn_licence_expiry_sweep), the pause of an expired approved supplier (fn_reconcile_doc_blocks),
-- and a finding already tagged owner_seat 'sales_engineer' but raised under the it_engineer. The seat audit
-- (GAPS.md row 898) lists it as wrong-owned.
--
-- WHAT THIS CHANGES: the same routine body under the owning seat's name, fn_sales_engineer_licence_expiry_watch,
-- raising its finding as the sales_engineer; the duty sales_engineer.licence_expiry_watch on the same daily clock;
-- the it_engineer duty row deleted and fn_it_engineer_licence_expiry_watch dropped. The #903 file keeps its historical
-- definition, so the apply also records the drop in DROPPED.txt and renames the routine in the REGISTER of
-- scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs (see this file's pending note). The company's OWN licences, NOL, domains
-- and TLS (public.it_expiry) stay with the it_engineer: those are platform facts, not suppliers.
--
-- WHAT THIS DOES NOT CHANGE: the renewal-ask and pause wording, the finding key, or who is told.

create or replace function public.fn_sales_engineer_licence_expiry_watch()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_asks jsonb; v_before int; v_after int; v_fix json; v_ids jsonb;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_asks := public.fn_licence_expiry_sweep(false);

  -- THE INVARIANT, measured here and not trusted to the routine that sets it: an approved supplier whose licence
  -- or insurance is past its date is not matchable (fn_is_matchable reads matching_blocked).
  select count(*) into v_before from public.leads l
   where l.approval_status = 'approved' and not coalesce(l.banned, false) and not coalesce(l.matching_blocked, false)
     and (l.license_expiry < v_today or l.insurance_expiry < v_today);
  if v_before > 0 then v_fix := public.fn_reconcile_doc_blocks(0); end if;   -- pauses them AND tells each supplier
  select count(*), coalesce(jsonb_agg(l.id order by l.id), '[]'::jsonb) into v_after, v_ids from public.leads l
   where l.approval_status = 'approved' and not coalesce(l.banned, false) and not coalesce(l.matching_blocked, false)
     and (l.license_expiry < v_today or l.insurance_expiry < v_today);

  if v_after > 0 then
    perform public.fn_it_engineer_finding_upsert('licence_expiry:matchable_after_expiry',
      v_after || ' approved supplier(s) with an expired licence or insurance are still matchable after the pause ran',
      'public.leads / fn_reconcile_doc_blocks', 'customer_facing', v_after, jsonb_build_object('lead_ids', v_ids, 'owner_seat', 'sales_engineer'),
      '{}'::text[], array['why fn_reconcile_doc_blocks skipped them (a manual block reason it will not overwrite?)'], 'sales_engineer');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'no expired supplier is matchable (sales_engineer.licence_expiry_watch)'
     where issue_key = 'licence_expiry:matchable_after_expiry' and closed_at is null;
  end if;
  return jsonb_build_object('renewal_asks', v_asks - 'sample', 'expired_matchable_before', v_before,
                            'paused', v_fix, 'expired_matchable_after', v_after);
end $fn$;
revoke execute on function public.fn_sales_engineer_licence_expiry_watch() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_licence_expiry_watch() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.licence_expiry_watch', 'sales_engineer', interval '1 day', 'fn_sales_engineer_licence_expiry_watch',
   'Renewal asks at 30/14/7 days; no expired approved supplier stays matchable (paused and told through fn_reconcile_doc_blocks).',
   'scripts/sql/the_sales_engineer_owns_the_supplier_licence_expiry_watch.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- the it_engineer's copy goes: one clock, one owner
delete from public.seat_duty where duty = 'it_engineer.licence_expiry_watch';
drop function if exists public.fn_it_engineer_licence_expiry_watch();
