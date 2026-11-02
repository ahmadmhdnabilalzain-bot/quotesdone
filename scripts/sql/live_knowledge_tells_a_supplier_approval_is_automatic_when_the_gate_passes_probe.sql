-- PROBE: live knowledge tells a supplier approval is automatic when the gate passes (3 Nov 2026). Seat: sales_engineer.
-- No DDL. Run AFTER live_knowledge_tells_a_supplier_approval_is_automatic_when_the_gate_passes.sql is applied. Never
-- applied itself: it always raises CHK<<...>>, so everything it writes rolls back.
-- It re-runs fn_company_org_directory_sync(), the routine that rebuilds ops_knowledge 'qd-company:faq-company-policies'
-- from company_faq, and asserts the rebuilt row still carries the true sentence (the fix lives upstream, in company_faq,
-- so a rebuild cannot bring the old one back). Then it scans the live knowledge an agent answers from for the false claim.
do $probe$
declare f text[] := '{}'; v_false text; n int;
  t constant text := 'approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held).';
begin
  perform public.fn_company_org_directory_sync();

  select count(*) into n from public.ops_knowledge where record_id = 'qd-company:faq-company-policies' and strpos(content, t) > 0;
  if n <> 1 then f := f || text 'the rebuilt ops_knowledge faq-company-policies row lost the automatic-approval sentence'; end if;
  select count(*) into n from public.company_faq where id = 159 and strpos(answer, t) > 0;
  if n <> 1 then f := f || text 'company_faq 159 does not carry the automatic-approval sentence'; end if;
  select count(*) into n from public.company_faq where id = 786 and strpos(answer, 'وتصدر الموافقة تلقائيًا متى اجتازت المستندات هذا التحقق وأكّد المورّد خدماته') > 0;
  if n <> 1 then f := f || text 'company_faq 786 (ar) does not carry the automatic-approval sentence'; end if;
  select count(*) into n from public.kb_chunks where id in (174359, 177559) and strpos(content, t) > 0;
  if n <> 2 then f := f || ('kb_chunks 174359/177559: ' || n || ' of 2 carry the sentence'); end if;
  select count(*) into n from public.agent_knowledge where id = 1047 and strpos(content, t) > 0;
  if n <> 1 then f := f || text 'agent_knowledge 1047 does not carry the automatic-approval sentence'; end if;

  select string_agg(k.t || ' ' || k.id, ', ') into v_false from (
    select 'company_faq' t, id::text id, coalesce(question, '') || ' ' || coalesce(answer, '') x from public.company_faq
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
  ) k
  where k.x ~* '(not auto-approved|no supplier is (ever )?approved automatically|approval is manual|not approved automatically|auto-approve flag exists)'
     or k.x ~ '(لا (تُمنح|تمنح|يتم) الموافقة[^.]{0,30}تلقائي|لا (يُوافَق|يوافق) على أي (مورّد|مورد) تلقائي|لا نوافق على أي (مورّد|مورد) تلقائي)';
  if v_false is not null then f := f || ('live knowledge still says approval is not automatic: ' || v_false); end if;

  if cardinality(f) > 0 then raise exception 'CHK<<PROBE FAILED: %>>', array_to_string(f, '; '); end if;
  raise exception 'CHK<<PROBE OK: company_faq 159/786, kb_chunks 174359/177559, agent_knowledge 1047 and the rebuilt ops_knowledge row say approval is automatic when the gate passes; 0 live rows say otherwise (rolled back)>>';
end $probe$;
