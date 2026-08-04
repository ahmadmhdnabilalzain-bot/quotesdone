-- Correcting myself, same session. The #205 pass marked all 39 researched routes
-- confirmed_covered, including 23 Furniture/FF&E and 46 Cleaning. PHASE2_WORKSTREAM_ORDER.md
-- section 2 says in terms:
--
--   "Do not mark 23 Furniture / FF&E or 46 Cleaning as confirmed_none. Review each and mark
--    confirmed_covered only AFTER scope-specific regulatory and escalation triggers exist."
--
-- The triggers do not exist. Of 2510 kb_stage.records across the eleven subcategories mapped to
-- these two routes, 255 carry an escalation_rule and none of them encode the scope triggers listed
-- in #207. Naming the authority is not the same as having the trigger: a hospital ward clean and an
-- office clean are the same route and different risks, which is the entire point of that ticket.
--
-- So these two go back to requires_review. The authority research is kept in the note — it is
-- correct and re-usable — but the activation gate stays shut until #207 is actually done.
-- Net effect of today's #205 pass: 37 routes unblocked, not 39.

update public.kb_operational_route set
  regulatory_coverage_status = 'requires_review',
  regulatory_reviewed_by = 'claude-research-2026-08-04',
  regulatory_reviewed_at = now(),
  regulatory_coverage_note = regulatory_coverage_note ||
    ' | HELD AT requires_review 4 Aug 2026: authorities are identified above, but spec_backlog#207 '
    'scope-specific regulatory and escalation triggers do not exist yet. '
    'PHASE2_WORKSTREAM_ORDER.md section 2 forbids marking this route confirmed_covered until they do. '
    'Route 23 triggers needed: fire-rated or upholstered products; healthcare furniture; educational '
    'furniture; outdoor and public-area furniture; electrical or motorised furniture; certificate and '
    'project-approval requirements. '
    'Route 46 triggers needed: healthcare and food-premises cleaning; chemical handling; facade or '
    'high-level access; hazardous-material cleaning; pest-control overlap; waste handling; any '
    'activity requiring municipality or specialist approval.'
where catalog_num in (23, 46);;
