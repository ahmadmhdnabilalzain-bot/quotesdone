// quote_review.fixture.ts — the synthetic quotation corpus for the sales engineer's review and the generaliser.
// Seat: sales_engineer. 10 Nov 2026, founder ledger 1588-1590.
//
// 24 trades, two from each of the twelve taxonomy groups (scripts/sql/the_missing_trades_join_the_taxonomy_under_twelve_
// groups.sql), goods and services. Each trade has ONE request and TWO quotes:
//   * DEVIANT — planted identifiers (a known brand, a model number, a proprietary product line, the supplier's own name
//     inside a description, a phone and an e-mail) and planted deviations (an origin swap, a requested item left out
//     or excluded, a lower grade, a quantity short, a lead time past the required date, a warranty shorter than asked);
//   * CONTROL — answers the request exactly (the right origin, grade and quantity, in time, the warranty asked), and
//     still names its own brand and model the way real quotations do: a review note on it is a false flag, and a
//     specification token it loses to the generaliser (SS316, 600x600, IP65, R410A) is an over-redaction.
// Every name is synthetic: suppliers are "ZZ DEMO …", addresses are @example.invalid (the estate's fixture convention).
// Read by _shared/quote_review_corpus.test.ts (the gate) and scripts/e2e/quote_review_corpus.ts (the before/after table).
import type { NoteCode, QuoteIn, QuoteLineIn, RequestLine } from './quote_review_notes.ts';

export type CorpusTrade = {
  code: string; group: string; supplier: string; summary: string;
  request: RequestLine[]; installation: 'yes' | 'not_needed'; warranty_months: number | null;
  control: { quote: QuoteIn; lines: QuoteLineIn[]; ids: string[]; keep: string[] };
  deviant: { quote: QuoteIn; lines: QuoteLineIn[]; ids: string[]; planted: { code: NoteCode; line_no: number | null }[] };
};
export const NOW = new Date('2026-11-10T08:00:00Z');
export const REQUIRED_BY = '2026-12-01';   // 21 days after NOW: "14 days" is in time, "8 weeks" is not
const PHONE = '050 123 4567';
const mail = (s: string) => `sales@${s}.example.invalid`;
const R = (description: string, qty: number, unit: string): RequestLine => ({ description, qty, unit });
const L = (line_no: number, description: string, qty: number, unit: string, amount: number, more: Partial<QuoteLineIn> = {}): QuoteLineIn => ({ line_no, description, qty, unit, amount, ...more });

type Build = Omit<CorpusTrade, 'control' | 'deviant'> & {
  control: { lines: QuoteLineIn[]; ids?: string[]; keep: string[]; quote?: Partial<QuoteIn> };
  deviant: { lines: QuoteLineIn[]; ids: string[]; planted: { code: NoteCode; line_no: number | null }[]; quote?: Partial<QuoteIn> };
};
function trade(b: Build): CorpusTrade {
  const slug = b.supplier.replace(/^ZZ DEMO\s+/, '').split(/\s+/)[0].toLowerCase();
  const goodWarranty = b.warranty_months ? (b.warranty_months >= 24 ? '2 years' : `${b.warranty_months} months`) : '';
  const devWarranty = b.warranty_months ? '6 months' : '';
  const late = b.deviant.planted.some((p) => p.code === 'lead_time_late');
  return {
    ...b,
    control: { lines: b.control.lines, ids: b.control.ids ?? [], keep: b.control.keep,
      quote: { lead_time: '14 days', warranty: goodWarranty, scope: b.installation === 'yes' ? 'Supply and installation as per your request' : 'As per your request', exclusions: '', conditions: 'Prices valid 30 days', notes: '', ...(b.control.quote || {}) } },
    deviant: { lines: b.deviant.lines, planted: b.deviant.planted,
      ids: [...b.deviant.ids, PHONE, mail(slug)],
      quote: { lead_time: late ? '8 weeks' : '14 days', warranty: devWarranty, scope: b.installation === 'yes' ? 'Supply and installation' : 'As per our offer', exclusions: '', conditions: 'Prices valid 30 days',
        notes: `For any query call ${PHONE} or write to ${mail(slug)}.`, ...(b.deviant.quote || {}) } },
  };
}
const GOODS: NoteCode[] = ['lead_time_late', 'warranty_short'];
const q = (code: NoteCode, line_no: number | null = null) => ({ code, line_no });

export const CORPUS: CorpusTrade[] = [
  // ── construction_building ──────────────────────────────────────────────────────────────────────
  trade({ code: 'flooring', group: 'construction_building', supplier: 'ZZ DEMO Marmara Tiles Trading LLC', summary: 'Villa ground floor tiling', installation: 'yes', warranty_months: 24,
    request: [R('Porcelain floor tiles 600x600, Italian origin, 10 mm thick', 120, 'm2'), R('Tile adhesive, cementitious C2TE', 40, 'bags'), R('Skirting tiles 600x100', 80, 'lm'), R('Epoxy grout for joints', 20, 'kg')],
    control: { lines: [L(1, 'Marazzi porcelain floor tiles 600x600, 10 mm thick, made in Italy', 120, 'm2', 14400), L(2, 'Tile adhesive cementitious C2TE', 40, 'bags', 1200), L(3, 'Skirting tiles 600x100', 80, 'lm', 1600), L(4, 'Epoxy grout for joints', 20, 'kg', 900)],
      ids: ['Marazzi'], keep: ['600x600', '10 mm', 'C2TE', '600x100'] },
    deviant: { lines: [L(1, 'Somany Duragres porcelain floor tiles 600x600, 8 mm thick, model GVT-6060', 120, 'm2', 9600, { country_of_origin: 'China' }), L(2, 'Tile adhesive C2TE by ZZ DEMO Marmara Tiles Trading', 30, 'bags', 900), L(3, 'Skirting tiles 600x100, StoneLux™ edge', 80, 'lm', 1400)],
      ids: ['Somany', 'Duragres', 'GVT-6060', 'StoneLux', 'ZZ DEMO Marmara'], planted: [q('origin_deviation', 1), q('grade_lower', 1), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'joinery', group: 'construction_building', supplier: 'ZZ DEMO Cedar Line Joinery LLC', summary: 'Office internal doors', installation: 'yes', warranty_months: 24,
    request: [R('Solid oak internal doors 2100x900, 45 mm, European origin', 12, 'nos'), R('Door lever handles, stainless steel SS316', 12, 'sets'), R('Door frames, solid wood', 12, 'nos'), R('Door closers, fire rated', 12, 'nos')],
    control: { lines: [L(1, 'Solid oak internal doors 2100x900, 45 mm, made in Germany', 12, 'nos', 30000), L(2, 'Door lever handles SS316, Hafele', 12, 'sets', 2400), L(3, 'Door frames solid wood', 12, 'nos', 6000), L(4, 'Door closers fire rated', 12, 'nos', 3600)],
      ids: ['Hafele'], keep: ['2100x900', '45 mm', 'SS316'] },
    deviant: { lines: [L(1, 'MDF internal doors 2100x900, 45 mm, oak veneer finish, ref DR-2190', 12, 'nos', 18000, { country_of_origin: 'China' }), L(2, 'Door lever handles SS304, Hettich Pro series', 10, 'sets', 1500), L(3, 'Door frames solid wood, ZZ DEMO Cedar Line signature profile', 12, 'nos', 5000)],
      ids: ['DR-2190', 'Hettich', 'Pro series', 'ZZ DEMO Cedar Line'], planted: [q('origin_deviation', 1), q('grade_lower', 1), q('grade_lower', 2), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  // ── mep_building_systems ───────────────────────────────────────────────────────────────────────
  trade({ code: 'plumbing', group: 'mep_building_systems', supplier: 'ZZ DEMO Nahr Sanitary Trading LLC', summary: 'Washroom refurbishment', installation: 'yes', warranty_months: 24,
    request: [R('Wall-hung wash basins, porcelain, European origin', 6, 'nos'), R('Basin mixer, Grohe or equivalent', 6, 'nos'), R('Grab bars, stainless steel SS316', 4, 'nos'), R('PPR pipes 25 mm PN20', 60, 'm')],
    control: { lines: [L(1, 'Wall-hung wash basins porcelain, Duravit, made in Germany', 6, 'nos', 6600), L(2, 'Basin mixer chrome', 6, 'nos', 4200, { brand: 'Grohe', model: '23461002' }), L(3, 'Grab bars stainless steel SS316', 4, 'nos', 1000), L(4, 'PPR pipes 25 mm PN20', 60, 'm', 900)],
      ids: ['Duravit', 'Grohe', '23461002'], keep: ['SS316', '25 mm', 'PN20'] },
    deviant: { lines: [L(1, 'Wall-hung wash basins porcelain, AquaLux™ range', 4, 'nos', 2400, { country_of_origin: 'China' }), L(2, 'Roca L20 basin mixer, model 5A3009C00', 6, 'nos', 1800, { brand: 'Roca', model: '5A3009C00' }), L(3, 'Grab bars stainless steel SS304 supplied by ZZ DEMO Nahr Sanitary Trading', 4, 'nos', 600)],
      ids: ['AquaLux', 'Roca', '5A3009C00', 'ZZ DEMO Nahr'], planted: [q('origin_deviation', 1), q('quantity_mismatch', 1), q('brand_tier_lower', 2), q('grade_lower', 3), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'hvac', group: 'mep_building_systems', supplier: 'ZZ DEMO Polar Air Conditioning LLC', summary: 'Warehouse office cooling', installation: 'yes', warranty_months: 24,
    request: [R('Ducted split AC 5 TR, Japanese origin, R410A', 4, 'nos'), R('Copper refrigerant piping, insulated', 60, 'm'), R('Wired thermostats', 4, 'nos'), R('Condensate pumps', 4, 'nos')],
    control: { lines: [L(1, 'Ducted split AC 5 TR, R410A, made in Japan', 4, 'nos', 36000, { brand: 'Daikin', model: 'FDYQN150' }), L(2, 'Copper refrigerant piping insulated', 60, 'm', 4800), L(3, 'Wired thermostats', 4, 'nos', 800), L(4, 'Condensate pumps', 4, 'nos', 1600)],
      ids: ['Daikin', 'FDYQN150'], keep: ['5 TR', 'R410A'] },
    deviant: { lines: [L(1, 'Gree ducted split AC 5 TR, R410A, model GUD140PHS', 4, 'nos', 22000), L(2, 'Aluminium refrigerant piping insulated', 40, 'm', 2000), L(3, 'Wired thermostats, ZZ DEMO Polar Air control kit', 4, 'nos', 600)],
      ids: ['Gree', 'GUD140PHS', 'ZZ DEMO Polar'], planted: [q('origin_deviation', 1), q('grade_lower', 2), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  // ── industrial_manufacturing ───────────────────────────────────────────────────────────────────
  trade({ code: 'industrial_pumps', group: 'industrial_manufacturing', supplier: 'ZZ DEMO Delta Flow Pumps Trading LLC', summary: 'Process water pumps', installation: 'not_needed', warranty_months: 24,
    request: [R('End-suction centrifugal pump 30 m3/h, 40 m head, SS316 impeller, European origin', 2, 'nos'), R('Pump control panel IP65', 2, 'nos'), R('Isolation valves DN80 PN16', 4, 'nos'), R('Commissioning and testing', 1, 'ls')],
    control: { lines: [L(1, 'End-suction centrifugal pump 30 m3/h 40 m head, SS316 impeller', 2, 'nos', 24000, { brand: 'KSB', model: 'Etanorm 050-032-200' }), L(2, 'Pump control panel IP65', 2, 'nos', 6000), L(3, 'Isolation valves DN80 PN16', 4, 'nos', 2000), L(4, 'Commissioning and testing', 1, 'ls', 1500)],
      ids: ['KSB', 'Etanorm 050-032-200'], keep: ['SS316', 'IP65', 'DN80', 'PN16'] },
    deviant: { lines: [L(1, 'Ebara 3M 40-200/7.5 end-suction centrifugal pump, SS304 impeller', 2, 'nos', 14000), L(2, 'Pump control panel IP54, FlowGuard™ controller', 1, 'nos', 2500), L(3, 'Isolation valves DN80 PN16 from ZZ DEMO Delta Flow stock', 4, 'nos', 1800)],
      ids: ['Ebara', '3M 40-200/7.5', 'FlowGuard', 'ZZ DEMO Delta Flow'], planted: [q('origin_deviation', 1), q('grade_lower', 1), q('grade_lower', 2), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'hand_power_tools', group: 'industrial_manufacturing', supplier: 'ZZ DEMO Toolmart Trading LLC', summary: 'Maintenance team tools', installation: 'not_needed', warranty_months: 12,
    request: [R('Cordless drill driver 18V, German origin', 10, 'nos'), R('Angle grinder 125 mm', 6, 'nos'), R('SDS-plus rotary hammer', 4, 'nos'), R('Spare batteries 18V 5.0Ah', 20, 'nos')],
    control: { lines: [L(1, 'Cordless drill driver 18V, made in Germany', 10, 'nos', 6500, { brand: 'Bosch', model: 'GSR 18V-55' }), L(2, 'Angle grinder 125 mm', 6, 'nos', 2400), L(3, 'SDS-plus rotary hammer', 4, 'nos', 3200), L(4, 'Spare batteries 18V 5.0Ah', 20, 'nos', 5000)],
      ids: ['Bosch', 'GSR 18V-55'], keep: ['18V', '125 mm', '5.0Ah'] },
    deviant: { lines: [L(1, 'Makita DHP485Z cordless drill driver 18V', 10, 'nos', 4200), L(2, 'Angle grinder 125 mm, PowerMax series', 4, 'nos', 1300), L(3, 'SDS-plus rotary hammer, ZZ DEMO Toolmart house kit', 4, 'nos', 2600)],
      ids: ['Makita', 'DHP485Z', 'PowerMax series', 'ZZ DEMO Toolmart'], planted: [q('origin_deviation', 1), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  // ── materials_packaging ────────────────────────────────────────────────────────────────────────
  trade({ code: 'chemicals', group: 'materials_packaging', supplier: 'ZZ DEMO Gulf Chem Trading LLC', summary: 'Warehouse floor and joints', installation: 'not_needed', warranty_months: 12,
    request: [R('Polyurethane joint sealant 600 ml, European origin', 200, 'nos'), R('Epoxy floor coating, 3 mm', 300, 'm2'), R('Concrete primer', 50, 'l'), R('Cleaning solvent', 40, 'l')],
    control: { lines: [L(1, 'Polyurethane joint sealant 600 ml, made in Switzerland', 200, 'nos', 5000, { brand: 'Sika', model: 'Sikaflex-11 FC+' }), L(2, 'Epoxy floor coating 3 mm', 300, 'm2', 27000), L(3, 'Concrete primer', 50, 'l', 1500), L(4, 'Cleaning solvent', 40, 'l', 600)],
      ids: ['Sika', 'Sikaflex-11 FC+'], keep: ['600 ml', '3 mm'] },
    deviant: { lines: [L(1, 'Polyurethane joint sealant 600 ml, Mapei Mapeflex PU45', 200, 'nos', 3600, { country_of_origin: 'China' }), L(2, 'Epoxy floor coating 2 mm, DuraCoat™ system', 300, 'm2', 18000), L(3, 'Concrete primer by ZZ DEMO Gulf Chem lab', 30, 'l', 700)],
      ids: ['Mapei', 'Mapeflex', 'PU45', 'DuraCoat', 'ZZ DEMO Gulf Chem'], planted: [q('origin_deviation', 1), q('grade_lower', 2), q('quantity_mismatch', 3), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'corrugated_packaging', group: 'materials_packaging', supplier: 'ZZ DEMO Boxco Packaging Industries LLC', summary: 'Shipping cartons', installation: 'not_needed', warranty_months: null,
    request: [R('Corrugated cartons 5-ply 400x300x300 mm, UAE origin', 10000, 'nos'), R('Logo printing, 2 colours', 10000, 'nos'), R('Pallet stretch film', 20, 'rolls'), R('Delivery to Jebel Ali warehouse', 1, 'ls')],
    control: { lines: [L(1, 'Corrugated cartons 5-ply 400x300x300 mm, made in UAE', 10000, 'nos', 32000), L(2, 'Logo printing 2 colours', 10000, 'nos', 4000), L(3, 'Pallet stretch film', 20, 'rolls', 1200), L(4, 'Delivery to Jebel Ali warehouse', 1, 'ls', 800)],
      keep: ['5-ply', '400x300x300 mm'] },
    deviant: { lines: [L(1, 'Corrugated cartons 5-ply 400x300x300 mm, BoxPro™ board, item code BX-4402', 8000, 'nos', 20000, { country_of_origin: 'China' }), L(2, 'Logo printing 2 colours, ZZ DEMO Boxco press', 10000, 'nos', 3000), L(3, 'Pallet stretch film', 20, 'rolls', 1000)],
      ids: ['BoxPro', 'BX-4402', 'ZZ DEMO Boxco'], planted: [q('origin_deviation', 1), q('quantity_mismatch', 1), q('scope_missing', 4), q('lead_time_late')] } }),
  // ── energy_environment ─────────────────────────────────────────────────────────────────────────
  trade({ code: 'solar', group: 'energy_environment', supplier: 'ZZ DEMO Sunpeak Solar Energy LLC', summary: 'Rooftop solar for a factory', installation: 'yes', warranty_months: 24,
    request: [R('Solar PV panels 550 W monocrystalline, European origin', 40, 'nos'), R('Hybrid inverter 10 kW, IP65', 2, 'nos'), R('Aluminium mounting structure', 1, 'set'), R('Lithium battery 10 kWh', 2, 'nos')],
    control: { lines: [L(1, 'Solar PV panels 550 W monocrystalline, made in Germany', 40, 'nos', 26000), L(2, 'Hybrid inverter 10 kW IP65', 2, 'nos', 12000, { brand: 'Fronius', model: 'Symo GEN24 10.0' }), L(3, 'Aluminium mounting structure', 1, 'set', 6000), L(4, 'Lithium battery 10 kWh', 2, 'nos', 18000)],
      ids: ['Fronius', 'Symo GEN24 10.0'], keep: ['550 W', '10 kW', 'IP65', '10 kWh'] },
    deviant: { lines: [L(1, 'JinkoSolar Tiger Neo 550 W monocrystalline panels, JKM550N-72HL4', 40, 'nos', 17000), L(2, 'Hybrid inverter 10 kW IP54', 1, 'nos', 5500), L(3, 'Aluminium mounting structure, ZZ DEMO Sunpeak rail system', 1, 'set', 4500)],
      ids: ['JinkoSolar', 'Tiger Neo', 'JKM550N-72HL4', 'ZZ DEMO Sunpeak'], planted: [q('origin_deviation', 1), q('grade_lower', 2), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'power_generators', group: 'energy_environment', supplier: 'ZZ DEMO Volt Power Generators Trading LLC', summary: 'Standby power for a cold store', installation: 'yes', warranty_months: 24,
    request: [R('Diesel generator 500 kVA prime rated, UK origin', 1, 'nos'), R('Automatic transfer switch panel 800 A', 1, 'nos'), R('Soundproof canopy 75 dBA', 1, 'nos'), R('Bulk fuel tank 1000 l', 1, 'nos')],
    control: { lines: [L(1, 'Diesel generator 500 kVA prime rated, made in UK', 1, 'nos', 145000, { brand: 'Perkins', model: '2806A-E18TAG2' }), L(2, 'Automatic transfer switch panel 800 A', 1, 'nos', 18000), L(3, 'Soundproof canopy 75 dBA', 1, 'nos', 22000), L(4, 'Bulk fuel tank 1000 l', 1, 'nos', 9000)],
      ids: ['Perkins', '2806A-E18TAG2'], keep: ['500 kVA', '800 A', '75 dBA', '1000 l'] },
    deviant: { lines: [L(1, 'Cummins C550D5 diesel generator 500 kVA prime rated', 1, 'nos', 118000, { country_of_origin: 'India' }), L(2, 'Automatic transfer switch panel 800 A', 2, 'nos', 30000), L(3, 'Soundproof canopy 75 dBA, ZZ DEMO Volt Power QuietBox™', 1, 'nos', 15000)],
      ids: ['Cummins', 'C550D5', 'QuietBox', 'ZZ DEMO Volt'], planted: [q('origin_deviation', 1), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  // ── transport_mobility ─────────────────────────────────────────────────────────────────────────
  trade({ code: 'staff_transport', group: 'transport_mobility', supplier: 'ZZ DEMO Rahal Passenger Transport LLC', summary: 'Staff buses for a factory, 12 months', installation: 'not_needed', warranty_months: null,
    request: [R('30-seater bus with driver, monthly rental, Japanese make', 2, 'buses'), R('Diesel fuel for the buses', 12, 'months'), R('Replacement vehicle within 4 hours', 12, 'months'), R('Salik and parking charges', 12, 'months')],
    control: { lines: [L(1, '30-seater bus with driver, monthly rental, Toyota Coaster, Japanese make', 2, 'buses', 18000), L(2, 'Diesel fuel for the buses', 12, 'months', 9600), L(3, 'Replacement vehicle within 4 hours', 12, 'months', 0.01), L(4, 'Salik and parking charges', 12, 'months', 2400)],
      ids: ['Toyota Coaster'], keep: ['30-seater', '4 hours'] },
    deviant: { lines: [L(1, 'King Long XMQ6900 30-seater bus with driver, monthly rental', 1, 'buses', 7000), L(2, 'Replacement vehicle within 4 hours, ZZ DEMO Rahal RapidSwap™ service', 12, 'months', 0.01), L(3, 'Salik and parking charges', 12, 'months', 2000)],
      ids: ['King Long', 'XMQ6900', 'RapidSwap', 'ZZ DEMO Rahal'], quote: { exclusions: 'Diesel fuel for the buses' },
      planted: [q('origin_deviation', 1), q('quantity_mismatch', 1), q('scope_excluded', 2), q('lead_time_late')] } }),
  trade({ code: 'tyres_batteries', group: 'transport_mobility', supplier: 'ZZ DEMO Tyreland Auto Parts Trading LLC', summary: 'Fleet tyre replacement', installation: 'yes', warranty_months: 12,
    request: [R('Truck tyres 315/80R22.5, Japanese origin', 24, 'nos'), R('Truck batteries 12V 200Ah', 12, 'nos'), R('Fitting and wheel balancing', 24, 'nos'), R('Disposal of old tyres', 24, 'nos')],
    control: { lines: [L(1, 'Truck tyres 315/80R22.5, made in Japan', 24, 'nos', 33600, { brand: 'Bridgestone', model: 'R249' }), L(2, 'Truck batteries 12V 200Ah', 12, 'nos', 9600), L(3, 'Fitting and wheel balancing', 24, 'nos', 1200), L(4, 'Disposal of old tyres', 24, 'nos', 480)],
      ids: ['Bridgestone', 'R249'], keep: ['315/80R22.5', '12V', '200Ah'] },
    deviant: { lines: [L(1, 'Linglong KTD300 truck tyres 315/80R22.5', 20, 'nos', 16000, { country_of_origin: 'China' }), L(2, 'Truck batteries 12V 200Ah, ZZ DEMO Tyreland PowerCell™', 12, 'nos', 7200), L(3, 'Fitting and wheel balancing', 24, 'nos', 1000)],
      ids: ['Linglong', 'KTD300', 'PowerCell', 'ZZ DEMO Tyreland'], planted: [q('origin_deviation', 1), q('quantity_mismatch', 1), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  // ── technology_telecom ─────────────────────────────────────────────────────────────────────────
  trade({ code: 'office_equipment', group: 'technology_telecom', supplier: 'ZZ DEMO Printech Office Systems LLC', summary: 'Printers for an office floor', installation: 'yes', warranty_months: 12,
    request: [R('A3 colour laser printer 35 ppm, Japanese origin', 3, 'nos'), R('Toner sets', 6, 'sets'), R('Network setup', 3, 'nos'), R('On-site maintenance', 12, 'months')],
    control: { lines: [L(1, 'A3 colour laser printer 35 ppm, made in Japan', 3, 'nos', 21000, { brand: 'Canon', model: 'imageRUNNER ADVANCE C3835i' }), L(2, 'Toner sets', 6, 'sets', 4800), L(3, 'Network setup', 3, 'nos', 900), L(4, 'On-site maintenance', 12, 'months', 3600)],
      ids: ['Canon', 'imageRUNNER ADVANCE C3835i'], keep: ['A3', '35 ppm'] },
    deviant: { lines: [L(1, 'HP Color LaserJet Enterprise M751dn A3 colour laser printer 35 ppm', 3, 'nos', 15000), L(2, 'Toner sets W2000A', 4, 'sets', 2800), L(3, 'Network setup by ZZ DEMO Printech engineers', 3, 'nos', 600)],
      ids: ['HP', 'LaserJet', 'M751dn', 'W2000A', 'ZZ DEMO Printech'], planted: [q('origin_deviation', 1), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'it_services', group: 'technology_telecom', supplier: 'ZZ DEMO Netcore IT Solutions LLC', summary: 'Office IT refresh', installation: 'yes', warranty_months: 24,
    request: [R('Business laptops, Core i7, 16 GB RAM, 512 GB SSD', 20, 'nos'), R('Managed network switch 24-port PoE', 2, 'nos'), R('Wi-Fi access points', 8, 'nos'), R('Installation and configuration', 1, 'ls')],
    control: { lines: [L(1, 'Business laptops Core i7 16 GB RAM 512 GB SSD', 20, 'nos', 90000, { brand: 'Dell', model: 'Latitude 5450' }), L(2, 'Managed network switch 24-port PoE', 2, 'nos', 9000), L(3, 'Wi-Fi access points', 8, 'nos', 6400), L(4, 'Installation and configuration', 1, 'ls', 5000)],
      ids: ['Dell', 'Latitude 5450'], keep: ['16 GB', '512 GB', '24-port', 'PoE'] },
    deviant: { lines: [L(1, 'Lenovo ThinkPad T14 Gen 5 business laptops Core i7 16 GB RAM 512 GB SSD, 21ML0035AD', 20, 'nos', 78000), L(2, 'Managed network switch 24-port PoE, Cisco CBS350-24P', 2, 'nos', 7000), L(3, 'Wi-Fi access points, ZZ DEMO Netcore MeshPro™', 6, 'nos', 4200)],
      ids: ['Lenovo', 'ThinkPad', '21ML0035AD', 'Cisco', 'CBS350-24P', 'MeshPro', 'ZZ DEMO Netcore'], quote: { exclusions: 'Installation and configuration' },
      planted: [q('quantity_mismatch', 3), q('scope_excluded', 4), q('scope_excluded'), ...GOODS.map((c) => q(c))] } }),
  // ── facilities_property ────────────────────────────────────────────────────────────────────────
  trade({ code: 'cleaning', group: 'facilities_property', supplier: 'ZZ DEMO Sparkle Cleaning Services LLC', summary: 'Office cleaning contract', installation: 'not_needed', warranty_months: null,
    request: [R('Daily office cleaning, 2 cleaners, 8 hours', 12, 'months'), R('Carpet deep cleaning, monthly', 12, 'visits'), R('Washroom consumables', 12, 'months'), R('Window cleaning, quarterly', 4, 'visits')],
    control: { lines: [L(1, 'Daily office cleaning 2 cleaners 8 hours', 12, 'months', 96000), L(2, 'Carpet deep cleaning monthly', 12, 'visits', 9600), L(3, 'Washroom consumables', 12, 'months', 12000), L(4, 'Window cleaning quarterly', 4, 'visits', 6000)],
      keep: ['8 hours'] },
    deviant: { lines: [L(1, 'Daily office cleaning 2 cleaners 8 hours, ZZ DEMO Sparkle ShineCare™ programme', 10, 'months', 70000), L(2, 'Carpet deep cleaning monthly with Karcher Puzzi 10/1 machine', 12, 'visits', 7200)],
      ids: ['ShineCare', 'Karcher', 'Puzzi 10/1', 'ZZ DEMO Sparkle'], quote: { exclusions: 'Washroom consumables' },
      planted: [q('quantity_mismatch', 1), q('scope_excluded', 3), q('scope_missing', 4), q('lead_time_late')] } }),
  trade({ code: 'security_guarding', group: 'facilities_property', supplier: 'ZZ DEMO Shield Guard Security Services LLC', summary: 'Warehouse guarding', installation: 'not_needed', warranty_months: null,
    request: [R('Licensed security guards, 12-hour shifts', 4, 'guards'), R('Guard supervisor', 1, 'nos'), R('CCTV monitoring', 12, 'months'), R('Patrol vehicle', 1, 'nos')],
    control: { lines: [L(1, 'Licensed security guards 12-hour shifts', 4, 'guards', 240000), L(2, 'Guard supervisor', 1, 'nos', 90000), L(3, 'CCTV monitoring', 12, 'months', 24000), L(4, 'Patrol vehicle', 1, 'nos', 36000)],
      keep: ['12-hour'] },
    deviant: { lines: [L(1, 'Licensed security guards 12-hour shifts, ZZ DEMO Shield Guard SecureWatch™ app', 3, 'guards', 170000), L(2, 'Guard supervisor', 1, 'nos', 80000)],
      ids: ['SecureWatch', 'ZZ DEMO Shield Guard'], quote: { exclusions: 'CCTV monitoring' },
      planted: [q('quantity_mismatch', 1), q('scope_excluded', 3), q('scope_missing', 4), q('lead_time_late')] } }),
  // ── professional_business ──────────────────────────────────────────────────────────────────────
  trade({ code: 'accounting_bookkeeping', group: 'professional_business', supplier: 'ZZ DEMO Ledger Point Accounting LLC', summary: 'Bookkeeping for a trading company', installation: 'not_needed', warranty_months: null,
    request: [R('Monthly bookkeeping', 12, 'months'), R('Quarterly VAT return filing', 4, 'returns'), R('Year-end financial statements', 1, 'ls'), R('Payroll processing (WPS)', 12, 'months')],
    control: { lines: [L(1, 'Monthly bookkeeping', 12, 'months', 18000), L(2, 'Quarterly VAT return filing', 4, 'returns', 4000), L(3, 'Year-end financial statements', 1, 'ls', 5000), L(4, 'Payroll processing (WPS)', 12, 'months', 6000)],
      keep: ['WPS'] },
    deviant: { lines: [L(1, 'Monthly bookkeeping on Zoho Books with the ZZ DEMO Ledger Point LedgerPro™ method', 6, 'months', 7200), L(2, 'Year-end financial statements', 1, 'ls', 4000)],
      ids: ['Zoho Books', 'LedgerPro', 'ZZ DEMO Ledger Point'], quote: { exclusions: 'VAT return filing' },
      planted: [q('quantity_mismatch', 1), q('scope_excluded', 2), q('scope_missing', 4), q('lead_time_late')] } }),
  trade({ code: 'engineering_consultancy', group: 'professional_business', supplier: 'ZZ DEMO Axis Line Engineering Consultants', summary: 'MEP design for a warehouse', installation: 'not_needed', warranty_months: null,
    request: [R('MEP design drawings, IFC stage', 1, 'ls'), R('Authority approvals, DEWA and Civil Defence', 1, 'ls'), R('Site supervision visits', 20, 'visits'), R('As-built drawings', 1, 'ls')],
    control: { lines: [L(1, 'MEP design drawings IFC stage', 1, 'ls', 60000), L(2, 'Authority approvals DEWA and Civil Defence', 1, 'ls', 15000), L(3, 'Site supervision visits', 20, 'visits', 20000), L(4, 'As-built drawings', 1, 'ls', 8000)],
      keep: ['IFC', 'DEWA'] },
    deviant: { lines: [L(1, 'MEP design drawings IFC stage in Autodesk Revit 2025, DesignFast™ workflow', 1, 'ls', 45000), L(2, 'Site supervision visits by ZZ DEMO Axis Line Engineering', 10, 'visits', 8000)],
      ids: ['DesignFast', 'ZZ DEMO Axis Line'], quote: { exclusions: 'Authority approvals' },
      planted: [q('scope_excluded', 2), q('quantity_mismatch', 3), q('scope_missing', 4), q('lead_time_late')] } }),
  // ── marketing_media_events ─────────────────────────────────────────────────────────────────────
  trade({ code: 'signage', group: 'marketing_media_events', supplier: 'ZZ DEMO Brightsign Advertising LLC', summary: 'Shopfront sign', installation: 'yes', warranty_months: 24,
    request: [R('3D acrylic letters, LED illuminated, IP65, 600 mm high', 1, 'set'), R('Aluminium composite panel backing, 4 mm', 12, 'm2'), R('Installation at height with lift', 1, 'ls'), R('Municipality permit', 1, 'ls')],
    control: { lines: [L(1, '3D acrylic letters LED illuminated IP65 600 mm high', 1, 'set', 14000), L(2, 'Aluminium composite panel backing 4 mm', 12, 'm2', 3600), L(3, 'Installation at height with lift', 1, 'ls', 2500), L(4, 'Municipality permit', 1, 'ls', 1500)],
      keep: ['IP65', '600 mm', '4 mm'] },
    deviant: { lines: [L(1, '3D acrylic letters LED illuminated IP44, Mean Well HLG-150H-12 drivers', 1, 'set', 9000), L(2, 'Aluminium composite panel backing 3 mm, Alucobond plus', 10, 'm2', 2000), L(3, 'Installation at height with lift, ZZ DEMO Brightsign crew', 1, 'ls', 2000)],
      ids: ['Mean Well', 'HLG-150H-12', 'Alucobond', 'ZZ DEMO Brightsign'], planted: [q('grade_lower', 1), q('grade_lower', 2), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'event_management', group: 'marketing_media_events', supplier: 'ZZ DEMO Gala Events Management LLC', summary: 'Annual corporate dinner', installation: 'not_needed', warranty_months: null,
    request: [R('Corporate gala dinner, guests', 300, 'guests'), R('Stage 12x6 m with LED screen', 1, 'ls'), R('Line-array sound system', 1, 'ls'), R('Photography and video', 1, 'ls')],
    control: { lines: [L(1, 'Corporate gala dinner guests', 300, 'guests', 90000), L(2, 'Stage 12x6 m with LED screen', 1, 'ls', 30000), L(3, 'Line-array sound system', 1, 'ls', 15000), L(4, 'Photography and video', 1, 'ls', 8000)],
      keep: ['12x6 m'] },
    deviant: { lines: [L(1, 'Corporate gala dinner guests, ZZ DEMO Gala GalaPrime™ package', 250, 'guests', 62000), L(2, 'Stage 12x6 m with Absen A27 Pro LED screen', 1, 'ls', 24000), L(3, 'Line-array sound system', 1, 'ls', 12000)],
      ids: ['GalaPrime', 'Absen', 'A27 Pro', 'ZZ DEMO Gala'], planted: [q('quantity_mismatch', 1), q('scope_missing', 4), q('lead_time_late')] } }),
  // ── health_lab_safety ──────────────────────────────────────────────────────────────────────────
  trade({ code: 'safety_equipment', group: 'health_lab_safety', supplier: 'ZZ DEMO Safeguard PPE Trading LLC', summary: 'PPE for a construction site', installation: 'not_needed', warranty_months: 12,
    request: [R('Safety helmets EN397, European origin', 200, 'nos'), R('Safety shoes S3 steel toe', 200, 'pairs'), R('Hi-vis vests class 2', 200, 'nos'), R('FFP3 disposable respirators', 500, 'nos')],
    control: { lines: [L(1, 'Safety helmets EN397, made in Germany', 200, 'nos', 9000, { brand: 'Uvex', model: 'pheos B-WR' }), L(2, 'Safety shoes S3 steel toe', 200, 'pairs', 24000), L(3, 'Hi-vis vests class 2', 200, 'nos', 2400), L(4, 'FFP3 disposable respirators', 500, 'nos', 6000)],
      ids: ['Uvex', 'pheos B-WR'], keep: ['EN397', 'S3', 'FFP3'] },
    deviant: { lines: [L(1, 'Safety helmets EN397, SafeTop™ shell', 200, 'nos', 5000, { country_of_origin: 'China' }), L(2, 'Safety shoes S3 steel toe, Delta Plus model JUMPER3', 150, 'pairs', 13500), L(3, 'Hi-vis vests class 2 printed ZZ DEMO Safeguard', 200, 'nos', 1800)],
      ids: ['SafeTop', 'Delta Plus', 'JUMPER3', 'ZZ DEMO Safeguard'], planted: [q('origin_deviation', 1), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'medical_consumables', group: 'health_lab_safety', supplier: 'ZZ DEMO Medisupply Medical Equipment Trading LLC', summary: 'Clinic consumables', installation: 'not_needed', warranty_months: null,
    request: [R('Nitrile examination gloves, powder-free, Malaysian origin', 500, 'boxes'), R('Surgical masks type IIR', 1000, 'boxes'), R('Syringes 5 ml', 10000, 'nos'), R('Alcohol swabs', 5000, 'nos')],
    control: { lines: [L(1, 'Nitrile examination gloves powder-free, made in Malaysia', 500, 'boxes', 12500), L(2, 'Surgical masks type IIR', 1000, 'boxes', 9000), L(3, 'Syringes 5 ml', 10000, 'nos', 3000, { brand: 'Terumo' }), L(4, 'Alcohol swabs', 5000, 'nos', 500)],
      ids: ['Terumo'], keep: ['IIR', '5 ml'] },
    deviant: { lines: [L(1, 'Nitrile examination gloves powder-free, Ansell TouchNTuff 92-600', 500, 'boxes', 9000, { country_of_origin: 'China' }), L(2, 'Surgical masks type IIR, ZZ DEMO Medisupply CareShield™', 1000, 'boxes', 7000), L(3, 'Syringes 5 ml', 8000, 'nos', 2000)],
      ids: ['Ansell', 'TouchNTuff', '92-600', 'CareShield', 'ZZ DEMO Medisupply'], planted: [q('origin_deviation', 1), q('quantity_mismatch', 3), q('scope_missing', 4), q('lead_time_late')] } }),
  // ── furniture_hospitality_consumer ─────────────────────────────────────────────────────────────
  trade({ code: 'office_furniture', group: 'furniture_hospitality_consumer', supplier: 'ZZ DEMO Workspace Furniture Trading LLC', summary: 'Open-plan office furniture', installation: 'yes', warranty_months: 24,
    request: [R('Ergonomic task chairs, mesh back, European origin', 50, 'nos'), R('Height-adjustable desks 1600x800, solid wood top', 50, 'nos'), R('Mobile pedestals, 3 drawers', 50, 'nos'), R('Delivery and assembly', 1, 'ls')],
    control: { lines: [L(1, 'Ergonomic task chairs mesh back, made in Germany', 50, 'nos', 60000, { brand: 'Sedus', model: 'se:flex' }), L(2, 'Height-adjustable desks 1600x800, solid wood top', 50, 'nos', 90000), L(3, 'Mobile pedestals 3 drawers', 50, 'nos', 20000), L(4, 'Delivery and assembly', 1, 'ls', 6000)],
      ids: ['Sedus', 'se:flex'], keep: ['1600x800'] },
    deviant: { lines: [L(1, 'Herman Miller Aeron ergonomic task chairs, mesh back, AER1B23DW', 50, 'nos', 52000), L(2, 'Height-adjustable desks 1600x800, MDF top', 50, 'nos', 45000), L(3, 'Mobile pedestals 3 drawers, ZZ DEMO Workspace FlexiStore™', 40, 'nos', 12000)],
      ids: ['Herman Miller', 'Aeron', 'AER1B23DW', 'FlexiStore', 'ZZ DEMO Workspace'], planted: [q('origin_deviation', 1), q('grade_lower', 2), q('quantity_mismatch', 3), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
  trade({ code: 'commercial_kitchen', group: 'furniture_hospitality_consumer', supplier: 'ZZ DEMO Chefline Kitchen Equipment Trading LLC', summary: 'Hotel kitchen equipment', installation: 'yes', warranty_months: 24,
    request: [R('Combi oven 10 GN 1/1, German origin', 2, 'nos'), R('Work tables, stainless steel SS304', 6, 'nos'), R('Hood-type dishwasher', 1, 'nos'), R('Exhaust hood with grease filters', 1, 'nos')],
    control: { lines: [L(1, 'Combi oven 10 GN 1/1, made in Germany', 2, 'nos', 64000, { brand: 'Rational', model: 'iCombi Pro 10-1/1' }), L(2, 'Work tables stainless steel SS304', 6, 'nos', 9000), L(3, 'Hood-type dishwasher', 1, 'nos', 21000), L(4, 'Exhaust hood with grease filters', 1, 'nos', 15000)],
      ids: ['Rational', 'iCombi Pro 10-1/1'], keep: ['10 GN 1/1', 'SS304'] },
    deviant: { lines: [L(1, 'Unox Cheftop Mind.Maps combi oven 10 GN 1/1, XEVC-1011-EPR', 2, 'nos', 46000), L(2, 'Work tables stainless steel SS201', 4, 'nos', 4000), L(3, 'Hood-type dishwasher, ZZ DEMO Chefline WashPro™', 1, 'nos', 14000)],
      ids: ['Unox', 'Cheftop', 'XEVC-1011-EPR', 'WashPro', 'ZZ DEMO Chefline'], planted: [q('origin_deviation', 1), q('grade_lower', 2), q('quantity_mismatch', 2), q('scope_missing', 4), ...GOODS.map((c) => q(c))] } }),
];

/** The intake answers of a corpus trade, as inquiries.spec stores them. */
export function specOf(t: CorpusTrade) {
  return { customer_requirements: { version: 2, installation: { required: t.installation }, warranty: t.warranty_months ? { required: 'yes', min_months: t.warranty_months } : { required: 'not_needed' },
    required_by: { flexible: false, date: REQUIRED_BY } } };
}
