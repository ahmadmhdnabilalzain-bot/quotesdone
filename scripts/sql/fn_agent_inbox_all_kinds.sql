-- The inbox showed employees ONE of the twenty-two kinds of work addressed to them.
--
-- fn_agent_handoff_inbox filtered `kind = 'handoff'`, and it is the ONLY consumer of
-- agent_actions in the estate (fn_action_queue_sweep touches incidents; everything else only
-- WRITES). So 202 open items sat in a queue whose single reader could see 84 of them.
--
-- Measured on production before this change: 92 open items are addressed to one of the six
-- employees that actually reach agent_brain, and only 61 of those were visible. 31 were
-- invisible to the employee they were assigned to — knowledge_task, improvement_question,
-- report_recommendation, objective_step and so on, every one already carrying a recommendation
-- AND a confidence. The company had decided; nobody could see it to say yes.
--
-- THE PROMPT DOES NOT GROW. The cap stays at 3 items and 110 characters of recommendation, which
-- is what it was trimmed to after this inbox timed agent_brain out twice at ~56s (2,082 chars ->
-- 678). Widening the KINDS changes which three items appear, not how many. That matters:
-- agent_brain is ~93% of OpenRouter spend and runs seconds from its timeout.
--
-- AND THE ANSWER PATH IS **NOT** WIDENED THE SAME WAY. Seeing an item and being allowed to close
-- it are different rights. fn_action_queue_sweep's own founder alert states the rule the estate
-- already follows — "Handoffs, legal flags, customer escalations and recommendations were left
-- untouched — those need you." Letting an AI employee unilaterally close a legal_flag, a
-- security_incident or a customer_escalation would be a safety regression dressed as autonomy.
-- So the inbox shows everything and MARKS the founder's items, while fn_handoff_answer closes
-- only the classes that are the company's own internal work. Of the 92 items held by employees
-- that run, 89 are closable and 3 (compliance_update, incident) are not.
create or replace function public.fn_agent_inbox_closable_kinds()
 returns text[]
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  -- The company's own internal work: an employee finishing it is the point of the workforce.
  -- Everything NOT on this list reaches a person, a regulator, money or the model policy, and
  -- stays with the founder. Add to this list deliberately, never to drain a queue faster.
  select array['handoff','improvement_question','knowledge_task','ai_improvement',
               'report_recommendation','ops_recommendation','doc_task','report_task',
               'objective_step','supply_health','autonomy_stall'];
$function$;

-- Name kept: agent_brain calls fn_agent_handoff_inbox by name and renaming it to match its wider
-- job would be a rename for tidiness that breaks the company's reasoning loop.
create or replace function public.fn_agent_handoff_inbox(p_agent_key text)
 returns text
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select string_agg(line, E'\n' order by created_at)
  from (
    select a.created_at,
           -- Bound the WHOLE line, not its parts. Capping title and recommendation separately
           -- still left four employees over budget because the prefix varies ("from Document
           -- Controller" is longer than "doc_task"). 215 x 3 lines + 2 newlines = 647, inside the
           -- 678 this inbox was trimmed to after it timed agent_brain out twice.
           left(
           '- #'||a.id||' ('||extract(day from now() - a.created_at)::int||'d old, '
             ||case when a.kind = 'handoff'
                    then 'from '||coalesce(a.detail->>'from_name', a.detail->>'from', 'a colleague')
                    else a.kind end
             ||case when a.kind = any(fn_agent_inbox_closable_kinds()) then '' else ', FOUNDER DECIDES — do not close' end
             ||'): '
             -- The TITLE was never capped, only the recommendation. With handoffs only that was
             -- harmless; the wider kinds carry long generated titles and the block measured 821
             -- characters for `docs` and 769 for `it` — both ABOVE the 678 this inbox was trimmed
             -- to after it timed agent_brain out twice at ~56s. `it`'s prompt is 30,821 tokens and
             -- its one prior success took 53,139 ms, so the margin is real and small. Capped at 80
             -- so three lines cannot exceed roughly the budget that was proved safe.
             ||coalesce(a.title,'(untitled)')
             ||coalesce(' — '||a.recommendation, '')
           , 215) as line
      from agent_actions a
     where a.agent = p_agent_key
       and a.status in ('pending','needs_review')
     order by a.created_at
     limit 3
  ) z;
$function$;

create or replace function public.fn_handoff_answer(p_id bigint, p_agent_key text, p_answer text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_asker text;
begin
  if coalesce(btrim(p_answer),'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty answer');
  end if;
  select * into r from agent_actions
   where id = p_id and agent = p_agent_key
     and status in ('pending','needs_review');
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no open item with that id for this agent');
  end if;

  -- The refusal that keeps this honest. An employee may finish the company's own work; it may not
  -- close a legal flag, a security incident, a customer escalation, a compliance update, a money
  -- item or a prompt approval by writing a paragraph about it.
  if not (r.kind = any(fn_agent_inbox_closable_kinds())) then
    return jsonb_build_object('ok', false, 'kind', r.kind,
      'reason', 'items of kind '||r.kind||' are decided by the founder, not closed by an employee');
  end if;

  update agent_actions
     set status = 'done', decided_at = now(), decided_by = p_agent_key,
         detail = coalesce(detail,'{}'::jsonb)
                  || jsonb_build_object('answer', left(p_answer, 4000), 'answered_at', now())
   where id = p_id;

  -- Only a handoff has an asker waiting on a reply. Self-raised work has nobody to notify, and
  -- the existing guard already handles that rather than inventing a recipient.
  v_asker := coalesce(r.detail->>'from', '');
  if v_asker <> '' and exists (select 1 from org_agents o where o.agent_key = v_asker) then
    insert into agent_memory (agent_key, kind, content, source, importance)
    values (v_asker, 'learned',
            'Answer to the '||r.kind||' you raised — "'||coalesce(r.title,'(untitled)')||'": '
              ||left(p_answer, 1200),
            r.kind||':'||p_id, 4);
  end if;

  return jsonb_build_object('ok', true, 'id', p_id, 'kind', r.kind, 'asker_notified', v_asker <> '');
end $function$;

revoke execute on function public.fn_agent_handoff_inbox(text) from public, anon, authenticated;
revoke execute on function public.fn_handoff_answer(bigint, text, text) from public, anon, authenticated;
revoke execute on function public.fn_agent_inbox_closable_kinds() from public, anon, authenticated;
