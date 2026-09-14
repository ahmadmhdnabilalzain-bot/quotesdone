// The FAQ is what the support widget answers from, so it must not promise what the policies do not.
// Website audit, 14 Sep 2026: the FAQ named a staff title that does not exist, gated refunds to a
// person who by the 8 Sep ruling no longer approves anything, and invented a refund window that the
// Refund Policy never grants.
//
// Fails when the FAQ (English or Arabic):
//   1. names a staff title (director/manager/officer-style, or a capitalised title word such as a
//      curator or trainer, or a capitalised "<Word> agent") that no legal document names;
//   2. names the company's owner as the one who approves, reviews, decides or makes a final call
//      (any owner-role word in the FAQ at all is treated as that — the CEO decides);
//   3. says something is routed, gated or approved by a human, a person or an admin;
//   4. quotes a working-day figure that no legal document states, or any refund "window";
//   5. publishes a Sunday-to-Thursday week (the working week is Monday to Friday everywhere).
// The patterns are assembled from fragments so this file does not match its own subject when grepped.
//
//   node scripts/checks/faq_matches_policies.mjs
import fs from 'node:fs';

const read = (f) => JSON.parse(fs.readFileSync(new URL(`../../src/content/${f}.json`, import.meta.url), 'utf8'));
const legal = read('legal');
const mk = read('marketing');
const text = (h) => h.replace(/<[^>]+>/g, ' ').replace(/&#39;|&#x27;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/\s+/g, ' ');
const legalEn = Object.values(legal).map((d) => text(d.en.html)).join(' ');
const legalAr = Object.values(legal).map((d) => text(d.ar.html)).join(' ');
const faqEn = text(mk.faq.en.html);
const faqAr = text(mk.faq.ar.html);
const fails = [];

// 1. staff titles
const TITLES = ['Direc' + 'tor', 'Mana' + 'ger', 'Offi' + 'cer', 'Cura' + 'tor', 'Train' + 'er', 'Supervi' + 'sor'];
for (const m of faqEn.matchAll(new RegExp(`\\b(?:[A-Z][a-z]+ ){0,3}(?:${TITLES.join('|')})\\b`, 'g'))) {
  if (!legalEn.includes(m[0])) fails.push(`FAQ (en) names the role "${m[0]}", which no legal document names`);
}
for (const m of faqEn.matchAll(/\b([A-Z][a-z]+) agent\b/g)) {
  if (!['The', 'An', 'A', 'Each', 'Every', 'One'].includes(m[1]) && !legalEn.includes(m[0])) fails.push(`FAQ (en) names the role "${m[0]}"`);
}
const AR_TITLES = ['مدي' + 'ر', 'المنس' + 'ق', 'مدر' + 'ب'];
for (const m of faqAr.matchAll(new RegExp(`(?<![\\u0600-\\u06FF])(?:${AR_TITLES.join('|')})(?![\\u0600-\\u06FF])(?:\\s[\\u0600-\\u06FF]+){0,2}`, 'g'))) {
  if (!legalAr.includes(m[0])) fails.push(`FAQ (ar) names the role "${m[0]}", which no legal document names`);
}

// 2. the owner as approver
const OWNER_EN = new RegExp('\\b' + 'foun' + 'der' + '\\b', 'i');
const OWNER_AR = new RegExp('(?<![\\u0600-\\u06FF])(?:ال|و|ل)?' + 'مؤس' + 'س(?:نا|ها)?(?![\\u0600-\\u06FF])');
for (const s of faqEn.split(/(?<=[.;?!])\s/)) if (OWNER_EN.test(s)) fails.push(`FAQ (en) names the owner in: "${s.slice(0, 140)}"`);
for (const s of faqAr.split(/(?<=[.؛؟!])\s/)) if (OWNER_AR.test(s)) fails.push(`FAQ (ar) names the owner in: "${s.slice(0, 140)}"`);

// 3. human / admin gates
// "role-gated admin areas" (access control) is not a gate TO a person, so the routing words must be
// followed by "to" / "by" and the person.
const GATE_EN = new RegExp('\\b(?:gated|routed?|routes|escalat\\w*|approved)\\s+(?:it\\s+)?(?:to|by)\\s+(?:a\\s+)?(?:hu' + 'man|person|ad' + 'min)\\b|\\bhu' + 'man(?:-approved| approval| oversight| control)\\b|a person approves|ad' + 'min authority', 'i');
for (const s of faqEn.split(/(?<=[.;?!])\s/)) if (GATE_EN.test(s)) fails.push(`FAQ (en) gates an action to a person: "${s.slice(0, 140)}"`);
const GATE_AR = new RegExp('إنسا' + 'ن|الإشراف البشر' + 'ي|الموافقة البشر' + 'ية|السيطرة البشر' + 'ية|سلطة الإدا' + 'رة|شخص ما يوا' + 'فق');
for (const s of faqAr.split(/(?<=[.؛؟!])\s/)) if (GATE_AR.test(s)) fails.push(`FAQ (ar) gates an action to a person: "${s.slice(0, 140)}"`);

// 4. working-day figures and refund windows
const nums = (t, re) => { const out = new Set(); for (const m of t.matchAll(re)) for (const g of m.slice(1)) if (g) out.add(Number(g)); return out; };
const EN_WD = /(\d+)\)?(?:\s*(?:[-–]|to)\s*(?:[a-z]+\s)?\(?(\d+)\)?)?[ -]working[ -]days?/gi;
const AR_WD = /(\d+)\)?(?:\s*-\s*(\d+))?\)?\s*(?:[؀-ۿ]+\s){0,2}عمل/g;
const legalEnDays = nums(legalEn, EN_WD), legalArDays = nums(legalAr, AR_WD);
for (const d of nums(faqEn, EN_WD)) if (!legalEnDays.has(d)) fails.push(`FAQ (en) quotes ${d} working days; no legal document does`);
for (const d of nums(faqAr, AR_WD)) if (!legalArDays.has(d)) fails.push(`FAQ (ar) quotes ${d} working days; no legal document does`);
if (new RegExp('refund ' + 'window', 'i').test(faqEn)) fails.push('FAQ (en) mentions a refund window; the Refund Policy has none');
if (faqAr.includes('نافذة ' + 'الاسترداد')) fails.push('FAQ (ar) mentions a refund window; the Refund Policy has none');

// 5. one working week
const WEEK_EN = new RegExp('\\bSun(?:day)?\\s*(?:to|-|–)\\s*Thu', 'i');
const WEEK_AR = 'الأحد إلى ' + 'الخميس';
for (const [where, t] of [['faq/en', faqEn], ['contact/en', text(mk.contact.en.html)], ['legal/en', legalEn]]) if (WEEK_EN.test(t)) fails.push(`${where} publishes a Sunday-to-Thursday week`);
for (const [where, t] of [['faq/ar', faqAr], ['contact/ar', text(mk.contact.ar.html)], ['legal/ar', legalAr]]) if (t.includes(WEEK_AR)) fails.push(`${where} publishes a Sunday-to-Thursday week`);

if (fails.length) { console.error('faq_matches_policies: FAIL\n  ' + fails.join('\n  ')); process.exit(1); }
console.log('faq_matches_policies: OK — no invented roles, no owner or person gates, every working-day figure is in the legal documents, one working week');
