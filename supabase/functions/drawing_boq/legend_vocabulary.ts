// legend_vocabulary — what a drawing's legend entry, a CAD block name or a BOQ line CALLS a device,
// mapped to one line type the BOQ uses. English and Arabic. No model.
//
// WHY (14 Sep 2026). A fire alarm drawing read through the free path produced one junk BOQ line
// because nothing knew that "SMOKE DETECTOR c/w SOUNDER" is a thing a supplier prices. The legend is
// the drawing's own statement of what is on it; this turns its words into line types.
//
// ORDER MATTERS: a combined device ("smoke detector c/w sounder") is tested before its parts, or it
// would be read as a plain smoke detector. OCR-tolerant: "¢/w", "c/w", "c w", "complete with" and
// "with" are the same thing, and common OCR confusions (0/O, 1/l/I, rn/m) are folded before matching.
//
// WHAT IT DOES NOT DO. It does not count. A legend entry says a device TYPE exists; how many there
// are comes from the counters (symbol_count.ts, a CAD block count) or from the customer.

export type DeviceType = {
  type: string; en: string; ar: string; unit: 'nos' | 'm';
  /** Tested against folded text; the first type whose pattern matches wins. */
  re: RegExp;
};

const CW = String.raw`(?:c\s*/?\s*w|complete\s+with|with|w/)`;
export const DEVICE_TYPES: DeviceType[] = [
  { type: 'fire_alarm_control_panel', en: 'Fire alarm control panel', ar: 'لوحة تحكم إنذار الحريق', unit: 'nos',
    re: new RegExp(String.raw`fire\s*alarm\s*(?:control\s*)?panel|\bf\.?a\.?c\.?p\b|\bfap\b|لوح[هة]\s*(?:تحكم\s*)?انذار`, 'i') },
  { type: 'repeater_panel', en: 'Repeater panel', ar: 'لوحة مكررة', unit: 'nos', re: /repeater\s*panel|\bmimic\s*panel/i },
  { type: 'manual_call_point', en: 'Manual call point (break glass)', ar: 'نقطة نداء يدوية (كسر الزجاج)', unit: 'nos',
    re: /manual\s*call\s*-?\s*point|\bmcp\b|break\s*glass|نقط[هة]\s*نداء|كسر\s*الزجاج/i },
  { type: 'smoke_detector_sounder', en: 'Smoke detector c/w sounder', ar: 'كاشف دخان مع صفارة', unit: 'nos',
    re: new RegExp(String.raw`smoke\s*detector\s*${CW}\s*(?:base\s*)?sounder|كاشف\s*دخان\s*مع\s*صفار`, 'i') },
  { type: 'heat_detector_sounder', en: 'Heat detector c/w sounder', ar: 'كاشف حرارة مع صفارة', unit: 'nos',
    re: new RegExp(String.raw`heat\s*detector\s*${CW}\s*(?:base\s*)?sounder|كاشف\s*حرار[هة]\s*مع\s*صفار`, 'i') },
  { type: 'multi_sensor_detector', en: 'Multi-sensor detector', ar: 'كاشف متعدد الحساسات', unit: 'nos', re: /multi[\s-]*sensor|optical\s*heat|كاشف\s*متعدد/i },
  { type: 'beam_detector', en: 'Beam detector', ar: 'كاشف شعاعي', unit: 'nos', re: /beam\s*detector|كاشف\s*شعاع/i },
  { type: 'smoke_detector', en: 'Smoke detector', ar: 'كاشف دخان', unit: 'nos', re: /smoke\s*detector|optical\s*detector|كاشف\s*دخان|كواشف\s*دخان/i },
  { type: 'heat_detector', en: 'Heat detector', ar: 'كاشف حرارة', unit: 'nos', re: /heat\s*detector|كاشف\s*حرار/i },
  { type: 'wall_sounder_beacon', en: 'Wall-mounted sounder beacon', ar: 'صفارة مع ضوء وامض جدارية', unit: 'nos',
    re: /(?:wall\s*mounted\s*)?sounder\s*[/&+]?\s*(?:visual\s*)?beacon|\bvad\b|صفار[هة]\s*(?:مع\s*)?(?:ضوء|وامض)/i },
  { type: 'sounder', en: 'Sounder', ar: 'صفارة إنذار', unit: 'nos', re: /\bsounder\b|\bbell\b|صفار[هة]\s*انذار/i },
  { type: 'beacon', en: 'Beacon', ar: 'ضوء وامض', unit: 'nos', re: /\bbeacon\b|\bstrobe\b|ضوء\s*وامض/i },
  { type: 'interface_module', en: 'Interface / input-output module', ar: 'وحدة ربط', unit: 'nos', re: /interface\s*(?:unit|module)|\bi\/o\s*module|وحد[هة]\s*ربط/i },
  { type: 'loop_isolator', en: 'Loop isolator', ar: 'عازل الحلقة', unit: 'nos', re: /loop\s*isolator|\bisolator\s*module|عازل\s*(?:ال)?حلق/i },
  { type: 'fire_rated_cable', en: 'Fire-rated cable', ar: 'كابل مقاوم للحريق', unit: 'm', re: /fp\s*200|fire\s*(?:rated|resistant)\s*cable|\bmicc\b|كابل\s*مقاوم/i },
];

/** Lower-case, fold OCR look-alikes that turn up in drawing text, keep Arabic. */
export function foldOcr(s: string): string {
  return String(s || '').toLowerCase()
    .replace(/[¢©]/g, 'c').replace(/[|]/g, 'l').replace(/[‘’`´]/g, "'")
    .replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه')
    .replace(/(?<=[a-z])0(?=[a-z])/g, 'o').replace(/(?<=[a-z])1(?=[a-z])/g, 'l').replace(/rn(?=[a-z])/g, 'm')
    .replace(/\s+/g, ' ').trim();
}

export function deviceTypeOf(text: string): DeviceType | null {
  const t = foldOcr(text);
  for (const d of DEVICE_TYPES) if (d.re.test(t)) return d;
  return null;
}
