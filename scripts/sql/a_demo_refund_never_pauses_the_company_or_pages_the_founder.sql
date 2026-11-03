-- A DEMO REFUND NEVER PAUSES THE COMPANY'S REFUNDS OR PAGES THE FOUNDER.
--
-- Assigned: accountant. 3 Nov 2026. Gap #8 of docs/release/qualification_matrix.md (a test-mode refund end to end).
--
-- WHAT WAS MEASURED. The first Stripe TEST-mode refund driven end to end on a ZZ DEMO reveal (run acpay01: CEO approved
-- on the checklist, the accountant refunded AED 150 with the test key, Stripe's refund.created, charge.refunded and
-- refund.updated all settled refund 78197 once) was followed by fn_ceo_refund_verify. Two items of its checklist,
-- customer_told and supplier_told, can never pass for a demo payment: fn_seat_handoff files no handoff from a demo
-- row (founder instruction 1199: no agent works on demo data as if it were real), so the refund.paid notices that
-- prove them are never written. The verdict therefore failed and fn_ceo_refund_mismatch_playbook ran:
--   * it set decision_policy refunds_and_supplier_charges_paused = true, the COMPANY-WIDE circuit breaker, so every
--     later refund and supplier charge, real ones included, stopped (runs acpay02/03: execute_refunds answered
--     paused:true for CEO-approved refunds 78200 and 78201);
--   * fn_ceo_incident_advance sent the founder four founder_alert e-mails (status sent) about reveals #30e17bdd and
--     #7ed02d8b, both ZZ DEMO payments on @example.invalid customers.
-- The demo teardown deletes refund_incident rows but never lifts the breaker, so it stays on after the run.
--
-- THE FIX. Test money never reaches the books (fn_gl_sync_business, 15 Sep 2026), and now it never reaches the
-- circuit breaker or the founder either: for a demo transaction fn_ceo_refund_verify returns its checklist verdict,
-- marked demo, and opens no incident. A real payment is verified exactly as before.
-- THE REPAIR, once: incidents on demo transactions are removed (what the demo teardown does), and the breaker is
-- lifted only if no incident on a real payment is open or paused.
--
-- prevented by: scripts/sql/a_demo_refund_never_pauses_the_company_or_pages_the_founder_probe.sql
create or replace function public.fn_ceo_refund_verify(p_transaction_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb; v_inc bigint;
begin
  -- A demo payment is checked and the verdict returned, but it never opens an incident: the incident pauses every
  -- refund and supplier charge in the company and pages the founder (3 Nov 2026, gap #8).
  -- DEMO MEANS THE IDENTITY THAT PICKS THE STRIPE TEST KEY: the e-mail (isDemoEmail in stripe_checkout,
  -- fn_is_demo_email here). customers.is_demo is also true by NAME or phone, and a name is typed freely at sign-up,
  -- so a real customer who calls himself "ZZ DEMO ..." pays LIVE money and must still open the incident (review of #1835).
  if exists (select 1 from public.transactions t join public.customers c on c.id = t.customer_id
              where t.id = p_transaction_id and public.fn_is_demo_email(c.email)) then
    return public.fn_ceo_refund_checklist(p_transaction_id, 'verify', true) || jsonb_build_object('demo', true, 'incident', null);
  end if;
  -- An incident already open on this payment owns the re-verification: it re-runs the checklist and
  -- either closes (and resumes) or stays paused. A second incident on the same money is never opened.
  select id into v_inc from public.refund_incident i
   where i.transaction_id = p_transaction_id and i.status in ('open', 'paused') order by id desc limit 1;
  if v_inc is not null then
    return jsonb_build_object('incident', v_inc, 'advance', public.fn_ceo_incident_advance(v_inc, 0));
  end if;
  v := public.fn_ceo_refund_checklist(p_transaction_id, 'verify', true);
  if (v->>'ok')::boolean then return v; end if;
  return v || jsonb_build_object('incident', public.fn_ceo_refund_mismatch_playbook(p_transaction_id, v));
end $function$;

-- The repair. Demo incidents go, as the teardown removes them; the breaker comes off only when nothing real holds it.
delete from public.refund_incident i
 using public.transactions t, public.customers c
 where t.id = i.transaction_id and c.id = t.customer_id and public.fn_is_demo_email(c.email);

update public.decision_policy set value = 'false'::jsonb, updated_at = now()
 where key = 'refunds_and_supplier_charges_paused'
   and value = 'true'::jsonb
   and not exists (select 1 from public.refund_incident i where i.status in ('open', 'paused'));
