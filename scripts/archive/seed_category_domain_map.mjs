// THE TWO HALVES OF THE FOUNDER'S OWN SPEC HAD NO LINK BETWEEN THEM.
//
// The suppliers-categories spec is two cuts of the same space: 66 grouped FAMILIES (Construction &
// Civil, MEP, Interior Fit-Out …) and an 84-item "Realistic Suppliers Categories List (UAE)".
// Both are loaded — catalog_domains 67, catalog_supplier_categories 86 — and the 1 GB knowledge
// corpus is organised by the FAMILY: kb_stage.questions carries 16,588 qualification questions
// (7,079 mandatory, 14,051 with conditional activation, 14,051 bilingual) keyed by family slug.
//
// Nothing joins the two. Measured 6 Aug 2026, every candidate bridge is a different vocabulary:
//   kb_stage.questions.category_slug  -> 64 of 67 match catalog_domains.slug
//   catalog_supplier_categories       -> no domain column at all
//   category_agent_map.agent_slug     -> catalogue-style ('travel-agencies'), 84 distinct
//   catalog_subcategories.agent_slug  -> short legacy ('false-ceiling'), 17 distinct, 0 overlap
//   kb_operational_route.route_key    -> 'opcat-001', a scheme of its own
//   kb_stage.categories.aliases       -> free-text search terms, and empty for some families
//
// So the link is authored, not derived. Each line below places one of the 84 UAE categories inside
// the family whose knowledge package covers it, following the spec's own grouping — 'Aluminium &
// Glass Suppliers' sits under family 8 'Interior Fit-Out, Finishes & Joinery' because that is where
// the spec lists aluminium systems and glazing.
//
// Why this matters: without it, 16,588 structured qualification questions - the spec's own
// "Inquiry Qualification Logic" - cannot be reached from a customer's inquiry, which is why
// inquiry_intake still flattens category_specs.fields into a static prompt list with no ask-order
// and no conditional activation.
//
//   node scripts/seed_category_domain_map.mjs <staging-ref>
//   node scripts/seed_category_domain_map.mjs --print-sql
import { mgmtRead, mgmtWrite, resolveStagingRef } from './staging/qd_guard.mjs';

export const MAP = {
  'construction-materials-suppliers': 'construction-civil-and-building-materials',
  'steel-and-reinforcement-suppliers': 'construction-civil-and-building-materials',
  'cement-and-concrete-suppliers': 'construction-civil-and-building-materials',
  'formwork-and-scaffolding-suppliers': 'construction-civil-and-building-materials',
  'waterproofing-suppliers': 'construction-civil-and-building-materials',
  'insulation-suppliers': 'construction-civil-and-building-materials',
  'roofing-suppliers': 'construction-civil-and-building-materials',
  'modular-and-prefab-building-suppliers': 'construction-civil-and-building-materials',
  'mep-suppliers-electromechanical-suppliers': 'mep-mechanical-electrical-plumbing',
  'hvac-suppliers': 'mep-mechanical-electrical-plumbing',
  'electrical-suppliers': 'mep-mechanical-electrical-plumbing',
  'plumbing-and-sanitaryware-suppliers': 'mep-mechanical-electrical-plumbing',
  'utility-contractors-dewa-sewa-fewa-approved': 'utilities',
  'gas-systems-suppliers-lpg-medical-gas-industrial-gas': 'gas-systems',
  'wastewater-and-drainage-contractors': 'wastewater-and-drainage',
  'fire-fighting-equipment-suppliers': 'firefighting-life-safety-and-security',
  'fire-alarm-and-life-safety-suppliers': 'firefighting-life-safety-and-security',
  'security-companies': 'firefighting-life-safety-and-security',
  'elv-and-security-systems-suppliers': 'elv-smart-systems-and-home-automation',
  'smart-home-and-home-automation-suppliers': 'elv-smart-systems-and-home-automation',
  'fit-out-contractors-interior-fit-out-suppliers': 'interior-fit-out-finishes-and-joinery',
  'gypsum-and-false-ceiling-suppliers': 'interior-fit-out-finishes-and-joinery',
  'flooring-suppliers': 'interior-fit-out-finishes-and-joinery',
  'aluminium-and-glass-suppliers': 'interior-fit-out-finishes-and-joinery',
  'joinery-and-carpentry-suppliers': 'interior-fit-out-finishes-and-joinery',
  'paints-and-finishing-materials-suppliers': 'interior-fit-out-finishes-and-joinery',
  'kitchen-and-bathroom-suppliers': 'interior-fit-out-finishes-and-joinery',
  'signage-and-printing-suppliers': 'printing-packaging-and-office-supplies',
  'interior-decoration': 'interior-decoration-and-styling',
  'furniture-suppliers-ff-and-e-suppliers': 'furniture-ff-and-e-and-loose-items',
  'swimming-pool-suppliers-and-contractors': 'swimming-pools-spas-and-water-features',
  'cold-room-and-refrigeration-suppliers': 'cold-rooms-refrigeration-and-cold-chain',
  'catering-companies': 'catering-f-and-b-and-hospitality-services',
  'hospitality-supplies-companies': 'hospitality-supplies',
  'bakery-equipment-suppliers': 'bakery-and-food-processing',
  'food-processing-equipment-suppliers': 'bakery-and-food-processing',
  'av-and-media-equipment-suppliers': 'media-av-production-and-creative-equipment',
  'marketing-and-advertising-agencies': 'marketing-media-events-and-creative-services',
  'event-management-companies': 'marketing-media-events-and-creative-services',
  'exhibition-stand-contractors': 'exhibition-industry',
  'it-companies-it-services-providers': 'it-technology-and-digital-services',
  'data-centre-suppliers-and-service-providers': 'data-centres',
  'telecommunication-companies': 'telecommunications',
  'accounting-and-audit-firms': 'accounting-finance-and-corporate-services',
  'tax-consultants': 'accounting-finance-and-corporate-services',
  'corporate-service-providers-pro-services': 'accounting-finance-and-corporate-services',
  'law-firms': 'legal-and-compliance',
  'management-consulting-firms': 'business-consulting',
  'hr-and-recruitment-agencies': 'human-resources-and-recruitment',
  'staffing-companies': 'human-resources-and-recruitment',
  'facilities-management-companies': 'facilities-management-and-support-services',
  'cleaning-companies': 'facilities-management-and-support-services',
  'business-centres-and-coworking-spaces': 'business-centres-and-coworking',
  'logistics-and-freight-forwarding-companies': 'logistics-transport-and-supply-chain',
  'warehousing-and-3pl-companies': 'logistics-transport-and-supply-chain',
  'oil-and-gas-equipment-suppliers': 'oil-and-gas-energy-and-industrial',
  'industrial-equipment-suppliers': 'oil-and-gas-energy-and-industrial',
  'renewable-energy-companies-solar-ev-battery': 'renewable-energy',
  'industrial-automation-suppliers': 'industrial-automation',
  'bearings-and-power-transmission-suppliers': 'bearings-power-transmission-and-hydraulics',
  'fasteners-and-fixings-suppliers': 'fasteners-and-fixings',
  'tools-and-abrasives-suppliers': 'abrasives-tools-and-industrial-consumables',
  'air-compressor-and-pneumatic-suppliers': 'air-compressors-and-pneumatics',
  'chemical-suppliers': 'chemicals',
  'medical-equipment-suppliers': 'healthcare-medical-and-life-sciences',
  'pharmaceutical-suppliers': 'healthcare-medical-and-life-sciences',
  'laboratory-equipment-suppliers': 'laboratory-and-scientific-suppliers',
  'cleanroom-suppliers-and-contractors': 'cleanrooms-and-controlled-environments',
  'education-equipment-suppliers': 'education-and-training-support',
  'aviation-and-ground-support-suppliers': 'aviation-maritime-and-offshore',
  'offshore-and-marine-construction-companies': 'aviation-maritime-and-offshore',
  'marine-equipment-and-marine-safety-suppliers': 'marine-safety',
  'real-estate-agencies': 'real-estate-services',
  'property-management-companies': 'real-estate-services',
  'textile-and-uniform-suppliers': 'textile-uniforms-and-soft-goods',
  'beauty-and-spa-equipment-suppliers': 'beauty-wellness-and-personal-care',
  'gym-and-sports-equipment-suppliers': 'sports-recreation-and-leisure',
  'jewelry-suppliers-gold-and-diamond-traders': 'jewelry-and-luxury-retail',
  'luxury-and-concierge-service-providers': 'luxury-and-concierge-services',
  'travel-agencies': 'travel-and-tourism-services',
  'domestic-services-companies-maids-care': 'domestic-services',
  'pet-care-and-veterinary-services': 'pet-industry',
  'translation-and-interpretation-companies': 'translation-interpretation-and-localization',
  'tender-and-bid-management-consultants': 'government-tenders-and-procurement-support',
  'testing-inspection-and-certification-companies': 'testing-inspection-certification-and-technical-services',
  // There is NO lifts family: catalog_domains 67 is general-contracting-and-civil-works, and the
  // corpus's separate QD-KB-086-lifts-and-escalators package was never given one. Vertical
  // transportation is conventionally MEP, and that is where its qualification questions belong -
  // load, travel, stops, shaft dimensions and Civil Defence approval are all MEP-shaped questions.
  'lifts-and-escalator-suppliers': 'mep-mechanical-electrical-plumbing',
};

const rows = Object.entries(MAP).map(([c, d]) => `('${c}','${d}')`).join(',\n    ');

// Both columns are foreign-keyed, so a typo in either vocabulary fails loudly at apply time rather
// than becoming a category that silently reaches no questions.
export const SQL = `create table if not exists public.catalog_category_domain (
  catalog_slug text primary key references public.catalog_supplier_categories(slug),
  domain_slug  text not null references public.catalog_domains(slug)
);
insert into public.catalog_category_domain (catalog_slug, domain_slug) values
    ${rows}
  on conflict (catalog_slug) do update set domain_slug = excluded.domain_slug;`;

if (process.argv.includes('--print-sql')) { console.log(SQL); process.exit(0); }

const REF = resolveStagingRef(process.argv[2]);
await mgmtWrite(REF, SQL, 'seed catalog_category_domain');

const m = (await mgmtRead(REF, `
  select (select count(*) from public.catalog_category_domain)::int mapped,
         (select count(*) from public.catalog_supplier_categories)::int categories,
         (select count(distinct domain_slug) from public.catalog_category_domain)::int domains_used,
         (select count(*) from public.catalog_supplier_categories c
            where not exists (select 1 from public.catalog_category_domain m where m.catalog_slug=c.slug))::int unmapped,
         (select count(*) from kb_stage.questions q
            join public.catalog_category_domain m on m.domain_slug = q.category_slug)::int questions_now_reachable`))[0];

console.log(`catalog_category_domain: ${m.mapped}/${m.categories} categories mapped into ${m.domains_used} families`);
console.log(`unmapped: ${m.unmapped}`);
console.log(`qualification questions now reachable from a catalogue category: ${m.questions_now_reachable}`);
process.exitCode = m.unmapped === 0 ? 0 : 1;
