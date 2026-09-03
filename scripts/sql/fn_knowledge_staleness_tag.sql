-- THE STALENESS TAG A KNOWLEDGE HEADING CARRIES INTO A PROMPT (3 Sep 2026).
--
-- One expression, used by every knowledge loop in fn_agent_context so the four loops cannot drift
-- apart on what "stale" means. '' for a current item; a bracketed warning otherwise. Quarantined
-- items are not tagged because they are not served at all — the loops skip them.
--
-- STABLE, plain SQL: it reads its arguments and the date.

create or replace function public.fn_knowledge_staleness_tag(p_review_due date, p_validation_status text)
returns text
language sql
stable
as $function$
  select case
    when coalesce(p_validation_status,'') = 'stale' or (p_review_due is not null and p_review_due < current_date)
      then '[STALE - review was due '||coalesce(p_review_due::text,'(undated)')||'; verify before relying on it] '
    else '' end;
$function$;
