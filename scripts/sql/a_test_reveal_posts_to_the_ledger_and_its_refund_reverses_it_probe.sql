-- PROBE (accountant, 23 Sep 2026): the ledger half of the sandbox money path.
--
-- The nightly journey (scripts/e2e/journeys.mjs d + e) drives a ZZ DEMO reveal through Stripe TEST checkout,
-- the signed webhook, the reveal invoice, the refund request, the CEO's approval and a Stripe TEST refund.
-- It never reaches the ledger, ON PURPOSE: fn_gl_sync_business books nothing whose customer or supplier is a
-- demo identity (fn_gl_fixture_or_orphan), so test money cannot touch the company's books. The cost of that
-- rule was that the reveal and refund branches of fn_gl_sync_business had never run on any row: 0 'reveal_fee'
-- and 0 'refund_paid' journals exist (measured 23 Sep 2026).
--
-- This probe runs them on the newest demo reveal the journey paid AND refunded in TEST mode, inside one
-- transaction that always rolls back: the demo flag is lifted on that transaction's two parties only, the
-- sale is booked with its refund status cleared, then the refund status is put back and the refund posts.
-- It asserts the entries are balanced and equal to what the customer was charged, and that the refund
-- takes back everything the customer paid. Pure probe, no DDL: it raises CHK<<...>> and leaves nothing.
--   node scripts/qsql.mjs scripts/sql/a_test_reveal_posts_to_the_ledger_and_its_refund_reverses_it_probe.sql
do $$
declare t record; v_rs text; n1 int; n2 int; sale jsonb; ref jsonb; v_real_before bigint; v_gross numeric;
begin
  select tx.id, tx.customer_id, tx.supplier_id, tx.total_charged, tx.reveal_fee, tx.refund_status, tx.payment_ref
    into t
    from public.transactions tx join public.customers c on c.id = tx.customer_id
   where c.is_demo and c.email like '%@example.invalid' and tx.fee_status = 'paid'
     and tx.refund_status in ('refunded', 'succeeded') and tx.payment_ref like 'pi_%'
   order by tx.revealed_at desc nulls last limit 1;
  if t.id is null then raise exception 'CHK<<PROBE FAILED: no ZZ DEMO reveal paid and refunded in Stripe TEST mode to read>>'; end if;
  v_real_before := (select count(*) from public.gl_journal);
  v_gross := round(coalesce(t.total_charged, t.reveal_fee), 2);

  update public.customers set is_demo = false where id = t.customer_id;
  update public.leads set is_demo = false where id = t.supplier_id;
  update public.transactions set refund_status = null where id = t.id;
  n1 := public.fn_gl_sync_business();
  select jsonb_agg(jsonb_build_object('acct', l.account_code, 'dr', l.debit, 'cr', l.credit) order by l.account_code)
    into sale from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
   where g.source = 'reveal_fee' and g.source_ref = t.id::text;
  update public.transactions set refund_status = t.refund_status where id = t.id;
  n2 := public.fn_gl_sync_business();
  select jsonb_agg(jsonb_build_object('acct', l.account_code, 'dr', l.debit, 'cr', l.credit) order by l.account_code)
    into ref from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
   where g.source = 'refund_paid' and g.source_ref = t.id::text;

  if sale is null then raise exception 'CHK<<PROBE FAILED: the paid test reveal posted no sale (tx %)>>', t.id; end if;
  if (select sum((x->>'dr')::numeric) - sum((x->>'cr')::numeric) from jsonb_array_elements(sale) x) <> 0
     or (select sum((x->>'cr')::numeric) from jsonb_array_elements(sale) x where x->>'acct' = '4000') <> v_gross
    then raise exception 'CHK<<PROBE FAILED: sale unbalanced or not the amount charged (% vs %)>>', sale, v_gross; end if;
  if ref is null then raise exception 'CHK<<PROBE FAILED: the test refund posted no reversal (tx %)>>', t.id; end if;
  if (select sum((x->>'cr')::numeric) from jsonb_array_elements(ref) x where x->>'acct' = '1050') <> v_gross
     or (select sum((x->>'dr')::numeric) from jsonb_array_elements(ref) x) <> (select sum((x->>'cr')::numeric) from jsonb_array_elements(ref) x)
    then raise exception 'CHK<<PROBE FAILED: the refund does not take back the % charged: %>>', v_gross, ref; end if;
  raise exception 'CHK<<PROBE OK tx=% pi=%… charged=% sale=% refund=% journals_before=%>>',
    t.id, left(t.payment_ref, 8), v_gross, sale, ref, v_real_before;
end $$;
