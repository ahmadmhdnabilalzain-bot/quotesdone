-- A BACKUP OF A SOURCE THAT NO LONGER EXISTS IS ABANDONED, NOT REFILED FOR EVER.
--
-- Assigned: it_engineer. 21 Sep 2026.
--
-- ══ WHAT WAS MEASURED, 21 Sep 2026, against htdblwldjkcgjvmqkbeh (read-only) ═══════════════════
--
-- "Dropbox backup coverage has been failing for over 48 hours (["refile_not_verified_in_48h"])" was
-- filed to the CEO on 17, 18 and 19 Sep and reached the founder on 18, 19 and 20 Sep. The arm:
--   backup.refile handoffs to sales_engineer, pending past 48 h ..... 2   (ids 28974, 38862)
-- Both name ONE file each, both a Stripe invoice PDF in bucket finance-docs, both "download Object
-- not found":
--   doc_backups 109177  status abandoned (by hand, 18 Sep: "the Stripe invoice PDF of a rehearsal
--                       transaction torn down on 14 Sep 2026 - transaction 4710dbb1… no longer
--                       exists") — and its handoff 28974 is STILL pending, because fn_it_backup_recheck
--                       reads an abandoned row as 'failing', and a failing refile past its second
--                       attempt sits behind its escalation for ever.
--   doc_backups 270782  status error, attempts 5, entity transaction 36267ce7… — that transaction
--                       does not exist (select from public.transactions: no such row). It was the
--                       nightly d-payment journey's TEST checkout of 18 Sep, torn down after the run;
--                       stripe_webhook had already queued its invoice for backup.
--   storage.objects in finance-docs under invoices/stripe/ ............ 0 (the bucket holds one 2026-07 test .txt)
-- doc_backups rows for entity 'transaction' whose transaction is gone ... 2, both of the above.
--
-- So the coverage arm has been counting a document whose SOURCE was deliberately deleted — a
-- rehearsal's residue — as a backup failure, every day, and the sales engineer was asked to refile a
-- file that cannot exist. Nothing here was ever a lost customer document.
--
-- ══ WHAT THIS FILE CHANGES ══════════════════════════════════════════════════════════════════
--
-- fn_it_backup_recheck, two edits, body otherwise the deployed one:
--   1. Before the handoff loop it ABANDONS, with a dated reason, every non-done doc_backups row of
--      entity 'transaction' whose transactions row no longer exists. Only that entity: it is the one
--      measured, and the rule is "the source is gone", which for the other entities (leads, customers,
--      inquiries) has not been measured and is not claimed here.
--   2. A file whose row is abandoned WITH a documented reason ('abandoned: …') is settled ('ok'), the
--      same reading fn_backup_coverage already gives such rows (abandoned_documented). An abandonment
--      with no reason stays 'failing', exactly as before.
-- With both, the two pending handoffs close on the next tick (the closer is it_engineer, through the
-- same set_config door as before), refiles_open_past_48h reads 0, and the daily coverage report stops.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE: stripe_webhook's enqueue (a real invoice must be backed up),
-- the journey's teardown, fn_backup_coverage, the escalation ladder.
--
--   node scripts/apply_sql.mjs scripts/sql/a_backup_of_a_source_that_no_longer_exists_is_abandoned_not_refiled_for_ever.sql --apply --ddl

create or replace function public.fn_it_backup_recheck()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; s record; d public.doc_backups; v_since timestamptz; v_files jsonb; v_state text;
  n_ok int; n_fail int; n_wait int; v_att int; v_rep jsonb; n_closed int := 0; n_retry int := 0; n_esc int := 0;
  n_orphaned int := 0;
begin
  -- 1. A backup whose source row is gone can never be filed. Measured 21 Sep 2026: two Stripe invoice
  --    rows for TEST transactions the nightly journey tore down. The reason carries the date and the id.
  update public.doc_backups d
     set status = 'abandoned',
         error = left('abandoned: source transaction ' || d.entity_id || ' no longer exists (measured '
                      || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai; last error: '
                      || coalesce(d.error, 'none') || ')', 300)
   where d.entity = 'transaction' and d.status <> 'done' and d.status <> 'abandoned'
     and not exists (select 1 from public.transactions t where t.id::text = d.entity_id);
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
-- CREATE OR REPLACE preserves the ACL; the revoke below is the existing one, restated for the auditor.
revoke execute on function public.fn_it_backup_recheck() from public, anon, authenticated;

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the verdict is a ROW. Source anchors are statement text. The routine itself is not
-- run here: it closes real handoffs, and this file must leave production exactly as it found it.
-- What it WOULD do is measured read-only: the two orphan rows and the two pending refiles.
with src as (
  select pg_get_functiondef(p.oid) d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_it_backup_recheck' and p.prokind = 'f'
),
chk as (
  select
    (select d like '%not exists (select 1 from public.transactions t where t.id::text = d.entity_id)%' from src) as abandons_orphans,
    (select d like '%like ''abandoned:%'' then ''ok''%' from src)                                                 as documented_abandon_is_settled,
    (select count(*) from public.doc_backups d where d.entity = 'transaction' and d.status <> 'done' and d.status <> 'abandoned'
       and not exists (select 1 from public.transactions t where t.id::text = d.entity_id))                       as orphans_now,
    (select count(*) from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer' and status = 'pending'
       and detail->>'type' = 'backup.refile' and created_at < now() - interval '48 hours')                         as refiles_open_past_48h
)
select case when abandons_orphans and documented_abandon_is_settled
       then 'PROBE OK: fn_it_backup_recheck abandons a transaction backup whose transaction is gone (' || orphans_now
            || ' such row(s) right now) and settles a documented abandonment (' || refiles_open_past_48h
            || ' refile(s) open past 48h will close on the next tick).'
       else 'PROBE FAILED: abandons_orphans=' || coalesce(abandons_orphans::text,'null')
            || ' documented_abandon_is_settled=' || coalesce(documented_abandon_is_settled::text,'null')
       end as verdict
from chk;
