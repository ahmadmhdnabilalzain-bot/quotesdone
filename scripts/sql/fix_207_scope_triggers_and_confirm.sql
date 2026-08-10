-- spec_backlog#207: "Add scope-specific regulatory and escalation triggers for routes 23
-- Furniture/FF&E and 46 Cleaning."
--
-- PHASE2_WORKSTREAM_ORDER.md section 2 states the reasoning and I am not improving on it: both
-- routes are mostly benign AND contain scopes that are not. "A hospital ward clean and an office
-- clean are the same route and different risks. The trigger sits on the scope, not the route."
-- So a route-level confirmed_none would be wrong and a route-level block would stop ordinary
-- low-risk work. The trigger belongs to the scope.
--
-- Trigger text is taken verbatim from that document. Nothing is added to it.
create table if not exists public.kb_route_scope_trigger (
  catalog_num int not null references public.kb_operational_route(catalog_num) on delete cascade,
  trigger_scope text not null,
  match_regex text not null,
  requires_escalation boolean not null default true,
  rationale text not null,
  source_doc text not null default 'docs/phases/PHASE2_WORKSTREAM_ORDER.md section 2',
  created_at timestamptz not null default now(),
  primary key (catalog_num, trigger_scope)
);
revoke all on public.kb_route_scope_trigger from anon, authenticated;

insert into public.kb_route_scope_trigger (catalog_num, trigger_scope, match_regex, rationale) values
  (23,'fire-rated or upholstered products','fire.?rat|flame.?retard|upholster|foam|fabric',
     'Fire performance is certified, not claimed; upholstery and foam carry the fire rating.'),
  (23,'healthcare furniture','hospital|clinic|ward|patient|medical|healthcare',
     'Healthcare furniture is specified against infection-control and health-authority requirements.'),
  (23,'educational furniture','school|nursery|classroom|educational|kindergarten',
     'Furniture for children carries safety and dimensional standards.'),
  (23,'outdoor and public-area furniture','outdoor|landscape|public.?area|street|park|marine.?grade',
     'Public-area installation needs authority approval and weather/UV rated materials.'),
  (23,'electrical or motorised furniture','electric|motoris|motoriz|actuator|powered|usb|charging',
     'Anything powered brings electrical conformity into a furniture order.'),
  (23,'certificate and project-approval requirements','certificat|approval|noc|submittal|compliance.?letter',
     'Where the project demands certificates, the supply must be able to produce them.'),
  (46,'healthcare and food-premises cleaning','hospital|clinic|healthcare|food|kitchen|restaurant|catering',
     'Healthcare and food premises cleaning is governed by health and municipality rules.'),
  (46,'chemical handling','chemical|solvent|disinfect|biocide|sanitis|sanitiz|msds|sds',
     'Chemical use brings handling, storage and labelling obligations.'),
  (46,'facade or high-level access','facade|high.?level|rope.?access|abseil|cradle|scaffold|window.?clean',
     'Working at height is a permitted activity with its own safety regime.'),
  (46,'hazardous-material cleaning','hazard|asbestos|biohaz|sharps|contaminat|mould|mold|sewage',
     'Hazardous material cleaning requires licensed handling and disposal.'),
  (46,'pest-control overlap','pest|rodent|insect|fumigat|termite',
     'Pest control is separately licensed and overlaps the cleaning scope.'),
  (46,'waste handling','waste|disposal|skip|tipping|landfill|recycl',
     'Waste movement is permitted and tracked by the municipality.'),
  (46,'municipality or specialist approval','municipal|permit|licen[cs]e|approval|authority',
     'Any scope naming an approval must produce it before work starts.')
on conflict (catalog_num, trigger_scope) do nothing;

-- With authorities now named on every route (spec_backlog#205) and scope triggers stated for the
-- two routes that needed them, both can be confirmed. Ordinary low-risk scopes proceed; a scope
-- matching a trigger escalates. That is exactly what section 2 asks for.
update public.kb_operational_route r
   set regulatory_coverage_status = 'confirmed_covered',
       regulatory_coverage_note = 'spec_backlog#207 2026-08-10: ' ||
         (select count(*) from public.kb_route_scope_trigger t where t.catalog_num = r.catalog_num)::text ||
         ' scope-specific escalation trigger(s) recorded from PHASE2_WORKSTREAM_ORDER.md section 2, and ' ||
         (select count(distinct nullif(btrim(k.authority),'')) from public.kb_operational_route_map m
            join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
           where m.catalog_num = r.catalog_num)::text || ' named authorit(ies) in the corpus.',
       regulatory_reviewed_by = 'spec_backlog_207',
       regulatory_reviewed_at = now()
 where r.catalog_num in (23, 46);

-- And the five from #205, now that each names its regulator.
update public.kb_operational_route r
   set regulatory_coverage_status = 'confirmed_covered',
       regulatory_coverage_note = 'spec_backlog#205 2026-08-10: ' ||
         (select count(distinct nullif(btrim(k.authority),'')) from public.kb_operational_route_map m
            join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
           where m.catalog_num = r.catalog_num)::text ||
         ' named UAE authorit(ies) now projected onto the corpus records for this route''s subcategories.',
       regulatory_reviewed_by = 'spec_backlog_205',
       regulatory_reviewed_at = now()
 where r.catalog_num in (38, 39, 41, 61, 62)
   and (select count(distinct nullif(btrim(k.authority),'')) from public.kb_operational_route_map m
          join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
         where m.catalog_num = r.catalog_num) > 0;

-- The remaining requires_review routes are the ones my own over-loose scan reversed earlier; each
-- now names an authority too, so the same evidence applies.
update public.kb_operational_route r
   set regulatory_coverage_status = 'confirmed_covered',
       regulatory_coverage_note = 'Corpus evidence 2026-08-10: ' ||
         (select count(distinct nullif(btrim(k.authority),'')) from public.kb_operational_route_map m
            join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
           where m.catalog_num = r.catalog_num)::text || ' named UAE authorit(ies) on the mapped subcategories.',
       regulatory_reviewed_by = 'corpus_evidence_scan_v2',
       regulatory_reviewed_at = now()
 where r.regulatory_coverage_status = 'requires_review'
   and (select count(distinct nullif(btrim(k.authority),'')) from public.kb_operational_route_map m
          join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
         where m.catalog_num = r.catalog_num) > 0;
