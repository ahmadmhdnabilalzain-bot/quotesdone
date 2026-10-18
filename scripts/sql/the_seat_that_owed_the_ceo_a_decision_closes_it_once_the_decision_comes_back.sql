-- THE SEAT THAT OWED THE CEO A DECISION CLOSES IT, ONCE THE DECISION COMES BACK AND IT HAS RE-VERIFIED IT.
--
-- Assigned: it_engineer, ceo. The it_engineer owns the loop register (seat_handoff_kind) and the check that reads
-- it; the CEO owns every decision this conversation carries.
--
-- The founder, 14 Sep 2026: "always make sure things are in loop. nothing literally should ever be a one way
-- communication" -- every handoff is tracked, replied, re-verified and closed by the seat that opened it.
--
-- WHAT WAS MEASURED (6 Oct 2026, production, read-only).
--   * scripts/checks/it_engineer_loop_is_closed.test.mjs is red on its first test. The only failing row is
--     (ceo.decision_owed, it_engineer -> ceo): originator_closes = false, and no delivery.result comes back from
--     the CEO to the it_engineer. It is a REGISTRY defect, not stuck data: 0 ceo.decision_owed or
--     ceo.decision_closed handoffs are pending or failed.
--   * The same row shape is registered for all five seats that can owe the CEO a decision (customer_support,
--     sales_engineer, accountant, it_engineer, marketing), every one by
--     a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql (#1128).
--   * The behaviour matched the register: trg_ceo_decision_round_follows_through closed the owed handoff itself
--     the moment the CEO recorded a round (fn_seat_handoff_complete with no closer named), and
--     fn_reason_apply_ceo__decision_owed closed it the same way when there was nothing left to decide. The seat
--     that raised the question never looked at the answer before its question was marked done.
--
-- WHAT THIS CHANGES. Nothing new is invented: it reuses the return that already exists and the originator-close
-- mechanism every other originator_closes kind uses (z61_handoff_only_originator_closes + qd.handoff_closer set to
-- the originator, as fn_it_loop_reverify and fn_seat_takes_the_ceo_decision's deliberation branch already do).
--   1. The five ceo.decision_owed rows become originator_closes = true. From now z61 refuses the CEO (or anyone
--      but the seat that owed it) closing one.
--   2. The CEO's decision is DELIVERED BACK, never closed on the seat's behalf: trg_ceo_decision_round_follows_through
--      records the decision on the owed handoff ('ceo_decided') and, for a final decision, sends the existing
--      ceo.decision_closed to the seat. For a rejection the return is the ceo.revise that fn_ceo_decide opened.
--      When the CEO finds nothing left to decide, fn_reason_apply_ceo__decision_owed records that answer
--      ('ceo_nothing_to_close') and sends ceo.decision_closed too.
--   3. The seat RE-VERIFIES AND CLOSES: fn_seat_verifies_the_ceo_decision_it_owed reads the ledger
--      (public.ceo_decision_round) for a CEO round on that item, by that seat, after the round the question was
--      raised at -- or the CEO's recorded nothing-to-close answer -- and only then closes the owed handoff as its
--      originator. fn_seat_takes_the_ceo_decision (the ceo.decision_closed handler, which the seat runs) calls it.
--
-- WHAT THIS DOES NOT CHANGE.
--   * ceo.decision_closed and ceo.revise keep their registration. decision_closed is the CEO's notice to the seat;
--     the seat reading it is the reply.
--   * A rejection recorded with existing revise handoffs passed in (p_revise_handoffs) opens no new ceo.revise; the
--     trigger still runs the seat's re-verification against the recorded round, so the owed question closes.
--   * fn_ceo_refund_review still treats a pending owed handoff as awaiting the CEO. After a final decision the
--     owed handoff is closed in the same transaction (the handler runs synchronously inside fn_seat_handoff), so
--     it never sees one that was decided; a 'replaced' refund starts a new generation with 0 rejections anyway.
--
-- Prevented by: scripts/checks/it_engineer_loop_is_closed.test.mjs (it reads this file's rows while it is
-- pending) and the verdict-row probe at the end of this file.
--
-- No begin/commit: the checks replay it inside one aborted transaction before apply.

-- ── 1. THE SEAT RE-VERIFIES AND CLOSES ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_verifies_the_ceo_decision_it_owed(p_seat text, p_item_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o record; r public.ceo_decision_round; v_closed bigint[] := '{}'; v_open bigint[] := '{}';
begin
  for o in select a.id, a.detail from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.decision_owed'
              and a.detail->>'from' = p_seat and a.detail->>'item_key' = p_item_key
            order by a.id loop
    -- the CEO's answer, read from the ledger rather than from the notice: a round on this item, by this seat,
    -- after the round the question was raised at
    r := null;
    select * into r from public.ceo_decision_round x
     where x.item_key = p_item_key and x.originator_seat = p_seat
       and (x.generation, x.round) > (coalesce((o.detail->>'generation')::int, 1), coalesce((o.detail->>'after_round')::int, 0))
     order by x.generation desc, x.round desc limit 1;
    if r.id is null and not (o.detail ? 'ceo_nothing_to_close') then
      v_open := v_open || o.id;
      continue;
    end if;
    perform set_config('qd.handoff_closer', p_seat, true);
    perform public.fn_seat_handoff_complete(o.id, jsonb_build_object(
      'verified_by', p_seat, 'checked_at', now(), 'round_id', r.id,
      'decision', coalesce(r.decision, 'nothing_to_close'),
      'reasons', left(coalesce(r.reasons, o.detail->'ceo_nothing_to_close'->>'reason'), 2000)));
    perform set_config('qd.handoff_closer', '', true);
    v_closed := v_closed || o.id;
  end loop;
  return jsonb_build_object('closed', to_jsonb(v_closed), 'still_owed', to_jsonb(v_open));
end $fn$;
revoke execute on function public.fn_seat_verifies_the_ceo_decision_it_owed(text, text) from public, anon, authenticated;
grant execute on function public.fn_seat_verifies_the_ceo_decision_it_owed(text, text) to service_role;

-- ── 2. THE CEO'S DECISION IS DELIVERED BACK, NOT CLOSED ON THE SEAT'S BEHALF ───────────────────────────────────
create or replace function public.trg_ceo_decision_round_follows_through()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h record;
begin
  for h in select a.id from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.revise'
              and a.detail->>'item_key' = new.item_key
              and not ((a.detail->>'generation')::int = new.generation and (a.detail->>'round')::int = new.round) loop
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'ceo', 'next_round_id', new.id,
      'next_decision', new.decision, 'generation', new.generation, 'round', new.round));
    perform set_config('qd.handoff_closer', '', true);
  end loop;
  -- an owed decision is answered here and closed by the seat that owed it (z61), after it re-verifies
  update public.agent_actions a
     set detail = a.detail || jsonb_build_object(
           'ceo_decided', jsonb_build_object('decided_by', 'ceo', 'decision', new.decision, 'round_id', new.id,
                                             'reasons', left(new.reasons, 2000)),
           'awaiting', coalesce(a.detail->>'from', 'the originating seat') || ' re-verifies the CEO''s decision')
   where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.decision_owed'
     and a.detail->>'item_key' = new.item_key;
  if new.decision in ('approved', 'replaced', 'withdrawn') then
    -- the return: the seat's handler (fn_seat_takes_the_ceo_decision) re-verifies and closes what it owed
    perform public.fn_seat_handoff('ceo', new.originator_seat, 'ceo.decision_closed', 'ceo_decision_round', new.id::text,
      jsonb_build_object('round_id', new.id, 'path', new.path, 'item_key', new.item_key, 'decision', new.decision,
                         'reasons', left(new.reasons, 3000), 'generation', new.generation, 'round', new.round,
                         'version', new.version, 'source_table', new.source_table, 'source_id', new.source_id));
  elsif new.decision = 'rejected' then
    -- the return is the ceo.revise fn_ceo_decide opened for this round; the seat re-verifies against the ledger
    perform public.fn_seat_verifies_the_ceo_decision_it_owed(new.originator_seat, new.item_key);
  end if;
  return null;
end $fn$;
revoke execute on function public.trg_ceo_decision_round_follows_through() from public, anon, authenticated;

-- ── 3. THE SEAT READS THE CEO'S FINAL DECISION, AND CLOSES WHAT IT OWED ────────────────────────────────────────
-- (#1128's body, unchanged above the last statement.) A deliberation is closed by its author here -- except a
-- high-stakes one: the gate keeps reading its last verdict, and closing it would make the next gate call open a
-- fresh review of the same decision with a fresh count, undoing the CEO's withdrawal.
create or replace function public.fn_seat_takes_the_ceo_decision(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; d public.seat_deliberation; v_closed jsonb; v_owed jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  if a.detail->>'path' = 'seat_deliberation' then
    select * into d from public.seat_deliberation where id = (a.detail->'version'->>'deliberation_id')::bigint;
    if d.id is not null and d.author_seat = a.agent and d.status in ('reviewed', 'no_independent_reviewer')
       and d.kind not like 'high_stakes.%' then
      v_closed := public.fn_seat_deliberation_close(d.id, a.agent,
        left(a.detail->>'decision' || ' by the CEO in round ' || coalesce(a.detail->>'round', '?') || ': ' || coalesce(a.detail->>'reasons', ''), 2000));
      perform set_config('qd.handoff_closer', '', true);
    elsif d.id is not null and d.author_seat = a.agent and d.kind like 'high_stakes.%' and d.handoff_id is not null
          and exists (select 1 from public.agent_actions h where h.id = d.handoff_id and h.status = 'pending') then
      perform set_config('qd.handoff_closer', a.agent, true);
      perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('kind', 'deliberation.review', 'deliberation_id', d.id,
        'ceo_decision', a.detail->>'decision', 'reasons', left(a.detail->>'reasons', 2000), 'closed_by', a.agent));
      perform set_config('qd.handoff_closer', '', true);
      v_closed := jsonb_build_object('handoff_closed', d.handoff_id, 'deliberation_kept_for_the_gate', d.id);
    end if;
  end if;
  -- the seat that owed the CEO this decision re-verifies it against the ledger and closes its own question
  if a.detail->>'item_key' is not null then
    v_owed := public.fn_seat_verifies_the_ceo_decision_it_owed(a.agent, a.detail->>'item_key');
  end if;
  return jsonb_build_object('read_by', a.agent, 'decision', a.detail->>'decision', 'item_key', a.detail->>'item_key',
                            'reasons', left(a.detail->>'reasons', 600), 'deliberation_closed', v_closed, 'owed_closed', v_owed);
end $fn$;
revoke execute on function public.fn_seat_takes_the_ceo_decision(bigint) from public, anon, authenticated;

-- ── 4. THE CEO'S OWED ANSWER: A STALE ONE CHANGES NOTHING, AND "NOTHING TO CLOSE" GOES BACK TOO ────────────────
-- (#1128's body; two statements change, both marked.)
create or replace function public.fn_reason_apply_ceo__decision_owed(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; v_choice text; v_hid bigint; v_review jsonb; v jsonb; x record; v_from text;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_hid := (r.subject->>'handoff_id')::bigint;
  -- A REFUND IS RE-MEASURED FIRST: one whose checks now pass is approved, which settles what was owed, so a
  -- payable refund is never declined on a stale reading.
  if split_part(r.subject->>'item_key', ':', 1) = 'refunds' then
    for x in select a.id, a.detail from public.agent_actions a
              where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'refund.remediate'
                and a.detail->>'refund_id' = split_part(r.subject->>'item_key', ':', 2) order by a.id loop
      v := public.fn_ceo_refund_checklist((x.detail->>'transaction_id')::uuid, 'approve', false);
      if not exists (select 1 from jsonb_array_elements(v->'items') i
                      where (x.detail->'checks') ? (i->>'item') and not coalesce((i->>'passed')::boolean, false)) then
        perform public.fn_seat_handoff_complete(x.id, jsonb_build_object('resolved_by', 're-measured before the CEO''s owed decision', 'checks', x.detail->'checks'));
      end if;
    end loop;
    v_review := public.fn_ceo_refund_review(split_part(r.subject->>'item_key', ':', 2)::bigint, 'ceo_decision_owed');
  end if;
  -- CHANGED: a stale answer changes nothing. The item moved on (a new round, an approval) and the CEO's decision is
  -- recorded on the owed handoff ('ceo_decided'), which now waits only for its seat to re-verify and close it.
  if not exists (select 1 from public.agent_actions a where a.id = v_hid and a.status = 'pending'
                   and not (a.detail ? 'ceo_decided') and not (a.detail ? 'ceo_nothing_to_close')) then
    return jsonb_build_object('applied', true, 'already', 'the owed decision was settled by the item''s next round', 'review', v_review);
  end if;
  v := public.fn_ceo_decision_close(r.subject->>'item_key', case v_choice when 'replace' then 'replaced' else 'withdrawn' end,
    coalesce(p_result->>'answer', ''), jsonb_build_object('held_id', p_id, 'model', p_result->>'model', 'fields', public.fn_ambition_fields(p_result)));
  -- CHANGED: nothing is left to decide (the item closed or the refund left 'requested' another way). The CEO's
  -- answer is recorded and delivered back as ceo.decision_closed; the seat that owed it re-verifies and closes it.
  -- An item under review stays owed; its review turn settles it.
  if not coalesce((v->>'ok')::boolean, false) and coalesce(v->>'reason', '') !~ 'under review' then
    update public.agent_actions
       set detail = detail || jsonb_build_object('ceo_nothing_to_close', jsonb_build_object('decided_by', 'ceo', 'reason', v->>'reason', 'held_id', p_id),
                                                 'awaiting', coalesce(detail->>'from', 'the originating seat') || ' re-verifies the CEO''s answer')
     where id = v_hid
    returning detail->>'from' into v_from;
    perform public.fn_seat_handoff('ceo', v_from, 'ceo.decision_closed', 'agent_actions', 'owed:' || v_hid,
      jsonb_build_object('item_key', r.subject->>'item_key', 'decision', 'nothing_to_close', 'reasons', left(v->>'reason', 3000),
                         'owed_handoff_id', v_hid, 'held_id', p_id));
  end if;
  return v || jsonb_build_object('review', v_review);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__decision_owed(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__decision_owed(bigint, jsonb) to service_role;

-- ── 5. THE REGISTER: EVERY OWED DECISION IS CLOSED BY THE SEAT THAT OWED IT ────────────────────────────────────
update public.seat_handoff_kind
   set originator_closes = true,
       meaning = 'A submission was sent back 4 times, or its revision stalled: the CEO approves it, or replaces or withdraws it with reasons. Never the founder. The decision comes back to the seat (ceo.decision_closed, or ceo.revise for a rejection), which re-verifies it against ceo_decision_round and closes this itself.',
       owner_file = 'scripts/sql/the_seat_that_owed_the_ceo_a_decision_closes_it_once_the_decision_comes_back.sql'
 where type = 'ceo.decision_owed' and to_seat = 'ceo'
   and from_seat in ('customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing');

-- ── 6. PROBE: ONE FULL CEO DECISION CYCLE ON ZZ DEMO DATA ──────────────────────────────────────────────────────
-- owe -> the CEO cannot close it -> the CEO decides -> the decision is delivered back -> the seat re-verifies and
-- closes it. Everything the cycle writes happens inside a plpgsql sub-block that ends by raising, so its
-- subtransaction is undone whatever the cycle did (ceo_decision_round is append-only and could not be deleted
-- afterwards); the probe then asserts nothing of it is left. It touches no customer or supplier: the item is a
-- ceo_improvement key with no row behind it and the only parties are two seats.
do $probe$
declare
  v_key text := 'ceo_improvement:-' || (900000000 + floor(random() * 99999999))::bigint;
  v_bad text[] := '{}'; v jsonb; v_owed bigint; v_back bigint; v_round bigint; s record; n int;
begin
  if (select count(*) from public.seat_handoff_kind
       where type = 'ceo.decision_owed' and to_seat = 'ceo' and originator_closes) <> 5 then
    v_bad := v_bad || 'registry: not all five ceo.decision_owed rows are originator_closes'::text;
  end if;
  begin
    -- a rejected round with an empty revise list, so the cycle starts at the owed question itself
    v := public.fn_ceo_decide('ceo_improvement', v_key, 'it_engineer', 'rejected',
           'ZZ DEMO probe: the submission misses its evidence and its owner, so revise it before resubmitting',
           '{}'::jsonb, null, null, '{}'::bigint[]);
    if not coalesce((v->>'recorded')::boolean, false) then v_bad := v_bad || ('rejection not recorded: ' || v::text); end if;

    -- 1. OWE
    v_owed := public.fn_ceo_decision_owe('ceo_improvement', v_key, 'it_engineer', 1, 'ZZ DEMO probe: the revision stalled');
    select status, agent, detail->>'from' as frm into s from public.agent_actions where id = v_owed;
    if s.status is distinct from 'pending' or s.agent is distinct from 'ceo' or s.frm is distinct from 'it_engineer' then
      v_bad := v_bad || ('owe: ' || coalesce(s.status, '?') || '/' || coalesce(s.agent, '?') || '/' || coalesce(s.frm, '?'));
    end if;

    -- the receiver may not close it
    begin
      perform set_config('qd.handoff_closer', 'ceo', true);
      update public.agent_actions set status = 'done' where id = v_owed;
      v_bad := v_bad || 'the CEO closed the owed decision itself'::text;
    exception when others then null;
    end;
    perform set_config('qd.handoff_closer', '', true);

    -- 2. THE CEO DECIDES
    v := public.fn_ceo_decision_close(v_key, 'withdrawn',
           'ZZ DEMO probe: withdrawn because the improvement duplicates work another seat already owns', '{}'::jsonb);
    v_round := (v->>'round_id')::bigint;
    if not coalesce((v->>'ok')::boolean, false) then v_bad := v_bad || ('decide: ' || v::text); end if;
    if not exists (select 1 from public.agent_actions where id = v_owed and detail->'ceo_decided'->>'decision' = 'withdrawn') then
      v_bad := v_bad || 'the decision was not recorded on the owed handoff'::text;
    end if;

    -- 3. DELIVERED BACK
    select id into v_back from public.agent_actions
     where kind = 'handoff' and agent = 'it_engineer' and detail->>'type' = 'ceo.decision_closed'
       and detail->>'from' = 'ceo' and detail->>'item_key' = v_key;
    if v_back is null then v_bad := v_bad || 'no ceo.decision_closed came back to it_engineer'::text;
    elsif (select status from public.agent_actions where id = v_back) <> 'done' then
      v_bad := v_bad || ('ceo.decision_closed not read: ' || (select status || ' ' || coalesce(detail->>'error', '') from public.agent_actions where id = v_back));
    end if;

    -- 4. THE ORIGINATOR RE-VERIFIED AND CLOSED IT
    select status, evidence->>'verified_by' as vb, (evidence->>'round_id')::bigint as rid into s
      from public.agent_actions where id = v_owed;
    if s.status is distinct from 'done' then v_bad := v_bad || ('owed not closed: ' || coalesce(s.status, '?')); end if;
    if s.vb is distinct from 'it_engineer' then v_bad := v_bad || ('closed by ' || coalesce(s.vb, 'nobody') || ', not it_engineer'); end if;
    if s.rid is distinct from v_round then v_bad := v_bad || 'the close does not name the round it verified'::text; end if;

    raise exception 'zz_probe_undo';
  exception when others then
    if sqlerrm <> 'zz_probe_undo' then v_bad := v_bad || ('probe error: ' || sqlerrm); end if;
  end;

  -- nothing of the cycle is left
  select (select count(*) from public.ceo_decision_round where item_key = v_key)
       + (select count(*) from public.agent_actions where detail->>'item_key' = v_key)
       + (select count(*) from public.reasoning_held_question where dedupe_key like '%' || v_key || '%') into n;
  if n <> 0 then v_bad := v_bad || ('left behind: ' || n || ' rows'); end if;

  perform set_config('qd.zz_owed_probe_verdict',
    case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end, true);
end $probe$;

select current_setting('qd.zz_owed_probe_verdict', true) as verdict;
