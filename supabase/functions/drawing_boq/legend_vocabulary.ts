// legend_vocabulary — the device types a drawing's BOQ uses, and what the drawing's own words were
// REASONED to name. English and Arabic labels. Seat: sales_engineer.
//
// WHY (14 Sep 2026). A fire alarm drawing read through the free path produced one junk BOQ line
// because nothing knew that "SMOKE DETECTOR c/w SOUNDER" is a thing a supplier prices. The legend is
// the drawing's own statement of what is on it; it becomes line types.
//
// REASONED, NOT PATTERN-MATCHED (23 Sep 2026, founder_instruction 886-903; decision point
// drawing_boq.vocabulary). A regex per device type decided which printed text named which device, a
// title regex decided the drawing type and a room-word list decided which labels were rooms. think()
// now reads the drawing's texts (_shared/reasoned_intake.ts drawingVocabulary) and returns, for each
// device type, the text that names it — copied from the drawing — so the parsers look it up EXACTLY and
// read nothing into it. Held (the model hold): the vocabulary is empty, the legend yields no lines, and
// the BOQ says the legend was not read, rather than guessing from a word.
//
// WHAT IT DOES NOT DO. It does not count. A legend entry says a device TYPE exists; how many there
// are comes from the counters (symbol_count.ts, a CAD block count) or from the customer.
import type { Stated } from '../_shared/reasoned_intake.ts';

export type DeviceType = { type: string; en: string; ar: string; unit: 'nos' | 'm' };

export const DEVICE_TYPES: DeviceType[] = [
  { type: 'fire_alarm_control_panel', en: 'Fire alarm control panel', ar: 'لوحة تحكم إنذار الحريق', unit: 'nos' },
  { type: 'repeater_panel', en: 'Repeater panel', ar: 'لوحة مكررة', unit: 'nos' },
  { type: 'manual_call_point', en: 'Manual call point (break glass)', ar: 'نقطة نداء يدوية (كسر الزجاج)', unit: 'nos' },
  { type: 'smoke_detector_sounder', en: 'Smoke detector c/w sounder', ar: 'كاشف دخان مع صفارة', unit: 'nos' },
  { type: 'heat_detector_sounder', en: 'Heat detector c/w sounder', ar: 'كاشف حرارة مع صفارة', unit: 'nos' },
  { type: 'multi_sensor_detector', en: 'Multi-sensor detector', ar: 'كاشف متعدد الحساسات', unit: 'nos' },
  { type: 'beam_detector', en: 'Beam detector', ar: 'كاشف شعاعي', unit: 'nos' },
  { type: 'smoke_detector', en: 'Smoke detector', ar: 'كاشف دخان', unit: 'nos' },
  { type: 'heat_detector', en: 'Heat detector', ar: 'كاشف حرارة', unit: 'nos' },
  { type: 'wall_sounder_beacon', en: 'Wall-mounted sounder beacon', ar: 'صفارة مع ضوء وامض جدارية', unit: 'nos' },
  { type: 'sounder', en: 'Sounder', ar: 'صفارة إنذار', unit: 'nos' },
  { type: 'beacon', en: 'Beacon', ar: 'ضوء وامض', unit: 'nos' },
  { type: 'interface_module', en: 'Interface / input-output module', ar: 'وحدة ربط', unit: 'nos' },
  { type: 'loop_isolator', en: 'Loop isolator', ar: 'عازل الحلقة', unit: 'nos' },
  { type: 'fire_rated_cable', en: 'Fire-rated cable', ar: 'كابل مقاوم للحريق', unit: 'm' },
];

/** What think() read the drawing's texts to name. Every text is copied from the drawing. */
export type Vocab = { device: [string, DeviceType][]; drawingType: string | null; rooms: string[] };
export const EMPTY_VOCAB: Vocab = { device: [], drawingType: null, rooms: [] };

/** The reasoned fields (drawingVocabulary) as a vocabulary the parsers look up. null (held) = empty. */
export function vocabFrom(stated: Stated | null): Vocab {
  if (!stated) return EMPTY_VOCAB;
  const device: [string, DeviceType][] = [];
  for (const d of DEVICE_TYPES) { const t = String(stated[`device:${d.type}`]?.value ?? '').trim(); if (t) device.push([t, d]); }
  const rooms = Object.entries(stated).filter(([k]) => k.startsWith('room:')).map(([, v]) => String(v.value).trim()).filter(Boolean);
  return { device, drawingType: String(stated.drawing_type?.value ?? '').trim() || null, rooms: [...new Set(rooms)] };
}

/**
 * The device type a printed text names, per the reasoning: the text itself, or a printed line that CONTAINS
 * the text the reasoning copied (locating the reasoned words in their own line, never reading a word). The
 * longest reasoned text wins, so "smoke detector c/w sounder" is not read as its shorter part.
 */
export function deviceTypeIn(text: string, vocab: Vocab): DeviceType | null {
  const t = String(text || '').trim().toLowerCase();
  if (!t) return null;
  let best: [string, DeviceType] | null = null;
  for (const e of vocab.device) if (t.includes(e[0].toLowerCase()) && (!best || e[0].length > best[0].length)) best = e;
  return best ? best[1] : null;
}
