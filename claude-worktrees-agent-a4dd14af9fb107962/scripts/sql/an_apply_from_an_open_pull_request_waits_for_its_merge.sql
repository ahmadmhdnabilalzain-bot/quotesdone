-- AN APPLY FROM AN OPEN PULL REQUEST WAITS FOR ITS MERGE BEFORE IT IS A FINDING.
--
-- Assigned: it_engineer. 22 Sep 2026.
--
-- MEASURED (production, 22 Sep 2026 11:00-11:45Z):
--   duty:unsigned_revision:rev:2d34c4a  txid 11567482, 10 routines, 10:54:51Z,
--       application_name 'qd-apply 2d34c4a agent-a3466b29cc207b137 the_marketing_seat_pub'
--   duty:unsigned_revision:rev:59a3de8  txids 11567687 and 11567690, fn_table_export_list(), 10:59:36Z / 10:59:41Z,
--       application_name 'qd-apply 59a3de8 agent-a3466b29cc207b137 the_marketing_report_i'
--   Both revisions are in PR #834 (marketing), open at the 11:00:55Z tick, MERGED 11:02:04Z.
--   Every earlier open_pr finding followed the same arc: raised minutes after the apply, closed by the
--   first tick after the merge (e.g. rev:8fab2b6 / rev:19b7ff7, PR #829: raised 07:15 / 08:45Z, merged
--   08:51Z, closed 09:30Z). Of the 22 unsigned_revision findings on record, 16 were raised while their PR
--   was open, and 11 of those revisions read merged_pr today (the two above are still awaiting re-check).
--
-- WHAT IS WRONG: the estate's own order is apply, then merge (memory: two applied PRs deadlock each
--   other's database check -- "apply, merge, then next"; the coordinator serialises it). So a revision in
--   an OPEN pull request is the expected state for the minutes between an apply and its merge, and
--   raising it is an alarm on a healthy day. What IS a fault: a PR that stays open with its code live, or
--   a revision in no PR at all (not_on_main) -- both still raise.
--   Second: the finding could not say which seat applied, only a worktree name
--   ("agent-a3466b29cc207b137"); attributing it meant opening the PR.
--
-- WHAT CHANGES (fn_it_change_watch only):
--   1. an open_pr revision is given the same two hours a 'pending' one already had. After two hours
--      unmerged it is raised exactly as before. not_on_main is raised at once, as before.
--   2. the finding's evidence carries 'applied_as': the distinct application_name tags of its changes,
--      which from this PR on carry the seat (scripts/apply_sql.mjs, scripts/lib/apply_seat.mjs).
--
-- WHAT DOES NOT CHANGE: trg_it_judge_routine_change, the unsigned_change duty (mgmt-api / untagged writes
--   stay a security finding at once), fn_it_change_accept (the ceo or the founder, by txid), GitHub
--   verification (verifyRevisions).
--
-- NOT DONE, AND WHY: accepting txids 11567482 / 11567687 / 11567690. PR #834 merged at 11:02:04Z, so
--   verifyRevisions answers merged_pr on the next tick and the settle closes both keys itself; an
--   acceptance would claim a review the merge already records. fn_it_change_accept also takes only
--   'ceo' or 'founder', not the owning seat.
--
-- PREVENTED BY: scripts/checks/it_engineer_duties_19_to_24.test.mjs (the tag carries the seat; an apply
--   with no seat is refused) and "an open PR revision waits two hours; after that, and not_on_main at
--   once, it is raised" in the same file (rolled-back probe with control).
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/an_apply_from_an_open_pull_request_waits_for_its_merge.sql --apply

create or replace function public.fn_it_change_watch()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r public.it_change_revision; f record; v_items jsonb := '[]'::jsonb; v_tx bigint; v_note text; n_closed int := 0; v_rev jsonb;
begin
  for r in select * from public.it_change_revision
            where first_seen_at > now() - interval '30 days' and verdict not in ('on_main', 'merged_pr') loop
    -- In flight, not a fault: GitHub has not answered yet ('pending'), or the pull request carrying the
    -- revision is still open ('open_pr') -- the estate applies before it merges (22 Sep 2026).
    continue when r.verdict in ('pending', 'open_pr') and r.first_seen_at > now() - interval '2 hours';
    -- SETTLED: every change this revision made was re-applied from a reviewed revision or accepted.
    continue when exists (select 1 from public.routine_change_log c
                           where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev)
             and not exists (
                   select 1 from public.routine_change_log c
                    where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev
                      and not exists (select 1 from public.it_change_acceptance a where a.txid = c.txid)
                      and not exists (select 1 from public.routine_change_log s
                                        join public.it_change_revision rv
                                          on rv.rev = substring(s.application_name from '^qd-apply ([0-9a-f]{7,40}) ')
                                       where s.object_identity = c.object_identity and s.at > c.at
                                         and rv.verdict in ('on_main', 'merged_pr')));
    v_items := v_items || jsonb_build_object('item', 'rev:' || r.rev, 'owner_seat', 'ceo', 'subject', 'routine_change_log',
      'title', case r.verdict
                 when 'open_pr' then 'Routines were applied to production from ' || r.rev || ', which is in pull request #'
                                     || coalesce(r.pr_number::text, '?') || ' and has not been merged into main for over two hours'
                 when 'not_on_main' then 'Routines were applied to production from ' || r.rev
                                     || ', a revision that is not on main and in no merged or open pull request'
                 else 'Routines were applied from ' || r.rev || ' and GitHub could not yet be asked whether it is on main' end,
      'blast', case when r.verdict = 'not_on_main' then 'security' else 'agent_facing' end,
      'affected', case when r.verdict = 'not_on_main' then 1 else 0 end,
      'evidence', jsonb_build_object('rev', r.rev, 'verdict', r.verdict, 'pr_number', r.pr_number, 'checked_at', r.checked_at,
        'detail', r.detail,
        'objects', (select jsonb_agg(distinct c.command_tag || ' ' || c.object_identity) from public.routine_change_log c
                     where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev),
        -- who applied it: 'qd-apply <rev> <seat> <worktree> <file>' since 22 Sep 2026
        'applied_as', (select jsonb_agg(distinct c.application_name) from public.routine_change_log c
                        where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev),
        'txids', (select jsonb_agg(distinct c.txid) from public.routine_change_log c
                   where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev),
        'close', 'Merge the pull request, re-apply each routine from a reviewed revision, or the ceo or the founder accepts its transaction with public.fn_it_change_accept(txid, who, why).'));
  end loop;
  v_rev := public.fn_it_duty_settle('unsigned_revision', v_items);

  for f in select issue_key, evidence from public.it_engineer_finding
            where closed_at is null and issue_key like 'duty:unsigned\_change:tx%' loop
    v_tx := (f.evidence->>'txid')::bigint;
    continue when v_tx is null;
    select 'accepted by the ' || accepted_by || ': ' || reason into v_note from public.it_change_acceptance where txid = v_tx;
    if v_note is null and not exists (
         select 1 from public.routine_change_log c
          where c.txid = v_tx
            and not exists (select 1 from public.routine_change_log s
                              join public.it_change_revision rv
                                on rv.rev = substring(s.application_name from '^qd-apply ([0-9a-f]{7,40}) ')
                             where s.object_identity = c.object_identity and s.at > c.at
                               and rv.verdict in ('on_main', 'merged_pr'))) then
      v_note := 'every routine it touched has since been re-applied from a reviewed revision';
    end if;
    if v_note is not null then
      perform public.fn_it_engineer_finding_close(f.issue_key, v_note);
      n_closed := n_closed + 1;
    end if;
  end loop;
  return jsonb_build_object('unsigned_revision', v_rev, 'unsigned_changes_closed', n_closed);
end $function$;

revoke execute on function public.fn_it_change_watch() from public, anon, authenticated;

select case when p.prosrc like '%r.verdict in (''pending'', ''open_pr'') and r.first_seen_at > now() - interval ''2 hours''%'
             and p.prosrc like '%''applied_as''%'
            then 'PROBE OK: an open_pr revision waits two hours for its merge; findings name who applied them'
            else 'PROBE FAILED: fn_it_change_watch is not the version this file defines' end verdict
  from pg_proc p where p.oid = 'public.fn_it_change_watch()'::regprocedure;
