-- THE BACKUP RE-CHECK NAMES ITS TABLE ALIAS APART FROM ITS RECORD.
--
-- Assigned: it_engineer. 21 Sep 2026. Founder instruction 573: "i dont want things to pop up again
-- for the same reasons".
--
-- ══ WHAT WAS MEASURED, 21 Sep 2026, against htdblwldjkcgjvmqkbeh ═══════════════════════════════
--
-- scripts/checks/it_failures_of_18_to_21_september_do_not_recur.test.mjs, run against production,
-- failed on "the CEO decides the ... dropbox_backup_escalation families":
--   ERROR 42702: column reference "d.entity" is ambiguous
--   DETAIL: It could refer to either a PL/pgSQL variable or a table column.
--   CONTEXT: PL/pgSQL function fn_it_backup_recheck() line 9 at SQL statement
--            fn_ceo_backup_coverage_decide(bigint) line 6 -> fn_ceo_decide_report(bigint) line 7
-- fn_it_backup_recheck declares `d public.doc_backups` and its first statement (added by
-- a_backup_of_a_source_that_no_longer_exists_is_abandoned_not_refiled_for_ever.sql, applied today)
-- is `update public.doc_backups d ... where d.entity = ...`. Every call raises, so the backup refile
-- loop and the CEO's backup-coverage decider that calls it are dead since that apply. That file's
-- probe read the source text and did not run the routine, so it printed PROBE OK.
-- The same shape stopped nine scheduled IT duties on 15-18 Sep.
-- A scan of every plpgsql routine in supabase/schema/full_schema.sql for a table alias named after
-- the routine's own record variable finds exactly one: this one.
--
-- ══ WHAT THIS FILE CHANGES ══════════════════════════════════════════════════════════════════
--
-- fn_it_backup_recheck: the UPDATE's alias `d` becomes `b` (five references in that one statement).
-- Nothing else in the body changes; it is the deployed body otherwise.
--
-- WHAT IT DOES NOT CHANGE: the handoff loop, the escalation ladder, fn_backup_coverage, the callers.
--
-- ══ PREVENTED BY ════════════════════════════════════════════════════════════════════════════
--
-- scripts/checks/no_routine_names_a_table_alias_after_its_own_record.test.mjs (every plpgsql routine
-- in the live mirror, every run of scripts/checks/run.mjs) — it FAILS on today's mirror and passes
-- once this file is applied and the mirror refreshed. The probe below RUNS the routine, rolled back.
--
--   node scripts/apply_sql.mjs scripts/sql/the_backup_recheck_names_its_table_alias_apart_from_its_record.sql --apply --ddl

create or replace function public.fn_it_backup_recheck()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; s record; d public.doc_backups; v_since timestamptz; v_files jsonb; v_state text;
  n_ok int; n_fail int; n_wait int; v_att int; v_rep jsonb; n_closed int := 0; n_retry int := 0; n_esc int := 0;
  n_orphaned int := 0;
begin
  -- 1. A backup whose source row is gone can never be filed. Measured 21 Sep 2026: two Stripe invoice
  --    rows for TEST transactions the nightly journey tore down. The reason carries the date and the id.
  update public.doc_backups b
     set status = 'abandoned',
         error = left('abandoned: source transaction ' || b.entity_id || ' no longer exists (measured '
                      || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai; last error: '
                      || coalesce(b.error, 'none') || ')', 300)
   where b.entity = 'transaction' and b.status <> 'done' and b.status <> 'abandoned'
     and not exists (select 1 from public.transactions t where t.id::text = b.entity_id);
  get diagnostics n_orphaned = row_count;

  for h in select * from public.agent_actions
            where kind = 'handoff' and agent = 'sales_engineer' and status = 'pending'
              and detail->>'type' in ('backup.refile', 'backup.remediate') order by id loop
    v_since := coalesce((h.detail->>'refiled_at')::timestamptz, h.created_at);
    v_files := '[]'::jsonb; n_ok := 0; n_fail := 0; n_wait := 0;
    for s in select e from jsonb_array_elements(coalesce(h.detail->'files', '[]'::jsonb)) e loop
      d := null;
      select * into d from public.doc_backups where id = (s.e->>'doc_backup_id')::bigint;
      v_state := case
        when d.id is null then case when h.detail ? 'sales_done_at' then 'failing' else 'waiting' end
        when d.status = 'done' and d.verified_at > v_since then 'ok'
        -- 2. Abandoned with its reason on the row: settled, the same reading fn_backup_coverage gives it.
        when d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%' then 'ok'
        when d.status in ('skipped_large', 'abandoned') or (d.status = 'error' and d.attempts >= 5) then 'failing'
        else 'waiting' end;
      if v_state = 'ok' then n_ok := n_ok + 1; elsif v_state = 'failing' then n_fail := n_fail + 1; else n_wait := n_wait + 1; end if;
      v_files := v_files || (s.e || jsonb_build_object('state', v_state, 'status', d.status, 'attempts', d.attempts, 'error', d.error));
    end loop;
    v_att := coalesce((h.detail->>'refile_attempts')::int, 0);

    if n_fail = 0 and n_wait = 0 then
      perform set_config('qd.backup_closer', 'it_engineer', true);
      perform set_config('qd.backup_closer_routine', 'fn_it_backup_recheck', true);
      perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'it_engineer', 'files', v_files, 'verified_at', now()));
      perform set_config('qd.backup_closer', '', true);
      perform set_config('qd.backup_closer_routine', '', true);
      update public.agent_actions set decided_by = 'it_engineer' where id = h.id;
      n_closed := n_closed + 1;
    elsif h.detail->>'type' = 'backup.refile' and not (h.detail ? 'escalated_report_id') then
      if n_fail > 0 and v_att < 2 then
        perform public.fn_seat_handoff_act(h.id);          -- the second refile
        n_retry := n_retry + 1;
      elsif n_fail > 0 or h.created_at < now() - interval '48 hours' then
        v_rep := public.fn_support_report_to_ceo(
          'backup_escalation:' || h.id, 'serious',
          'Dropbox backup: ' || (n_fail + n_wait) || ' file(s) still not backed up after ' || v_att || ' refile(s)'
            || case when h.created_at < now() - interval '48 hours' then ' and 48 hours' else '' end,
          jsonb_build_object('handoff_id', h.id, 'files', v_files, 'refile_attempts', v_att, 'opened_at', h.created_at),
          jsonb_build_array(jsonb_build_object('action', 'handed to sales_engineer to refile', 'handoff_id', h.id, 'attempts', v_att,
                                               'last_refile_at', h.detail->>'refiled_at')),
          'Send the sales engineer instructions for these files, or record that they cannot be backed up and why. The IT engineer re-checks each file and closes only when it is verified in Dropbox.',
          p_review_in => interval '1 day', p_source_agent => 'it_engineer');
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', v_rep->'report_id', 'escalated_at', now())
         where id = h.id;
        perform public.fn_ceo_backup_escalation_decide((v_rep->>'report_id')::bigint);
        n_esc := n_esc + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'second_refiles', n_retry, 'escalated', n_esc, 'orphaned_abandoned', n_orphaned);
end $fn$;
-- CREATE OR REPLACE preserves the ACL; the revoke is restated on the exact signature.
revoke execute on function public.fn_it_backup_recheck() from public, anon, authenticated;

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- The routine is RUN, inside a block that always raises, so everything it would close, refile or
-- escalate is rolled back and nothing reaches a person. The verdict is a ROW.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare v_out jsonb;
begin
  begin
    v_out := public.fn_it_backup_recheck();
    raise exception 'zz_probe_rollback:%', v_out::text;
  exception when others then
    if sqlerrm like 'zz_probe_rollback:%' then
      insert into zz_probe_verdict values ('PROBE OK', 'fn_it_backup_recheck ran and returned ' || substr(sqlerrm, 19) || ' (rolled back)');
    else
      insert into zz_probe_verdict values ('PROBE FAILED', sqlstate || ' ' || sqlerrm);
    end if;
  end;
end
$probe$;
select verdict, detail from zz_probe_verdict;
