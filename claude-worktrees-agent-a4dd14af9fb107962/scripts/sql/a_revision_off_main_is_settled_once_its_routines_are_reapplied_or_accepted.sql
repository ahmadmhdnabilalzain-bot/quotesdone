-- A REVISION OFF MAIN IS SETTLED ONCE ITS ROUTINES ARE RE-APPLIED OR ACCEPTED.
--
-- Assigned: it_engineer. Founder, 21 Sep 2026: "i dont want things to pop up again for the same reasons".
--
-- MEASURED (22 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   finding duty:unsigned_revision:rev:14ad86a (blast security, open since 21 Sep 17:45Z, seen 12 times)
--   names four routines applied at 17:40:13Z by 'qd-apply 14ad86a pr783 ...'. 14ad86a was a commit on
--   PR #783's branch that the branch no longer contains, so GitHub answers compare 404 / pulls 422 and
--   it_change_revision holds verdict 'not_on_main'. PR #783 merged at 17:47:21Z.
--   canonical_routine_manifest.mjs on main (22 Sep): 0 repository->production drift, and per routine
--   the deployed sha256 equals the canonical file's:
--     fn_sales_assist(text,vector,numeric,numeric,integer,text)   ef8c4b87...  MANIFEST:1522
--     fn_support_knowledge_gap(text,text,text)                    32210a2d...  MANIFEST:1569
--     fn_text_did_not_survive_reply(text)                         c78342af...  MANIFEST:1569
--     fn_text_lost_its_script(text)                               410ddb3a...  MANIFEST:1522
--   Two of the four were re-applied from reviewed e5c478d (merged_pr) at 01:39:11Z on 22 Sep; two were not.
--
-- WHAT WAS WRONG. fn_it_change_watch raises a not_on_main revision on every tick for 30 days, whatever
-- happened since. An unsigned CHANGE already had two ways to close (every routine re-applied from a
-- reviewed revision, or the ceo/founder accepting its transaction in it_change_acceptance); a signed
-- REVISION had none. Closing its finding by hand only lasts until the next 15-minute tick, when
-- fn_it_duty_settle upserts it open again — the same finding popping up for the same reason.
--
-- WHAT THIS CHANGES. fn_it_change_watch only: a revision that is not reviewed is no longer raised once
-- EVERY routine change it made is settled — re-applied later from a reviewed revision (on_main or
-- merged_pr), or its transaction accepted in it_change_acceptance (fn_it_change_accept, ceo or founder).
-- Then fn_it_duty_settle closes the finding with "the unsigned_revision duty no longer finds it". The
-- unsigned-change loop below is byte-for-byte the canonical body in
-- a_routine_change_nobody_signed_is_a_finding_within_minutes.sql.
--
-- WHAT IT DOES NOT CHANGE. No verdict is rewritten: 14ad86a stays 'not_on_main' in it_change_revision,
-- because that is what GitHub answered. Nothing is accepted here — acceptance stays the ceo's or the
-- founder's (fn_it_change_accept). For 14ad86a the remaining two routines still need either a re-apply
-- from a reviewed revision or that acceptance; the measurement above is the evidence for it.
-- The table DDL, the trigger, fn_it_change_accept and the GitHub path are untouched.
--
-- Prevented by: the probe at the end of this file (verdict row) and
-- scripts/checks/a_revision_off_main_is_settled_once_its_routines_are_reapplied_or_accepted.test.mjs.

create or replace function public.fn_it_change_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.it_change_revision; f record; v_items jsonb := '[]'::jsonb; v_tx bigint; v_note text; n_closed int := 0; v_rev jsonb;
begin
  for r in select * from public.it_change_revision
            where first_seen_at > now() - interval '30 days' and verdict not in ('on_main', 'merged_pr') loop
    continue when r.verdict = 'pending' and r.first_seen_at > now() - interval '2 hours';
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
                                     || coalesce(r.pr_number::text, '?') || ' and not merged into main'
                 when 'not_on_main' then 'Routines were applied to production from ' || r.rev
                                     || ', a revision that is not on main and in no merged or open pull request'
                 else 'Routines were applied from ' || r.rev || ' and GitHub could not yet be asked whether it is on main' end,
      'blast', case when r.verdict = 'not_on_main' then 'security' else 'agent_facing' end,
      'affected', case when r.verdict = 'not_on_main' then 1 else 0 end,
      'evidence', jsonb_build_object('rev', r.rev, 'verdict', r.verdict, 'pr_number', r.pr_number, 'checked_at', r.checked_at,
        'detail', r.detail,
        'objects', (select jsonb_agg(distinct c.command_tag || ' ' || c.object_identity) from public.routine_change_log c
                     where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev),
        'close', 'Re-apply each routine from a reviewed revision, or the ceo or the founder accepts its transaction with public.fn_it_change_accept(txid, who, why).'));
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
end $fn$;
revoke execute on function public.fn_it_change_watch() from public, anon, authenticated;

-- PROBE (read-only, verdict row): the routine now carries the settled rule, and 14ad86a is still raised
-- today because two of its four changes are neither re-applied nor accepted — the rule must not
-- silence a revision on the strength of half its routines.
select case
  when position('SETTLED: every change this revision made' in p.prosrc) = 0 then 'PROBE FAILED: fn_it_change_watch has no settled rule'
  when not p.proconfig @> array['search_path=public, pg_temp'] then 'PROBE FAILED: search_path is not pinned'
  when (select count(*) from public.routine_change_log c
         where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = '14ad86a'
           and not exists (select 1 from public.it_change_acceptance a where a.txid = c.txid)
           and not exists (select 1 from public.routine_change_log s
                             join public.it_change_revision rv on rv.rev = substring(s.application_name from '^qd-apply ([0-9a-f]{7,40}) ')
                            where s.object_identity = c.object_identity and s.at > c.at and rv.verdict in ('on_main', 'merged_pr'))) = 0
    then 'PROBE OK: settled rule installed; 14ad86a is fully settled and its finding closes on the next tick'
  else 'PROBE OK: settled rule installed; 14ad86a still has unsettled changes and stays raised until they are re-applied or accepted'
end as verdict
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'fn_it_change_watch';
