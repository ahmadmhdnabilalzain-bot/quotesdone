-- A REJECTION NEVER ENDS THE CYCLE: THE CEO GIVES REASONS, THE SEAT REVISES AND RESUBMITS.
--
-- Assigned: ceo (every decision recorded here is the CEO's). The revisions are each originating seat's
-- (customer_support, sales_engineer, accountant, it_engineer, marketing), asked through their own reasoning.
--
-- The founder, 29 Sep 2026 (founder_instruction 1059): approvals and rejections work like the real world. A
-- rejection never ends the cycle. The CEO gives reasons for every rejection and a proper logic for every
-- approval. The originating seat handles those comments, produces a revised version and resubmits it until it
-- is approved. The CEO always approves what is good for the company. The founder is never part of this loop
-- (his only approval left is the monthly social calendar; refunds are the CEO's).
--
-- WHAT WAS MEASURED (29 Sep 2026, the schema mirror and production, read-only).
--   1. There is no one record of the CEO's decisions on a seat's work. Each path kept its own, differently:
--      refund_ceo_review (cycles, reasons in failed), seat_deliberation_turn (verdict, agreements/disagreements),
--      ceo_experiment.approval (overwritten per iteration), agent_actions.detail.returned (overwritten per return).
--   2. A rejection dead-ended on four paths:
--      - seat_deliberation reviewed by the CEO (cross-reviews of the accountant's fee-circumvention call, the
--        sales engineer's and customer support's dispute answers, every seat's root cause; the high-stakes gate):
--        a reject left the deliberation 'reviewed' and its handoff pending; no author except marketing ever
--        calls fn_seat_deliberation_revise or _close, and _revise accepted only 'revise', never 'reject';
--      - ceo_experiment: 'reject' set status rejected and closed it; 'revise' kept it proposed but told nobody;
--      - refunds: after 3 rejected cycles the review paged the FOUNDER (fn_ceo_founder_summary 'Refund approval
--        loop stuck'), and an overdue remediation paged him too, then the refund waited on him;
--      - ceo.improvement: a return overwrote the last one's reason, with no round count, so it could loop forever.
--   3. A reasonless decision was accepted by the database: ceo_approval.rationale is NOT NULL but '' or 'ok'
--      passed (only ceo_agent's app code asked for 12 characters); a compare turn's agreements/disagreements
--      accepted "none"; an experiment approval and a sales-escalation choice stored an empty answer.
--   4. ceo_approval_decision has no caller; ceo_judgement's one caller is the CEO's own daily plan (no seat
--      submits anything there). Neither is a path a seat's work waits on.
--
-- WHAT THIS CHANGES. One mechanism, reused by every path, built on the handoffs that already own "nothing is
-- one-way" (seat_handoff_kind, fn_seat_handoff, the handoff SLA watch):
--   A. public.ceo_decision_round: one row per CEO decision on a seat's item, kept for ever (append-only).
--      approved | rejected | replaced | withdrawn, each WITH REASONS the database checks (fn_ceo_reasons_problem:
--      at least six words, not the same few repeated). Round and generation are counted by the database.
--   B. A rejection opens ceo.revise to the originating seat carrying the reasons; the seat's own reasoning
--      (surface <seat>.ceo_revision) revises and resubmits; the CEO's next decision closes that handoff.
--   C. THE LOOP GUARD. After 4 rejections of one item the database refuses a fifth: the CEO approves it, or
--      replaces or withdraws it with reasons. ceo.decision_owed carries that to the CEO (surface
--      ceo.decision_owed), never to the founder; the handoff SLA watch raises it if it waits. Replace names what
--      takes the item's place: a refund restarts its review as a new generation with a fresh count; an experiment
--      or an improvement closes and the seat is told what replaces it. An overdue refund remediation owes the same
--      choice; a refund whose checks pass meanwhile is simply approved.
--   D. Every final decision goes back to the seat that submitted it (ceo.decision_closed), with its reasons.
--   E. Wired paths: seat_deliberation reviewed by the CEO (except marketing.monthly_plan, below), refunds,
--      ceo_experiment approvals, ceo.improvement answers. ceo_approval and the sales-escalation choice refuse a
--      reasonless decision. The refund loop pages the founder no more.
--
-- WHAT THIS DOES NOT CHANGE.
--   * No money guard is touched or weakened: a00/a01/z00/z05 on refunds, a05 and the append-only rule on
--     ceo_approval, fn_refund_decide's second seat, the pause. A withdrawn refund is DECLINED through
--     fn_refund_decide (no money moves); a replaced refund only starts a fresh review. Approval still needs every
--     check green. (Seen, not changed: fn_ceo_refund_review's approval leaves the refund at 'requested' with its
--     decision linked and never calls fn_refund_decide(true), so the second-seat gate is not asked on that path;
--     z05 still holds. It is a money-path question for its own change.)
--   * marketing.monthly_plan keeps its own argument round (marketing_plan_review_turn: reasoning >= 40 chars,
--     itemised changes on a reject, at most 3 rounds, then the CEO's 'decide' with conditions). It never
--     dead-ends and its reasons are enforced already, so it is not ledgered twice here. The founder's monthly
--     calendar approval is untouched.
--   * The marketing blog/article flow (#1114) is not touched.
--   * A cross-review revises a call that was already applied (a cross-review never blocks). The approved
--     revision is recorded on the deliberation and the ledger; applying a changed call to its case stays with
--     the seat's own flow.
--
-- Idempotent and without begin/commit: the check replays it inside an aborted transaction before apply.

-- ── 1. WHAT COUNTS AS A REASON ──────────────────────────────────────────────────────────────────────────────
-- Six words, at least four of them different. Measured on production 29 Sep 2026: every ceo_approval rationale
-- written by fn_ceo_refund_review and every decision this file writes is longer; "ok", "none", "approved",
-- "see above" and "ok ok ok ok ok ok" are not.
create or replace function public.fn_ceo_reasons_problem(p_reasons text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when coalesce(cardinality(w), 0) = 0 then 'no reasons were given'
    when cardinality(w) < 6 then 'the reasons are ' || cardinality(w) || ' word(s); a decision says why in at least six'
    when (select count(distinct x) from unnest(w) x) < 4 then 'the reasons repeat the same few words'
  end
  from (select regexp_split_to_array(nullif(public.fn_seat_deliberation_norm(p_reasons), ''), ' ') w) s
$fn$;
revoke execute on function public.fn_ceo_reasons_problem(text) from public, anon, authenticated;
grant execute on function public.fn_ceo_reasons_problem(text) to service_role;

-- ── 2. THE LEDGER ────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_decision_round (
  id                 bigint generated always as identity primary key,
  path               text not null check (path in ('seat_deliberation', 'refund', 'ceo_experiment', 'ceo_improvement')),
  item_key           text not null check (btrim(item_key) <> ''),
  originator_seat    text not null references public.org_role(role_id),
  generation         integer not null default 1 check (generation >= 1),
  round              integer not null default 1 check (round >= 1),
  decision           text not null check (decision in ('approved', 'rejected', 'replaced', 'withdrawn')),
  reasons            text not null,
  version            jsonb not null default '{}'::jsonb check (jsonb_typeof(version) = 'object' and length(version::text) <= 30000),
  source_table       text,
  source_id          text,
  revise_handoff_ids bigint[] not null default '{}',
  decided_by         text not null default 'ceo' check (decided_by = 'ceo'),
  decided_at         timestamptz not null default now(),
  unique (item_key, generation, round)
);
create unique index if not exists ceo_decision_round_one_per_source
  on public.ceo_decision_round (item_key, source_table, source_id) where source_id is not null;
create index if not exists ceo_decision_round_by_item on public.ceo_decision_round (item_key, generation desc, round desc);
alter table public.ceo_decision_round enable row level security;
drop policy if exists ceo_decision_round_service_role_only on public.ceo_decision_round;
create policy ceo_decision_round_service_role_only on public.ceo_decision_round as permissive for all to public using (false) with check (false);
revoke all on public.ceo_decision_round from anon, authenticated;
comment on table public.ceo_decision_round is
  'Every CEO decision on a seat''s submitted item, one row per round, never edited (founder_instruction 1059). '
  'a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql';

-- Where an item stands: is it open, which generation and round the next decision is, how many times this
-- generation was sent back. The ONE place the round and the loop guard's count are computed (the trigger, the
-- CEO's entry and the refund review all read it). A 'replaced' item starts a new generation with a fresh count.
create or replace function public.fn_ceo_decision_next(p_item_key text)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case when l.id is null
    then jsonb_build_object('open', true, 'generation', 1, 'round', 1, 'rejections', 0)
    else jsonb_build_object('open', l.decision not in ('approved', 'withdrawn'), 'last_id', l.id, 'last_decision', l.decision,
      'last_round', l.round, 'path', l.path, 'originator', l.originator_seat,
      'generation', case when l.decision = 'replaced' then l.generation + 1 else l.generation end,
      'round', case when l.decision = 'replaced' then 1 else l.round + 1 end,
      'rejections', case when l.decision = 'replaced' then 0
                         else (select count(*) from public.ceo_decision_round r
                                where r.item_key = p_item_key and r.generation = l.generation and r.decision = 'rejected') end)
  end
  from (select 1) one
  left join lateral (select * from public.ceo_decision_round r where r.item_key = p_item_key order by r.generation desc, r.round desc limit 1) l on true
$fn$;
revoke execute on function public.fn_ceo_decision_next(text) from public, anon, authenticated;
grant execute on function public.fn_ceo_decision_next(text) to service_role;

-- What was decided on, bounded for the ledger's 30,000-character version check without losing what the paths
-- read back: every short scalar key (deliberation_id, experiment_id, refund_id, round, ...) is kept as it is and
-- the rest is kept as a cut text. 12,000 characters leave room for JSON escaping, which can double a text.
create or replace function public.fn_ceo_decision_version_cut(p jsonb)
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when length(coalesce(p, '{}'::jsonb)::text) <= 29000 then coalesce(p, '{}'::jsonb)
    else coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(p) e
                    where jsonb_typeof(e.value) in ('number', 'string', 'boolean', 'null') and length(e.value::text) <= 200), '{}'::jsonb)
         || jsonb_build_object('cut_at_12000_chars', left(p::text, 12000)) end
$fn$;
revoke execute on function public.fn_ceo_decision_version_cut(jsonb) from public, anon, authenticated;

-- The rules the database holds, so no caller can skip them.
create or replace function public.trg_ceo_decision_round_rules()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n jsonb; v_problem text;
begin
  perform pg_advisory_xact_lock(hashtext('ceo_decision_round:' || new.item_key));
  if new.originator_seat = 'ceo' or not exists (select 1 from public.org_role r where r.role_id = new.originator_seat and r.status = 'active') then
    raise exception using errcode = 'check_violation',
      message = 'CEO_DECISION: ' || coalesce(new.originator_seat, '?') || ' is not an active seat other than the CEO; the ledger holds the CEO''s decisions on a seat''s work';
  end if;
  v_problem := public.fn_ceo_reasons_problem(new.reasons);
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: every CEO decision carries its reasons (' || new.decision || ' on ' || new.item_key || '): ' || v_problem;
  end if;
  n := public.fn_ceo_decision_next(new.item_key);
  if n->>'path' is not null and n->>'path' <> new.path then
    raise exception using errcode = 'check_violation', message = 'CEO_DECISION: ' || new.item_key || ' is a ' || (n->>'path') || ' item, not ' || new.path;
  end if;
  if not (n->>'open')::boolean then
    raise exception using errcode = 'check_violation',
      message = 'ITEM_CLOSED: ' || new.item_key || ' was ' || (n->>'last_decision') || ' in round ' || (n->>'last_round') || '; a new submission is a new item';
  end if;
  new.generation := (n->>'generation')::int;
  new.round := (n->>'round')::int;
  if new.decision = 'rejected' and (n->>'rejections')::int >= 4 then
    raise exception using errcode = 'check_violation',
      message = 'ROUND_LIMIT: ' || new.item_key || ' has been sent back 4 times; the CEO now approves it, or replaces or withdraws it with reasons';
  end if;
  new.decided_by := 'ceo'; new.decided_at := now();
  return new;
end $fn$;
revoke execute on function public.trg_ceo_decision_round_rules() from public, anon, authenticated;

create or replace function public.trg_ceo_decision_round_append_only()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $fn$
begin
  raise exception using errcode = 'check_violation',
    message = 'ceo_decision_round ' || old.id || ' is history: a decision is followed by the next round, never edited or deleted';
end $fn$;
revoke execute on function public.trg_ceo_decision_round_append_only() from public, anon, authenticated;

-- What a decision sets in motion. Closes the CEO's own earlier ask (ceo.revise is closed by its originator, the
-- CEO, once the next decision shows the revision arrived), settles an owed decision, and returns a final one.
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
  for h in select a.id from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.decision_owed'
              and a.detail->>'item_key' = new.item_key loop
    perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('decided_by', 'ceo', 'decision', new.decision,
      'round_id', new.id, 'reasons', left(new.reasons, 2000)));
  end loop;
  if new.decision in ('approved', 'replaced', 'withdrawn') then
    perform public.fn_seat_handoff('ceo', new.originator_seat, 'ceo.decision_closed', 'ceo_decision_round', new.id::text,
      jsonb_build_object('round_id', new.id, 'path', new.path, 'item_key', new.item_key, 'decision', new.decision,
                         'reasons', left(new.reasons, 3000), 'generation', new.generation, 'round', new.round,
                         'version', new.version, 'source_table', new.source_table, 'source_id', new.source_id));
  end if;
  return null;
end $fn$;
revoke execute on function public.trg_ceo_decision_round_follows_through() from public, anon, authenticated;

drop trigger if exists a00_ceo_decision_round_rules on public.ceo_decision_round;
create trigger a00_ceo_decision_round_rules before insert on public.ceo_decision_round
  for each row execute function public.trg_ceo_decision_round_rules();
drop trigger if exists a01_ceo_decision_round_append_only on public.ceo_decision_round;
create trigger a01_ceo_decision_round_append_only before update or delete on public.ceo_decision_round
  for each row execute function public.trg_ceo_decision_round_append_only();
drop trigger if exists z50_ceo_decision_round_follows_through on public.ceo_decision_round;
create trigger z50_ceo_decision_round_follows_through after insert on public.ceo_decision_round
  for each row execute function public.trg_ceo_decision_round_follows_through();

-- ── 3. THE THREE CONVERSATIONS ──────────────────────────────────────────────────────────────────────────────
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select v.type, v.from_seat, v.to_seat, v.meaning, v.handler, v.reply_within, v.originator_closes,
       'scripts/sql/a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql'
  from (select 'ceo.revise' as type, 'ceo' as from_seat, s.seat as to_seat,
               'The CEO sent a submission back with its reasons: revise it to answer every reason and resubmit. The CEO closes this when it decides the next round.' as meaning,
               'fn_seat_revises_for_the_ceo' as handler, interval '3 days' as reply_within, true as originator_closes
          from unnest(array['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing']) s(seat)
        union all
        select 'ceo.decision_closed', 'ceo', s.seat,
               'The CEO''s final decision on a submission (approved, replaced or withdrawn) and its reasons, returned to the seat that submitted it.',
               'fn_seat_takes_the_ceo_decision', interval '1 day', false
          from unnest(array['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing']) s(seat)
        union all
        select 'ceo.decision_owed', s.seat, 'ceo',
               'A submission was sent back 4 times, or its revision stalled: the CEO approves it, or replaces or withdraws it with reasons. Never the founder.',
               'fn_ceo_owes_a_decision', interval '2 days', false
          from unnest(array['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing']) s(seat)) v
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ── 4. THE CEO DECIDES (the one entry every path calls) ─────────────────────────────────────────────────────
-- Owes the CEO a replace-or-withdraw on an item: one handoff per item, generation and last decided round, so an
-- owe that was settled (a stalled remediation that then moved) never swallows a later one (the loop guard).
create or replace function public.fn_ceo_decision_owe(p_path text, p_item_key text, p_originator text, p_generation integer,
  p_why text, p_last_reasons text default null, p_version jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_after int := coalesce((select max(r.round) from public.ceo_decision_round r
                                  where r.item_key = p_item_key and r.generation = p_generation), 0);
begin
  return public.fn_seat_handoff(p_originator, 'ceo', 'ceo.decision_owed', 'ceo_decision_round',
    p_item_key || ':g' || p_generation || ':after_r' || v_after,
    jsonb_build_object('path', p_path, 'item_key', p_item_key, 'generation', p_generation, 'after_round', v_after, 'why', p_why,
      'last_reasons', left(p_last_reasons, 3000), 'version', coalesce(p_version, '{}'::jsonb),
      'rounds', (select coalesce(jsonb_agg(jsonb_build_object('round', r.round, 'decision', r.decision, 'reasons', left(r.reasons, 600))
                                           order by r.round), '[]'::jsonb)
                   from public.ceo_decision_round r where r.item_key = p_item_key and r.generation = p_generation)));
end $fn$;
revoke execute on function public.fn_ceo_decision_owe(text, text, text, integer, text, text, jsonb) from public, anon, authenticated;

-- Records one decision. A rejection with no revise handoff of its own opens ceo.revise to the originator; at
-- the loop guard a fifth rejection is not written (the database would refuse it) and the CEO is owed a choice.
create or replace function public.fn_ceo_decide(p_path text, p_item_key text, p_originator text, p_decision text, p_reasons text,
  p_version jsonb default '{}'::jsonb, p_source_table text default null, p_source_id text default null,
  p_revise_handoffs bigint[] default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x public.ceo_decision_round; n jsonb; v_gen int; v_round int; v_rej int; v_h bigint;
  v_ids bigint[] := coalesce(p_revise_handoffs, '{}'); v_problem text; v_version jsonb := coalesce(p_version, '{}'::jsonb);
begin
  perform pg_advisory_xact_lock(hashtext('ceo_decision_round:' || p_item_key));
  if p_source_id is not null then
    select * into x from public.ceo_decision_round
     where item_key = p_item_key and source_table is not distinct from p_source_table and source_id = p_source_id;
    if found then
      return jsonb_build_object('recorded', true, 'already', true, 'round_id', x.id, 'decision', x.decision,
                                'generation', x.generation, 'round', x.round);
    end if;
  end if;
  n := public.fn_ceo_decision_next(p_item_key);
  if not (n->>'open')::boolean then
    return jsonb_build_object('recorded', false, 'closed', true, 'item_key', p_item_key, 'decision', n->>'last_decision', 'round_id', n->'last_id');
  end if;
  v_problem := public.fn_ceo_reasons_problem(p_reasons);
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: every CEO decision carries its reasons (' || p_decision || ' on ' || p_item_key || '): ' || v_problem;
  end if;
  -- what was decided on is kept, cut to the ledger's bound rather than refusing the decision
  v_version := public.fn_ceo_decision_version_cut(v_version);
  v_gen := (n->>'generation')::int; v_round := (n->>'round')::int; v_rej := (n->>'rejections')::int;
  if p_decision = 'rejected' then
    if v_rej >= 4 then
      v_h := public.fn_ceo_decision_owe(p_path, p_item_key, p_originator, v_gen,
               'sent back 4 times; a fifth rejection is refused, so the CEO approves it, or replaces or withdraws it', p_reasons, v_version);
      return jsonb_build_object('recorded', false, 'round_limit', true, 'item_key', p_item_key, 'generation', v_gen,
                                'rejections', v_rej, 'decision_owed_handoff', v_h);
    end if;
    if p_revise_handoffs is null then
      v_h := public.fn_seat_handoff('ceo', p_originator, 'ceo.revise', 'ceo_decision_round', p_item_key || ':g' || v_gen || ':r' || v_round,
        jsonb_build_object('path', p_path, 'item_key', p_item_key, 'generation', v_gen, 'round', v_round, 'rounds_left', 4 - v_rej - 1,
                           'reasons', left(p_reasons, 3000), 'version', v_version));
      v_ids := array[v_h];
    end if;
  end if;
  insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons, version, source_table, source_id, revise_handoff_ids)
  values (p_path, p_item_key, p_originator, p_decision, p_reasons, v_version, p_source_table, p_source_id, v_ids)
  returning * into x;
  return jsonb_build_object('recorded', true, 'round_id', x.id, 'decision', x.decision, 'generation', x.generation,
                            'round', x.round, 'revise_handoff_ids', to_jsonb(x.revise_handoff_ids));
end $fn$;
revoke execute on function public.fn_ceo_decide(text, text, text, text, text, jsonb, text, text, bigint[]) from public, anon, authenticated;
grant execute on function public.fn_ceo_decide(text, text, text, text, text, jsonb, text, text, bigint[]) to service_role;

-- The CEO replaces or withdraws an open item (its last decision was a rejection), with reasons, and the path
-- follows: a withdrawn refund is declined through fn_refund_decide, a replaced one starts a fresh review; an
-- experiment closes; an improvement is dropped. A deliberation is closed by its author when the notice
-- reaches it (fn_seat_takes_the_ceo_decision), because only the author closes a deliberation.
create or replace function public.fn_ceo_decision_close(p_item_key text, p_decision text, p_reasons text, p_detail jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare l public.ceo_decision_round; x public.ceo_decision_round; v_effect jsonb := '{}'::jsonb; v_id bigint;
  r public.refunds; i public.ceo_improvement;
begin
  if p_decision not in ('replaced', 'withdrawn') then
    raise exception 'the CEO closes an open item by replacing or withdrawing it, not %', p_decision using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('ceo_decision_round:' || p_item_key));
  select * into l from public.ceo_decision_round where item_key = p_item_key order by generation desc, round desc limit 1;
  if l.id is null or l.decision <> 'rejected' then
    return jsonb_build_object('ok', false, 'reason', 'no open item ' || p_item_key || ' (its last decision is ' || coalesce(l.decision, 'none') || ')');
  end if;
  if l.path = 'seat_deliberation' and exists (select 1 from public.seat_deliberation d
       where d.id = (l.version->>'deliberation_id')::bigint and d.status = 'open') then
    return jsonb_build_object('ok', false, 'reason', 'the revision is under review now; the CEO decides it at its review turn');
  end if;
  if l.path = 'refund' then   -- locked, and still an open request, before the ledger says anything about it
    select * into r from public.refunds where id = split_part(p_item_key, ':', 2)::bigint for update;
    if r.id is null or r.status <> 'requested' then
      return jsonb_build_object('ok', false, 'reason', 'refund ' || split_part(p_item_key, ':', 2) || ' is ' || coalesce(r.status, 'missing') || ', not an open request');
    end if;
  end if;
  insert into public.ceo_decision_round (path, item_key, originator_seat, decision, reasons, version, source_table, source_id)
  values (l.path, p_item_key, l.originator_seat, p_decision, p_reasons,
          public.fn_ceo_decision_version_cut(l.version || jsonb_build_object('closes_round_id', l.id, 'closing', coalesce(p_detail, '{}'::jsonb))),
          'ceo_decision_close', null)
  returning * into x;

  if l.path = 'refund' then
    if p_decision = 'withdrawn' then
      -- DECLINED, never paid (fn_ceo_refund_decline, the same decline the review makes). No money guard is involved.
      v_effect := jsonb_build_object('decline', public.fn_ceo_refund_decline(r.id, p_reasons, 'ceo_withdrew', l.version->'failed'));
    end if;
    -- A stalled remediation is superseded by the CEO's decision. Closing its last handoff re-runs the review
    -- (fn_ceo_refund_loop_advance), which for a replaced refund starts the fresh generation and for a declined
    -- one answers that the refund is no longer open.
    for v_id in select a.id from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                  and a.detail->>'type' = 'refund.remediate' and a.detail->>'refund_id' = r.id::text order by a.id loop
      perform public.fn_seat_handoff_complete(v_id, jsonb_build_object('superseded_by_ceo', p_decision, 'round_id', x.id,
                                                                         'reasons', left(p_reasons, 2000)));
      v_effect := v_effect || jsonb_build_object('superseded_remediation', coalesce(v_effect->'superseded_remediation', '[]'::jsonb) || to_jsonb(v_id));
    end loop;
    if p_decision = 'replaced' and not (v_effect ? 'superseded_remediation') then
      v_effect := v_effect || jsonb_build_object('review', public.fn_ceo_refund_review(r.id, 'ceo_replaced'));
    end if;
  elsif l.path = 'ceo_experiment' then
    update public.ceo_experiment
       set status = 'rejected', closed_at = now(), updated_at = now(),
           approval = coalesce(approval, '{}'::jsonb) || jsonb_build_object('closed_by_ceo', p_decision, 'reasons', left(p_reasons, 4000), 'round_id', x.id)
     where id = split_part(p_item_key, ':', 2)::bigint and status = 'proposed';
    v_effect := jsonb_build_object('experiment_closed', found);
  elsif l.path = 'ceo_improvement' then
    select * into i from public.ceo_improvement where id = split_part(p_item_key, ':', 2)::bigint for update;
    if i.id is not null and i.status in ('open', 'assigned') then
      update public.ceo_improvement set status = 'dropped', closed_at = now(), done_evidence = p_decision || ' by the CEO: ' || left(p_reasons, 3000)
       where id = i.id;
      update public.ceo_task set state = 'done', closed_at = now(), evidence = left(coalesce(evidence || E'\n', '') || p_decision || ' by the CEO: ' || p_reasons, 8000)
       where task_id = i.task_id and state in ('open', 'working', 'blocked');
      v_effect := jsonb_build_object('improvement_dropped', i.id);
    end if;
    -- the conversation closes whatever the improvement's state (it may have finished while the CEO's choice was
    -- owed, and the review sweep no longer reads a handoff that is waiting on that choice)
    if i.handoff_id is not null and exists (select 1 from public.agent_actions where id = i.handoff_id and status = 'pending') then
      perform set_config('qd.handoff_closer', 'ceo', true);
      perform public.fn_seat_handoff_complete(i.handoff_id, jsonb_build_object('verified_by', 'ceo', 'improvement_id', i.id,
        'closed', p_decision, 'reasons', left(p_reasons, 2000), 'round_id', x.id));
      perform set_config('qd.handoff_closer', '', true);
      v_effect := v_effect || jsonb_build_object('handoff_closed', i.handoff_id);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'round_id', x.id, 'decision', x.decision, 'generation', x.generation, 'round', x.round, 'effect', v_effect);
end $fn$;
revoke execute on function public.fn_ceo_decision_close(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_ceo_decision_close(text, text, text, jsonb) to service_role;

-- ── 5. THE HANDLERS ─────────────────────────────────────────────────────────────────────────────────────────
-- ceo.revise: the originating seat reasons its revision, with the CEO's reasons and its submission in front of it.
create or replace function public.fn_seat_revises_for_the_ceo(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_held bigint; v_fields jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_held := public.fn_seat_duty_reason(a.agent, a.agent || '.ceo_revision',
    'The CEO sent your submission back (round ' || coalesce(a.detail->>'round', '?') || ', ' || coalesce(a.detail->>'rounds_left', '?')
      || ' more before the CEO must replace or withdraw it). Read each of the CEO''s reasons. Produce a revised version that answers '
      || 'every one of them, or where you are right keep it and answer each reason with evidence. The CEO reviews what you resubmit.',
    '[{"id":"revised","meaning":"the submission is revised so that it answers every reason the CEO gave"},{"id":"defended","meaning":"the submission stands, and each reason is answered with evidence"}]'::jsonb,
    jsonb_build_object('path', a.detail->>'path', 'item_key', a.detail->>'item_key', 'round', a.detail->'round',
                       'ceo_reasons', a.detail->>'reasons', 'submission', a.detail->'version'),
    jsonb_build_object('handoff_id', p_id, 'path', a.detail->>'path', 'item_key', a.detail->>'item_key'),
    'ceo_revision:' || (a.detail->>'item_key') || ':g' || coalesce(a.detail->>'generation', '1') || ':r' || coalesce(a.detail->>'round', '1'));
  v_fields := jsonb_build_array(
    jsonb_build_object('key', 'revision', 'question', 'the revised submission, complete, as the CEO should now review it'),
    jsonb_build_object('key', 'answers', 'question', 'for each of the CEO''s reasons: what changed, or the evidence that answers it'));
  if a.detail->>'path' = 'ceo_experiment' then
    v_fields := v_fields || jsonb_build_array(
      jsonb_build_object('key', 'hypothesis', 'question', 'the revised hypothesis (blank keeps it)'),
      jsonb_build_object('key', 'approach', 'question', 'the revised approach (blank keeps it)'),
      jsonb_build_object('key', 'target', 'question', 'the revised target, a number (blank keeps it)'),
      jsonb_build_object('key', 'days', 'question', 'the revised run length in days, 7 to 365 (blank keeps it)'));
  end if;
  perform public.fn_ambition_ask_fields(v_held, v_fields);
  return jsonb_build_object('waiting', a.agent || ' revises and resubmits ' || coalesce(a.detail->>'item_key', '?') || ' (held question ' || v_held || ')',
                            'held_id', v_held);
end $fn$;
revoke execute on function public.fn_seat_revises_for_the_ceo(bigint) from public, anon, authenticated;

-- The seat's reasoned revision is resubmitted along its path.
create or replace function public.fn_ceo_revision_applies(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; a public.agent_actions; v_choice text; v_f jsonb; v_problem text; v jsonb;
  d public.seat_deliberation; e public.ceo_experiment; v_model text; v_target numeric; v_days int; v_revised jsonb;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_f := public.fn_ambition_fields(p_result);
  -- a round the CEO has already left takes no revision (checked first, so a stale answer is never re-reasoned)
  select * into a from public.agent_actions where id = (r.subject->>'handoff_id')::bigint and kind = 'handoff';
  if a.id is null or a.status <> 'pending' then
    return jsonb_build_object('applied', true, 'already', 'the CEO has moved on from this round');
  end if;
  -- A revision answers the CEO's reasons; an empty one is not a resubmission and is reasoned again.
  v_problem := public.fn_ceo_reasons_problem(coalesce(v_f->>'answers', '') || ' ' || coalesce(p_result->>'answer', ''));
  if v_problem is not null then
    raise exception using errcode = 'check_violation', message = 'UNANSWERED_REVISION: a revision answers the CEO''s reasons: ' || v_problem;
  end if;
  v_model := coalesce((select m.model_id from public.model_registry m where m.model_id = p_result->>'model'), 'deterministic');

  if a.detail->>'path' = 'seat_deliberation' then
    select * into d from public.seat_deliberation where id = (a.detail->'version'->>'deliberation_id')::bigint;
    -- a deliberation that has no round left (opened before the five-round rule, or at its cap) cannot take the
    -- revision: the CEO is owed the choice instead of the seat's answer failing on every retry
    if d.round >= d.max_rounds then
      v := jsonb_build_object('decision_owed', public.fn_ceo_decision_owe('seat_deliberation', a.detail->>'item_key', a.agent,
             coalesce((a.detail->>'generation')::int, 1), 'revised with no round left in its deliberation (' || d.round || ' of ' || d.max_rounds || ')',
             a.detail->>'reasons', a.detail->'version'));
      update public.agent_actions set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('resubmitted_at', now(), 'held_id', p_id,
               'answers', left(coalesce(v_f->>'answers', ''), 3000), 'no_round_left', v) where id = a.id;
      return jsonb_build_object('applied', true, 'item_key', a.detail->>'item_key', 'resubmission', v);
    end if;
    v_revised := d.proposal || jsonb_build_object('revision', coalesce(v_f->>'revision', p_result->>'answer'), 'answers_to_the_ceo', v_f->>'answers',
                                                  'revision_choice', v_choice, 'revises_round', a.detail->'round');
    if length(v_revised::text) > 28000 then   -- seat_deliberation.proposal holds 30,000 characters
      v_revised := jsonb_build_object('previous_proposal_cut', left(d.proposal::text, 6000),
        'revision', left(coalesce(v_f->>'revision', p_result->>'answer'), 12000), 'answers_to_the_ceo', left(v_f->>'answers', 4000),
        'revision_choice', v_choice, 'revises_round', a.detail->'round');
    end if;
    v := public.fn_seat_deliberation_revise(d.id, v_revised, v_model);
  elsif a.detail->>'path' = 'ceo_experiment' then
    select * into e from public.ceo_experiment where id = (a.detail->'version'->>'experiment_id')::bigint;
    v_target := case when coalesce(v_f->>'target', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_f->>'target')::numeric else e.target end;
    v_days := case when coalesce(v_f->>'days', '') ~ '^\d{1,3}$' and (v_f->>'days')::int between 7 and 365 then (v_f->>'days')::int else e.days end;
    v := jsonb_build_object('experiment_id', public.fn_ceo_experiment_propose(e.proposed_by, e.key,
           coalesce(nullif(btrim(v_f->>'hypothesis'), ''), e.hypothesis), e.metric_key, e.metric_definition, e.baseline, e.baseline_note,
           v_target, e.direction, coalesce(nullif(btrim(v_f->>'approach'), ''), e.approach), e.starts_on, v_days));
  else
    raise exception 'no revision route for a % item (%)', coalesce(a.detail->>'path', '?'), a.detail->>'item_key';
  end if;
  update public.agent_actions
     set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('resubmitted_at', now(), 'held_id', p_id, 'choice', v_choice,
                      'answers', left(coalesce(v_f->>'answers', ''), 3000), 'model', v_model, 'resubmission', v),
         detail = detail || jsonb_build_object('awaiting', 'the CEO decides the resubmitted round')
   where id = a.id;
  return jsonb_build_object('applied', true, 'item_key', a.detail->>'item_key', 'choice', v_choice, 'resubmission', v);
end $fn$;
revoke execute on function public.fn_ceo_revision_applies(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_reason_apply_customer_support__ceo_revision(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$ select public.fn_ceo_revision_applies(p_id, p_result) $fn$;
create or replace function public.fn_reason_apply_sales_engineer__ceo_revision(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$ select public.fn_ceo_revision_applies(p_id, p_result) $fn$;
create or replace function public.fn_reason_apply_accountant__ceo_revision(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$ select public.fn_ceo_revision_applies(p_id, p_result) $fn$;
create or replace function public.fn_reason_apply_it_engineer__ceo_revision(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$ select public.fn_ceo_revision_applies(p_id, p_result) $fn$;
create or replace function public.fn_reason_apply_marketing__ceo_revision(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$ select public.fn_ceo_revision_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_customer_support__ceo_revision(bigint, jsonb) from public, anon, authenticated;
revoke execute on function public.fn_reason_apply_sales_engineer__ceo_revision(bigint, jsonb) from public, anon, authenticated;
revoke execute on function public.fn_reason_apply_accountant__ceo_revision(bigint, jsonb) from public, anon, authenticated;
revoke execute on function public.fn_reason_apply_it_engineer__ceo_revision(bigint, jsonb) from public, anon, authenticated;
revoke execute on function public.fn_reason_apply_marketing__ceo_revision(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_customer_support__ceo_revision(bigint, jsonb) to service_role;
grant execute on function public.fn_reason_apply_sales_engineer__ceo_revision(bigint, jsonb) to service_role;
grant execute on function public.fn_reason_apply_accountant__ceo_revision(bigint, jsonb) to service_role;
grant execute on function public.fn_reason_apply_it_engineer__ceo_revision(bigint, jsonb) to service_role;
grant execute on function public.fn_reason_apply_marketing__ceo_revision(bigint, jsonb) to service_role;

-- ceo.decision_closed: the seat reads the CEO's final decision. A deliberation is closed by its author here --
-- except a high-stakes one: the gate keeps reading its last verdict (approved: the decision proceeds; withdrawn
-- or replaced: it stays refused), and closing it would make the next gate call open a fresh review of the same
-- decision with a fresh count, undoing the CEO's withdrawal.
create or replace function public.fn_seat_takes_the_ceo_decision(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; d public.seat_deliberation; v_closed jsonb;
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
      -- the conversation is answered and closed by its author; the deliberation row stays for the gate to read
      perform set_config('qd.handoff_closer', a.agent, true);
      perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('kind', 'deliberation.review', 'deliberation_id', d.id,
        'ceo_decision', a.detail->>'decision', 'reasons', left(a.detail->>'reasons', 2000), 'closed_by', a.agent));
      perform set_config('qd.handoff_closer', '', true);
      v_closed := jsonb_build_object('handoff_closed', d.handoff_id, 'deliberation_kept_for_the_gate', d.id);
    end if;
  end if;
  return jsonb_build_object('read_by', a.agent, 'decision', a.detail->>'decision', 'item_key', a.detail->>'item_key',
                            'reasons', left(a.detail->>'reasons', 600), 'deliberation_closed', v_closed);
end $fn$;
revoke execute on function public.fn_seat_takes_the_ceo_decision(bigint) from public, anon, authenticated;

-- ceo.decision_owed: the CEO reasons its choice (replace or withdraw), never the founder.
create or replace function public.fn_ceo_owes_a_decision(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_held bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_held := public.fn_seat_duty_reason('ceo', 'ceo.decision_owed',
    'A seat''s submission has been ' || coalesce(a.detail->>'why', 'sent back 4 times') || '. As the chief executive, decide what is good for '
      || 'the company: replace it (a different piece of work, owner or approach takes its place) or withdraw it (it does not go ahead). '
      || 'Say why, answering the reasons given in every round.',
    '[{"id":"replace","meaning":"replace the item: say in your reasons what takes its place (other work, owner or approach). A refund restarts its review with a fresh count; any other item closes and the seat is told what replaces it"},{"id":"withdraw","meaning":"withdraw the item: it does not go ahead (a refund is declined, never paid), and the seat is told why"}]'::jsonb,
    jsonb_build_object('path', a.detail->>'path', 'item_key', a.detail->>'item_key', 'rounds', a.detail->'rounds',
                       'last_reasons', a.detail->>'last_reasons', 'submission', a.detail->'version'),
    jsonb_build_object('handoff_id', p_id, 'item_key', a.detail->>'item_key'),
    'ceo_decision_owed:' || (a.detail->>'item_key') || ':g' || coalesce(a.detail->>'generation', '1') || ':after_r' || coalesce(a.detail->>'after_round', '0'));
  return jsonb_build_object('waiting', 'the CEO replaces or withdraws ' || coalesce(a.detail->>'item_key', '?') || ', with reasons (held question ' || v_held || ')',
                            'held_id', v_held);
end $fn$;
revoke execute on function public.fn_ceo_owes_a_decision(bigint) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__decision_owed(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; v_choice text; v_hid bigint; v_review jsonb; v jsonb; x record;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_hid := (r.subject->>'handoff_id')::bigint;
  -- A REFUND IS RE-MEASURED FIRST: one whose checks now pass is approved, which settles what was owed, so a
  -- payable refund is never declined on a stale reading.
  if split_part(r.subject->>'item_key', ':', 1) = 'refunds' then
    -- a remediation whose checks now pass is closed first (as fn_ceo_refund_loop_sweep would on its next run);
    -- closing the last one re-runs the review through fn_ceo_refund_loop_advance
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
  -- a stale answer changes nothing: the item moved on (a new round, an approval) and settled what was owed
  if not exists (select 1 from public.agent_actions a where a.id = v_hid and a.status = 'pending') then
    return jsonb_build_object('applied', true, 'already', 'the owed decision was settled by the item''s next round', 'review', v_review);
  end if;
  v := public.fn_ceo_decision_close(r.subject->>'item_key', case v_choice when 'replace' then 'replaced' else 'withdrawn' end,
    coalesce(p_result->>'answer', ''), jsonb_build_object('held_id', p_id, 'model', p_result->>'model', 'fields', public.fn_ambition_fields(p_result)));
  -- nothing is left to decide (the item closed or the refund left 'requested' another way): the owed conversation
  -- ends with that fact instead of waiting for ever. An item under review stays owed; its review turn settles it.
  if not coalesce((v->>'ok')::boolean, false) and coalesce(v->>'reason', '') !~ 'under review' then
    perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('decided_by', 'ceo', 'nothing_to_close', v->>'reason', 'held_id', p_id));
  end if;
  return v || jsonb_build_object('review', v_review);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__decision_owed(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__decision_owed(bigint, jsonb) to service_role;

-- ── 6. PATH: SEAT_DELIBERATION REVIEWED BY THE CEO ──────────────────────────────────────────────────────────
-- Five rounds (the loop guard's four rejections and the round after) for a deliberation the CEO reviews;
-- marketing.monthly_plan keeps the 3 its own loop sets after open. The 1..3 bound becomes 1..5.
alter table public.seat_deliberation drop constraint if exists seat_deliberation_max_rounds_check;
alter table public.seat_deliberation add constraint seat_deliberation_max_rounds_check check (max_rounds >= 1 and max_rounds <= 5);
update public.seat_deliberation set max_rounds = 5
 where reviewer_seat = 'ceo' and kind <> 'marketing.monthly_plan' and status <> 'closed' and max_rounds < 5;

-- From a_high_stakes_decision_waits_for_a_second_seat_on_another_family.sql (MANIFEST 1877); only the max_rounds line is new.
create or replace function public.trg_seat_deliberation_guard()
 returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
begin
  if new.author_model = 'deterministic' then
    new.author_provider := 'deterministic';   -- a decision taken by code (29 Sep 2026, instruction 1009)
  elsif tg_op = 'INSERT' or new.author_model is distinct from old.author_model then
    select lower(btrim(r.provider)) into new.author_provider from public.model_registry r where r.model_id = new.author_model;
    if new.author_provider is null then
      raise exception 'seat_deliberation: author model % is not in model_registry; its family cannot be known', new.author_model;
    end if;
  end if;
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.org_agents a where a.agent_key = new.author_seat and a.active)
       or not exists (select 1 from public.org_agents a where a.agent_key = new.reviewer_seat and a.active) then
      raise exception 'seat_deliberation: % and % must both be active seats', new.author_seat, new.reviewer_seat;
    end if;
    -- A REJECTION NEVER ENDS THE CYCLE (founder_instruction 1059): the CEO's reviews run to the loop guard.
    if new.reviewer_seat = 'ceo' and new.kind <> 'marketing.monthly_plan' then new.max_rounds := 5; end if;
  end if;
  return new;
end $function$;

-- From a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql (MANIFEST 1685); a 'reject' is revised too.
create or replace function public.fn_seat_deliberation_revise(p_id bigint, p_proposal jsonb, p_author_model text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare d public.seat_deliberation; v_last text;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  select t.verdict into v_last from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'compare' and t.status = 'recorded' and t.round = d.round;
  -- A CEO rejection is sent back to be revised (founder_instruction 1059); another seat's reject stays final (the
  -- accountant's second-seat refusal of a CEO money decision is not something the CEO re-argues round after round).
  if d.status <> 'reviewed' or not (v_last = 'revise' or (v_last = 'reject' and d.reviewer_seat = 'ceo')) or v_last is null then
    raise exception 'deliberation % can be revised only after the reviewer asked for a revision (or the CEO rejected it)', p_id;
  end if;
  if d.round >= d.max_rounds then
    raise exception 'deliberation % is at its last round (%); the author closes it with the reviewer''s verdict', p_id, d.max_rounds;
  end if;
  update public.seat_deliberation set round = round + 1, proposal = p_proposal, status = 'open' where id = p_id;
  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, model, output)
  values (p_id, d.round + 1, 'proposal', d.author_seat, 'recorded', p_author_model, p_proposal);
  return public.fn_seat_deliberation_step(p_id);
end $function$;

-- From a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql (MANIFEST 1685); the CEO's comparison is now a
-- decision in the ledger: approve -> approved with its agreements as the logic; revise or reject -> rejected with
-- its disagreements as the reasons, and the author is asked to revise.
create or replace function public.fn_seat_deliberation_record(p_id bigint, p_phase text, p_model text, p_output jsonb,
  p_prompt_tokens integer default null::integer, p_output_tokens integer default null::integer,
  p_status text default 'recorded'::text, p_why text default null::text)
 returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare d public.seat_deliberation; v_id bigint; o jsonb := coalesce(p_output, '{}'::jsonb); v_verdict text; v_reasons text;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if d.status <> 'open' then raise exception 'seat_deliberation % is %, not open', p_id, d.status; end if;
  if p_phase not in ('blind', 'compare') then raise exception 'only the reviewer''s blind and compare turns are recorded here'; end if;
  -- A gateway that held the call after the step did not: "held, not run" is recorded once per round and phase.
  if p_status = 'held_not_run' then
    select t.id into v_id from public.seat_deliberation_turn t where t.deliberation_id = p_id and t.round = d.round
       and t.phase = p_phase and t.status = 'held_not_run';
    if v_id is not null then return v_id; end if;
  end if;

  insert into public.seat_deliberation_turn (deliberation_id, round, phase, seat, status, task_class, model, verdict,
    steelman_against, agreements, disagreements, output, why, prompt_tokens, output_tokens, payload_sha256)
  values (p_id, d.round, p_phase, d.reviewer_seat, p_status, 'seat_deliberation_' || p_phase, p_model,
          case when p_status = 'recorded' then lower(o->>'verdict') end,
          case when jsonb_typeof(o->'steelman_against') = 'string' then o->>'steelman_against' end, o->>'agreements', o->>'disagreements', o, p_why, p_prompt_tokens, p_output_tokens,
          o->>'_payload_sha256')
  returning id into v_id;

  if p_status = 'recorded' and p_phase = 'compare' then
    update public.seat_deliberation set status = 'reviewed' where id = p_id;
    update public.agent_actions
       set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('deliberation_id', p_id, 'round', d.round,
                        'verdict', lower(o->>'verdict'), 'compare_turn_id', v_id, 'reviewed_at', now()),
           detail = detail || jsonb_build_object('awaiting', d.author_seat || ' closes the deliberation')
     where id = d.handoff_id and kind = 'handoff';
    perform public.fn_seat_handoff_event(d.handoff_id, 'reviewed');
    -- THE CEO'S DECISION CARRIES ITS REASONS AND A REJECTION LOOPS BACK (founder_instruction 1059).
    if d.reviewer_seat = 'ceo' and d.kind <> 'marketing.monthly_plan' then
      v_verdict := lower(o->>'verdict');
      -- the reasons are the side the verdict rests on, with the CEO's own reasoning when that side is too thin
      v_reasons := btrim(coalesce(case when v_verdict = 'approve' then o->>'agreements' else o->>'disagreements' end, ''));
      if public.fn_ceo_reasons_problem(v_reasons) is not null and coalesce(btrim(o->>'reasoning'), '') <> '' then
        v_reasons := btrim(v_reasons || E'\n' || (o->>'reasoning'));
      end if;
      perform public.fn_ceo_decide('seat_deliberation', 'seat_deliberation:' || p_id, d.author_seat,
        case when v_verdict = 'approve' then 'approved' else 'rejected' end,
        v_reasons,
        jsonb_build_object('deliberation_id', p_id, 'kind', d.kind, 'round', d.round, 'verdict', v_verdict, 'compare_turn_id', v_id,
                           'subject_table', d.subject_table, 'subject_id', d.subject_id, 'question', left(d.question, 1000),
                           'proposal', case when length(d.proposal::text) <= 20000 then d.proposal
                                            else jsonb_build_object('cut_at_20000_chars', left(d.proposal::text, 20000)) end),
        'seat_deliberation_turn', v_id::text);
    end if;
  end if;
  return v_id;
end $function$;

-- From a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql (MANIFEST 1685); the CEO is told its comparison
-- is a decision whose reasons the database checks, so a model is not paid for a turn the ledger would refuse.
create or replace function public.fn_seat_deliberation_compare_payload(p_id bigint)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $function$
declare d public.seat_deliberation; b public.seat_deliberation_turn;
begin
  select * into d from public.seat_deliberation where id = p_id;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  select * into b from public.seat_deliberation_turn t
   where t.deliberation_id = p_id and t.phase = 'blind' and t.status = 'recorded' order by t.round desc limit 1;
  if not found then
    raise exception 'BLIND_FIRST: deliberation % has no recorded blind verdict; the proposal is not revealed before it', p_id;
  end if;
  return jsonb_build_object(
    'phase', 'compare', 'deliberation_id', d.id, 'kind', d.kind, 'round', d.round,
    'author_seat', d.author_seat, 'reviewer_seat', d.reviewer_seat,
    'question', d.question, 'evidence', d.evidence,
    'independent_context', public.fn_seat_deliberation_independent_context(d.reviewer_seat),
    'your_blind_verdict', jsonb_build_object('verdict', b.verdict, 'steelman_against', b.steelman_against, 'output', b.output),
    'proposal', d.proposal,
    'instructions', 'The ' || d.author_seat || ' seat''s proposal is now revealed. Compare it with YOUR blind verdict above. '
      || 'State explicitly what you agree with and what you do not (write "none" if there is nothing). Give the strongest '
      || 'case AGAINST the proposal even if you approve; an approval without it is rejected as malformed. Do not agree '
      || 'because the proposal is confident, and do not disagree for its own sake.'
      || case when d.reviewer_seat = 'ceo' and d.kind <> 'marketing.monthly_plan'
              then ' As the chief executive your verdict is a decision: when you approve, your agreements are its logic; when you '
                || 'revise or reject, your disagreements are its reasons and go back to the ' || d.author_seat || ' seat to answer '
                || 'in a revised version. Write that side as at least one full sentence, never "none"; a decision without reasons is refused.'
              else '' end,
    'output_contract', jsonb_build_object('verdict', 'approve|reject|revise', 'agreements', 'text', 'disagreements', 'text',
      'steelman_against', 'text, at least one full sentence', 'reasoning', 'text',
      'changed_from_blind_because', 'text, or "unchanged"'));
end $function$;

-- ── 7. PATH: REFUNDS ────────────────────────────────────────────────────────────────────────────────────────
-- A CEO approval says why, in the database, whoever writes it (ceo_agent decide asked for 12 characters in app
-- code only). a04 runs before a05_ceo_refund_approval_checks_the_process; both stay.
create or replace function public.trg_ceo_approval_carries_its_reasons()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_problem text := public.fn_ceo_reasons_problem(new.rationale);
begin
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: a CEO ' || new.decision || ' of ' || new.subject_kind || ' ' || new.subject_id || ' says why: ' || v_problem;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_ceo_approval_carries_its_reasons() from public, anon, authenticated;
drop trigger if exists a04_ceo_approval_carries_its_reasons on public.ceo_approval;
create trigger a04_ceo_approval_carries_its_reasons before insert on public.ceo_approval
  for each row execute function public.trg_ceo_approval_carries_its_reasons();

-- The one way the CEO declines a refund, from its review (a check that cannot be fixed) or from its withdrawal
-- at the loop guard: ceo_approval records the refusal with the reasons, refund_ceo_review seals a declined cycle,
-- and fn_refund_decide sets it rejected (the refund.declined follow-through tells the customer why). No money moves.
create or replace function public.fn_ceo_refund_decline(p_refund_id bigint, p_reasons text, p_trigger text, p_failed jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.refunds; v_dec bigint; v_rev bigint; v_cycle int;
begin
  select * into r from public.refunds where id = p_refund_id for update;
  if not found or r.status <> 'requested' then
    return jsonb_build_object('ok', false, 'reason', 'refund ' || p_refund_id || ' is ' || coalesce(r.status, 'missing') || ', not an open request');
  end if;
  insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
  values ('refund', r.id::text, 'refused', 'ceo', round(r.amount_fils / 100.0, 2), left(p_reasons, 2000)) returning decision_id into v_dec;
  select coalesce(max(cycle), 0) + 1 into v_cycle from public.refund_ceo_review where refund_id = r.id;
  insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, decision_id, trigger, sealed)
  values (r.id, r.transaction_id, v_cycle, 'declined', coalesce(p_failed, '[]'::jsonb), v_dec, p_trigger, true) returning id into v_rev;
  return jsonb_build_object('ok', true, 'decision_id', v_dec, 'review_id', v_rev, 'cycle', v_cycle,
                            'refund', public.fn_refund_decide(r.id, false, 'ceo', left(p_reasons, 900)));
end $fn$;
revoke execute on function public.fn_ceo_refund_decline(bigint, text, text, jsonb) from public, anon, authenticated;

-- From routing_and_ceo_decisions_are_reasoned_not_word_matched.sql (MANIFEST 1709). New: each outcome is a round
-- in the ledger (approved / withdrawn for a decline / rejected with the remediation handoffs as its revise asks),
-- and the loop guard after 4 rejections owes the CEO a replace-or-withdraw instead of paging the founder.
create or replace function public.fn_ceo_refund_review(p_refund_id bigint, p_trigger text default 'manual'::text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  r public.refunds; v jsonb; v_cycle int; v_nonrem jsonb; v_rev bigint; v_dec bigint; x record; v_task bigint;
  v_tasks jsonb := '[]'::jsonb; v_rat text; v_deadline timestamptz; v_chase int; v_adv jsonb;
  v_wait boolean := false;   -- a check still being reasoned (23 Sep 2026)
  v_item text := 'refunds:' || p_refund_id; v_ids bigint[] := '{}'; v_cyc jsonb;
begin
  select * into r from public.refunds where id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'reason', 'refund is ' || r.status || '; the CEO reviews only an open request'); end if;
  if r.refund_decision_id is not null then return jsonb_build_object('ok', true, 'outcome', 'already_approved', 'decision_id', r.refund_decision_id); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = r.id::text and a.status = 'pending') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_remediation');
  end if;
  select coalesce(max(cycle), 0) + 1 into v_cycle from public.refund_ceo_review where refund_id = r.id;
  v := public.fn_ceo_refund_checklist(r.transaction_id, 'approve', true);

  if (v->>'ok')::boolean then
    v_rat := 'Cycle ' || v_cycle || ': every pre-approval check passed ('
          || (select string_agg(i->>'item', ', ') from jsonb_array_elements(v->'items') i) || '). Evidence: refund_ceo_check for this transaction.';
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'approved', 'ceo', round(r.amount_fils / 100.0, 2), v_rat) returning decision_id into v_dec;
    update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now(), decision_note = v_rat where id = r.id;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'approved', v_dec, p_trigger, true) returning id into v_rev;
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'approved', v_rat,
               jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'decision_id', v_dec), 'refund_ceo_review', v_rev::text);
    return jsonb_build_object('ok', true, 'outcome', 'approved', 'cycle', v_cycle, 'decision_id', v_dec, 'round', v_cyc);
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_nonrem from jsonb_array_elements(v->'failed') i where not coalesce((i->>'remediable')::boolean, false);
  if jsonb_array_length(v_nonrem) > 0 then
    v_rat := 'Declined, because these checks cannot be fixed and the refund is not paid: '
          || (select string_agg((i->>'item') || ' — ' || coalesce(i->>'reason', ''), '; ') from jsonb_array_elements(v_nonrem) i);
    v_adv := public.fn_ceo_refund_decline(r.id, v_rat, p_trigger, v->'failed');
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'withdrawn', left(v_rat, 3000),
               jsonb_build_object('refund_id', r.id, 'cycle', v_adv->'cycle', 'decision_id', v_adv->'decision_id', 'failed', v->'failed'),
               'refund_ceo_review', v_adv->>'review_id');
    return jsonb_build_object('ok', true, 'outcome', 'declined', 'cycle', v_adv->'cycle', 'reason', v_rat, 'round', v_cyc);
  end if;

  -- A CHECK THAT IS STILL BEING REASONED IS NOT A FAILURE (23 Sep 2026, founder_instruction 886-903).
  -- Under the model hold the off-platform notes wait in the CEO seat's reasoning queue. Counting that as a
  -- rejected cycle would hand work to nobody who can do it. So the refund rests, visible, with no cycle spent;
  -- the reasoned answer re-runs this review (fn_reason_apply_ceo__refund_off_platform).
  -- Only the unread note fails: the refund rests. Other remediable failures still go to their owners below.
  v_wait := exists (select 1 from jsonb_array_elements(v->'failed') i where i->>'kind' = 'needs_reasoning');
  if v_wait and not exists (select 1 from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_reasoning',
      'held', (select jsonb_agg(i->'evidence') from jsonb_array_elements(v->'failed') i where i->>'kind' = 'needs_reasoning'));
  end if;

  v_rat := 'Cycle ' || v_cycle || ': these checks still fail and go back to the seats that own them: '
        || (select string_agg((i->>'item') || ' (' || coalesce(i->>'reason', 'no reason recorded') || ')', '; ')
              from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning');

  -- THE LOOP GUARD (founder_instruction 1059), in place of the founder page after three cycles: after 4
  -- rejections the CEO approves, replaces or withdraws, with reasons. The escalated row records the stop, once:
  -- while the CEO's choice is owed a re-run answers that and writes nothing. (An approval above is never held by
  -- it: a refund whose checks now pass is approved, which settles what was owed.)
  if (public.fn_ceo_decision_next(v_item)->>'rejections')::int >= 4 then
    -- a check still being reasoned is not a rejection the CEO must act on: the refund rests, as above
    if v_wait then
      return jsonb_build_object('ok', false, 'outcome', 'waiting_on_reasoning', 'at_loop_guard', true);
    end if;
    if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                 and a.detail->>'type' = 'ceo.decision_owed' and a.detail->>'item_key' = v_item) then
      return jsonb_build_object('ok', false, 'outcome', 'awaiting_ceo_replace_or_withdraw', 'cycle', v_cycle - 1);
    end if;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'escalated', v->'failed', p_trigger, true) returning id into v_rev;
    v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'rejected', v_rat,
               jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'failed', v->'failed'), 'refund_ceo_review', v_rev::text);
    return jsonb_build_object('ok', false, 'outcome', 'awaiting_ceo_replace_or_withdraw', 'cycle', v_cycle, 'round', v_cyc);
  end if;

  insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger)
  values (r.id, r.transaction_id, v_cycle, 'rejected', v->'failed', p_trigger) returning id into v_rev;
  select chase_after_working_days into v_chase from public.pricing_config order by id limit 1;
  v_deadline := public.fn_add_working_days(now(), coalesce(v_chase, 3));
  for x in
    select i->>'owner' as owner, i->>'remedy_key' as rk, jsonb_agg(i->>'item') as checks, jsonb_agg(i) as items
      from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning' group by 1, 2 order by 1, 2
  loop
    v_task := public.fn_seat_handoff('ceo', x.owner, 'refund.remediate', 'refunds', r.id || ':c' || v_cycle || ':' || x.rk,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'cycle', v_cycle, 'review_id', v_rev,
                         'remedy_key', x.rk, 'checks', x.checks, 'items', x.items, 'deadline', v_deadline));
    v_tasks := v_tasks || jsonb_build_object('handoff_id', v_task, 'owner', x.owner, 'checks', x.checks);
    v_ids := v_ids || v_task;
  end loop;
  update public.refund_ceo_review set sealed = true, tasks = v_tasks where id = v_rev;
  v_cyc := public.fn_ceo_decide('refund', v_item, 'accountant', 'rejected', v_rat,
             jsonb_build_object('refund_id', r.id, 'cycle', v_cycle, 'failed', v->'failed', 'tasks', v_tasks), 'refund_ceo_review', v_rev::text, v_ids);
  v_adv := public.fn_ceo_refund_loop_advance(r.id);
  return jsonb_build_object('ok', false, 'outcome', 'rejected', 'cycle', v_cycle, 'tasks', v_tasks, 'advance', v_adv, 'round', v_cyc);
end $function$;

-- From payments_are_the_accountant_and_the_seats_close_every_refund_together.sql (MANIFEST 1368). An overdue
-- remediation no longer pages the founder: the CEO is owed a replace-or-withdraw on the refund.
create or replace function public.fn_ceo_refund_loop_sweep()
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare a record; v jsonb; n_closed int := 0; n_overdue int := 0; n_raised int := 0; x record; l public.ceo_decision_round;
begin
  for a in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'refund.remediate' and status = 'pending' order by id loop
    v := public.fn_ceo_refund_checklist((a.detail->>'transaction_id')::uuid, 'approve', false);
    if not exists (select 1 from jsonb_array_elements(v->'items') i
                    where (a.detail->'checks') ? (i->>'item') and not coalesce((i->>'passed')::boolean, false)) then
      perform public.fn_seat_handoff_complete(a.id, jsonb_build_object('resolved_by', 're-measured', 'checks', a.detail->'checks'));
      n_closed := n_closed + 1;
    elsif now() > (a.detail->>'deadline')::timestamptz and not (a.detail ? 'escalated_at') then
      select * into l from public.ceo_decision_round where item_key = 'refunds:' || (a.detail->>'refund_id')
       order by generation desc, round desc limit 1;
      -- marked escalated only once the CEO is actually owed the choice (a remediation opened before the ledger has
      -- no round to decide on; it stays unmarked and the handoff SLA watch keeps it in view)
      if l.decision = 'rejected' then
        perform public.fn_ceo_decision_owe('refund', l.item_key, a.agent, l.generation,
          'left with its remediation undone past the deadline ' || to_char((a.detail->>'deadline')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY')
            || ' (the ' || a.agent || ' has not closed ' || coalesce(a.detail->>'checks', '?') || ')',
          l.reasons, l.version);
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_at', now()) where id = a.id;
        n_overdue := n_overdue + 1;
      end if;
    end if;
  end loop;

  if not public.fn_refunds_paused() then
    for x in select t.id from public.transactions t
              where t.refund_status in ('refunded', 'succeeded') and t.refund_amount_aed is not null
                and coalesce(t.refund_reason, 'supplier_unresponsive') = 'supplier_unresponsive'
                and not exists (select 1 from public.supplier_dues d where d.transaction_id = t.id and coalesce(d.status, '') <> 'cancelled') loop
      v := public.fn_accountant_raise_nonresponse_charge(x.id, true);
      if coalesce((v->>'created')::boolean, false) then n_raised := n_raised + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('remediation_closed', n_closed, 'remediation_overdue', n_overdue, 'held_charges_raised', n_raised);
end $function$;

-- ── 8. PATH: EXPERIMENTS A SEAT PROPOSES ────────────────────────────────────────────────────────────────────
-- From the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql (MANIFEST 1746). A seat's proposal
-- is no longer closed by a reject: revise and reject both send it back with the CEO's reasons, and the proposer
-- revises through fn_ceo_experiment_propose (same key, next iteration). The CEO's own experiments keep their old
-- ending, with reasons now required.
create or replace function public.fn_reason_apply_ceo__experiment_approval(p_id bigint, p_result jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare r public.reasoning_held_question; e public.ceo_experiment; v_choice text; v_f jsonb; v_review jsonb; v_owner text; v_days int;
  v_today date := (now() at time zone 'Asia/Dubai')::date; v_by_seat boolean; v_reasons text; v_cyc jsonb; v_problem text;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  select * into e from public.ceo_experiment where id = (r.subject->>'experiment_id')::bigint for update;
  if not found or e.status <> 'proposed' or e.iteration <> (r.subject->>'iteration')::int then
    return jsonb_build_object('applied', true, 'already', 'the experiment moved on');
  end if;
  v_f := public.fn_ambition_fields(p_result);
  v_owner := case when exists (select 1 from public.org_role where role_id = v_f->>'owner_seat' and status = 'active' and role_id <> 'ceo')
                  then v_f->>'owner_seat' else e.proposed_by end;
  v_days := case when coalesce(v_f->>'days', '') ~ '^\d{1,3}$' and (v_f->>'days')::int between 7 and 365 then (v_f->>'days')::int else e.days end;

  -- THE DECISION SAYS WHY (founder_instruction 1059), and a seat's proposal goes round the cycle.
  v_reasons := btrim(coalesce(p_result->>'answer', '') || case when coalesce(btrim(v_f->>'conditions'), '') <> ''
                                                              then E'\nConditions: ' || (v_f->>'conditions') else '' end);
  v_by_seat := e.proposed_by <> 'ceo';
  if v_by_seat then
    v_cyc := public.fn_ceo_decide('ceo_experiment', 'ceo_experiment:' || e.id, e.proposed_by,
               case when v_choice = 'approve' then 'approved' else 'rejected' end, v_reasons,
               jsonb_build_object('experiment_id', e.id, 'key', e.key, 'iteration', e.iteration, 'choice', v_choice,
                                  'experiment', to_jsonb(e) - 'approval', 'fields', v_f),
               'reasoning_held_question', p_id::text);
  else
    v_problem := public.fn_ceo_reasons_problem(v_reasons);
    if v_problem is not null then
      raise exception using errcode = 'check_violation', message = 'REASONLESS_DECISION: the CEO''s call on experiment ' || e.key || ' says why: ' || v_problem;
    end if;
  end if;

  -- THE CHALLENGE: the accountant reviews every approval call on a model of another family.
  v_review := public.fn_seat_duty_cross_review('ceo.experiment_approval', 'ceo', 'accountant',
    'Challenge the chief executive''s call on this experiment before it runs.',
    jsonb_build_object('experiment', to_jsonb(e) - 'approval'),
    jsonb_build_object('call', v_choice, 'fields', v_f, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000)),
    p_result, 'ceo_experiment', e.id::text || ':' || e.iteration);

  update public.ceo_experiment
     set approval = jsonb_build_object('decision', v_choice, 'fields', v_f, 'reasoning', left(coalesce(p_result->>'answer', ''), 6000),
                                       'model', p_result->>'model', 'review', v_review, 'decided_at', now(), 'cycle', v_cyc),
         status = case v_choice when 'approve' then case when e.starts_on <= v_today then 'running' else 'approved' end
                                when 'reject' then case when v_by_seat then 'proposed' else 'rejected' end else 'proposed' end,
         owner_seat = case when v_choice = 'approve' then v_owner else owner_seat end,
         days = v_days,
         starts_on = case when v_choice = 'approve' then greatest(e.starts_on, v_today) else starts_on end,
         ends_on = case when v_choice = 'approve' then greatest(e.starts_on, v_today) + v_days end,
         closed_at = case when v_choice = 'reject' and not v_by_seat then now() end,
         updated_at = now()
   where id = e.id;
  return jsonb_build_object('applied', true, 'experiment', e.key, 'choice', v_choice, 'owner', v_owner, 'review', v_review, 'cycle', v_cyc);
end $function$;

-- ── 9. PATH: A SEAT'S ANSWER TO A CEO IMPROVEMENT ───────────────────────────────────────────────────────────
-- From the_ceo_reviews_every_answered_improvement_within_its_window.sql (MANIFEST 1819), split so one answer can
-- be decided alone. Each close and each return is a round in the ledger; a fifth return is not made: the CEO is
-- owed a replace-or-withdraw and the handoff waits for it (decision_owed) instead of looping for ever.
create or replace function public.fn_ceo_review_one_answered_improvement(p_handoff_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h record; v_why text; v_cyc jsonb; v_receipt text;
begin
  select a.id, a.agent, a.evidence, a.detail, i.id imp_id, i.status imp_status, i.seat imp_seat, i.task_id, i.done_evidence
    into h
    from public.agent_actions a
    left join public.ceo_improvement i on i.handoff_id = a.id
   where a.id = p_handoff_id and a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.improvement'
     and a.detail ? 'replied_at'
   for update of a;
  if not found then return jsonb_build_object('reviewed', false); end if;
  v_why := case
    when h.imp_status in ('done', 'dropped') then null
    when coalesce(h.evidence->>'accepted', '') <> 'true' then 'the answer does not accept the improvement'
    when h.evidence->>'seat' is distinct from h.agent or h.imp_seat is distinct from h.agent then 'answered by a seat other than the one asked'
    end;
  -- At the loop guard the CEO owes a replace-or-withdraw: a later answer that deserves it is still approved (which
  -- settles what was owed), but one that does not is not returned a fifth time.
  if h.detail ? 'decision_owed' and v_why is not null then
    return jsonb_build_object('reviewed', false, 'waiting', 'the CEO replaces or withdraws improvement #' || h.imp_id);
  end if;
  if h.imp_id is null then
    -- Nothing to review: no improvement carries it. Returning it (as before) asked the seat to answer nothing, and
    -- the handler accepts again, for ever; the CEO closes it with that receipt instead.
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object('verified_by', 'ceo', 'reviewed_at', now(),
      'receipt', 'Closed by the CEO: no ceo_improvement carries this handoff, so there is nothing for the seat to answer.'));
    perform set_config('qd.handoff_closer', '', true);
    return jsonb_build_object('reviewed', true, 'closed', true, 'orphan', true);
  end if;
  if v_why is null then
    v_receipt := case when h.imp_status in ('done', 'dropped')
                      then format('The CEO closes this answer because improvement #%s is already %s: %s', h.imp_id, h.imp_status, coalesce(h.done_evidence, 'no evidence recorded'))
                      else format('Reviewed by the CEO: %s accepted improvement #%s. The work is tracked on ceo_task #%s and closed by the CEO sweep when its source recovers.',
                                  h.agent, h.imp_id, coalesce(h.task_id::text, 'none')) end;
    v_cyc := public.fn_ceo_decide('ceo_improvement', 'ceo_improvement:' || h.imp_id, h.agent, 'approved', v_receipt,
               jsonb_build_object('improvement_id', h.imp_id, 'handoff_id', h.id, 'answer', left(h.evidence::text, 8000)), 'agent_actions',
               h.id || ':replied:' || (h.detail->>'replied_at'));
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(h.id, h.evidence || jsonb_build_object(
      'verified_by', 'ceo', 'reviewed_at', now(), 'improvement_id', h.imp_id, 'receipt', v_receipt, 'round', v_cyc));
    perform set_config('qd.handoff_closer', '', true);
    return jsonb_build_object('reviewed', true, 'closed', true, 'round', v_cyc);
  end if;
  v_cyc := public.fn_ceo_decide('ceo_improvement', 'ceo_improvement:' || h.imp_id, h.agent, 'rejected',
             'The CEO returned the answer to improvement #' || h.imp_id || ' because ' || v_why,
             jsonb_build_object('improvement_id', h.imp_id, 'handoff_id', h.id, 'answer', left(h.evidence::text, 8000)), 'agent_actions',
             h.id || ':replied:' || (h.detail->>'replied_at'), array[h.id]);
  if coalesce((v_cyc->>'round_limit')::boolean, false) then
    update public.agent_actions set detail = detail || jsonb_build_object('decision_owed', v_cyc->'decision_owed_handoff') where id = h.id;
    return jsonb_build_object('reviewed', true, 'decision_owed', v_cyc);
  end if;
  update public.agent_actions
     set detail = (detail - 'replied_at') || jsonb_build_object('returned', jsonb_build_object('at', now(), 'by', 'ceo', 'reason', v_why, 'round', v_cyc))
   where id = h.id;
  perform public.fn_seat_handoff_event(h.id, 'returned');
  return jsonb_build_object('reviewed', true, 'returned', true, 'reason', v_why, 'round', v_cyc);
end $fn$;
revoke execute on function public.fn_ceo_review_one_answered_improvement(bigint) from public, anon, authenticated;

create or replace function public.fn_ceo_reviews_answered_improvements()
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare h record; v jsonb; n_closed int := 0; n_returned int := 0; n_owed int := 0; v_failed jsonb := '[]'::jsonb;
begin
  for h in select a.id from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.improvement'
              and a.detail ? 'replied_at'
            order by a.id loop
    -- one answer that cannot be decided is reported and left for the next run; it never holds the others back
    begin
      v := public.fn_ceo_review_one_answered_improvement(h.id);
    exception when others then
      v_failed := v_failed || jsonb_build_object('handoff_id', h.id, 'error', left(sqlerrm, 300));
      continue;
    end;
    n_closed := n_closed + coalesce((v->>'closed')::boolean, false)::int;
    n_returned := n_returned + coalesce((v->>'returned')::boolean, false)::int;
    n_owed := n_owed + (v ? 'decision_owed')::int;
  end loop;
  return jsonb_build_object('closed', n_closed, 'returned', n_returned, 'decision_owed', n_owed, 'failed', v_failed);
end $function$;

-- ── 10. THE SALES ESCALATION CHOICE SAYS WHY ────────────────────────────────────────────────────────────────
-- From the_sales_engineer_can_escalate_a_decision_to_the_ceo.sql (MANIFEST 1791). A choice among options, not an
-- approval, so it does not loop; its reasoning is now required (a reasonless answer raises and is reasoned again).
create or replace function public.fn_reason_apply_ceo__sales_escalation(p_id bigint, p_result jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_hid bigint; v_problem text;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  v_problem := public.fn_ceo_reasons_problem(p_result->>'answer');
  if v_problem is not null then
    raise exception using errcode = 'check_violation', message = 'REASONLESS_DECISION: the CEO''s answer to a sales escalation says why: ' || v_problem;
  end if;
  v_hid := (r.subject->>'handoff_id')::bigint;
  perform set_config('qd.handoff_closer', 'ceo', true);
  perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('decided_by', 'ceo', 'escalation', r.subject->>'escalation',
    'choice', v_choice, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000), 'model', p_result->>'model', 'held_question', p_id));
  perform set_config('qd.handoff_closer', '', true);
  return jsonb_build_object('applied', true, 'handoff_id', v_hid, 'choice', v_choice);
end $function$;

-- ── 11. THE LEDGER IS IN THE DAILY EXPORT ───────────────────────────────────────────────────────────────────
-- From the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql (MANIFEST 1879,
-- the last definer on 29 Sep 2026) with ONLY ceo_decision_round added under 'decision'.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'), ('ceo_decision_round','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_calendar_resend_decision','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('marketing_recruitment_source','marketing'), ('marketing_gap_recruitment_plan','marketing'), ('marketing_plan_doc','marketing'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;
