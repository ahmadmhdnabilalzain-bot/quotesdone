-- PROBE: A DEMO REFUND NEVER PAUSES THE COMPANY'S REFUNDS OR PAGES THE FOUNDER.
--
-- Assigned: accountant. 3 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_demo_refund_never_pauses_the_company_or_pages_the_founder.sql. It always raises, so every row it writes (one
-- ZZ DEMO customer, supplier, request, quote and paid reveal, all on @example.invalid) is rolled back; pg_net and the
-- outbox send only committed rows, so nothing it does can reach anyone.
--
-- PROBE OK only if
--   1. fn_ceo_refund_verify on a demo reveal whose checklist fails answers demo:true and opens NO refund_incident;
--   2. the company-wide breaker reads the same before and after, and no founder_alert was written;
--   3. no incident on a demo transaction is left open or paused (the file's repair);
--   4. anon and authenticated still cannot execute fn_ceo_refund_verify (CREATE OR REPLACE kept the ACL).
do $probe$
declare
  c uuid := gen_random_uuid(); l bigint; i uuid; q uuid; t uuid; v jsonb; b0 jsonb; b1 jsonb; a0 bigint; fails text := '';
begin
  select value into b0 from public.decision_policy where key = 'refunds_and_supplier_charges_paused';
  select count(*) into a0 from public.notifications where type = 'founder_alert';
  insert into public.customers (id, email, full_name, email_verified, locale)
  values (c, 'qd-probeverify-cust1@example.invalid', 'ZZ DEMO probe customer', true, 'en');
  insert into public.leads (company_name, emirate, email, source, tags)
  values ('ZZ DEMO probe supplier', 'Dubai', 'qd-probeverify-sup1@example.invalid', 'demo_factory', array['qd_demo']) returning id into l;
  insert into public.inquiries (customer_id, category, emirate, raw_input, summary, status, provenance)
  values (c, 'aluminium', 'Dubai', 'ZZ DEMO probe', 'ZZ DEMO probe', 'sent', '{"source":"probe"}') returning id into i;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, notes, status, source)
  values (i, l, 5000, 'ZZ DEMO probe', 'submitted', 'form') returning id into q;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged,
                                   customer_price, paid_by, payment_ref, fee_status, revealed_at)
  values (q, i, l, c, 5000, 150, 150, 5000, 'customer', 'pi_probe_verify', 'paid', now() - interval '10 days') returning id into t;

  if not (select is_demo from public.customers where id = c) then fails := fails || ' 0:fixture_not_demo'; end if;
  v := public.fn_ceo_refund_verify(t);
  if coalesce((v->>'demo')::boolean, false) is not true then fails := fails || ' 1:not_marked_demo(' || left(v::text, 200) || ')'; end if;
  if exists (select 1 from public.refund_incident where transaction_id = t) then fails := fails || ' 1:incident_opened'; end if;

  select value into b1 from public.decision_policy where key = 'refunds_and_supplier_charges_paused';
  if b1 is distinct from b0 then fails := fails || ' 2:breaker_moved(' || b0::text || '->' || b1::text || ')'; end if;
  if (select count(*) from public.notifications where type = 'founder_alert') <> a0 then fails := fails || ' 2:founder_paged'; end if;

  if exists (select 1 from public.refund_incident ri join public.transactions tr on tr.id = ri.transaction_id
              join public.customers cu on cu.id = tr.customer_id where cu.is_demo and ri.status in ('open', 'paused')) then
    fails := fails || ' 3:demo_incident_left'; end if;

  if has_function_privilege('anon', 'public.fn_ceo_refund_verify(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_ceo_refund_verify(uuid)', 'execute') then
    fails := fails || ' 4:client_can_execute'; end if;

  raise exception 'CHK<<%>>', case when fails = '' then 'PROBE OK demo verdict=' || coalesce(v->>'ok', 'null') || ' breaker=' || coalesce(b1::text, 'null')
                                    else 'PROBE FAILED:' || fails end;
end $probe$;
