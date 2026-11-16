// answer_parse — the small readers of a customer's answer: Arabic-Indic digits, the emirate, when the job is wanted,
// yes / no, and "I don't know" (16 Nov 2026, it_engineer; simplification wave A, DUP item 1).
//
// MOVED VERBATIM from inquiry_intake/interview.ts, which re-exports them. _shared/intake_requirements.ts and
// _shared/match_criteria.ts imported these five from that function folder, which put the whole 43,308-byte interview
// (and its Arabic question words) into supplier_api and wa_inbound. No model, no network, no env.
import { saysDontKnow } from './inquiry_state.ts';

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
