// drawing_location — the PLACE BELOW THE EMIRATE a drawing prints, as one rule for every drawing route (the CAD
// preview and file, the scan OCR floor, the PDF title-block boxes). Imports nothing of the drawing modules, so each of
// them can use it without a cycle.
import * as identityText from './identity_text.ts';

// ── LOCATION BELOW THE EMIRATE (13 Nov 2026, sales_engineer; founder ruling 1683: "Dubai in general is okay … Al
// Barsha and Villa 15 need to be hidden"). MEASURED that day (anonymity audit B, its policy probe): isDrawingContent
// returned TRUE for "VILLA 15", "UNIT 1204", "373 1234" and a bare Makani "12345 67890", because "villa", "unit" and
// "area" are trade words and a number is content; the CAD preview drew "UNIT 1204" and "373 1234" for a supplier.
// A place below the emirate is now never drawing content: a premises word with its number (villa, plot, unit with a
// 3+ digit number, flat, building, tower, street, road, sector), a phone- or Makani-shaped bare number, and a
// community or landmark by name (the gazetteer). The emirate itself ("DUBAI") still passes.
//
// THE GAZETTEER IS F1's (the anonymity fix round's text-scrubber agent builds one in identity_text.ts). Until it lands
// this file carries the minimal list below. The interface assumed, so the two branches meet without an edit here:
//     export function locationBelowEmirate(text: string): string[]   // the matched spans; [] when none
// When identity_text exports it, it is called FIRST and its answer is unioned with the local rule.
const F1_LOCATION = (identityText as Record<string, unknown>).locationBelowEmirate as ((t: string) => unknown) | undefined;
/** Dubai / UAE communities, districts, roads and landmarks a drawing prints in a site plan, a key plan or an address. */
const GAZETTEER = ['al barsha', 'barsha', 'al quoz', 'quoz', 'umm suqeim', 'suqeim', 'jumeirah', 'jumeira', 'al safa', 'al wasl', 'arabian ranches',
  'dubai hills', 'palm jumeirah', 'emirates hills', 'mirdif', 'al nahda', 'deira', 'bur dubai', 'karama', 'satwa', 'business bay',
  'downtown dubai', 'dubai marina', 'jlt', 'jbr', 'jvc', 'jvt', 'al furjan', 'furjan', 'discovery gardens', 'motor city', 'sports city',
  'silicon oasis', 'international city', 'al warqa', 'warqa', 'al mizhar', 'mizhar', 'khawaneej', 'nad al sheba', 'meydan', 'al barari',
  'damac hills', 'tilal al ghaf', 'the springs', 'the meadows', 'the lakes', 'the greens', 'al sufouh', 'umm al sheif',
  'al manara', 'al twar', 'al qusais', 'qusais', 'muhaisnah', 'hor al anz', 'garhoud', 'port saeed', 'oud metha', 'al jaddaf', 'al khail',
  'tecom', 'abu hail', 'al rashidiya', 'rashidiya', 'nadd al hamar', 'ras al khor', 'al aweer', 'hatta', 'jebel ali', 'al quoz industrial',
  'khalifa city', 'al reem', 'reem island', 'saadiyat', 'yas island', 'al raha', 'mohammed bin zayed city', 'mbz city', 'al khalidiya',
  'al mushrif', 'musaffah', 'mussafah', 'al bateen', 'al majaz', 'al khan', 'al taawun', 'muwaileh', 'al qasimia', 'al nuaimiya',
  'al jurf', 'al rawda', 'al zahia', 'al mamzar', 'al mankhool', 'al hudaiba', 'al jafiliya', 'zabeel', 'al sufouh', 'al thanya',
  'sheikh zayed road', 'szr', 'umm suqeim road', 'umm suqeim rd', 'al khail road', 'hessa street', 'emirates road',
  'mall of the emirates', 'dubai mall', 'burj khalifa', 'burj al arab', 'ibn battuta', 'city walk', 'la mer', 'bluewaters'];
const GAZ_RE = new RegExp(`(?<![A-Za-z])(?:${[...new Set(GAZETTEER)].sort((a, b) => b.length - a.length).map((g) => g.replace(/ /g, '[\\s\\-]*')).join('|')})(?![A-Za-z])`, 'i');
/** A premises / street word with its number: "VILLA 15", "PLOT NO. 345", "STREET 23B", "23B STREET", "UNIT 1204", "TOWER B". */
const PREMISES_NO = /\b(?:VILLA|VILLAS|PLOT|PARCEL|APT|APARTMENT|FLAT|BLDG|BUILDING|TOWER|STREET|ROAD|SECTOR|COMMUNITY|HOUSE|LANE|AVENUE|AVE)\.?\s*(?:NO\.?|NUMBER|#)?\s*[:\-]?\s*(?:\d+[A-Z]?|[A-Z]\d*)\b|\b\d+[A-Z]?\s*(?:STREET|ROAD|LANE|AVENUE)\b|\bUNIT\s*(?:NO\.?|#)?\s*[:\-]?\s*\d{3,}\b/i;
/** A number alone that is shaped like a local phone, a Makani number or a plot number, not like a dimension: "373 1234",
 *  "373-1234", "12345 67890", "04 555 0277". "3000 4500", "1200" and "-1.80" are dimensions and levels and pass. */
const NUMBER_PLACE = /^\s*(?:\d{3}[\s\-]\d{4}|\d{5}\s?\d{5}|\d{2,3}[\s\-]\d{3}[\s\-]\d{4})\s*$/;
/** Arabic place words a site or key plan prints: villa, plot, street, area, community. */
const PLACE_AR = /(?:\u0641\u064a\u0644\u0627|\u0642\u0637\u0639\u0629|\u0642\u0637\u0639\u0647|\u0634\u0627\u0631\u0639|\u0645\u0646\u0637\u0642\u0629|\u0645\u0646\u0637\u0642\u0647|\u062d\u064a|\u0645\u062c\u0645\u0639)\s*(?:\u0631\u0642\u0645\s*)?[\d\u0660-\u0669]|\u0627\u0644\u0628\u0631\u0634\u0627\u0621|\u0627\u0644\u0628\u0631\u0634\u0627|\u0627\u0644\u0642\u0648\u0632|\u0627\u0645\s*\u0633\u0642\u064a\u0645|\u0623\u0645\s*\u0633\u0642\u064a\u0645|\u062c\u0645\u064a\u0631\u0627|\u0645\u0631\u062f\u0641|\u0627\u0644\u0635\u0641\u0627|\u0627\u0644\u0648\u0635\u0644|\u062f\u064a\u0631\u0629|\u0627\u0644\u0643\u0631\u0627\u0645\u0629|\u0627\u0644\u0633\u0637\u0648\u0629/;

/**
 * The place below the emirate that `text` names, or null: a premises word with its number, a phone / Makani / plot
 * shaped bare number, a community or landmark from the gazetteer, an Arabic place. The emirate alone is not a place.
 */
export function drawingLocation(text: string): string | null {
  const t = String(text || '');
  if (!t.trim()) return null;
  if (F1_LOCATION) {
    try { const r = F1_LOCATION(t); if (Array.isArray(r) ? r.length : r) return Array.isArray(r) ? String(r[0]) : 'location'; } catch (_e) { /* the local rule still runs */ }
  }
  const m = t.match(GAZ_RE) || t.match(PREMISES_NO) || t.match(NUMBER_PLACE) || t.match(PLACE_AR);
  return m ? m[0].trim() : null;
}

