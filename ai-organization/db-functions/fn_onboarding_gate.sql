CREATE OR REPLACE FUNCTION public.fn_onboarding_gate(p_agent text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select jsonb_build_object('agent',agent_key,'status',status,
       'outputs_need_review', status <> 'certified',
       'reason', case status
         when 'certified' then 'fully onboarded'
         when 'probation' then 'passed exams; first '||probation_reviews_required||' outputs need founder/lead review ('||probation_reviews_done||' done)'
         when 'recert_due' then 'certification expired; re-examination pending'
         else 'not yet examined on the four knowledge layers' end)
     from org_onboarding where agent_key=p_agent),
    jsonb_build_object('agent',p_agent,'status','unknown','outputs_need_review',true,
      'reason','no onboarding record - treat as uncertified'));
$function$
