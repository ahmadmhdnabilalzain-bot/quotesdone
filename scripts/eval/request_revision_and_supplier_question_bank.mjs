// THE REQUEST-REVISION AND ONE-SUPPLIER-QUESTION SCENARIO BANK (sales_engineer, CUSTOMER_W2, 16 Nov 2026; founder ledgers
// 1711-1713; scratchpad holes/CUSTOMER.md items 5 and 6).
//
// The founder: "I don't want the system to be rule-based only ... it's scenarios". These are the changes and questions a UAE
// customer sends after his request went out, in English, Arabic and Gulf dialect, with what the sales engineer's reading must
// be and what must and must not follow. Nothing here decides anything: the model reads each message (surfaces
// sales_engineer.request_revision and sales_engineer.customer_question); `reading` is what a correct reading is, and the check
// proves that reading, once given, lands right in the record, the notices and the customer's facts.
//
// Two uses:
//   1. DETERMINISTIC (no model): scripts/checks/a_change_is_a_revision_and_a_question_reaches_one_supplier.test.mjs writes the
//      fixture below in a LOCAL Postgres 16 (rolled back), files each message, applies the reading through
//      fn_reason_held_resolve, and checks every `expect` and `must_not`. Without a local database that part is NOT RUN.
//   2. PAID (not run in this change; no paid model calls): the same messages through the two surfaces' real model, the reading
//      compared with `reading` by a judge of another family.
// Every party is ZZ DEMO on @example.invalid; the customer's number is in the reserved fixture range.

export const CUSTOMER = { name: 'ZZ DEMO Hamdan Fixture', email: 'zz-demo-revq-c@example.invalid', phone: '+971500000161' };
export const SUPPLIERS = { A: 'ZZ DEMO Scaffold Masters', B: 'ZZ DEMO Brush and Roller' };
// The request as posted (revision 1). Dates are days from today in Dubai.
export const REQUEST = { category: 'Painting', emirate: 'Dubai', budget: 'AED 20,000', required_by_days: 20, summary: 'ZZ DEMO paint a villa exterior, two floors' };
// Supplier A's quote states scaffolding and a 2-year warranty; B's excludes scaffolding. A's own brand is planted in its scope.
export const QUOTES = {
  A: { amount: 36000, scope: 'Scaffolding included. Two coats of Zeltra elastomeric paint on all external walls.', exclusions: 'Roof and boundary wall', warranty: '2 years', lead_time: '10 days', brand: 'Zeltra' },
  B: { amount: 41000, scope: 'Paint only, two coats on external walls.', exclusions: 'Scaffolding', warranty: '1 year', lead_time: '12 days', brand: 'ZZ DEMO Brand' },
};
export const NEVER_TO_SUPPLIERS = [CUSTOMER.name, '500000161', CUSTOMER.email];
export const NEVER_TO_CUSTOMER_BEFORE_REVEAL = [SUPPLIERS.A, SUPPLIERS.B, 'Zeltra'];

// ── hole 5: a change after the request went out ────────────────────────────────────────────────────────────────────────
// reading: { choice: 'revise' | 'addendum_only', fields: { budget?, required_by_days?, emirate?, summary?, change_en? } }
// expect:  { revision, budget?, emirate?, required_by_days?, summary_has?, staled, supplier_told_has?: [...], customer_told }
export const REVISIONS = [
  { id: 'budget_up_en', lang: 'en', msg: 'Budget is now 30k, not 20k.',
    reading: { choice: 'revise', fields: { budget: 'AED 30,000', change_en: 'The budget is now AED 30,000.' } },
    expect: { revision: 2, budget: 'AED 30,000', staled: true, supplier_told_has: ['Budget: AED 20,000 -> AED 30,000'], customer_told: true } },
  { id: 'budget_down_ar', lang: 'ar', msg: 'الميزانية صارت ١٥ ألف درهم بس',
    reading: { choice: 'revise', fields: { budget: 'AED 15,000', change_en: 'The budget is now AED 15,000.' } },
    expect: { revision: 2, budget: 'AED 15,000', staled: true, supplier_told_has: ['AED 15,000'], customer_told: true } },
  { id: 'date_earlier_en', lang: 'en', msg: 'I need it done by the 1st of next month instead, we have guests coming. Call me on 0500000161 if that is a problem.',
    reading: { choice: 'revise', fields: { required_by_days: 12, change_en: 'The work is now needed 12 days from today. Call the customer on 0500000161.' } },
    expect: { revision: 2, required_by_days: 12, staled: true, supplier_told_has: ['Needed by:'], customer_told: true } },
  { id: 'date_later_gulf', lang: 'ar', msg: 'مب مستعجلين، خلوها بعد شهرين',
    reading: { choice: 'revise', fields: { required_by_days: 60, change_en: 'There is no rush: the work is now needed in about two months.' } },
    expect: { revision: 2, required_by_days: 60, staled: true, customer_told: true } },
  { id: 'emirate_move_en', lang: 'en', msg: 'Sorry, the villa is in Sharjah not Dubai.',
    reading: { choice: 'revise', fields: { emirate: 'sharjah', change_en: 'The job is in Sharjah, not Dubai.' } },
    expect: { revision: 2, emirate: 'Sharjah', staled: true, supplier_told_has: ['Emirate: Dubai -> Sharjah'], customer_told: true } },
  { id: 'scope_three_floors_ar', lang: 'ar', msg: 'نبي نصبغ ثلاث طوابق مو طابقين',
    reading: { choice: 'revise', fields: { summary: 'ZZ DEMO paint a villa exterior, three floors', change_en: 'Three floors are to be painted, not two.' } },
    expect: { revision: 2, summary_has: 'three floors', staled: false, supplier_told_has: ['description of the work was updated', 'confirm your quote still stands'], customer_told: true } },
  { id: 'budget_and_date_en', lang: 'en', msg: 'Can stretch to 25k if you can finish before the 10th.',
    reading: { choice: 'revise', fields: { budget: 'AED 25,000', required_by_days: 8, change_en: 'Budget up to AED 25,000 if finished within 8 days.' } },
    expect: { revision: 2, budget: 'AED 25,000', required_by_days: 8, staled: true, supplier_told_has: ['Budget: AED 20,000 -> AED 25,000', 'Needed by:'], customer_told: true } },
  { id: 'colour_detail_en', lang: 'en', msg: 'The colour will be off-white, like the neighbours.',
    reading: { choice: 'addendum_only' }, expect: { revision: 1, staled: false, customer_told: false } },
  { id: 'question_not_change_ar', lang: 'ar', msg: 'متى توصل العروض؟',
    reading: { choice: 'addendum_only' }, expect: { revision: 1, staled: false, customer_told: false } },
  { id: 'repeat_same_budget_en', lang: 'en', msg: 'Just confirming the budget is 20k.',
    reading: { choice: 'revise', fields: { budget: 'AED 20,000' } }, expect: { revision: 1, staled: false, customer_told: false } },
  { id: 'arabic_digits_budget_ar', lang: 'ar', msg: 'الميزانية ٢٢٠٠٠ درهم',
    reading: { choice: 'revise', fields: { budget: 'AED ٢٢٠٠٠' } }, expect: { revision: 2, budget: 'AED 22000', staled: true, customer_told: true } },
  { id: 'past_date_dropped_en', lang: 'en', msg: 'It should have been done last week honestly.',
    reading: { choice: 'revise', fields: { required_by_days: -7 } }, expect: { revision: 1, staled: false, customer_told: false } },
  { id: 'not_an_emirate_dropped_ar', lang: 'ar', msg: 'المشروع انتقل إلى مسقط',
    reading: { choice: 'revise', fields: { emirate: 'Muscat' } }, expect: { revision: 1, staled: false, customer_told: false } },
  { id: 'arabic_budget_words_dropped_ar', lang: 'ar', msg: 'الميزانية عشرين ألف وخمسمية',
    reading: { choice: 'revise', fields: { budget: 'عشرين ألف وخمسمية' } }, expect: { revision: 1, staled: false, customer_told: false } },
];

// ── hole 6: a question about ONE supplier's quote before paying ────────────────────────────────────────────────────────
// reading: { choice: 'answered_from_quote' | 'relay_to_supplier', fields: { answer? | question_en? } }
// expect:  { answered_by: 'sales_engineer' | null, relayed, customer_told, facts_has?: [...], supplier_told_has?: [...] }
export const QUESTIONS = [
  { id: 'scaffold_in_a_en', lang: 'en', quote: 'A', msg: 'Does this price include scaffolding?',
    reading: { choice: 'answered_from_quote', fields: { answer: 'Yes. The quote says: "Scaffolding included."' } },
    expect: { answered_by: 'sales_engineer', relayed: false, customer_told: true, facts_has: ['Scaffolding included'] } },
  { id: 'scaffold_in_b_ar', lang: 'ar', quote: 'B', msg: 'هل السعر يشمل السقالات؟',
    reading: { choice: 'answered_from_quote', fields: { answer: 'لا، العرض يستثني السقالات صراحةً.' } },
    expect: { answered_by: 'sales_engineer', relayed: false, customer_told: true, facts_has: ['يستثني السقالات'] } },
  { id: 'warranty_a_en', lang: 'en', quote: 'A', msg: 'How long is the warranty on this one?',
    reading: { choice: 'answered_from_quote', fields: { answer: 'The quote states a 2-year warranty.' } },
    expect: { answered_by: 'sales_engineer', relayed: false, customer_told: true, facts_has: ['2-year warranty'] } },
  { id: 'brand_leak_scrubbed_en', lang: 'en', quote: 'A', msg: 'What paint brand do they use?',
    reading: { choice: 'answered_from_quote', fields: { answer: 'Zeltra elastomeric paint, from ZZ DEMO Scaffold Masters.' } },
    expect: { answered_by: 'sales_engineer', relayed: false, customer_told: true, facts_has: ['a brand (shown after reveal)'] } },
  { id: 'start_sunday_en', lang: 'en', quote: 'A', msg: 'Can they start this Sunday?',
    reading: { choice: 'relay_to_supplier', fields: { question_en: 'Can you start this Sunday?' } },
    expect: { answered_by: null, relayed: true, customer_told: false, facts_has: ['answer due by'], supplier_told_has: ['Can you start this Sunday?', 'Please answer by'] } },
  { id: 'start_sunday_gulf', lang: 'ar', quote: 'B', msg: 'يقدرون يبدون يوم الأحد؟',
    reading: { choice: 'relay_to_supplier', fields: { question_en: 'Can you start on Sunday?' } },
    expect: { answered_by: null, relayed: true, customer_told: false, facts_has: ['answer due by'], supplier_told_has: ['Can you start on Sunday?'] } },
  { id: 'best_price_en', lang: 'en', quote: 'B', msg: 'Is this their best price? I am Hamdan, call me on 0500000161.',
    reading: { choice: 'relay_to_supplier', fields: { question_en: 'Is this your best price? (ZZ DEMO Hamdan Fixture, 0500000161)' } },
    expect: { answered_by: null, relayed: true, customer_told: false, supplier_told_has: ['Is this your best price?'] } },
  { id: 'payment_split_ar', lang: 'ar', quote: 'A', msg: 'هل يقبلون الدفع على ثلاث دفعات؟',
    reading: { choice: 'relay_to_supplier', fields: { question_en: 'Do you accept payment in three instalments?' } },
    expect: { answered_by: null, relayed: true, customer_told: false, supplier_told_has: ['three instalments'] } },
  { id: 'roof_excluded_a_en', lang: 'en', quote: 'A', msg: 'Is the roof included?',
    reading: { choice: 'answered_from_quote', fields: { answer: 'No. The quote excludes the roof and the boundary wall.' } },
    expect: { answered_by: 'sales_engineer', relayed: false, customer_told: true, facts_has: ['excludes the roof'] } },
  { id: 'lead_time_b_ar', lang: 'ar', quote: 'B', msg: 'كم يوم ياخذ الشغل؟',
    reading: { choice: 'answered_from_quote', fields: { answer: 'يذكر العرض مدة تنفيذ 12 يومًا.' } },
    expect: { answered_by: 'sales_engineer', relayed: false, customer_told: true, facts_has: ['12 يومًا'] } },
  { id: 'arabic_relay_held_ar', lang: 'ar', quote: 'B', msg: 'هل عندهم تأمين على العمال؟',
    reading: { choice: 'relay_to_supplier', fields: { question_en: 'هل عندكم تأمين على العمال؟' } },
    expect: { answered_by: null, relayed: false, customer_told: false, seat_queue: true } },
  { id: 'empty_answer_relays_en', lang: 'en', quote: 'A', msg: 'Do they clean up after?',
    reading: { choice: 'answered_from_quote', fields: { answer: '', question_en: 'Do you clean up the site after the work?' } },
    expect: { answered_by: null, relayed: true, customer_told: false, supplier_told_has: ['clean up the site'] } },
  { id: 'phone_in_answer_scrubbed_ar', lang: 'ar', quote: 'A', msg: 'هل يعطون ضمان مكتوب؟',
    reading: { choice: 'answered_from_quote', fields: { answer: 'نعم، ضمان سنتين حسب العرض. للتواصل 0501234567' } },
    expect: { answered_by: 'sales_engineer', relayed: false, customer_told: true, facts_has: ['ضمان سنتين'], facts_must_not: ['0501234567'] } },
  { id: 'colour_choice_relay_en', lang: 'en', quote: 'B', msg: 'Can I choose any colour at this price?',
    reading: { choice: 'relay_to_supplier', fields: { question_en: 'Can the customer choose any colour at this price?' } },
    expect: { answered_by: null, relayed: true, customer_told: false, supplier_told_has: ['any colour'] } },
];
