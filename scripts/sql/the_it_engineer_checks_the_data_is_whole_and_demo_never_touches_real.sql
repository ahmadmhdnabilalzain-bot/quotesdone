-- THE IT ENGINEER CHECKS, EVERY DAY, THAT THE DATA IS WHOLE AND THAT DEMO DATA NEVER TOUCHES A REAL PARTY.
-- Seat: it_engineer. 24 Sep 2026, seat audit (GAPS.md IT gap 6; ledger 983). Needs seat_duty and fn_it_duty_settle.
--
-- WHAT WAS MEASURED (production, 24 Sep 2026): no duty checked for orphans, for totals that disagree, or for test
--   and demo data leaking into real numbers. leads.is_demo and customers.is_demo are GENERATED columns
--   (fn_is_demo_email / fn_is_demo_phone / the ZZ DEMO name), so a demo party can never be flagged real: the leak
--   that CAN happen is a demo row crossing into a real one — a ZZ DEMO customer's inquiry quoted by a real supplier,
--   or a transaction between a demo party and a real one. That both counts demo money as real and puts a fixture in
--   front of a real person.
--
-- WHAT THIS ADDS: seat_duty it_engineer.data_quality (1 day), deterministic, no model. Each class is one finding
--   duty:data_quality:<class> carrying up to 20 ids for the owning seat; a clean day closes it. Nothing is deleted:
--   removing money-bearing rows is destructive and not this seat's call.
--   1. DEMO CROSSES REAL: quotes whose inquiry's customer and supplier disagree on is_demo (sales_engineer);
--      transactions whose customer and supplier disagree on is_demo (accountant).
--   2. ORPHANS: a quote whose inquiry or supplier is gone; an inquiry whose customer is gone (sales_engineer); a
--      transaction whose quote, inquiry, customer or supplier is gone (accountant).
--   3. MISMATCHES: a transaction whose quote_amount, inquiry or supplier disagrees with its quote (accountant).
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_checks_the_data_is_whole_and_demo_never_touches_real.sql --apply --ddl

create or replace function public.fn_it_engineer_data_quality()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_items jsonb := '[]'::jsonb; n int; ids jsonb; v_chk record; v_counts jsonb := '{}'::jsonb;
begin
  for v_chk in
    select * from (values
      ('demo_quote_crosses_real', 'sales_engineer', 'quotes join a ZZ DEMO party to a real one (customer and supplier disagree on demo)',
       $q$select q.id from public.quotes q join public.inquiries i on i.id = q.inquiry_id
            join public.customers cu on cu.id = i.customer_id join public.leads l on l.id = q.supplier_id
          where cu.is_demo is distinct from l.is_demo$q$),
      ('demo_transaction_crosses_real', 'accountant', 'transactions join a ZZ DEMO party to a real one (customer and supplier disagree on demo)',
       $q$select t.id from public.transactions t join public.customers cu on cu.id = t.customer_id join public.leads l on l.id = t.supplier_id
          where cu.is_demo is distinct from l.is_demo$q$),
      ('orphan_quotes', 'sales_engineer', 'quotes point at an inquiry or a supplier that no longer exists',
       $q$select q.id from public.quotes q where not exists (select 1 from public.inquiries i where i.id = q.inquiry_id)
            or (q.supplier_id is not null and not exists (select 1 from public.leads l where l.id = q.supplier_id))$q$),
      ('orphan_inquiries', 'sales_engineer', 'inquiries point at a customer that no longer exists',
       $q$select i.id from public.inquiries i where i.customer_id is not null and not exists (select 1 from public.customers c where c.id = i.customer_id)$q$),
      ('orphan_transactions', 'accountant', 'transactions point at a quote, inquiry, customer or supplier that no longer exists',
       $q$select t.id from public.transactions t
          where (t.quote_id is not null and not exists (select 1 from public.quotes q where q.id = t.quote_id))
             or (t.inquiry_id is not null and not exists (select 1 from public.inquiries i where i.id = t.inquiry_id))
             or (t.customer_id is not null and not exists (select 1 from public.customers c where c.id = t.customer_id))
             or (t.supplier_id is not null and not exists (select 1 from public.leads l where l.id = t.supplier_id))$q$),
      ('transaction_quote_mismatch', 'accountant', 'transactions disagree with the quote they were revealed from (amount, inquiry or supplier)',
       $q$select t.id from public.transactions t join public.quotes q on q.id = t.quote_id
          where t.quote_amount is distinct from q.quote_amount or t.inquiry_id is distinct from q.inquiry_id
             or t.supplier_id is distinct from q.supplier_id$q$)
    ) v(cls, owner, what, q)
  loop
    execute 'select count(*), coalesce(jsonb_agg(id) filter (where rn <= 20), ''[]'') from (select id, row_number() over (order by id) rn from ('
            || v_chk.q || ') s) z' into n, ids;
    v_counts := v_counts || jsonb_build_object(v_chk.cls, n);
    if n > 0 then
      v_items := v_items || jsonb_build_object('item', v_chk.cls, 'owner_seat', v_chk.owner, 'subject', v_chk.cls, 'affected', n,
        'blast', case when v_chk.owner = 'accountant' then 'customer_facing' else 'internal' end,
        'title', n || ' ' || v_chk.what, 'evidence', jsonb_build_object('ids', ids, 'count', n));
    end if;
  end loop;

  return jsonb_build_object('counts', v_counts, 'settled', public.fn_it_duty_settle('data_quality', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_data_quality() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_data_quality() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.data_quality', 'it_engineer', interval '1 day', 'fn_it_engineer_data_quality',
   'Demo rows crossing into real parties, orphans and transaction-quote mismatches, raised to the owning seat.',
   'scripts/sql/the_it_engineer_checks_the_data_is_whole_and_demo_never_touches_real.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

select case when to_regprocedure('public.fn_it_engineer_data_quality()') is not null
             and exists (select 1 from public.seat_duty where duty = 'it_engineer.data_quality')
            then 'PROBE OK' else 'PROBE FAILED: the data quality duty is not registered' end as verdict;
