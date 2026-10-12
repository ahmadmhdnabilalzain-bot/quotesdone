// A CATALOGUE IS READ AS A CATALOGUE — no model. Seat: sales_engineer. 21 Sep 2026.
//
// MEASURED 21 Sep 2026 on a real importer-wholesaler's 7-page product catalogue (laptops, printers,
// photocopiers, toners, projectors, UPS, POS terminals, CCTV kits, cables), run through the platform's
// own deterministic path:
//   * the Services rewrite read only the first 2,000 characters of 12,029 — the company blurb;
//   * read whole, the matcher took the side-by-side spec tables as statements: "DVR Storage Upto 6TB"
//     named Storage & warehousing, a UPS's "Power Indicator LED Light" named Lighting, and "protect
//     your electric gadgets" named the Electrical trade;
//   * UPS (17 mentions), printers, photocopiers, toners, desktops and POS named nothing;
//   * "importer, exporter and wholesaler" meant nothing, so it was proposed Network installation and
//     Structured cabling for cable it sells, and the implication map added intruder alarms from CCTV.
//
// WHAT THIS DOES. One reader used by both the catalogue upload (supplier_doc_trades.readDocForTrades,
// called by supplier_catalog_ingest, which takes its line sort and supply-only test and proposes TRADES by exact
// code or meaning only, trade_resolve.ts) and the Services tab's catalogue input (supplier_services.
// servicesRewrite with from_catalogue). It reads the WHOLE text and sorts every line:
//   spec row   a table row of values — a measurement (690VA, 6TB, 3.6 MM), a model number (PM-UPS690,
//              CF400A), a bare Yes/No cell, a "Model No" label, or the same label repeated across
//              side-by-side columns ("Color Grey Color Grey"). DROPPED before matching: a word inside a
//              spec row describes a product the company sells, it does not name a service it performs.
//              The one thing kept from a spec row is the value of its "Type" cell ("Type Receipt
//              Printer" -> "Receipt Printer"), because that value IS a product-type line.
//   contact    an address, phone, e-mail, web or legal-entity line (LLC, FZE). Dropped from matching:
//              "PREVIEW GENERAL TRADING LLC (Warehouse)" is where the company keeps stock, not a
//              warehousing service.
//   statement  a sentence about the company — it speaks in the first or second person ("we", "our",
//              "your") or runs past MAX_HEADING_WORDS. Not matched for services ("protect your electric
//              gadgets" is marketing), but read for supply-only (below).
//   heading    everything else: headings and product-type lines. These, plus the Type values, are
//              what the rewrite matches.
// SUPPLY ONLY. Words that say the company trades in goods — importer, wholesaler, distributor,
// stockist, trading, reseller (and the Arabic equivalents) — with NO installation or contracting word
// anywhere in its statements and headings mark it supply-only. Spec rows are not read for this: a
// battery's "Sealed Maintenance Free" is a product property, not an offer to maintain. The flag is a
// PROPOSAL shown to the supplier ("supply only — confirm"), never a verdict: the supplier can say it
// also installs, and the rewrite runs again without it.
import { foldForMatch, termPattern } from './alias_pattern.ts';
import { finishRewrite, rewriteServices, tidy, type Rewrite, type ServiceTerm } from './service_rewrite.ts';

// Bounded, not merely large: at most CATALOGUE_MAX_LINES lines, each short once spec rows are gone. Since
// 29 Sep 2026 (decision point 93) the rewrite names a service only by an exact name; the rest is meaning's.
export const CATALOGUE_MAX_TEXT = 80_000;
export const CATALOGUE_MAX_LINES = 400;
export const MAX_HEADING_WORDS = 8;

const UNIT = /(?<![\p{L}\p{N}])\d+(?:[.,]\d+)?\s?(?:k?va|k?w|v|hz|tb|gb|mb|mp|mm|cm|m|inch|ppm|dpi|mah|ah|pcs|fps|ms|db|lm|kg|g)(?![\p{L}])/iu;
// A model number: letters and digits in one token, with a hyphen (PM-UPS690, RS-232) or not (CF400A,
// M251n, RJ45). A word with no digit ("Wi-Fi") is not one; neither is a year or a bare number.
const MODEL = /(?<![\p{L}\p{N}])(?=[\p{L}\p{N}-]*\p{L})(?=[\p{L}\p{N}-]*\d)[\p{L}\p{N}]+(?:-[\p{L}\p{N}]+)*(?![\p{L}\p{N}])/u;
const YES_NO = /(?<![\p{L}])(?:yes|no|n\/a|نعم|لا)(?![\p{L}])\s*$|(?<![\p{L}])(?:yes|no)(?![\p{L}.:])(?=\s+\p{Lu})/u;
const MODEL_LABEL = /\bmodel\s*(?:no|number|#)|رقم\s*الموديل|موديل\s*رقم/i;
const CONTACT = /\b(?:tel|fax|mob|mobile|phone|p\.?\s?o\.?\s?box|e-?mail|l\.?l\.?c|fze|fzco|fz-llc|dmcc)\b|@|www\.|https?:|هاتف|فاكس|ص\s?\.?\s?ب|ذ\s?\.?\s?م\s?\.?\s?م|بريد/i;
const ADDRESS = /\b(?:bldg|building|road|street|st|floor|shops?|office|warehouse|plot|area|zone)\b/i;
/** An address, phone, e-mail, web or legal-entity line ("ZZ DEMO Falcon Cleaning LLC"): it says who and where, never
 *  what the company does. trade_resolve.tradesOfText drops it too (12 Oct 2026). */
export const isContactLine = (line: string): boolean => CONTACT.test(line) || (/\d/.test(line) && ADDRESS.test(line));
const PERSON =/(?<![\p{L}])(?:we|our|ours|us|you|your|yours|they|their|i|it's|نحن|لدينا|نقدم|نقوم|نوفر|لكم|لك)(?![\p{L}])/iu;
const TYPE_CELL = /(?<![\p{L}])(?:type|النوع)\s+(.+?)(?=\s+(?:type|النوع|model|features?|functions?|capacity|sizes?|colou?r|speed|display|compatible|input|output|lens|package)\b|$)/giu;
const TYPE_LABEL = /^(?:type|النوع)\s+\S/iu;   // a row that starts with a "Type" cell is a table row

export type CatalogueLines = { headings: string[]; types: string[]; statements: string[]; spec_rows: number; contact_rows: number };

const isSpecRow = (line: string): boolean => {
  if (UNIT.test(line) || MODEL_LABEL.test(line) || YES_NO.test(line) || TYPE_LABEL.test(line)) return true;
  const words = line.split(/\s+/).filter(Boolean);
  if (words.length >= 3 && MODEL.test(line)) return true;
  // Side-by-side columns: a label repeated across the row ("Type X Type X", "Color Grey Color Grey").
  const labels = words.filter((w) => /^\p{L}[\p{L}-]{2,}$/u.test(w)).map((w) => w.toLowerCase());
  return words.length >= 4 && labels.some((w, i) => labels.indexOf(w) !== i && !['and', 'the', 'for', 'with'].includes(w));
};

/** The value of each "Type" cell in a spec row, up to the next label or value, at most five words. */
function typeValues(line: string): string[] {
  const out: string[] = [];
  for (const m of line.matchAll(TYPE_CELL)) {
    const words: string[] = [];
    for (const w of m[1].split(/\s+/)) {
      // A short number stays ("Cat 6 Cable"); a model number, a value or the next cell ends the type.
      if (!w || /:/.test(w) || (/\d/.test(w) && !/^\d{1,2}$/.test(w)) || /^(?:yes|no)$/i.test(w) || words.length >= 5) break;
      words.push(w);
    }
    if (words.length) out.push(words.join(' '));
  }
  return out;
}

/** Every line of a catalogue, sorted (see the header). The text is read whole, up to CATALOGUE_MAX_TEXT. */
export function catalogueLines(text: string): CatalogueLines {
  const r: CatalogueLines = { headings: [], types: [], statements: [], spec_rows: 0, contact_rows: 0 };
  for (const raw of String(text ?? '').slice(0, CATALOGUE_MAX_TEXT).split(/\r?\n/)) {
    const line = raw.replace(/[\s]+/g, ' ').replace(/^[\s•·▪●◦*–—-]+/, '').trim();
    if (line.length < 2) continue;
    if (isContactLine(line)) { r.contact_rows++; continue; }
    if (isSpecRow(line)) { r.spec_rows++; r.types.push(...typeValues(line)); continue; }
    if (PERSON.test(line) || line.split(' ').length > MAX_HEADING_WORDS || /[.!?]\s+\S/.test(line)) { r.statements.push(line); continue; }
    r.headings.push(line);
  }
  return r;
}

// Word lists, compared on folded text. English forms are whole words; Arabic ones go through the alias
// pattern (alias_pattern.ts: definite article and proclitics allowed, word-start anchored).
const SUPPLY_EN = ['importer', 'importers', 'importing', 'import', 'imports', 'exporter', 'exporters', 'wholesaler', 'wholesalers', 'wholesale',
  'distributor', 'distributors', 'stockist', 'stockists', 'trading', 'trader', 'traders', 'reseller', 'resellers', 'dealer', 'dealers'];
const SUPPLY_AR = ['مستورد', 'استيراد', 'مصدر', 'تصدير', 'تاجر جملة', 'تجار جملة', 'بالجملة', 'بيع بالجملة', 'موزع', 'موزعون', 'موزعين', 'وكيل', 'وكلاء', 'تجارة عامة', 'للتجارة', 'تجارة'];
const INSTALL_EN = ['install', 'installs', 'installed', 'installing', 'installer', 'installers', 'installation', 'installations', 'contracting',
  'contractor', 'contractors', 'fit-out', 'fitout', 'fit out', 'commissioning', 'erection', 'maintenance', 'servicing', 'repair', 'repairs',
  'integrator', 'integrators', 'amc',
  // 7 Oct 2026 (accuracy suite, ledger 1162): "Plumbing works", "Electrical works" are how a profile and a licence
  // name execution work; without the word, the line was compared with supply services only (hoses & fittings).
  'works'];
const INSTALL_AR = ['تركيب', 'تركيبات', 'مقاولات', 'مقاول', 'تمديد', 'تمديدات', 'تنفيذ', 'صيانة', 'تصليح'];

const wordRe = (w: string) => new RegExp('(?<![\\p{L}\\p{N}])' + w.replace(/[-\s]+/g, '[\\s-]+') + '(?![\\p{L}\\p{N}])', 'iu');
const SUPPLY_RE = [...SUPPLY_EN.map(wordRe), ...SUPPLY_AR.map((w) => termPattern(w)).filter((r): r is RegExp => !!r)];
const INSTALL_RE = [...INSTALL_EN.map(wordRe), ...INSTALL_AR.map((w) => termPattern(w)).filter((r): r is RegExp => !!r)];

/** Does this text speak of installation, contracting or after-sales work at all? */
export const saysInstallWork = (text: string): boolean => {
  const norm = foldForMatch(String(text ?? '')).norm;
  return INSTALL_RE.some((re) => re.test(norm));
};

export type SupplyOnly = { supply_only: boolean; supply_words: string[]; install_words: string[] };

/** Supply-only: at least one trading word and no installation / contracting word. */
export function supplyOnlyOf(text: string): SupplyOnly {
  const norm = foldForMatch(String(text ?? '')).norm;
  const found = (res: RegExp[]) => [...new Set(res.map((re) => re.exec(norm)?.[0]?.toLowerCase().trim()).filter((w): w is string => !!w))];
  const supply_words = found(SUPPLY_RE); const install_words = found(INSTALL_RE);
  return { supply_only: supply_words.length > 0 && install_words.length === 0, supply_words, install_words };
}

export type CatalogueRead = { lines: CatalogueLines; supply: SupplyOnly; supply_only: boolean; rewrite: Rewrite; matched_text: string };

/** The whole catalogue path: sort the lines, decide supply-only, rewrite the headings and product types.
 *  `supplyOnly` overrides the detection (the supplier said "we also install", or confirmed it). */
export function readCatalogue(text: string, services: ServiceTerm[], supplyOnly?: boolean): CatalogueRead {
  const lines = catalogueLines(text);
  const supply = supplyOnlyOf([...lines.headings, ...lines.statements].join('\n'));
  const supply_only = typeof supplyOnly === 'boolean' ? supplyOnly : supply.supply_only;
  const matched_text = [...lines.headings, ...lines.types].join('\n');
  const rw = rewriteServices(matched_text, services,
    { supplyOnly: supply_only, maxText: CATALOGUE_MAX_TEXT, maxPhrases: CATALOGUE_MAX_LINES });
  // WHAT REACHES THE SALES ENGINEER FROM A CATALOGUE. A typed description's leftovers are the
  // supplier's words about its services and are all kept. A catalogue's are not: once "CCTV KITS" has
  // named CCTV, "KITS" is a fragment of a heading, not a product. So from a catalogue only a WHOLE line
  // that named nothing is kept ("Inverter", "Cables") — and never a trading word, which is already
  // the supply-only evidence.
  const rewrite = finishRewrite(rw.items.filter((i) => i.kind !== 'unmatched'
    || (tidy(i.from) === i.text && !SUPPLY_RE.some((re) => re.test(foldForMatch(i.text).norm)))));
  return { lines, supply, supply_only, rewrite, matched_text };
}
