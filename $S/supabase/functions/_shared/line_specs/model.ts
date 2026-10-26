// line_specs/model.ts — what every line of a quotation must state, per trade, in English and Arabic.
//
// THE RULE (founder, 14 Sep 2026, verbatim in public.founder_instruction #78): "in fitout quotation
// for example, we need to make sure that exact specs of the material used, what type of wood, what
// thickness, etc. this is a rule, and if a supplier submits missing information, then the sales agent
// will notify him that the quotation will be on hold until he mentions the exact details".
//
// WHAT THIS IS. One catalogue (catalogue.json beside this file), keyed by the trade vocabulary the
// database's spec groups use, of LINE-level attributes: code, EN and AR label, type and unit, mandatory or
// trade-specific extra, the suggested values the portal lists, and `conditional` for an attribute that is
// asked only of some kinds of line (a ceiling TILE has a size and no stud frame).
//
// WHAT CHANGED, 23 Sep 2026 (founder_instruction 886-903, ledger 890: no word matching anywhere;
// decision point 29 line_specs.vague). This file used to READ the supplier's words: a regex + lexicon
// reader per attribute, a keyword pattern per trade deciding which trade a line is (tradeOfLine), a
// NON_MATERIAL pattern deciding which lines carry no material, a VAGUE pattern deciding which values
// are not specifications, a category regex deciding a quote's trade, and applies/except patterns
// deciding which attributes a line is asked. Every one of those decided MEANING by spotting words.
// They are gone. What a line states, which trade it is, whether it carries material, whether a
// conditional attribute applies and whether a value is exact is now READ BY REASONING
// (supabase/functions/_shared/reasoned_matching.ts readQuote, think() with the supplier's own words as
// evidence) or STATED BY THE SUPPLIER in the portal's keyed fields. Under the model hold nothing is read,
// so every required detail is asked of the supplier and the quote is held — never a guess.
// A quote's trade comes from its category by an EXACT map (measured 23 Sep 2026 from the regex it
// replaces); installApplies / warrantyApplies had no caller and are removed with their word rules.
import { BRANDED_GOODS, NO_LINE_SPECS_YET, SAME_AS } from './taxonomy_trades.ts';
import CATALOGUE from './catalogue.json' with { type: 'json' };
// Kept only for supplier_api/quote_review.ts and line_specs/derive.ts (decision points 31 and 36, another batch).
export { VAGUE } from './legacy_word_readers.ts';

export type AttrType = 'text' | 'number';
export type Attr = {
  code: string; en: string; ar: string; type: AttrType;
  unit?: string; unit_ar?: string; mandatory: boolean;
  /** Suggested values for the portal's list; any exact value is accepted. */
  options?: string[];
  /** Asked only of the kinds of line it applies to; the reading says when it does not (a "not applicable" with the words that show it). */
  conditional?: boolean;
};
export type Trade = { code: string; en: string; ar: string; attrs: Attr[] };

/** Arabic-Indic digits to Western, the Arabic decimal mark to '.', whitespace collapsed. Format only. */
const AR_DIGITS = /[٠-٩]/g;
export const normText = (s: string) => String(s ?? '').replace(AR_DIGITS, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[٫]/g, '.').replace(/\s+/g, ' ').trim();

export const TRADES: Record<string, Trade> = Object.fromEntries((CATALOGUE as Trade[]).map((t) => [t.code, t]));

// Trades whose quotes mix many kinds of line. Each LINE of such a quote is the trade the reading finds it
// to be (a fit-out's wardrobe line is joinery, its ceiling line is gypsum), among the trades below.
export const COMPOSITE = new Set(['fitout', 'mep', 'general', 'interiordesign', 'handyman']);
const LINE_TRADES = ['hvac', 'elevators', 'generators', 'solar', 'fire', 'security', 'networking', 'avsystems', 'smarthome', 'electrical', 'plumbing',
  'glazing', 'joinery', 'gypsum', 'tiling', 'flooring', 'carpet', 'wallpaper', 'painting', 'waterproofing', 'insulation', 'roofing', 'concrete',
  'masonry', 'steel', 'signage', 'acrylic', 'upholstery', 'shutters', 'shade', 'landscaping', 'pools'];
const MEP_TRADES = ['hvac', 'fire', 'electrical', 'plumbing', 'generators', 'networking', 'security', 'insulation'];
/** The trades one line of a quote may be: the quote's own, or for a composite the trades its lines can name. */
export function lineTradeOptions(quoteTrade: string): string[] {
  if (COMPOSITE.has(quoteTrade)) return quoteTrade === 'mep' ? MEP_TRADES : LINE_TRADES;
  return TRADES[quoteTrade] ? [quoteTrade] : [];
}

// THE CATEGORY -> TRADE MAP, EXACT. Measured 23 Sep 2026: the category regex this replaces, run over the 56
// category_specs slugs, the 54 site categories and the 195 taxonomy codes. Only the keys that are not already
// a trade code of their own are listed; safety_equipment (PPE) is deliberately NOT fire (the regex read the
// word "safety"). Anything not listed and not a trade is 'general'.
const CATEGORY_TRADE: Readonly<Record<string, string>> = {
  'aluminium': 'glazing', 'av-systems': 'avsystems', 'blinds-curtains': 'upholstery', 'carpentry': 'joinery', 'carpentry-joinery': 'joinery',
  'carpets': 'carpet', 'combined-mep': 'mep', 'commercial-retail-fitout': 'fitout', 'custom-furniture': 'joinery',
  'engineering-and-architectural-consultancies': 'consultancy', 'engineering_consultancy': 'consultancy', 'epoxy-flooring': 'flooring',
  'facade-cleaning': 'facade', 'fire_fighting': 'fire', 'garage-doors': 'shutters', 'glass': 'glazing', 'home_automation': 'smarthome',
  'interior-design': 'interiordesign', 'interior_fitout': 'fitout', 'it-networking': 'networking', 'job-shop-manufacturing': 'manufacturing',
  'kitchens': 'joinery', 'logistics_moving': 'movers', 'marble-granite': 'tiling', 'mep_general': 'mep', 'pest': 'pestcontrol',
  'power_generators': 'generators', 'safety': 'fire', 'security_systems': 'security', 'smart-home': 'smarthome',
  'structural-steel-fabrication': 'steel', 'swimming-pools': 'pools', 'tents-and-shade-structures': 'shade', 'water-tank-cleaning': 'watertank',
};

/** The trade of a quote, from its category key — an exact lookup, never a pattern. */
export function tradeOfCategory(category: string | null | undefined): string {
  const c = String(category ?? '').trim().toLowerCase();
  if (SAME_AS[c]) return SAME_AS[c];
  if (BRANDED_GOODS.has(c)) return 'branded_goods';
  if (NO_LINE_SPECS_YET.has(c)) return c;
  if (CATEGORY_TRADE[c]) return CATEGORY_TRADE[c];
  if (TRADES[c] || COMPOSITE.has(c)) return c;
  return 'general';
}

/** Every attribute of a trade; which conditional ones a line is NOT asked is the reading's call. */
export function attrsOf(trade: string | null | undefined): Attr[] {
  return trade && TRADES[trade] ? TRADES[trade].attrs : [];
}
