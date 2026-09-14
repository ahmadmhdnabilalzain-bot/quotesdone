-- WHAT THE AGENTS TELL CUSTOMERS FOLLOWS THE CARD FEE, NO VAT, AND THE NEW NON-RESPONSE CHARGE.
--
-- Agent: ceo. Founder rulings of 14 Sep 2026 (public.founder_instruction 88 and 90): the customer pays the 3% reveal fee
-- plus the card processing fee (Stripe's fee, grossed up); no VAT on the reveal fee; a refund returns everything the
-- customer paid; the silent supplier owes the exact amount refunded + AED 250 + 9% a year simple interest.
-- The signed texts moved in the_reveal_fee_carries_the_card_processing_fee_and_no_vat.sql. The customer_support seat
-- (the chat widget and WhatsApp) answers from public.company_faq through fn_faq_answer and kb_chunks, and every seat
-- reads the _global agent_knowledge rows, so the same sentences are corrected where the agents read them.
--
-- WHAT WAS MEASURED (read-only, 14 Sep 2026, before this file):
--   company_faq: 508 rows; 77 mention the fee, VAT or a refund. 25 public rows (EN and AR) said
--     "refunded in full" / "your reveal fee is refunded", "you pay one fee ... no other charges", "a 3% facilitation fee",
--     or a non-response charge of "the refunded reveal fee plus AED 250 + 9%", or named the 3% as the whole payment.
--   agent_knowledge: _global "Company primer" (1) said the supplier's only charge is "equal to the 3% reveal fee";
--     _global "Penalty & collections model" (3) and cs_support (7981) quoted the refund and the charge the old way;
--     _global "Company FAQ (canonical answers)" (1047) is the static copy of the FAQ; _global "Pricing & fees (LIVE)"
--     (279) is rendered by fn_company_facts_sync and said "a non-response fee equal to that reveal fee".
--   Seats with no customer reach (bookkeeper, cfo, collections, legal, contract_specialist) still describe the
--     charge as "equal to the refunded reveal fee"; they are listed in the pull request and not changed here.
--
-- WHAT THIS DOES
--   1. company_faq: sentence-level replace() on each row, guarded by the old sentence, embedding_gte cleared so
--      kb_embed re-embeds with the free in-region gte-small.
--   2. agent_knowledge 1, 3, 7981, 1047: the same, sentence by sentence.
--   3. fn_company_facts_sync: CREATE OR REPLACE (ACL and search_path kept) with the card fee, no-VAT and new
--      non-response sentences, then run once so row 279 carries them.
--   4. fn_company_org_directory_sync() re-renders ops_knowledge qd-company:faq-*; the kb_chunks mirrors of the
--      changed rows are refreshed in place with embeddings cleared (the pattern of
--      the_faq_and_the_signed_texts_carry_the_ladder_and_their_own_version.sql).
--   5. A proof block: every new sentence is present, no old one remains, and no public answer still says
--      "refunded in full" or "equal to that reveal fee". It raises (rolling everything back) otherwise.
--
--   node scripts/apply_sql.mjs scripts/sql/what_the_agents_tell_customers_follows_the_card_fee_and_the_new_non_response_charge.sql --apply --ddl

begin;

-- ---------------------------------------------------------------- 1. the company FAQ
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$pays a 3% reveal fee on the quote they choose$o$, $n$pays a 3% reveal fee, plus the card processing fee, on the quote they choose$n$)
 where id = 1 and strpos(answer, $o$pays a 3% reveal fee on the quote they choose$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$the buyer only pays a 3% reveal fee on the quote they actually choose.$o$, $n$the buyer pays only on the quote they actually choose: a 3% reveal fee plus the card processing fee.$n$)
 where id = 9 and strpos(answer, $o$the buyer only pays a 3% reveal fee on the quote they actually choose.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$pay a 3% reveal fee to unlock$o$, $n$pay the 3% reveal fee plus the card processing fee to unlock$n$)
 where id = 11 and strpos(answer, $o$pay a 3% reveal fee to unlock$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$pay the 3% reveal fee to unlock that one supplier.$o$, $n$pay the 3% reveal fee plus the card processing fee to unlock that one supplier.$n$)
 where id = 17 and strpos(answer, $o$pay the 3% reveal fee to unlock that one supplier.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$your reveal fee is refunded in full (banks$o$, $n$everything you paid is refunded (banks$n$)
 where id = 26 and strpos(answer, $o$your reveal fee is refunded in full (banks$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$You pay the 3% reveal fee and that supplier's identity$o$, $n$You pay the 3% reveal fee plus the card processing fee, and that supplier's identity$n$)
 where id = 28 and strpos(answer, $o$You pay the 3% reveal fee and that supplier's identity$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$You pay the reveal fee securely by card or Apple Pay through our checkout. It is only charged when you choose to reveal a supplier.$o$, $n$You pay the reveal fee (3% of the quote you choose) plus the card processing fee in one payment, securely by card or Apple Pay through our checkout. Both are shown in full before you pay, no VAT is added, and nothing is charged until you choose to reveal a supplier.$n$)
 where id = 29 and strpos(answer, $o$You pay the reveal fee securely by card or Apple Pay through our checkout. It is only charged when you choose to reveal a supplier.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$As a customer you pay one fee: a 3% reveal fee on the value of the quote you choose (no cap), and only on that chosen quote. There are no other charges to you. Suppliers pay no commission on won jobs.$o$, $n$As a customer you pay only when you reveal a supplier: a 3% reveal fee on the value of the quote you choose (no cap), plus the card processing fee, both shown in full before you pay. No VAT is charged on the reveal fee. There are no other charges to you. Suppliers pay no commission on won jobs.$n$)
 where id = 30 and strpos(answer, $o$As a customer you pay one fee: a 3% reveal fee on the value of the quote you choose (no cap), and only on that chosen quote. There are no other charges to you. Suppliers pay no commission on won jobs.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$your reveal fee is refunded in full to your original payment method$o$, $n$everything you paid is refunded to your original payment method$n$)
 where id = 31 and strpos(answer, $o$your reveal fee is refunded in full to your original payment method$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$you are refunded the reveal fee in full. That supplier then owes the refunded fee plus an AED 250 administrative fee and 9% per annum interest$o$, $n$everything you paid is refunded. That supplier then owes the exact amount refunded to you (the 3% reveal fee plus the card processing fee), an AED 250 administrative fee, and simple interest at 9% a year (or the maximum lawful rate) from the due date$n$)
 where id = 32 and strpos(answer, $o$you are refunded the reveal fee in full. That supplier then owes the refunded fee plus an AED 250 administrative fee and 9% per annum interest$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest.$o$, $n$the exact amount refunded to the customer (the 3% reveal fee plus the card processing fee charged on it), an AED 250 administrative fee, and simple interest at 9% a year (or the maximum lawful rate) from the due date.$n$)
 where id = 49 and strpos(answer, $o$the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$The 3% fee is the customer reveal fee: 3% of the value of the quote you choose, with no cap. A customer pays it once to unlock the identity and contact details of their chosen supplier. It is the platform's main charge and it is paid by the customer — suppliers pay no commission.$o$, $n$The 3% fee is the customer reveal fee: 3% of the value of the quote you choose, with no cap. A customer pays it once to unlock the identity and contact details of their chosen supplier. It is the platform's main charge and it is paid by the customer — suppliers pay no commission. The card processing fee is added on top, and both are shown in full before payment. No VAT is charged on the reveal fee.$n$)
 where id = 89 and strpos(answer, $o$The 3% fee is the customer reveal fee: 3% of the value of the quote you choose, with no cap. A customer pays it once to unlock the identity and contact details of their chosen supplier. It is the platform's main charge and it is paid by the customer — suppliers pay no commission.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$your reveal fee is refunded in full.$o$, $n$everything you paid is refunded.$n$)
 where id = 94 and strpos(answer, $o$your reveal fee is refunded in full.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$(the 3% fee to unlock a supplier's contact)$o$, $n$(the 3% reveal fee plus the card processing fee, to unlock a supplier's contact)$n$)
 where id = 143 and strpos(answer, $o$(the 3% fee to unlock a supplier's contact)$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$the customer's reveal fee (3% of the quote, to unlock a supplier's contact)$o$, $n$the customer's reveal payment (the 3% reveal fee plus the card processing fee, to unlock a supplier's contact)$n$)
 where id = 153 and strpos(answer, $o$the customer's reveal fee (3% of the quote, to unlock a supplier's contact)$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$pays only the 3% reveal fee on the quote$o$, $n$pays only the 3% reveal fee, plus the card processing fee, on the quote$n$)
 where id = 160 and strpos(answer, $o$pays only the 3% reveal fee on the quote$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$the customer's 3% reveal fee is refunded in full$o$, $n$everything the customer paid (the 3% reveal fee and the card processing fee) is refunded$n$)
 where id = 167 and strpos(answer, $o$the customer's 3% reveal fee is refunded in full$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$owes the refunded fee plus an AED 250 administrative fee and 9% per annum simple interest$o$, $n$owes the exact amount refunded, plus an AED 250 administrative fee and 9% per annum simple interest from the due date$n$)
 where id = 167 and strpos(answer, $o$owes the refunded fee plus an AED 250 administrative fee and 9% per annum simple interest$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$(the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest)$o$, $n$(the exact amount refunded to the customer, which is the 3% reveal fee plus the card processing fee, plus an AED 250 administrative fee and 9% per annum interest from the due date)$n$)
 where id = 169 and strpos(answer, $o$(the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest)$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$pays a 3% facilitation fee only when$o$, $n$pays a 3% reveal fee plus the card processing fee only when$n$)
 where id = 169 and strpos(answer, $o$pays a 3% facilitation fee only when$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$وتدفع رسوم الكشف البالغة 3٪ لكشف$o$, $n$وتدفع رسوم الكشف البالغة 3٪ مضافًا إليها رسوم معالجة البطاقة لكشف$n$)
 where id = 606 and strpos(answer, $o$وتدفع رسوم الكشف البالغة 3٪ لكشف$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$تُسترد رسوم الكشف كاملة$o$, $n$يُردّ إليك كل ما دفعته$n$)
 where id = 607 and strpos(answer, $o$تُسترد رسوم الكشف كاملة$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$تدفع رسوم الكشف بأمان بالبطاقة المصرفية أو عبر Apple Pay من خلال صفحة الدفع لدينا. ولا تُحصّل الرسوم إلا عندما تختار الكشف عن مورد.$o$, $n$تدفع رسوم الكشف (3٪ من عرض السعر الذي تختاره) مضافًا إليها رسوم معالجة البطاقة في دفعة واحدة، بأمان بالبطاقة المصرفية أو عبر Apple Pay من خلال صفحة الدفع لدينا. ويظهر لك المبلغان كاملين قبل الدفع، ولا تُضاف ضريبة القيمة المضافة، ولا يُحصَّل شيء إلا عندما تختار الكشف عن مورد.$n$)
 where id = 608 and strpos(answer, $o$تدفع رسوم الكشف بأمان بالبطاقة المصرفية أو عبر Apple Pay من خلال صفحة الدفع لدينا. ولا تُحصّل الرسوم إلا عندما تختار الكشف عن مورد.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$رسوم الـ 3٪ هي رسوم الكشف التي يدفعها العميل: 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى. يدفعها العميل مرة واحدة لكشف هوية المورد الذي اختاره وبيانات التواصل معه. وهي الرسوم الأساسية للمنصة ويتحملها العميل، والموردون لا يدفعون أي عمولة.$o$, $n$رسوم الـ 3٪ هي رسوم الكشف التي يدفعها العميل: 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى. يدفعها العميل مرة واحدة لكشف هوية المورد الذي اختاره وبيانات التواصل معه. وهي الرسوم الأساسية للمنصة ويتحملها العميل، والموردون لا يدفعون أي عمولة. وتُضاف إليها رسوم معالجة البطاقة، ويظهر المبلغان كاملين قبل الدفع. لا تُفرض ضريبة القيمة المضافة على رسوم الكشف.$n$)
 where id = 610 and strpos(answer, $o$رسوم الـ 3٪ هي رسوم الكشف التي يدفعها العميل: 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى. يدفعها العميل مرة واحدة لكشف هوية المورد الذي اختاره وبيانات التواصل معه. وهي الرسوم الأساسية للمنصة ويتحملها العميل، والموردون لا يدفعون أي عمولة.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$تُسترد رسوم الكشف كاملة.$o$, $n$يُردّ إليك كل ما دفعته.$n$)
 where id = 614 and strpos(answer, $o$تُسترد رسوم الكشف كاملة.$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$تُسترد رسوم الكشف كاملة إلى وسيلة الدفع الأصلية$o$, $n$يُردّ إليك كل ما دفعته إلى وسيلة الدفع الأصلية$n$)
 where id = 615 and strpos(answer, $o$تُسترد رسوم الكشف كاملة إلى وسيلة الدفع الأصلية$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$تُسترد رسوم الكشف البالغة 3٪ كاملة للعميل$o$, $n$يُردّ إلى العميل كل ما دفعه (رسوم الكشف البالغة 3٪ ورسوم معالجة البطاقة)$n$)
 where id = 616 and strpos(answer, $o$تُسترد رسوم الكشف البالغة 3٪ كاملة للعميل$o$) > 0;
update public.company_faq set embedding_gte = null, updated_at = now(), answer = replace(answer, $o$مديناً بقيمة الرسوم المستردة إضافة إلى رسوم إدارية قدرها 250 درهماً وفائدة بسيطة قدرها 9٪ سنوياً$o$, $n$مديناً بالمبلغ المردود بالضبط إضافة إلى رسوم إدارية قدرها 250 درهماً وفائدة بسيطة قدرها 9٪ سنوياً من تاريخ الاستحقاق$n$)
 where id = 616 and strpos(answer, $o$مديناً بقيمة الرسوم المستردة إضافة إلى رسوم إدارية قدرها 250 درهماً وفائدة بسيطة قدرها 9٪ سنوياً$o$) > 0;

-- ---------------------------------------------------------------- 2. the knowledge rows the seats read
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$The ONLY charge a supplier can incur is a non-response charge equal to the 3% reveal fee if they ignore$o$, $n$The ONLY charge a supplier can incur on a job is the non-response charge (the exact amount refunded to the customer, which is the 3% reveal fee plus the card processing fee, plus an AED 250 administrative fee and simple interest at 9% a year from the due date) if they ignore$n$)
 where id = 1 and strpos(content, $o$The ONLY charge a supplier can incur is a non-response charge equal to the 3% reveal fee if they ignore$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$the customer reveal fee is refunded in full$o$, $n$everything the customer paid (the 3% reveal fee and the card processing fee) is refunded$n$)
 where id = 3 and strpos(content, $o$the customer reveal fee is refunded in full$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$the refunded reveal fee (the 3%) + AED 250 administrative fee + 9% per annum simple interest$o$, $n$the exact amount refunded (the 3% reveal fee plus the card processing fee) + AED 250 administrative fee + 9% per annum simple interest from the due date$n$)
 where id = 3 and strpos(content, $o$the refunded reveal fee (the 3%) + AED 250 administrative fee + 9% per annum simple interest$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$the customer reveal fee is REFUNDED in full$o$, $n$everything the customer paid (the 3% reveal fee and the card processing fee) is REFUNDED$n$)
 where id = 7981 and strpos(content, $o$the customer reveal fee is REFUNDED in full$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$a non-response charge - that fee plus an AED 250 administrative fee and 9% per annum interest - is billed$o$, $n$a non-response charge - the exact amount refunded plus an AED 250 administrative fee and 9% per annum interest from the due date - is billed$n$)
 where id = 7981 and strpos(content, $o$a non-response charge - that fee plus an AED 250 administrative fee and 9% per annum interest - is billed$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$the buyer only pays a 3% reveal fee on the quote they actually choose.$o$, $n$the buyer pays only on the quote they actually choose: a 3% reveal fee plus the card processing fee.$n$)
 where id = 1047 and strpos(content, $o$the buyer only pays a 3% reveal fee on the quote they actually choose.$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$the customer's 3% reveal fee is refunded in full$o$, $n$everything the customer paid (the 3% reveal fee and the card processing fee) is refunded$n$)
 where id = 1047 and strpos(content, $o$the customer's 3% reveal fee is refunded in full$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$(the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest)$o$, $n$(the exact amount refunded to the customer, which is the 3% reveal fee plus the card processing fee, plus an AED 250 administrative fee and 9% per annum interest from the due date)$n$)
 where id = 1047 and strpos(content, $o$(the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest)$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$your reveal fee is refunded in full (banks$o$, $n$everything you paid is refunded (banks$n$)
 where id = 1047 and strpos(content, $o$your reveal fee is refunded in full (banks$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$your reveal fee is refunded in full to your original payment method$o$, $n$everything you paid is refunded to your original payment method$n$)
 where id = 1047 and strpos(content, $o$your reveal fee is refunded in full to your original payment method$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$your reveal fee is refunded in full.$o$, $n$everything you paid is refunded.$n$)
 where id = 1047 and strpos(content, $o$your reveal fee is refunded in full.$o$) > 0;
update public.agent_knowledge set updated_at = now(), content = replace(content, $o$the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest.$o$, $n$the exact amount refunded to the customer (the 3% reveal fee plus the card processing fee charged on it), an AED 250 administrative fee, and simple interest at 9% a year (or the maximum lawful rate) from the due date.$n$)
 where id = 1047 and strpos(content, $o$the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest.$o$) > 0;

-- ---------------------------------------------------------------- 3. the live pricing row
CREATE OR REPLACE FUNCTION public.fn_company_facts_sync()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c record; pct text; capnote text; txt text; regline text;
begin
  select * into c from pricing_config where id=1; if c is null then return; end if;

  pct := trim(to_char(coalesce(c.standard_reveal_rate,0)*100,'FM990.##'))||'%';
  capnote := 'NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal - the founder''s decision of 6 Sep 2026, enforced by a pricing_config constraint';

  -- The registration sentence is DERIVED. 6 Sep 2026 (founder): "dont use a deadline with dates" -
  -- a NULL start date is the rule itself, never a gap to ask him about.
  if c.supplier_charging_starts is null then
    regline := 'Supplier registration is FREE for the first ' || c.supplier_free_count || ' verified registrations, and those '
            || c.supplier_free_count || ' suppliers are exempt PERMANENTLY. Every registration after them pays a '
            || coalesce(c.supplier_reg_period,'yearly') || ' subscription of ' || coalesce(c.supplier_reg_currency,'AED') || ' '
            || trim(to_char(c.supplier_reg_fee,'FM999,999,990.##')) || '. There is NO calendar start date and there will not be one: '
            || 'charging begins with registration number ' || (c.supplier_free_count + 1) || ', whenever that happens. '
            || 'Never state a date, never ask the founder for one. ';
  else
    regline := 'Supplier registration is FREE for EVERY supplier until '
            || to_char(c.supplier_charging_starts - 1, 'FMDD FMMonth YYYY') || '. '
            || 'From ' || to_char(c.supplier_charging_starts, 'FMDD FMMonth YYYY') || ' a '
            || coalesce(c.supplier_reg_period,'yearly') || ' subscription of '
            || coalesce(c.supplier_reg_currency,'AED') || ' '
            || trim(to_char(c.supplier_reg_fee,'FM999,999,990.##')) || ' applies, and it is NOT charged '
            || 'before that date. The first ' || c.supplier_free_count || ' businesses to register are '
            || 'exempt PERMANENTLY and never pay it - that exemption does not expire. ';
  end if;

  txt := 'PRICING & FEES - LIVE, AUTO-SYNCED FROM pricing_config (authoritative; OVERRIDES any pricing figure stated elsewhere). '
    ||'Customer REVEAL FEE: '||pct||' of the accepted quotation value ('||capnote||'), paid by the customer to unlock their chosen supplier. '
    ||'On top of it the customer pays the CARD PROCESSING FEE (the Stripe fee, grossed up so QuotesDone receives the full '||pct||'); both are shown in full before payment. '
    ||'QuotesDone is NOT VAT registered: NO VAT is charged on the reveal fee - never say the fee is VAT-inclusive or that VAT is added. '
    ||'Suppliers pay NO commission on won jobs. '
    ||regline
    ||'CATEGORY OPENING: a category is OPEN once it has '||coalesce(c.category_open_min_suppliers,10)||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. '
    ||'Non-response window: '||c.refund_window_working_days||' working days from the customer''s payment - if a revealed supplier stays silent through the chase and the CEO''s final call, EVERYTHING the customer paid (reveal fee + card processing fee) is refunded and QuotesDone bears the Stripe fee; the supplier is charged the exact amount refunded + an AED 250 administrative fee + simple interest at 9% a year (or the maximum lawful rate) from the due date, and is blocked from matching until paid. '
    ||'There is NO 2% fee and NO supplier commission - never quote those. (Auto-updated '||to_char(now(),'YYYY-MM-DD HH24:MI')||' UTC.)';

  update agent_knowledge set content=txt, priority=100, updated_at=now()
    where agent_key='_global' and topic='Pricing & fees (LIVE — auto-synced)';
  if not found then
    insert into agent_knowledge(agent_key,topic,content,priority,updated_at)
      values ('_global','Pricing & fees (LIVE — auto-synced)',txt,100,now());
  end if;
end $function$;

select public.fn_company_facts_sync();

-- ---------------------------------------------------------------- 4. the rendered records and the search mirrors
select public.fn_company_org_directory_sync();

update public.kb_chunks k
   set content = a.content, title = a.topic, embedding_gte = null
  from public.agent_knowledge a
 where k.source_kind = 'trade' and k.source_id = a.id::text
   and a.id in (1, 3, 279, 7981)
   and k.content is distinct from a.content;
update public.kb_chunks k
   set content = '## ' || k.title || E'\n' || f.answer, embedding_gte = null
  from public.company_faq f
 where k.source_kind = 'company_faq' and k.title = '[' || f.section || '] ' || f.question
   and f.id in (1, 9, 11, 17, 26, 28, 29, 30, 31, 32, 49, 89, 94, 143, 153, 160, 167, 169, 606, 607, 608, 610, 614, 615, 616)
   and k.content like '## ' || k.title || E'\n%'
   and k.content is distinct from ('## ' || k.title || E'\n' || f.answer);

-- ---------------------------------------------------------------- 5. proof, or the whole file rolls back
do $proof$
declare r record; n int;
begin
  for r in select * from (values
    ('company_faq', 1, $n$pays a 3% reveal fee, plus the card processing fee, on the quote they choose$n$),
    ('company_faq', 9, $n$the buyer pays only on the quote they actually choose: a 3% reveal fee plus the card processing fee.$n$),
    ('company_faq', 11, $n$pay the 3% reveal fee plus the card processing fee to unlock$n$),
    ('company_faq', 17, $n$pay the 3% reveal fee plus the card processing fee to unlock that one supplier.$n$),
    ('company_faq', 26, $n$everything you paid is refunded (banks$n$),
    ('company_faq', 28, $n$You pay the 3% reveal fee plus the card processing fee, and that supplier's identity$n$),
    ('company_faq', 29, $n$You pay the reveal fee (3% of the quote you choose) plus the card processing fee in one payment, securely by card or Apple Pay through our checkout. Both are shown in full before you pay, no VAT is added, and nothing is charged until you choose to reveal a supplier.$n$),
    ('company_faq', 30, $n$As a customer you pay only when you reveal a supplier: a 3% reveal fee on the value of the quote you choose (no cap), plus the card processing fee, both shown in full before you pay. No VAT is charged on the reveal fee. There are no other charges to you. Suppliers pay no commission on won jobs.$n$),
    ('company_faq', 31, $n$everything you paid is refunded to your original payment method$n$),
    ('company_faq', 32, $n$everything you paid is refunded. That supplier then owes the exact amount refunded to you (the 3% reveal fee plus the card processing fee), an AED 250 administrative fee, and simple interest at 9% a year (or the maximum lawful rate) from the due date$n$),
    ('company_faq', 49, $n$the exact amount refunded to the customer (the 3% reveal fee plus the card processing fee charged on it), an AED 250 administrative fee, and simple interest at 9% a year (or the maximum lawful rate) from the due date.$n$),
    ('company_faq', 89, $n$The 3% fee is the customer reveal fee: 3% of the value of the quote you choose, with no cap. A customer pays it once to unlock the identity and contact details of their chosen supplier. It is the platform's main charge and it is paid by the customer — suppliers pay no commission. The card processing fee is added on top, and both are shown in full before payment. No VAT is charged on the reveal fee.$n$),
    ('company_faq', 94, $n$everything you paid is refunded.$n$),
    ('company_faq', 143, $n$(the 3% reveal fee plus the card processing fee, to unlock a supplier's contact)$n$),
    ('company_faq', 153, $n$the customer's reveal payment (the 3% reveal fee plus the card processing fee, to unlock a supplier's contact)$n$),
    ('company_faq', 160, $n$pays only the 3% reveal fee, plus the card processing fee, on the quote$n$),
    ('company_faq', 167, $n$everything the customer paid (the 3% reveal fee and the card processing fee) is refunded$n$),
    ('company_faq', 167, $n$owes the exact amount refunded, plus an AED 250 administrative fee and 9% per annum simple interest from the due date$n$),
    ('company_faq', 169, $n$(the exact amount refunded to the customer, which is the 3% reveal fee plus the card processing fee, plus an AED 250 administrative fee and 9% per annum interest from the due date)$n$),
    ('company_faq', 169, $n$pays a 3% reveal fee plus the card processing fee only when$n$),
    ('company_faq', 606, $n$وتدفع رسوم الكشف البالغة 3٪ مضافًا إليها رسوم معالجة البطاقة لكشف$n$),
    ('company_faq', 607, $n$يُردّ إليك كل ما دفعته$n$),
    ('company_faq', 608, $n$تدفع رسوم الكشف (3٪ من عرض السعر الذي تختاره) مضافًا إليها رسوم معالجة البطاقة في دفعة واحدة، بأمان بالبطاقة المصرفية أو عبر Apple Pay من خلال صفحة الدفع لدينا. ويظهر لك المبلغان كاملين قبل الدفع، ولا تُضاف ضريبة القيمة المضافة، ولا يُحصَّل شيء إلا عندما تختار الكشف عن مورد.$n$),
    ('company_faq', 610, $n$رسوم الـ 3٪ هي رسوم الكشف التي يدفعها العميل: 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى. يدفعها العميل مرة واحدة لكشف هوية المورد الذي اختاره وبيانات التواصل معه. وهي الرسوم الأساسية للمنصة ويتحملها العميل، والموردون لا يدفعون أي عمولة. وتُضاف إليها رسوم معالجة البطاقة، ويظهر المبلغان كاملين قبل الدفع. لا تُفرض ضريبة القيمة المضافة على رسوم الكشف.$n$),
    ('company_faq', 614, $n$يُردّ إليك كل ما دفعته.$n$),
    ('company_faq', 615, $n$يُردّ إليك كل ما دفعته إلى وسيلة الدفع الأصلية$n$),
    ('company_faq', 616, $n$يُردّ إلى العميل كل ما دفعه (رسوم الكشف البالغة 3٪ ورسوم معالجة البطاقة)$n$),
    ('company_faq', 616, $n$مديناً بالمبلغ المردود بالضبط إضافة إلى رسوم إدارية قدرها 250 درهماً وفائدة بسيطة قدرها 9٪ سنوياً من تاريخ الاستحقاق$n$),
    ('agent_knowledge', 1, $n$The ONLY charge a supplier can incur on a job is the non-response charge (the exact amount refunded to the customer, which is the 3% reveal fee plus the card processing fee, plus an AED 250 administrative fee and simple interest at 9% a year from the due date) if they ignore$n$),
    ('agent_knowledge', 3, $n$everything the customer paid (the 3% reveal fee and the card processing fee) is refunded$n$),
    ('agent_knowledge', 3, $n$the exact amount refunded (the 3% reveal fee plus the card processing fee) + AED 250 administrative fee + 9% per annum simple interest from the due date$n$),
    ('agent_knowledge', 7981, $n$everything the customer paid (the 3% reveal fee and the card processing fee) is REFUNDED$n$),
    ('agent_knowledge', 7981, $n$a non-response charge - the exact amount refunded plus an AED 250 administrative fee and 9% per annum interest from the due date - is billed$n$),
    ('agent_knowledge', 1047, $n$the buyer pays only on the quote they actually choose: a 3% reveal fee plus the card processing fee.$n$),
    ('agent_knowledge', 1047, $n$everything the customer paid (the 3% reveal fee and the card processing fee) is refunded$n$),
    ('agent_knowledge', 1047, $n$(the exact amount refunded to the customer, which is the 3% reveal fee plus the card processing fee, plus an AED 250 administrative fee and 9% per annum interest from the due date)$n$),
    ('agent_knowledge', 1047, $n$everything you paid is refunded (banks$n$),
    ('agent_knowledge', 1047, $n$everything you paid is refunded to your original payment method$n$),
    ('agent_knowledge', 1047, $n$everything you paid is refunded.$n$),
    ('agent_knowledge', 1047, $n$the exact amount refunded to the customer (the 3% reveal fee plus the card processing fee charged on it), an AED 250 administrative fee, and simple interest at 9% a year (or the maximum lawful rate) from the due date.$n$)
  ) as t(tbl, id, txt) loop
    if r.tbl = 'company_faq' then select count(*) into n from public.company_faq where id = r.id and strpos(answer, r.txt) > 0;
    else select count(*) into n from public.agent_knowledge where id = r.id and strpos(content, r.txt) > 0; end if;
    if n <> 1 then raise exception '%.% does not carry the new sentence: %', r.tbl, r.id, left(r.txt, 80); end if;
  end loop;
  select count(*) into n from public.company_faq
   where public and (answer ~* '(reveal fee|3% reveal fee) (is )?refunded in full' or answer ~* 'refunded the reveal fee in full'
                     or answer ~* 'refunded reveal fee plus' or answer ~* 'facilitation fee' or answer ~ 'تُسترد رسوم الكشف');
  if n > 0 then raise exception '% public FAQ answer(s) still state the old refund or charge', n; end if;
  select count(*) into n from public.agent_knowledge where id in (1, 3, 279, 7981, 1047)
     and (content ~* 'equal to (that|the 3%) reveal fee' or content ~* 'reveal fee (is )?refunded in full');
  if n > 0 then raise exception '% seat knowledge row(s) still state the old refund or charge', n; end if;
  select count(*) into n from public.agent_knowledge where id = 279 and content ~ 'CARD PROCESSING FEE' and content ~ 'NOT VAT registered' and content ~ 'exact amount refunded';
  if n <> 1 then raise exception 'the live pricing row did not re-render'; end if;
  raise notice 'agents follow the 14 Sep fee rule: % FAQ sentence(s), % knowledge sentence(s)', 28, 12;
end
$proof$;

commit;
