CREATE OR REPLACE FUNCTION public.fn_phase_b_baseline_drift()
 RETURNS TABLE(subject text, approved text, live text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare b public.org_phase_baseline%rowtype; v text; r record;
begin
  select * into b from public.org_phase_baseline where phase = 'B';
  if not found then
    subject := 'baseline'; approved := 'a recorded Phase B baseline'; live := 'MISSING';
    return next; return;
  end if;

  -- the counts a reader checks first
  for r in select * from (values
      ('workflows',   (select count(*)::text from public.phase_b_workflow)),
      ('steps',       (select count(*)::text from public.phase_b_workflow_step)),
      ('handoffs',    (select count(*)::text from public.phase_b_handoff)),
      ('cross_department_handoffs',
                      (select count(*)::text from public.phase_b_handoff where handoff_type='cross_department')),
      ('business_objects', (select count(*)::text from public.phase_b_business_object)),
      ('business_rules',   (select count(*)::text from public.phase_b_business_rule)),
      ('gates',            (select count(*)::text from public.phase_b_gate)),
      ('exceptions',       (select count(*)::text from public.phase_b_exception)),
      ('sla_policies',     (select count(*)::text from public.phase_b_sla_policy)),
      ('events',           (select count(*)::text from public.phase_b_event)),
      ('workflow_states',      (select count(*)::text from public.phase_b_workflow_state)),
      ('workflow_transitions', (select count(*)::text from public.phase_b_workflow_transition)),
      ('step_states',          (select count(*)::text from public.phase_b_step_state)),
      ('step_transitions',     (select count(*)::text from public.phase_b_step_transition)),
      ('founder_boundaries',   (select count(*)::text from public.phase_b_founder_boundary)),
      ('crosswalk_classifications', (select count(*)::text from public.phase_b_crosswalk))
    ) t(k, v)
  loop
    if r.v is distinct from (b.counts->>r.k) then
      subject := 'count:'||r.k; approved := b.counts->>r.k; live := r.v; return next;
    end if;
  end loop;

  -- the frozen structure, one digest per subject the founder named
  for r in select * from public.fn_phase_b_structure_digest() loop
    if r.sha256 is distinct from (b.registry_sha256->'structure'->r.subject->>'database') then
      subject := 'structure:'||r.subject;
      approved := coalesce(b.registry_sha256->'structure'->r.subject->>'database', 'NOT RECORDED');
      live := r.sha256; return next;
    end if;
  end loop;

  -- the three founder-stated erratum conditions must still hold
  v := (select count(*)::text from public.fn_phase_b_effective_errata() where not resolved);
  if v <> '0' then
    subject := 'effective_errata_unresolved'; approved := '0'; live := v; return next;
  end if;

  -- and Phase A must still be frozen underneath it
  v := (select count(*)::text from public.fn_phase_a_baseline_drift());
  if v <> '0' then
    subject := 'phase_a_baseline_drift'; approved := '0'; live := v; return next;
  end if;

  return;
end $function$
