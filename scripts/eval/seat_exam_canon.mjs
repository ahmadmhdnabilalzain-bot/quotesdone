// THE CANON A SEAT'S ANSWER IS GRADED AGAINST, BY CODE. Seat: ceo (company knowledge). 3 Nov 2026, qualification
// matrix gap #13 / row E14 (docs/release/qualification_matrix.md).
//
// The full seat-exam sweep (scripts/eval/seat_exam_sweep.mjs) grades every answer by code first. Two kinds of
// company fact are checked here, against the three places the company states them:
//   * src/content/company_facts.json (the one source for every fee, penalty and rate), through the same detectors the
//     repository check uses (scripts/legal/company_facts.mjs: findings + wrongWordings);
//   * knowledge/brief/company.md and knowledge/brief/seats.md (the settled facts every seat answers from), and
//     knowledge/COMPANY_CANON.md, through the claims below. Each claim names the line it comes from.
//
// A claim is either a VALUE (a stated number must equal the canon's) or a FORBIDDEN statement (a sentence the canon
// contradicts, such as "the founder approves refunds"). A forbidden statement is skipped when its own sentence negates
// it before the match ("no refund is automatic"). Every detector is narrow on purpose: it fires on the company's own
// fact, never on a general professional figure (a market's typical quote validity is not QuotesDone's 30 days).
//
// The same detectors run over the knowledge itself (seat packs, seat cards, the briefs, the canon, the exam keys), so
// a wrong source is found before any model is asked. Pure: no token, no database, no model.
import { findings, wrongWordings, loadFacts, plain } from '../legal/company_facts.mjs';

// The last version a legacy figure applies to (company_facts.json legacy.applies_to): AED 250 up to v12, 9% up to v13.
const LEGACY_MAX = { nonresponse_admin_fee_aed: 12, late_interest_pct_pa: 13 };
function isLegacyContext(win, fact) {
  const vs = [...win.matchAll(/\bv(?:ersion)?\s?(\d{1,2})\b/gi)].map((m) => Number(m[1]));
  if (vs.length) return vs[vs.length - 1] <= (LEGACY_MAX[fact] ?? 13);
  return /\b(?:earlier|older|legacy|previous) (?:version|agreement)\b|\bsigned before\b/i.test(win);
}
const LEGACY = /\b(?:v(?:ersion)?\s?(?:9|1[0-3])\b|(?:12|13|thirteen|twelve)\s+or\s+earlier|earlier (?:version|agreement)|older (?:version|agreement)|legacy|signed before)/i;
const BORNE = /^\s*(?:cost|costs|charges?|fees?)?\s*(?:is|are)\s+(?:booked|borne|absorbed|recorded|expensed|paid by QuotesDone)\b/i;
const NEG = /\b(?:no|not|never|none|nothing|without|neither|nor|cannot)\b|n't\b/i;
const num = (s) => Number(String(s).replace(/,/g, ''));

/** VALUE claims: every number a detector captures must be one of `want`. `legacy`: a sentence that names an earlier
 *  signed version may state that version's figure. */
export const VALUE_CLAIMS = [
  { id: 'bank_refund_days', canon: 'company.md §5 "Banks take 7–14 working days"; COMPANY_CANON Refunds', want: [7, 14],
    re: [/\bbanks?\b[^.]{0,80}?\b(\d+)\s?(?:–|-|to)\s?(\d+)\s+(?:working|business|banking)\s+days/gi,
         /\brefunds?\b[^.]{0,60}?\b(?:show|appear|reflect|land|arrive)\w*[^.]{0,30}?\b(\d+)\s?(?:–|-|to)\s?(\d+)\s+(?:working|business|banking)\s+days/gi,
         /\b(?:customers?|buyers?|she|he|they)\b[^.]{0,40}?\bsees?\b[^.]{0,40}?\b(?:credit|refund|amount)\b[^.]{0,30}?\b(\d+)\s?(?:–|-|to)\s?(\d+)\s+(?:working|business|banking)\s+days/gi],
    // Stripe's own guide says 5–10 business days; an entry may quote it beside the Terms' figure.
    except: /\bStripe(?:'s)?\s+(?:own\s+)?(?:guide|documentation|docs|says|states)\b/i },
  { id: 'supplier_approval_days', canon: 'company.md §3.3 "within 3 working days of complete documents" (SA§13)', want: [3],
    re: [/within (\d+) working days of (?:complete|receiving complete|full) documents/gi] },
  { id: 'nonresponse_window_days', canon: 'company.md §3.7/§5: the revealed supplier must begin responding within 5 working days', want: [5],
    re: [/(?:begin|start) respond\w* within (\d+) working days/gi, /revealed supplier[^.]{0,60}?(\d+) working days to respond/gi] },
  { id: 'nonresponse_chase_day', canon: 'company.md §5: day 3 (working) QuotesDone chases the supplier, copying the customer', want: [3],
    re: [/\bchases?\b[^.]{0,30}?\bat (?:day |working day )?(\d+)(?! to)\b(?: working days?)?/gi, /\bday (\d+)\b[^.]{0,25}\bchase/gi] },
  { id: 'ceo_final_call_day', canon: 'company.md §5: day 5 the case goes to QuotesDone\'s CEO for a final call', want: [5],
    re: [/\bday (\d+)\b[^.,;(]{0,50}\bCEO\b[^.,;]{0,20}final call/gi, /\bCEO\b[^.,;]{0,30}final call (?:at|on) (?:working )?day (\d+)\b/gi] },
  { id: 'inquiry_edit_hours', canon: 'company.md §2 "edit an inquiry within 24 hours"', want: [24],
    re: [/\bedit\w*\s+(?:an?\s+|the\s+|your\s+)?(?:inquiry|request|RFQ)[^.]{0,20}within (\d+) hours/gi] },
  { id: 'minimum_job_aed', canon: 'company.md §1 "The minimum job value is AED 500"', want: [500],
    re: [/minimum job(?: value)?(?: is| of)?\s+AED\s?([\d,]+)/gi] },
  { id: 'complaint_ack_days', canon: 'company.md §5 "acknowledged within 2 working days" (CT§18)', want: [2],
    re: [/complaint[^.]{0,60}?acknowledg\w* within (\d+) working days/gi] },
  { id: 'complaint_response_days', canon: 'company.md §5 "substantive response within 10 working days" (CT§18)', want: [10],
    re: [/substantive (?:response|reply|answer) within (\d+) working days/gi] },
  { id: 'liability_cap_aed', canon: 'company.md §6 "the greater of the reveal fees paid in the prior 12 months and AED 1,000" (CT§9)', want: [1000],
    re: [/greater of the reveal fees[^.]{0,60}?AED\s?([\d,]+)/gi] },
  { id: 'quote_validity_days', canon: 'company.md §3.6 "valid 30 days from submission" (SA§12)', want: [30],
    re: [/valid(?:ity)?(?: is| of| for)?\s+(\d+)\s+days from submission/gi] },
  { id: 'vat_mandatory_threshold_aed', canon: 'seats.md "the FTA mandatory threshold of AED 375,000"', want: [375000],
    re: [/mandatory (?:VAT )?(?:registration )?threshold(?: is| of)?\s+(?:of\s+)?AED\s?([\d,]+)/gi, /AED\s?([\d,]+)[^.]{0,30}\bmandatory (?:VAT )?(?:registration )?threshold/gi] },
  { id: 'vat_voluntary_threshold_aed', canon: 'seats.md "AED 187,500 is only the voluntary threshold"', want: [187500],
    re: [/voluntary (?:VAT )?(?:registration )?threshold(?: is| of)?\s+(?:of\s+)?AED\s?([\d,]+)/gi, /AED\s?([\d,]+)[^.]{0,30}\bvoluntary (?:VAT )?(?:registration )?threshold/gi] },
  { id: 'bank_account_fee_aed', canon: 'seats.md "The account fee is AED 199 a month plus AED 9.95 VAT"', want: [199],
    re: [/Mashreq[^.]{0,80}?account fee(?: is)?\s+AED\s?([\d,.]+)/gi, /account fee(?: is)?\s+AED\s?([\d,.]+)\s+a month/gi] },
  { id: 'consumer_hotline', canon: 'company.md §5 "Ministry of Economy consumer hotline 800 1222"', want: [8001222],
    re: [/consumer (?:protection )?hotline[^.]{0,20}?\b(800\s?\d{4})\b/gi] },
];

/** FORBIDDEN statements: a sentence the canon contradicts. */
export const FORBIDDEN_CLAIMS = [
  { id: 'founder_decides_refunds', canon: 'company.md §5 "Every refund is decided by QuotesDone\'s CEO"; seats.md "Every approval is the CEO seat\'s, refunds included"',
    re: /\b(?:the )?founder\b(?:(?!\bCEO\b|\bnotified\b|\binformed\b)[^.]){0,50}\b(?:approves?|decides?|signs? off|authori[sz]es?)\b[^.]{0,40}\brefunds?\b|\brefunds?\b[^.]{0,50}\b(?:approved|decided|signed off|authori[sz]ed)\s+by\s+(?:the\s+)?founder\b/gi },
  { id: 'automatic_refund', canon: 'company.md §5 "Every refund is decided by QuotesDone\'s CEO … None is automatic"; Customer Terms v11 clause 5 "no refund is automatic"',
    re: /\bautomatic(?:ally)?\s+(?:[\w-]+\s+){0,2}refunds?\b|\brefund(?:s|ed)?\b[^.;:?!]{0,45}?\bautomatic(?:ally)?\b|\bautomatically\s+(?:\w+\s+){0,2}refund(?:ed|s)?\b|\brefunds?\s+you\s+automatically\b|\bmoney\s+back\s+automatically\b|\btriggers?\s+(?:a\s+|an\s+)?(?:full\s+)?refund\s+automatically\b/gi,
    // the LADDER (the clock, the chase) runs by itself; that is not the refund being automatic (Refund Policy v1.9 s4)
    except: /\b(?:ladder|clock)\s+(?:above\s+)?runs?\s+automatically\b|\btracks?\s+(?:every|each)\s+reveal\b/i },
  { id: 'quotesdone_vat_registered', canon: 'company.md §4 "QuotesDone is not VAT-registered"',
    re: /\bQuotesDone\s+(?:is|has been)\s+VAT[- ]registered\b|\bQuotesDone\s+charges?\s+VAT\b|\bVAT\b[^.;]{0,25}\b(?:is\s+)?(?:charged|added)\b[^.;]{0,30}\b(?:reveal|unlock)\s+fee\b|\b(?:we|QuotesDone)\s+(?:add|charge)s?\s+(?:\d+\s?%\s+)?VAT\b/gi,
    // "applies only AFTER QuotesDone is VAT registered" is a condition, not a claim that it is.
    except: /\b(?:after|once|until|unless|if|when|before|whether)\s+(?:QuotesDone|it|we)\s+(?:is|becomes|has been|registers)/i },
  { id: 'card_cost_passed_to_customer', canon: 'company.md §4 "Card fee / surcharge on the reveal fee: None. QuotesDone bears Stripe\'s charges itself" (Cabinet Resolution 66/2023 Art. 5(3))',
    re: /\b(?:card|processing|processor|Stripe)\s+(?:fees?|costs?|charges?)\b[^.;]{0,30}\b(?:passed|added|charged|billed)\s+(?:on\s+)?to\s+the\s+(?:customer|buyer)\b|\bas\s+a\s+card\s+surcharge\b|\bcard\s+surcharge\s+(?:is\s+)?(?:added|applies|charged)\b/gi },
  { id: 'departments_exist', canon: 'seats.md "There are six seats and no departments"',
    re: /\b(?:\d+|ten|nine|eight|seven|several)\s+(?:AI[- ])?departments\b/gi },
  { id: 'quotesdone_holds_job_money', canon: 'company.md §2.8 "QuotesDone … holds no money for the job (no escrow)"',
    re: /\bQuotesDone\s+(?:holds|keeps|retains)\s+(?:the\s+)?(?:job(?:'s)?\s+|customer'?s?\s+|buyer'?s?\s+)?(?:money|funds|payment)\s+(?:in escrow|until)/gi },
  { id: 'quotesdone_takes_commission', canon: 'company.md §4 "Commission on won work: None"',
    re: /\bQuotesDone\s+(?:takes|charges|earns)\s+(?:a\s+)?(?:\d+\s?%\s+)?commission\b/gi },
  { id: 'interest_from_refund_date', canon: 'company.md §5 "12% p.a. simple interest … from the due date — payable within 7 days of notice" (Supplier Agreement clauses 31, 33)',
    re: /\binterest\b[^.]{0,200}?\bfrom the (?:refund|reveal|payment) date\b/gi },
  { id: 'free_tier_has_end_date', canon: 'company.md §4 "The free-1,000 offer has no end date … Never quote a date"',
    re: /\bfree\s+until\s+\d{1,2}\s+[A-Z][a-z]+\s+20\d\d\b/g,
    // company.md quotes the superseded note in order to rule it out.
    except: /\b(?:earlier|superseded|withdrawn|replaced|older|never quote)\b/i },
];

const sentenceAround = (t, i) => {
  const s = Math.max(t.lastIndexOf('. ', i), t.lastIndexOf('\n', i), t.lastIndexOf('; ', i), t.lastIndexOf('? ', i), t.lastIndexOf('! ', i)) + 1;
  return t.slice(s, i);
};

const sentenceTail = (t, i) => {
  const ends = ['. ', '\n', '; ', '? ', '! '].map((x) => t.indexOf(x, i)).filter((x) => x >= 0);
  return t.slice(i, ends.length ? Math.min(...ends) : t.length);
};

/** Every place `text` contradicts the canon: [{claim, kind, got, want, text}]. */
export function canonFindings(text) {
  const t = String(text ?? '');
  const out = [];
  const facts = loadFacts().facts;
  const P = plain(t);
  for (const f of findings(t)) {
    // A supplier bound by an earlier signed version owes that version's figure (company_facts.json `legacy`, clause 33
    // as signed): AED 250 or 9% is right when the same sentence names the earlier version it applies to.
    const leg = facts[f.fact]?.legacy?.value;
    // The version may be named a clause or a sentence before ("… v12 or earlier; … The interest for such a supplier is
    // 9%"), so the window is the 250 characters before the figure and the rest of its sentence.
    // findings() indexes the tag-stripped, whitespace-collapsed text, so the window is read from that text; and the
    // NEAREST version named before the figure decides ("v12 … AED 250. A supplier on v17 owes AED 250" is not excused).
    if (leg != null && f.got === leg && isLegacyContext(P.slice(Math.max(0, f.at - 250), f.at), f.fact)) continue;
    out.push({ claim: `company_facts.${f.fact}`, kind: 'value', got: f.got, want: f.want, text: f.text });
  }
  for (const w of wrongWordings(t)) {
    // "the full fee and the processing cost is booked separately" describes QuotesDone's own cost, not a surcharge.
    const i = t.indexOf(w.text);
    if (w.rule === 'no_card_fee' && i >= 0 && BORNE.test(sentenceTail(t, i + w.text.length).slice(0, 60))) continue;
    out.push({ claim: `company_facts.${w.rule}`, kind: 'wording', got: w.text, want: w.say, text: w.text });
  }
  for (const c of VALUE_CLAIMS) for (const re of c.re) {
    re.lastIndex = 0;
    for (const m of t.matchAll(re)) {
      const got = m.slice(1).filter((x) => x != null).map((x) => num(String(x).replace(/\s/g, '')));
      const bad = got.filter((g) => !c.want.includes(g));
      if (bad.length && c.except && c.except.test(sentenceAround(t, m.index) + m[0] + sentenceTail(t, m.index + m[0].length))) continue;
      if (bad.length) out.push({ claim: c.id, kind: 'value', got: got.join('–'), want: c.want.join('–'), text: m[0].slice(0, 160), canon: c.canon });
    }
  }
  for (const c of FORBIDDEN_CLAIMS) {
    c.re.lastIndex = 0;
    for (const m of t.matchAll(c.re)) {
      const before = sentenceAround(t, m.index);
      // Negation counts only where it governs the claim: inside it, or in the few words just before it ("no automatic
      // refund"). A negation elsewhere in the sentence ("if the supplier does NOT respond, the refund is automatic")
      // does not excuse it.
      // The window stops at the clause: "Don't worry, the refund is automatic" is NOT excused by "Don't".
      const clause = before.slice(-24).split(/[,:;—–]|\s-\s/).pop();
      if (NEG.test(clause + m[0])) continue;
      const tail = sentenceTail(t, m.index + m[0].length);
      if (c.except && c.except.test(before + m[0] + tail)) continue;
      if (t[m.index + m[0].length + tail.length] === '?') continue;   // a question asks; it does not state
      out.push({ claim: c.id, kind: 'forbidden', got: m[0], want: 'not stated', text: m[0].slice(0, 160), canon: c.canon });
    }
  }
  return out;
}

/** ARABIC (the Arabic text prevails, CT§22): the same refund facts, in the forms the packs use. */
export const ARABIC_CLAIMS = [
  { id: 'automatic_refund_ar', canon: 'Customer Terms v11 clause 5 (Arabic): no refund is automatic',
    re: /(?:استرداد|استردادات|يُ?رد|يُ?ردّ|رُدّ|تُرد|تُردّ|المبلغ)[^.؛،]{0,50}تلقائ(?:ي|ياً|يا|ية)|تلقائ(?:ي|ياً|يا)[^.؛،]{0,20}(?:استرداد|يُ?رد)/g,
    neg: /(?:^|[\s(])(?:و?لا|و?ليس|و?غير|و?دون)(?:\s|$)/ },
  { id: 'interest_from_refund_date_ar', canon: 'Supplier Agreement clauses 31, 33: interest runs from the due date',
    re: /فائدة[^.]{0,220}?من تاريخ (?:الرد|الاسترداد|الكشف|الدفع) حتى/g },
  { id: 'bank_refund_days_ar', canon: 'Customer Terms v11 clause 5: seven (7) to fourteen (14) working days',
    re: /(?<!دليل Stripe[^.]{0,40})(?:\b5|٥)\s*(?:إلى|-|–)\s*(?:10|١٠)\s*أيام\s*عمل/g },
];
export function arabicFindings(text) {
  const t = String(text ?? ''), out = [];
  for (const c of ARABIC_CLAIMS) for (const m of t.matchAll(c.re)) {
    const before = t.slice(Math.max(0, m.index - 30), m.index);
    if (c.neg && c.neg.test(before.split(/[،؛:]/).pop() + ' ' + m[0])) continue;
    out.push({ claim: c.id, kind: 'forbidden', got: m[0], want: 'not stated', text: m[0].slice(0, 160), canon: c.canon });
  }
  return out;
}

/** The money, fee, terms and legal items carry the 100% bar (matrix row E14). Decided from the item's own words. */
const MONEY_TERMS = /\bAED\b|%|\bfees?\b|\bpric(?:e|es|ing)\b|\bcosts?\b|\brefund|\breveal\b|\bVAT\b|\btax|\binterest\b|\bpenalt|\bcharges?\b|\binvoic|\bpayments?\b|\bpaid\b|\brevenue|\bsubscription|\bcommission|\bdiscount|\bcompensation|\bchargeback|\bterms\b|\bagreement\b|\bcontract|\bclause|\bliabil|\blegal|\blaw\b|\bdecree|\bresolution\b|\bPDPL\b|\bprivacy|\bretention|\bconsent\b|\bindemn|\bwarrant(?:y|ies)\b|\bdispute/i;
export const isMoneyOrTerms = (it) => MONEY_TERMS.test([it.q_en, ...(it.answer_must ?? []), ...(it.expected_facts ?? [])].join(' '));

/** Figures an answer states (AED amounts and percentages), each as a bare number string. */
export function figuresOf(text) {
  const t = String(text ?? '');
  const out = new Set();
  for (const m of t.matchAll(/\bAED\s?([\d,]+(?:\.\d+)?)\s?(k|K|m|M|million|thousand)?\b/g)) out.add(`AED ${m[1].replace(/,/g, '')}${m[2] ? m[2][0].toLowerCase() : ''}`);
  for (const m of t.matchAll(/(\d+(?:\.\d+)?)\s?(?:%|per ?cent\b)/gi)) out.add(`${m[1]}%`);
  for (const m of t.matchAll(/\b([\d,]+(?:\.\d+)?)\s?(?:AED|dirhams?)\b/gi)) out.add(`AED ${m[1].replace(/,/g, '')}`);
  return [...out];
}

/** A figure the answer states that nothing the seat was given states: a possible invention, sent to the judge. */
// The context is compared as FIGURES, never as bare numbers: matched as a bare number anywhere in the ~25k-character
// settled facts, an invented "2% handling fee" passed (review of 3 Nov 2026), because some 2 appears somewhere.
export function unsupportedFigures(answer, context) {
  const have = new Set(figuresOf(context));
  return figuresOf(answer).filter((f) => !have.has(f));
}
