-- THE BACKUP REFILE LOOKS UP ITS OWN FILE INSTEAD OF RECOMPUTING EVERY EXPECTED FILE.
--
-- Assigned: sales_engineer (the refile handler it owns), for it_engineer (whose daily Dropbox check
-- was timing out on it). 22 Sep 2026. Founder instruction 573: "i dont want things to pop up again
-- for the same reasons".
--
-- ══ WHAT WAS MEASURED, 22 Sep 2026, against htdblwldjkcgjvmqkbeh ═══════════════════════════════
--
-- resilience_step backupVerify has not passed since 20 Sep 03:31: dropbox_backup mode 'reconcile' ->
-- fn_dropbox_reconcile_apply -> fn_it_backup_check answers "canceling statement due to statement
-- timeout" (PostgREST 8 s), so the whole check rolls back, logs nothing, and the next day finds the
-- same files again. Timed (rolled back): fn_it_backup_check('[]') 24.6-29.0 s, of which the
-- fn_seat_handoff('backup.refile') call is 18.9 s. The handoff acts synchronously (fn_seat_handoff ->
-- fn_seat_handoff_act -> fn_sales_engineer_acts_on_handoff -> fn_sales_engineer_refiles_backup).
--
-- THE SLOW STATEMENT, inside the refile's per-file loop, for every file with no doc_backups row:
--     select x.doc_backup_id into v_row from public.fn_it_backup_expected_status() x where x.item_key = ...
-- fn_it_backup_expected_status() is a SQL set-returning function over fn_it_backup_expected(), which
-- enumerates every expected item (10,604 today) before the item_key filter can apply: EXPLAIN ANALYZE
-- 2,628 ms for fn_it_backup_expected() alone, 2,736 ms for _status. Called once PER FILE, so the 7
-- never_queued files of 22 Sep (backups/2026-09-15..21/table_export_change/page_0000.json) cost
-- 7 x ~2.7 s = ~19 s. The number of files is the multiplier, so the more that went wrong, the
-- surer the check was to die -- and it never recorded the files it was dying on.
--
-- ══ WHAT THIS FILE CHANGES ══════════════════════════════════════════════════════════════════
--
-- fn_sales_engineer_refiles_backup: that one lookup reads doc_backups directly, by exactly the rule
-- fn_it_backup_expected_status joins on (generated -> gen_kind + gen_ref; otherwise bucket + path,
-- the done row first, then the newest), on the file the handoff already carries. Both are indexed
-- (doc_backups_gen_kind_ref_idx, doc_backups_bucket_path_key): EXPLAIN ANALYZE 0.15 ms a file. The
-- rest of the body is the deployed body, unchanged.
--
-- WHAT IT DOES NOT CHANGE: fn_seat_handoff still has the receiving seat act at once -- that is every
-- conversation's contract in this estate and there is no tick that drains pending handoffs, so moving
-- the refile onto one would be a second mechanism. fn_it_backup_check still scans the expected set
-- ONCE a run (~2.7 s; the only large term left). Why those 7 table-export pages were never queued
-- (their day's export did not finish, fn_enqueue_doc_backups files only finished days) is the table
-- export's subject, not this one.
--
-- ══ PREVENTED BY ════════════════════════════════════════════════════════════════════════════
--
-- scripts/sql/the_backup_check_answers_inside_its_budget_probe.sql: runs fn_it_backup_check with a
-- realistic refile (the real never_queued files), rolled back, and returns PROBE FAILED over 4 s.
-- scripts/checks/the_backup_refile_never_recomputes_the_expected_set.test.mjs: fails if the refile
-- body (live mirror) reads fn_it_backup_expected* inside its loop again.
--
--   node scripts/apply_sql.mjs scripts/sql/the_backup_refile_looks_up_its_own_file_instead_of_recomputing_every_expected_file.sql --apply

create or replace function public.fn_sales_engineer_refiles_backup(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; fin jsonb; fout jsonb := '[]'::jsonb; v_att int; v_row bigint; n int; v_out text;
  v_enq boolean := false; s record;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_att := coalesce((a.detail->>'refile_attempts')::int, 0) + 1;
  fin := coalesce(a.detail->'files',
           jsonb_build_array(jsonb_build_object('key', 'db:' || (a.detail->>'doc_backup_id'), 'reason', a.detail->>'reason',
                                                'doc_backup_id', (a.detail->>'doc_backup_id')::bigint)));
  for s in select e from jsonb_array_elements(fin) e loop
    v_row := (s.e->>'doc_backup_id')::bigint; v_out := null;
    if v_row is null then
      -- never queued: the enqueue first, then a row of our own for what it does not cover
      if not v_enq then perform public.fn_enqueue_doc_backups(); v_enq := true; end if;
      -- 22 SEP 2026: the row for THIS file, by the join rule of the expected-status view, on the file
      -- in hand. It used to recompute all ~10,600 expected items (2.7 s) once per file, and seven files
      -- put the IT engineer's daily check past PostgREST's 8 s. See the header.
      if s.e->>'kind' = 'generated' then
        select d.id into v_row from public.doc_backups d
         where d.gen_kind = s.e->>'gen_kind' and d.gen_ref = s.e->>'gen_ref'
         order by (d.status = 'done') desc, d.id desc limit 1;
      elsif s.e->>'bucket' is not null then
        select d.id into v_row from public.doc_backups d
         where d.bucket = s.e->>'bucket' and d.path = s.e->>'path'
         order by (d.status = 'done') desc, d.id desc limit 1;
      end if;
      if v_row is null and s.e->>'bucket' is not null and s.e->>'kind' <> 'conversation' then
        insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key)
        values (split_part(s.e->>'owner', ':', 1), split_part(s.e->>'owner', ':', 2), 'Refiled', s.e->>'bucket', s.e->>'path',
                regexp_replace(s.e->>'path', '^.*/', ''), '/QuotesDone Backup/Refiled/' || (s.e->>'bucket') || '/' || (s.e->>'path'),
                'storage', 'REFILE:' || (s.e->>'bucket') || ':' || (s.e->>'path'))
        on conflict do nothing returning id into v_row;
      elsif v_row is null and s.e->>'kind' = 'generated' then
        insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
        values (split_part(s.e->>'owner', ':', 1), split_part(s.e->>'owner', ':', 2), 'Refiled', 'generated', s.e->>'gen_kind', s.e->>'gen_ref',
                '/QuotesDone Backup/Refiled/' || (s.e->>'gen_kind') || '/' || (s.e->>'gen_ref') || '.pdf', 'REFILE:' || (s.e->>'item_key'))
        on conflict do nothing returning id into v_row;
      end if;
      v_out := case when v_row is null then 'cannot_refile: no source to file from' else 'queued' end;
    end if;
    if v_row is not null and v_out is null then
      update public.doc_backups
         set status = 'pending', attempts = 0, verified_at = null, requeued_at = now(),
             error = left('refile ' || v_att || ': ' || coalesce(s.e->>'reason', 'requested') || ' (handoff ' || p_id || ')', 300)
       where id = v_row and status <> 'abandoned';
      get diagnostics n = row_count;
      v_out := case when n = 1 then 'requeued' else 'cannot_refile: row missing or abandoned' end;
    end if;
    fout := fout || (s.e || jsonb_build_object('doc_backup_id', v_row, 'refile', v_out));
  end loop;
  update public.agent_actions
     set detail = detail || jsonb_build_object('files', fout, 'refile_attempts', v_att, 'refiled_at', now(), 'sales_done_at', now())
   where id = p_id;
  return jsonb_build_object('waiting', 'it_engineer re-verification', 'refile_attempt', v_att, 'files', fout);
end $fn$;
-- CREATE OR REPLACE preserves the ACL; the revoke is restated on the exact (only) signature.
revoke execute on function public.fn_sales_engineer_refiles_backup(bigint) from public, anon, authenticated;
