-- ORG ALIGNMENT 01 — the artifact path never got the lexicon that review_chain got.
--
-- MEASURED DEFECT, 15 Aug 2026, on production, at zero model cost:
--
--   select ('visual_design' = 'marketing_design')                                              as raw_guard_fires,
--          (fn_org_agent_resolve('visual_design') = fn_org_agent_resolve('marketing_design'))  as same_employee;
--   -->    raw_guard_fires = false          same_employee = true
--
-- The Visual Design Director's role_id is `visual_design`; its runtime agent_key is
-- `marketing_design`. One employee, two names. THREE places decide whether a reviewer is
-- independent, and on 14 Aug only one of them was taught to resolve:
--
--   review_chain    trg_review_chain_no_self_review   RESOLVES both sides, and canonicalises on
--                                                     write. Correct. Left untouched by this file.
--   artifact_review fn_artifact_review_valid          compares new.reviewer_agent = new.author_agent
--                                                     RAW.                              <-- fixed here
--   artifact_review supabase/functions/artifact_review  authorAgent === reviewerAgent RAW, and the
--                                                     reviewer DEFAULTED to 'marketing_design' —
--                                                     the designer was the default reviewer of its
--                                                     own artifact.                     <-- fixed in TS
--
-- So the guard built to stop a designer approving its own work could not see the one case it
-- exists for. This is the same root cause as fn_pick_reviewer (182 self-approvals), fn_agent_tools
-- and the autonomy gate: a routine comparing an identity it never resolved. review_chain proves
-- the fix works — with the resolving trigger in place, 0 of 1,885 rows carry an alias-hidden
-- self-review, because the trigger normalises on write.
--
-- artifact_review holds 0 rows on both projects. Zero rows cannot tell a working guard from a dead
-- one, so scripts/checks/artifact_review_alias_cannot_self_approve.test.mjs forces this guard to
-- fire inside an aborted transaction rather than reading the count and calling it proof.
--
-- CREATE OR REPLACE preserves the ACL, so no REVOKE here.

create or replace function public.fn_artifact_review_valid()
returns trigger
language plpgsql
as $function$
declare
  v_author   text;
  v_reviewer text;
begin
  -- Resolve BOTH sides before comparing. coalesce keeps an unrecognised identity as itself rather
  -- than turning it into null: null = null is null, and a guard that evaluates to null lets the
  -- row through.
  v_author   := coalesce(public.fn_org_agent_resolve(new.author_agent),   new.author_agent);
  v_reviewer := coalesce(public.fn_org_agent_resolve(new.reviewer_agent), new.reviewer_agent);

  if new.verdict = 'pass' then
    -- A PASS WITH NO REVIEWER IS WORSE THAN A SELF-REVIEW, and the previous guard permitted it:
    -- a null reviewer_agent is never equal to author_agent, so the comparison answered "not a
    -- self-review" and the row went in with nobody having looked at the artifact.
    if new.reviewer_agent is null or btrim(new.reviewer_agent) = '' then
      raise exception 'artifact % % cannot be marked pass with no reviewer recorded',
        new.subject_type, new.subject_id
        using errcode = 'check_violation';
    end if;

    if new.author_agent is not null and v_author = v_reviewer then
      raise exception
        'artifact_review refuses a self-review: author "%" and reviewer "%" are the same employee (%). %',
        new.author_agent, new.reviewer_agent, v_author,
        'Route the artifact to the QA path (ai_quality_reviewer) or to fn_pick_reviewer(dept, author).'
        using errcode = 'check_violation';
    end if;
  end if;

  -- Store both sides canonical, so every later count over this table measures employees and not
  -- spelling. Same discipline as trg_review_chain_no_self_review.
  new.author_agent   := case when new.author_agent   is null then null else v_author   end;
  new.reviewer_agent := case when new.reviewer_agent is null then null else v_reviewer end;
  return new;
end $function$;

comment on function public.fn_artifact_review_valid() is
  'BEFORE INSERT/UPDATE on artifact_review. Resolves author and reviewer canonically before '
  'comparing, and refuses a pass with no reviewer. 15 Aug 2026: visual_design and marketing_design '
  'are one employee and the raw string comparison could not see it.';
