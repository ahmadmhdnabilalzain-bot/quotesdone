-- PROBE for a_fixture_asking_for_a_person_never_pages_the_founder.sql (19 Oct 2026, customer_support). Never applied:
-- it always raises CHK<<...>>, rolling back every row it writes (the handoffs, the alert rows and any queued send).
-- Behavioural: one "Talk to a person" from a reserved fixture number must NOT page the founder; since 16 Nov 2026 one from a
-- real-shaped number does not either, and opens the CEO's escalation clock. Paged = a founder_alerts row carrying this probe's event text.
do $probe$
declare v_bad text[] := '{}'; v_tag text := 'probe fixture-person ' || gen_random_uuid(); n int; r jsonb;
begin
  r := public.fn_wa_human_request('+971500000099', true, v_tag || ' fixture', 'probe');
  select count(*) into n from public.founder_alerts where event = v_tag || ' fixture';
  if n <> 0 then v_bad := v_bad || ('fixture number paged the founder: ' || n); end if;
  if (r ->> 'notified') is distinct from 'false' then v_bad := v_bad || ('fixture path notified=' || coalesce(r ->> 'notified', 'null')); end if;

  -- 16 Nov 2026 (every_escalation_carries_a_clock_and_the_ceo_decides_it_not_the_founder.sql): a real-shaped number no longer pages
  -- the founder either; it opens the CEO's escalation clock ('notified' = the clock opened)
  r := public.fn_wa_human_request('+971501234567', true, v_tag || ' real', 'probe');
  select count(*) into n from public.founder_alerts where event = v_tag || ' real';
  if n <> 0 then v_bad := v_bad || ('a real-shaped number paged the founder: ' || n); end if;
  if (r ->> 'notified') is distinct from 'true' or r -> 'escalation_clock' is null then v_bad := v_bad || ('a real-shaped number opened no clock: ' || r::text); end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end);
end $probe$;
