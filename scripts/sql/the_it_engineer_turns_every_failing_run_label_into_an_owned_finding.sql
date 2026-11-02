-- THE IT ENGINEER TURNS EVERY FAILING RUN LABEL INTO AN OWNED FINDING, AND NAMES A LABEL NO SEAT OWNS.
--
-- Assigned: it_engineer. 27 Oct 2026. Founder ledger 1003 stage 2, contribution IT-C14 of knowledge/standards/
-- it_engineer.json: "Turns failure clusters in agent_runs (over 50% non-ok, more than 5 runs in 7 days) into owned
-- findings, and flags run labels with no owner". Its status there was 'missing': no duty does it.
--
-- ══ MEASURED, 27 Oct 2026, htdblwldjkcgjvmqkbeh (read-only) ═════════════════════════════════════════════════════════
--   agent_runs, last 7 days: 25,114 ok, 644 warn, 58 error, 58 skipped. Over the last 30 days, with fixture traffic
--   excluded (counts.fixture / counts.caller = 'fixture', or a note naming an example.invalid address or ZZ DEMO), these
--   labels had more than 5 runs and more than half of them not ok:
--     llm_gateway_auth 413/413 error ("ai_gateway returned HTTP 502 with no JSON body for knowledge_exam")
--     compliance_archive 368/368, fn:quote_compare 356/628, fn:unsubscribe 346/377, wa_inbound 68/126,
--     site_assistant 39/40, fn:sanctions_screen 13/18, voice_otp_capture 7/7, fn:supplier_onboard 6/7,
--     fn:supplier_catalog_ingest 6/7.
--   The IT watch (it_watch_finding) raises run_failure on a rise against a label's own baseline, so a label that has
--   ALWAYS failed has no rise and no finding: watch:run_failure:compliance_archive was closed on 30 Sep while the label
--   kept failing. No it_engineer_finding exists for llm_gateway_auth at all.
--   Without the fixture filter, the 7-day list is fn:login_otp 234/282 and login_otp 45/45, and every one of those
--   runs is fixture traffic correctly refused. Counting them would be a finding about the rehearsal, not the product.
--
-- ══ WHAT THIS ADDS (code only; no model) ═══════════════════════════════════════════════════════════════════════════
--   it_engineer.run_clusters (daily) fn_it_engineer_run_clusters():
--     1. every run label with more than 5 runs in 7 days and more than half of them not ok (fixture runs counted
--        apart) is ONE finding, issue_key 'duty:run_cluster:<label>', through fn_it_engineer_finding_upsert. Its evidence
--        names the runs, the statuses, three sample notes and the OWNER: function_owner for an edge label
--        ('fn:<slug>' or '<slug>'), else the seat whose duty runs a routine of that name. The existing IT loop
--        (fn_it_loop_open, through the alert tick and the finding chase) hands it to that owner.
--     2. A label no seat owns says so in its title and in evidence.unowned; the loop gives an unowned finding to the CEO.
--     3. A run-cluster finding whose label is no longer a cluster is CLOSED with the measurement that cleared it.
--   Fixture runs are seen only by a fixture run (qd.duty_fixtures = on), under 'duty:run_cluster:fixture:<label>', with
--   evidence.demo = true, which the finding chase skips.
--
-- WHAT IT DOES NOT DO. It fixes no label: the owner does, and the loop holds it to it. It does not change the IT watch.
--
-- Prevented by: scripts/checks/the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.test.mjs
-- Pending: scripts/sql/pending/the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.txt

create or replace function public.fn_it_engineer_run_clusters()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_prefix text := case when coalesce(current_setting('qd.duty_fixtures', true), '') = 'on' then 'duty:run_cluster:fixture:' else 'duty:run_cluster:' end;
  r record; v_owner text; v_subject text; v_key text; v_res jsonb;
  v_labels text[] := '{}'; n_found int := 0; n_new int := 0; n_unowned int := 0; n_closed int := 0; f record;
begin
  for r in
    with runs as (
      select ar.agent as label, coalesce(ar.status, 'none') as status, ar.note
        from public.agent_runs ar
       where ar.started_at > now() - interval '7 days'
         and (coalesce(ar.counts->>'fixture', '0') in ('1', 'true')
              or coalesce(ar.counts->>'caller', '') = 'fixture'
              or coalesce(ar.note, '') ilike '%example.invalid%'
              or coalesce(ar.note, '') like '%ZZ DEMO%') = v_fx)
    select label, count(*) as runs, count(*) filter (where status <> 'ok') as non_ok,
           (select jsonb_object_agg(s, n) from (select status s, count(*) n from runs r2 where r2.label = runs.label group by 1) z) as statuses,
           (select jsonb_agg(x) from (select distinct left(r3.note, 200) x from runs r3
              where r3.label = runs.label and r3.status <> 'ok' and r3.note is not null limit 3) z) as notes
      from runs
     group by label
    having count(*) > 5 and count(*) filter (where status <> 'ok') * 2 > count(*)
     order by count(*) filter (where status <> 'ok') desc
  loop
    n_found := n_found + 1;
    v_labels := v_labels || r.label;
    v_subject := regexp_replace(r.label, '^fn:', '');
    v_owner := coalesce(
      (select o.owner from public.function_owner o join public.org_role s on s.role_id = o.owner and s.status = 'active'
        where o.function_slug = v_subject),
      (select d.owner_seat from public.seat_duty d join public.org_role s on s.role_id = d.owner_seat and s.status = 'active'
        where d.routine = v_subject or d.routine = 'fn_' || v_subject limit 1));
    if v_owner is null then n_unowned := n_unowned + 1; end if;
    v_key := v_prefix || r.label;
    v_res := public.fn_it_engineer_finding_upsert(
      v_key,
      format('%s%s failed %s of %s runs in 7 days (%s)%s', case when v_fx then 'ZZ DEMO ' else '' end, r.label, r.non_ok, r.runs,
             (select string_agg(k || ' ' || v, ', ' order by k) from jsonb_each_text(r.statuses) e(k, v)),
             case when v_owner is null then ' - no seat owns this run label' else '' end),
      'agent_runs label ' || r.label,
      'internal',
      r.non_ok::int,
      jsonb_strip_nulls(jsonb_build_object(
        'duty', 'it_engineer.run_clusters', 'subject', v_subject, 'owner_seat', v_owner, 'unowned', v_owner is null,
        'runs_7d', r.runs, 'non_ok_7d', r.non_ok, 'statuses', r.statuses, 'sample_notes', r.notes,
        'rule', 'more than 5 runs and more than half not ok in 7 days (IT-C14)', 'demo', v_fx)),
      array['fixture runs counted apart'],
      case when v_owner is null then array['which seat owns this run label'] else '{}'::text[] end,
      'it_engineer');
    if (v_res->>'seen_count')::int = 1 or coalesce((v_res->>'reopened')::boolean, false) then n_new := n_new + 1; end if;
  end loop;

  -- a label that is no longer a cluster: its finding is closed with the reading that cleared it
  for f in select e.issue_key, substr(e.issue_key, length(v_prefix) + 1) as label from public.it_engineer_finding e
            where e.closed_at is null and e.issue_key like v_prefix || '%'
              and (v_fx or e.issue_key not like 'duty:run_cluster:fixture:%') loop
    continue when f.label = any (v_labels);
    perform public.fn_it_engineer_finding_close(f.issue_key, format('cleared: %s now has %s non-ok of %s runs in 7 days (rule: more than 5 runs and more than half not ok)',
      f.label,
      (select count(*) filter (where coalesce(status, 'none') <> 'ok') from public.agent_runs where agent = f.label and started_at > now() - interval '7 days'),
      (select count(*) from public.agent_runs where agent = f.label and started_at > now() - interval '7 days')));
    n_closed := n_closed + 1;
  end loop;

  return jsonb_build_object('clusters', n_found, 'new_or_reopened', n_new, 'unowned', n_unowned, 'closed', n_closed,
                            'labels', to_jsonb(v_labels), 'fixture', v_fx);
end $fn$;

revoke execute on function public.fn_it_engineer_run_clusters() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.run_clusters', 'it_engineer', interval '1 day', 'fn_it_engineer_run_clusters',
   'IT-C14: every run label with more than 5 runs and more than half not ok in 7 days (fixture runs apart) is one owned finding, handed to its owner by the IT loop; a label no seat owns says so; a cleared label''s finding is closed with its reading.',
   'scripts/sql/the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
