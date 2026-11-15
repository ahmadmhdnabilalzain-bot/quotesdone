# The customer is asked in plain words, and sees one letter per supplier (15 Nov 2026)

Seat: sales_engineer. Branch `sales_engineer-the-customer-is-asked-in-plain-words-and-sees-one-letter-per-supplier`.

## One letter per supplier per request, STORED once (review REVIEW_plain item 1)
- The letter is RECORDED the first time the customer is shown the supplier and never changed: table
  `public.customer_supplier_letter` (inquiry, supplier) -> letter, written only by `fn_customer_supplier_letters(uuid[], jsonb, text)`
  (scripts/sql/a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it.sql). service_role may SELECT and INSERT it,
  never UPDATE or DELETE. An arrival-order rule worked out again later still moved (a revised upload after a hold, a
  withdrawal, a re-held live quote), so the letter is no longer worked out at all.
- WHO RECORDS (`_shared/quote_labels.ts recordShown`): the surfaces that SHOW a supplier first, passing only what they show:
  the portal cards (my_inquiries: not held, not sanctioned), quote_compare (it now drops sanctioned quotes too), messages_api
  (clarify_ask, and the owner's clarify_list). Several new suppliers in one view are lettered by their quotes' created_at.
  The function itself refuses a sanctioned supplier and one with no live quote and no question on the request (no gap A, C).
- WHO ONLY READS (`storedLetters` / `storedLetterOf`): the quotation PDF (letterOf), the reveal invoice (stripe_checkout) and
  the sales engineer's chat (own_quotes; it lists held quotes too, so it records nothing).
- A FAILED READ NEVER GUESSES (item 2): cards and chat say "Supplier" (NO_LETTER); quote_compare, the quotation PDF and the
  reveal checkout answer 503 retry. A supplier read fine but never shown prints "Supplier" and ref `QD-<job>` (no suffix).
- Deploy order: apply the SQL BEFORE customer_api, quote_compare, messages_api, stripe_checkout, sales_engineer.
- The supplier's own alias (`jobAlias`, match order) is a different, supplier-side letter and stays so.

## Plain words
- `_shared/customer_questions.ts` owns what the customer reads for a spec: plain EN/AR question, example, alternative,
  tap options ending "Not sure"; GLOSSARY for "what does X mean". The spec LABEL stays the supplier-facing text.
- Category options' Arabic labels: ONE table, `_shared/spec_options_ar.ts` (moved from src/components/me/specOptionsAr.ts,
  which re-exports it). `interview.ts modelText` is what the MODEL is told about a spec (never the Arabic frame).
- packFields puts `question_plain_en/ar` + `card_options(_ar)` beside the label; `options` stay [] (interview readers
  unchanged). `questionText` never returns English on an Arabic chat (ARABIC_FRAME when a spec has no Arabic).
- Coverage: every HVAC split-AC spec, every blocking HVAC spec, the most frequent blocking specs: 309 of 1,604 blocking
  specs. The rest show the model's own plain wording (`plain_question`) or the frame. Extending the table is the
  way to grow coverage; never word-match the customer (ruling 890): the model names asked-about words in `explain_terms`.
- A tapped option is stored as its ENGLISH value on every path: `interview.ts tappedOption` (options + options_ar/optionAr,
  card_options + card_options_ar) serves both interviewStep (model down) and slots.ts tappedHeldAnswer; Arabic "لست متأكداً"
  is read as "Not sure".
- Every gate asks through plain wording: the category_specs required gate uses `interview.ts questionsFor` (never `f.question`).
- Questions ask for PHOTOS only: the request chat takes no video and there is no identity check for one (location metadata,
  a voice saying a name or number). A test fails if NewRequest.tsx starts accepting video or a question asks for one.
