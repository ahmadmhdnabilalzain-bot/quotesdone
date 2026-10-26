-- OUR OWN TEST TRAFFIC NEVER REACHES A PAID MODEL.
--
-- Assigned: it_engineer. 22 Sep 2026. Founder instruction 705: "if there is a bug that is costing us
-- something or repeated work, that needs to be checked before we activate."
--
-- MEASURED (22 Sep 2026, production, the founder's hold in force so nothing was spent): ai_cost_log's HELD
-- rows are the demand the paid routes would have served. Only 3 inquiries exist in the last 30 days; the
-- rest of the demand is our own harness. it-post-deploy-smoke.yml ran 94 times in 30 days (every merge to
-- main) and nightly-journey.yml 10 times, and each run drives fixture customers and suppliers through
-- inquiry_intake, quote_compare, the quotation and licence readers and the drawing reader -- the same paid
-- routes a customer takes. Lifting the hold would have bought a model answer for every test.
--
-- THE MARKER MUST BE ONE ONLY THE HARNESS CAN SET (review of #828). The estate's is_demo markers (a ZZ DEMO
-- name, an @example.invalid address, a +9715000000xx number) are typed by whoever signs up, so a customer
-- or supplier could put themselves on the stub path and suppress their own real answer. They are NOT used
-- here. A harness identity is recognised by two facts together:
--   1. its address is the harness's own shape, qd-<run tag>-<kind><n>@example.<tld> (scripts/e2e/fixtures.mjs
--      demoEmail, created through the Auth ADMIN API by scripts/staging/demo_factory.mjs mkAuthUser), AND
--   2. public.rehearsal_window holds a row for 'qd_run:<run tag>'. That table has RLS on with no grant to
--      anon or authenticated (measured 22 Sep: 392 rows, grants null): only the harness, through the
--      Management API, can write it. Measured: 5 of 5 harness auth users (tags dbd6c21f, founderdemo)
--      have their window.
-- A person who signs up with such an address still needs a run tag the harness opened, cannot receive
-- mail there, and would only replace their own model answer with the deterministic one.
--
-- WHAT THIS CHANGES: one routine, public.fn_ai_subject_is_fixture(jsonb). ai_gateway's internal callers
-- name the SUBJECT they are working on -- {inquiry_id, customer_id, supplier_id, email} taken from rows they
-- loaded or a verified session -- and the gateway asks this before any paid call. The subject is reduced to
-- the address of the identity behind it (an inquiry's customer, a supplier's claimant or email), and that
-- address is judged by the two facts above. It answers {fixture:true, why} or {fixture:false}. A malformed
-- id is not a fixture and not an error. Only a service-role caller can execute it.
--
-- WHAT THIS DOES NOT CHANGE: no model, tier, route, rate limit or money cap (instructions 639 and 705); no
-- existing fixture definition; no row is written. drawing_boq and drawing_redact do not pass a subject yet
-- (other agents own that code this week); until they do, their fixture traffic is held by the hold alone.
--
-- Deploy order: apply THIS first, then deploy ai_gateway. A gateway deployed first answers every call that
-- names a subject with the stub (the check cannot answer yet) -- which, with the hold in force, is exactly
-- what the hold already does.
--
-- Probe: scripts/sql/our_own_test_traffic_never_reaches_a_paid_model_probe.sql (verdict row, read-only).

create or replace function public.fn_ai_subject_is_fixture(p_subject jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_uuid  constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_harness constant text := '^qd-([a-z0-9]+)-[^@]*@example[.](invalid|com|net|org)$';
  v_inq  text := nullif(btrim(coalesce(p_subject ->> 'inquiry_id', '')), '');
  v_cust text := nullif(btrim(coalesce(p_subject ->> 'customer_id', '')), '');
  v_sup  text := nullif(btrim(coalesce(p_subject ->> 'supplier_id', '')), '');
  v_emails text[] := array[]::text[];
  v_e text; v_tag text;
begin
  if nullif(btrim(coalesce(p_subject ->> 'email', '')), '') is not null then
    v_emails := v_emails || lower(btrim(p_subject ->> 'email'));
  end if;
  if v_inq ~ v_uuid then
    v_emails := v_emails || array(select lower(btrim(c.email)) from public.inquiries i
                                   join public.customers c on c.id = i.customer_id
                                  where i.id = v_inq::uuid and c.email is not null);
  end if;
  if v_cust ~ v_uuid then
    v_emails := v_emails || array(select lower(btrim(c.email)) from public.customers c where c.id = v_cust::uuid and c.email is not null);
  end if;
  if v_sup ~ '^[0-9]{1,18}$' then
    v_emails := v_emails || array(select lower(btrim(x)) from public.leads l, unnest(array[l.claimed_by, l.email]) x
                                   where l.id = v_sup::bigint and x is not null);
  end if;
  foreach v_e in array v_emails loop
    v_tag := substring(v_e from v_harness);
    if v_tag is not null and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || v_tag) then
      return jsonb_build_object('fixture', true, 'why', 'an identity of harness run ' || v_tag || ' (opened in rehearsal_window)');
    end if;
  end loop;
  return jsonb_build_object('fixture', false);
end
$fn$;

comment on function public.fn_ai_subject_is_fixture(jsonb) is
  'ai_gateway asks this before any paid call: is the named subject (inquiry, customer, supplier, email) an identity our E2E harness created? Only the harness address shape AND a rehearsal_window row for its run tag count. A name, domain or number a user can type never does. Founder instruction 705, 22 Sep 2026.';

revoke execute on function public.fn_ai_subject_is_fixture(jsonb) from public, anon, authenticated;
