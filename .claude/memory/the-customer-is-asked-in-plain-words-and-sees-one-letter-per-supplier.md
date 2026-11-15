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
- The supplier's own alias (`jobAlias`, match order) is a different, supplier-side letter and stays so.

## Plain words
- `_shared/customer_questions.ts` owns what the customer reads for a spec: plain EN/AR question, example, alternative,
  tap options ending "Not sure"; GLOSSARY for "what does X mean". The spec LABEL stays the supplier-facing text.
- packFields puts `question_plain_en/ar` + `card_options(_ar)` beside the label; `options` stay [] (interview readers
  unchanged). `questionText` never returns English on an Arabic chat (ARABIC_FRAME when a spec has no Arabic).
- Coverage: every HVAC split-AC spec, every blocking HVAC spec, the most frequent blocking specs: 309 of 1,604 blocking
  specs. The rest show the model's own plain wording (`plain_question`) or the frame. Extending the table is the
  way to grow coverage; never word-match the customer (ruling 890): the model names asked-about words in `explain_terms`.
