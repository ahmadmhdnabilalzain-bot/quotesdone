-- a_reserved_fixture_number_is_a_fixture_to_the_gateway_and_to_case_teardown.sql
-- Seat: customer_support (with it_engineer's gateway fence). Re-check of 12 Nov 2026 (R11, R12); ledger 1642.
-- MEASURED (production, read 12 Nov 2026): fn_ai_subject_is_fixture('{"phone":"whatsapp:+971500000004"}') answered
-- {"fixture": false}, so an untagged call about a reserved WhatsApp fixture number reached a paid model (the re-ask of fixture
-- turns: 16 calls, USD 0.41, in one audit run); and fn_support_case_is_demo answered false for a case of a fixture number with no
-- account, so the demo purge refused its cases and the auditor gave the profiles a reserved e-mail by hand.
-- WHAT THIS CHANGES (CREATE OR REPLACE, bodies as read from production 12 Nov 2026, each with one addition):
--   fn_ai_subject_is_fixture   a subject naming a reserved number (phone, to_phone, wa_from, from) is a fixture.
--   fn_support_case_is_demo    a case whose party id or profile phone tail is a reserved number is demo.
-- fn_is_demo_phone (the estate's one reserved-number predicate) decides both.
-- Apply: any order against the deploys. Probe: a_reserved_fixture_number_is_a_fixture_to_the_gateway_and_to_case_teardown_probe.sql.

create or replace function public.fn_ai_subject_is_fixture(p_subject jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uuid  constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_harness constant text := '^qd-([a-z0-9]+)-[^@]*@example[.](invalid|com|net|org)$';
  v_inq  text := nullif(btrim(coalesce(p_subject ->> 'inquiry_id', '')), '');
  v_cust text := nullif(btrim(coalesce(p_subject ->> 'customer_id', '')), '');
  v_sup  text := nullif(btrim(coalesce(p_subject ->> 'supplier_id', '')), '');
  v_emails text[] := array[]::text[];
  v_e text; v_tag text;
begin
  -- A RESERVED FIXTURE NUMBER IS A FIXTURE (12 Nov 2026, re-check R11): the block +971 50 000 00xx is ours by definition
  -- (fn_is_demo_phone), whatever window is open. Without this the gateway answered false for a WhatsApp fixture subject, and
  -- the re-ask of fixture turns made 16 untagged paid calls (USD 0.41) in one audit run. A tagged run inside its open window
  -- is let through by ai_gateway before this is asked, so a rehearsal still reaches the model, tagged and capped.
  if public.fn_is_demo_phone(p_subject ->> 'phone') or public.fn_is_demo_phone(p_subject ->> 'to_phone')
     or public.fn_is_demo_phone(p_subject ->> 'wa_from') or public.fn_is_demo_phone(p_subject ->> 'from') then
    return jsonb_build_object('fixture', true, 'why', 'a reserved fixture number (+971 50 000 00xx)');
  end if;
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
$function$;

create or replace function public.fn_support_case_is_demo(p_case_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((
    select public.fn_party_is_demo(c.party_kind, c.party_id)
        or coalesce(public.fn_is_demo_email(p.email), false)
        or (p.customer_id is not null and coalesce(public.fn_customer_is_demo(p.customer_id), false))
        or (p.lead_id is not null and coalesce(public.fn_supplier_is_demo(p.lead_id), false))
        -- a fixture number with no account (re-check R12): the reserved block is demo by definition
        or public.fn_is_demo_phone(c.party_id)
        or (p.phone_tail is not null and public.fn_is_demo_phone('971' || p.phone_tail))
      from public.support_case c left join public.support_customer_profile p on p.id = c.customer_profile_id
     where c.case_id = p_case_id), false)
$function$;

revoke execute on function public.fn_ai_subject_is_fixture(jsonb) from public, anon, authenticated;
revoke execute on function public.fn_support_case_is_demo(bigint) from public, anon, authenticated;
grant execute on function public.fn_ai_subject_is_fixture(jsonb) to service_role;
grant execute on function public.fn_support_case_is_demo(bigint) to service_role;
