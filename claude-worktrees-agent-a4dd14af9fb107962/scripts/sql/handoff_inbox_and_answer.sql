-- A HANDOFF IS A MESSAGE WITH NO INBOX.
--
-- Measured on production 2026-08-10: `agent_actions` holds 82 open `handoff` rows, oldest 24 July,
-- and NOT ONE has been completed since 25 June. All 82 titles are distinct, so this is not the
-- licence_expiring duplicate storm — it is the same question re-asked with a louder title because
-- nobody answers. `it` alone holds 28 and escalated one incident five times in three days, ending in
-- "URGENT (2nd escalation) … hard-stop not applied", over a defect that does not exist.
--
-- The cause is not the writer. `agent_brain` inserts the handoff correctly. It is that
-- `fn_agent_context` — the four-layer context every employee reasons from — does not contain the
-- string `handoff` anywhere, so the receiving employee has never been told anything was handed to
-- it. Visibility alone would be worse than nothing: an inbox that cannot be cleared would repeat in
-- every prompt, forever, at token cost. So both halves land together.
--
-- Scoped to agent_brain rather than to fn_agent_context itself: agent_brain is the only place an
-- employee reasons AND can act, and fn_agent_context is 31 KB feeding every AI call in the company.

-- ── the inbox ─────────────────────────────────────────────────────────────────────────────────────
-- Three at a time, oldest first, so a backlog drains in age order instead of the newest shouting
-- loudest — which is exactly how one incident reached a fifth escalation.
--
-- KEPT DELIBERATELY SMALL, and the number came from a failure. The first version emitted five items
-- with 300 characters of recommendation each — 2,082 characters for `it` — and agent_brain then
-- TIMED OUT twice at ~56s. Measured cause: `it`'s only prior successful call, at 01:51 the same
-- morning and BEFORE this change, already took 53,139 ms on a 30,821-token prompt. It was three
-- seconds from the cliff on its own and 1.7% more prompt pushed it over. The id and the title are
-- what an employee needs to act; the full text is one query away by id.
create or replace function public.fn_agent_handoff_inbox(p_agent_key text)
returns text language sql stable security definer set search_path to 'public','pg_temp' as $$
  select string_agg(line, E'\n' order by created_at)
  from (
    select a.created_at,
           '- #'||a.id||' ('||extract(day from now() - a.created_at)::int||'d old, from '
             ||coalesce(a.detail->>'from_name', a.detail->>'from', 'a colleague')||'): '
             ||coalesce(a.title,'(untitled)')
             ||coalesce(' — '||left(a.recommendation, 110), '') as line
      from agent_actions a
     where a.kind = 'handoff'
       and a.agent = p_agent_key
       and a.status in ('pending','needs_review')
     order by a.created_at
     limit 3
  ) z;
$$;
revoke execute on function public.fn_agent_handoff_inbox(text) from public, anon, authenticated;

-- ── the way to clear it ───────────────────────────────────────────────────────────────────────────
-- Refuses anything that is not an OPEN handoff addressed to this employee, so an agent cannot close
-- someone else's work or re-close a decided row. The answer goes back to the ASKER as an
-- agent_memory row, which fn_agent_context already surfaces — no new plumbing, and the colleague who
-- asked actually receives the reply instead of it dying in a status column.
create or replace function public.fn_handoff_answer(p_id bigint, p_agent_key text, p_answer text)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare r record; v_asker text;
begin
  if coalesce(btrim(p_answer),'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty answer');
  end if;
  select * into r from agent_actions
   where id = p_id and kind = 'handoff' and agent = p_agent_key
     and status in ('pending','needs_review');
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no open handoff with that id for this agent');
  end if;

  update agent_actions
     set status = 'done', decided_at = now(), decided_by = p_agent_key,
         detail = coalesce(detail,'{}'::jsonb)
                  || jsonb_build_object('answer', left(p_answer, 4000), 'answered_at', now())
   where id = p_id;

  v_asker := coalesce(r.detail->>'from', '');
  if v_asker <> '' and exists (select 1 from org_agents o where o.agent_key = v_asker) then
    insert into agent_memory (agent_key, kind, content, source, importance)
    values (v_asker, 'learned',
            'Answer to the handoff you raised — "'||coalesce(r.title,'(untitled)')||'": '
              ||left(p_answer, 1200),
            'handoff:'||p_id, 4);
  end if;

  return jsonb_build_object('ok', true, 'id', p_id, 'asker_notified', v_asker <> '');
end $$;
revoke execute on function public.fn_handoff_answer(bigint, text, text) from public, anon, authenticated;
