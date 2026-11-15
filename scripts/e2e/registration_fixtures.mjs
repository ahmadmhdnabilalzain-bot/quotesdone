// scripts/e2e/registration_fixtures.mjs — the FICTIONAL trade licences and company profiles the supplier registration
// certification registers with, and what each one must be read as. Assigned: customer_support (founder ruling 1620,
// 10 Nov 2026: he invites his own network only once IT confirms the registration "reads their trade licence, understands
// what they do").
//
//   node scripts/e2e/registration_fixtures.mjs --write     regenerate scripts/e2e/fixtures/registration/ (files + expected.json)
//
// EVERY DOCUMENT IS INVENTED. Every company name carries "ZZ DEMO"; every licence number carries "ZZ", a prefix no UAE
// registry issues, so no fixture can be the number of a real firm; every page prints "QuotesDone synthetic fixture". The
// authorities, label vocabularies and date styles are the ones the intake accuracy corpus models (document_intake_corpus.mjs
// AUTHORITIES, printDate) - modelled on the SHAPE of each issuer's licence, never copied from a real one.
//
// WHAT IS COVERED (founder's list, 10 Nov 2026)
//   licences  Dubai DET English+Arabic, Abu Dhabi ADDED, JAFZA, Ajman (a phone photo of a printed licence: sheared, turned,
//             shadowed, soft), RAKEZ (an image-only scan), Sharjah SEDD, DMCC, RAK DED (EXPIRED on 31 Aug 2026).
//   profiles  MEP contractor, joinery, building materials trader (DOCX), HVAC, packaging manufacturer (an image-only
//             brochure: only a model can read it), staff transport / bus rental (English and Arabic).
// Each profile prints the company name of the licence it is registered with: a profile naming another company proposes no
// trade by design (stage-2 run f0b2de8f), so a mismatched pair could not prove the reading.
//
// THE EXPECTED READING (expected.json) is the bar the certification judges against: per licence the five fields the
// founder named (number, legal name, issuing authority, expiry, activities) and whether it is expired; per profile the
// trades that are RIGHT, the neighbouring trades that are ACCEPTABLE, and that anything else is an absurd proposal.
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { AUTHORITIES, printDate, picture, rawPdf, docx } from './document_intake_corpus.mjs';
import { PROFILES as HARD } from './services_hard_profiles/profiles_def.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const FIXTURE_DIR = join(HERE, 'fixtures', 'registration');
export const SYNTHETIC = 'QuotesDone synthetic fixture - not a real company or licence';

// ── the licences ─────────────────────────────────────────────────────────────────────────────────────────────────────────
// format: pdf (a clean, system-printed PDF with a text layer), photo (a phone photo of the printed page, JPEG), scan
// (an image-only PDF, no text layer). code_readable: whether CODE alone can read it (a text layer) - the rest need the
// paid vision reader, and are certified only in the paid round.
export const LICENCES = [
  { id: 'L1', file: 'L1_dubai_det_bilingual.pdf', key: 'dubai_det', format: 'pdf', bilingual: true, code_readable: true,
    licence_no: 'ZZ-1290417', legal_name: 'ZZ DEMO Saker Electromechanical Contracting LLC', legal_name_ar: 'زد زد ديمو الصقر للمقاولات الكهروميكانيكية ذ.م.م',
    trade_name: 'ZZ DEMO Saker Electromechanical', issue: '2025-02-16', expiry: '2027-02-15',
    activities: ['Electromechanical Equipment Installation and Maintenance', 'Plumbing and Sanitary Installation', 'Air Conditioning and Ventilation Systems Installation'] },
  { id: 'L2', file: 'L2_abu_dhabi_added.pdf', key: 'abu_dhabi_added', format: 'pdf', code_readable: true,
    licence_no: 'CN-ZZ482137', legal_name: 'ZZ DEMO Ghaf Joinery and Carpentry LLC', trade_name: 'ZZ DEMO Ghaf Joinery', issue: '2025-05-04', expiry: '2027-05-03',
    activities: ['Carpentry and Joinery Works', 'Wooden Doors and Windows Manufacturing', 'Wooden Furniture Fixing'] },
  { id: 'L3', file: 'L3_jafza.pdf', key: 'jafza', format: 'pdf', code_readable: true,
    licence_no: 'ZZ-719044', legal_name: 'ZZ DEMO Dune Building Materials Trading FZE', trade_name: 'ZZ DEMO Dune Building Materials', issue: '2025-09-21', expiry: '2027-09-20',
    activities: ['Building Materials Trading', 'Tiles and Ceramics Trading', 'Sanitary Ware Trading'] },
  { id: 'L4', file: 'L4_ajman_phone_photo.jpg', key: 'ajman_ded', format: 'photo', code_readable: false,
    licence_no: 'ZZ-307721', legal_name: 'ZZ DEMO Pearl Air Conditioning Contracting Est', trade_name: 'ZZ DEMO Pearl Air Conditioning', issue: '2025-03-11', expiry: '2027-03-10',
    activities: ['Air Conditioning and Ventilation Systems Installation', 'Air Conditioning Equipment Repairing and Maintenance'] },
  { id: 'L5', file: 'L5_rakez_scan.pdf', key: 'rakez', format: 'scan', code_readable: false,
    licence_no: 'ZZ-5047219', legal_name: 'ZZ DEMO Najm Packaging Industries FZ-LLC', trade_name: 'ZZ DEMO Najm Packaging', issue: '2025-06-30', expiry: '2027-06-29',
    activities: ['Manufacture of Corrugated Cartons and Boxes', 'Manufacture of Plastic Packaging Products'] },
  { id: 'L6', file: 'L6_sharjah_sedd.pdf', key: 'sharjah_sedd', format: 'pdf', code_readable: true,
    licence_no: 'ZZ-748113', legal_name: 'ZZ DEMO Corniche Passenger Transport LLC', trade_name: 'ZZ DEMO Corniche Transport', issue: '2025-01-08', expiry: '2027-01-07',
    activities: ['Passenger Transport by Rented Buses', 'Staff Transport Services', 'Bus Rental with Driver'] },
  { id: 'L7', file: 'L7_dmcc.pdf', key: 'dmcc', format: 'pdf', code_readable: true,
    licence_no: 'DMCC-ZZ8401', legal_name: 'ZZ DEMO Marina Steel Trading DMCC', trade_name: 'ZZ DEMO Marina Steel', issue: '2025-04-14', expiry: '2027-04-13',
    activities: ['Iron and Steel Trading', 'Non-Ferrous Metals Trading'] },
  { id: 'L8', file: 'L8_rak_ded_expired.pdf', key: 'rak_ded', format: 'pdf', code_readable: true, expired: true,
    licence_no: 'ZZ-261150', legal_name: 'ZZ DEMO Wadi Painting Contracting LLC', trade_name: 'ZZ DEMO Wadi Painting', issue: '2024-09-01', expiry: '2026-08-31',
    activities: ['Painting Contracting', 'Building Cleaning Services'] },
  // THE FOUNDER'S OWN EXAMPLES (it_engineer, 12 Nov 2026; review of PR #1969, finding 4): the decoration company with pools through a
  // partner, and the manpower company that "supplies staff and similar services". Their profiles are the hard-profile set's H01 and H02
  // (services_hard_profiles/profiles_def.mjs); the licences are new numbers, so a hard-profile run and a certification never collide.
  { id: 'L9', file: 'L9_dubai_det_decoration.pdf', key: 'dubai_det', format: 'pdf', code_readable: true,
    licence_no: 'ZZ-880947', legal_name: 'ZZ DEMO Rimal Decoration LLC', trade_name: 'ZZ DEMO Rimal Decoration', issue: '2025-06-01', expiry: '2027-05-31',
    activities: ['Interior Decoration Works', 'Building Maintenance'] },
  { id: 'L10', file: 'L10_dubai_det_manpower.pdf', key: 'dubai_det', format: 'pdf', code_readable: true,
    licence_no: 'ZZ-431977', legal_name: 'ZZ DEMO Al Wafa Manpower Supply Services LLC', trade_name: 'ZZ DEMO Al Wafa Manpower', issue: '2025-06-01', expiry: '2027-05-31',
    activities: ['On Demand Labors Supply', 'Human Resources Consultancy'] },
];

// NOT A LICENCE IN THE LICENCE SLOT (12 Nov 2026, sales_engineer; founder ruling 1668: "on purpose, I attached the company profile
// instead of the trade license"). Kept apart from LICENCES (which are generated and judged as licences): L11 is P1's company profile file,
// attached as the licence. The model must name it a company profile, and nothing of it may be read as a licence.
export const NOT_LICENCES = [
  { id: 'L11', file: 'P1_mep_contractor.pdf', key: 'dubai_det', format: 'pdf', code_readable: true, not_a_licence: 'company_profile',
    licence_no: null, legal_name: null, trade_name: null, issue: null, expiry: null, activities: [] },
  // L12 (13 Nov 2026, founder ruling 1681): a 12-page ZZ DEMO company profile in the licence slot. More pages than any licence
  // (supabase/functions/_shared/licence_pages.ts LICENCE_MAX_PAGES = 8): answered by its page count, no model asked, so a FREE run judges it.
  { id: 'L12', file: 'N1_long_profile_12_pages.pdf', key: 'dubai_det', format: 'long_pdf', pages: 12, code_readable: true, not_a_licence: 'long_file',
    licence_no: null, legal_name: null, trade_name: null, issue: null, expiry: null, activities: [] },
];
/** The 12-page profile (L12): plain text pages, no Chromium needed. */
export async function longProfilePdf(pages = 12) {
  const { demoPdfPages } = await import('../lib/demo_pdf.mjs');
  return demoPdfPages(Array.from({ length: pages }, (_, i) => [[`ZZ DEMO Saker Electromechanical Contracting LLC - Company Profile - page ${i + 1} of ${pages}`, 12],
    [i === 0 ? 'About us: a UAE MEP contractor serving Dubai and Sharjah.' : `Project ${i}: ZZ DEMO Tower block ${i}, HVAC, plumbing and electrical works.`, 10],
    ['(QuotesDone synthetic fixture - not a real company)', 8]]));
}

// ── the company profiles ─────────────────────────────────────────────────────────────────────────────────────────────────
// licence: the licence it is registered with (the profile prints that licence's company name). trade: the sign-up trade the
// supplier picks. expect: the trades whose proposal is RIGHT (at least one must be proposed). accept: neighbours that are not
// wrong. Any other proposed trade is ABSURD. role: the role the supplier ticks on the Services tab.
export const PROFILES = [
  // services_must: keys the profile plainly states (each must be shown on screen 1 or as a chip); services_never: keys of one of its
  // trades it plainly does not do (never shown as a certain row). Review of PR #1969, finding 4 (a wrong service in a right trade).
  { id: 'P1', file: 'P1_mep_contractor.pdf', licence: 'L1', format: 'pdf', lang: 'en', trade: 'mep_general', role: /^Contractor$/i, code_readable: true,
    services_must: ['electrical.db_panels', 'plumbing.drainage', 'hvac.vrf_chiller', 'mep_general.mep_maintenance'], services_never: ['electrical.lighting_poles', 'electrical.earthing_lightning'],
    expect: ['mep_general', 'electrical', 'plumbing', 'hvac'], accept: ['fire_fighting', 'general_contracting', 'security_systems', 'lighting_fixtures', 'home_automation'],
    title: 'MEP contracting', services: ['Electrical installation: LV distribution boards, cabling, lighting and small power', 'Plumbing and drainage: water supply, sanitary installation, booster pumps', 'HVAC: ducted split, VRF and chilled-water fan coil installation, ductwork', 'Annual maintenance contracts for MEP systems in villas and offices'],
    projects: ['MEP package, G+4 residential building, Al Barsha, Dubai (2025)', 'HVAC and plumbing for a 22-villa community, Dubai South (2024)', 'Electrical fit-out of a 1,800 m2 office floor, Business Bay (2024)'] },
  { id: 'P2', file: 'P2_joinery.pdf', licence: 'L2', format: 'pdf', lang: 'en', trade: 'joinery', role: /^Contractor$|Manufacturer/i, code_readable: true,
    services_must: ['joinery.kitchens', 'joinery.wardrobes', 'joinery.wood_panelling', 'doors.wooden_doors'], services_never: ['doors.automatic_doors', 'doors.shutters'],
    // furniture_repair is ACCEPTABLE, not absurd (15 Nov 2026, customer_support; paid certification run 2 J2 judged it absurd). The
    // profile's own line, which the reading quoted for furniture_repair.furniture_polishing ("Furniture polishing and lacquering"):
    //   "Site installation, repairs and polishing of wooden works"
    // with "built-in furniture for offices" above it, and its licence L2's activity "Wooden Furniture Fixing". The catalogue's joinery
    // trade has no polishing service, so polishing wooden works is that key's work; the neighbouring furniture trades were already
    // acceptable here on less ("built-in furniture for offices" -> office_furniture). Its other services (office chair repair, hotel
    // FF&E refurbishment) are not stated, and the supplier ticks only what he does.
    expect: ['joinery', 'doors'], accept: ['interior_fitout', 'home_furniture', 'office_furniture', 'hotel_furniture', 'flooring', 'furniture_repair'],
    title: 'joinery and carpentry', services: ['Custom joinery: kitchen cabinets, wardrobes and vanity units', 'Solid wood and veneered doors, frames and architraves', 'Wall panelling, reception counters and built-in furniture for offices', 'Site installation, repairs and polishing of wooden works'],
    projects: ['Kitchens and wardrobes for 40 apartments, Al Reem Island (2025)', 'Fire-rated timber doors for a school, Khalifa City (2024)', 'Reception desk and wall panelling, ADGM office (2024)'] },
  { id: 'P3', file: 'P3_building_materials_trader.docx', licence: 'L3', format: 'docx', lang: 'en', trade: 'building_materials', role: /Supplier|Trader|Distributor/i, code_readable: true,
    expect: ['building_materials'], accept: ['flooring', 'marble_stone', 'plumbing', 'steel', 'masonry_blockwork', 'thermal_insulation', 'waterproofing', 'plastics_pipes', 'wallpaper', 'gypsum'],
    title: 'building materials trading', services: ['Supply of cement, blocks, sand and aggregates to contractors', 'Porcelain and ceramic floor and wall tiles', 'Sanitary ware, taps and bathroom accessories', 'Delivery to site across the UAE from our Jebel Ali warehouse'],
    projects: ['Tiles and sanitary ware for 120 apartments, JVC (2025)', 'Block and cement supply for a warehouse, Dubai Industrial City (2024)'] },
  { id: 'P4', file: 'P4_hvac.pdf', licence: 'L4', format: 'pdf', lang: 'en', trade: 'hvac', role: /^Contractor$|Installer/i, code_readable: true,
    expect: ['hvac'], accept: ['mep_general', 'refrigeration_cold_rooms', 'electrical', 'thermal_insulation'],
    title: 'air conditioning', services: ['Supply and installation of split, ducted and VRF air conditioning', 'Duct cleaning, gas charging and preventive maintenance', 'Fresh-air units and ventilation for kitchens and car parks', '24-hour AC breakdown repair for villas and shops'],
    projects: ['VRF system for a G+3 office building, Ajman (2025)', 'Ducted AC replacement for 15 villas, Sharjah (2024)'] },
  { id: 'P5', file: 'P5_packaging_brochure_image_only.pdf', licence: 'L5', format: 'image_pdf', lang: 'en', trade: 'packaging', role: /Manufacturer/i, code_readable: false,
    expect: ['packaging', 'corrugated_packaging', 'rigid_plastic_packaging', 'flexible_packaging'], accept: ['protective_packaging', 'paper_board', 'labels_sleeves', 'packaging_tapes_strapping', 'industrial_crating', 'paper_bags', 'luxury_rigid_boxes'],
    title: 'packaging manufacturing', services: ['Corrugated cartons and shipping boxes, 3-ply and 5-ply, custom printed', 'Plastic food containers, PET jars and HDPE bottles', 'Die-cut retail boxes and display trays', 'In-house design, printing and same-week delivery to Dubai and the Northern Emirates'],
    projects: ['Printed export cartons for a dates producer, Al Ain (2025)', 'PET containers for a catering group, Dubai (2024)'] },
  { id: 'P6', file: 'P6_bus_rental_bilingual.pdf', licence: 'L6', format: 'pdf', lang: 'bi', trade: 'staff_transport', role: /Service provider|Supplier|Contractor/i, code_readable: true,
    expect: ['staff_transport'], accept: ['vehicle_leasing', 'logistics_moving', 'fleet_maintenance'],
    title: 'passenger transport', services: ['Staff transport: daily pick-up and drop-off for companies and labour camps', 'Bus and coach rental with driver, 14 to 65 seats', 'School transport with trained conductors', 'Event and airport transfers'],
    services_ar: ['نقل الموظفين يومياً للشركات وسكن العمال', 'تأجير الحافلات مع السائق من 14 إلى 65 مقعداً', 'النقل المدرسي مع مشرفين مدربين', 'نقل الفعاليات والمطار'],
    projects: ['Daily transport of 600 staff for a hotel group, Sharjah and Dubai (2025)', 'Shuttle buses for an exhibition, Expo City Dubai (2024)'] },
  // THE FOUNDER'S EXAMPLES. `hard`: the profile document is the hard-profile set's (profiles_def.mjs), printed as that set prints it.
  // tap_services: the exact keys the walk taps (the answer key's must + ok services), not every service of the trade; partner_services:
  // answered "Partner"; phrases: his own words the walk ticks when the reading keeps them; expect_card: the card kind that must be
  // asked; watch_keys: the services the founder named, which that card must offer (judged by key against its options: a renamed
  // label cannot fail it; keys confirmed active on production 12 Nov 2026).
  { id: 'P7', file: 'P7_decoration_pools_partner.pdf', licence: 'L9', format: 'hard_pdf', hard: 'H01', lang: 'en', trade: 'interior_fitout', role: /^Contractor$/i, code_readable: true,
    expect: ['interior_fitout', 'landscaping', 'gypsum', 'painting', 'wallpaper', 'flooring'],
    accept: ['curtains_blinds', 'upholstery', 'joinery', 'swimming_pools', 'design_consultancy', 'aluminium', 'road_works', 'lighting_fixtures'],
    tap_services: ['interior_fitout.decoration', 'interior_fitout.interior_design', 'gypsum.false_ceiling', 'gypsum.decorative', 'painting.interior', 'painting.decorative',
      'wallpaper.supply_install', 'wallpaper.wall_panels', 'flooring.parquet_vinyl', 'landscaping.softscape', 'landscaping.hardscape', 'landscaping.irrigation', 'landscaping.maintenance'],
    partner_services: ['landscaping.pools', 'swimming_pools.pool_construction', 'swimming_pools.water_features', 'swimming_pools.pool_maintenance'],
    phrases: ['Garden design', 'Garden lighting', 'Jacuzzi', 'Pergolas & gazebos'], expect_card: 'partner',
    services_must: ['interior_fitout.decoration', 'gypsum.false_ceiling', 'landscaping.irrigation'], services_never: ['interior_fitout.healthcare', 'interior_fitout.hospitality'] },
  { id: 'P8', file: 'P8_manpower_staff_and_similar.pdf', licence: 'L10', format: 'hard_pdf', hard: 'H02', lang: 'en', trade: 'labour_supply', role: /Service provider|Supplier|Contractor/i, code_readable: true,
    expect: ['labour_supply', 'recruitment_executive_search'], accept: ['hr_outsourcing'],
    tap_services: ['labour_supply.general', 'labour_supply.project_manpower', 'labour_supply.hourly', 'recruitment_executive_search.permanent_recruitment', 'recruitment_executive_search.overseas_recruitment'],
    // his own words a real owner of this profile certainly ticks: it says "We supply staff to our clients on a temporary or permanent
    // basis" and calls itself "a UAE recruitment and manpower company" (the paid check of J10 showed exactly these three rows)
    phrases: ['Recruitment services', 'Temporary staff supply', 'Permanent staff supply'],
    expect_card: 'vague', watch_keys: ['labour_supply.general', 'labour_supply.professional_staff', 'labour_supply.freelancers'] },
];

const byId = (id) => LICENCES.find((l) => l.id === id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
// Bilingual labels, as a Dubai licence prints them beside the English.
const AR_LABEL = { no: 'رقم الرخصة', name: 'الاسم القانوني', trade: 'الاسم التجاري', form: 'الشكل القانوني', emirate: 'الإمارة', auth: 'جهة الإصدار', issue: 'تاريخ الإصدار', expiry: 'تاريخ الانتهاء', acts: 'الأنشطة' };

/** The licence as the issuer's system prints it: an A4 HTML page in that issuer's layout, labels and date style. */
export function licenceHtml(L) {
  const A = AUTHORITIES[L.key];
  const rows = [['no', L.licence_no], ['name', L.legal_name], ['trade', L.trade_name], ['form', A.form],
    ...(A.printsEmirate ? [['emirate', A.emirate]] : []), ['auth', A.authority],
    ['issue', printDate(L.issue, A.date)], ['expiry', printDate(L.expiry, A.date)], ['acts', L.activities.join(', ')]];
  const label = (k) => A.L[k] || ({ emirate: 'Emirate' }[k]);
  const body = A.layout === 'colon' && !L.bilingual
    ? rows.map(([k, v]) => `<p class="c"><b>${esc(label(k))}:</b> ${esc(v)}</p>`).join('')
    : `<table>${rows.map(([k, v]) => `<tr><th>${esc(label(k))}</th><td>${esc(v)}${k === 'name' && L.legal_name_ar ? `<div class="ar" dir="rtl">${esc(L.legal_name_ar)}</div>` : ''}</td>${L.bilingual ? `<th class="ar" dir="rtl">${AR_LABEL[k]}</th>` : ''}</tr>`).join('')}</table>`;
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    @page { size: A4; margin: 0 } body { margin: 0; font-family: 'DejaVu Sans', Arial, sans-serif; color: #15202b; background: #fdfdfb }
    .page { box-sizing: border-box; width: 210mm; min-height: 297mm; padding: 16mm 16mm; border: 3px double #2f4b6e; }
    h1, h2, h3 { text-align: center; margin: 2px 0; color: #1d3557 } h1 { font-size: 15pt } h2 { font-size: 12pt } h3 { font-size: 17pt; margin-top: 8px; letter-spacing: 1px }
    .ar { font-size: 10pt } h3.ar { font-size: 15pt } table { width: 100%; border-collapse: collapse; margin-top: 14px; font-size: 10pt }
    th, td { border: 1px solid #a9b8c9; padding: 7px 8px; text-align: left; vertical-align: top } th { background: #eef3f8; width: 30% } th.ar { text-align: right; width: 22% }
    p.c { font-size: 11pt; margin: 9px 0 } .seal { margin-top: 18px; text-align: right; color: #6a7c90; font-size: 9pt }
    .foot { margin-top: 26px; font-size: 7.5pt; color: #8795a6; text-align: center }
  </style></head><body><div class="page">
    ${A.title.map((t, i) => (i < A.title.length - 1 ? `<h${i + 1}>${esc(t)}</h${i + 1}>` : `<h3>${esc(t)}</h3>`)).join('')}
    ${L.bilingual ? '<h3 class="ar" dir="rtl">رخصة تجارية</h3>' : ''}
    ${body}
    <div class="seal">Electronically issued document - verify on the issuer's portal</div>
    <div class="foot">(${SYNTHETIC})</div>
  </div></body></html>`;
}

/** A company profile: two A4 pages, cover facts, services, projects, and (bilingual) the services again in Arabic. A `hard` profile
 *  is the hard-profile set's own body under its company's band, as services_hard_profiles/make_profiles.mjs prints it. */
export function profileHtml(P) {
  if (P.hard) {
    const H = HARD.find((h) => h.id === P.hard), L = byId(P.licence);
    return `<!doctype html><html><head><meta charset="utf-8"><style>@page { size: A4; margin: 14mm } body { font-family: 'DejaVu Sans', Arial, sans-serif; font-size: 10.5pt; color: #222 }
      h1 { color: #0b4f6c; margin: 0 0 4px } h2 { color: #0b4f6c; border-bottom: 2px solid #0b4f6c; padding-bottom: 3px; margin-top: 18px } li { margin: 4px 0 } .brk { page-break-before: always }
      .band { background: #0b4f6c; color: #fff; padding: 18px; border-radius: 6px; margin-bottom: 10px } .band h1 { color: #fff }</style></head><body>
      <div class="band"><h1>${esc(L.legal_name)}</h1><div>Company profile 2026 - ${esc(H.tagline)}</div></div>
      ${H.body}
      <p style="color:#888;font-size:8pt;margin-top:30px">(${SYNTHETIC})</p></body></html>`;
  }
  const L = byId(P.licence);
  const ar = P.lang === 'bi';
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    @page { size: A4; margin: 14mm } body { font-family: 'DejaVu Sans', Arial, sans-serif; font-size: 10.5pt; color: #222 }
    h1 { color: #0b4f6c; margin: 0 0 4px } h2 { color: #0b4f6c; border-bottom: 2px solid #0b4f6c; padding-bottom: 3px; margin-top: 18px }
    li { margin: 4px 0 } .ar { direction: rtl; text-align: right } .k { color: #555 } .brk { page-break-before: always }
    .band { background: #0b4f6c; color: #fff; padding: 18px; border-radius: 6px; margin-bottom: 10px } .band h1 { color: #fff }
  </style></head><body>
    <div class="band"><h1>${esc(L.legal_name)}</h1><div>Company profile 2026 - ${esc(P.title)} - United Arab Emirates</div>${ar ? `<div class="ar">${esc(L.legal_name_ar || 'زد زد ديمو الكورنيش لنقل الركاب ذ.م.م')} - الملف التعريفي</div>` : ''}</div>
    <h2>About us</h2><p>${esc(L.legal_name)} is a UAE company in ${esc(P.title)}, licensed by the ${esc(AUTHORITIES[L.key].authority)}. We serve contractors, developers, facility managers and businesses across the Emirates with our own team and equipment.</p>
    <h2>What we do</h2><ul>${P.services.map((s) => `<li>${esc(s)}</li>`).join('')}</ul>
    ${ar ? `<h2 class="ar">خدماتنا</h2><ul class="ar">${P.services_ar.map((s) => `<li>${esc(s)}</li>`).join('')}</ul>` : ''}
    <div class="brk"></div>
    <h2>Selected projects</h2><ul>${P.projects.map((s) => `<li>${esc(s)}</li>`).join('')}</ul>
    <h2>Why work with us</h2><ul><li>Licensed in the UAE: licence ${esc(L.licence_no)}</li><li>Dedicated project manager for every order</li><li>Health and safety induction for every crew</li></ul>
    <h2>Contact</h2><p class="k">Contact details are shared through QuotesDone after a customer reveals the quotation.</p>
    <p style="color:#888;font-size:8pt;margin-top:30px">(${SYNTHETIC})</p>
  </body></html>`;
}

const docxLines = (P) => { const L = byId(P.licence); return [`${L.legal_name} - Company profile 2026`, 'About us', `${L.legal_name} is a UAE company in ${P.title}, licensed by the ${AUTHORITIES[L.key].authority}.`, 'What we do', ...P.services.map((s) => `- ${s}`), 'Selected projects', ...P.projects.map((s) => `- ${s}`), `(${SYNTHETIC})`]; };

async function htmlToPdf(browser, html) { const p = await browser.newPage(); await p.setContent(html, { waitUntil: 'load' }); const b = await p.pdf({ format: 'A4', printBackground: true, preferCSSPageSize: true }); await p.close(); return b; }
async function htmlToPng(browser, html, width = 1240) {
  const p = await browser.newPage({ viewport: { width: 794, height: 1123 }, deviceScaleFactor: width / 794 });
  await p.setContent(html, { waitUntil: 'load' }); const b = await p.screenshot({ fullPage: true, type: 'png' }); await p.close(); return b;
}
/** An office scanner: greyscale, a little noise and a 1-degree turn, one JPEG per page, no text layer. */
async function scannedPdf(pngs) {
  const pages = [];
  for (const png of pngs) {
    const turned = await sharp(png).rotate(1.1, { background: '#ffffff' }).greyscale().modulate({ brightness: 0.97 }).blur(0.4).resize({ width: 1240 }).jpeg({ quality: 68 }).toBuffer();
    const m = await sharp(turned).metadata(); pages.push({ jpeg: turned, w: m.width, h: m.height });
  }
  return rawPdf(pages);
}
/** A designed brochure exported as pictures: colour, one JPEG per page, no text layer (only a model can read it). */
async function imageOnlyPdf(pngs) {
  const pages = [];
  for (const png of pngs) { const j = await sharp(png).resize({ width: 1240 }).jpeg({ quality: 72 }).toBuffer(); const m = await sharp(j).metadata(); pages.push({ jpeg: j, w: m.width, h: m.height }); }
  return rawPdf(pages);
}
/** The page split into A4-proportioned slices (a full-page screenshot of a two-page profile is one tall image). */
async function slicesA4(png) {
  const m = await sharp(png).metadata(); const h = Math.round(m.width * 297 / 210); const out = [];
  for (let top = 0; top < m.height; top += h) out.push(await sharp(png).extract({ left: 0, top, width: m.width, height: Math.min(h, m.height - top) }).extend({ bottom: Math.max(0, h - (m.height - top)), background: '#ffffff' }).png().toBuffer());
  return out;
}

/** The judging bar the certification reads (expected.json). */
export function expectedReading() {
  return {
    note: 'Generated by scripts/e2e/registration_fixtures.mjs. Every company and licence here is fictional (ZZ DEMO, licence numbers prefixed ZZ).',
    licences: LICENCES.map((L) => ({ id: L.id, file: L.file, issuer: L.key, format: L.format, code_readable: L.code_readable, bilingual: !!L.bilingual,
      licence_no: L.licence_no, legal_name: L.legal_name, authority: AUTHORITIES[L.key].authority, emirate: AUTHORITIES[L.key].emirate,
      issue_date: L.issue, expiry_date: L.expiry, expired: !!L.expired, activities: L.activities })),
    profiles: PROFILES.map((P) => ({ id: P.id, file: P.file, licence: P.licence, format: P.format, lang: P.lang, code_readable: P.code_readable,
      company: byId(P.licence).legal_name, signup_trade: P.trade, expect_trades: P.expect, acceptable_trades: P.accept,
      ...(P.services_must ? { services_must: P.services_must, services_never: P.services_never } : {}),
      ...(P.tap_services ? { tap_services: P.tap_services, partner_services: P.partner_services || [], phrases: P.phrases || [], expect_card: P.expect_card } : {}) })),
  };
}

/** Write every fixture to `dir`. Needs Chromium (playwright) and sharp; deterministic in content, not byte-for-byte. */
export async function generate(dir = FIXTURE_DIR, only = null) {
  const want = (d) => !only || only.includes(d.id);
  mkdirSync(dir, { recursive: true });
  const { chromium } = await import('playwright');
  const browser = await chromium.launch();
  const written = [];
  try {
    for (const L of LICENCES.filter(want)) {
      const html = licenceHtml(L);
      let bytes;
      if (L.format === 'pdf') bytes = await htmlToPdf(browser, html);
      else if (L.format === 'scan') bytes = await scannedPdf([await htmlToPng(browser, html)]);
      else if (L.format === 'photo') bytes = (await picture(await htmlToPng(browser, html), 'phone')).bytes;   // the corpus's phone transform
      else throw new Error('licence format ' + L.format);
      writeFileSync(join(dir, L.file), bytes); written.push([L.file, bytes.length]);
    }
    for (const L of NOT_LICENCES.filter((x) => want(x) && x.format === 'long_pdf')) { const bytes = await longProfilePdf(L.pages); writeFileSync(join(dir, L.file), bytes); written.push([L.file, bytes.length]); }
    for (const P of PROFILES.filter(want)) {
      let bytes;
      if (P.format === 'pdf' || P.format === 'hard_pdf') bytes = await htmlToPdf(browser, profileHtml(P));
      else if (P.format === 'docx') bytes = docx(docxLines(P));
      else if (P.format === 'image_pdf') bytes = await imageOnlyPdf(await slicesA4(await htmlToPng(browser, profileHtml(P), 1100)));
      else throw new Error('profile format ' + P.format);
      writeFileSync(join(dir, P.file), bytes); written.push([P.file, bytes.length]);
    }
  } finally { await browser.close(); }
  writeFileSync(join(dir, 'expected.json'), JSON.stringify(expectedReading(), null, 1) + '\n');
  return written;
}

export const fixturePath = (file) => join(FIXTURE_DIR, file);
export const fixturesPresent = () => [...LICENCES, ...NOT_LICENCES, ...PROFILES].every((d) => existsSync(fixturePath(d.file)));

const MAIN = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (MAIN && process.argv.includes('--write')) {
  // --only L9,P7: write those files alone (the committed ones are generated, not byte-for-byte reproducible); expected.json always
  const oi = process.argv.indexOf('--only');
  const w = await generate(FIXTURE_DIR, oi > 0 ? process.argv[oi + 1].split(',') : null);
  for (const [f, n] of w) console.log(`${String(n).padStart(8)}  ${f}`);
  console.log(`wrote ${w.length} fixtures and expected.json to ${FIXTURE_DIR}`);
}
