-- A ROUTINE CHANGE NOBODY SIGNED IS A FINDING WITHIN MINUTES.
--
-- Assigned: it_engineer (the guard, the verification, the re-check). The ceo owns the answer: only the
-- ceo or the founder can accept a change made outside the reviewed path.
--
-- Founder, 14 Sep 2026, approving IT duty 24 ("add all for accountant and IT"): any routine_change_log row
-- whose application_name is not a `qd-apply <rev> ...` tag from a revision on origin/main (or a known
-- service) raises an it.finding to the it_engineer within minutes. No model call anywhere.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production): public.routine_change_log
-- (every_routine_change_records_who_made_it.sql) held 111 rows since it was installed that afternoon:
-- 95 as 'mgmt-api' (a session writing through the management API with no tag) and 16 signed
-- 'qd-apply <rev> ...' by scripts/apply_sql.mjs. Nothing read either kind. Those rows are the baseline and
-- are not judged: the guard starts with the next row.
--
-- HOW IT DECIDES, per row, the moment the row is written (trigger z10 on routine_change_log):
--   signed    application_name is 'qd-apply <7-40 hex> ...'. The revision is queued in it_change_revision
--             as 'pending'. Whether it is on main needs GitHub, so the 15-minute tick asks
--             (resilience_ping -> fn_it_change_revisions_due -> GitHub -> fn_it_change_revisions_record).
--   known     session_user or application_name matches a row of it_change_source (data, not code): today
--             only Supabase's own platform maintenance. Nothing is raised.
--   unsigned  anything else: 'mgmt-api', a tag with no revision ('qd-apply unknown ...' from a copy that is
--             not a git checkout), an empty name. ONE it_engineer_finding per transaction
--             ('duty:unsigned_change:tx<txid>', blast 'security', owner ceo) naming every routine that
--             transaction touched, written inside the change's own transaction. fn_it_loop_tick hands it
--             to the ceo on its next 15-minute pass: that is the "within minutes".
--
-- ON MAIN, OR NOT. This repository merges by squash, so the commit a worktree applies from is usually NOT
-- an ancestor of main even after its PR merges. A revision is therefore reviewed when it is an ancestor
-- of main (compare main...rev answers 'behind' or 'identical') OR it belongs to a pull request merged into
-- main (GET /commits/{rev}/pulls). Verdicts:
--   on_main / merged_pr   reviewed: nothing raised, and any finding about it closes.
--   open_pr               applied from a PR not merged yet: raised at agent_facing, quiet for six hours and
--                         loud after (fn_it_engineer_severity). The PR has six hours to merge.
--   not_on_main           GitHub knows no merged or open PR for it: security, at once.
--   pending over 2 hours  GitHub could not be asked: raised quietly, so "could not check" is on record.
--
-- HOW AN UNSIGNED CHANGE CLOSES, only by the IT engineer's own re-check, one of two ways:
--   1. every routine the transaction touched has since been re-applied from a reviewed revision; or
--   2. the ceo or the founder accepted it with fn_it_change_accept(txid, who, why), recorded and kept.
-- An unsigned change nobody re-applies or accepts goes the way every IT finding goes: after the ceo's
-- reply window it is escalated, and the founder gets one plain-English email.
--
-- WHAT IT CANNOT SEE: DDL on tables, triggers or policies (the event trigger records routines only); and a
-- session that sets the qd-apply tag itself with a real reviewed revision. The tag is a label a caller
-- sets, not a signature: it catches the unreviewed copy - what happened three times on 14 Sep 2026 - not
-- someone holding the database password.
-- IT NEVER RAISES INSIDE THE CHANGE IT JUDGES: a failure to judge is written to agent_runs and the change
-- goes ahead. The event trigger that writes the log row swallows every error, so a raise here would lose
-- the log row as well.

create table if not exists public.it_change_source (
  match_on  text not null check (match_on in ('application_name', 'session_user')),
  pattern   text not null check (btrim(pattern) <> ''),
  meaning   text not null check (btrim(meaning) <> ''),
  primary key (match_on, pattern)
);
comment on table public.it_change_source is
  'Callers whose routine changes are known services and are not judged by the unsigned-change guard (IT duty 24). A regular expression per row, on application_name or session_user. A session is never a known service.';
alter table public.it_change_source enable row level security;
drop policy if exists it_change_source_service_role_only on public.it_change_source;
create policy it_change_source_service_role_only on public.it_change_source as permissive for all to public using (false) with check (false);
revoke all on public.it_change_source from anon, authenticated;

insert into public.it_change_source (match_on, pattern, meaning) values
  ('session_user', '^supabase_admin$', 'Supabase platform maintenance: extension and platform upgrades run as supabase_admin, never by a seat or a session')
on conflict (match_on, pattern) do update set meaning = excluded.meaning;

create table if not exists public.it_change_revision (
  rev            text primary key check (rev ~ '^[0-9a-f]{7,40}$'),
  verdict        text not null default 'pending' check (verdict in ('pending', 'on_main', 'merged_pr', 'open_pr', 'not_on_main')),
  pr_number      int,
  first_seen_at  timestamptz not null default now(),
  checked_at     timestamptz,
  detail         jsonb not null default '{}'::jsonb
);
comment on table public.it_change_revision is
  'Every revision a signed apply named, and what GitHub says about it: an ancestor of main, part of a merged or an open pull request, or neither.';
alter table public.it_change_revision enable row level security;
drop policy if exists it_change_revision_service_role_only on public.it_change_revision;
create policy it_change_revision_service_role_only on public.it_change_revision as permissive for all to public using (false) with check (false);
revoke all on public.it_change_revision from anon, authenticated;

create table if not exists public.it_change_acceptance (
  txid         bigint primary key,
  accepted_by  text not null check (accepted_by in ('ceo', 'founder')),
  reason       text not null check (btrim(reason) <> ''),
  accepted_at  timestamptz not null default now()
);
comment on table public.it_change_acceptance is
  'An unsigned routine change the ceo or the founder accepted, with why. Kept, never deleted.';
alter table public.it_change_acceptance enable row level security;
drop policy if exists it_change_acceptance_service_role_only on public.it_change_acceptance;
create policy it_change_acceptance_service_role_only on public.it_change_acceptance as permissive for all to public using (false) with check (false);
revoke all on public.it_change_acceptance from anon, authenticated;

create or replace function public.trg_it_judge_routine_change()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_rev text; v_objects jsonb;
begin
  begin
    v_rev := substring(coalesce(new.application_name, '') from '^qd-apply ([0-9a-f]{7,40}) ');
    if v_rev is not null then
      insert into public.it_change_revision (rev) values (v_rev) on conflict (rev) do nothing;
    elsif not exists (select 1 from public.it_change_source s
                       where (s.match_on = 'session_user' and new.session_user_name ~ s.pattern)
                          or (s.match_on = 'application_name' and coalesce(new.application_name, '') ~ s.pattern)) then
      select jsonb_agg(distinct c.command_tag || ' ' || c.object_identity) into v_objects
        from public.routine_change_log c where c.txid = new.txid;
      perform public.fn_it_engineer_finding_upsert(
        'duty:unsigned_change:tx' || new.txid,
        'A routine change was made outside the reviewed path: ' || jsonb_array_length(v_objects) || ' routine(s) changed by '
          || coalesce(nullif(new.application_name, ''), 'an unnamed session') || ' as ' || new.session_user_name,
        'public.routine_change_log', 'security', 1,
        jsonb_build_object('duty', 'unsigned_change', 'owner_seat', 'ceo', 'subject', 'routine_change_log',
          'txid', new.txid, 'application_name', new.application_name, 'session_user', new.session_user_name,
          'client_addr', host(new.client_addr), 'at', new.at, 'objects', v_objects,
          'close', 'Re-apply each routine with node scripts/apply_sql.mjs from a reviewed revision, or the ceo or the founder accepts it with public.fn_it_change_accept(txid, who, why).'),
        '{}'::text[], '{}'::text[], 'it_engineer.unsigned_change');
    end if;
  exception when others then
    begin
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      values ('it_engineer', 'error', now(), now(), jsonb_build_object('job', 'unsigned_change_guard', 'log_id', new.id),
              left('The unsigned-change guard could not judge routine_change_log ' || new.id || ': ' || sqlerrm, 500));
    exception when others then null;
    end;
  end;
  return null;
end $fn$;
revoke execute on function public.trg_it_judge_routine_change() from public, anon, authenticated;
drop trigger if exists z10_it_judge_routine_change on public.routine_change_log;
create trigger z10_it_judge_routine_change after insert on public.routine_change_log
  for each row execute function public.trg_it_judge_routine_change();

-- The revisions to ask GitHub about: not yet final, seen in the last 30 days, not asked in 10 minutes.
create or replace function public.fn_it_change_revisions_due()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(rev order by first_seen_at), '[]'::jsonb) from (
    select rev, first_seen_at from public.it_change_revision
     where verdict in ('pending', 'open_pr', 'not_on_main') and first_seen_at > now() - interval '30 days'
       and (checked_at is null or checked_at < now() - interval '10 minutes')
     order by first_seen_at limit 20) z
$fn$;
revoke execute on function public.fn_it_change_revisions_due() from public, anon, authenticated;

-- The re-check. Raises what is not reviewed, closes what now is.
create or replace function public.fn_it_change_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.it_change_revision; f record; v_items jsonb := '[]'::jsonb; v_tx bigint; v_note text; n_closed int := 0; v_rev jsonb;
begin
  for r in select * from public.it_change_revision
            where first_seen_at > now() - interval '30 days' and verdict not in ('on_main', 'merged_pr') loop
    continue when r.verdict = 'pending' and r.first_seen_at > now() - interval '2 hours';
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
                     where substring(c.application_name from '^qd-apply ([0-9a-f]{7,40}) ') = r.rev)));
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

-- p: [{rev, verdict, pr_number, detail}] from verifyRevisions. A reading with no verdict (GitHub did not
-- answer) is skipped, so the revision stays due and is asked again.
create or replace function public.fn_it_change_revisions_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; n int := 0;
begin
  if jsonb_typeof(p) is distinct from 'array' then
    raise exception 'fn_it_change_revisions_record takes the array verifyRevisions returns';
  end if;
  for x in select e from jsonb_array_elements(p) e
            where e->>'verdict' in ('on_main', 'merged_pr', 'open_pr', 'not_on_main') loop
    update public.it_change_revision
       set verdict = x->>'verdict', pr_number = (x->>'pr_number')::int, checked_at = now(),
           detail = coalesce(x->'detail', '{}'::jsonb)
     where rev = x->>'rev';
    n := n + 1;
  end loop;
  return jsonb_build_object('recorded', n) || public.fn_it_change_watch();
end $fn$;
revoke execute on function public.fn_it_change_revisions_record(jsonb) from public, anon, authenticated;

create or replace function public.fn_it_change_accept(p_txid bigint, p_by text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if p_by is null or p_by not in ('ceo', 'founder') then
    raise exception 'an unsigned change is accepted by the ceo or the founder, not %', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'say why the change is accepted'; end if;
  if not exists (select 1 from public.routine_change_log where txid = p_txid) then
    raise exception 'no routine change was recorded in transaction %', p_txid;
  end if;
  insert into public.it_change_acceptance (txid, accepted_by, reason) values (p_txid, p_by, p_reason)
  on conflict (txid) do nothing;
  return public.fn_it_change_watch();
end $fn$;
revoke execute on function public.fn_it_change_accept(bigint, text, text) from public, anon, authenticated;
