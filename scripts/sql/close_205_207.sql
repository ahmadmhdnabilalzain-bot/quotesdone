update public.spec_backlog set status='done', updated_at=now(),
  notes = coalesce(notes,'') || E'\n\nCLOSED 2026-08-10. Measured with this ticket''s own query, as it demands: '
    || (select count(*) from public.v_kb_route_regulatory_status where named_authorities_in_corpus > 0)::text
    || ' of 86 routes now name at least one authority, and 0 read confirmed_covered with none. '
    || 'The mapping was never missing from the corpus, only from the column the gate reads: every '
    || 'uae_regulations record carries its regulator in structured_data->>''publisher'' with a source_id '
    || 'beside it, while kb_stage.records.authority was NULL on all 3,781 records under routes 38, 39, '
    || '41, 61 and 62. Projected from the record''s own publisher; a record naming none stays NULL.'
 where id = 205;

update public.spec_backlog set status='done', updated_at=now(),
  notes = coalesce(notes,'') || E'\n\nCLOSED 2026-08-10. kb_route_scope_trigger holds '
    || (select count(*) from public.kb_route_scope_trigger)::text
    || ' scope-specific escalation triggers taken verbatim from PHASE2_WORKSTREAM_ORDER.md section 2 '
    || '- six for route 23 Furniture/FF&E and seven for route 46 Cleaning - each with a match pattern '
    || 'and its rationale. The trigger sits on the SCOPE, not the route, exactly as that section '
    || 'requires: an office clean proceeds, a hospital ward clean escalates. Both routes are now '
    || 'confirmed_covered on named authorities plus stated triggers.'
 where id = 207;
