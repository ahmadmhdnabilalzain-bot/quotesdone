-- An agent that reads knowledge should leave a trace in the table the surface reads.
--
-- fn_record_context_retrieval wrote agent_context_retrieval, which the decision trace cites.
-- kb_usage_log is the table the executive surface reads to answer "which knowledge did this
-- employee use", and nothing was writing it for a context assembly. Two records of the same
-- fact, one of them empty, is the instrument-measuring-the-wrong-subject shape.
--
-- This does NOT invent usage. A row is written only when an assembly actually returned
-- records; an agent that decided without retrieving anything stays untraced, because that is
-- the true statement about it.
create or replace function fn_record_context_retrieval(
  p_agent_key text, p_task_class text, p_category text,
  p_ids text[], p_budget integer, p_chars integer
) returns bigint
language plpgsql volatile security definer set search_path = public as $$
declare v_id bigint;
begin
  insert into agent_context_retrieval
    (agent_key, task_class, category_key, knowledge_ids, knowledge_count, budget_chars, chars_returned)
  values (p_agent_key, p_task_class, p_category, coalesce(p_ids,'{}'),
          coalesce(array_length(p_ids,1),0), p_budget, p_chars)
  returning id into v_id;

  if coalesce(array_length(p_ids, 1), 0) > 0 then
    insert into kb_usage_log (agent, query, category)
    values (p_agent_key,
            'context assembly: ' || coalesce(array_length(p_ids,1), 0) || ' knowledge record(s) — '
              || left(array_to_string(p_ids[1:5], ', '), 400),
            coalesce(p_category, p_task_class, 'context_assembly'));
  end if;

  return v_id;
end $$;

revoke all on function fn_record_context_retrieval(text, text, text, text[], integer, integer) from public;
grant execute on function fn_record_context_retrieval(text, text, text, text[], integer, integer) to service_role;
