-- THE ONLY THING THAT INVITES A SUPPLIER TO CONFIRM HAS NEVER HAD A CANDIDATE.
--
-- 13 Aug 2026. fn_match_capability gates every RFQ on supplier_capabilities.confirmed_at. 15,306
-- suppliers hold capability data and exactly one has confirmed. fn_supplier_capability_chase is the
-- one mechanism in the estate whose job is to ask them to, it is on cron (jobid 118,
-- supplier_capability_chase_daily, 30 6 * * *, active) — and it has produced nothing:
--
--   agent_runs where agent='supplier_success'          24 runs, latest 2026-08-13 06:30 UTC
--   every note                                          "0 chased, 0 escalated, 0 flagged"
--   notifications where type='capability_chase'         0, ever
--
-- Because loop A opens with
--
--     where sc.confirmed_at is null
--       and sc.review_status in ('insufficient','awaiting_confirmation')
--
-- and neither value exists in the table. The actual distribution of review_status across all
-- 15,306 rows is `derived` 15,305 and `confirmed` 1. Those two statuses are written by exactly one
-- place — capability_agent's `analyze` action (index.ts:331), which reads a supplier's own uploaded
-- DOCUMENTS. No scraped directory lead has ever uploaded a document, so analyze has never run for
-- one; every row in the table was written by the deriver with review_status='derived'. The chase
-- filters for the output of a path that has never executed, so it selects zero rows every morning
-- and reports success.
--
-- ── WHY THE FIX IS NOT "ADD 'derived' TO THE LIST" ──────────────────────────────────────────────
-- That would select 15,305 rows and try to email every scraped lead in the directory. The invite
-- ramp is deliberately capped at 10/day with an auto-pause on bounce rate for exactly that reason,
-- and a cold "confirm your scope" mail to a company that has never heard of us is spam.
--
-- The right population is not a status, it is a RELATIONSHIP: a supplier who has claimed their
-- company already has an account, has already opted in, and is one screen away from being
-- matchable. "One step left" is a legitimate mail to them and an intrusion to anyone else. That
-- population is 0 today — MERIDIAN MEP is the only claimed real supplier and it has confirmed — and
-- it becomes non-empty the moment the invite ramp converts anyone, which is precisely when this
-- should fire. A guard that is currently empty for a real reason is not the same defect as a guard
-- that can never match.
--
-- review_status still chooses the WORDING, because 'insufficient' genuinely means we could not
-- read a scope and have to ask for documents, while 'derived' and 'awaiting_confirmation' both mean
-- we have a proposal on file for them to correct. It no longer decides whether anyone is chased.
--
-- fn_email_sendable is now consulted, the same predicate enqueue_supplier_invites uses. The six
-- ZZ DEMO fixtures are claimed and carry @example.invalid addresses; the predicate refuses them
-- with "domain does not accept mail". They have no capability row either, so the inner join already
-- excludes them — this is the belt to that pair of braces, and it is one call.
--
-- AND THE MAIL POINTED AT THE WRONG TAB. It said "Open the Profile tab in your supplier portal to
-- confirm." The confirmation screen is the My scope tab; Profile is the company-details form. A
-- supplier following that instruction lands on the wrong screen and finds no confirm button.
--
-- CREATE OR REPLACE, so the ACL is preserved and there is nothing to revoke.
create or replace function public.fn_supplier_capability_chase(p_days integer default 3, p_max_chases integer default 3)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  rec record; v_sent int := 0; v_skipped int := 0; v_escalated int := 0; v_orphans int := 0;
  v_to text; v_chases int; v_ask text; v_have_proposal boolean;
begin
  ---------------------------------------------------------------- A. stalled records
  for rec in
    select sc.supplier_id, sc.review_status, sc.missing_fields, sc.updated_at,
           l.company_name, l.claimed_by, l.email
      from supplier_capabilities sc
      join leads l on l.id = sc.supplier_id
     where sc.confirmed_at is null
       and coalesce(l.claimed, false) = true         -- they have an account. This is not cold outreach.
       and sc.updated_at < now() - make_interval(days => p_days)
       and coalesce(l.banned,false) = false
       and coalesce(l.permanently_closed,false) = false
  loop
    select count(*) into v_chases from notifications
     where type = 'capability_chase' and lead_id = rec.supplier_id;

    -- Stop emailing after p_max_chases and hand to supplier_success as an action instead.
    if v_chases >= p_max_chases then
      if not exists (select 1 from agent_actions
                      where agent='supplier_success' and kind='capability_stalled'
                        and target_id = rec.supplier_id::text and status in ('needs_review','pending')) then
        insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
        values ('supplier_success','capability_stalled','needs_review','medium',
                'Supplier stalled in onboarding: ' || coalesce(rec.company_name,'#'||rec.supplier_id),
                'Chased ' || v_chases || ' times with no response. They cannot receive any inquiry until their scope is confirmed. Consider a call, or retire the registration.',
                jsonb_build_object('supplier_id',rec.supplier_id,'review_status',rec.review_status,
                                   'missing',to_jsonb(rec.missing_fields),'chases',v_chases),
                'leads', rec.supplier_id::text);
        v_escalated := v_escalated + 1;
      end if;
      continue;
    end if;

    -- one chase per 5 days
    if exists (select 1 from notifications where type='capability_chase' and lead_id=rec.supplier_id
                 and created_at > now() - interval '5 days') then
      v_skipped := v_skipped + 1; continue;
    end if;

    v_to := nullif(trim(coalesce(rec.claimed_by, rec.email)), '');
    if v_to is null or position('@' in v_to) = 0 then v_skipped := v_skipped + 1; continue; end if;
    if not (public.fn_email_sendable(v_to)->>'ok')::boolean then v_skipped := v_skipped + 1; continue; end if;

    -- 'insufficient' is the only status meaning we could not read a scope at all. Everything else
    -- ('derived' from the directory, 'awaiting_confirmation' from their documents) means a proposal
    -- is already on their screen and the ask is to correct it.
    v_have_proposal := coalesce(rec.review_status, 'derived') <> 'insufficient';

    -- Reuse the agent's own wording. A generic "please complete your profile" is why these stall.
    v_ask := coalesce(
      (select string_agg('  • ' || m, chr(10)) from unnest(rec.missing_fields) m),
      '  • a company profile or catalogue describing the products and services you supply');

    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('capability_chase', v_to, 'supplier', rec.supplier_id, 'email',
      case when v_have_proposal
           then 'One step left — confirm what your company can quote for'
           else 'We need a little more to start sending you work' end,
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      case when v_have_proposal
        then 'We have already filled in the trades and the role we hold for your company. We just need you to confirm they are right before we start matching you to customer requests — we will not guess your scope on your behalf, so until you confirm it you receive nothing.'
        else 'We have reviewed the documents you uploaded, but we cannot yet tell precisely what work to send you. Until we can, you will not receive customer requests — we would rather send you nothing than send you jobs you do not do.'
      end || chr(10) || chr(10) ||
      case when v_have_proposal then 'Open the "My scope" tab in your supplier portal, correct anything that is wrong, and press Confirm.'
           else 'What we still need:' || chr(10) || v_ask end || chr(10) || chr(10) ||
      'It takes about a minute and only needs doing once.' || chr(10) || chr(10) ||
      'QuotesDone',
      'queued');
    v_sent := v_sent + 1;
  end loop;

  ---------------------------------------------------------------- B. approved but no record at all
  for rec in
    select l.id as supplier_id, l.company_name
      from leads l
      left join supplier_capabilities sc on sc.supplier_id = l.id
     where l.approval_status = 'approved'
       and coalesce(l.banned,false) = false
       and coalesce(l.matching_blocked,false) = false
       and sc.supplier_id is null
  loop
    if not exists (select 1 from agent_actions
                    where agent='supplier_success' and kind='capability_missing'
                      and target_id = rec.supplier_id::text and status in ('needs_review','pending')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values ('supplier_success','capability_missing','needs_review','high',
              'Approved supplier has no capability record: ' || coalesce(rec.company_name,'#'||rec.supplier_id),
              'This supplier is approved but invisible to matching, because fn_match_capability requires a supplier-confirmed capability record. They will receive zero inquiries and will conclude the platform does not work. Run capability_agent analyze for them.',
              jsonb_build_object('supplier_id',rec.supplier_id),
              'leads', rec.supplier_id::text);
      v_orphans := v_orphans + 1;
    end if;
  end loop;

  insert into agent_runs(agent,status,counts,note,started_at,finished_at)
  values ('supplier_success','ok',
          jsonb_build_object('chased',v_sent,'skipped',v_skipped,'escalated',v_escalated,'no_capability_record',v_orphans),
          'capability chase: ' || v_sent || ' chased, ' || v_escalated || ' escalated after ' || p_max_chases ||
          ' attempts, ' || v_orphans || ' approved supplier(s) flagged with no capability record at all',
          now(), now());

  return json_build_object('chased',v_sent,'skipped',v_skipped,'escalated',v_escalated,'no_capability_record',v_orphans);
end $function$;
