// THE KNOWLEDGE BASE WAS FINISHED AND THE PRODUCT COULD NOT SEE IT.
//
// The spec ships 84 UAE supplier categories, and production carries all of them in
// catalog_supplier_categories with all 8 knowledge modules each, backed by a 112,611-record
// corpus. The live customer intake path does not use that vocabulary: inquiry_intake/index.ts:93
// loads `select category from category_specs` — a 56-slug legacy taxonomy — and every inquiry is
// filed under one of those. Measured 6 Aug 2026, the overlap between the two vocabularies is
// EXACTLY ZERO, so an inquiry's own category can never name a catalogue entry directly.
//
// The bridge is public.lead_trade_map(trade_key -> catalog_slug). It already worked for 16 of the
// 56 (the ones whose slug happens to equal a taxonomy_trade code) and nothing had ever extended it
// to the rest. So this is not a new mechanism, a new table, or a change to the request path — it
// is 38 rows in a map that already exists and is already read.
//
// WHY NOT REPOINT inquiry_intake AT THE CATALOGUE INSTEAD: category_specs does double duty. It is
// the category vocabulary AND the required-field checklist that fn_rfq_required_check reads and
// trg_rfq_complete computes rfq_ready from. Swapping the vocabulary would leave every new inquiry
// failing its checklist, and dispatch_inquiry answers that with {"ok":true,"skip":"not_rfq_ready"}
// — a 200 that contacts nobody. Extending the map keeps the checklist and the matcher untouched.
//
// TWO SLUGS ARE LEFT UNMAPPED ON PURPOSE. 'general' and 'general-services-other' are the catch-alls
// the intake falls back to when it could not classify. Pointing them at a real catalogue category
// would attach confident, specific trade knowledge to precisely the inquiries the system has
// admitted it does not understand — worse than attaching none, and invisible once it happens.
//
// Reference DATA, applied directly and not as a migration: a migration breaks the 712-vs-712
// ledger parity verify_phase1.mjs asserts.
//
//   node scripts/archive/seed_category_bridge.mjs              # apply to staging, then verify
//   node scripts/archive/seed_category_bridge.mjs --print-sql  # emit the statement for production
import { mgmtRead, mgmtWrite, resolveStagingRef } from '../lib/qd_guard.mjs';

const REF = resolveStagingRef(process.argv[2]);

// legacy category_specs slug -> catalog_supplier_categories.slug
// Each mapping follows the spec's own grouping; the spec section is named where it is not obvious.
export const BRIDGE = {
  'acrylic': 'signage-and-printing-suppliers',
  'av-systems': 'av-and-media-equipment-suppliers',
  'blinds-curtains': 'textile-and-uniform-suppliers',            // spec 51: "Curtains & upholstery"
  'carpentry': 'joinery-and-carpentry-suppliers',
  'carpentry-joinery': 'joinery-and-carpentry-suppliers',
  'carpets': 'flooring-suppliers',                               // spec 8: flooring incl. carpet
  'combined-mep': 'mep-suppliers-electromechanical-suppliers',
  'commercial-retail-fitout': 'fit-out-contractors-interior-fit-out-suppliers',
  'custom-furniture': 'furniture-suppliers-ff-and-e-suppliers',
  'demolition': 'construction-materials-suppliers',              // spec 1: civil & building
  'engineering-and-architectural-consultancies': 'testing-inspection-and-certification-companies', // spec 65
  'epoxy-flooring': 'flooring-suppliers',                        // spec 8: flooring incl. epoxy
  'facade-cleaning': 'cleaning-companies',
  'fitout': 'fit-out-contractors-interior-fit-out-suppliers',
  'garage-doors': 'aluminium-and-glass-suppliers',               // UAE shutter/garage doors are alu fabrication
  'general-building-contracting': 'construction-materials-suppliers',
  'generators': 'electrical-suppliers',                          // spec 2 MEP: "Generators, UPS & power systems"
  'glass': 'aluminium-and-glass-suppliers',
  'insulation': 'insulation-suppliers',
  'interior-design': 'interior-decoration',
  'it-networking': 'it-companies-it-services-providers',
  'job-shop-manufacturing': 'industrial-equipment-suppliers',    // spec 40: manufacturing by process
  'kitchens': 'kitchen-and-bathroom-suppliers',
  'marble-granite': 'flooring-suppliers',                        // spec 8: flooring incl. marble
  'masonry': 'construction-materials-suppliers',
  'mep': 'mep-suppliers-electromechanical-suppliers',
  'movers': 'logistics-and-freight-forwarding-companies',
  'pest': 'facilities-management-companies',                     // spec 30 FM: "Pest control"
  'roofing': 'roofing-suppliers',
  'safety': 'fire-fighting-equipment-suppliers',                 // judgement: site safety reads as life safety here
  'security': 'security-companies',
  'smart-home': 'smart-home-and-home-automation-suppliers',
  'solar': 'renewable-energy-companies-solar-ev-battery',
  'structural-steel-fabrication': 'steel-and-reinforcement-suppliers',
  'swimming-pools': 'swimming-pool-suppliers-and-contractors',
  'tents-and-shade-structures': 'modular-and-prefab-building-suppliers', // spec 20/66: temporary structures
  'tiling': 'flooring-suppliers',
  'water-tank-cleaning': 'cleaning-companies',
};

const values = Object.entries(BRIDGE)
  .map(([k, v]) => `(${JSON.stringify(k).replace(/"/g, "'")}, ${JSON.stringify(v).replace(/"/g, "'")})`)
  .join(',\n    ');

// on conflict do nothing: the 16 that already resolve keep whatever they have. This script adds
// reach, it never overrides an existing decision.
export const SQL = `insert into public.lead_trade_map (trade_key, catalog_slug) values\n    ${values}\n  on conflict (trade_key) do nothing;`;

if (process.argv.includes('--print-sql')) { console.log(SQL); process.exit(0); }

const before = (await mgmtRead(REF, `select count(*)::int n from public.lead_trade_map`))[0].n;
await mgmtWrite(REF, SQL, 'seed category bridge');
const after = (await mgmtRead(REF, `select count(*)::int n from public.lead_trade_map`))[0].n;

// THE MEASUREMENT THAT MATTERS is not the row count — it is how many of the intake's own slugs can
// now reach a catalogue category, because that is the thing that was zero-for-40.
const reach = (await mgmtRead(REF, `
  with cs as (select distinct category slug from public.category_specs)
  select count(*)::int total,
         count(m.trade_key)::int mapped,
         count(c.slug)::int reaching_catalog
    from cs
    left join public.lead_trade_map m on m.trade_key = cs.slug
    left join public.catalog_supplier_categories c on c.slug = m.catalog_slug`))[0];

console.log(`lead_trade_map ${before} -> ${after} row(s) on ${REF}`);
console.log(`intake slugs: ${reach.total} total, ${reach.mapped} mapped, ${reach.reaching_catalog} reaching a real catalogue category`);
const expected = reach.total - 2; // 'general' and 'general-services-other', unmapped on purpose
if (reach.reaching_catalog < expected) {
  console.log(`INCOMPLETE — expected ${expected} (all but the two catch-alls), got ${reach.reaching_catalog}`);
  process.exitCode = 1;
} else {
  console.log(`OK — every intake category except the two catch-alls now resolves to a catalogue category`);
}
