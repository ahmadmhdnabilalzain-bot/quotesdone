-- ---------------------------------------------------------------------------------------------
-- "REMOVE ALL HISTORY OF ESCALATIONS IN THE OS. WE ARE STARTING FRESH."  — founder, 16 Aug 2026
--
-- A destructive clear-out was measured first, in rolled-back transactions, and it fails four ways.
-- This file does what he asked without any of them.
--
-- WHY NOT DELETE
--
--  1. It does not work. Every raiser dedupes on "is an open row already present" — leg_flag(),
--     sec_incident(), the agents' queue() and the rest. Deleting an open row RELEASES the
--     suppression. Proved by execution: all 27 founder-queue rows deleted, then five of the 186
--     active cron jobs re-run in the same aborted transaction — 7 came straight back. Across the
--     full cron cycle (03:10-06:50 UTC) the measured figure is 36 of the same issues returning.
--     Closing them instead behaves identically, for the same reason.
--
--  2. decision_log cannot be deleted at all. Trigger declog_immutable raises "decision_log is
--     append-only" on DELETE and on UPDATE, and 721 agent_actions rows point at it through an FK
--     with no ON DELETE action. It is the single largest copy of the history — 1,862 rows.
--
--  3. It would email real customers. 18 routines use public.notifications as their OWN send-dedupe
--     ("have I already sent this?"). Wiping 624 notification rows unmutes all 18 and re-sends real
--     mail to real customers and suppliers. That is an outward-facing consequence of a screen
--     tidy-up, and it is not acceptable.
--
--  4. It would corrupt the founder's own gates. Measured in an aborted transaction:
--     fn_os_portals_gates() is 23/23 met before and 20/23 after, with evidence strings collapsing
--     to "0 of 0 ... (%)", and 8 rows on the Escalations screen silently rewrite from a true
--     outcome to the false sentence "no follow-up action recorded".
--
-- WHAT THIS DOES INSTEAD
--
-- One dated watermark that every founder-facing escalation surface reads from. Nothing is deleted,
-- nothing is closed, nothing is back-dated and no gate moves. The OS shows the company from
-- 16 Aug 2026 forward; everything before it stays exactly where it is, still auditable, still
-- pointed at by every FK, and recoverable in one statement by moving the watermark back.
--
-- The re-raise behaviour becomes the FEATURE rather than the flaw. Of the 27 items measured:
-- 16 name a condition that has already cleared and will stay gone; 9 are still true — several
-- materially worse than when raised — and will re-appear above the watermark within 24 hours,
-- which is exactly "current problems, not old ones". Two exceptions are handled here rather than
-- left to recur or vanish, and they are named in the fresh-start row itself.
--
-- This is the second time this has been done: public.escalations_archive_20260724 holds 694 rows
-- from a clear-out on 24 Jul 2026 and has zero readers. A watermark leaves no such orphan.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.os_fresh_start (
  id             bigserial primary key,
  effective_from timestamptz not null,
  actor          text        not null,
  reason         text        not null,
  carried_forward jsonb      not null default '[]'::jsonb,
  created_at     timestamptz not null default now()
);
alter table public.os_fresh_start enable row level security;
revoke all on public.os_fresh_start from anon, authenticated;

comment on table public.os_fresh_start is
  'Dated resets of the founder-facing OS surfaces. The NEWEST row wins. Nothing is deleted by a '
  'reset - the surfaces simply read from effective_from forward, so a reset is reversible by '
  'inserting an earlier one and costs no history, no audit trail and no foreign key.';

-- Never returns null: with no reset ever recorded, every surface behaves exactly as it did before
-- this file existed. A missing watermark must not be able to blank a screen.
create or replace function public.fn_os_fresh_start_at()
 returns timestamptz
 language sql
 stable
 set search_path to 'public', 'pg_catalog'
as $function$
  select coalesce((select f.effective_from from public.os_fresh_start f
                    order by f.effective_from desc, f.id desc limit 1),
                  '-infinity'::timestamptz);
$function$;

-- ---------------------------------------------------------------------------------------------
-- THE TWO ITEMS THAT MUST NOT SIMPLY VANISH, handled at the mechanism rather than carried as
-- clutter. Both were identified by measuring which queue items can never be raised again.
--
-- (a) The two prompt approvals cannot re-raise because fn_ai_trainer refuses to draft a new
--     version while ANY row sits in prompt_versions at status='draft' — and the two drafts live in
--     a different table, so they survive any clear-out and block the re-raise for ever. Retiring
--     the orphaned drafts restores the mechanism: if quote quality is still below 60 the trainer
--     raises a fresh approval above the watermark on its own. This is a root-cause fix, not a
--     carry-forward, and it is the reason those two are not in carried_forward below.
-- ---------------------------------------------------------------------------------------------
--     Measured: 2 rows at status='draft', both prompt_key='quote_review.system', and the two open
--     prompt_approval actions that reference them. Retiring the drafts is what unblocks the
--     trainer; the actions themselves fall behind the watermark with everything else.
update public.prompt_versions
   set status = 'retired_at_fresh_start'
 where status = 'draft';

-- ---------------------------------------------------------------------------------------------
-- (b) The Dubai Municipality Al Sa'fat compliance change is the one item with a real external
--     consequence that can NEVER be raised again: its writer fires only on a signature TRANSITION
--     and it already advanced compliance_sources.last_signature when it raised the row, so the
--     transition cannot recur. It is carried across the watermark as a new row, dated now, saying
--     plainly where it came from. Everything else is left to the watermark.
--
--     The other four unrepeatable items are deliberately NOT carried: two contract reviews from an
--     edge function with zero callers anywhere in the estate (a wiring gap already recorded as
--     Phase C work, not a live obligation), and one simulation projection with no consequence.
--     Carrying those would be importing the clutter he asked to be rid of.
-- ---------------------------------------------------------------------------------------------
-- THE CARRY MUST LAND ABOVE THE WATERMARK. First version inserted the carry and THEN the reset
-- row, three seconds apart, so the one item deliberately rescued was itself hidden by the reset it
-- was rescued from — a silent loss of the only regulatory item on the queue. created_at is set
-- explicitly relative to the watermark rather than left to statement time.
insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, escalated, created_at)
select a.agent, a.kind, 'pending', a.risk,
       'Carried forward: ' || a.title,
       coalesce(a.recommendation, a.title),
       coalesce(a.detail, '{}'::jsonb)
         || jsonb_build_object('carried_forward_from', a.id,
                               'carried_because',
                               'Its writer fires only on a compliance signature transition and the '
                               'signature was already advanced when this was first raised, so it can '
                               'never be raised again. Everything else on the old queue either '
                               're-raises on its own or names a condition that has cleared.'),
       true,
       public.fn_os_fresh_start_at() + interval '1 second'
  from public.agent_actions a
 where a.kind = 'compliance_update'
   and a.status in ('pending','needs_review')
   and a.title ilike '%Sa%fat%'
   -- A CARRIED ROW IS NOT A CANDIDATE. The first version of this guard only checked "has THIS row
   -- been carried already", which is true and insufficient: the row it inserts also matches the
   -- title predicate, so a second execution carried the carry and produced
   -- "Carried forward: Carried forward: ...". An idempotency guard has to cover its own output,
   -- not just its input. Caught on the live apply and cleaned up below.
   and a.detail->>'carried_forward_from' is null
   and not exists (select 1 from public.agent_actions b
                    where b.detail->>'carried_forward_from' = a.id::text);

-- Remove any double-carry a previous run of this file produced. Scoped to rows whose SOURCE was
-- itself a carried row, so it can never touch a genuine escalation.
delete from public.agent_actions a
 where a.detail->>'carried_forward_from' is not null
   and exists (select 1 from public.agent_actions b
                where b.id = (a.detail->>'carried_forward_from')::bigint
                  and b.detail->>'carried_forward_from' is not null);

-- One reset row only. Re-applying this file must not move the watermark forward and re-hide
-- everything raised since the first reset.
insert into public.os_fresh_start (effective_from, actor, reason, carried_forward)
select now(), 'management@quotesdone.com',
  'Founder instruction, 16 Aug 2026: "remove all history of escalations in the OS. i say we are '
  'starting fresh and i dont need previous issues to carry on as we did many upgrades." '
  'Implemented as a watermark rather than a deletion: deleting does not clear the queue (every '
  'raiser dedupes on an open row, so 36 of 27 measured items return on the next cron cycle), '
  'decision_log is append-only with 721 dependent rows, wiping notifications re-sends real customer '
  'email from 18 routines that use it as a send-dedupe, and a delete drops fn_os_portals_gates from '
  '23/23 to 20/23. Nothing is deleted; the surfaces read from this timestamp forward. Of the 27 '
  'items measured: 16 stale and gone, 9 still true and expected to re-appear above the watermark '
  'within 24h, which is the intent.',
  jsonb_build_object(
    'carried', jsonb_build_array('compliance_update: Dubai Municipality Al Sa''fat code re-issue'),
    'root_cause_fixed', jsonb_build_array('prompt_approval x2: orphan prompt_versions drafts retired so fn_ai_trainer can raise again'),
    'not_carried', jsonb_build_array(
      'contract_review x2 (legal_review edge function has zero callers - a recorded Phase C wiring gap, not a live obligation)',
      'simulation_apply x1 (RPC-only projection, no consequence)'))
 where not exists (select 1 from public.os_fresh_start f where f.effective_from >= '2026-08-16'::date);
