// SPEC FILE #6, sections 1-2 — the domain taxonomy and the realistic supplier categories.
//
//   §1 Domain Taxonomy            (66) — the spec's 66 numbered group headings
//   §2 Realistic Categories       (84) — the "Realistic Suppliers Categories List (UAE)", 1-84
//
// ── WHY THIS MODULE EXISTS AT ALL, GIVEN THE BRIEF SAYS "DO NOT BUILD A TAXONOMY" ────────────────
// Because "it exists" is a claim, and an unmeasured claim is how row #5 lost a day. The taxonomy
// does exist — but "86 rows in catalog_supplier_categories" is not the same statement as "the 84
// categories THIS SPEC names are present, at the numbers this spec gives them". A table with 86 rows
// could hold 86 categories none of which the spec asked for. So the names are embedded here from the
// spec text and compared item by item; the evidence prints both sides of any mismatch.
//
// Scored as a per-item coverage count over ONE table each (row #5's defect class #3), not 150
// independent greps: the two populations are fetched once and every verdict is a literal computed
// from that one payload.
//
// ── THE SUPERSET IS NOT A FAILURE ────────────────────────────────────────────────────────────────
// Production carries 67 domains and 86 categories against the spec's 66 and 84. The extras
// (domain 67 "General Contracting & Civil Works"; categories 85 "Signage & Printing Suppliers" and
// 86 "Lifts & Escalator Suppliers") are ADDITIONS beyond the spec, not omissions from it. A spec
// requirement is satisfied by presence; a row the spec never asked for cannot fail a requirement
// the spec never wrote. The extras are printed in the evidence so they stay visible, and §2's
// coverage check names the two categories that carry no agent rather than burying them.

export const EXPECTED = 150;

// The spec's 66 numbered group headings, docs/specs_row6_supplier_categories_and_agents.txt L1-653.
const DOMAINS = [
  'Construction, Civil & Building Materials', 'MEP (Mechanical, Electrical, Plumbing)', 'Utilities',
  'Gas Systems', 'Wastewater & Drainage', 'Firefighting, Life Safety & Security',
  'ELV, Smart Systems & Home Automation', 'Interior Fit-Out, Finishes & Joinery', 'Luxury Fit-Out',
  'Interior Decoration & Styling', 'Furniture, FF&E & Loose Items',
  'Swimming Pools, Spas & Water Features', 'Cold Rooms, Refrigeration & Cold Chain',
  'Catering, F&B & Hospitality Services', 'Hospitality Supplies', 'Bakery & Food Processing',
  'Media, AV, Production & Creative Equipment', 'Marketing, Media, Events & Creative Services',
  'Exhibition Industry', 'Temporary Event Infrastructure', 'IT, Technology & Digital Services',
  'Data Centres', 'Telecommunications', 'Accounting, Finance & Corporate Services',
  'Banking & Financial Products', 'Insurance', 'Legal & Compliance', 'Business Consulting',
  'Human Resources & Recruitment', 'Facilities Management & Support Services',
  'Business Centres & Coworking', 'Logistics, Transport & Supply Chain',
  'Oil & Gas, Energy & Industrial', 'Renewable Energy', 'Industrial Automation',
  'Bearings, Power Transmission & Hydraulics', 'Fasteners & Fixings',
  'Abrasives, Tools & Industrial Consumables', 'Air Compressors & Pneumatics',
  'Manufacturing by Process', 'Chemicals', 'Healthcare, Medical & Life Sciences',
  'Laboratory & Scientific Suppliers', 'Cleanrooms & Controlled Environments',
  'Education & Training Support', 'Aviation, Maritime & Offshore', 'Marine Safety',
  'Agriculture, Food Production & Environment', 'Recycling & Circular Economy',
  'Real Estate Services', 'Textile, Uniforms & Soft Goods', 'Beauty, Wellness & Personal Care',
  'Sports, Recreation & Leisure', 'Religious Facilities', 'Jewelry & Luxury Retail',
  'Luxury & Concierge Services', 'Retail & Consumer Goods',
  'Printing, Packaging & Office Supplies', 'Vehicles, Automotive & Equipment',
  'Travel & Tourism Services', 'Domestic Services', 'Pet Industry',
  'Translation, Interpretation & Localization', 'Government Tenders & Procurement Support',
  'Testing, Inspection, Certification & Technical Services', 'Miscellaneous / Catch-All',
];

// The spec's "Realistic Suppliers Categories List (UAE)", L656-740.
const CATEGORIES = [
  'Construction Materials Suppliers', 'Steel & Reinforcement Suppliers',
  'Cement & Concrete Suppliers', 'Formwork & Scaffolding Suppliers', 'Waterproofing Suppliers',
  'Insulation Suppliers', 'Roofing Suppliers', 'MEP Suppliers / Electromechanical Suppliers',
  'HVAC Suppliers', 'Electrical Suppliers', 'Plumbing & Sanitaryware Suppliers',
  'Fire Fighting Equipment Suppliers', 'Fire Alarm & Life Safety Suppliers',
  'ELV & Security Systems Suppliers', 'Smart Home & Home Automation Suppliers',
  'Fit-Out Contractors / Interior Fit-Out Suppliers', 'Gypsum & False Ceiling Suppliers',
  'Flooring Suppliers', 'Aluminium & Glass Suppliers', 'Joinery & Carpentry Suppliers',
  'Paints & Finishing Materials Suppliers', 'Interior Decoration',
  'Furniture Suppliers / FF&E Suppliers', 'Kitchen & Bathroom Suppliers',
  'Swimming Pool Suppliers & Contractors', 'Cold Room & Refrigeration Suppliers',
  'Catering Companies', 'Hospitality Supplies Companies', 'Bakery Equipment Suppliers',
  'Food Processing Equipment Suppliers', 'Event Management Companies',
  'Exhibition Stand Contractors', 'AV & Media Equipment Suppliers',
  'Marketing & Advertising Agencies', 'IT Companies / IT Services Providers',
  'Data Centre Suppliers & Service Providers', 'Telecommunication Companies',
  'Accounting & Audit Firms', 'Tax Consultants', 'Corporate Service Providers / PRO Services',
  'Law Firms', 'Management Consulting Firms', 'HR & Recruitment Agencies', 'Staffing Companies',
  'Facilities Management Companies', 'Cleaning Companies', 'Security Companies',
  'Business Centres & Coworking Spaces', 'Logistics & Freight Forwarding Companies',
  'Warehousing & 3PL Companies', 'Oil & Gas Equipment Suppliers', 'Industrial Equipment Suppliers',
  'Industrial Automation Suppliers', 'Bearings & Power Transmission Suppliers',
  'Fasteners & Fixings Suppliers', 'Tools & Abrasives Suppliers',
  'Air Compressor & Pneumatic Suppliers', 'Chemical Suppliers', 'Laboratory Equipment Suppliers',
  'Cleanroom Suppliers & Contractors', 'Medical Equipment Suppliers', 'Pharmaceutical Suppliers',
  'Education Equipment Suppliers', 'Aviation & Ground Support Suppliers',
  'Marine Equipment & Marine Safety Suppliers', 'Offshore & Marine Construction Companies',
  'Renewable Energy Companies (Solar, EV, Battery)', 'Real Estate Agencies',
  'Property Management Companies', 'Textile & Uniform Suppliers',
  'Beauty & Spa Equipment Suppliers', 'Gym & Sports Equipment Suppliers',
  'Jewelry Suppliers / Gold & Diamond Traders', 'Luxury & Concierge Service Providers',
  'Travel Agencies', 'Domestic Services Companies (Maids, Care)',
  'Pet Care & Veterinary Services', 'Translation & Interpretation Companies',
  'Tender & Bid Management Consultants', 'Testing, Inspection & Certification Companies',
  'Modular & Prefab Building Suppliers',
  'Gas Systems Suppliers (LPG, Medical Gas, Industrial Gas)',
  'Utility Contractors (DEWA / SEWA / FEWA approved)', 'Wastewater & Drainage Contractors',
];

// Cosmetic punctuation is not a taxonomy defect. "Fit-Out" vs "Fit Out" and "FF&E" vs "FF and E"
// name the same category, and failing on an ampersand would report a build order for a row that is
// already correct. Letters and digits only, case-folded — a comparison that still distinguishes
// "Roofing Suppliers" from "Flooring Suppliers", which is the distinction that matters.
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');

export default async function (H) {
  const { req, many, B, Q, MAPPED_N } = H;

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §1 — DOMAIN TAXONOMY (66)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  const domRows = await many(`select num, name from public.catalog_domains order by num`);
  const byNum = new Map(domRows.map(r => [Number(r.num), r.name]));
  const extraDomains = domRows.filter(r => Number(r.num) > DOMAINS.length).map(r => `${r.num}=${r.name}`);

  for (let i = 0; i < DOMAINS.length; i++) {
    const n = i + 1, want = DOMAINS[i], got = byNum.get(n);
    const ok = got != null && norm(got) === norm(want);
    await req('§1 domains', `dom-${String(n).padStart(2, '0')}`, want,
      B(ok),
      Q(`catalog_domains.num=${n} -> ${got == null ? 'NO ROW' : `"${got}"`}; spec says "${want}"` +
        (ok ? '' : ' — MISMATCH')));
  }

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §2 — REALISTIC SUPPLIER CATEGORIES (84)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // A catalogue row alone does NOT satisfy §2. The spec's subject is "the AI agent behind each
  // category", so a category with no agent is a category the spec's premise does not hold for. Both
  // legs print, so a MISSING says which one failed rather than leaving it to be guessed.
  const catRows = await many(`select c.num, c.name, c.slug,
      (select count(*) from public.category_agent_map m where m.catalog_slug=c.slug) as mapped,
      (select count(*) from public.agent_knowledge k where k.agent_key='cat:'||c.slug) as kn
    from public.catalog_supplier_categories c order by c.num`);
  const catByNum = new Map(catRows.map(r => [Number(r.num), r]));
  const extraCats = catRows.filter(r => Number(r.num) > CATEGORIES.length).map(r => `${r.num}=${r.name}`);

  for (let i = 0; i < CATEGORIES.length; i++) {
    const n = i + 1, want = CATEGORIES[i], row = catByNum.get(n);
    const named = row != null && norm(row.name) === norm(want);
    const hasAgent = row != null && Number(row.mapped) > 0 && Number(row.kn) > 0;
    await req('§2 categories', `cat-${String(n).padStart(2, '0')}`, want,
      B(named && hasAgent),
      Q(`catalog_supplier_categories.num=${n} -> ${row == null ? 'NO ROW' : `"${row.name}" [${row.slug}]`}; ` +
        `spec says "${want}"${named ? '' : ' — NAME MISMATCH'}; ` +
        `agent: category_agent_map ${row ? row.mapped : 0} row(s), ` +
        `agent_knowledge 'cat:' ${row ? row.kn : 0} row(s)${hasAgent ? '' : ' — NO AGENT'}`));
  }

  // Printed once, at the end of the section, so the superset stays visible without consuming a
  // requirement the spec did not write.
  console.log(`         (beyond the spec: ${domRows.length - DOMAINS.length} extra domain(s) ` +
    `[${extraDomains.join(' ') || 'none'}], ${catRows.length - CATEGORIES.length} extra ` +
    `categor(ies) [${extraCats.join(' ') || 'none'}] — additions, not omissions; ` +
    `the 84 scored above are the spec's own list, and ${MAPPED_N} is the mapped population)`);
}
