// The stage-2 demo customer's FACT SHEET (it_engineer, 7 Oct 2026). Pure: no database, no token.
import { TRADE_DEFS } from './trade_defs.mjs';

// ---- the interview: a FACT SHEET per demo customer ------------------------------------------
// Stage-2 run fe7ba9c4 (7 Oct 2026): after four scripted answers the harness sent "standard
// specification, please assume typical values" for whatever was missing, so no interview reached
// ready and every downstream scenario had no request to work on. A demo customer now carries a fact
// sheet covering every slot of its trade's checklist, and each turn answers the question the intake
// actually asked, chosen by the KEYS the response returns (next_question.key,
// required_gate.missing_keys, and `missing` entries that are keys) -- never by reading the question.
//
// Keys are the category_specs field keys (read on production for the 11 stage-2 trades, 7 Oct 2026)
// and the sales engineer's requirement keys (supabase/functions/_shared/intake_requirements.ts). A key
// the sheet does not know is answered with the whole sheet: real facts, never filler.
const SLOT_OF = {
  // Run 321d13ae (18 Oct 2026): system_type answered with the element ("fan coil unit, AHU, ducting")
  // and fixture_count with the door-sized lines; neither says split/ducted/central or how many
  // bathrooms, so C4 hvac and C3 plumbing were held for specs unanswered three times. Each has its fact.
  element: 'element', item_type: 'element', floor_type: 'element', type: 'element', system_type: 'system_type',
  dimensions_qty: 'lines', quantity_size: 'lines', 'quantity-unit': 'lines', fixture_count: 'fixtures', point_counts: 'lines',
  stops: 'stops', capacity: 'capacity',
  location: 'location', location_floor: 'location',
  area_sqm: 'area', area: 'area', property_area: 'area', areas: 'purpose', application_area: 'purpose', safety_context: 'purpose',
  scope: 'scope', scope_mode: 'scope', supply_install: 'scope',
  new_mod: 'new_or_replace', new_or_replace: 'new_or_replace', issue: 'leak', removal_levelling: 'new_or_replace',
  timeline: 'timeline', supply_phase: 'supply_phase', surface_prep: 'surface_prep', design: 'design',
  system_finish: 'material', glazing: 'material', glazing_performance: 'material', finish: 'finish', aluminium_system: 'material',
  carcass_material: 'material', brand_tier: 'material', brand: 'material', color_finish: 'material', thickness_wear: 'material',
};
// The sales engineer's tap-to-answer questions accept an option VALUE (parseRequirementAnswer matches
// x.v), so these answers are the same in either language.
const REQ_VALUE = { installation: 'yes', warranty: 'yes_24', required_by: 'm1' };

/**
 * Every slot a trade checklist can ask, for one demo customer: element and lines with sizes and
 * quantities, location and emirate, timeline, warranty, new or replacement, area, purpose per line,
 * material. `notSure` answers the material question "not sure" on purpose -- that path is proved too.
 */
export function factSheet(trade, { lang = 'en', emirate = 'Dubai', notSure = false } = {}) {
  const t = TRADE_DEFS[trade] || { name: trade, products: [trade, trade, trade] };
  const [p0, p1, p2] = t.products;
  const v = lang === 'ar' ? {
    element: `${t.name}: ${p0} و${p1} و${p2}`,
    lines: `البند 1: ${p0} عدد 20، مقاس 1200 × 1500 مم لكل وحدة؛ البند 2: ${p1} عدد 10، مقاس 900 × 2100 مم لكل وحدة؛ البند 3: ${p2} عدد 5، مقاس 3000 × 2400 مم لكل وحدة`,
    purpose: 'البند 1 لغرف النوم، البند 2 للمدخل الرئيسي والشرفات، البند 3 لواجهة غرفة المعيشة',
    location: `فيلا في ${emirate}، الطابق الأرضي والأول، وصول مباشر بالطريق، لا حاجة لرافعة`,
    area: 'حوالي 450 متر مربع مساحة مبنية، 6 غرف',
    scope: 'توريد وتركيب، مع إزالة القطع القديمة والتخلص منها',
    new_or_replace: 'استبدال قطع قائمة في فيلا مسكونة',
    timeline: 'خلال شهر واحد',
    warranty: 'ضمان سنتان على الأقل',
    supply_phase: 'تغذية ثلاثية الطور 400 فولت',
    surface_prep: 'جدران مدهونة سابقًا بحالة جيدة مع إصلاح شقوق بسيطة',
    stops: '4 وقفات (أرضي + 3)', capacity: '8 أشخاص، 630 كغ', design: 'التصميم جاهز',
    material: notSure ? 'لست متأكداً' : 'درجة تجارية قياسية من علامة معروفة',
    leak: 'لا يوجد تسرب حالياً، العمل وقائي',
    finish: 'لامينيت / ميلامين',
    system_type: 'نظام مركزي بالمياه المبردة: وحدات فان كويل مخفية بمجارٍ مع وحدات مناولة هواء',
    fixtures: '4 حمامات ومطبخ واحد',
  } : {
    element: `${t.name}: ${p0}, ${p1} and ${p2}`,
    lines: `Line 1: ${p0} x 20, 1200 x 1500 mm each; Line 2: ${p1} x 10, 900 x 2100 mm each; Line 3: ${p2} x 5, 3000 x 2400 mm each`,
    purpose: 'Line 1 is for the bedrooms, line 2 for the main entrance and balconies, line 3 for the living-room facade',
    location: `Villa in ${emirate}, ground and first floor, clear road access, no crane needed`,
    area: 'About 450 m2 built-up, 6 rooms',
    scope: 'Supply and install, including removal and disposal of the existing items',
    new_or_replace: 'Replacement of existing items in an occupied villa',
    timeline: 'Within 1 month',
    warranty: 'At least 2 years',
    supply_phase: 'Three-phase 400 V supply',
    surface_prep: 'Previously painted walls in fair condition, minor crack repair',
    stops: '4 stops (G+3)', capacity: '8 persons, 630 kg', design: 'Design is ready',
    material: notSure ? 'Not sure' : `Standard commercial grade, ${t.brands?.[0] || 'a known brand'}`,
    // Run f4294be8 (12 Oct 2026): the sheet had no fact for waterproofing `issue` (leak now or
    // preventive) nor joinery `finish`; it answered them with new_or_replace and the brand-grade
    // material, which do not say either, and C9/C6 were asked 13 times. Each now has its own fact.
    leak: 'No leak at the moment, this is preventive',
    finish: 'Laminate / melamine',
    system_type: 'Central chilled-water system: ducted concealed fan coil units with air handling units',
    fixtures: '4 bathrooms and 1 kitchen',
  };
  // Run 321d13ae cust23: landscaping area_sqm got "450 m2 built-up, 6 rooms", which is the house, not
  // the garden, and the intake was held after three asks. Landscaping's area is the outdoor area.
  if (trade === 'landscaping') v.area = lang === 'ar' ? 'مساحة الحديقة الخارجية حوالي 300 متر مربع' : 'Garden (outdoor) area of about 300 m2';
  // Run 0a717394 (19 Oct 2026): waterproofing has TWO keys, `area` (a select: WHICH part - Roof, Bathroom,
  // Balcony...) and `area_sqm` (how big). Both read the built-up size, which answers area_sqm and never
  // says where, so `area` stayed open three turns and C9 was held 'specs_unanswered: area'. It names a part.
  const slotOf = (k) => (trade === 'waterproofing' && k === 'area' ? 'wp_part' : SLOT_OF[k]);
  if (trade === 'waterproofing') v.wp_part = lang === 'ar' ? 'السطح (Roof)' : 'Roof';
  const whole = () => Object.entries(v).map(([k, x]) => `${k}: ${x}`).join('. ') + '.';
  return {
    trade, lang, notSure, values: v,
    opening: `${v.element}. ${v.lines}. ${v.location}.`,
    /** The answer to the next turn, from the keys the last intake response returned. */
    answerFor(r) {
      const nq = r?.next_question || null;
      const k0 = nq?.key ? String(nq.key) : null;
      if (k0 && REQ_VALUE[k0]) return REQ_VALUE[k0];
      if (k0 && k0.startsWith('material.')) return notSure ? v.material : (Array.isArray(nq.options) && nq.options[0]) || v.material;
      // missing_keys: the open slot keys before a ready, when required_gate is null (inquiry_intake, 18 Oct 2026).
      const keys = [...new Set([k0, ...(r?.required_gate?.missing_keys || []), ...(r?.missing_keys || []),
        ...(Array.isArray(r?.missing) ? r.missing : []).filter((m) => /^[a-z0-9_.-]+$/i.test(String(m)))]
        .filter(Boolean).map(String))];
      const parts = keys.filter((k) => v[slotOf(k)]).map((k) => `${k}: ${v[slotOf(k)]}`);
      return parts.length ? parts.join('. ') + '.' : whole();
    },
  };
}

