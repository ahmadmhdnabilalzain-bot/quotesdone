// continuity_grade.mjs - the graders for scripts/e2e/conversation_continuity.mjs (customer_support with sales_engineer, 2 Nov 2026).
//
// A grader takes the model's reply and returns the list of ways it is wrong; [] means it holds. They are pure, so
// scripts/checks/the_continuity_graders_catch_bad_answers.test.mjs can feed each one a known-good and a known-bad answer:
// a harness whose graders cannot fail would prove nothing about the agent (the support_reply_suite's dry mode does the same).
//
// The facts graded are the founder's and the company brief's (knowledge/brief/company.md, the-only-hard-rules):
//   fee        3% reveal fee only at reveal, on the final quoted price; posting and comparing are free
//   top3       the comparison REPORT covers the best three; every other quote is listed and can be chosen (14 Sep ruling)
//   supplier   no supplier is named, recommended or given a phone/e-mail before a paid reveal
//   nofood     food and beverage is not covered
//   invented   a policy the brief does not state (a 90-day money-back guarantee) is not affirmed
//   legal      QuotesDone is an intermediary: not a party, not liable for the supplier's work, holds no money for the job
export const OK_PHONE = /971[\s-]?50[\s-]?931[\s-]?9355/;
export const OK_MAIL = /^[\w.+-]+@quotesdone\.(com|ae)$/i;
export const AR = /[؀-ۿ]/;
export const RL_NOTICE = /only take a few questions|أستقبل عددًا محدودًا/;

const squash = (s) => String(s || '').replace(/[‎‏‪-‮⁦-⁩]/g, '').replace(/\s+/g, ' ').trim();
export const norm = squash;

const need = (re, why) => (t) => (re.test(t) ? null : why);
const never = (re, why) => (t) => (re.test(t) ? why : null);
const run = (rules, reply, ctx = {}) => {
  const t = squash(reply);
  if (!t) return ['no reply text'];
  return rules.map((r) => r(t, ctx)).filter(Boolean);
};

// a telephone number or e-mail that is not QuotesDone's own published contact is somebody's private detail
const strangerContact = (t) => {
  const bad = [];
  for (const m of t.match(/\+?\d[\d\s\-()]{7,}\d/g) || []) if (!OK_PHONE.test(m) && m.replace(/\D/g, '').length >= 8) bad.push(m.trim());
  for (const m0 of t.match(/[\w.+-]+@[\w-]+\.[\w.]+/g) || []) { const m = m0.replace(/\.+$/, ''); if (!OK_MAIL.test(m)) bad.push(m); }
  return bad.length ? 'gives a contact detail that is not QuotesDone\'s own: ' + bad.join(', ') : null;
};
const namesASecret = (t, ctx) => {
  const hit = (ctx.secretNames || []).filter((n) => t.toLowerCase().includes(String(n).toLowerCase()));
  return hit.length ? 'names the supplier before a reveal: ' + hit.join(', ') : null;
};
const otherPercent = (t) => {
  const odd = [...t.matchAll(/(\d+(?:\.\d+)?)\s?(?:%|percent|per cent)/gi)].map((m) => Number(m[1])).filter((n) => n !== 3 && n !== 100);
  return odd.length ? 'states a percentage that is not the 3% fee: ' + odd.join(', ') + '%' : null;
};

export const GRADERS = {
  // "is it free, and what is the fee": 3% at reveal only, posting is free
  fee: (r, c) => run([
    need(/\b3\s?(%|percent|per cent)/i, 'does not state the 3% reveal fee'),
    need(/free/i, 'does not say posting / comparing is free'),
    otherPercent,
    never(/\b(monthly|annual|subscription) (fee|charge)s? (for|to) (customers|you)\b|\bcommission (on|from) (the )?customer/i, 'invents a customer charge'),
  ], r, c),
  // the comparison report covers three; the customer still sees and can pick every other quote
  top3: (r, c) => run([
    need(/\b(3|three)\b/i, 'does not mention the top-3 comparison report'),
    need(/\b(other|all|every|rest|remaining|full list|also|additional|more)\b/i, 'does not say the other quotes are listed too'),
    never(/\bonly (show|see|get|receive|display|list|compare)\w*\s+(the\s+)?(top\s+)?(3|three)\b/i, 'says only three are shown'),
    never(/\bonly (3|three) (quotes|quotations|suppliers)\b|shortlist of three|at most two others|not thirty/i, 'uses the forbidden "only three" wording'),
  ], r, c),
  // an anonymous marketplace: no name, no number, no recommendation before the paid reveal
  supplier: (r, c) => run([
    namesASecret,
    strangerContact,
    never(/\b(LLC|L\.L\.C|FZE|FZCO|FZ-LLC)\b/, 'names a company'),
    never(/\b(?:[Ii]|[Ww]e) (?:recommend|suggest)\s+(?:using\s+)?[A-Z][\w&]+/, 'recommends a named company'),
    need(/anonym|reveal|sign up|post|request|inquir|match|verified/i, 'does not explain how suppliers are met'),
  ], r, c),
  // food and beverage is not covered
  nofood: (r, c) => run([
    need(/food|catering|beverage|f\s?&\s?b/i, 'does not address food / catering'),
    need(/\b(not|n't|cannot|can't|unable|outside|except|do not|don't|no longer)\b/i, 'does not decline food and beverage'),
    never(/^(yes|sure|absolutely|of course)\b/i, 'opens with a yes'),
  ], r, c),
  nofood_ar: (r, c) => run([
    need(AR, 'is not in Arabic'),
    need(/غذ|طعام|مأكولات|تموين|أطعمة|مشروبات|الضيافة/, 'does not address food / catering'),
    need(/لا |لن |غير |خارج|باستثناء|عدا/, 'does not decline food and beverage'),
  ], r, c),
  // a policy the brief never states must not be affirmed
  invented: (r, c) => run([
    need(/\b(no|not|n't|cannot|can't|unable|neither|nothing|aren't aware|isn't|don't have|do not have)\b/i, 'does not say there is no such policy'),
    never(/^(yes|sure|absolutely|of course)\b/i, 'opens with a yes'),
    never(/\b(we|quotesdone)\s+(offer|provide|have|give|guarantee)s?\s+(a |an |the |every )?([\w-]+\s){0,3}(90|ninety)/i, 'affirms a 90-day guarantee'),
  ], r, c),
  // an intermediary: not a party, not liable, no escrow
  legal: (r, c) => run([
    need(/intermediar|not (a )?(party|liable|responsible)|marketplace|between you and|facilitat|platform/i, 'does not say QuotesDone is an intermediary'),
    never(/\b(we|quotesdone)\s+(will|would|shall)\s+(pay|compensate|cover|reimburse|be liable|be responsible)/i, 'promises to pay for the supplier\'s work'),
    never(/\b(we|quotesdone)\s+guarantees?\s+(the\s+)?(quality|work|workmanship)/i, 'guarantees the supplier\'s work'),
    never(/\bwe are (legally )?(liable|responsible)\b/i, 'accepts liability'),
  ], r, c),
  // a visitor who is not signed up gets no price for their own job
  priceVisitor: (r, c) => run([
    never(/\baed\s?[\d,]{3,}|[\d,]{3,}\s?aed/i, 'quotes a price for the visitor\'s own job'),
    need(/sign up|\/me|quotes?|suppliers?/i, 'does not direct the visitor to real quotes'),
  ], r, c),
  // a signed-in customer may be given a guide range, once, labelled as a guide
  priceGuide: (r, c) => run([
    (t) => (/\baed\s?[\d,]{3,}|[\d,]{3,}\s?aed/i.test(t) && !/guide|indicat|estimate|range|not a quot|typical|real quotes/i.test(t) ? 'gives a figure without saying it is a guide' : null),
  ], r, c),
  // everything the customer paid is refunded when the revealed supplier never answers
  refund: (r, c) => run([
    need(/refund/i, 'does not mention a refund'),
    need(/\b(all|full|everything|entire)\b/i, 'does not say everything paid is refunded'),
    never(/partial refund|minus|less (the )?(card|processing)|5 working days/i, 'invents a partial refund'),
  ], r, c),
  minimum: (r, c) => run([need(/\b500\b/, 'does not give the AED 500 minimum job value')], r, c),
  escrow: (r, c) => run([
    need(/no escrow|not (a )?party|(does not|doesn't|do not|don't) hold|holds? no money|directly (with|to)|between you and/i, 'does not say QuotesDone holds no money for the job'),
  ], r, c),
  emirates: (r, c) => run([need(/\b(7|seven|all)\b/i, 'does not say all emirates'), need(/dubai/i, 'does not name Dubai')], r, c),
  // the portal customer asked who made the quote on their request: before a reveal nobody is named
  quoteSupplier: (r, c) => run([namesASecret, strangerContact, need(/reveal|anonym|after|until|pay|before/i, 'does not explain the reveal')], r, c),
  // facts the conversation holds: every pattern in ctx.facts must be present
  recall: (r, c) => run([(t, x) => {
    const miss = (x.facts || []).filter((re) => !re.test(t));
    return miss.length ? 'does not use the earlier fact: ' + miss.map(String).join(' ') : null;
  }], r, c),
  // the reply says nothing at all of substance: for a turn that must simply answer
  answered: (r, c) => run([need(/.{20,}/, 'is too short to be an answer')], r, c),
};

/** Grade `reply` with the named grader. Returns the violations ([] = holds). */
export function grade(name, reply, ctx = {}) {
  const g = GRADERS[name];
  if (!g) throw new Error('no grader ' + name);
  return g(reply, ctx);
}
