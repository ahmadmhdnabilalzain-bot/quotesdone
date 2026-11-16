-- an_incident_is_one_per_cause_and_the_it_engineers_model_says_who_it_reaches_probe.sql (it_engineer, OPS_LOOPS, 16 Nov 2026)
-- A pure probe, run AFTER the file in the SAME transaction on a LOCAL Postgres 16 (scripts/db/local_pg16.mjs); it always
-- aborts (raise 'CHK<<...>>'), so nothing it writes survives. Its findings are its own rows; no message is queued to anyone
-- (the notice duty is not run). Run twice on 16 Nov 2026: PROBE OK.
do $probe$
declare
  h1 bigint; h2 bigint; h3 bigint; h4 bigint; i1 bigint; i2 bigint; i3 bigint; i4 bigint; r jsonb; v_q bigint; v_res jsonb;
  mk constant text := 'probe-ops-loops';
begin
  -- an it.finding handoff, as the IT loop files it; the first three share one cause, the fourth is internal
  insert into public.agent_actions (agent, kind, status, risk, title, detail, decided_at, target_table, target_id)
  values ('sales_engineer', 'handoff', 'pending', 'high', 'Probe: quote page fails 1',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'severity', 'high', 'issue_key', 'watch:quote_page:' || mk || ':1',
                             'title', 'Probe: quote page answers 500', 'where_it_is', 'supplier_api quote page', 'subject', 'supplier_api',
                             'occurrence_started_at', now() - interval '3 hours', 'finding_evidence', jsonb_build_object('public_surface', true)),
          now(), 'it_engineer_finding', 'it.finding:probe:' || mk || ':h1') returning id into h1;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, decided_at, target_table, target_id)
  values ('sales_engineer', 'handoff', 'pending', 'high', 'Probe: quote page fails 2',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'severity', 'high', 'issue_key', 'watch:quote_page:' || mk || ':2',
                             'title', 'Probe: quote page answers 500', 'where_it_is', 'supplier_api quote page', 'subject', 'supplier_api',
                             'occurrence_started_at', now() - interval '2 hours', 'finding_evidence', jsonb_build_object('public_surface', true)),
          now(), 'it_engineer_finding', 'it.finding:probe:' || mk || ':h2') returning id into h2;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, decided_at, target_table, target_id)
  values ('sales_engineer', 'handoff', 'pending', 'high', 'Probe: quote page fails 3',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'severity', 'high', 'issue_key', 'watch:quote_page:' || mk || ':3',
                             'title', 'Probe: quote page answers 500', 'where_it_is', 'supplier_api quote page', 'subject', 'supplier_api',
                             'occurrence_started_at', now() - interval '1 hour', 'finding_evidence', jsonb_build_object('public_surface', true)),
          now(), 'it_engineer_finding', 'it.finding:probe:' || mk || ':h3') returning id into h3;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, decided_at, target_table, target_id)
  values ('it_engineer', 'handoff', 'pending', 'high', 'Probe: a heartbeat step was slow',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'severity', 'high', 'issue_key', 'duty:probe_slow:' || mk,
                             'title', 'Probe: a heartbeat step was slow', 'where_it_is', 'resilience_ping', 'subject', 'resilience_ping',
                             'occurrence_started_at', now() - interval '1 hour', 'finding_evidence', jsonb_build_object('public_surface', false)),
          now(), 'it_engineer_finding', 'it.finding:probe:' || mk || ':h4') returning id into h4;
  i1 := public.fn_it_incident_open(h1); i2 := public.fn_it_incident_open(h2); i3 := public.fn_it_incident_open(h3); i4 := public.fn_it_incident_open(h4);
  update public.it_incident set cause = 'Probe cause: a missing index on the quote read' where id = i1;

  -- 1. three occurrences of one cause are one root with three occurrences; the internal one is its own root
  r := public.fn_it_incident_collapse(5000);
  if (select same_cause_as from public.it_incident where id = i1) is not null then raise exception 'CHK<<PROBE FAILED: the first occurrence is not the root>>'; end if;
  if (select same_cause_as from public.it_incident where id = i2) is distinct from i1 or (select same_cause_as from public.it_incident where id = i3) is distinct from i1 then
    raise exception 'CHK<<PROBE FAILED: a later occurrence of the same cause was not folded into its root: %>>', r; end if;
  if (select occurrences from public.it_incident where id = i1) is distinct from 3 then raise exception 'CHK<<PROBE FAILED: the root does not count its occurrences>>'; end if;
  if (select cause from public.it_incident where id = i3) not like 'Same cause as incident ' || i1 || ': Probe cause%' then
    raise exception 'CHK<<PROBE FAILED: an occurrence does not carry its root''s cause>>'; end if;
  if (select same_cause_as from public.it_incident where id = i4) is not null then raise exception 'CHK<<PROBE FAILED: a different cause was folded>>'; end if;
  if exists (select 1 from public.it_incident_register where id in (i2, i3)) then raise exception 'CHK<<PROBE FAILED: the register shows occurrences>>'; end if;
  r := public.fn_it_incident_collapse(5000);
  if (select occurrences from public.it_incident where id = i1) is distinct from 3 then raise exception 'CHK<<PROBE FAILED: a second run counted again>>'; end if;

  -- 2. the customer-facing root is asked of the it_engineer's model once; the internal root is judged by the detector's flag
  r := public.fn_it_incident_impact_ask(50);
  select id into v_q from public.reasoning_held_question where dedupe_key = 'incident_impact:' || i1;
  if v_q is null then raise exception 'CHK<<PROBE FAILED: no impact question was filed for the customer-facing root: %>>', r; end if;
  if exists (select 1 from public.reasoning_held_question where dedupe_key in ('incident_impact:' || i2, 'incident_impact:' || i3, 'incident_impact:' || i4)) then
    raise exception 'CHK<<PROBE FAILED: an occurrence or an internal root was asked of the model>>'; end if;
  if (select seat || '/' || surface from public.reasoning_held_question where id = v_q) <> 'it_engineer/it_engineer.incident_impact' then
    raise exception 'CHK<<PROBE FAILED: the question is not the it_engineer''s>>'; end if;
  if (select request->'decision'->'options' from public.reasoning_held_question where id = v_q) is null
     or (select request->'context'->'case'->>'occurrences' from public.reasoning_held_question where id = v_q) <> '3' then
    raise exception 'CHK<<PROBE FAILED: the question does not carry the choice and the facts>>'; end if;
  if (select impact_judgement->>'by' from public.it_incident where id = i4) is distinct from 'detector' then
    raise exception 'CHK<<PROBE FAILED: the internal root was not recorded as judged by the detector>>'; end if;
  r := public.fn_it_incident_impact_ask(50);
  if (select count(*) from public.reasoning_held_question where dedupe_key = 'incident_impact:' || i1) <> 1 then
    raise exception 'CHK<<PROBE FAILED: the root was asked twice>>'; end if;

  -- 3. an answer outside the four options applies nothing; the model's 'suppliers' answer reaches the notice duty's column
  v_res := public.fn_reason_apply_it_engineer__incident_impact(v_q, jsonb_build_object('status', 'answered', 'answer', 'x',
             'decision', jsonb_build_object('choice', 'partners')));
  if v_res is not null or (select customer_impact from public.it_incident where id = i1) is not null then
    raise exception 'CHK<<PROBE FAILED: an invented option was applied>>'; end if;
  v_res := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub',
             'answer', 'Opening a quotation request in the supplier portal is failing for some suppliers right now.',
             'decision', jsonb_build_object('choice', 'suppliers')));
  if (v_res->>'status') is distinct from 'applied' then raise exception 'CHK<<PROBE FAILED: the answer was not applied: %>>', v_res; end if;
  if (select customer_impact from public.it_incident where id = i1) is distinct from 'suppliers'
     or (select customer_note_en from public.it_incident where id = i1) not like 'Opening a quotation request%' then
    raise exception 'CHK<<PROBE FAILED: customer_impact / customer_note_en were not written>>'; end if;
  if exists (select 1 from public.it_incident where id in (i2, i3) and customer_impact is not null) then
    raise exception 'CHK<<PROBE FAILED: an occurrence carries the impact, so people would be told twice>>'; end if;

  raise exception 'CHK<<PROBE OK>>';
end $probe$;
