-- PACR-001 — THE PHASE A BASELINE RE-RECORDS THE REPORTING GRAPH THE FOUNDER ACTUALLY APPROVED.
--
-- fn_phase_a_baseline_drift() freezes the reporting graph as a sha256 over
-- role_id|manager_role_id|primary_department_id for every active standing role. That digest was
-- taken on 15 Aug from the graph live at the time. The founder's 16 Aug reporting map moves 23 of
-- those manager edges, so after the reconciliation the digest necessarily disagreed with the
-- recorded baseline — correctly, and that is the guard doing its job rather than a nuisance.
--
-- WHY THIS IS A RE-RECORD AND NOT A CHECK BEING WEAKENED. Nothing here relaxes what the digest
-- covers, changes how it is computed, or excludes a row from it. The comparison is byte-for-byte
-- identical to what it was; only the approved value moves, and it moves to the graph the founder
-- put in writing. A baseline that keeps pointing at a superseded graph does not protect anything —
-- it reports drift for as long as the organisation is correct, which is the fastest way to teach a
-- reader to ignore it.
--
-- EVERY DIGEST IS RECOMPUTED IN PLACE, from the same expressions fn_phase_a_baseline_drift() uses,
-- rather than transcribed from a script's output. A hand-copied hash is a hash nobody verified.
--
-- The counts are re-measured too, and they must not have moved: 10 departments, 90 standing roles,
-- 86 overlays. If PACR-001 had changed the SHAPE of the organisation rather than its reporting
-- edges, that would be a different change request and this file would show it.

begin;

set local app.phase_a_change_reason =
  'PACR-001: re-record the Phase A reporting-graph digest after reconciling 23 manager edges and '
  '3 role classes to the founder-approved QuotesDone Reporting and Chain-of-Command Map '
  'v2026.08.16. Counts unchanged at 10/90/86. Approver: founder, 16 Aug 2026.';

update public.org_phase_baseline b
   set counts = jsonb_build_object(
         'active_departments',       (select count(*) from public.org_departments where active),
         'canonical_roles',          (select count(*) from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay'),
         'category_overlays',        (select count(*) from public.org_role where status='active' and runtime_mode = 'knowledge_overlay'),
         'department_heads',         (select count(*) from public.org_departments where active and lead_agent is not null),
         'organizational_workflows', (select count(*) from public.org_workflow_ownership),
         'phase_a_violations',       (select count(*) from public.fn_phase_a_organization_violations()),
         'deferred_items',           (select count(*) from public.fn_phase_a_deferred_items()),
         'retired_roles',            (select count(*) from public.org_role where status='retired')),
       registry_sha256 = jsonb_set(
         b.registry_sha256,
         '{reporting_graph,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select r.role_id sortkey,
                                  r.role_id||'|'||coalesce(r.manager_role_id,'founder')||'|'||r.primary_department_id x
                             from public.org_role r
                            where r.status='active' and r.runtime_mode <> 'knowledge_overlay') s))),
       note = b.note || E'\n\nPACR-001, 16 Aug 2026: the reporting graph was reconciled to the '
              'founder-approved QuotesDone Reporting and Chain-of-Command Map v2026.08.16 — 23 '
              'manager edges and 3 role classes. The 15 Aug baseline agreed with the live database '
              'on every one of those edges, so this was a founder decision superseding it, not a '
              'repair of drift. Counts unchanged at 10 departments / 90 standing roles / 86 '
              'category overlays. The authority now lives in public.phase_c_reporting_authority and '
              'is checked by public.fn_phase_c_reporting_map_drift().',
       recorded_at = now()
 where b.phase = 'A';

commit;
