# The customer is asked in plain words, and sees one letter per supplier (15 Nov 2026)

Seat: sales_engineer. Branch `sales_engineer-the-customer-is-asked-in-plain-words-and-sees-one-letter-per-supplier`.

## One letter per supplier per request
- A supplier's letter is the order its first quote REACHED THE CUSTOMER (`live_since`: the latest release of a quality or
  spec hold, else `created_at`; ties by id), counted over every live quote of the request (held and sanctioned included).
  A later quote, cheaper or not, takes the next letter; a letter once given never moves.
- The one read is `_shared/quote_labels.ts` `customerQuoteLabels` / `customerQuoteLabelsByInquiry`. Portal cards
  (my_inquiries), the quotation PDF and its file name (customer_api letterOf), quote_compare, the reveal invoice
  (stripe_checkout) and the sales engineer's chat (own_quotes) all read it. Never compute a letter anywhere else.
- Before: each surface used the PRICE rank at its own moment, so journey A's two quotation PDFs both said "Supplier A".
- A supplier the customer first met through its question in the request's thread (rfq_clarification) holds its letter from
  that moment; messages_api's customer e-mail and clarify_list read `customerSupplierLetters`.
- The supplier's own alias (`jobAlias`, match order) is a different, supplier-side letter and stays so (supplier docs, the
  supplier's view of the thread).

## Plain words
- `_shared/customer_questions.ts` owns what the customer reads for a spec: plain EN/AR question, example, alternative,
  tap options ending "Not sure"; GLOSSARY for "what does X mean". The spec LABEL stays the supplier-facing text.
- Category options' Arabic labels: ONE table, `_shared/spec_options_ar.ts` (moved from src/components/me/specOptionsAr.ts,
  which re-exports it). `interview.ts modelText` is what the MODEL is told about a spec (never the Arabic frame).
- packFields puts `question_plain_en/ar` + `card_options(_ar)` beside the label; `options` stay [] (interview readers
  unchanged). `questionText` never returns English on an Arabic chat (ARABIC_FRAME when a spec has no Arabic).
- Coverage (16 Nov 2026): ALL 1,604 blocking specs of the 450 packs (1,273 distinct spec codes), measured and printed by
  `customer_questions.test.ts`, which fails if a blocking spec has none. The table is one file per group of trades
  (`customer_questions_{home,building,works,commercial,services,industrial,goods}.ts`, entries written with
  `customer_question_kit.ts q()`); a code has ONE entry (a test fails on an overlap). A NEW blocking spec in a pack needs its
  entry in the file of its trade group, or the test names it. Tests also hold: Not sure last and never twice, no English in
  the Arabic, one short question, no ask for a name, address, plot number, phone, e-mail or ID. Never word-match the customer
  (ruling 890): the model names asked-about words in `explain_terms`.
- Arabic register (native review, 15 Nov 2026): the customer is addressed in the formal plural (هل تريدون، أرسلوا، لديكم);
  an option is the customer's own voice (نعم، سأرسله); "Not sure? ..." is «إن لم تكونوا متأكدين ف...»; UAE trade words in
  Arabic letters (سبليت، ممبرين، شتر، ميزانين، بمواصفات خليجية); pipe and bar sizes are «قطر», not «عرض». A test fails on a
  singular address. An edited Arabic line is re-recorded with
  `node scripts/checks/every_arabic_message_is_written_not_translated.test.mjs --write` (run with SUPABASE_ACCESS_TOKEN unset).
