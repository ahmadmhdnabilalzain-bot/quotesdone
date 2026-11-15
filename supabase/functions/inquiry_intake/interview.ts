// interview — the deterministic intake interview (14 Sep 2026). No model, no network, no env.
//
// WHY THIS EXISTS. Every model route in llm_route_health is held under the founder's OpenRouter
// hold, so inquiry_intake's keyword fallback is the path every real customer takes. That fallback
// derived its "missing" list from category_specs required fields and NEVER READ THE ANSWERS: the
// customer answered, the next turn asked the same three trade-language questions again, status
// stayed needs_info, brief stayed null, and create_inquiry (which needs a 'ready' intake row) was
// unreachable for every category with a required field — 47 of 56 categories, 252 of 396 fields
// (measured on production category_specs, 14 Sep 2026). Posting a job has to work with no model.
//
// WHAT IT DOES. One question at a time, in the category's own order. The answer to the question
// last asked is parsed into that field's canonical key (category_specs.fields[].key — the same
// keys fn_rfq_required_check scores and the model path is told to use), and the first message is
// read opportunistically for anything it already states (an emirate, "120 sqm", an option named
// outright). When every required field is filled the brief is built in the exact shape the model
// path returns, so create_inquiry and customer_api take it unchanged.
//
// WHAT IT DOES NOT DO. It does not judge whether an answer is sensible for the trade. A vague or
// unparseable answer to the question just asked is KEPT IN THE CUSTOMER'S OWN WORDS rather than
// re-asked — the intake prompt's own rule is that an approximate answer beats an abandoned inquiry,
// and a supplier can quote against a stated assumption. Structured parsing (numbers + units,
// emirates, dates, yes/no, options, AED) normalises what it can recognise; nothing is invented.

import { saysDontKnow } from '../_shared/inquiry_state.ts';
import { ARABIC_FRAME, NOT_SURE, optionAr, saysNotSureAr } from '../_shared/customer_questions.ts';
export type SpecField = {
  key?: string; question?: string; required?: boolean; type?: string; options?: string[];
  question_plain_en?: string; question_plain_ar?: string;
  /** THE CARD'S WORDS (15 Nov 2026; _shared/customer_questions.ts): tap options a pack spec offers the customer (its own
   *  `options` stay [] so the readers here treat it as free text), Arabic labels of `options` (parallel), and plain=false when
   *  question_plain_en is only the generic frame of the label (the model's own plain wording may then be shown instead). */
  card_options?: string[]; card_options_ar?: string[]; options_ar?: string[]; plain?: boolean;
  /** WHEN THE JOB DOES NOT NEED THIS SPEC (15 Nov 2026, journey A; slots.ts notNeededOf). Data on the trade's own spec, never an
   *  if-statement: `answered` names specs whose answer makes this one unnecessary (code checks only that one of them holds an
   *  answer; it reads no words), `text` is the condition in plain words, which the model may judge holds from what the
   *  customer said (its "not_needed", with their words). Either way the spec is recorded as not needed and never asked. */
  not_needed_when?: { answered?: string[]; text: string } | null;
  /** The same question as another spec of the job (a slug's field that a placed trade's checklist also asks, e.g. hvac
   *  application_area and spec_room_use_and_area_or_heat_load_calc): asked once, as that spec, and answered by its answer. */
  same_as?: string | null;
};
export type Lang = 'en' | 'ar';
export type NextQuestion = { key: string; text: string; options: string[] | null };

// 38 of the 396 fields (every field of 9 categories: epoxy-flooring, interior-design, it-networking,
// kitchens, marble-granite, roofing, smart-home, solar, swimming-pools) carry NO key. The canonical
// ready gate in index.ts skips keyless fields (it filters on f.key), so a derived key is only this
// interview's own handle — it lands in brief.details and never collides with a canonical one.
export const fieldKey = (f: SpecField, i: number) => (f.key && String(f.key)) || `field_${i + 1}`;

const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';
export function normDigits(s: string): string {
  return String(s || '').replace(/[٠-٩]/g, (d) => String(AR_DIGITS.indexOf(d))).replace(/[٫]/g, '.').replace(/[٬،](?=\d{3}\b)/g, ',');
}

// ── EMIRATES, English and Arabic ────────────────────────────────────────────────────────────────
const EMIRATE_PATTERNS: [string, RegExp][] = [
  ['Abu Dhabi', /abu\s*dhabi|أبو\s*ظبي|ابو\s*ظبي|أبوظبي|ابوظبي/i],
  ['Al Ain', /\bal\s*ain\b|العين/i],
  ['Dubai', /dubai|دبي/i],
  ['Sharjah', /sharjah|الشارقة|شارقة/i],
  ['Ajman', /ajman|عجمان/i],
  ['Ras Al Khaimah', /ras\s*al\s*khaimah|\brak\b|رأس\s*الخيمة|راس\s*الخيمة/i],
  ['Fujairah', /fujairah|الفجيرة|فجيرة/i],
  ['Umm Al Quwain', /umm\s*al\s*quwain|\buaq\b|أم\s*القيوين|ام\s*القيوين/i],
];
export function parseEmirate(text: string): string | null {
  for (const [name, re] of EMIRATE_PATTERNS) if (re.test(text)) return name;
  return null;
}

// ── NUMBERS WITH UNITS ──────────────────────────────────────────────────────────────────────────
// Order matters: square units before linear metres, or "120 m2" would read as 120 m.
const UNITS: [string, RegExp][] = [
  ['sqm', /^(?:sqm|sq\.?\s*m(?:tr|eters?|etres?)?|m2|m²|square\s*met(?:er|re)s?|متر\s*مربع|م2|م²|مترمربع)/i],
  ['sqft', /^(?:sq\.?\s*ft|sqft|square\s*f(?:ee|oo)t|ft2|ft²|قدم\s*مربع)/i],
  ['lm', /^(?:lm|l\.m\.?|rm|linear\s*met(?:er|re)s?|running\s*met(?:er|re)s?|متر\s*طولي)/i],
  ['m3', /^(?:m3|m³|cu\.?\s*m|cubic\s*met(?:er|re)s?|متر\s*مكعب)/i],
  ['mm', /^(?:mm|millimet(?:er|re)s?|مم|ملم)/i],
  ['m', /^(?:m|met(?:er|re)s?|mtrs?|متر|أمتار|م)(?![a-z])/i],
  ['kva', /^kva/i], ['kw', /^kw(?!h)/i], ['tr', /^(?:tr|tons?\s*of\s*refrigeration)\b/i],
  ['kg', /^(?:kg|kgs|kilos?|كغ|كيلو)/i], ['ton', /^(?:tons?|tonnes?|طن)/i],
  ['litre', /^(?:l|ltrs?|lit(?:er|re)s?|لتر)(?![a-z])/i], ['gallon', /^(?:gal|gallons?|جالون|غالون)/i],
  ['pcs', /^(?:pcs|pieces?|units?|nos\.?|no\.|numbers?|items?|sets?|قطع|قطعة|وحدات|وحدة|حبة|حبات)/i],
  ['rooms', /^(?:rooms?|bedrooms?|br\b|bhk|غرف|غرفة)/i],
  ['floors', /^(?:floors?|storeys?|stories|levels?|طوابق|طابق|أدوار|دور)/i],
  ['windows', /^(?:windows?|نوافذ|نافذة|شبابيك|شباك)/i],
  ['doors', /^(?:doors?|أبواب|باب)/i],
  ['cameras', /^(?:cameras?|كاميرات|كاميرا)/i],
];
export type Measure = { value: number; unit: string | null; text: string };
export function parseMeasures(text: string): Measure[] {
  const t = normDigits(text);
  const out: Measure[] = [];
  const re = /(\d+(?:[.,]\d+)*)\s*(k\b|thousand|ألف|الف)?\s*/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(t)) !== null) {
    const rawNum = m[1].replace(/,(?=\d{3}(?:\D|$))/g, '').replace(',', '.');
    let value = Number(rawNum);
    if (!Number.isFinite(value)) continue;
    if (m[2]) value *= 1000;
    const rest = t.slice(m.index + m[0].length);
    let unit: string | null = null;
    for (const [u, ure] of UNITS) if (ure.test(rest)) { unit = u; break; }
    // "1200 x 1500" is a dimension pair: keep it whole rather than two bare numbers.
    const dim = t.slice(m.index).match(/^(\d+(?:\.\d+)?)\s*[x×\*]\s*(\d+(?:\.\d+)?)(?:\s*[x×\*]\s*(\d+(?:\.\d+)?))?\s*(mm|cm|m)?/i);
    if (dim && dim[2]) {
      out.push({ value, unit: dim[4] ? dim[4].toLowerCase() : null, text: dim[0].trim() });
      re.lastIndex = m.index + dim[0].length;
      continue;
    }
    out.push({ value, unit, text: unit ? `${value} ${unit}` : String(value) });
  }
  return out;
}

// ── DATES, DURATIONS, "ASAP" ────────────────────────────────────────────────────────────────────
export type When = { days: number | null; text: string; flexible?: boolean };
const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
export function parseWhen(text: string, now = new Date()): When | null {
  const t = normDigits(text).toLowerCase();
  if (/\b(asap|urgent(?:ly)?|immediately|right away|today|now|emergency)\b|فور[اًا]?|عاجل|بأسرع وقت|في أسرع وقت|اليوم|حالا|حالاً/.test(t)) return { days: 0, text: 'ASAP' };
  if (/\b(flexible|any ?time|no rush|not urgent|whenever)\b|مرن|غير مستعجل|أي وقت|اي وقت/.test(t)) return { days: null, text: 'Flexible', flexible: true };
  if (/\btomorrow\b|غد[اًا]?|بكرة|بكره/.test(t)) return { days: 1, text: 'Tomorrow' };
  if (/\bnext week\b|الأسبوع القادم|الاسبوع القادم|الأسبوع الجاي/.test(t)) return { days: 7, text: 'Next week' };
  if (/\bnext month\b|الشهر القادم|الشهر الجاي/.test(t)) return { days: 30, text: 'Next month' };
  const dur = t.match(/(\d+(?:\.\d+)?)\s*(?:-|to|–)?\s*(\d+)?\s*(days?|weeks?|months?|يوم|أيام|ايام|أسبوع|اسبوع|أسابيع|اسابيع|شهر|أشهر|اشهر|شهور)/);
  if (dur) {
    const n = Number(dur[2] || dur[1]);
    const u = dur[3];
    const mult = /week|أسبوع|اسبوع|أسابيع|اسابيع/.test(u) ? 7 : (/month|شهر|أشهر|اشهر|شهور/.test(u) ? 30 : 1);
    return { days: Math.round(n * mult), text: dur[0].trim() };
  }
  const arDur = t.match(/(أسبوعين|اسبوعين|شهرين|يومين)/);
  if (arDur) return { days: /شهرين/.test(arDur[1]) ? 60 : (/يومين/.test(arDur[1]) ? 2 : 14), text: arDur[1] };
  const dmy = t.match(/\b(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})\b/);
  if (dmy) {
    const y = Number(dmy[3].length === 2 ? '20' + dmy[3] : dmy[3]);
    const d = new Date(Date.UTC(y, Number(dmy[2]) - 1, Number(dmy[1])));
    if (!isNaN(d.getTime())) return { days: Math.max(0, Math.round((d.getTime() - now.getTime()) / 86400000)), text: d.toISOString().slice(0, 10) };
  }
  for (let i = 0; i < 12; i++) {
    const re = new RegExp(`(?:(\\d{1,2})\\s*)?\\b${MONTHS[i]}|\\b${MONTHS[i].slice(0, 3)}\\b`);
    const mm = t.match(re);
    if (mm) {
      let y = now.getUTCFullYear();
      const day = mm[1] ? Number(mm[1]) : 1;
      let d = new Date(Date.UTC(y, i, day));
      if (d.getTime() < now.getTime() - 86400000) { y++; d = new Date(Date.UTC(y, i, day)); }
      return { days: Math.round((d.getTime() - now.getTime()) / 86400000), text: mm[1] ? d.toISOString().slice(0, 10) : `${MONTHS[i][0].toUpperCase()}${MONTHS[i].slice(1)} ${y}` };
    }
  }
  return null;
}

// ── MONEY ───────────────────────────────────────────────────────────────────────────────────────
export function parseBudget(text: string): string | null {
  const t = normDigits(text);
  if (!/aed|dhs?\b|dirhams?|درهم|دراهم|د\.إ|budget|ميزانية|\d\s*(?:k|m)\b/i.test(t)) return null;
  // A NUMBER IS A BUDGET ONLY WHEN IT CARRIES A MONEY MARKER ITSELF. Measured 22 Sep 2026 on production
  // (scripts/e2e/drawing_reaches_suppliers.mjs): "...26x18 supply duct... Budget is open." became budget
  // "AED 26" - the word "budget" let the text in and the first number anywhere was taken - and 26 fell
  // below every HVAC supplier's minimum job, so the request matched nobody. Review of #821: the first fix
  // still read "Budget: not sure, maybe use 26x18 duct" as AED 26. So each number is judged on its own:
  //  * never when it is part of a dimension: NxN / N×N, or N followed by mm, cm, m, in, inch, ", ', ft;
  //  * yes when it carries a multiplier (k, thousand, ألف, M, million, مليون), a currency right after it
  //    (AED, Dhs, dirhams, درهم, د.إ), a currency or "budget" right before it (a few characters, no other
  //    words), or a thousands separator (250,000).
  const re = /\d+(?:[.,]\d+)*/g;
  for (let m: RegExpExecArray | null; (m = re.exec(t)); ) {
    const raw = m[0], before = t.slice(Math.max(0, m.index - 24), m.index), after = t.slice(m.index + raw.length, m.index + raw.length + 16);
    if (/[x×*]\s*$/i.test(before) || /^\s*[x×*]\s*\d/i.test(after)) continue;                         // 26x18
    const mult = after.match(/^\s*(k\b|thousand|ألف|الف|M\b|mn\b|million|مليون)/);
    if (!mult && /^\s*(?:mm|cm|m|in|inch(?:es)?|ft|feet|metres?|meters?|["'″′])(?![a-z])/i.test(after)) continue;   // 12 m, 8"
    const curAfter = /^\s*(?:aed|dhs?|dirhams?|درهم|دراهم|د\.إ)(?![a-z])/i.test(after);
    const curBefore = /(?:aed|dhs?|dirhams?|درهم|دراهم|د\.إ|budget|ميزانية)[\s:~]*(?:(?:is|of|around|about|approx(?:imately|\.)?|roughly|حوالي|تقريبا|تقريبًا)[\s:~]*)?$/i.test(before);
    const grouped = /^\d{1,3}(?:,\d{3})+(?:\.\d+)?$/.test(raw);
    if (!mult && !curAfter && !curBefore && !grouped) continue;
    let v = Number(raw.replace(/,/g, ''));
    if (!Number.isFinite(v) || v <= 0) continue;
    if (mult) v *= /M\b|mn|million|مليون/.test(mult[1]) ? 1_000_000 : 1000;
    return `AED ${Math.round(v)}`;
  }
  return null;
}

// ── YES / NO / DON'T KNOW ───────────────────────────────────────────────────────────────────────
export function parseYesNo(text: string): 'Yes' | 'No' | null {
  // "Not sure" is not a yes. The yes pattern below contains `sure`, so without this line "not sure,
  // advise" read as Yes (found 14 Sep 2026 replaying the founder's generators request: his "Not sure"
  // about the power rating answered "should it switch on by itself?" with Yes, unasked).
  if (isUnknown(text)) return null;
  const t = ' ' + String(text || '').toLowerCase().trim() + ' ';
  if (/\b(no|nope|not needed|none|don't need|do not need)\b|^\s*لا\s|لا نحتاج|لا أحتاج|غير مطلوب/.test(t)) return 'No';
  if (/\b(yes|yeah|yep|yup|sure|please|of course|definitely|needed|required)\b|نعم|أيوه|ايوه|اي نعم|أكيد|اكيد|طبعا|طبعاً|مطلوب/.test(t)) return 'Yes';
  return null;
}
// "I don't know" in Egyptian, Levantine and Gulf Arabic and in Arabizi too (_shared/inquiry_state.ts saysDontKnow, ledger 1572).
export const isUnknown = (text: string) => saysDontKnow(text) ||
  /\b(not sure|don'?t know|do not know|no idea|unsure|you (?:tell|advise|recommend)|recommend|advise)\b|لا أعرف|لا اعرف|مش عارف|ما أعرف|ما اعرف|غير متأكد|غير متاكد|انصحني|اقترح/i.test(String(text || ''));

// ── OPTIONS ─────────────────────────────────────────────────────────────────────────────────────
const tokens = (s: string) => String(s || '').toLowerCase().replace(/\(.*?\)/g, ' ').split(/[^a-z0-9؀-ۿ+]+/).filter((w) => w.length > 2);
function optionForDays(options: string[], w: When): string | null {
  if (w.flexible) return options.find((o) => /flexib/i.test(o)) || null;
  if (w.days === null) return null;
  let best: string | null = null;
  for (const o of options) {
    const lo = o.toLowerCase();
    if (/urgent|asap|immediate/.test(lo) && w.days <= 14) return o;
    const nums = (lo.match(/\d+/g) || []).map(Number);
    if (!nums.length) continue;
    const mult = /month/.test(lo) ? 30 : (/week/.test(lo) ? 7 : 1);
    const max = Math.max(...nums) * mult;
    if (w.days <= max) { best = o; break; }
  }
  return best;
}
// Every option in category_specs is written in English (all 396 fields, measured 14 Sep 2026), so
// an Arabic answer can never name one. Common Arabic trade words are glossed to the English an
// option uses before matching.
// ponytail: a fixed glossary of ~40 terms; the upgrade is an options_ar sibling on category_specs.
const AR_GLOSS: [RegExp, string][] = [
  [/نوافذ|نافذة|شبابيك|شباك/, 'windows'], [/أبواب|ابواب|باب/, 'doors'], [/درابزين/, 'railing handrails'],
  [/تكسية|كلادينج/, 'cladding'], [/برجولة|مظلة|مظلات/, 'pergola shade'], [/قواطع|فواصل|بارتشن/, 'partitions'],
  [/منزلق|سحاب/, 'sliding'], [/توريد\s*و\s*تركيب|توريد\s*وتركيب/, 'supply and install supply + installation'],
  [/توريد\s*فقط/, 'supply only'], [/تركيب\s*فقط/, 'install only installation only'],
  [/فيلا|فلة|فيلّا/, 'villa'], [/شقة/, 'apartment'], [/مكتب/, 'office'], [/محل|متجر/, 'retail shop'],
  [/مستودع|مخزن/, 'warehouse'], [/مطعم|مقهى/, 'restaurant cafe'], [/عيادة/, 'clinic'], [/مبنى|بناية|عمارة/, 'building'],
  [/داخلي/, 'indoor interior'], [/خارجي/, 'outdoor exterior'], [/كلاهما|الاثنين|الإثنين/, 'both'],
  [/زجاج\s*مزدوج|دبل/, 'double glazed'], [/زجاج\s*مفرد|سنجل/, 'single glazed'], [/مصنفر/, 'frosted'],
  [/مرة\s*واحدة/, 'one-time'], [/أسبوعي|اسبوعي/, 'weekly'], [/شهري/, 'monthly'], [/سنوي|عقد\s*سنوي/, 'annual contract'],
  [/إيجار|ايجار|استئجار/, 'rental'], [/شراء/, 'buy'], [/جديد/, 'new installation new build'], [/استبدال/, 'replacement'],
  [/صيانة/, 'maintenance'], [/إصلاح|اصلاح|تصليح/, 'repair'], [/سيراميك/, 'ceramic'], [/بورسلان/, 'porcelain'],
  [/رخام/, 'marble'], [/جرانيت|غرانيت/, 'granite'], [/باركيه/, 'parquet'], [/فينيل/, 'vinyl'], [/إيبوكسي|ايبوكسي/, 'epoxy'],
  [/سجاد|موكيت/, 'carpet'], [/أسقف\s*معلقة|سقف\s*معلق|جبس/, 'false ceiling'], [/كاميرات|كاميرا|مراقبة/, 'cctv cameras'],
  [/سطح/, 'roof'], [/حمام/, 'bathroom'], [/مطبخ/, 'kitchen'], [/حديقة/, 'garden softscape'],
];
function glossArabic(text: string): string {
  let add = '';
  for (const [re, en] of AR_GLOSS) if (re.test(text)) add += ' ' + en;
  return add;
}

/** Every option named in the text. A select field takes the first; a multiselect takes all. */
// English says the same option several ways. Measured on harness journey a (14 Sep 2026): "supplied
// and installed" never matched the option "Supply and install", so scope was asked again and the next
// sentence the customer typed was stored as the answer.
function glossEnglish(text: string): string {
  const t = String(text || '').toLowerCase();
  let add = '';
  if (/\bsuppl(?:y|ied)\s+(?:and|&|\+)\s+install(?:ed|ation)?\b|\bsupply[\s-]+(?:and|&)[\s-]+fix\b|\binstalled\b/.test(t)) add += ' supply and install';
  if (/\b(?:supply|deliver(?:y)?)\s+only\b|\bno installation\b|\bwithout installation\b/.test(t)) add += ' supply only';
  return add;
}

// Words that name no work on their own, so a multiselect option is never picked on one of them.
const GENERIC_TOKENS = new Set(['not', 'sure', 'other', 'only', 'and', 'the', 'with', 'new', 'supply', 'install', 'points', 'works', 'work', 'system', 'systems', 'services', 'service', 'general', 'type', 'unit', 'units', 'connection', 'standard']);
/**
 * `multi` = a multiselect field: a list of works, where every option the customer names is wanted.
 * Then an option is also matched by its parenthetical ("New wiring (first fix)" ← "first fix") or by
 * its last specific noun ("Power sockets" ← "60 double sockets"). Measured 21 Sep 2026 (customer
 * audit, finding 8): "Supply and install 500 m of ... cable ... 3 x 12-way DB boards ... 60 double
 * sockets" kept only "DB board supply & install"; the cable and the sockets were dropped from scope.
 */
export function matchOptions(options: string[], text: string, multi = false): string[] {
  const t = ' ' + String(text || '').toLowerCase() + glossArabic(String(text || '')) + glossEnglish(String(text || '')) + ' ';
  const hits: string[] = [];
  const word = (w: string) => new RegExp(`(^|[^a-z])${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^a-z]|$)`).test(t);
  for (const o of options) {
    const lo = o.toLowerCase();
    if (/^(yes|no)\b/.test(lo) && lo.length < 5) continue; // yes/no handled by parseYesNo
    const whole = lo.replace(/\s*\(.*?\)\s*/g, ' ').trim();
    if (whole.length > 2 && t.includes(whole)) { hits.push(o); continue; }
    const alts = lo.split(/\s*[\/+]\s*|\s+or\s+/).map((s) => s.replace(/\(.*?\)/g, '').trim()).filter((s) => s.length > 2);
    if (alts.some(word)) { hits.push(o); continue; }
    const tk = tokens(o).filter((w) => !GENERIC_TOKENS.has(w));
    if (tk.length && tk.length <= 3 && tk.every((w) => t.includes(w))) { hits.push(o); continue; }
    if (!multi) continue;
    const paren = (lo.match(/\(([^)]{4,})\)/) || [])[1];
    if (paren && t.includes(paren.trim())) { hits.push(o); continue; }
    const last = tk[tk.length - 1];
    if (last && last.length >= 6 && word(last)) hits.push(o);
  }
  return hits;
}

// ── WHAT KIND OF ANSWER A FIELD WANTS ───────────────────────────────────────────────────────────
type Kind = 'emirate' | 'when' | 'budget' | 'measure' | 'text';
export function kindOf(f: SpecField): Kind {
  const s = `${f.key || ''} ${f.question || ''}`.toLowerCase();
  if (/budget/.test(s)) return 'budget';
  if (/timeline|timing|deadline|\bdate\b|start|when |completion|duration/.test(s)) return 'when';
  if (/emirate|location/.test(s)) return 'emirate';
  if (f.type === 'number' || /area|sqm|size|quantity|how many|dimensions|capacity|qty|stops|count|m²|length|height/.test(s)) return 'measure';
  return 'text';
}

// ── AN ANSWER IS RECORDED UNDER THE SPEC IT ANSWERS (evidence run of 10 Nov 2026, ledger 1604, finding b2) ─────────
// The request chat asked "MEP scope" and the customer answered "We need it finished by 15 December 2026."; it asked
// "Authority approvals and responsibility" and the customer answered "At least 2 years warranty on materials and
// installation.". Each reply was stored as the answer to the question asked (a targeted free-text field keeps the reply
// verbatim, below; a held spec is read the same way, slots.ts readHeldAnswer), the two blocking specs counted answered,
// and the request went ready with 20/20 filled. The four UNIVERSAL kinds — a date or timeline, money, a warranty period,
// an emirate — are recognised here by their own shape and vocabulary (the readers above, and the words of that kind
// only). A reply that is ONLY a statement of one of them answers that kind, and never a field of another kind: it
// leaves the asked spec open. Anything else is never decided by a word list here (ruling 890): it is the question's.
export type UniversalKind = 'required_by' | 'budget' | 'warranty' | 'location';
const FUNCTION_WORDS = new Set(('we i it its is are be will would should must can could need needs needed want wants like the a an and or of for to on in at by '
  + 'before after within until till latest no not than our my me us this that please thanks thank you have has get got least minimum maximum max min '
  + 'around about approx approximately roughly up from all also just only so as with any it\'s we\'d we\'re i\'d i\'m would\'ve '
  + 'نحتاج نحتاجه نحتاجها نريد نريده نريدها أريد اريد يجب أن ان على الأقل الاقل أقل اقل في من إلى الى قبل بعد خلال حتى مع و أو او لا هذا هذه لدينا عندنا يكون تكون نحن').split(/\s+/));
const KIND_WORDS: Record<UniversalKind, Set<string>> = {
  required_by: new Set(('finished finish finishing done complete completed completion ready delivered delivery deliver start started starting handover handed deadline date time '
    + 'day days week weeks month months year asap urgent urgently soon end early mid next tomorrow today st nd rd th '
    + 'january february march april may june july august september october november december jan feb mar apr jun jul aug sep sept oct nov dec '
    + 'ينتهي ننتهي الانتهاء انتهاء تسليم التسليم جاهز جاهزة موعد تاريخ يوم أيام ايام أسبوع اسبوع أسابيع شهر أشهر اشهر نهاية بداية '
    + 'يناير فبراير مارس أبريل ابريل مايو يونيو يوليو أغسطس اغسطس سبتمبر أكتوبر اكتوبر نوفمبر ديسمبر').split(/\s+/)),
  budget: new Set(('budget aed dhs dh dirham dirhams k thousand million total cost costs price spend spending max per '
    + 'ميزانية الميزانية درهم دراهم ألف الف مليون تكلفة التكلفة سعر').split(/\s+/)),
  warranty: new Set(('warranty warranties guarantee guaranteed year years yr yrs month months materials material installation install workmanship labour labor parts '
    + 'defects defect covering cover covers coverage full comprehensive both '
    + 'ضمان الضمان كفالة سنة سنتين سنتان سنوات عام عامين شهر أشهر المواد مواد التركيب تركيب العمالة الصنعة').split(/\s+/)),
  location: new Set(('dubai abu dhabi sharjah ajman ras al khaimah umm quwain fujairah rak uaq auh dxb shj emirate uae '
    + 'دبي أبوظبي ابوظبي أبو ظبي الشارقة شارقة عجمان رأس الخيمة راس أم ام القيوين الفجيرة الإمارات الامارات').split(/\s+/)),
};
// parseWhen reads English month names; an Arabic date is a day and a month name (the Arabic month names of KIND_WORDS).
const AR_DATE = /\d{1,2}\s*(?:يناير|فبراير|مارس|أبريل|ابريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر)/;
const WARRANTY_SIGN = /\b(warrant(?:y|ies)|guarantee[d]?)\b|ضمان|كفالة/i;
const tokensOf = (s: string) => normDigits(s).toLowerCase().replace(/[^\p{L}\p{N}'\s]+/gu, ' ').split(/\s+/).filter(Boolean);
const bare = (w: string) => w.replace(/^(?:وال|بال|لل|ال|و)(?=\p{L}{2,})/u, '');
/** The universal kind a reply is ONLY a statement of, or null (it says something else, or several things). */
export function statementKind(text: string): UniversalKind | null {
  const raw = String(text || '').trim();
  if (!raw || raw.length > 240) return null;
  const has: Record<UniversalKind, boolean> = {
    warranty: WARRANTY_SIGN.test(raw), budget: !!parseBudget(raw), required_by: !!parseWhen(raw) || AR_DATE.test(normDigits(raw)), location: !!parseEmirate(raw),
  };
  // A warranty is a period, so its years are not a timeline; a money amount is not a date.
  const order: UniversalKind[] = ['warranty', 'budget', 'required_by', 'location'];
  for (const k of order) {
    if (!has[k]) continue;
    const content = tokensOf(raw).filter((w) => !/^\d/.test(w) && !FUNCTION_WORDS.has(w) && !FUNCTION_WORDS.has(bare(w)) && !KIND_WORDS[k].has(w) && !KIND_WORDS[k].has(bare(w)));
    if (!content.length) return k;
  }
  return null;
}
/** The universal kind a FIELD asks, from its own key and question (our checklist's words, not the customer's), or null. */
export function fieldKind(f: Pick<SpecField, 'key' | 'question'> & { label_en?: string | null }): UniversalKind | null {
  const s = `${f.key || ''} ${f.question || ''} ${f.label_en || ''}`.toLowerCase();
  if (/warrant|guarantee|ضمان/.test(s)) return 'warranty';
  const k = kindOf(f as SpecField);
  return k === 'when' ? 'required_by' : k === 'budget' ? 'budget' : k === 'emirate' ? 'location' : null;
}
/** The kind a reply answers INSTEAD of field `f` — non-null means it is not this field's answer, and `f` stays open. */
export function answersAnotherKind(f: Pick<SpecField, 'key' | 'question'> & { label_en?: string | null }, text: string): UniversalKind | null {
  const k = statementKind(text);
  return k && k !== fieldKind(f) ? k : null;
}

/**
 * Parse `text` as the answer to field `f`.
 * `targeted` = this was the question just asked, so an answer that cannot be normalised is still
 * the customer's answer and is kept verbatim. Untargeted (reading the first message for facts it
 * already states) only fills a field on a clear structured hit, never on free text.
 */
export function parseAnswer(f: SpecField, text: string, targeted: boolean): string | null {
  const raw = String(text || '').trim();
  if (!raw) return null;
  // A reply that only states a date, money, a warranty or an emirate answers THAT, never another kind of field (b2).
  if (answersAnotherKind(f, raw)) return null;
  const opts = Array.isArray(f.options) ? f.options.filter((o) => typeof o === 'string' && o) : [];
  const kind = kindOf(f);
  if (opts.length) {
    // Only the question just asked can be answered by a bare yes or no. Reading the whole
    // conversation for one let any "yes" or "no" the customer said about something else fill every
    // unanswered yes/no field at once.
    if (targeted && opts.length <= 3 && opts.some((o) => /^yes\b/i.test(o)) && opts.some((o) => /^no\b/i.test(o))) {
      const yn = parseYesNo(raw);
      if (yn) return opts.find((o) => o.toLowerCase().startsWith(yn.toLowerCase())) || yn;
    }
    if (kind === 'when') { const w = parseWhen(raw); const o = w ? optionForDays(opts, w) : null; if (o) return o; }
    if (kind === 'emirate') {
      const e = parseEmirate(raw);
      if (e) return opts.find((o) => o.toLowerCase().includes(e.toLowerCase()))
        || (['Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'].includes(e) ? opts.find((o) => /northern/i.test(o)) : undefined)
        || (targeted ? e : null);
    }
    // A "not sure" is only ever the answer to the question it was said to. Read untargeted, one "not
    // sure" anywhere in the conversation filled every field that offers a Not sure / Recommend option
    // (the generators replay, 14 Sep 2026: "Not sure - advise" about power also answered the
    // automatic-switch question, which was then never asked).
    const hits = matchOptions(opts, raw, f.type === 'multiselect').filter((o) => targeted || !/not sure|recommend|advise|unknown|unsure/i.test(o));
    if (hits.length) return f.type === 'multiselect' ? hits.join(', ') : hits[0];
    if (targeted && isUnknown(raw)) return opts.find((o) => /not sure|recommend|advise|unknown|unsure/i.test(o)) || 'Not sure';
    // A tap question answered with a paragraph that names none of its options is a STATEMENT about
    // something else, not this answer (measured, journey a: "Materials: thermal break aluminium
    // frames, ..." was stored as the answer to "install or deliver only?"). Its facts are still read
    // for the fields they fit; this question stays open.
    return targeted && raw.length <= 80 && !/[.!?؟]\s+\S/.test(raw) ? raw.slice(0, 300) : null;
  }
  if (targeted && isUnknown(raw)) return 'Not sure';
  if (kind === 'emirate') {
    const e = parseEmirate(raw);
    if (!targeted) return e;
    // Keep the customer's area words ("Dubai Marina, 12th floor") — the emirate is also lifted
    // onto brief.emirate separately, so nothing is lost by not reducing this to one word.
    return raw.slice(0, 300);
  }
  if (kind === 'budget') return parseBudget(raw) || (targeted ? raw.slice(0, 120) : null);
  if (kind === 'when') { const w = parseWhen(raw); return w ? w.text : (targeted ? raw.slice(0, 120) : null); }
  if (kind === 'measure') {
    const ms = parseMeasures(raw);
    const q0 = `${f.key || ''} ${f.question || ''}`.toLowerCase();
    // "40 aluminium windows ... Sizes 1200 x 1500 mm": a count of things and a size, however far
    // apart, answer a "how many and how big" field outright (measured: journey a stated both in its
    // first message and was asked for them anyway).
    // Read from what was already said only (untargeted): a direct answer keeps the customer's own
    // words, and a unit they did not write is never added.
    if (!targeted && /quantity|how many|pieces|qty|dimensions/.test(q0)) {
      const t = normDigits(raw);
      const cnt = t.match(/\b(\d{1,4})\s+(?:[a-z\-]+\s+){0,2}?(windows?|doors?|units?|pieces?|pcs|panels?|shutters?|railings?|sets?|nos)\b/i);
      const dim = t.match(/\b(\d{2,5})\s*[x×*]\s*(\d{2,5})(?:\s*[x×*]\s*\d{2,5})?\s*(mm|cm|m)?\b/i);
      if (cnt) return `${cnt[1]} ${cnt[2].toLowerCase()}${dim ? `, ${dim[1]} x ${dim[2]}${dim[3] ? ' ' + dim[3].toLowerCase() : ''}` : ''}`;
    }
    // A "how many / how big" question answered with no number at all did not answer it.
    if (targeted && !/\d/.test(normDigits(raw))) return null;
    if (targeted) {
      // A targeted multi-part answer ("3 windows, 1200x1500 each") is kept whole; a single bare
      // measure is normalised to "<n> <unit>".
      if (ms.length === 1 && raw.replace(/[\d.,\s]/g, '').length <= 20) return ms[0].text;
      // A paragraph answers a "how big" question with ONE of its sentences: the first that carries a
      // number. Measured 21 Sep 2026 (customer audit, finding 8): "It is a 4-bedroom villa, about 450
      // m2 built-up, 9 rooms. Three-phase supply. As I said: MK Logic or Legrand ... finished by 30
      // November 2026." was stored whole as property_area and printed as the Quantity.
      const sentences = raw.split(/(?<=[.!?؟])\s+(?=\S)/);
      const first = sentences.length > 1 ? sentences.find((s) => /\d/.test(normDigits(s))) || sentences[0] : raw;
      return first.slice(0, 300);
    }
    // Opportunistic read: only a measure whose unit this field is plainly about.
    const q = `${f.key || ''} ${f.question || ''}`.toLowerCase();
    const want = /sq\.?\s*ft|sqft/.test(q) ? ['sqft', 'sqm'] : (/area|sqm|m²|m2/.test(q) ? ['sqm', 'sqft'] : (/room|bedroom/.test(q) ? ['rooms'] : (/floor|stops/.test(q) ? ['floors'] : (/camera/.test(q) ? ['cameras'] : (/window/.test(q) ? ['windows'] : [])))));
    const hit = ms.find((m) => m.unit && want.includes(m.unit));
    return hit ? hit.text : null;
  }
  return targeted ? raw.slice(0, 300) : null;
}

/** Required first, then fn_category_questions' ask_order where the key matches, then spec order. */
export function orderFields(fields: SpecField[], askOrder: Record<string, number> = {}) {
  return fields
    .map((f, i) => ({ f, i, key: fieldKey(f, i) }))
    .filter(({ f }) => f && (f.question || f.key))
    .sort((a, b) => (Number(!!b.f.required) - Number(!!a.f.required))
      || ((askOrder[a.key] ?? 999) - (askOrder[b.key] ?? 999))
      || (a.i - b.i));
}

/** The question the CUSTOMER reads: the plain wording in their language. NEVER ENGLISH ON AN ARABIC CHAT (15 Nov 2026, persona
 *  dry run: every card of an Arabic chat was an English spec label): a field with no Arabic wording is asked with the Arabic
 *  frame (customer_questions.ts ARABIC_FRAME), never its English label. The label (`question`) is what suppliers read. */
export function questionText(f: SpecField, lang: Lang): string {
  if (lang === 'ar') return String(f.question_plain_ar || '').trim() || (f && (f.question || f.key) ? ARABIC_FRAME : '');
  return String(f.question_plain_en || f.question || f.key || '').trim();
}
/** The spec as the MODEL is told it (its prompt's open specs, the held reply's facts): the plain wording in the customer's
 *  language where there is one, else the English plain wording or the label, which the model reads and words in their language.
 *  Never the Arabic frame: that names no spec. */
export function modelText(f: SpecField, lang: Lang): string {
  return String((lang === 'ar' ? f.question_plain_ar || f.question_plain_en : f.question_plain_en) || f.question || f.key || '').trim();
}
/** The options the card offers to tap, in the customer's language, or null. A field's own options first (in Arabic, those with
 *  an Arabic label: options_ar, else customer_questions.ts OPTION_AR; "Not sure" always), else the pack spec's card options. */
export function optionsOf(f: SpecField | null | undefined, lang: Lang): string[] | null {
  if (!f) return null;
  const own = Array.isArray(f.options) ? f.options.filter((o) => typeof o === 'string' && o) : [];
  if (own.length) {
    // "Not sure" on every card (an option of the field's own that already says so is kept as it is)
    const sure = own.some((o) => /not sure|unsure|recommend|advise/i.test(o));
    if (lang === 'en') return sure ? own : [...own, NOT_SURE.en];
    const ar = own.map((o, i) => (Array.isArray(f.options_ar) && f.options_ar.length === f.options!.length && f.options_ar[i]) || optionAr(o)).filter((x): x is string => !!x);
    return ar.some(saysNotSureAr) ? ar : [...ar, NOT_SURE.ar];
  }
  const card = (lang === 'ar' ? f.card_options_ar : f.card_options) ?? [];
  const list = card.filter((o) => typeof o === 'string' && o);
  return list.length ? list : null;
}

export type InterviewState = { details: Record<string, string>; asked_key: string | null };
export type InterviewStep = {
  details: Record<string, string>;
  filled_now: string[];
  next: NextQuestion | null;
  readiness: { filled: number; required: number };
  complete: boolean;
};

/**
 * One turn. `answer` is this turn's message; `firstText` is everything the customer has said so
 * far (read only for clear structured facts). The field last asked receives `answer`.
 */
export function interviewStep(fields: SpecField[], state: InterviewState, answer: string, allText: string, lang: Lang, askOrder: Record<string, number> = {}): InterviewStep {
  const details: Record<string, string> = { ...(state.details || {}) };
  const ordered = orderFields(fields, askOrder);
  const filledNow: string[] = [];
  const has = (k: string) => details[k] !== undefined && String(details[k]).trim() !== '';
  if (state.asked_key && answer && !has(state.asked_key)) {
    const hit = ordered.find((o) => o.key === state.asked_key);
    if (hit) { const v = parseAnswer(hit.f, answer, true); if (v) { details[hit.key] = v; filledNow.push(hit.key); } }
  }
  for (const o of ordered) {
    if (has(o.key)) continue;
    const v = parseAnswer(o.f, allText, false);
    if (v) { details[o.key] = v; filledNow.push(o.key); }
  }
  const req = ordered.filter((o) => o.f.required);
  const filled = req.filter((o) => has(o.key)).length;
  const nextField = req.find((o) => !has(o.key));
  const next = nextField
    ? { key: nextField.key, text: questionText(nextField.f, lang), options: optionsOf(nextField.f, lang) }
    : null;
  return { details, filled_now: filledNow, next, readiness: { filled, required: req.length }, complete: !nextField };
}

/** The brief, in the shape the model path returns (inquiry_intake sys prompt, "brief"). */
export function buildBrief(category: string, details: Record<string, string>, allText: string, emirate: string | null, firstUserText: string) {
  const pick = (re: RegExp) => { const k = Object.keys(details).find((x) => re.test(x)); return k ? String(details[k]) : ''; };
  const location = pick(/location|emirate/);
  const em = emirate || parseEmirate(location) || '';
  // Quantity is a measure ("450 sqm", "40 windows, 1200 x 1500 mm") or empty; the customer's prose
  // stays in details under its own key and in the summary. Measured 21 Sep 2026 (customer audit,
  // finding 8): a whole reply about brands and warranty was printed as "Quantity: It is a 4-bedroom
  // villa...". The summary is the customer's description in full: the 160-character cut of the old
  // shape truncated the audit request at "3 x 12-way D" and lost the cable, boards and sockets.
  const qtyText = pick(/area|qty|quantity|size|dimensions|count|stops|capacity|windows|rooms|coverage|scale|building/);
  const qtyMeasures = parseMeasures(qtyText);
  const quantity = /^\d/.test(qtyText.trim()) && qtyText.length <= 80 ? qtyText : (qtyMeasures.find((m) => m.unit)?.text || '');
  return {
    summary: String(firstUserText || allText).replace(/\s+/g, ' ').trim().slice(0, 4000),
    category,
    scope: pick(/^scope|supply_install|scope_mode|installation|engagement|work_type|service/),
    quantity,
    location: location || em,
    emirate: em,
    timeline: pick(/timeline|timing|date|deadline|duration/),
    budget: pick(/budget/) || parseBudget(allText) || '',
    details,
  };
}
