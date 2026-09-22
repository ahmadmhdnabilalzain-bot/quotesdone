-- OUR OWN TEST TRAFFIC NEVER REACHES A PAID MODEL.
--
-- Assigned: it_engineer. 22 Sep 2026. Founder instruction 705: "if there is a bug that is costing us
-- something or repeated work, that needs to be checked before we activate."
--
-- MEASURED (22 Sep 2026, production, the founder's hold in force so nothing was spent): ai_cost_log's HELD
-- rows are the demand the paid routes would have served. Only 3 inquiries exist in the last 30 days; the
-- rest of the demand is our own harness. it-post-deploy-smoke.yml ran 94 times in 30 days (every merge to
-- main) and nightly-journey.yml 10 times, and each run drives ZZ DEMO customers and suppliers at
-- @example.invalid addresses (scripts/e2e/fixtures.mjs) through inquiry_intake, quote_compare, the
-- quotation and licence readers and the drawing reader -- the same paid routes a customer takes. Each run
-- makes fresh inquiries, so no cache ever hits across runs. Lifting the hold would have bought a model
-- answer for every test.
--
-- WHAT IS WRONG: ai_gateway could not tell a fixture from a customer. The fixture markers exist and are
-- server-side (customers.is_demo / leads.is_demo are derived from the ZZ DEMO name and the reserved address;
-- fn_inquiry_is_demo; fn_is_demo_email; fn_is_demo_phone), but nothing on the paid path asked them.
--
-- WHAT THIS CHANGES: one routine, public.fn_ai_subject_is_fixture(jsonb). ai_gateway's internal callers name
-- the SUBJECT they are working on -- {inquiry_id, customer_id, supplier_id, email, phone}, taken from rows
-- they already loaded or a verified session -- and the gateway asks this routine before any paid call. A
-- fixture is answered with a no-cost stub (the same 503 shape as the founder's hold, so every caller takes
-- the deterministic path it takes today). The routine reuses the estate's own definitions and adds none:
--   inquiry  -> fn_inquiry_is_demo (demo customer, a qd_run provenance, a demo-fixture brief)
--   customer -> fn_seat_clock_customer_is_fixture (is_demo, a ZZ DEMO name, a reserved email domain)
--   supplier -> fn_seat_clock_lead_is_fixture (is_demo, a ZZ DEMO company, a reserved email or claimant)
--   email    -> fn_is_demo_email, or the customer / lead that address belongs to is a fixture
--   phone    -> fn_is_demo_phone (+9715000000xx)
-- It answers {fixture:true, why} or {fixture:false}. A malformed id is not a fixture and not an error.
-- It is not a flag anyone can set: only a service-role caller can execute it, and it reads rows.
--
-- WHAT THIS DOES NOT CHANGE: no model, tier, route, rate limit or money cap (those are the founder's --
-- instructions 639 and 705); no fixture definition (it calls the existing ones); no row is written.
-- drawing_boq and drawing_redact do not pass a subject yet (other agents own that code this week); until
-- they do, their fixture traffic is still held by the founder's hold, not by this.
--
-- Deploy order: apply THIS first, then deploy ai_gateway. A gateway deployed first answers every call that
-- names a subject with the stub (the check cannot answer yet) -- which, with the hold in force, is exactly
-- what the hold already does, so nothing a customer sees changes either way.
--
-- Probe: scripts/sql/our_own_test_traffic_never_reaches_a_paid_model_probe.sql (verdict row, read-only).
-- Check: scripts/checks/our_own_test_traffic_never_reaches_a_paid_model.test.mjs.

create or replace function public.fn_ai_subject_is_fixture(p_subject jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_inq   text := nullif(btrim(coalesce(p_subject ->> 'inquiry_id', '')), '');
  v_cust  text := nullif(btrim(coalesce(p_subject ->> 'customer_id', '')), '');
  v_sup   text := nullif(btrim(coalesce(p_subject ->> 'supplier_id', '')), '');
  v_email text := lower(nullif(btrim(coalesce(p_subject ->> 'email', '')), ''));
  v_phone text := nullif(btrim(coalesce(p_subject ->> 'phone', '')), '');
  v_uuid  constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  c public.customers;
  l public.leads;
begin
  if v_inq ~ v_uuid and public.fn_inquiry_is_demo(v_inq::uuid) then
    return jsonb_build_object('fixture', true, 'why', 'inquiry ' || v_inq || ' belongs to a demo identity or a harness run');
  end if;
  if v_cust ~ v_uuid then
    select * into c from public.customers where id = v_cust::uuid;
    if found and public.fn_seat_clock_customer_is_fixture(c) then
      return jsonb_build_object('fixture', true, 'why', 'customer ' || v_cust || ' is a demo identity');
    end if;
  end if;
  if v_sup ~ '^[0-9]{1,18}$' then
    select * into l from public.leads where id = v_sup::bigint;
    if found and public.fn_seat_clock_lead_is_fixture(l) then
      return jsonb_build_object('fixture', true, 'why', 'supplier ' || v_sup || ' is a demo identity');
    end if;
  end if;
  if v_email is not null then
    if public.fn_is_demo_email(v_email) then
      return jsonb_build_object('fixture', true, 'why', 'the address is on a reserved test domain');
    end if;
    select * into c from public.customers where lower(btrim(email)) = v_email limit 1;
    if found and public.fn_seat_clock_customer_is_fixture(c) then
      return jsonb_build_object('fixture', true, 'why', 'the address belongs to a demo customer');
    end if;
    select * into l from public.leads where lower(btrim(claimed_by)) = v_email limit 1;
    if not found then select * into l from public.leads where lower(email) = v_email limit 1; end if;
    if found and public.fn_seat_clock_lead_is_fixture(l) then
      return jsonb_build_object('fixture', true, 'why', 'the address belongs to a demo supplier');
    end if;
  end if;
  if v_phone is not null and public.fn_is_demo_phone(v_phone) then
    return jsonb_build_object('fixture', true, 'why', 'the number is in the reserved test range');
  end if;
  return jsonb_build_object('fixture', false);
end
$fn$;

comment on function public.fn_ai_subject_is_fixture(jsonb) is
  'ai_gateway asks this before any paid call: is the named subject (inquiry, customer, supplier, email, phone) one of our own fixtures? Reuses fn_inquiry_is_demo, fn_seat_clock_customer_is_fixture, fn_seat_clock_lead_is_fixture, fn_is_demo_email and fn_is_demo_phone. Founder instruction 705, 22 Sep 2026.';

revoke execute on function public.fn_ai_subject_is_fixture(jsonb) from public, anon, authenticated;
