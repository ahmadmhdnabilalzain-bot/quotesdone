// drawing_text_policy — WHICH WORDS OF A DRAWING MAY REACH A SUPPLIER. One file, used by the CAD renderer
// (cad_render.ts) and the scan redactor (scan_redact.ts). 24 Sep 2026, sales_engineer; founder instructions
// 32 ("no details at all"), 580, 703.
//
// WHY THE DEFAULT IS INVERTED. The first version withheld a word only when a rule RECOGNISED it as identity: a
// contact pattern, a label, a seed. The independent review of #967 then got these onto a supplier's page with
// our own code: an ATTRIB tagged CLIENT_NAME inside a block called ISO_A1; plain TEXT "ZZ ORBIT ENGINEERING" and
// "ORBIT HOLDINGS"; a dimension override "BY ZZ ORBIT"; "DM LIC 123456"; the customer's name letter-spaced, and
// split one letter per TEXT. Any party no rule names gets through a list of what identity looks like. So the
// list is now of what DRAWING CONTENT looks like: numbers, dimensions, levels, units, short tags and codes, and
// words of the trade's own vocabulary (rooms, elements, devices, the words notes are written in). Anything else
// is withheld. Withholding a label a supplier would have liked is a cost; showing a party is a breach.
//
// And a party that hides in the SPACING is caught by squashing: text runs on the same line are joined, every
// space and punctuation mark is removed, and the result is looked for against the seed terms, exactly and with
// an edit distance of up to 2 (OCR and letter-spacing both shift a letter or two).
import { ID_LABEL, ID_TEXT } from './drawing_identity_text.ts';
import { PARTY_TAG, VOCAB } from './cad_identity.ts';

/** Company suffixes and firm words, English and Arabic: a text carrying one names a party. */
export const COMPANY = /\b(?:L\.?\s?L\.?\s?C|F\.?Z\.?E|FZ-?LLC|FZCO|EST\.?|ESTABLISHMENT|CO\.|COMPANY|CORP(?:ORATION)?|INC\.?|LTD\.?|LIMITED|GROUP|HOLDINGS?|ENGINEERING|ENGINEERS|CONSULTANTS?|CONSULTING|CONSULTANCY|CONTRACTING|CONTRACTORS?|DEVELOPMENTS?|DEVELOPERS?|REAL\s+ESTATE|PROPERTIES|PROPERTY|ARCHITECTS?|INTERIORS|ASSOCIATES|PARTNERS|TRADING|INDUSTRIES|ENTERPRISES?|SERVICES)\b|\u0630\.?\s?\u0645\.?\s?\u0645|\u0645\u0624\u0633\u0633\u0629|\u0634\u0631\u0643\u0629|\u0645\u0643\u062a\u0628\s+\u0647\u0646\u062f\u0633\u064a|\u0644\u0644\u0645\u0642\u0627\u0648\u0644\u0627\u062a|\u0644\u0644\u0627\u0633\u062a\u0634\u0627\u0631\u0627\u062a|\u0627\u0644\u0639\u0642\u0627\u0631\u064a\u0629/i;
/** A licence, permit, registration, plot, Makani, TRN, PO box or DM number: letters then digits. */
export const LICENCE = /\b(?:LIC(?:EN[CS]E)?|TRADE\s+LIC|DM|DEWA|RERA|TRN|VAT|PERMIT|PLOT|PARCEL|MAKANI|P\.?\s?O\.?\s?BOX|POB|CR|REG(?:ISTRATION)?|PROJECT|JOB|DWG|DRG|DRAWING)\.?\s*(?:NO\.?|NUMBER|#|:)?\s*[A-Z]{0,3}[-\s]?\d{3,}/i;
/** An ATTRIB tag of a party, the job or the sheet: every value of an INSERT carrying one is withheld. */
export const PARTY_TAG_WIDE = /(?:^|_)(?:NAME|TITLE|CLIENT|OWNER|CONSULT\w*|CONTRACT\w*|ARCHITECT\w*|ENGINEER\w*|PROJ\w*|DWG\w*|DRG\w*|DRAWING\w*|JOB\w*|SITE|LOCATION|ADDR\w*|PLOT|MAKANI|COMPANY|FIRM|DRAWN|DRN|CHECK\w*|CHK|APPROV\w*|DESIGN\w*|PHONE|TEL|FAX|E?MAIL|WEB\w*|LIC\w*|PERMIT|TRN|DEVELOPER|EMPLOYER|CUSTOMER|SIGN\w*|STAMP|SEAL|REV\w*|DATE|SCALE|SHEET\w*|ISSUE\w*|PREPARED|REVIEWED)(?:_|$|\d)/i;
export const partyTag = (tag: string) => !!tag && (PARTY_TAG.test(tag) || PARTY_TAG_WIDE.test(tag));

// The trade's own words, beyond cad_identity's layer vocabulary: rooms, drawing furniture, devices and the small
// words notes are written in. Plurals are folded (a trailing S / ES) before the lookup.
const MORE = `
  a an the of to at in on by for and or with from as per not no all any each every only other same see refer note notes
  general typical typ unless otherwise stated shown indicated noted mounted installed provide provided fixed mount
  above below over under between near top bottom side left right front back center centre high low level levels
  new existing remove relocate retain future proposed approx approximately min max minimum maximum
  office meeting room store storage lobby reception corridor hall hallway kitchen pantry toilet toilets bathroom bath
  bedroom master guest living dining majlis maid maids laundry utility electrical mechanical plant riser shaft stair
  stairs staircase lift lifts balcony terrace roof garage parking entrance exit foyer dressing closet study library
  gym pool prayer server it telecom janitor cleaner lounge waiting conference board boardroom open plan area zone
  plan section elevation detail details schedule legend key scale drawing sheet layout ground first second third
  fourth fifth floor floors basement mezzanine podium typical north south east west part
  smoke heat detector detectors sounder beacon strobe call point panel socket sockets outlet outlets double single
  twin switch switches isolator fused spur light lighting luminaire downlight emergency exit sign fan coil unit units
  supply return exhaust extract fresh air grille diffuser damper duct ducts pipe pipes valve drain gully trap sprinkler
  hose reel extinguisher cabinet data telephone tv cctv camera access card reader speaker intercom meter distribution
  board db mdb smdb cable tray trunking conduit containment earth bonding lightning protection
  wall walls door doors window windows glazing partition ceiling floor finish tile tiles paint skirting column columns
  beam slab opening void dim dimension dimensions height width length depth thickness dia diameter radius
  mm cm m sqm kw kva amp amps volt volts watt watts lux cfm lps nos no qty quantity each set lot
  affl ffl ssl fcl tos bos cl sfl rl fgl ngl datum
`.split(/\s+/).filter(Boolean);
const WORDS = new Set([...VOCAB, ...MORE].map((w) => w.toLowerCase()));
const known = (w: string) => {
  const l = w.toLowerCase();
  return WORDS.has(l) || WORDS.has(l.replace(/es$/, '')) || WORDS.has(l.replace(/s$/, ''));
};

const NUMERIC = /^[\d\s.,:;x×\/'"\-+±Ø°%=()@#~]*\d[\d\s.,:;x×\/'"\-+±Ø°%=()@#~]*(?:\s*(?:mm|cm|m|m2|m²|sqm|kw|kva|a|v|w|lux|l\/s|cfm|lps|nos?|dia|ffl|affl|ssl|fcl|typ|thk)\.?)*\s*$/i;

/**
 * True when a text reads as drawing content a supplier needs; false means withhold it. Rules, in order:
 * anything carrying a company word, a licence number, a contact or a party label is not content; numbers and
 * dimensions are; letter-spaced text (4+ single letters in a row) is not; otherwise every word of 4+ letters must
 * be the trade's vocabulary (words of 1-3 letters are codes and tags: SD, SKT, FCU, DB).
 */
export function isDrawingContent(text: string): boolean {
  const t = String(text || '').replace(/\s+/g, ' ').trim();
  if (!t) return false;
  if (COMPANY.test(t) || LICENCE.test(t) || ID_TEXT.test(t) || ID_LABEL.test(t)) return false;
  if (NUMERIC.test(t)) return true;
  if (/[\u0600-\u06ff]/.test(t)) return false;                 // Arabic words are not in the vocabulary yet: withheld
  if (/(?:\b\p{L}\b[\s.\-]*){4,}/u.test(t)) return false;        // letter-spaced text
  const words = t.split(/[^A-Za-z]+/).filter(Boolean);
  return words.every((w) => w.length <= 3 || known(w));
}

/** Letters and digits only, lower case: "Z Z  D-E-M-O" -> "zzdemo". */
export const squash = (s: string) => String(s || '').toLowerCase().normalize('NFKD').replace(/[^a-z0-9\u0600-\u06ff]/g, '');

function editWithin(a: string, b: string, k: number): boolean {
  if (Math.abs(a.length - b.length) > k) return false;
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let best = i;
    for (let j = 1; j <= b.length; j++) { cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)); best = Math.min(best, cur[j]); }
    if (best > k) return false;
    prev = cur;
  }
  return prev[b.length] <= k;
}

/**
 * Does `text` (a line, or several runs joined) carry any seed term? Squashed containment for every seed of 4+
 * characters, and an edit distance of at most 2 between each seed token of 5+ characters and every window of
 * the squashed text of about the same length - 1 edit for a token of 5-6 letters, 2 from 7 - so OCR's "KAREFM"
 * and a letter-spaced "K A R E E M" both hit.
 */
export function seedHit(text: string, seeds: string[]): string | null {
  const s = squash(text);
  if (!s) return null;
  for (const seed of seeds) {
    const q = squash(seed);
    if (q.length >= 4 && s.includes(q)) return seed;
  }
  for (const seed of seeds) for (const tok of String(seed).split(/\s+/)) {
    const q = squash(tok);
    if (q.length < 5 || /^\d+$/.test(q)) continue;
    for (let i = 0; i + q.length - 2 <= s.length; i++) {
      for (const len of [q.length - 1, q.length, q.length + 1]) {
        if (len < 4 || i + len > s.length) continue;
        if (editWithin(s.slice(i, i + len), q, q.length >= 7 ? 2 : 1)) return seed;
      }
    }
  }
  return null;
}
