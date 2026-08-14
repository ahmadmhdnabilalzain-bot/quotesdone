-- THE GATE CITED ITS OWN CODE AND CALLED IT SOURCES
--
-- Row #3 "employee-knowledge-used" asks which knowledge an employee used to be visible. Measured:
-- 18 of 33 employees who decided something in 7 days have no kb_usage_log row in that window, and
-- kb_usage_log holds 144 rows whose `category` is the retrieval context 'agent_context', not a KB
-- category.
--
-- The tempting shortcut was to mirror decision_log.sources into kb_usage_log, because all 569
-- decisions in the window carry sources. Opening one shows why that would have been a lie: every
-- entry is `fn_should_escalate` (policy_check) and `fn_authorize` (authority_check). The gate cites
-- ITS OWN CODE. Not one reference to a kb_chunk anywhere. Writing a knowledge-usage row from that
-- would record a consultation that never happened — the same fabrication as a scorer reporting on a
-- file it could not read.
--
-- So the gate now actually retrieves. Before recording the verdict it looks up the knowledge that
-- governs the action class it is deciding, over the kb_chunks full-text index, and:
--   * appends it to `sources` as a third element of kind 'knowledge', carrying the query it ran and
--     the chunks that came back, so the decision cites what it was taken against; and
--   * writes a kb_usage_log row under the DECIDING EMPLOYEE'S key with the real kb category, so
--     "which knowledge this employee used" is answerable per employee.
--
-- WHAT IT HONESTLY IS, AND THE LABEL SAYS SO. The retrieved knowledge informs the human reviewing
-- the decision; it does not change the boolean, which still comes from fn_should_escalate and
-- fn_authorize. The entry carries a `note` saying exactly that, because a source element that
-- implies it drove the verdict when it did not would be the same defect one level down.
--
-- IT CAN NEVER BREAK THE GATE. The whole retrieval sits in its own BEGIN/EXCEPTION. If it raises,
-- the failure is appended to sources as kind 'knowledge_error' — visible, not swallowed — and the
-- verdict proceeds untouched. The lookup is bounded to 3 chunks and runs against the GIN index
-- kb_chunks_fts, on a table taking roughly 50 rows a day.
--
-- This does NOT close the check today: the 7-day window still holds employees who decided before
-- this deployed and have no usage row. It closes as they decide again or the window rolls.

create or replace function public.trg_action_gate()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare attrs jsonb; action text; esc jsonb; authz jsonb; blocked boolean:=false; reasons text[]:='{}'; amt numeric;
        v_sources jsonb := '[]'::jsonb; v_dl_id bigint;
        v_taken text; v_other text; v_why text; v_alts jsonb;
        v_kb_q text; v_kb jsonb; v_kb_cat text;
begin
  -- build context defensively (detail may be jsonb or text)
  begin
    attrs := case when jsonb_typeof(to_jsonb(NEW.detail)) = 'object' then to_jsonb(NEW.detail) else '{}'::jsonb end;
  exception when others then attrs := '{}'::jsonb; end;
  begin amt := nullif(attrs->>'amount_aed','')::numeric; if amt is null then amt := nullif(attrs->>'amount','')::numeric; end if; exception when others then amt := null; end;
  -- 'actor' IS PART OF THE CONTEXT, NOT JUST OF THE LEDGER ROW. NEW.agent was written to
  -- decision_log.actor and withheld from fn_should_escalate, so the router had nobody to route
  -- FROM and every one of these rows carried the same company-wide addressee. With it the
  -- escalation travels up the escalating employee's own reporting line.
  attrs := attrs || jsonb_build_object('amount_aed', amt, 'text', lower(coalesce(NEW.title,'')||' '||coalesce(NEW.recommendation,'')),
                                       'category', coalesce(attrs->>'category',''), 'moves_money', (lower(coalesce(NEW.kind,'')) ~ '(refund|payout|charge|payment|transfer)'),
                                       'actor', coalesce(NEW.agent,'agent'),
                                       -- KIND, FOR THE SAME REASON ACTOR IS HERE. fn_should_escalate
                                       -- has a rule that only makes sense for actions that ACT, and
                                       -- it could not tell a strategy from a handoff because the one
                                       -- field that says which is which was never passed.
                                       'kind', lower(coalesce(NEW.kind,'')));
  -- map action kind to an RBAC action
  action := case
    when lower(coalesce(NEW.kind,'')) ~ 'refund' then 'issue_refund'
    when lower(coalesce(NEW.kind,'')) ~ 'approve.*suppl|suppl.*approve|kyc' then 'approve_supplier'
    when lower(coalesce(NEW.kind,'')) ~ 'price|fee|commission' then 'edit_pricing'
    when lower(coalesce(NEW.kind,'')) ~ 'publish|post|content|blog|campaign' then 'publish_content'
    when lower(coalesce(NEW.kind,'')) ~ 'message|email|notify|send' then 'send_message'
    else 'run_agent_action' end;

  begin
    esc  := public.fn_should_escalate(attrs);
    authz:= public.fn_authorize(coalesce(NEW.agent,'agent'), action, attrs);
    if (esc->>'escalate')::boolean then blocked:=true; reasons := reasons || array(select jsonb_array_elements_text(coalesce(esc->'reasons','[]'))); end if;
    if not (authz->>'allowed')::boolean then blocked:=true; reasons := array_append(reasons, authz->>'reason'); end if;
  exception when others then blocked:=true; reasons := array_append(reasons,'gate error — held for review: '||sqlerrm); end;

  -- WHAT THIS DECISION WAS TAKEN ON. Each element is a retrieval that actually returned: if the
  -- call above raised, the variable is still NULL, nothing is appended, and the ledger row says so.
  if esc is not null then
    v_sources := v_sources || jsonb_build_array(jsonb_build_object(
      'kind', 'policy_check', 'ref', 'fn_should_escalate', 'result', esc));
  end if;
  if authz is not null then
    v_sources := v_sources || jsonb_build_array(jsonb_build_object(
      'kind', 'authority_check', 'ref', 'fn_authorize', 'result', authz));
  end if;

  -- THE KNOWLEDGE THIS DECISION WAS TAKEN AGAINST. Until this existed the two entries above were
  -- the whole of `sources` — the gate cited its own code and nothing else, so no employee could
  -- ever answer "which knowledge did you use". The lookup runs against the kb_chunks GIN index and
  -- is bounded to three chunks. It sits in its own block: if anything here raises, the failure is
  -- RECORDED rather than swallowed and the verdict proceeds untouched, because a knowledge lookup
  -- must never be able to hold up an action.
  begin
    -- action and kind are frequently the same word ('publish_content' maps to 'publish_content'),
    -- so the kind is only added when it says something the action does not. Otherwise the query
    -- reads "publish content publish content", which is not wrong but is careless in a record a
    -- human is meant to read.
    v_kb_q := btrim(regexp_replace(
                coalesce(action,'') ||
                case when lower(coalesce(NEW.kind,'')) = lower(coalesce(action,'')) or coalesce(NEW.kind,'') = ''
                     then '' else ' ' || NEW.kind end, '[_]+', ' ', 'g'));
    if v_kb_q <> '' then
      select jsonb_agg(jsonb_build_object('id', k.id, 'title', k.title, 'category', k.category)),
             (array_agg(k.category order by k.category))[1]
        into v_kb, v_kb_cat
        from (select c.id, c.title, c.category
                from public.kb_chunks c
               where c.fts @@ websearch_to_tsquery('english', v_kb_q)
               order by ts_rank(c.fts, websearch_to_tsquery('english', v_kb_q)) desc
               limit 3) k;
      if v_kb is not null then
        v_sources := v_sources || jsonb_build_array(jsonb_build_object(
          'kind', 'knowledge', 'ref', 'kb_chunks', 'query', v_kb_q, 'result', v_kb,
          -- The label is exact on purpose: this informs the human reading the decision. It does not
          -- move the boolean, which is still fn_should_escalate + fn_authorize. A source element
          -- implying it drove the verdict when it did not is the same defect one level down.
          'note', 'governing knowledge retrieved for this action class; informs the reviewer, does not set the verdict'));
        insert into public.kb_usage_log(query, category, agent)
        values (v_kb_q, coalesce(v_kb_cat, 'action_gate'), coalesce(NEW.agent, 'agent'));
      end if;
    end if;
  exception when others then
    v_sources := v_sources || jsonb_build_array(jsonb_build_object(
      'kind', 'knowledge_error', 'ref', 'kb_chunks', 'query', v_kb_q, 'error', sqlerrm));
  end;

  -- enforce: a gated action can never be auto-approved; force human review
  if blocked and coalesce(NEW.status,'pending') in ('approved','auto','auto_approved','executed','done') then
    NEW.status := 'needs_review';
  elsif blocked and coalesce(NEW.status,'pending')='pending' then
    NEW.status := 'needs_review';
  end if;

  -- THE OPTION THAT WAS NOT TAKEN. Two outcomes were genuinely available and one was genuinely
  -- rejected; the reasons it lost are the ones already computed above, not a new narrative.
  v_taken := case when blocked then 'held_for_review' else 'permitted' end;
  v_other := case when blocked then 'permitted' else 'held_for_review' end;
  v_why := case when blocked
    then case when array_length(reasons,1) is null
              then 'the gate blocked without recording a reason, which is itself the finding'
              else array_to_string(reasons, ' | ') end
    else 'fn_should_escalate did not fire and fn_authorize allowed it, so there was no ground to hold it' end;
  v_alts := jsonb_build_array(
    jsonb_build_object('option', v_taken, 'selected', true,
                       'basis', 'fn_should_escalate + fn_authorize on this action''s own context'),
    jsonb_build_object('option', v_other, 'selected', false, 'rejected_because', v_why));

  -- immutable audit
  begin
    insert into decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to,alternatives)
    values (coalesce(NEW.agent,'agent'),'action_gate',
            jsonb_build_object('action',action,'kind',NEW.kind,'risk',NEW.risk,'attrs',attrs),
            case when blocked then 'held_for_review' else 'permitted' end,
            -- NEW.confidence, not a literal null. This trigger is named zzz_action_gate so it fires
            -- AFTER trg_governance_stamp, which is what stamps the 0.9 — see
            -- action_gate_runs_after_the_stamp.sql. Reading it any earlier reads a NULL.
            NEW.confidence,
            to_jsonb(reasons), v_sources, esc->>'route_to', v_alts)
    returning id into v_dl_id;
  exception when others then v_dl_id := null; end;

  NEW.decision_log_id := v_dl_id;
  return NEW;
end $function$;
