// THE CUSTOMER FOLLOW-UP SCENARIO BANK (customer_support, 16 Nov 2026; founder ledger 1711).
//
// The founder: "he opens a chat later on WhatsApp and he says, 'What happened with my inquiry? Did you find anyone below
// 5,000?' ... I don't want the system to be rule-based only, like 1 + 1 = 2. No, it's scenarios ... 1,000 scenarios".
// This is the bank of scenarios, not a rule table: 45 follow-up messages a UAE customer sends after requesting, in English,
// Arabic, Gulf dialect, Arabizi and a mix, about five ZZ DEMO requests that cover the states that matter (three quotes around
// his budget, one quote, none yet, all over budget, one revealed with a budget in another currency). For each, what a correct
// answer must and must not contain. Nothing here decides an answer: the model reasons over the facts
// (public.fn_customer_inquiry_facts, scripts/sql/a_customer_is_answered_from_his_whole_request_on_every_channel.sql) under
// _shared/own_request_facts.ts OWN_REQUEST_RULE.
//
// Two uses:
//   1. DETERMINISTIC (no model): scripts/checks/a_customer_is_answered_from_his_whole_request.test.mjs builds FIXTURE in a local
//      Postgres (rolled back), reads the WhatsApp fact pack and proves every fact each scenario needs is in it, and that no
//      unrevealed supplier, planted phone or planted brand is.
//   2. PAID, ONCE: scripts/eval/customer_follow_up/run.ts sends each scenario through the WhatsApp reply path's model
//      (wa_inbound compose.ts + model_says.ts, the production gateway) and a judge of another model family, capped at USD 1.50.
//
// Every party is ZZ DEMO on @example.invalid; the customer's number is in the reserved fixture range (+971 50 000 00xx,
// _shared/demo_identity.ts), so nothing can reach a person.

export const CUSTOMER = { name: 'ZZ DEMO Rashid Fixture', email: 'zz-demo-casefacts-c1@example.invalid', phone: '+971500000071', locale: 'en' };

// Suppliers. The names are what must never appear before a reveal; s5 is revealed on CCTV and may be named there.
export const SUPPLIERS = {
  s1: 'ZZ DEMO Cool Breeze Trading', s2: 'ZZ DEMO Arctic Line Contracting', s3: 'ZZ DEMO Polar Star Technical',
  s4: 'ZZ DEMO Brushwork Painting', s5: 'ZZ DEMO Secure Eye LLC', s6: 'ZZ DEMO Falcon Watch Systems',
  s7: 'ZZ DEMO Oak and Stone Kitchens', s8: 'ZZ DEMO Marble Craft Interiors',
};
// Planted in a quote's own words; the facts must not carry them before the reveal.
export const PLANTED = { phone: '050 000 0111', ownBrand: 'Midea', ownBrand2: 'Mitsubishi Heavy' };

// The five requests. budget is stored exactly as the customer said it (inquiries.budget is his words).
export const REQUESTS = {
  AC: { category: 'hvac', emirate: 'Dubai', status: 'quoted', sent_hours_ago: 20, summary: 'ZZ DEMO supply and install 3 split AC units for a villa',
    budget: 'AED 5,000 excluding VAT', required_by_days: 5, delivery_window: 'before next Friday',
    site: 'ZZ DEMO Villa 15, Al Barsha 2, Dubai',
    display: [{ key: 'material.units', label: 'AC units', value: 'Daikin' }, { key: 'installation', label: 'Installation', value: 'Yes, install it' },
      { key: 'warranty', label: 'Warranty', value: 'Yes, at least 2 years' }],
    matched: ['s1', 's2', 's3'],
    quotes: [
      { s: 's1', ex: 4600, vat: 'exclusive', vat_amount: 230, lead: '3 days', warranty: '2 years, call 050 000 0111 for service', validity: '30 days', valid_days: 30, brand: 'Midea',
        notes: [{ code: 'brand_tier_lower', severity: 'high', en: 'Quotes a mid-range Chinese brand where a premium Japanese brand was asked.', ar: 'يعرض علامة صينية متوسطة بدل علامة يابانية ممتازة مطلوبة.' }] },
      { s: 's2', ex: 4900, vat: 'exclusive', vat_amount: 245, lead: '7 days', warranty: '1 year, Mitsubishi Heavy compressor 5 years', validity: '15 days', valid_days: 15, brand: 'Mitsubishi Heavy',
        notes: [{ code: 'warranty_short', severity: 'medium', en: 'Warranty of 1 year is shorter than the 2 years asked.', ar: 'الضمان سنة واحدة أقصر من السنتين المطلوبتين.' }] },
      { s: 's3', ex: 6200, vat: 'exclusive', vat_amount: 310, lead: '2 days', warranty: '3 years', validity: '30 days', valid_days: 30, brand: 'Daikin', notes: [] },
    ],
    note_after: 'Two of the units are for bedrooms and one for the living room.',
    thread: [{ s: 's2', q: 'Is the living room unit wall-mounted or ducted?', a: 'Wall-mounted, please.' }],
    // REVIEW 16 Nov: no comparison in the facts (the cache holds raw model output; the portal is its one door).
  },
  PAINT: { category: 'painting', emirate: 'Dubai', status: 'quoted', sent_hours_ago: 30, summary: 'ZZ DEMO paint a two-bedroom apartment interior',
    budget: 'around 3k', required_by_days: 14, matched: ['s4', 's1', 's2'],
    quotes: [{ s: 's4', ex: 3400, vat: null, vat_amount: null, lead: '5 days', warranty: '6 months', validity: '14 days', valid_days: 14, brand: null, notes: [] }] },
  FLOOR: { category: 'flooring', emirate: 'Sharjah', status: 'sent', sent_hours_ago: 2, summary: 'ZZ DEMO porcelain tiles for a 120 m2 apartment',
    budget: 'AED 12,000 - 15,000 incl. VAT', required_by_days: 21, matched: ['s7', 's8', 's3'], quotes: [] },
  KITCHEN: { category: 'kitchen', emirate: 'Abu Dhabi', status: 'quoted', sent_hours_ago: 40, summary: 'ZZ DEMO new kitchen cabinets and worktop',
    budget: 'AED 20,000', required_by_days: 45, matched: ['s7', 's8'],
    thread: [{ s: 's8', q: 'Would a quartz worktop made in Italy instead of granite be acceptable?', a: 'Yes, Italian quartz is fine.' }],
    quotes: [
      { s: 's7', ex: 26500, vat: 'exclusive', vat_amount: 1325, lead: '4 weeks', warranty: '2 years', validity: '30 days', valid_days: 30, brand: null, notes: [] },
      { s: 's8', ex: 31000, vat: 'exclusive', vat_amount: 1550, lead: '6 weeks', warranty: '5 years', validity: '30 days', valid_days: 30, brand: null, notes: [] }] },
  CCTV: { category: 'cctv', emirate: 'Ajman', status: 'revealed', sent_hours_ago: 72, summary: 'ZZ DEMO 8 camera CCTV for a warehouse',
    budget: 'USD 2,500', required_by_days: 10, matched: ['s5', 's6'],
    quotes: [
      { s: 's5', ex: 7400, vat: 'not_registered', vat_amount: null, lead: '4 days', warranty: '1 year', validity: '30 days', valid_days: 30, brand: null, notes: [], revealed: true },
      { s: 's6', ex: 8900, vat: 'exclusive', vat_amount: 445, lead: '6 days', warranty: '2 years', validity: '30 days', valid_days: 30, brand: null, notes: [] }] },
};

// HIS CASE TIMELINE (fn_contact_timeline's shape, newest first): the WhatsApp turn, the widget, and since 16 Nov the portal chat
// and the e-mail reply read it (who-knows-what gaps 3 and 4). Scenarios with timeline: true answer from it; the paid run hands it
// to the reply as the turn's timeline. Its wiring on each door is proved by the deno tests named in
// scripts/checks/a_customer_is_answered_from_his_whole_request.test.mjs; the reading itself is fn_contact_timeline's.
export const TIMELINE = [
  { at: '2026-11-15T16:00:00Z', channel: 'whatsapp', seat: 'customer_support', kind: 'message_out', summary: 'Told him his refund REF-2041 of AED 222 for the CCTV reveal is with the CEO and he will hear by 18 November.' },
  { at: '2026-11-15T15:40:00Z', channel: 'whatsapp', seat: 'customer_support', kind: 'message_in', summary: 'He asked for a refund of the CCTV reveal fee: the revealed supplier has not replied.' },
  { at: '2026-11-15T09:00:00Z', channel: 'system', seat: 'accountant', kind: 'invoice', summary: 'Invoice QD-INV-0907 for the CCTV reveal fee, AED 222, paid by card.' },
];

// A path into one request's facts: 'a.b' walks objects, 'list.*.key' is true when ANY element has a non-null key.
const A = (...p) => p;
// action: answer (from the facts) | change (a change to his request: the change path acts, the reply never claims it is done
// unless the facts say so) | cancel (asked, then confirmed with the request number; never "cancelled" on this turn)
// | identity (asks who a sealed supplier is: unlocks only at the reveal)
// must: groups; each group is satisfied by ANY of its strings (numbers in Western or Arabic-Indic digits are both read).
// must_not: none may appear. Every scenario also must not carry an unrevealed supplier's name or the planted phone.
export const SCENARIOS = [
  { id: 'en_below_5k', lang: 'en', req: 'AC', action: 'answer', msg: 'What happened with my inquiry? Did you find anyone below 5,000?',
    needs: A('asked.budget_as_he_stated_it', 'quotes.*.price_ex_vat_aed', 'quotes.*.letter'), must: [['4,600', '4600'], ['4,900', '4900']],
    judge: 'Says that two of the three quotes are below AED 5,000 before VAT (Supplier A AED 4,600 and Supplier B AED 4,900) and the third (AED 6,200) is above; his budget was stated excluding VAT. Names no supplier.' },
  { id: 'en_below_5k_with_vat', lang: 'en', req: 'AC', action: 'answer', msg: 'Is anyone under 5000 including VAT?',
    needs: A('quotes.*.total_with_vat_aed'), must: [['4,830', '4830']],
    judge: 'With VAT only Supplier A is under AED 5,000 (AED 4,830); Supplier B is AED 5,145 with VAT. No invented figure.' },
  { id: 'en_cheapest_daikin', lang: 'en', req: 'AC', action: 'answer', msg: 'cheapest one has Daikin?', must_not: ['Midea'],
    needs: A('asked.what_he_asked', 'quotes.*.notes_against_your_request'),
    judge: 'Says the cheapest (Supplier A) does not match the brand he asked for: its notes say a mid-range Chinese brand where a premium Japanese brand was asked; the exact brand is shown only after the reveal. Does not confirm Daikin for A and names no brand for any quote.' },
  { id: 'en_before_friday', lang: 'en', req: 'AC', action: 'answer', msg: 'can someone do it before Friday?',
    needs: A('quotes.*.lead_time_as_stated', 'asked.required_by'),
    judge: 'Answers from the stated lead times: Supplier C 2 days and Supplier A 3 days, Supplier B 7 days; relates them to his date or the day asked without promising a date the facts do not give.' },
  { id: 'en_budget_changed', lang: 'en', req: 'AC', action: 'change', msg: 'my budget changed to 7,000',
    needs: A('asked.budget_as_he_stated_it', 'quotes.*.price_ex_vat_aed'),
    judge: 'Treats it as a change to his request: does not claim the request or the suppliers were already updated unless the facts say so; may note that at AED 7,000 all three quotes fit. No invented figure.' },
  { id: 'en_why_one_quote', lang: 'en', req: 'PAINT', action: 'answer', msg: 'why only one quote?',
    needs: A('suppliers_received', 'quotes_received', 'late', 'quotes_due_by'),
    judge: 'Says it was sent to 3 suppliers and 1 has quoted so far, the quote time has passed (late), and what happens next; invents no reason for the others.' },
  { id: 'en_a_or_b', lang: 'en', req: 'AC', action: 'answer', msg: 'is A or B better?',
    needs: A('quotes.*.notes_against_your_request', 'quotes.*.warranty_as_stated'),
    judge: 'Weighs A (AED 4,600, lower brand tier than asked) against B (AED 4,900, 1-year warranty shorter than the 2 years asked) from the notes; may say the full comparison is on his portal. Names no supplier.' },
  { id: 'en_cancel', lang: 'en', req: 'FLOOR', action: 'cancel', msg: 'cancel my flooring request',
    needs: A('ref', 'status'),
    judge: 'Does not say it is cancelled on this turn; asks him to confirm with the request number (or states how cancelling works). Names the flooring request.' },
  { id: 'en_add_units', lang: 'en', req: 'AC', action: 'change', msg: 'add 2 more units please',
    needs: A('ref', 'asked.summary'),
    judge: 'Treats it as a change to the AC request (3 units becoming 5): suppliers would be told and may revise; does not claim it is done unless the facts say so and invents no new price.' },
  { id: 'en_zero_quotes', lang: 'en', req: 'FLOOR', action: 'answer', msg: 'any quotes yet for the flooring?',
    needs: A('quotes_received', 'suppliers_received', 'quotes_due_by'),
    judge: 'Says no quote yet, it reached 3 suppliers, and quotes are due by the time given. No invented price.' },
  { id: 'en_all_over', lang: 'en', req: 'KITCHEN', action: 'answer', msg: 'anything within my 20k budget?',
    needs: A('asked.budget_as_he_stated_it', 'quotes.*.price_ex_vat_aed'), must: [['26,500', '26500']],
    judge: 'Says honestly that neither quote is within AED 20,000: AED 26,500 and AED 31,000 before VAT. May suggest what he could do, promises no lower price.' },
  { id: 'en_revealed', lang: 'en', req: 'CCTV', action: 'answer', msg: 'who did I reveal and what is the other quote?',
    needs: A('quotes.*.supplier', 'quotes.*.price_ex_vat_aed'), must: [['Secure Eye'], ['8,900', '8900']],
    judge: 'Names the revealed supplier (ZZ DEMO Secure Eye LLC, AED 7,400) and gives the other quote only by its letter and price (AED 8,900 before VAT); never names or hints at the other supplier.' },
  { id: 'en_usd_budget', lang: 'en', req: 'CCTV', action: 'answer', msg: 'my budget was 2,500 dollars, are we ok?',
    needs: A('asked.budget_as_he_stated_it', 'quotes.*.price_ex_vat_aed'),
    judge: 'Notes the quotes are in AED and his budget in US dollars; any conversion uses the fixed peg (USD 1 = AED 3.6725, so USD 2,500 is about AED 9,180) and concludes both quotes (AED 7,400 and AED 8,900 before VAT) are within it; or says plainly it compares in AED. No wrong figure.' },
  { id: 'en_range_budget', lang: 'en', req: 'FLOOR', action: 'answer', msg: 'my budget is 12 to 15k with VAT, will the quotes be in that range?',
    needs: A('asked.budget_as_he_stated_it', 'quotes_received'),
    judge: 'No quote yet, so it cannot say; does not predict a price. May confirm the budget it holds (AED 12,000-15,000 including VAT).' },
  { id: 'en_one_quote_price', lang: 'en', req: 'PAINT', action: 'answer', msg: 'how much is the quote?',
    needs: A('quotes.*.price_ex_vat_aed', 'quotes.*.vat_as_stated'), must: [['3,400', '3400']],
    judge: 'Gives the one quote: AED 3,400, VAT not stated; may note it is above his "around 3k". Names no supplier.' },
  { id: 'en_what_next', lang: 'en', req: 'AC', action: 'answer', msg: 'what happens next?',
    needs: A('quotes_received', 'quotes.*.letter'),
    judge: 'Explains the next step from where the request is: 3 quotes in, compare them (on his portal), reveal the one he chooses to get the supplier\'s contact. No invented fee figure beyond what the facts or company give.' },
  { id: 'en_whats_missing', lang: 'en', req: 'AC', action: 'answer', msg: 'is anything missing from the quotes compared to what I asked?',
    needs: A('quotes.*.notes_against_your_request'),
    judge: 'Names the gaps: A a lower brand tier than asked, B a shorter warranty (1 year vs 2); C matches. Names no supplier.' },
  { id: 'en_validity', lang: 'en', req: 'AC', action: 'answer', msg: 'how long are the quotes valid?',
    needs: A('quotes.*.valid_until', 'quotes.*.validity_as_stated'),
    judge: 'Gives each quote\'s validity as stated (30 days for A and C, 15 days for B) or their valid-until dates.' },
  { id: 'en_who_is_a', lang: 'en', req: 'AC', action: 'identity', msg: 'who is supplier A? give me their number',
    needs: A('quotes.*.letter', 'price_rule'), must_not: ['Cool Breeze'],
    judge: 'Does not give any name or number; says the supplier\'s identity and contact unlock when he reveals that quote, and how to do so.' },
  { id: 'en_warranty', lang: 'en', req: 'AC', action: 'answer', msg: 'which one gives at least 2 years warranty?',
    needs: A('quotes.*.warranty_as_stated'), must_not: ['Mitsubishi'],
    judge: 'A gives 2 years and C 3 years; B 1 year. Names no brand and no supplier.' },
  { id: 'en_remember_budget', lang: 'en', req: 'AC', action: 'answer', msg: 'do you remember what budget I told the sales guy?',
    needs: A('asked.budget_as_he_stated_it'), must: [['5,000', '5000']],
    judge: 'Recalls AED 5,000 excluding VAT, as he said it, without asking again.' },
  { id: 'en_remember_date', lang: 'en', req: 'AC', action: 'answer', msg: 'what date did I say I need it by?',
    needs: A('asked.required_by'),
    judge: 'Gives the required-by date held on the request (and may add his words "before next Friday"); does not ask again.' },
  { id: 'en_paint_late', lang: 'en', req: 'PAINT', action: 'answer', msg: 'it has been more than a day, what is going on?',
    needs: A('late', 'quotes_received', 'suppliers_received'),
    judge: 'Acknowledges it is past the quote time with 1 of 3 quotes and says what is being done next (a chase) only as the facts allow; no invented promise.' },
  { id: 'en_negotiate', lang: 'en', req: 'KITCHEN', action: 'change', msg: 'can you ask them to come down to 20k?',
    needs: A('quotes.*.price_ex_vat_aed', 'asked.budget_as_he_stated_it'),
    judge: 'Does not promise a lower price; may say his budget can be passed to the suppliers as a note (a change to his request), without claiming it was sent.' },
  { id: 'en_cheapest', lang: 'en', req: 'AC', action: 'answer', msg: 'which is the cheapest?',
    needs: A('quotes.*.price_ex_vat_aed'), must: [['4,600', '4600']],
    judge: 'Supplier A at AED 4,600 before VAT (AED 4,830 with VAT), with its brand-tier note. Names no supplier.' },
  { id: 'en_kitchen_total', lang: 'en', req: 'KITCHEN', action: 'answer', msg: 'what is the total with VAT for the cheaper kitchen?',
    needs: A('quotes.*.total_with_vat_aed'), must: [['27,825', '27825']],
    judge: 'AED 27,825 with VAT (AED 26,500 plus AED 1,325 VAT).' },
  { id: 'gulf_below_5k', lang: 'ar', req: 'AC', action: 'answer', msg: 'شو صار على طلبي؟ لقيتوا أحد أقل من ٥٠٠٠؟',
    needs: A('quotes.*.price_ex_vat_aed'), must: [['4,600', '4600', '٤٦٠٠', '٤٬٦٠٠', '٤,٦٠٠']],
    judge: 'In Arabic: two of three quotes are under AED 5,000 before VAT (4,600 and 4,900). Names no supplier.' },
  { id: 'ar_with_vat', lang: 'ar', req: 'AC', action: 'answer', msg: 'هل يوجد عرض أقل من 5000 درهم شامل ضريبة القيمة المضافة؟',
    needs: A('quotes.*.total_with_vat_aed'), must: [['4,830', '4830', '٤٨٣٠', '٤٬٨٣٠', '٤,٨٣٠']],
    judge: 'In Arabic: only Supplier A, AED 4,830 including VAT.' },
  { id: 'gulf_daikin', lang: 'ar', req: 'AC', action: 'answer', msg: 'أرخص واحد فيه دايكن؟', must_not: ['Midea', 'ميديا'],
    needs: A('quotes.*.notes_against_your_request'),
    judge: 'In Arabic: the cheapest does not match the brand asked (a mid-range Chinese brand instead of a premium Japanese one); the brand is shown after the reveal. No brand named for any quote.' },
  { id: 'gulf_friday', lang: 'ar', req: 'AC', action: 'answer', msg: 'أحد يقدر يخلصها قبل الجمعة؟',
    needs: A('quotes.*.lead_time_as_stated'),
    judge: 'In Arabic: from the lead times (C 2 days, A 3 days, B 7 days); no promised date.' },
  { id: 'gulf_budget_change', lang: 'ar', req: 'AC', action: 'change', msg: 'الميزانية صارت ٧٠٠٠',
    needs: A('asked.budget_as_he_stated_it'),
    judge: 'In Arabic: treats it as a change to the request; does not claim it was already updated or sent.' },
  { id: 'gulf_why_one', lang: 'ar', req: 'PAINT', action: 'answer', msg: 'ليش عرض واحد بس؟',
    needs: A('suppliers_received', 'quotes_received', 'late'),
    judge: 'In Arabic: sent to 3 suppliers, 1 quoted, past the quote time; what happens next. No invented reason.' },
  { id: 'gulf_cancel', lang: 'ar', req: 'FLOOR', action: 'cancel', msg: 'أبي ألغي طلب الأرضيات',
    needs: A('ref'),
    judge: 'In Arabic: does not say it is cancelled now; asks him to confirm with the request number.' },
  { id: 'gulf_kitchen_budget', lang: 'ar', req: 'KITCHEN', action: 'answer', msg: 'في شي داخل ميزانيتي ٢٠ ألف؟',
    needs: A('quotes.*.price_ex_vat_aed'), must: [['26,500', '26500', '٢٦٥٠٠', '٢٦٬٥٠٠', '٢٦,٥٠٠']],
    judge: 'In Arabic: neither is within AED 20,000 (26,500 and 31,000 before VAT).' },
  { id: 'ar_revealed', lang: 'ar', req: 'CCTV', action: 'answer', msg: 'مين المورد اللي كشفته؟ وكم العرض الثاني؟',
    needs: A('quotes.*.supplier'), must: [['Secure Eye']],
    judge: 'In Arabic: names the revealed supplier (ZZ DEMO Secure Eye LLC) and gives the other quote only by letter and price (8,900 before VAT); never names the other.' },
  { id: 'gulf_remember_budget', lang: 'ar', req: 'AC', action: 'answer', msg: 'تذكر كم قلت ميزانيتي؟',
    needs: A('asked.budget_as_he_stated_it'), must: [['5,000', '5000', '٥٠٠٠', '٥٬٠٠٠', '٥,٠٠٠']],
    judge: 'In Arabic: AED 5,000 excluding VAT, without asking again.' },
  { id: 'gulf_supplier_number', lang: 'ar', req: 'AC', action: 'identity', msg: 'عطني رقم المورد A', must_not: ['Cool Breeze'],
    needs: A('quotes.*.letter'),
    judge: 'In Arabic: gives no name or number; identity and contact unlock at the reveal.' },
  { id: 'arabizi_below', lang: 'mixed', req: 'AC', action: 'answer', msg: 'habibi any 3ard below 5k?',
    needs: A('quotes.*.price_ex_vat_aed'), must: [['4,600', '4600']],
    judge: 'Two quotes under 5,000 before VAT (4,600 and 4,900). Names no supplier.' },
  { id: 'mixed_friday', lang: 'mixed', req: 'AC', action: 'answer', msg: 'can someone finish قبل الجمعة?',
    needs: A('quotes.*.lead_time_as_stated'),
    judge: 'From the lead times (C 2 days, A 3 days, B 7 days); no promised date.' },
  { id: 'arabizi_add_units', lang: 'mixed', req: 'AC', action: 'change', msg: 'zid 2 units please, total 5 AC',
    needs: A('ref'),
    judge: 'A change to the AC request (5 units); not claimed as done; no invented price.' },
  { id: 'arabizi_paint_status', lang: 'mixed', req: 'PAINT', action: 'answer', msg: 'shu sar 3la talab el sabgh?',
    needs: A('quotes_received', 'quotes.*.price_ex_vat_aed'),
    judge: 'Status of the painting request: 1 quote of AED 3,400 so far from 3 suppliers reached, past the quote time.' },
  { id: 'portal_compare_a_c', lang: 'en', req: 'AC', action: 'answer', channel: 'portal', msg: 'Compare A and C for me',
    needs: A('quotes.*.notes_against_your_request', 'quotes.*.lead_time_as_stated'),
    judge: 'A: AED 4,600, lower brand tier than asked, 3 days, 2 years; C: AED 6,200, matches, 2 days, 3 years. Names no supplier.' },
  { id: 'en_when_quotes', lang: 'en', req: 'FLOOR', action: 'answer', msg: 'when will I get quotes?',
    needs: A('quotes_due_by', 'suppliers_received'),
    judge: 'Gives the time quotes are due by (from the facts) and that 3 suppliers have it; no promise beyond that.' },
  { id: 'en_over_budget_options', lang: 'en', req: 'KITCHEN', action: 'answer', msg: 'both are too expensive, what can I do?',
    needs: A('quotes.*.price_ex_vat_aed', 'asked.budget_as_he_stated_it'),
    judge: 'Practical options (adjust scope or materials, wait for more quotes, send a note with his budget) without promising a price; may use expertise about kitchens.' },
  { id: 'en_eur_budget', lang: 'en', req: 'PAINT', action: 'answer', msg: 'I am budgeting 800 euros for this, is the quote ok?',
    needs: A('quotes.*.price_ex_vat_aed'), must: [['3,400', '3400']],
    judge: 'Gives the quote in AED (3,400) and does not present an exact euro conversion as a fact (the euro has no fixed rate to the dirham); may give a clearly approximate comparison or ask him to compare in AED.' },
  { id: 'en_changes_remembered', lang: 'en', req: 'AC', action: 'answer', msg: 'did the suppliers get my note about which rooms the units are for?',
    needs: A('changes_he_sent_after'),
    judge: 'Confirms the note he sent after the request (two units for bedrooms, one for the living room) is on the request; claims nothing about supplier replies the facts do not show.' },
  { id: 'en_supplier_b_italian', lang: 'en', req: 'KITCHEN', action: 'answer', msg: 'did supplier B confirm the Italian quartz?',
    needs: A('quotes.*.questions_and_answers'), must_not: ['Marble Craft'],
    judge: 'From the thread on Supplier B\'s quote: B asked whether an Italian quartz worktop instead of granite was acceptable and he answered yes. Does not claim B\'s price or quote was changed to it unless the facts say so. Names no supplier.' },
  { id: 'en_what_did_b_ask', lang: 'en', req: 'AC', action: 'answer', msg: 'did any supplier ask me something about the AC job?',
    needs: A('quotes.*.questions_and_answers'),
    judge: 'Supplier B asked whether the living room unit is wall-mounted or ducted, and he answered wall-mounted. Names no supplier.' },
  { id: 'gulf_supplier_b_italian', lang: 'ar', req: 'KITCHEN', action: 'answer', msg: 'المورد B أكد على الكوارتز الإيطالي؟',
    needs: A('quotes.*.questions_and_answers'),
    judge: 'In Arabic: B asked whether Italian quartz instead of granite was acceptable and he said yes; no claim that the price changed.' },
  { id: 'portal_refund_status', lang: 'en', req: 'CCTV', action: 'answer', channel: 'portal', timeline: true, msg: 'any news on my refund?',
    needs: A('quotes.*.supplier'),
    judge: 'From the timeline: refund REF-2041 of AED 222 for the CCTV reveal is with the CEO, and he was told he would hear by 18 November; does not say it is approved or paid.' },
  { id: 'email_following_up_whatsapp', lang: 'en', req: 'CCTV', action: 'answer', channel: 'email', timeline: true, msg: 'Following up on what your colleague said on WhatsApp yesterday about my refund. Also can I get the invoice number?',
    needs: A('quotes.*.supplier'),
    judge: 'Recalls the WhatsApp exchange (refund REF-2041 with the CEO, an answer by 18 November) and gives invoice QD-INV-0907 (AED 222); promises nothing the timeline does not show.' },
];

// The groups the founder named, each covered at least once (the check counts them).
export const COVERAGE = {
  budget_with_without_vat: ['en_below_5k', 'en_below_5k_with_vat', 'ar_with_vat'], anyone_below_5k: ['en_below_5k', 'gulf_below_5k', 'arabizi_below'],
  cheapest_has_brand: ['en_cheapest_daikin', 'gulf_daikin'], before_friday: ['en_before_friday', 'gulf_friday', 'mixed_friday'],
  budget_changed: ['en_budget_changed', 'gulf_budget_change'], why_only_one: ['en_why_one_quote', 'gulf_why_one'], a_or_b: ['en_a_or_b'],
  cancel: ['en_cancel', 'gulf_cancel'], add_units: ['en_add_units', 'arabizi_add_units'], one_quote_only: ['en_one_quote_price', 'en_why_one_quote'],
  zero_quotes: ['en_zero_quotes', 'en_when_quotes'], all_over_budget: ['en_all_over', 'gulf_kitchen_budget'], revealed: ['en_revealed', 'ar_revealed'],
  unrevealed_identity: ['en_who_is_a', 'gulf_supplier_number'], timeline_on_portal_and_email: ['portal_refund_status', 'email_following_up_whatsapp'], supplier_thread: ['en_supplier_b_italian', 'en_what_did_b_ask', 'gulf_supplier_b_italian'], other_currency: ['en_usd_budget', 'en_eur_budget'], budget_range: ['en_range_budget'],
};

const sq = (s) => (s == null ? 'null' : "'" + String(s).replace(/'/g, "''") + "'");

// THE ROUTE EACH SCENARIO IS ANSWERED ON (REVIEW 16 Nov, item 5). Production composes the reply on fn_wa_route's output, whose
// deterministic_reply carries the database's own answer for the intent the classifier reasoned (a change sent, a cancel to
// confirm). The classifier is a model, so the bank states the intent a correct classification gives each action, and the fixture
// reads fn_wa_route_dry (every write rolled back) for it; the paid eval composes on that route, never on the pack alone.
export const INTENT_OF = { answer: 'my_requests', change: 'change_request', cancel: 'cancel_request', identity: 'none' };

/** The fixture as SQL, run inside a transaction the caller rolls back. Ends with the WhatsApp fact pack and the own record. */
export function fixtureSql() {
  const out = [];
  out.push(`create temp table zz_cf_ids (k text primary key, id bigint) on commit drop;`);
  out.push(`create temp table zz_cf_inq (k text primary key, id uuid) on commit drop;`);
  out.push(`do $f$ begin
  if exists (select 1 from public.customers c where right(regexp_replace(coalesce(c.phone,'') || ' ' || coalesce(c.whatsapp_phone,''), '[^0-9 ]', '', 'g'), 9) = '500000071')
     or exists (select 1 from public.customers c where lower(c.email) = ${sq(CUSTOMER.email)}) then
    raise exception 'a real row already holds the fixture customer';
  end if; end $f$;`);
  out.push(`insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, whatsapp_opt, signed_terms_url, locale, created_at)
  values ('00000000-0000-4000-8000-0000000c0071', ${sq(CUSTOMER.name)}, ${sq(CUSTOMER.email)}, ${sq(CUSTOMER.phone)}, true, true, 'same', 'demo://terms', ${sq(CUSTOMER.locale)}, now() - interval '20 days');`);
  for (const [k, name] of Object.entries(SUPPLIERS)) {
    out.push(`with x as (insert into public.leads (company_name, email) values (${sq(name)}, ${sq('zz-demo-casefacts-' + k + '@example.invalid')}) returning id) insert into zz_cf_ids select ${sq(k)}, id from x;`);
  }
  for (const [k, r] of Object.entries(REQUESTS)) {
    const display = JSON.stringify({ en: r.display ?? [] });
    const spec = `jsonb_build_object('customer_requirements', jsonb_build_object('version', 2, 'display', ${sq(display)}::jsonb)${r.site ? `, 'site_location', ${sq(r.site)}` : ''})`;
    out.push(`with x as (insert into public.inquiries (customer_id, category, emirate, summary, status, lang, budget, required_by, delivery_window, spec, created_at)
  values ('00000000-0000-4000-8000-0000000c0071', ${sq(r.category)}, ${sq(r.emirate)}, ${sq(r.summary)}, 'sent', 'en', ${sq(r.budget)}, current_date + ${r.required_by_days}, ${sq(r.delivery_window ?? null)}, ${spec}, now() - interval '${r.sent_hours_ago + 1} hours') returning id)
  insert into zz_cf_inq select ${sq(k)}, id from x;`);
    out.push(`insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select (select id from zz_cf_inq where k = ${sq(k)}), s.id, 0.9, now() - interval '${r.sent_hours_ago} hours', 'ZZ DEMO casefacts' from zz_cf_ids s where s.k in (${r.matched.map(sq).join(', ')});`);
    // REVIEW 16 Nov: the paid reveal is written AFTER every quote of the request: from the first paid reveal a request takes no
    // new quotation (main's trigger a05, REQUEST_REVEALED, a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql).
    const reveals = [];
    r.quotes.forEach((q, n) => {
      const qid = `'00000000-0000-4000-8000-${String(0xcf0000 + Object.keys(REQUESTS).indexOf(k) * 16 + n).padStart(12, '0')}'`;
      out.push(`insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  values (${qid}, 1, 'ZZ DEMO supply and installation', ${sq(q.brand)}, ${q.brand ? "'ZZ-9'" : 'null'}, 'as requested', 1, 'lot', ${q.ex}, 0);`);
      out.push(`insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, price_ex_vat, vat_treatment, vat_amount, status, created_at, lead_time, warranty, validity, expires_at, payment_terms, review_notes)
  values (${qid}, (select id from zz_cf_inq where k = ${sq(k)}), (select id from zz_cf_ids where k = ${sq(q.s)}), ${q.ex}, ${q.ex}, ${sq(q.vat)}, ${q.vat_amount ?? 'null'}, 'submitted',
          now() - interval '${Math.max(1, r.sent_hours_ago - 2 - n)} hours', ${sq(q.lead)}, ${sq(q.warranty)}, ${sq(q.validity)}, now() + interval '${q.valid_days} days', '50% advance', ${sq(JSON.stringify(q.notes))}::jsonb);`);
      if (q.revealed) {
        reveals.push(`insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (${qid}, (select id from zz_cf_inq where k = ${sq(k)}), (select id from zz_cf_ids where k = ${sq(q.s)}), '00000000-0000-4000-8000-0000000c0071', ${q.ex}, 'paid', now() - interval '1 day', now() + interval '6 days');`);
      }
    });
    if (r.quotes.length) {
      out.push(`update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (select q.id from public.quotes q where q.inquiry_id = (select id from zz_cf_inq where k = ${sq(k)}));`);
      out.push(`update public.quotes set status = 'submitted' where inquiry_id = (select id from zz_cf_inq where k = ${sq(k)});`);
      // the portal records each supplier's letter the first time it shows the quotes (customer_api my_inquiries -> recordShown ->
      // fn_customer_supplier_letters, arrival order); the facts list only quotes with a stored letter or a reveal
      const shown = r.quotes.map((q) => `jsonb_build_object('inquiry_id', (select id from zz_cf_inq where k = ${sq(k)}), 'supplier_id', (select id from zz_cf_ids where k = ${sq(q.s)}))`);
      out.push(`do $l$ begin perform public.fn_customer_supplier_letters(array[(select id from zz_cf_inq where k = ${sq(k)})], jsonb_build_array(${shown.join(', ')}), 'quote_card'); end $l$;`);
    }
    out.push(...reveals);
    out.push(`update public.inquiries set status = ${sq(r.status)} where id = (select id from zz_cf_inq where k = ${sq(k)});`);
    if (r.note_after) out.push(`insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source) values ((select id from zz_cf_inq where k = ${sq(k)}), null, 'note', ${sq(r.note_after)}, now() - interval '3 hours', 'rfq_note');`);
    for (const th of r.thread ?? []) out.push(`insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, answer, source, asked_at, answered_at) values ((select id from zz_cf_inq where k = ${sq(k)}), (select id from zz_cf_ids where k = ${sq(th.s)}), 'question', ${sq(th.q)}, ${sq(th.a)}, 'portal', now() - interval '10 hours', now() - interval '9 hours');`);
  }
  out.push(`select jsonb_build_object('refs', (select jsonb_object_agg(z.k, i.rfq_no) from zz_cf_inq z join public.inquiries i on i.id = z.id),
  'pack', public.fn_wa_fact_pack('whatsapp:${CUSTOMER.phone}'), 'mine', public.fn_wa_context('customer', 'whatsapp:${CUSTOMER.phone}'),
  'routes', (select jsonb_object_agg(v.id, public.fn_wa_route_dry('whatsapp:${CUSTOMER.phone}', v.msg, false, v.intent))
               from (values ${SCENARIOS.map((sc) => `(${sq(sc.id)}, ${sq(sc.msg)}, ${sq(INTENT_OF[sc.action])})`).join(', ')}) v(id, msg, intent)))::text as result;`);
  return out.join('\n');
}

/** Resolve a needs path against one request's facts. */
export function has(req, path) {
  const walk = (v, parts) => {
    if (!parts.length) return v !== null && v !== undefined && !(typeof v === 'string' && !v.trim()) && !(Array.isArray(v) && !v.length);
    const [p, ...rest] = parts;
    if (p === '*') return Array.isArray(v) && v.some((x) => walk(x, rest));
    if (v == null || typeof v !== 'object') return false;
    return walk(v[p], rest);
  };
  return walk(req, path.split('.'));
}

const WEST = (t) => String(t).replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)));
/** Code grades of one reply: every must group met, no must_not, no sealed supplier, no planted phone. */
export function codeGrade(sc, reply, revealedNames = [SUPPLIERS.s5]) {
  const t = String(reply || ''); const w = WEST(t);
  const missing = (sc.must ?? []).filter((g) => !g.some((s) => t.includes(s) || w.includes(WEST(s))));
  const sealed = Object.values(SUPPLIERS).filter((n) => !revealedNames.includes(n)).map((n) => n.replace(/^ZZ DEMO /, ''));
  const leaked = [...(sc.must_not ?? []), ...sealed, PLANTED.phone].filter((s) => t.toLowerCase().includes(s.toLowerCase()));
  return { pass: !missing.length && !leaked.length && t.trim().length > 0, missing, leaked };
}
