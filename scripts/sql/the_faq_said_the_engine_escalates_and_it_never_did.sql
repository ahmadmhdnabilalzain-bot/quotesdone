-- THE FAQ SAID THE ENGINE ESCALATES, AND IT NEVER DID.
--
-- company_faq #101, "Does the Smart Engine guess?", is public and approved, and site_assistant
-- quotes it to visitors verbatim through fn_faq_answer:
--
--   "...if the information is not there, it asks you, records it as an open item, or ESCALATES --
--    rather than fabricating specifications, prices or regulations."
--
-- The founder ruled on 9 Sep 2026 that escalation does not exist: "Escalate to human, that is
-- something that doesn't exist. We don't have escalation to human." So the last verb in that
-- sentence named a mechanism the company does not have, in a paragraph whose entire subject is
-- that we do not say things we cannot back. It was published copy promising an action.
--
-- The rest of the sentence is now literally true and stays: "records it as an open item" is exactly
-- what fn_support_knowledge_gap does -- the question is kept word for word, counted, and given an
-- org_tasks row owned by a named seat. The fix is to say what that open item IS, and to drop the
-- verb that named nobody.
--
-- FAQ #146 is deliberately NOT touched. Its "escalated" is about a REQUEST being broadened when no
-- supplier responds, not about handing a person to a person, and that mechanism exists.

update public.company_faq
   set answer = 'No — it is designed not to. A hard grounding rule requires answers to come from '
             || 'verified knowledge; if the information is not there, it asks you, or records your '
             || 'question as an open item owned by the agent responsible for it — rather than '
             || 'fabricating specifications, prices or regulations.'
 where id = 101
   and answer like '%or escalates%';

do $probe$
declare v_answer text; v_public boolean; v_status text;
begin
  select answer, public, status into v_answer, v_public, v_status from public.company_faq where id = 101;
  if v_answer is null then
    raise exception 'PROBE FAILED: company_faq #101 does not exist';
  end if;
  if v_answer ~* '\mescalat' then
    raise exception 'PROBE FAILED: the published answer still promises an escalation: %', v_answer;
  end if;
  if v_answer not like '%open item owned by the agent responsible%' then
    raise exception 'PROBE FAILED: the answer does not name what actually happens: %', v_answer;
  end if;
  raise notice 'PROBES PASSED: company_faq #101 (public=%, status=%) no longer promises an escalation and names the open item instead.', v_public, v_status;
end
$probe$;
