-- live_knowledge_tells_a_supplier_approval_is_automatic_when_the_gate_passes.sql
-- Seat: sales_engineer. 3 Nov 2026.
-- The "Supplier onboarding policy" answer that agents read live says "(verification within a maximum of 3 working days;
-- suppliers are not auto-approved)" and, in Arabic, "ولا تُمنح الموافقة تلقائيًا". Production does the opposite:
-- pricing_config.auto_approve_suppliers is true and fn_sales_engineer_verifies_supplier approves when the gate passes
-- (the six present, licensed name read and matching, licence in date, number/authority/expiry read, documents finished
-- reading, services confirmed - ledger 1469); a foreign or unconfirmed issuing authority is held (ledger 1442).
-- The true wording is PR #1731's (src/content/marketing.json, the site FAQ, English and Arabic), so every copy agrees.
-- Measured on production 3 Nov 2026, read-only scan of company_faq, kb_chunks, agent_knowledge, knowledge_library,
-- ops_knowledge, sales/support/ceo/it_engineer/accountant/marketing knowledge, marketing_library, social_reply_library,
-- response_template, wa_reply_intent, templates, knowledge_exam_questions, seat_playbook, legal_documents, decision_policy,
-- prompt_versions, scenario_library: the false sentence lives in exactly these six rows:
--   company_faq 159 (en) and 786 (ar); kb_chunks 174359 (from company_faq) and 177559 (chunk of agent_knowledge 1047);
--   agent_knowledge 1047 ("Company FAQ (canonical answers)"); ops_knowledge 'qd-company:faq-company-policies'.
-- knowledge_library id 3 mirrors the ops_knowledge row; zz_knowledge_library_mirror re-syncs it on this update.
-- dept_library 1431-1435 and canon_eval_questions 18/38 are PR #1731's file and are not touched here.
-- Each update replaces only the false sentence, guarded by its exact text (strpos), so a re-run changes nothing.
-- Re-embedding: company_faq and ops_knowledge null embedding_gte by their own BEFORE triggers on a text change
-- (fn_company_faq_text_change_clears_embedding, fn_ops_knowledge_embedding_status -> 'pending'); kb_chunks and
-- agent_knowledge have none, so they are nulled here and fn_kb_embed_claim picks kb_chunks up again. z_ml_vectors_stale
-- drops the knowledge_vector_ml rows of every changed row. fts / tsv / search are generated columns.
-- Data only: no routine, no table, no grant, no BEGIN/COMMIT of its own (apply_sql.mjs runs it as one transaction).

update public.company_faq
   set answer = replace(answer,
     '(verification within a maximum of 3 working days; suppliers are not auto-approved).',
     '(verification within a maximum of 3 working days; approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).')
 where id = 159
   and strpos(answer, '(verification within a maximum of 3 working days; suppliers are not auto-approved).') > 0;

update public.company_faq
   set answer = replace(answer,
     '(خلال 3 أيام عمل كحد أقصى، ولا تُمنح الموافقة تلقائيًا).',
     '(خلال 3 أيام عمل كحد أقصى؛ وتصدر الموافقة تلقائيًا متى اجتازت المستندات هذا التحقق وأكّد المورّد خدماته، أمّا الرخصة الصادرة عن جهة خارج الإمارات أو عن جهة يتعذّر التأكد منها فتبقى معلّقة).')
 where id = 786
   and strpos(answer, '(خلال 3 أيام عمل كحد أقصى، ولا تُمنح الموافقة تلقائيًا).') > 0;

update public.kb_chunks
   set content = replace(content,
     '(verification within a maximum of 3 working days; suppliers are not auto-approved).',
     '(verification within a maximum of 3 working days; approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).'),
       embedding_gte = null, embed_claimed_at = null
 where id in (174359, 177559)
   and strpos(content, '(verification within a maximum of 3 working days; suppliers are not auto-approved).') > 0;

update public.agent_knowledge
   set content = replace(content,
     '(verification within a maximum of 3 working days; suppliers are not auto-approved).',
     '(verification within a maximum of 3 working days; approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).'),
       embedding_gte = null
 where id = 1047
   and strpos(content, '(verification within a maximum of 3 working days; suppliers are not auto-approved).') > 0;

update public.ops_knowledge
   set content = replace(content,
     '(verification within a maximum of 3 working days; suppliers are not auto-approved).',
     '(verification within a maximum of 3 working days; approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).')
 where record_id = 'qd-company:faq-company-policies'
   and strpos(content, '(verification within a maximum of 3 working days; suppliers are not auto-approved).') > 0;

-- Verdict. FALSE: the claim in any live knowledge row this file owns the subject of (dept_library and canon_eval_questions
-- are #1731's). TRUE: the six rows carry the new sentence. EMB: none of the six still holds a vector of the old text.
with k(t, id, x) as (
  select 'company_faq', id::text, coalesce(question, '') || ' ' || coalesce(answer, '') from public.company_faq
  union all select 'kb_chunks', id::text, coalesce(title, '') || ' ' || content from public.kb_chunks
  union all select 'agent_knowledge', id::text, coalesce(topic, '') || ' ' || content from public.agent_knowledge
  union all select 'knowledge_library', id::text, coalesce(title, '') || ' ' || content from public.knowledge_library
  union all select 'ops_knowledge', record_id, coalesce(title, '') || ' ' || content from public.ops_knowledge
  union all select 'sales_knowledge', record_id, coalesce(title, '') || ' ' || content from public.sales_knowledge
  union all select 'support_knowledge', record_id, coalesce(title, '') || ' ' || coalesce(body, '') from public.support_knowledge
  union all select 'ceo_knowledge', record_id, coalesce(title, '') || ' ' || coalesce(body, '') from public.ceo_knowledge
  union all select 'social_reply_library', key, coalesce(reply_en, '') || ' ' || coalesce(reply_ar, '') from public.social_reply_library
  union all select 'response_template', key, coalesce(body, '') || ' ' || coalesce(body_ar, '') from public.response_template
  union all select 'wa_reply_intent', intent_key, coalesce(answer_template, '') from public.wa_reply_intent
  union all select 'knowledge_exam_questions', id::text, question || ' ' || coalesce(reference_answer, '') from public.knowledge_exam_questions
), v as (
  select
    (select string_agg(t || ' ' || id, ', ') from k
      where x ~* '(not auto-approved|no supplier is (ever )?approved automatically|approval is manual|not approved automatically|auto-approve flag exists)'
         or x ~ '(لا (تُمنح|تمنح|يتم) الموافقة[^.]{0,30}تلقائي|لا (يُوافَق|يوافق) على أي (مورّد|مورد) تلقائي|لا نوافق على أي (مورّد|مورد) تلقائي)') as false_rows,
    (select count(*) from public.company_faq where id = 159 and answer like '%approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).%')
  + (select count(*) from public.company_faq where id = 786 and answer like '%وتصدر الموافقة تلقائيًا متى اجتازت المستندات هذا التحقق وأكّد المورّد خدماته%')
  + (select count(*) from public.kb_chunks where id in (174359, 177559) and content like '%approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).%')
  + (select count(*) from public.agent_knowledge where id = 1047 and content like '%approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).%')
  + (select count(*) from public.ops_knowledge where record_id = 'qd-company:faq-company-policies' and content like '%approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).%') as true_rows,
    (select count(*) from public.knowledge_library where content like '%approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).%') as mirror_rows,
    (select count(*) from public.company_faq where id in (159, 786) and embedding_gte is not null)
  + (select count(*) from public.kb_chunks where id in (174359, 177559) and embedding_gte is not null)
  + (select count(*) from public.agent_knowledge where id = 1047 and embedding_gte is not null)
  + (select count(*) from public.ops_knowledge where record_id = 'qd-company:faq-company-policies' and embedding_gte is not null)
  + (select count(*) from public.knowledge_vector_ml m where (m.src = 'company_faq' and m.row_id in ('159', '786'))
       or (m.src = 'kb_chunks' and m.row_id in ('174359', '177559')) or (m.src = 'agent_knowledge' and m.row_id = '1047')
       or (m.src = 'ops_knowledge' and m.row_id = 'qd-company:faq-company-policies')) as emb_left
)
select case
  when false_rows is not null then 'PROBE FAILED: live knowledge still says supplier approval is not automatic: ' || false_rows
  when true_rows <> 6 then 'PROBE FAILED: ' || true_rows || ' of the 6 rows carry the automatic-approval sentence'
  when emb_left > 0 then 'PROBE FAILED: ' || emb_left || ' vector(s) of the old text survive on the six rows'
  when mirror_rows < 1 then 'PROBE FAILED: knowledge_library did not mirror the corrected ops_knowledge row'
  else 'PROBE OK: 6 rows say approval is automatic when the gate passes (EN+AR), ' || mirror_rows || ' knowledge_library mirror row(s), 0 live rows say otherwise'
end as verdict
from v;
