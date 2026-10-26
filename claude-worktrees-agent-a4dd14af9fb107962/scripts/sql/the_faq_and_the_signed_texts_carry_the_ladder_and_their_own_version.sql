-- THE FAQ AND THE SIGNED TEXTS CARRY THE LADDER AND THEIR OWN VERSION (6 Sep 2026, repair of the refund ladder).
--
-- The refund ladder (founder ruling 6 Sep 2026, final) is 5 working days from the customer's payment, a chase
-- at day 3 by the Customer Success Director, the founder's final call on day 5, the refund on no response,
-- banks 7-14 working days, AED 250 administrative fee + 9% p.a. interest recovered from the silent supplier.
-- scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql
-- built it; scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql put it in
-- the Terms, the Supplier Agreement and the Refund Policy. An adversarial read of production afterwards found:
--
--   1. Agents still read the OLD rule from the company FAQ. ops_knowledge qd-company:faq-customer,
--      qd-company:faq-financial and qd-company:faq-company-policies are rendered by
--      fn_company_org_directory_sync from public.company_faq, and rows 26, 31, 32, 94 and 167 still said
--      "3 working days" and "refunded automatically" (measured 6 Sep 2026 19:03 UTC). Rows 49 and 169 said the
--      non-response charge is "equal to the customer's reveal fee" - true but short of the AED 250 + 9% the
--      Supplier Agreement v6 made contractual; row 49 also carried a doubled apostrophe (customer''s), an
--      escaping artefact. The FAQ is a TABLE, so the fix is a data change here; the renderer is untouched
--      (fn_company_self_knowledge_sync / fn_company_hard_rules / fn_agent_context are merged once by the
--      integrator today). embedding_gte is cleared on the changed rows so kb_embed (target company_faq) re-embeds
--      them with the free in-region gte-small; fn_faq_answer would otherwise match the old meaning.
--   2. The two signed bodies named a version older than the registry row a customer or supplier accepts
--      against: pages.legal_terms_body (= legal_documents customer-terms v4) said "(Version 3, effective
--      3 July 2026)" in its Permitted-use clause; pages.legal_supplier_body (= supplier-agreement v6 =
--      app_secrets.supplier_terms_html) said "Version 5 · governed by the laws of the United Arab Emirates".
--      A body that changes IS a new version (trg_legal_documents_hash bumps it), so the self-references are
--      written as the version they become: customer-terms v4 -> v5, supplier-agreement v6 -> v7. The site copy
--      (src/content/legal.json) is aligned to the registry in the same commit, and
--      scripts/checks/the_refund_ladder_texts_agree.test.mjs keeps the three in step from now on.
--   3. The terms pins in app_secrets follow the new text (the same statements the legal file used), so
--      fn_terms_integrity stays ok for customer v5 and supplier v7 and kyc stamps the new version on acceptance.
--   4. Three agent_knowledge rows (_global "Penalty & collections model", collections "Role & expertise",
--      cs_support "Support on a pre-reveal anonymous marketplace") quoted the old remedy "to be quoted exactly";
--      the first two also carried the retired AED 10,000 circumvention sum. Fixed by replace() on the sentence.
--   5. The kb_chunks mirrors of those rows and of the FAQ answers (source_kind trade / company_faq) are refreshed
--      in place with their embeddings cleared, instead of kb_sync()'s 2,055-row delete-and-reinsert.
--
-- The proof block at the end raises (rolling the whole file back) unless: no qd-company, agent_knowledge or
-- kb_chunks sentence still ties a refund to 3 working days (the chase sentence excepted), both agreements are at
-- their new version, and fn_terms_integrity is ok. Idempotent: every statement is guarded by the old text.
--
--   node scripts/apply_sql.mjs scripts/sql/the_faq_and_the_signed_texts_carry_the_ladder_and_their_own_version.sql --apply --ddl

-- ---------------------------------------------------------------- 1. the FAQ says the ladder
update public.company_faq set embedding_gte = null, updated_at = now(), answer = $q$It depends on the job, but 3-5 working days is realistic to receive quotes, and you are notified as each one arrives. Once you reveal a supplier, they have 5 working days from your payment to respond: we chase them for you after 3 working days, our founder makes the final call on day 5, and if they are still silent your reveal fee is refunded in full (banks take 7-14 working days to show it).$q$
 where id = 26 and question = 'How long does the process take?';

update public.company_faq set embedding_gte = null, updated_at = now(), answer = $q$Yes, in defined cases — most notably if the supplier you revealed does not respond within 5 working days of your payment. We chase them after 3 working days with you copied; on day 5 our founder makes the final call, and if the supplier is still silent your reveal fee is refunded in full to your original payment method. Every refund is the founder's decision — none is automatic — and banks take 7-14 working days to show it. Other refunds follow our Refund Policy.$q$
 where id = 31 and question = 'Can I get a refund?';

update public.company_faq set embedding_gte = null, updated_at = now(), answer = $q$If a revealed supplier does not respond within 5 working days of your payment (we chase them after 3 working days, and our founder makes the final call on day 5), you are refunded the reveal fee in full. That supplier then owes the refunded fee plus an AED 250 administrative fee and 9% per annum interest, and is blocked from new matches until it is settled.$q$
 where id = 32 and question = 'What if the supplier disappears?';

update public.company_faq set embedding_gte = null, updated_at = now(), answer = $q$There is no commission on won jobs — you keep 100% of the job value. The only charge tied to a job is the non-response charge if you ignore a customer who paid to reveal you: the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest.$q$
 where id = 49 and question = 'How are commissions calculated?';

update public.company_faq set embedding_gte = null, updated_at = now(), answer = $q$Refunds are returned to your original payment method through Stripe and every one is approved by our founder — none is automatic. The clearest case is a silent supplier: if the supplier you revealed does not respond within 5 working days of your payment (we chase them after 3 working days, and the founder makes the final call on day 5), your reveal fee is refunded in full. Banks usually take 7-14 working days to show the refund. Other refund requests made within the refund window are reviewed the same way.$q$
 where id = 94 and question = 'How are refunds processed?';

update public.company_faq set embedding_gte = null, updated_at = now(), answer = $q$Refunds are returned to the customer's original payment method via Stripe, and every refund is the founder's decision — none is automatic. The ladder runs from the customer's payment: if the revealed supplier has not responded by working day 3, our Customer Success Director chases them with the customer copied; still silent on working day 5, the founder is notified for the final call; no response to that and the customer's 3% reveal fee is refunded in full, with banks taking 7-14 working days to show it. The non-responding supplier then owes the refunded fee plus an AED 250 administrative fee and 9% per annum simple interest (the UAE statutory maximum), except where such a charge is not permitted under UAE law, and is held from new matches until it is settled. Working days are Monday to Friday, UAE public holidays excluded. Other refund requests made within the 5-working-day refund window are reviewed and, if valid, refunded the same way.$q$
 where id = 167 and question = 'Refund policy';

update public.company_faq set embedding_gte = null, updated_at = now(), answer = $q$QuotesDone charges suppliers no commission on won jobs — suppliers keep 100% of the job value. The only amounts collected from suppliers are the annual subscription (AED 1,000/year, never applicable to the first 1,000 suppliers who registered, applying from the 1,001st registration onward with no fixed start date) and a non-response charge (the customer's refunded reveal fee plus an AED 250 administrative fee and 9% per annum interest) if a supplier ignores a customer who paid to reveal them, applied except where not permitted under UAE law. The customer separately pays a 3% facilitation fee only when they choose to reveal a supplier's contact details.$q$
 where id = 169 and question = 'Commission policy';

-- the statement trigger re-rendered agent_knowledge; this renders the ops_knowledge qd-company:faq-* records
-- (the same routine fn_company_self_knowledge_sync calls every 15 minutes)
select public.fn_company_org_directory_sync();

-- ---------------------------------------------------------------- 2. the signed bodies name the version they become
-- trg_pages_legal_sync copies each page into its legal_documents row; trg_legal_documents_hash bumps the version
update public.pages
   set html = replace(html, '(Version 3, effective 3 July 2026)', '(Version 5, effective 6 September 2026)'), updated_at = now()
 where slug = 'legal_terms_body' and html like '%(Version 3, effective 3 July 2026)%';

update public.pages
   set html = replace(html, 'Version 5 &middot; governed by the laws', 'Version 7 &middot; governed by the laws'), updated_at = now()
 where slug = 'legal_supplier_body' and html like '%Version 5 &middot; governed by the laws%';

-- ---------------------------------------------------------------- 3. the terms pins follow the text
update public.app_secrets set value = (select encode(sha256(convert_to(html, 'UTF8')), 'hex') from public.pages where slug = 'legal_terms_body'), updated_at = now()
 where key = 'terms_sha256_customer';
update public.app_secrets set value = (select version from public.legal_documents where slug = 'customer-terms'), updated_at = now()
 where key in ('customer_terms_version', 'terms_sha256_customer_version');
update public.app_secrets set value = (select encode(sha256(convert_to(html, 'UTF8')), 'hex') from public.pages where slug = 'legal_supplier_body'), updated_at = now()
 where key = 'terms_sha256_supplier';
update public.app_secrets set value = (select version from public.legal_documents where slug = 'supplier-agreement'), updated_at = now()
 where key in ('terms_version', 'supplier_terms_version', 'terms_sha256_supplier_version');

-- ---------------------------------------------------------------- 4. the three agent_knowledge rows that quoted the old remedy
-- (seeded by supabase/seeds/agent_knowledge.seed.sql; the collections and penalty rows also carried the retired
-- AED 10,000 circumvention sum - hard rule 4 is AED 15,000 per incident or three times the fee, whichever is higher)
update public.agent_knowledge set updated_at = now(), content = replace(replace(content,
  $o$Non-responsive supplier: if a revealed supplier does not respond within 3 working days to the paying customer, and the founder also cannot get a response, the customer reveal fee is refunded AND a non-response recovery charge equal to that reveal fee (the 3%) is billed to the supplier as a due; the supplier is blocked from new matching until it is paid (repeat offenders removed).$o$,
  $n$Non-responsive supplier (the refund ladder, founder ruling 6 Sep 2026, final): a revealed supplier has 5 working days from the customer's PAYMENT to respond; the Customer Success Director chases on working day 3 with the customer copied; still silent on working day 5, the founder is notified for his final call; no response to that and the customer reveal fee is refunded in full (the founder approves every refund, none is automatic; banks take 7-14 working days to show it) AND a non-response recovery charge - the refunded reveal fee (the 3%) + AED 250 administrative fee + 9% per annum simple interest - is billed to the supplier as a due; the supplier is blocked from new matching until it is paid (repeat offenders removed).$n$),
  $o$Off-platform circumvention (supplier or customer): AED 10,000 liquidated sum per incident$o$,
  $n$Off-platform circumvention (supplier or customer): AED 15,000 liquidated sum per incident or three (3) times the fee, whichever is higher, plus the unpaid fee$n$)
 where agent_key = '_global' and topic = 'Penalty & collections model' and content like '%respond within 3 working days to the paying customer%';

update public.agent_knowledge set updated_at = now(), content = replace(content,
  $o$The only supplier dues you chase are: (a) the non-response recovery charge — equal to the reveal fee refunded to the customer when a revealed supplier failed to respond within 3 working days and could not be reached — and (b) the AED 10,000 off-platform circumvention sum where invoked.$o$,
  $n$The only supplier dues you chase are: (a) the non-response recovery charge — the reveal fee refunded to the customer when a revealed supplier stayed silent through the 5-working-day ladder from the customer's payment (the Customer Success Director chases on working day 3, the founder makes his final call on day 5), plus the AED 250 administrative fee and 9% per annum simple interest — and (b) the off-platform circumvention sum (AED 15,000 per incident or three times the fee, whichever is higher, plus the unpaid fee) where invoked.$n$)
 where agent_key = 'collections' and topic = 'Role & expertise' and content like '%failed to respond within 3 working days%';

update public.agent_knowledge set updated_at = now(), content = replace(content,
  $o$The third has a defined remedy and it must be quoted exactly: if a revealed supplier does not respond within 3 working days and the founder also cannot reach them, the customer reveal fee is REFUNDED and a non-response charge equal to that fee is billed to the supplier.$o$,
  $n$The third has a defined remedy and it must be quoted exactly: a revealed supplier has 5 working days from the customer's payment to respond; we chase them on working day 3 with the customer copied; still silent on working day 5, the founder is notified for his final call; no response to that and the customer reveal fee is REFUNDED in full (every refund is the founder's decision, never automatic; banks take 7-14 working days to show it) and a non-response charge - that fee plus an AED 250 administrative fee and 9% per annum interest - is billed to the supplier.$n$)
 where agent_key = 'cs_support' and topic = 'Support on a pre-reveal anonymous marketplace' and content like '%does not respond within 3 working days and the founder also cannot reach them%';

-- ---------------------------------------------------------------- 5. the kb_chunks mirrors of those rows (what fn_kb_search retrieves)
-- kb_sync() rebuilds every 'trade' chunk verbatim from agent_knowledge and is a full delete-and-reinsert (2,055 rows to
-- re-embed); only the mirrors that still carry the old phrase are refreshed here, and their embeddings cleared for kb_embed.
update public.kb_chunks k
   set content = a.content, title = a.topic, embedding_gte = null
  from public.agent_knowledge a
 where k.source_kind = 'trade' and k.source_id = a.id::text
   and k.content ~* '3 working days' and k.content is distinct from a.content;

update public.kb_chunks k
   set content = '## ' || k.title || E'\n' || f.answer, embedding_gte = null
  from public.company_faq f
 where k.source_kind = 'company_faq' and k.title = '[' || f.section || '] ' || f.question
   and f.id in (26, 31, 32, 49, 94, 167, 169)
   and k.content like '## ' || k.title || E'\n%'
   and k.content is distinct from ('## ' || k.title || E'\n' || f.answer);

-- ---------------------------------------------------------------- 6. proof, or the whole file rolls back
do $proof$
declare v_old int; v_ct text; v_sa text; v_bad int; v_faq int; v_ak int; v_kb int;
begin
  -- a qd-company sentence that still ties a refund to 3 working days, other than the chase sentence
  select count(*) into v_old
    from public.ops_knowledge
   where record_id like 'qd-company:%'
     and exists (select 1 from regexp_matches(content, '[^.]*3 working days[^.]*', 'g') m
                  where m[1] ~* 'refund' and m[1] !~* 'chase');
  select count(*) into v_ak
    from public.agent_knowledge
   where exists (select 1 from regexp_matches(content, '[^.]*3 working days[^.]*', 'g') m
                  where m[1] ~* 'refund' and m[1] !~* 'chase');
  select count(*) into v_kb
    from public.kb_chunks
   where source_kind in ('trade', 'company_faq')
     and exists (select 1 from regexp_matches(content, '[^.]*3 working days[^.]*', 'g') m
                  where m[1] ~* 'refund' and m[1] !~* 'chase');
  select count(*) into v_faq from public.ops_knowledge where record_id like 'qd-company:faq-%';
  select version into v_ct from public.legal_documents where slug = 'customer-terms';
  select version into v_sa from public.legal_documents where slug = 'supplier-agreement';
  select count(*) into v_bad from public.fn_terms_integrity() where not ok;
  if v_old > 0 or v_ak > 0 or v_kb > 0 or v_faq = 0 or v_ct <> 'v5' or v_sa <> 'v7' or v_bad > 0 then
    raise exception 'refund-ladder text repair not proven: old_rule_sentences ops_knowledge=% agent_knowledge=% kb_chunks=% faq_records=% customer_terms=% supplier_agreement=% integrity_not_ok=%',
      v_old, v_ak, v_kb, v_faq, v_ct, v_sa, v_bad;
  end if;
end $proof$;
