// scripts/e2e/journey_proof/scenarios.mjs — THE FOUNDER'S JOURNEYS (ledger 1684, 13 Nov 2026), as data. Seat: customer_support.
//
//   A   an inquiry made only by CHAT in the customer portal
//   B   an inquiry made from an OLD QUOTATION the customer has from another supplier, with almost no typing
//   B2  the same, with a VOICE NOTE on top
//   C   a DRAWING + a BOQ + a VOICE NOTE + CHAT together: the pool in a villa ("Villa 15, Al Barsha 2, Dubai")
//
// Every journey's customer says where the job is the way a real one does: "Villa 15, Al Barsha 2, Dubai". The founder
// (ledger 1683): Dubai may reach a supplier; "Al Barsha" and "Villa 15" may not. So both are on every journey's list of
// identifying details that went IN, beside his name, mobile and e-mail.
//
// The adversarial inputs are the anonymity auditors' files (scratchpad/anon, 13 Nov 2026), passed with --inputs <dir>:
//   B, B2  "A1 input - customer's existing quotation.pdf"    the old supplier's FULL identity: letterhead, TRN, licence,
//          mobile in Western and Arabic digits, a consultant, the site with villa, plot and Makani, PDF properties
//   C      "Pool drawings - Villa 15 Al Barsha 2.pdf"         a title block with consultant, contractor, client, villa,
//          plot, Makani, permit, a DWG path in the PDF properties
// Their identifying strings are listed here, value by value, so the dossier can look for each one in what the suppliers
// received. Everything is invented (ZZ DEMO, example.invalid, +971 50 000 0xxx); nothing names a real person.
//
// Each supplier who quotes sends his OWN quotation with his full identity on it (letterhead, address, landline, mobile,
// e-mail, TRN, bank IBAN, a salesperson, and his company in the PDF properties): the dossier looks for each in what the
// customer received before the reveal.
//
// Matching: the run makes, for each journey, demo suppliers that SHOULD be asked (the right trade, serving the job's
// emirate), suppliers of the right trade serving ANOTHER emirate only, and suppliers of unrelated trades in the same
// emirate. The live matcher chooses by itself; the dossier compares.
import { TRADES } from '../../lib/demo_factory.mjs';

// swimming_pools is a live taxonomy trade the demo factory's table does not carry (as staff_transport in evidence_pack);
// a demo supplier of it needs a capability profile, so the table is extended for this process only.
if (!TRADES.swimming_pools) TRADES.swimming_pools = { name: 'Swimming Pools', products: ['swimming pool construction', 'pool waterproofing', 'pool mosaic tiling', 'pool filtration', 'pool pumps', 'pool heat pump', 'salt chlorinator', 'pool maintenance'], brands: ['Pentair', 'Hayward', 'AstralPool'] };

/** Exact taxonomy service labels (supabase/functions/_shared/general_matching.vocab.fixtures.json), so services_rewrite names them. */
export const SERVICE_WORDS = {
  hvac: 'Supply & installation of AC units, Maintenance & annual contracts, Ducting & ventilation',
  plumbing: 'Sanitary fixtures installation, Water supply piping, Drainage & sewerage, Plumbing maintenance',
  flooring: 'Tiling, Marble & granite, Epoxy flooring',
  swimming_pools: 'Pool construction, Pumps, filters & pool equipment, Pool maintenance',
  painting: 'Interior painting, Exterior painting',
  aluminium: 'Aluminium windows & doors, Curtain wall, ACP cladding',
  landscaping: 'Softscape & planting, Irrigation systems, Artificial grass',
};

export const SITE = { emirate: 'Dubai', area: 'Al Barsha 2', areaName: 'Al Barsha', villa: 'Villa 15', said: 'Villa 15, Al Barsha 2, Dubai' };

/** What the customer gave us about himself: none of it may reach a supplier before the reveal. */
export function customerIdentity(cust) {
  return [
    { label: "the customer's name", value: cust.fullName || cust.name, kind: 'name' },
    { label: "the customer's e-mail", value: cust.email, kind: 'email' },
    { label: "the customer's mobile", value: cust.phone, kind: 'phone' },
    { label: 'the area of the job', value: SITE.areaName, kind: 'text' },
    { label: 'the area with its number', value: SITE.area, kind: 'text' },
    { label: 'the villa number', value: SITE.villa, kind: 'text' },
  ];
}

/** The old supplier's quotation the customer attaches in B and B2 (auditor A's file): its identifying strings. */
export const OLD_QUOTATION = {
  file: "A1 input - customer's existing quotation.pdf",
  identity: [
    { label: "the old supplier's name", value: 'Falcon Trading', kind: 'name' },
    { label: "the old supplier's name in Arabic", value: 'فالكون', kind: 'name' },
    { label: "the old supplier's address", value: 'Al Quoz Industrial 3', kind: 'text' },
    { label: "the old supplier's landline", value: '+971 4 000 0412', kind: 'phone' },
    { label: "the old supplier's mobile", value: '050-000-0413', kind: 'phone' },
    { label: "the old supplier's website", value: 'zz-falcon.example.invalid', kind: 'email' },
    { label: "the old supplier's e-mail", value: 'sales@zz-falcon.example.invalid', kind: 'email' },
    { label: "the old supplier's TRN", value: '100000000000412', kind: 'number' },
    { label: "the old supplier's quotation number", value: 'FT/Q/2026/0412', kind: 'text' },
    { label: "the old supplier's own detail reference", value: 'FT-SD-04', kind: 'text' },
    { label: "the old supplier's salesperson", value: 'Ahmed Saeed Al Mansoori', kind: 'name' },
    { label: 'the client named on the old quotation', value: 'Omar Haddad', kind: 'name' },
    { label: "that client's mobile", value: '+971 55 000 0499', kind: 'phone' },
    { label: "that client's e-mail", value: 'omar.haddad@zz-mail.example.invalid', kind: 'email' },
    { label: 'the project name', value: 'Barsha Garden Villa', kind: 'text' },
    { label: 'the consultant', value: 'Cedar Engineering Consultants', kind: 'name' },
    { label: 'the plot number', value: '000-412', kind: 'text' },
    { label: 'the Makani number', value: '00000 00412', kind: 'text' },
    { label: 'the landmark', value: 'Mall of the Emirates', kind: 'text' },
  ],
  // the old supplier's prices: the founder will be asked to rule whether these may reach the new suppliers
  prices: ['95.00', '8,170.00', '2,350.00', '9,400.00', '1,180.00', '4,720.00', '1,960.00', '5,880.00', '210.00', '1,260.00'],
};

/** The pool drawing the customer attaches in C (auditor B's file): its title block, word by word. */
export const POOL_DRAWING = {
  file: 'Pool drawings - Villa 15 Al Barsha 2.pdf',
  identity: [
    { label: 'the consultant on the drawing', value: 'Coral Pools Consultants', kind: 'name' },
    { label: "the consultant's landline", value: '+971 4 555 0199', kind: 'phone' },
    { label: "the consultant's fax", value: '+971 4 555 0198', kind: 'phone' },
    { label: "the consultant's e-mail", value: 'info@coralpools.example.invalid', kind: 'email' },
    { label: "the consultant's address", value: 'Al Quoz 3', kind: 'text' },
    { label: "the consultant's licence", value: '778899', kind: 'number' },
    { label: 'the main contractor on the drawing', value: 'Blue Wave Contracting', kind: 'name' },
    { label: "the contractor's phone", value: '04 555 0277', kind: 'phone' },
    { label: 'the client on the drawing', value: 'ZZ Demo Owner', kind: 'name' },
    { label: 'the plot number', value: '373-1234', kind: 'text' },
    { label: 'the Makani number', value: '12345 67890', kind: 'number' },
    { label: 'the building permit', value: '2026/BP/55821', kind: 'text' },
    { label: 'the drawing number (carries area and villa)', value: 'CPC-AB2-V15-P-101', kind: 'text' },
    { label: 'the CAD file path (PDF properties)', value: 'ZZDemoOwner_Villa15_AlBarsha2', kind: 'text' },
  ],
};

// ── the supplier's own quotation, with his full identity on it ─────────────────────────────────────────────────────
/** One supplier's identity as his quotation prints it, made from the run's own fixture (never a real company). */
export function supplierLetterhead(spec, sup, i) {
  const n = String(70 + i).padStart(2, '0');
  return {
    trading_name: spec.label,
    company: sup.company,
    address: `Warehouse ${12 + i}, ZZ Demo Industrial Park, ${spec.city || 'Al Quoz Industrial Area 4'}, Dubai, UAE`,
    landline: `+971 4 000 01${n}`,
    mobile: `050 000 01${n}`,
    email: `sales${i + 1}@zz-${spec.label.toLowerCase().replace(/[^a-z0-9]+/g, '')}.example.invalid`,
    trn: `1000000000${String(200 + i).padStart(3, '0')}03`,
    iban: `AE07 0000 0000 0000 0000 ${String(100 + i).padStart(3, '0')}`,
    salesperson: spec.salesperson || `ZZ Demo Salesperson ${spec.label.split(' ')[0]}`,
  };
}
export function supplierIdentity(lh) {
  return [
    { label: "the supplier's trading name", value: lh.trading_name, kind: 'name' },
    { label: "the supplier's registered name", value: lh.company, kind: 'name' },
    { label: "the supplier's address", value: lh.address.split(',')[0], kind: 'text' },
    { label: "the supplier's landline", value: lh.landline, kind: 'phone' },
    { label: "the supplier's mobile", value: lh.mobile, kind: 'phone' },
    { label: "the supplier's e-mail", value: lh.email, kind: 'email' },
    { label: "the supplier's TRN", value: lh.trn, kind: 'number' },
    { label: "the supplier's bank IBAN", value: lh.iban, kind: 'number' },
    { label: "the supplier's salesperson", value: lh.salesperson, kind: 'name' },
  ];
}
/** Puts the identity a real letterhead carries into the evidence pack's quotation HTML (bank, salesperson, PDF title). */
export function withFullIdentity(html, lh) {
  return html
    .replace('<head>', `<head><title>${lh.trading_name} - ${lh.company} - Quotation</title>`)
    .replace(/<h1>([^<]*)<\/h1>/, `<h1>${lh.trading_name}</h1><div style="font-size:10px">${lh.company}</div>`)
    .replace(/Office 000, ZZ Business Centre, [^<]*, UAE/, lh.address)
    .replace(/Tel \+971 4 000 0000 · sales@example\.invalid · TRN 100000000000003/, `Tel ${lh.landline} · Mob ${lh.mobile} · ${lh.email} · TRN ${lh.trn}`)
    .replace('Authorised signatory', `Authorised signatory<br>${lh.salesperson}, Sales<br>Bank: ZZ DEMO Bank, IBAN ${lh.iban}<br>Call ${lh.salesperson.split(' ').slice(-1)[0]} on ${lh.mobile}`);
}

// ── the four journeys ───────────────────────────────────────────────────────────────────────────────────────────────
const unrelated = (trades) => trades.map((trade) => ({ trade, emirates: ['Dubai'], should: 'unrelated' }));

export const SCENARIOS = {
  A: {
    key: 'A', folder: 'A_chat_only', short: 'an inquiry made only by chat', label: 'JA Villa AC',
    how_made: 'the customer opened "New request" in his portal and only typed: no file, no voice note',
    title: 'Replace four split AC units and service three ducted units, Villa 15, Al Barsha 2, Dubai',
    trade: 'hvac', trades: ['hvac'], estimate_usd: 0.5, cap_usd: 1.0,
    matching: { right: [{ trade: 'hvac', emirates: ['Dubai'], n: 5 }], wrong: [{ trade: 'hvac', emirates: ['Abu Dhabi'], n: 2 }], unrelated: unrelated(['painting', 'plumbing', 'aluminium']) },
    opener: `Hello. I need the air conditioning in my villa sorted out. It is ${SITE.said}. Four of the wall-mounted split units are old and no longer cool, I want them replaced with new ones, and the three ducted units serviced.`,
    facts: [
      [/payment/i, 'Payment terms: 50% advance and 50% on completion.'],
      [/capacity|btu|\btr\b|ton|kw|size of (the )?unit/i, 'Two bedrooms have 1.5 ton units and the majlis and living room have 2 ton units, so two of 1.5 TR and two of 2.0 TR. The three ducted units are 3 TR each.'],
      [/inverter|fixed.?speed/i, 'Inverter units, please.'],
      [/brand|make|manufactur|origin|tier|quality|efficien/i, 'Daikin, Mitsubishi Electric or Gree, inverter, R32 or R410A.'],
      [/remov|dispos|old unit|existing unit/i, 'Yes, remove the old split units and take them away.'],
      [/copper|pip|drain/i, 'Reuse the existing copper pipes if they are in good condition, otherwise allow up to 5 metres of new insulated pipe per unit.'],
      [/servic|clean|ducted|maint|gas/i, 'For the three ducted units: full cleaning of coils and filters, drain line cleaning and a gas pressure check, one visit.'],
      [/electric|power|isolator|supply/i, 'The power points and isolators are already there; you only connect to them.'],
      [/access|floor|roof|outdoor|ladder|where|location|emirate|address/i, 'Indoor units on the ground and first floor; the outdoor units are on the roof, reached by a fixed ladder.'],
      [/when|timeline|date|deadline|by when|start|complet/i, 'We need it done by 15 December 2026.'],
      [/warrant|guarantee/i, 'At least 2 years on the installation and 5 years on the compressors.'],
      [/budget|price|cost/i, 'Our budget is around AED 12,000 to 16,000.'],
      [/install|supply|scope/i, 'Supply and installation of the four new split units, plus the service of the three ducted units.'],
    ],
    confirm: 'Yes, that is correct. Please send it to suppliers.',
    defaultLines: [
      { description: 'Removal and disposal of existing wall split units', qty: 4, unit: 'nos' },
      { description: 'Wall split unit 1.5 TR, inverter, supply and install', qty: 2, unit: 'nos' },
      { description: 'Wall split unit 2.0 TR, inverter, supply and install', qty: 2, unit: 'nos' },
      { description: 'Insulated copper piping where the existing cannot be reused', qty: 20, unit: 'm' },
      { description: 'Service of ducted unit 3 TR: coils, filters, drain, gas check', qty: 3, unit: 'nos' },
      { description: 'Testing and commissioning', qty: 1, unit: 'lot' },
    ],
    quoting: [
      { label: 'Cool Breeze HVAC', factor: 1.00, brand: 'Daikin', origin: 'Thailand (Japanese brand)', lead: '10 days from LPO', warranty: '5 years on compressors, 2 years on the installation', payment: '50% advance, 50% on completion', omit: null, excl: 'Civil works, electrical works.' },
      { label: 'Arabian Air Systems', factor: 0.78, brand: 'Gree', origin: 'China', lead: '5 days from LPO', warranty: '1 year on the installation', payment: '50% advance, 50% on completion', omit: null, excl: 'Electrical works.' },
      { label: 'Polar Tech Contracting', factor: 1.14, vatInclusiveOnly: true, brand: 'Mitsubishi Electric', origin: 'Japan', lead: '14 days from LPO', warranty: '5 years on compressors, 2 years on the installation', payment: '30% advance, 70% on completion', omit: null, excl: 'Civil works.' },
    ],
    specFor: (d, s) => /remov|dispos/i.test(d) ? 'Disconnect, recover refrigerant, remove and dispose' : /servic|clean/i.test(d) ? 'Chemical coil cleaning, filters, drain flush, pressure check' : /test|commission/i.test(d) ? 'Pressure test, vacuum, performance readings' : /copper|pip/i.test(d) ? 'ASTM B280 copper, 19 mm insulation' : /split|unit|inverter/i.test(d) ? `${s.brand} wall split inverter, R32, made in ${String(s.origin).replace(/\s*\(.*\)$/, '')}` : 'As per the request',
    rate: (d) => /remov|dispos/i.test(d) ? 150 : /1\.5\s*tr/i.test(d) ? 2650 : /2\.0\s*tr|2\s*tr/i.test(d) ? 3100 : /copper|pip/i.test(d) ? 85 : /servic|clean/i.test(d) ? 450 : /test|commission/i.test(d) ? 600 : 300,
    brandRe: /split|unit|inverter/i,
    hold: { refrigerant: 'R32', standard: 'ESMA 5-star' },
    holdBy: [[/model/, (sp, d) => /split|unit/i.test(d) ? `${sp.brand} wall split inverter` : 'As per the request line'], [/unit_type|type/, 'Wall-mounted split, inverter'], [/inverter/, 'Inverter'], [/esma|star/, 'ESMA 5-star'], [/power|phase|voltage/, '220-240 V single phase']],
  },
  B: {
    key: 'B', folder: 'B_old_quotation', short: 'an inquiry made from an old quotation', label: 'JB Villa bathrooms',
    how_made: "the customer attached a quotation he already had from another supplier, and typed one line",
    title: 'Bathroom sanitary ware and wall tiling, from the customer\'s existing quotation, Villa 15, Al Barsha 2, Dubai',
    trade: 'plumbing', trades: ['plumbing', 'flooring'], estimate_usd: 0.7, cap_usd: 1.2,
    matching: { right: [{ trade: 'plumbing', emirates: ['Dubai'], n: 5 }, { trade: 'flooring', emirates: ['Dubai'], n: 3 }], wrong: [{ trade: 'plumbing', emirates: ['Sharjah'], n: 2 }], unrelated: unrelated(['hvac', 'painting', 'aluminium']) },
    opener: 'Hi, I already have this quotation for the bathrooms. Can you get me better prices for the same work?',
    attach: [{ kind: 'old_quotation', input: 'Attach a drawing, photo or quotation', action: 'analyze_drawing', from: OLD_QUOTATION }],
    facts: [
      [/payment/i, 'Payment: 30% advance, the rest on completion.'],
      [/when|timeline|date|deadline|by when|start|complet/i, 'Before the end of December 2026.'],
      [/warrant|guarantee/i, 'Two years on the installation.'],
      [/access|floor|where|location|emirate/i, 'Four bathrooms on the ground and first floor; normal access.'],
      [/remov|existing|demoli/i, 'The old tiles and fittings are removed by the contractor.'],
      [/brand|make|equivalent|origin/i, 'The same brands as in the quotation, or equivalent.'],
      [/budget|price|cost/i, 'Ideally less than the quotation I attached.'],
    ],
    confirm: 'Yes, that is correct. Please send it to suppliers.',
    defaultLines: [
      { description: 'Porcelain wall tiles 300x600 mm, supply and fix', qty: 86, unit: 'm2' },
      { description: 'Wall hung WC with concealed cistern', qty: 4, unit: 'set' },
      { description: 'Wash basin 600 mm with pedestal and mixer', qty: 4, unit: 'set' },
      { description: 'Thermostatic shower mixer with rain shower head', qty: 3, unit: 'nos' },
      { description: 'Floor drain 150x150 stainless steel', qty: 6, unit: 'nos' },
      { description: 'Waterproofing membrane to wet areas', qty: 40, unit: 'm2' },
    ],
    quoting: [
      { label: 'Gulf Sanitary Works', factor: 0.92, brand: 'Grohe', origin: 'Germany', lead: '3 weeks from LPO', warranty: '2 years on the installation, 5 years Grohe on fittings', payment: '30% advance, 70% on completion', omit: null, excl: 'Electrical works.' },
      { label: 'Marina Plumbing Contracting', factor: 0.85, brand: 'Duravit', origin: 'Germany', lead: '4 weeks from LPO', warranty: '1 year on the installation', payment: '50% advance, 50% on completion', omit: null, excl: 'Civil works.' },
      { label: 'Emirates Bath Solutions', factor: 1.02, vatInclusiveOnly: true, brand: 'Hansgrohe', origin: 'Germany', lead: '2 weeks from LPO', warranty: '2 years on the installation', payment: '40% advance, 60% on completion', omit: null, excl: 'None.' },
    ],
    specFor: (d, s) => /tile/i.test(d) ? 'RAK porcelain 300x600, gloss white, or equivalent' : /waterproof/i.test(d) ? 'Cementitious 2 coats, 150 mm upstand' : /drain/i.test(d) ? 'SS 304 anti-odour' : `${s.brand} or equivalent, chrome`,
    rate: (d) => /tile/i.test(d) ? 88 : /wc/i.test(d) ? 2200 : /basin/i.test(d) ? 1100 : /shower/i.test(d) ? 1850 : /drain/i.test(d) ? 190 : /waterproof/i.test(d) ? 45 : 300,
    brandRe: /wc|basin|mixer|shower/i, hold: {}, holdBy: [],
  },
};
SCENARIOS.B2 = {
  ...SCENARIOS.B, key: 'B2', folder: 'B2_old_quotation_and_voice', short: 'an old quotation with a voice note on top', label: 'JB2 Villa bathrooms',
  how_made: 'the customer attached a quotation he already had from another supplier and recorded a voice note, typing nothing',
  estimate_usd: 0.8, cap_usd: 1.4, opener: null,
  voice: [['en', `Hi, it is about the bathrooms in my villa, ${SITE.said}. Please use the quotation I attached, but I want Grohe or Hansgrohe for the mixers, and the floor tiles must be anti-slip. It must be finished before the end of December. Thank you.`]],
};
SCENARIOS.C = {
  key: 'C', folder: 'C_drawing_boq_voice_chat', short: 'a drawing, a BOQ, a voice note and chat together', label: 'JC Villa pool',
  how_made: 'the customer typed a first line, attached the pool drawings and a BOQ, recorded a voice note, and answered the questions',
  title: 'A private swimming pool, from the consultant\'s drawings and a BOQ, Villa 15, Al Barsha 2, Dubai',
  trade: 'swimming_pools', trades: ['swimming_pools'], estimate_usd: 1.2, cap_usd: 2.0,
  matching: { right: [{ trade: 'swimming_pools', emirates: ['Dubai'], n: 5 }], wrong: [{ trade: 'swimming_pools', emirates: ['Abu Dhabi'], n: 2 }], unrelated: unrelated(['painting', 'hvac', 'aluminium']) },
  opener: 'Hello, we want a private swimming pool built in our villa garden. The consultant gave us these drawings and a BOQ.',
  attach: [
    { kind: 'drawing', input: 'Attach a drawing, photo or quotation', action: 'analyze_drawing', from: POOL_DRAWING },
    { kind: 'boq', input: 'Attach a BOQ — Excel, CSV, PDF or a photo', action: 'analyze_document', make: 'pool_boq' },
  ],
  voice: [['en', `Hi, about the pool at our villa, ${SITE.said}. The drawings are from our consultant. We want the pool heated, with salt chlorination and LED lights, glass mosaic in blue. The garden has space for a small excavator through the side gate. We would like it finished by the end of March 2027.`]],
  facts: [
    [/payment/i, 'Payment by stages: 20% advance, then against progress, 10% at handover.'],
    [/dimension|size|length|width|depth|how big|area/i, 'The pool is 10 by 5 metres, 1.2 metres at the shallow end and 1.8 metres at the deep end, as on drawing P-101.'],
    [/heat/i, 'Yes, heated with a heat pump, as on the drawing.'],
    [/finish|tile|mosaic|coping/i, 'Glass mosaic 25 x 25 mm, blue mix, and travertine coping, as on the drawing.'],
    [/excavat|access|soil|site|crane|gate/i, 'A small excavator can reach the garden through the side gate, 3 metres wide. The soil is sand.'],
    [/permit|approval|municipality|authority|noc/i, 'The building permit is already issued; the contractor arranges the pool inspection.'],
    [/equipment|pump|filter|chlorinat|light/i, 'Equipment as in the schedule on the drawing: two pumps, a sand filter, a heat pump, a salt chlorinator and three LED lights.'],
    [/structure|concrete|shell|waterproof/i, 'Reinforced concrete shell with crystalline waterproofing and a PU membrane, as in the general notes.'],
    [/electric|power|db/i, 'A 32 A supply will be ready in the plant room; the pool contractor does the pool electrics from there.'],
    [/when|timeline|date|deadline|by when|start|complet/i, 'Finished by the end of March 2027.'],
    [/warrant|guarantee/i, 'Ten years on the structure and waterproofing, two years on the equipment.'],
    [/budget|price|cost/i, 'Our budget is around AED 180,000.'],
    [/maint|servic/i, 'One year of maintenance after handover would be good, priced separately.'],
  ],
  confirm: 'Yes, that is correct. Please send it to the suppliers.',
  boq: [
    [1, 'Excavation and disposal for the pool and balance tank', 95, 'm3'],
    [2, 'Reinforced concrete pool shell, C40, as per structural drawing', 38, 'm3'],
    [3, 'Waterproofing: crystalline 2 coats + PU membrane', 110, 'm2'],
    [4, 'Glass mosaic tiles 25x25 mm, blue mix, supply and fix', 105, 'm2'],
    [5, 'Travertine coping 600x300x30 mm, bullnose', 32, 'lm'],
    [6, 'Circulation pump 1.5 HP, duty/standby', 2, 'nos'],
    [7, 'Sand filter 760 mm', 1, 'nos'],
    [8, 'Heat pump 17 kW', 1, 'nos'],
    [9, 'Salt chlorinator 25 g/h', 1, 'nos'],
    [10, 'LED underwater light 35 W, IP68', 3, 'nos'],
    [11, 'uPVC PN16 pipework, skimmers, main drain, return inlets', 1, 'lot'],
    [12, 'Balance tank 3 m3 and overflow grating', 1, 'lot'],
    [13, 'Testing, commissioning and handover', 1, 'lot'],
  ],
  defaultLines: null,
  quoting: [
    { label: 'Aqua Pools Contracting', factor: 1.00, brand: 'Pentair', origin: 'USA', lead: '10 weeks from LPO', warranty: '10 years on the structure, 2 years on the equipment', payment: '20% advance, progress, 10% at handover', omit: null, excl: 'Landscaping around the pool.' },
    { label: 'Blue Lagoon Pools', factor: 0.86, brand: 'AstralPool', origin: 'Spain', lead: '12 weeks from LPO', warranty: '5 years on the structure, 1 year on the equipment', payment: '30% advance, progress', omit: null, excl: 'Electrical supply to the plant room, landscaping.' },
    { label: 'Desert Oasis Pool Works', factor: 1.18, vatInclusiveOnly: true, brand: 'Hayward', origin: 'USA', lead: '9 weeks from LPO', warranty: '10 years on the structure, 3 years on the equipment', payment: '20% advance, progress, 10% at handover', omit: null, excl: 'None.' },
  ],
  specFor: (d, s) => /pump|filter|heat|chlorinat|light/i.test(d) ? `${s.brand}, made in ${s.origin}` : /concrete/i.test(d) ? 'C40 with waterproof admixture' : /mosaic/i.test(d) ? 'Glass mosaic 25x25, blue mix' : /coping/i.test(d) ? 'Travertine 30 mm, bullnose' : 'As per the drawing and BOQ',
  rate: (d, u) => /excavat/i.test(d) ? 85 : /concrete/i.test(d) ? 1450 : /waterproof/i.test(d) ? 95 : /mosaic/i.test(d) ? 260 : /coping/i.test(d) ? 340 : /pump/i.test(d) ? 4200 : /filter/i.test(d) ? 3800 : /heat/i.test(d) ? 14500 : /chlorinat/i.test(d) ? 6200 : /light/i.test(d) ? 1600 : /pipe|skimmer/i.test(d) ? 18500 : /balance/i.test(d) ? 9500 : /test|commission/i.test(d) ? 3500 : u === 'lot' ? 5000 : 500,
  brandRe: /pump|filter|heat|chlorinat|light/i, hold: {}, holdBy: [],
};

/** Founder 1687: one supplier per journey states ONLY a total including VAT, so the journey shows what the platform does. */
export function vatInclusiveOnly(html, doc) {
  const fmt = (n) => Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return html.replace(/<table class="tot"[\s\S]*?<\/table>/, `<table class="tot" style="width:45%;margin-left:55%"><tr><td><b>Total price (inclusive of VAT)</b></td><td class=r><b>AED ${fmt(doc.tot)}</b></td></tr></table>`)
    .replace('In AED, excluding VAT (VAT 5% shown separately)', 'In AED, inclusive of VAT');
}

/** The evidence pack's journey shape (quoteOne, chatQuote and holdValue read it) for one scenario. */
export function asEvidenceJourney(sc) {
  return { folder: sc.folder, label: sc.label, trade: sc.trade, title: sc.title, facts: sc.facts, confirm: sc.confirm, opener: sc.opener,
    defaultLines: sc.defaultLines || (sc.boq || []).map(([, description, qty, unit]) => ({ description, qty, unit })),
    specFor: sc.specFor, rate: sc.rate, brandRe: sc.brandRe, hold: sc.hold || {}, holdBy: sc.holdBy || [], suppliers: sc.quoting };
}

/** Fail early, offline: every scenario has what the runner needs. Returns the problems, empty when complete. */
export function scenarioProblems(sc) {
  const p = [];
  if (!sc.opener && !sc.voice && !sc.attach) p.push(`${sc.key}: no opener, voice note or attachment: the customer never says anything`);
  if (!SERVICE_WORDS[sc.trade]) p.push(`${sc.key}: no service sentence for ${sc.trade}`);
  for (const r of [...sc.matching.right, ...sc.matching.wrong]) if (!SERVICE_WORDS[r.trade]) p.push(`${sc.key}: no service sentence for ${r.trade}`);
  for (const u of sc.matching.unrelated) { if (!SERVICE_WORDS[u.trade]) p.push(`${sc.key}: no service sentence for ${u.trade}`); if (sc.trades.includes(u.trade)) p.push(`${sc.key}: ${u.trade} is listed as unrelated and as the job's trade`); }
  if (!sc.quoting?.length) p.push(`${sc.key}: nobody quotes`);
  if (!(sc.cap_usd > 0) || !(sc.estimate_usd > 0) || sc.estimate_usd > sc.cap_usd) p.push(`${sc.key}: the cap must be set and above the estimate`);
  return p;
}
