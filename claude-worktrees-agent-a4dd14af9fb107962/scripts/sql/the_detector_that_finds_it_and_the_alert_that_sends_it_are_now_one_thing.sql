-- THE DETECTOR THAT FINDS IT AND THE ALERT THAT SENDS IT ARE NOW ONE THING.
--
-- Built in parallel on 9 September 2026, the IT engineer's detection engine and its alerting were
-- each finished, each proven, and each correct — and they were not connected.
--
--   public.it_watch_finding      10 rows, 3 OPEN     <- fn_it_detect writes here
--   public.it_engineer_finding    0 rows             <- fn_it_engineer_alert_tick reads here
--
-- Three real faults were sitting in the first table, found on live production without any
-- injection, and the founder was never going to hear about any of them:
--
--   [high]   doc_backups     26 undrained rows, oldest waiting 1,434 hours
--   [high]   exec_reports    318 undrained rows, oldest waiting 1,565 hours
--   [medium] review_queue    1,433 undrained rows, oldest waiting 121 hours
--
-- Both halves reported success. The alert tick returned monitor_findings: 0 and that was TRUE of
-- the table it reads. The detection engine's ledger filled up and that was true too. Nothing was
-- broken; there was simply no edge between them, and neither side could see the gap from inside.
-- That is this estate's most expensive recurring shape — a finished capability with no entry point
-- — and building the two halves concurrently is exactly how it gets manufactured.
--
-- THE BRIDGE IS DELIBERATELY LOSSY IN ONE DIRECTION AND NOT THE OTHER.
--
-- The alert carries `ruled_out` and `undetermined` because a handover that does not say what was
-- already eliminated makes the founder's session repeat the work. A detector produces evidence, not
-- deduction, so it has nothing honest to put in `ruled_out` — and inventing a plausible-sounding
-- "already checked the database is up" would be worse than leaving it empty: he would trust it.
-- So `ruled_out` stays empty here and `undetermined` carries the one thing that IS known — that
-- this came from an automatic detector which established the symptom and not the cause.
--
-- SEVERITY IS TRANSLATED, NEVER RE-DECIDED. fn_it_detect derives severity from measured state and
-- whether the surface is public. fn_it_engineer_severity derives it again from blast radius and
-- duration. Two derivations disagreeing would make the founder's email contradict the ledger it
-- points him at, so the detector's own severity is mapped to the blast class that reproduces it,
-- and the mapping is written down rather than left to coincidence.
--
-- WHAT THIS DOES NOT DO: it never closes a finding the detector still has open, and it never
-- reopens one the detector has resolved. The detector owns the truth about whether a fault is
-- present; the alert owns only whether the founder has been told.

create or replace function public.fn_it_engineer_ingest_watch_findings()
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_row      record;
  v_ingested int := 0;
  v_closed   int := 0;
  v_blast    text;
  v_affected int;
  v_errors   text[] := '{}';
begin
  -- OPEN FINDINGS BECOME, OR STAY, ISSUES.
  for v_row in
    select * from public.it_watch_finding where status = 'open'
     order by case severity when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end,
              opened_at
  loop
    begin
      -- The detector's severity, reproduced through the alert's own rule rather than asserted.
      -- 'blast' is what fn_it_engineer_severity reasons about; these are the classes that make its
      -- output match what the detector already decided from the numbers.
      v_blast := case v_row.severity
        when 'critical' then 'customer_facing'   -- critical here means a public surface is affected
        when 'high'     then 'agent_facing'      -- the machine is degraded; people are not yet stuck
        when 'medium'   then 'internal'
        else 'internal' end;

      -- AFFECTED IS A COUNT OF SUBJECTS, NOT A COUNT OF ROWS. A queue holding 1,433 items is one
      -- broken queue, not 1,433 casualties, and feeding the row count in would make every stalled
      -- queue read as a catastrophe and drown the one that is.
      v_affected := case when v_row.severity in ('critical','high') then 1 else 0 end;

      perform public.fn_it_engineer_finding_upsert(
        'watch:' || v_row.detector_key,
        v_row.title,
        v_row.detector || ' / ' || coalesce(v_row.subject, '(no subject)'),
        v_blast,
        v_affected,
        coalesce(v_row.evidence, '{}'::jsonb)
          || jsonb_build_object(
               'detector', v_row.detector,
               'detector_state', v_row.state,
               'detector_severity', v_row.severity,
               'first_detected', v_row.opened_at,
               'times_seen', v_row.seen_count),
        -- NOTHING was ruled out. A detector measures; it does not eliminate causes, and a
        -- fabricated "already checked" line is worse than an empty one because it would be believed.
        array[]::text[],
        array[
          'This came from an automatic detector (' || v_row.detector || '). It established the '
          || 'SYMPTOM and not the cause — no hypothesis has been tested and nothing has been ruled out.',
          'The detector''s own row, including anything seen since this was sent: '
          || 'select * from public.it_watch_finding where detector_key = ' || quote_literal(v_row.detector_key) || ';'
        ],
        'it_engineer.' || v_row.detector);

      v_ingested := v_ingested + 1;
    exception when others then
      v_errors := v_errors || (v_row.detector_key || ': ' || sqlerrm);
    end;
  end loop;

  -- RESOLVED FINDINGS CLOSE THEIR ISSUE. Without this the founder is told a fault appeared and
  -- never told it went away, which is how a person learns to ignore the sender.
  for v_row in
    select w.* from public.it_watch_finding w
     join public.it_engineer_finding f on f.issue_key = 'watch:' || w.detector_key
    where w.status <> 'open' and f.closed_at is null
  loop
    begin
      perform public.fn_it_engineer_finding_close('watch:' || v_row.detector_key,
        'The detector no longer sees it: ' || v_row.detector || ' resolved '
        || coalesce(v_row.resolved_at::text, 'at an unrecorded time') || '.');
      v_closed := v_closed + 1;
    exception when others then
      v_errors := v_errors || (v_row.detector_key || ' (close): ' || sqlerrm);
    end;
  end loop;

  return jsonb_build_object(
    'ingested', v_ingested,
    'closed', v_closed,
    'errors', to_jsonb(v_errors),
    'basis', 'Bridges public.it_watch_finding (what the detectors measured) to '
          || 'public.it_engineer_finding (what the founder has been told). The detector owns '
          || 'whether a fault is present; the alert owns only whether he has heard about it.');
end;
$function$;

revoke execute on function public.fn_it_engineer_ingest_watch_findings() from public;
grant execute on function public.fn_it_engineer_ingest_watch_findings() to service_role;

comment on function public.fn_it_engineer_ingest_watch_findings() is
  'Carries findings from the detection engine''s ledger (it_watch_finding) into the alert''s ledger '
  '(it_engineer_finding), so a detected fault can actually reach the founder. Built 9 Sep 2026 after '
  'both halves were finished separately and neither could see that no edge existed between them: the '
  'alert tick returned monitor_findings: 0, which was true of the table it read, while three real '
  'faults sat open in the other. Severity is TRANSLATED through the alert''s own rule rather than '
  're-decided, so the email cannot contradict the ledger it points at. ruled_out is left empty on '
  'purpose — a detector measures a symptom and eliminates nothing, and an invented "already checked" '
  'line would be trusted.';

-- CLOSING ASSERTION. The bridge is only worth having if a real open finding crosses it, so this
-- proves it on the three that are genuinely open right now — inside a subtransaction that rolls the
-- writes back, and with the positive control first.
do $do$
declare
  v_open int; v_before int; v_res jsonb; v_after int; v_body text; v_sev text;
begin
  select count(*) into v_open from public.it_watch_finding where status = 'open';
  if v_open = 0 then
    raise notice 'no open detector findings right now — the bridge is installed but was not exercised';
    return;
  end if;

  begin
    select count(*) into v_before from public.it_engineer_finding;
    v_res := public.fn_it_engineer_ingest_watch_findings();
    select count(*) into v_after from public.it_engineer_finding;

    if (v_res->>'ingested')::int <> v_open then
      raise exception 'the bridge carried % of % open finding(s)', v_res->>'ingested', v_open;
    end if;
    if v_after <> v_before + v_open then
      raise exception 'expected % new issue(s), got %', v_open, v_after - v_before;
    end if;
    if jsonb_array_length(v_res->'errors') > 0 then
      raise exception 'the bridge reported errors: %', (v_res->'errors')::text;
    end if;

    -- A carried issue must produce a real handover, not an empty shell.
    select f.issue_key into v_body from public.it_engineer_finding f
     where f.issue_key like 'watch:%' order by f.issue_key limit 1;
    v_body := public.fn_it_engineer_handover_body(v_body, 'new');
    if v_body is null or length(v_body) < 400 then
      raise exception 'the handover body is empty or too short to be a handover (% chars)', coalesce(length(v_body), 0);
    end if;
    if position('automatic detector' in v_body) = 0 then
      raise exception 'the handover does not tell the founder this came from a detector, so he cannot weigh it';
    end if;

    raise exception 'ZZ_BRIDGE_ROLLBACK';
  exception when others then
    if sqlerrm <> 'ZZ_BRIDGE_ROLLBACK' then raise; end if;
    raise notice 'bridge proved: % open detector finding(s) carried into real handovers, then rolled back', v_open;
  end;

  -- Nothing may survive.
  select count(*) into v_after from public.it_engineer_finding where issue_key like 'watch:%';
  if v_after <> 0 then
    raise exception '% bridged issue(s) survived the rollback', v_after;
  end if;
end
$do$;
