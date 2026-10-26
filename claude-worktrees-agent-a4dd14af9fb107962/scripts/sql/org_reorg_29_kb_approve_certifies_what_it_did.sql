-- REORGANISING THE AGENT COMPANY - 29: fn_kb_approve certified a publish it had not performed.
--
-- When publishing an agent_knowledge revision it runs:
--
--   update agent_knowledge set content=r.content
--    where agent_key=split_part(r.entry_ref,' :: ',1) and topic=split_part(r.entry_ref,' :: ',2);
--
-- and then returns status 'published' unconditionally - without looking at whether that UPDATE
-- touched a single row. If the target pair no longer exists, the revision is marked published in
-- kb_revisions, the caller is told 'published', and the live knowledge is unchanged. The record
-- says the employee learned something it did not learn.
--
-- Measured on production: of 10,190 agent_knowledge revisions, 8 match no live row and would
-- report a publish that did nothing.
--
-- WHAT I DID NOT DO, AND WHY. The remediation note for this routine called for resolving the agent
-- key on both sides of that UPDATE, on the grounds that agent_knowledge is alias-contaminated.
-- Measured before implementing it: 10,182 of 10,190 revisions match raw, and 10,182 match with both
-- sides resolved. IDENTICAL. Resolution changes nothing here, so adding a per-row
-- fn_org_agent_resolve call across a 10,000-row table would have bought a function call per row and
-- zero correctness. The claim was reasonable and the measurement did not support it.
--
-- The revision status is now driven by what the UPDATE actually did:
--   published        - the live row was replaced
--   approved_unapplied - approved, but no live agent_knowledge row matched, and the response says so
--
-- A caller that sees 'published' can now rely on it.

begin;

create or replace function public.fn_kb_approve(p_revision bigint, p_reviewer text, p_notes text default null::text, p_publish boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_rows int := 0; v_status text; v_applied boolean := false;
begin
  select * into r from public.kb_revisions where id = p_revision;
  if r is null then return jsonb_build_object('error', 'revision not found'); end if;

  if p_publish and r.entry_kind = 'agent_knowledge' and position(' :: ' in r.entry_ref) > 0 then
    update agent_knowledge set content = r.content
     where agent_key = split_part(r.entry_ref, ' :: ', 1)
       and topic     = split_part(r.entry_ref, ' :: ', 2);
    get diagnostics v_rows = row_count;
    v_applied := v_rows > 0;
  end if;

  -- THE STATUS FOLLOWS THE EFFECT, not the intent.
  v_status := case
    when not p_publish then 'approved'
    when r.entry_kind = 'agent_knowledge' and position(' :: ' in r.entry_ref) > 0 and not v_applied
      then 'approved_unapplied'
    else 'published' end;

  update public.kb_revisions
     set status = v_status, reviewer = p_reviewer, review_notes = p_notes, decided_at = now()
   where id = p_revision;

  return jsonb_build_object(
    'ok', true, 'revision', p_revision, 'status', v_status,
    'live_rows_updated', v_rows,
    'note', case when v_status = 'approved_unapplied'
                 then 'Approved, but NOT applied: no live agent_knowledge row matches "'
                      || r.entry_ref || '". The employee''s knowledge is unchanged.'
                 else null end);
end $function$;

commit;
