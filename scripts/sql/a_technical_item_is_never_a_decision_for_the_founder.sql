-- A TECHNICAL ITEM IS NEVER A DECISION FOR THE FOUNDER (18 Oct 2026). Assigned: it_engineer.
--
-- What happened: the IT daily digest of 18 Oct 18:46 UTC (notifications 101206, kind it_daily_digest) told
-- the founder "Only you can decide this" on two technical items - a visitor_chat review held for want of a
-- reachable reviewer, and a knowledge_validation review whose author model was 'unknown'. The digest emails
-- whatever matches an it_founder_decision_class row with to_founder = true, and two rows sent the whole
-- duty:review_independence:% and duty:deliberation_independence:% families to him, citing a coordinator
-- ruling on #880 (~891). Standing rulings say otherwise: every approval is the CEO seat's; he is told only
-- about money, a destructive production change, or a fact only he holds.
--
-- Measured causes (not the ones first assumed):
--   review_hold 71 (visitor_chat, author openai/gpt-6-luna, 12 Oct): the router DID pick a reviewer
--     (anthropic/claude-opus-5.5, google/gemini-3.8-flash). Both were refused by the gateway because the call
--     carried sandbox run tag 7230a92a after its rehearsal window had closed. A closed test window, not a
--     missing reviewer and not the model matrix. ai_gateway now treats that refusal like the founder hold:
--     no review_hold row.
--   ai_cost_log 19198 (knowledge_validation, sales_engineer_conversation_drill, e2e run 2d02a7bd): the drill's
--     agent turn produced no answer, so it judged with counterpart_model 'unknown'. The drill now skips the
--     judge when no agent model answered, and a rehearsal's own rows (e2e_run_tag set) are the run's report,
--     not an it_engineer finding.
--
-- This file:
--   1. it_founder_decision_class gains founder_category; a row may say to_founder only with one of the three
--      categories that genuinely need him (CHECK constraint). review_independence and
--      deliberation_independence become seat findings (CEO / IT), never founder decisions.
--   2. fn_it_review_independence_items skips rehearsal rows in the unknown-author watch.
--   3. Closes review_hold 71 and the two findings with what was done; records the ruling as standing.
-- prevented by: scripts/checks/a_technical_item_is_never_a_decision_for_the_founder.test.mjs

alter table public.it_founder_decision_class add column if not exists founder_category text;

update public.it_founder_decision_class set founder_category = 'fact_only_he_holds'
 where to_founder and issue_key_like in ('duty:access:%', 'duty:credential:%', 'duty:integration%');

update public.it_founder_decision_class
   set to_founder = false, founder_category = null,
       why = '18 Oct 2026: technical - a held or same-family-risk review is a finding the CEO and IT engineer seats '
          || 'resolve on the OS; it is never a decision for the founder (all approvals are the CEO''s). '
          || 'Supersedes the #880 coordinator ruling (~891) routing.'
 where issue_key_like in ('duty:review_independence:%', 'duty:deliberation_independence:%');

alter table public.it_founder_decision_class drop constraint if exists it_founder_decision_class_only_his_categories;
alter table public.it_founder_decision_class add constraint it_founder_decision_class_only_his_categories
  check (not to_founder or founder_category in ('money', 'destructive_production_change', 'fact_only_he_holds'));
comment on column public.it_founder_decision_class.founder_category is
  'Why the founder, and only he, must decide: money | destructive_production_change | fact_only_he_holds. '
  'Required when to_founder; anything technical stays with the seats (a_technical_item_is_never_a_decision_for_the_founder.sql).';

create or replace function public.fn_it_review_independence_items()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with held as (
    select jsonb_build_object(
             'item', 'review_held:' || task_class, 'owner_seat', 'ceo', 'subject', 'review_independence',
             'title', count(*) || ' ' || task_class || ' review(s) HELD: no healthy reviewer outside the authors'' families (not even a '
                      || 'last-resort family), or the chosen reviewer failed. Nothing ran unreviewed or same-family; restore a reviewer or decide the held work.',
             'blast', 'agent_facing', 'affected', sum(times_held),
             'evidence', jsonb_build_object('review_hold_ids', jsonb_agg(id order by id), 'authors', jsonb_agg(distinct counterpart_model))) x
      from public.review_hold where closed_at is null group by task_class
  ), third as (
    select jsonb_build_object(
             'item', 'third_family_review:' || task_class, 'owner_seat', 'ceo', 'subject', 'review_independence',
             'title', count(*) || ' ' || task_class || ' review(s) in 7 days ran on a LAST-RESORT family ('
                      || string_agg(distinct model_used, ', ') || ') because the authors spanned both judgement families.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('ai_cost_log_ids', jsonb_agg(id order by id))) x
      from public.ai_cost_log
     where reviewer_tier = 'third_family_fallback' and occurred_at > now() - interval '7 days'
     group by task_class
  ), unknown_author as (
    select jsonb_build_object(
             'item', 'review_author_unknown:' || coalesce(fn, task_class), 'owner_seat', 'it_engineer', 'subject', 'review_independence',
             'title', count(*) || ' ' || coalesce(task_class, '?') || ' review(s) from ' || coalesce(fn, '?') || ' in 7 days named an author '
                      || 'model that is not in model_registry (or ''unknown''), so they could not be routed. Fix what the caller records '
                      || 'about the author; the model comparison was withheld, not skipped silently.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('ai_cost_log_ids', jsonb_agg(id order by id), 'authors', jsonb_agg(distinct counterpart_model))) x
      from public.ai_cost_log
     where coalesce(model_used, 'none') = 'none' and model_selected_because like 'AUTHOR UNKNOWN:%'
       and e2e_run_tag is null              -- 18 Oct 2026: a rehearsal's own refusal is that run's report, not a finding
       and occurred_at > now() - interval '7 days'
     group by coalesce(fn, task_class), task_class, fn
  )
  select coalesce((select jsonb_agg(x) from held), '[]'::jsonb) || coalesce((select jsonb_agg(x) from third), '[]'::jsonb)
         || coalesce((select jsonb_agg(x) from unknown_author), '[]'::jsonb);
$function$;

update public.review_hold set closed_at = now(),
       close_note = '18 Oct 2026, it_engineer: not a missing reviewer. The router picked anthropic/claude-opus-5.5; the gateway refused '
                 || 'it because sandbox run 7230a92a outlived its rehearsal window. ai_gateway no longer records such a refusal as a hold.'
 where id = 71 and closed_at is null;

select public.fn_it_engineer_finding_close('duty:review_independence:review_held:visitor_chat',
  '18 Oct 2026, it_engineer: hold 71 came from a closed sandbox rehearsal window (run 7230a92a), not from the model matrix; '
  || 'the router picks a cross-family reviewer for every single-family author. Gateway fixed; hold closed. Never a founder decision.');
select public.fn_it_engineer_finding_close('duty:review_independence:review_author_unknown:sales_engineer_conversation_drill',
  '18 Oct 2026, it_engineer: e2e drill 2d02a7bd judged a turn whose agent had not answered (author unknown). The drill now skips '
  || 'the judge when no agent model answered; rehearsal rows are excluded from the watch. Never a founder decision.');

insert into public.founder_instruction (said_at, instruction, subject, status, closed_at, note)
select now(),
       'Technical decisions never go to the founder. Held reviews, unregistered models and every other technical item are '
       || 'findings the CEO and IT engineer seats resolve; only money, a destructive production change or a fact only he holds may be '
       || '"a decision for you".',
       'founder routing', 'standing', now(),
       'The IT daily digest of 18 Oct 2026 18:46 UTC (notifications 101206) violated this by routing two review_independence items '
       || 'to him under the #880 coordinator ruling. Fixed by a_technical_item_is_never_a_decision_for_the_founder.sql.'
 where not exists (select 1 from public.founder_instruction where subject = 'founder routing' and note like '%notifications 101206%');

select case when (select count(*) from public.it_founder_decision_class
                   where to_founder and issue_key_like like 'duty:%independence%') = 0
             and (select closed_at from public.review_hold where id = 71) is not null
            then 'PROBE OK' else 'PROBE FAILED: a technical class still routes to the founder, or hold 71 is open' end as verdict;
