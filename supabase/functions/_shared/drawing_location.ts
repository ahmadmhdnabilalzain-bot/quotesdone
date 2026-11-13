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
// PLACES ARE THE UNION OF BOTH LISTS, NEVER A DEFERRAL (second review, item 4, 13 Nov 2026). The text side's rules live in
// _shared/identity_places.ts and reach this file through identity_text.ts. This file used to DEFER to them when they were
// present; MEASURED on the merge with the text branch (405661a36 + ad932e645): ARJAN (on neither list then) and DEIRA /
// JVC (which the text side reads only after a "Location:" cue, which a drawing label never has) stopped being places, 2
// tests failed and v03 was released with "ARJAN". Now a drawing string is a place when EITHER says so:
//   * identity_text.locationBelowEmirate(text, { drawing: true }) when that export exists (the text side's reading for a
//     bare drawing label; until it accepts the option the call is the same as with one argument), else placeSpans;
//   * and ALWAYS the local gazetteer, premises, coordinate, number and Arabic rules below.
type Spans = (t: string) => { s: number; e: number }[];
type Below = (t: string, o?: { drawing?: boolean }) => string[];
const IT = identityText as Record<string, unknown>;
const SHARED_BELOW = typeof IT.locationBelowEmirate === 'function' ? IT.locationBelowEmirate as Below : undefined;
const SHARED_PLACES = typeof IT.placeSpans === 'function' ? IT.placeSpans as Spans : undefined;
/** The text side's answer for one drawing string (first place it names), or null. Never throws. */
function sharedPlace(t: string): string | null {
  try {
    if (SHARED_BELOW) { const r = SHARED_BELOW(t, { drawing: true }); if (Array.isArray(r) && r.length && String(r[0]).trim()) return String(r[0]).trim(); return null; }
    if (SHARED_PLACES) { const r = SHARED_PLACES(t); if (Array.isArray(r) && r.length) return t.slice(r[0].s, r[0].e).trim() || 'place'; }
  } catch (_e) { /* the local rules still run */ }
  return null;
}
/** Dubai / UAE communities, districts, roads and landmarks a drawing prints in a site plan, a key plan or an address. */
const GAZETTEER = ['al barsha', 'barsha', 'al quoz', 'quoz', 'umm suqeim', 'suqeim', 'jumeirah', 'jumeira', 'al safa', 'al wasl', 'arabian ranches',
  'dubai hills', 'palm jumeirah', 'emirates hills', 'mirdif', 'al nahda', 'deira', 'bur dubai', 'karama', 'satwa', 'business bay',
  'downtown dubai', 'dubai marina', 'jlt', 'jbr', 'jvc', 'jvt', 'al furjan', 'furjan', 'discovery gardens', 'motor city', 'sports city',
  'silicon oasis', 'international city', 'al warqa', 'warqa', 'al warqaa', 'warqaa', 'arjan', 'dubailand', 'dubai land', 'al barsha south', 'barsha heights', 'jumeirah village', 'jumeirah park', 'al khawaneej', 'liwan', 'majan', 'town square', 'mudon', 'the valley', 'serena', 'nshama', 'al qudra', 'dubai south', 'al yalayis', 'al mizhar', 'mizhar', 'khawaneej', 'nad al sheba', 'meydan', 'al barari',
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
// HIGH PRECISION ONLY (13 Nov 2026, independent review item 10): "TOWER B", "BUILDING A", "UNIT 1200 W" (a 1200 W unit),
// "HOUSE KEEPING" were withheld as places. Only the words that number a PLOT of land or a dwelling stay: villa, plot,
// parcel, flat / apartment, street, road, and "V-15" (a villa tag). A tower, building or unit name is left to the model
// pass that reads every page (drawing_pixel_gate.ts) and every CAD string (drawing_string_reading.ts).
const PREMISES_NO = /\b(?:VILLA|VILLAS|PLOT|PARCEL|APT|APARTMENT|FLAT)\.?\s*(?:NO\.?|NUMBER|#)?\s*[:\-]?\s*\d+[A-Z]?\b|\b(?:STREET|ROAD)\s*(?:NO\.?|#)?\s*[:\-]?\s*\d+[A-Z]?\b|\b\d+[A-Z]?\s*(?:STREET|ROAD)\b|(?<![A-Za-z0-9])V-\d{1,4}[A-Z]?(?![A-Za-z0-9])/i;
/** Survey and map coordinates: a precise place by its nature (review item 5): "E 492 310.25 N 2 778 104.60" (UTM / Dubai
 *  Local Transverse Mercator grid), "25.1134 N, 55.2006 E", "25.1134, 55.2006" and "25°06'48\"N". */
const COORDS = /\b[EN]\s*[:=]?\s*\d{1,3}(?:[\s,]\d{3}){1,2}(?:\.\d+)?\b[^\n]{0,8}\b[EN]\s*[:=]?\s*\d{1,3}(?:[\s,]\d{3}){1,2}(?:\.\d+)?|\b(?:EASTING|NORTHING)\s*[:=]?\s*\d{3,}|(?<![\d.])(?:2[2-6])\.\d{3,}\s*°?\s*N?\s*[,;\s]\s*(?:5[1-6])\.\d{3,}\s*°?\s*E?(?![\d.])|\b\d{1,3}\s*°\s*\d{1,2}\s*['\u2032]\s*\d{1,2}(?:\.\d+)?\s*["\u2033]?\s*[NE]\b/i;
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
  const m = t.match(GAZ_RE) || t.match(PREMISES_NO) || t.match(COORDS) || t.match(NUMBER_PLACE) || t.match(PLACE_AR);
  if (m) return m[0].trim();
  return sharedPlace(t);
}

