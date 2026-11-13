// drawing_text_policy — WHICH WORDS OF A DRAWING MAY REACH A SUPPLIER. One file, used by the CAD renderer
// (cad_render.ts) and the scan redactor (scan_redact.ts). 24 Sep 2026, sales_engineer; founder instructions
// 32 ("no details at all"), 580, 703.
//
// WHY THE DEFAULT IS INVERTED. The first version withheld a word only when a rule RECOGNISED it as identity: a
// contact pattern, a label, a seed. The independent review of #967 then got these onto a supplier's page with
// our own code: an ATTRIB tagged CLIENT_NAME inside a block called ISO_A1; plain TEXT "ZZ ORBIT ENGINEERING" and
// "ORBIT HOLDINGS"; a dimension override "BY ZZ ORBIT"; "DM LIC 123456"; the customer's name letter-spaced, and
// split one letter per TEXT. Any party no rule names gets through a list of what identity looks like. So the
// list is now of what DRAWING CONTENT looks like: numbers, dimensions, levels, units, codes from a closed list,
// and words of the trade's own vocabulary (drawing_vocabulary.ts). Anything else is withheld. Withholding a label
// a supplier would have liked is a cost; showing a party is a breach.
//
// SECOND REVIEW (25 Sep 2026). Every word of 3 letters or fewer used to pass as "a code", so "DAR", "WSP", "ZZ" +
// "ORB" + "IT" and "<> BY DAR" were drawn; a short word now passes only from the closed list. Seed matching was a
// sliding window over the squashed text, so "ORBITAL" hit the seed "Orbit" and "CEILING HEIGHT" hit "Marina
// Heights"; it now matches whole tokens (several adjacent tokens may run together), after a transliteration fold
// so "RASHEED KARIM" is "Rashid Kareem", and never on a seed word that is itself a trade word.
import { ID_LABEL, ID_TEXT } from './drawing_identity_text.ts';
import { PARTY_TAG } from './cad_identity.ts';
import { tradeOnly, tradeWord } from './drawing_vocabulary.ts';
import { drawingLocation } from './drawing_location.ts';
export { drawingLocation };

/** Company suffixes and firm words, English and Arabic: a text carrying one names a party. */
export const COMPANY = /\b(?:L\.?\s?L\.?\s?C|F\.?Z\.?E|FZ-?LLC|FZCO|EST\.?|ESTABLISHMENT|CO\.|COMPANY|CORP(?:ORATION)?|INC\.?|LTD\.?|LIMITED|GROUP|HOLDINGS?|ENGINEERING|ENGINEERS|CONSULTANTS?|CONSULTING|CONSULTANCY|CONTRACTING|CONTRACTORS?|DEVELOPMENTS?|DEVELOPERS?|REAL\s+ESTATE|PROPERTIES|PROPERTY|ARCHITECTS?|SURVEYORS?|SURVEYING|INTERIORS|ASSOCIATES|PARTNERS|TRADING|INDUSTRIES|ENTERPRISES?|SERVICES)\b|\u0630\.?\s?\u0645\.?\s?\u0645|\u0645\u0624\u0633\u0633\u0629|\u0634\u0631\u0643\u0629|\u0645\u0643\u062a\u0628\s+\u0647\u0646\u062f\u0633\u064a|\u0644\u0644\u0645\u0642\u0627\u0648\u0644\u0627\u062a|\u0644\u0644\u0627\u0633\u062a\u0634\u0627\u0631\u0627\u062a|\u0627\u0644\u0639\u0642\u0627\u0631\u064a\u0629/i;
/** A licence, permit, registration, plot, Makani, TRN, PO box or DM number: letters then digits. */
export const LICENCE = /\b(?:LIC(?:EN[CS]E)?|TRADE\s+LIC|DM|DEWA|RERA|TRN|VAT|PERMIT|PLOT|PARCEL|MAKANI|P\.?\s?O\.?\s?BOX|POB|CR|REG(?:ISTRATION)?|PROJECT|JOB|DWG|DRG|DRAWING)\.?\s*(?:NO\.?|NUMBER|#|:)?\s*[A-Z]{0,3}[-\s]?\d{3,}/i;
/** An ATTRIB tag of a party, the job or the sheet: every value of an INSERT carrying one is withheld. */
export const PARTY_TAG_WIDE = /(?:^|_)(?:NAME|TITLE|CLIENT|OWNER|CONSULT\w*|CONTRACT\w*|ARCHITECT\w*|ENGINEER\w*|PROJ\w*|DWG\w*|DRG\w*|DRAWING\w*|JOB\w*|SITE|LOCATION|ADDR\w*|PLOT|MAKANI|COMPANY|FIRM|DRAWN|DRN|CHECK\w*|CHK|APPROV\w*|DESIGN\w*|PHONE|TEL|FAX|E?MAIL|WEB\w*|LIC\w*|PERMIT|TRN|DEVELOPER|EMPLOYER|CUSTOMER|SIGN\w*|STAMP|SEAL|REV\w*|DATE|SCALE|SHEET\w*|ISSUE\w*|PREPARED|REVIEWED)(?:_|$|\d)/i;
export const partyTag = (tag: string) => !!tag && (PARTY_TAG.test(tag) || PARTY_TAG_WIDE.test(tag));

// Instructions that name a party ROLE, not a party: "CONTRACTOR TO VERIFY ON SITE", "THE CONTRACTOR SHALL ...".
// Taken out before the company / label rules read the text, so the rest of the note is judged on its own words.
const INSTRUCTION = /\b(?:THE\s+)?(?:MAIN\s+|MEP\s+|ELECTRICAL\s+|MECHANICAL\s+)?(?:SUB-?)?CONTRACTORS?\s+(?:TO|SHALL|MUST|IS\s+TO|ARE\s+TO)\b/gi;
/** A party label ("CLIENT:", "Drawn by", "TEL") whose value sits beside or under it; an instruction is not one. */
export const partyLabel = (text: string) => ID_LABEL.test(String(text || '').replace(INSTRUCTION, ' '));
// Latin letters, digits, punctuation and the few symbols a drawing prints (degree, plus-minus, squared, cubed,
// times, the diameter sign, dashes, primes). Any other letter is withheld: an accented "ORBÍT" is a name.
const FOREIGN = /[^\x00-\x7F\u00b0\u00b1\u00b2\u00b3\u00d7\u00d8\u00f8\u2013\u2014\u2019\u2032\u2033\u2300]/;

// An e-mail or web address, whole or in part ("al@", "@kx"). A digit either side of "@" is not: OCR reads the
// "0" of "101" as "@" (measured 25 Sep 2026 on the ZZ scan: "OFFICE 1@1" at 86).
const MAILISH = /[A-Za-z]@|@[A-Za-z]|www\.|https?:/i;

/** One token of a drawing's text: a number, a size or code with digits (13A, 600X600, CAT6, DB01), or a trade word. */
function tokenOk(w: string): boolean {
  if (/^\d+$/.test(w)) return true;
  if (/\d/.test(w)) return /^\d+(?:X\d+)*[A-Z]{0,4}\d*$/i.test(w) || /^[A-Z]{1,4}\d+[A-Z]?$/i.test(w);
  return tradeWord(w);
}

/**
 * THE VOCABULARY GATE, kept for the one reader no model checks: the OCR scan route on the CAD worker
 * (scan_redact.ts), where an unread word cannot be shown to a model. Everywhere else see isDrawingContent below.
 * True when a text reads as drawing content a supplier needs; false means withhold it. FAIL CLOSED: anything
 * carrying a company word, a licence number, a contact or a party label is not content; nor is Arabic (not in
 * the vocabulary yet), any other non-Latin letter, letter-spaced text, or a lone letter (a name split one glyph
 * per TEXT). Otherwise EVERY token must be a number, a size or device code, or a trade word; a short word passes
 * only if it is in the closed list (drawing_vocabulary CODES) - "DAR", "WSP", "ORB" do not.
 */
export function isVocabularyContent(text: string): boolean {
  const t0 = String(text || '').replace(/\s+/g, ' ').trim();
  if (!t0) return false;
  const t = t0.replace(INSTRUCTION, ' ').replace(/\s+/g, ' ').trim();
  if (!t) return true;
  if (COMPANY.test(t) || LICENCE.test(t) || ID_TEXT.test(t) || ID_LABEL.test(t)) return false;
  if (drawingLocation(t0)) return false;                              // a place below the emirate (ruling 1683)
  if (/[\u0600-\u06ff]/.test(t) || FOREIGN.test(t) || MAILISH.test(t)) return false;
  if (/(?:\b\p{L}\b[\s.\-]*){4,}/u.test(t)) return false;          // letter-spaced text
  // A device tag written with a dash ("P-1", "MD-1", "UWL-3") is one code, as "P1" is (13 Nov 2026: the B1 schedule's tags).
  const toks = t.replace(/\b([A-Za-z]{1,4})-(\d{1,3}[A-Za-z]?)\b/g, '$1$2').split(/[^A-Za-z0-9]+/).filter(Boolean);
  if (!toks.length) return !/[@#]/.test(t);                          // bare punctuation: "<>", "-", "="
  if (toks.length === 1 && /^[A-Za-z]$/.test(toks[0])) return false; // a lone letter
  return toks.every(tokenOk);
}

/**
 * THE CODE FLOOR'S RULE (13 Nov 2026, coordinator's design change C, independent review item 10): false only when
 * code can PROVE the text names a party or a place below the emirate - a company word, a licence number, a contact, a
 * party label, a villa / plot / street number, coordinates, a phone- or Makani-shaped number, a gazetteer place, an
 * e-mail fragment, letter-spaced text. A word the vocabulary does not know is no longer withheld for that alone: that
 * cost the CAD file 25 of 83 quoting strings ("BS 7671", "IEC 61439", "LOAD SCHEDULE", "TOTAL CONNECTED LOAD 45.6 KW",
 * "FLAT ROOF", "TOWER CRANE", "PAINT JOTUN FENOMASTIC", "N"). What only a reader can tell - a name with no company word,
 * a community no list knows - is read by a model: every CAD string (drawing_string_reading.ts) and every page's pixels
 * (drawing_pixel_gate.ts).
 */
export function isDrawingContent(text: string): boolean {
  const t0 = String(text || '').replace(/\s+/g, ' ').trim();
  if (!t0) return false;
  const t = t0.replace(INSTRUCTION, ' ').replace(/\s+/g, ' ').trim();
  if (!t) return true;
  if (COMPANY.test(t) || LICENCE.test(t) || ID_TEXT.test(t)) return false;
  // A party label is identity when it LABELS something ("PLOT NO: 345", "OWNER MR X"); a label word inside a phrase of
  // the trade's own words is not ("PLOT BOUNDARY", "PROJECT NORTH"): review item 10 lost "PLOT BOUNDARY" to it.
  const lm = ID_LABEL.exec(t);
  if (lm) { if (lm[1]) return false; const rest = (t.slice(0, lm.index) + ' ' + t.slice(lm.index + lm[0].length)).trim(); if (rest ? (/[:#]/.test(t) || !tradeOnly(rest)) : /[:#]\s*\S/.test(t)) return false; }
  if (drawingLocation(t0)) return false;
  if (MAILISH.test(t) || /\b[A-Za-z0-9-]{2,}\.(?:ae|com|net|org|co|io)\b/i.test(t)) return false;   // an address or a domain
  if (/(?:\b\p{L}\b[\s.\-]*){4,}/u.test(t)) return false;          // letter-spaced text
  return true;
}

/** Letters and digits only, lower case: "Z Z  D-E-M-O" -> "zzdemo". */
export const squash = (s: string) => String(s || '').toLowerCase().normalize('NFKD').replace(/[^a-z0-9\u0600-\u06ff]/g, '');

/** Company words that give a party away even with every space removed ("ZZORBITENGINEERING"). */
export const SQUASHED_COMPANY = /engineering|engineers|consultan|consulting|contracting|holdings|properties|developers|developments|architects|surveyors|interiors|associates|partners|trading|industries|enterprise|establishment|corporation|limited|fzllc|fzco/;

/** A company word (also with the spaces squashed out), a licence number or a contact, in a text read as it stands
 *  or with its runs joined; an instruction to the contractor is not a party. */
export const namesParty = (text: string) => {
  const t = String(text || '').replace(INSTRUCTION, ' ');
  return COMPANY.test(t) || LICENCE.test(t) || ID_TEXT.test(t) || SQUASHED_COMPANY.test(squash(t)) || !!drawingLocation(t);
};

// Transliteration fold: the same Arabic name in the spellings a drawing, an OCR and a customer use. "Rashid Kareem",
// "RASHEED KARIM" and "Rasheed Qarim" fold alike. Digits standing for letters inside a word (0RB1T) fold too.
const LEET: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b' };
export function fold(w: string): string {
  let s = String(w || '').toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/g, '');
  if (/[a-z]/.test(s) && /\d/.test(s)) s = s.replace(/[0134578]/g, (d) => LEET[d]);
  return s.replace(/kh/g, 'k').replace(/q/g, 'k').replace(/ck/g, 'k').replace(/ph/g, 'f').replace(/ee|ea|ie|ei|iy/g, 'i')
    .replace(/ou|oo|uu/g, 'u').replace(/aa/g, 'a').replace(/([aeiou])h$/, '$1').replace(/(.)\1+/g, '$1');
}

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
 * Does `text` (one run, or a line of runs joined) carry a seed term? WHOLE TOKENS only, where a token may be
 * several adjacent tokens run together (a letter-spaced "K A R E E M", a name split "ORB" + "IT", "RASHIDKAREM").
 * After the transliteration fold a token matches a seed word exactly, or within 1 edit for a seed word of 5
 * letters and 2 from 6, with the same first letter. A seed word that is itself a trade word ("kitchens",
 * "heights") is never matched on its own; the whole seed phrase still is. Digit seeds (a phone, a plot number)
 * match inside the text's digits with every separator removed.
 */
export function seedHit(text: string, seeds: string[]): string | null {
  const raw = String(text || '');
  const digits = raw.replace(/\D/g, '');
  const toks = raw.split(/[^\p{L}\p{N}]+/u).filter(Boolean).map(fold).filter(Boolean);
  const words: { seed: string; f: string; n: number }[] = [];
  for (const seed of seeds) {
    const q = String(seed || '').trim();
    if (!q) continue;
    const bare = q.replace(/[\s\-+().]/g, '');
    if (/^\d+$/.test(bare)) { if (bare.length >= 5 && digits.includes(bare)) return seed; continue; }
    const parts = q.split(/\s+/).filter(Boolean);
    const whole = fold(parts.join(''));
    if (parts.length > 1 && whole.length >= 5) words.push({ seed, f: whole, n: whole.length });
    for (const p of parts) {
      const f = fold(p);
      if (f.length < 4 || /^\d+$/.test(f) || tradeWord(p)) continue;
      words.push({ seed, f, n: p.replace(/[^\p{L}\p{N}]/gu, '').length });
    }
  }
  if (!words.length || !toks.length) return null;
  const maxLen = Math.max(...words.map((w) => w.f.length)) + 2;
  for (let i = 0; i < toks.length; i++) {
    let cand = '';
    for (let j = i; j < toks.length; j++) {
      cand += toks[j];
      if (cand.length > maxLen) break;
      for (const w of words) {
        if (cand === w.f) return w.seed;
        const k = w.n >= 6 ? 2 : w.n === 5 ? 1 : 0;
        // Two edits only between words that begin AND end alike (MUHAMMAD / Mohammed), so MANSARD is not Mansoori.
        if (k && cand[0] === w.f[0] && (k === 1 || cand[cand.length - 1] === w.f[w.f.length - 1]) && editWithin(cand, w.f, k)) return w.seed;
      }
    }
  }
  return null;
}
