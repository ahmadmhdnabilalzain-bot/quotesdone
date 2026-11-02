// The QuotesDone document template — the letterhead and footer every generated PDF wears.
//
// WHY IT IS A FILE AND NOT A CONSTANT INSIDE pdf_native (9 Sep 2026, agent: sales_engineer).
// The founder asked on 9 Sep for signed T&C copies "with our letter head and footer (quotesdone
// template). if the template is not built then it has to be". The BEHAVIOUR was built —
// pdf_native's `options.letterhead` has drawn a navy band, a lockup, a gold rule and a two-line
// footer since v14 — but the words in it were a hardcoded `const CO` inside that one function, so
// (a) nothing else could reuse it, and (b) it could not be checked against what the company
// actually publishes. Two of its lines were measurably wrong on 9 Sep:
//
//   CO.licence  said 'DET E-Trader Licence No. 1633275'
//               public.company_registration says license_type 'Trader License', authority
//               'Department of Economy and Tourism - Dubai (DET)'. There is no "E-Trader" licence.
//               The number 1633275 was right; the class printed beside it was not.
//   the lockup  was placed by WIDTH (128pt), which public.company_brand forbids twice over:
//               logo.sizing_unit 'HEIGHT, never width' and logo.never_size_by_width 'Do not set
//               width on a lockup and let the height follow.' It also used the 1859x460 master,
//               which is 38% ink and 62% empty alpha, so 128pt of box rendered ~12pt of wordmark.
//
// So: the identity is READ, from public.company_registration (the licence, verbatim) and
// public.company_brand (the sizing rule and the document logo height), and the lockup is the
// TRIMMED 1612x180 derivative sized by height. Nothing here is invented; every field below names
// the row it comes from. FALLBACK exists only so a database blip degrades a letterhead rather than
// blanking one — it is today's measured values, not a guess.
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

export type DocIdentity = {
  /** company_registration.trade_name, title-cased. */
  name: string;
  /** company_registration.license_type + license_no, as the licence itself reads. */
  licence: string;
  /** Not on the licence (it is a home-registered DE@AE Tier 1 business with no public address). */
  city: string;
  /** The published contact channel, NOT company_registration.registered_mobile: the registered
   * mobile is the DET record for the owner, the published pair is what a reader should use. Both
   * are real; a letterhead prints the one you may call. */
  email: string;
  phone: string;
  /** The calling number (ledger 1482). `phone` is the WhatsApp number and is never called. */
  callPhone: string;
  web: string;
  signer: string;
  title: string;
  /** The TDRA No-Objection Letter the company trades under. Stated by the founder in the 14 Sep
   * 2026 brief ("legal footer: QuotesDone Technologies, DET licence 1633275, TDRA
   * NOL-26-100000665"); no table carries it, so it is not read — it lives here, once. */
  permit: string;
  /** company_brand logo.height_document, in points. */
  logoPt: number;
  /** Where each value came from, so a reader of a response can check rather than trust. */
  source: 'company_registration' | 'fallback';
};

/** Today's measured values (9 Sep 2026). Used only when the read fails. */
export const FALLBACK: DocIdentity = {
  name: 'QuotesDone Technologies',
  licence: 'DET Trader License No. 1633275',
  city: 'Dubai, United Arab Emirates',
  email: 'management@quotesdone.com',
  phone: '+1 218 316 6814',
  callPhone: '+971 56 791 8605',
  // 21 Sep 2026 (customer audit, finding 12): the documents print the TDRA-permitted host the company
  // trades under in the UAE (NOL-26-100000665 is issued for www.quotesdone.ae; UAE visitors are served
  // there). The email stays management@quotesdone.com: measured 21 Sep 2026, it is the one address
  // the site publishes (src/content/company.json, legal.json) and company_registration.registered_email.
  web: 'quotesdone.ae',
  signer: 'Ahmad Alzain',
  title: 'Founder & Managing Director',
  permit: 'TDRA NOL-26-100000665',
  logoPt: 20,
  source: 'fallback',
};

/**
 * The licence line in the document's language (22 Sep 2026, audit finding 4). The licence and permit
 * NUMBERS are codes and stay as written; every word around them is Arabic on an Arabic document.
 */
export function licenceLine(id: DocIdentity, lang: 'en' | 'ar'): string {
  if (lang !== 'ar') return `${id.licence} · ${id.permit}`;
  const no = (id.licence.match(/\d{5,}/) || [''])[0];
  // 22 Sep 2026 (DL-08): the authority's own Arabic name is «هيئة تنظيم الاتصالات والحكومة الرقمية» —
  // it took the digital-government mandate in 2021 and the short form names a body that no longer exists.
  return `رخصة تاجر رقم ${no} · خطاب عدم ممانعة هيئة تنظيم الاتصالات والحكومة الرقمية ${id.permit.replace(/^TDRA\s*/, '')}`;
}

/** The trimmed lockup (1612x180, 98% ink) — the only one that may be sized by height. */
export const LOCKUP = {
  dark: 'kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png',
  light: 'kit/05_Logo_Lockups/horizontal_OnLight_trimmed.png',
  aspect: 1612 / 180,
} as const;

/**
 * company_registration.trade_name is stored as DET holds it, lower case: 'quotesdone technologies'.
 * Title-casing alone produced 'Quotesdone Technologies' on the first probe (9 Sep 2026) — which is
 * the wordmark misspelt on the company's own letterhead. The intercap is not decoration; it is what
 * public.company_brand logo.lockup and voice.wording both spell. Restore it explicitly.
 */
function titleCase(s: string): string {
  return String(s || '').replace(/\S+/g, (w) => w[0].toUpperCase() + w.slice(1))
    .replace(/\bQuotesdone\b/g, 'QuotesDone');
}

let cached: DocIdentity | null = null;

/**
 * The letterhead identity, read from the database. Cached for the life of the isolate: this is
 * licence data, it changes once a year, and a per-PDF round trip buys nothing.
 */
// deno-lint-ignore no-explicit-any
export async function docIdentity(admin: SupabaseClient<any, any, any>): Promise<DocIdentity> {
  if (cached) return cached;
  const out: DocIdentity = { ...FALLBACK };
  try {
    const { data: reg } = await admin.from('company_registration')
      .select('trade_name,license_type,license_no,registered_email')
      .order('recorded_at', { ascending: false }).limit(1).maybeSingle();
    if (reg?.license_no) {
      out.name = titleCase(String(reg.trade_name || '')) || FALLBACK.name;
      // 'Trader License No. 1633275' — the class the licence itself carries, prefixed with the
      // issuing authority's initials the way a UAE letterhead reads.
      out.licence = 'DET ' + String(reg.license_type || 'Licence') + ' No. ' + String(reg.license_no);
      out.email = String(reg.registered_email || FALLBACK.email);
      out.source = 'company_registration';
    }
  } catch (_e) { /* fallback stands */ }
  try {
    const { data: b } = await admin.from('company_brand').select('key,value').eq('key', 'logo.height_document').maybeSingle();
    const n = parseFloat(String(b?.value || '').replace(/[^0-9.]/g, ''));
    if (n > 0 && n < 200) out.logoPt = n;
  } catch (_e) { /* keep 20 */ }
  cached = out;
  return out;
}

/** The two footer lines: the legal line (who issues the document and under which licence and
 * permit), then where to reach us. */
export function footerLines(id: DocIdentity): [string, string] {
  return [`${id.name} · ${id.licence} · ${id.permit}`, `${id.city} · ${id.email} · WhatsApp ${id.phone} · ${id.callPhone} · ${id.web}`];
}

/** The same two lines for an Arabic document (14 Sep 2026: the founder asked for the Arabic
 * documents to be Arabic throughout). The trade name, licence number, permit number, email, phone
 * and web address are proper nouns and codes and stay as written; the words around them are Arabic. */
export function footerLinesAr(id: DocIdentity): [string, string] {
  const no = (id.licence.match(/\d{5,}/) || [''])[0];
  const permit = id.permit.replace(/^TDRA\s*/, '');
  // 22 Sep 2026 (DL-08): the authority's full Arabic name, and the Latin acronym TDRA dropped with it.
  // Measured through the real renderer (scripts/checks/legal_pdfs_have_no_overlapping_text.test.mjs):
  // the review of PR #857 measured origin/main as clearing the page number by 37.3pt (not broken to
  // begin with, which is why this is a regression and not a pre-existing fault); writing the name in
  // full while keeping the acronym overran it by 5.7pt and collided on ALL 11 Arabic pages of the
  // fourteen supplier-charge documents — every Arabic page, not a subset. Dropping the acronym clears
  // it again. The acronym is the English short form of the authority the line has just named in
  // Arabic; the permit NUMBER is the code that identifies the document and stays.
  return [`${id.name} · رخصة تاجر من دائرة الاقتصاد والسياحة في دبي رقم ${no} · خطاب عدم ممانعة هيئة تنظيم الاتصالات والحكومة الرقمية ${permit}`,
    `دبي، الإمارات العربية المتحدة · ${id.email} · واتساب ${id.phone} · ${id.callPhone} · ${id.web}`];
}

/**
 * Lockup width for a height. HEIGHT IS THE INPUT — never set both, and never set the width and let
 * the height follow (public.company_brand logo.never_size_by_width).
 */
export function lockupWidthFor(heightPt: number): number {
  return heightPt * LOCKUP.aspect;
}
