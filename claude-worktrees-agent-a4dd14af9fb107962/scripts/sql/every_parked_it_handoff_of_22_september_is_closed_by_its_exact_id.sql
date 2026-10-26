-- EVERY PARKED IT HANDOFF OF 22 SEPTEMBER IS CLOSED BY ITS EXACT ID, WITH WHAT WAS LEARNED.
--
-- Assigned: ceo. 22 Sep 2026. Data only: no routine, no table. Apply AFTER
-- every_handoff_is_answered_within_its_window.sql (section 2 below checks that it is live).
--
-- MEASURED, read-only, 22 Sep 2026 06:50-07:30Z: 29 it.finding handoffs pending more than 6 h, every one
-- answered by its seat, every one's finding cleared, every one's CEO report 'it_loop:<id>' accepted, and
-- every one parked at awaiting_learning because its it_incident had no cause, fix or regression check.
-- Why they parked, and the fix so it cannot recur silently, is every_handoff_is_answered_within_its_window.sql.
-- Plus two open findings, duty:delivery:request:48729 and :50861: founder-bound requests correctly held
-- for the 19:00 Dubai IT digest, misread by the delivery duty as undelivered.
--
-- WHAT THIS DOES, ROW BY ROW -- never by pattern (memory: close a finding by its exact key):
--   1. For each of the 29 handoff ids listed below, it re-checks, at apply time, that the handoff is still
--      pending, is an it.finding, carries EXACTLY the issue key listed beside it, that the occurrence it
--      tracked has cleared, and that its incident is still incomplete. Only then does it record the
--      learning with fn_it_attach_learning (the gate's own door; trigger z62 is not bypassed), which closes
--      the handoff as it_engineer, and completes that handoff's 'it_loop:<id>' CEO report by exact key.
--      Any row that fails a check is skipped and says why; nothing is closed on a guess.
--   2. Closes duty:delivery:request:48729 and :50861 by exact key, only if the digest still legitimately
--      holds the request (pending, evidence.digest = 'pending', before fn_it_digest_hold_ends).
--
-- WHAT EACH CAUSE SAYS. Written from the handoff's own title, the finding's evidence and close note.
-- Where the evidence names a cause, it is quoted; where it does not, the cause says "not determined"
-- instead of inventing one, and not_automatable_reason says why no routine could have closed it. Seven
-- rows name an existing playbook class (dependency_advisory, restore_table, unreviewed_revision).
--
-- WHAT THIS DOES NOT DO. It writes no it_playbook cause for the classes still without one (queue_stalled,
-- run_silent, access, credential, journey_heartbeat, table_export, org_task_queue, browser_journey,
-- monitor): a class's cause is written from measurement, and one occurrence each is not that. If those
-- classes park again, the handoff_sla duty now raises it within the reply window instead of never.
--
-- Returns one row per subject and a final verdict row: PROBE OK when all 31 were handled or already
-- resolved, PROBE FAILED otherwise. Re-applying is safe: a closed handoff or finding is skipped.
--
--   node scripts/apply_sql.mjs scripts/sql/every_parked_it_handoff_of_22_september_is_closed_by_its_exact_id.sql --apply --ddl

create temp table if not exists _qd_resolution (subject text, outcome text, evidence jsonb) on commit drop;

-- ── 1. THE 29, BY EXACT ID AND EXACT KEY ────────────────────────────────────────────────────────
do $res$
declare
  v record; h public.agent_actions; f public.it_engineer_finding; i public.it_incident;
  v_cleared boolean; v_reopened boolean; v_done text; v_cause text; v_fix text; r jsonb; n_rep int;
  c_by constant text := 'ceo (every_parked_it_handoff_of_22_september_is_closed_by_its_exact_id.sql, 22 Sep 2026)';
  -- {title} = the handoff's own title for the occurrence it tracked; {cleared} = how that occurrence ended.
  c_code constant text := 'A code or configuration change shipped through a pull request; no seat can make one.';
begin
  for v in select * from (values
    (16499::bigint, 'duty:credential:github',
     '{title} (14 Sep 2026 16:01Z). The duty records the HTTP status, not why the token was refused; not determined beyond "the GitHub credential in use was refused".',
     'No code changed for this finding: {cleared}.',
     'fn_it_duty_settle reopens duty:credential:github the next hourly tick the credential duty reads a 401 or 403 from GitHub.',
     null, 'A refused provider token is renewed at the provider by the account holder; no routine can mint a GitHub token.'),
    (19478, 'duty:access:dropbox:dbid:AADF32qp79e_CC8vnHWFCsBeJi1nrvRy03k',
     '{title}: the access duty found an owner-level principal that was not in it_access_known.',
     '{cleared}.',
     'fn_it_duty_settle reopens the key whenever the access duty lists an owner missing from it_access_known.',
     null, 'Whether an owner account is the founder''s is his decision (founder_instruction 426), not a routine''s.'),
    (19479, 'duty:access:vercel:ahmadmhdnabilalzain-1500',
     '{title}: the access duty found an owner-level principal that was not in it_access_known.',
     '{cleared}.',
     'fn_it_duty_settle reopens the key whenever the access duty lists an owner missing from it_access_known.',
     null, 'Whether an owner account is the founder''s is his decision (founder_instruction 426), not a routine''s.'),
    (21160, 'duty:restore_table:export_stale',
     '{title}. Measured on the finding: newest_export_day 2026-09-07 against max_age_days 2 -- no daily table export finished between 7 and 14 Sep 2026.',
     'Daily exports resumed (supabase/functions/backup, claimed by resilience_ping through fn_table_export_due): {cleared}.',
     'fn_it_duty_settle reopens duty:restore_table:export_stale when the newest finished export is older than max_age_days.',
     'restore_table', null),
    (21161, 'duty:restore_table:restore',
     '{title}. Measured on the finding: the drill read 2026-09-07/supplier_dues/page_0000.json, rows_in_file 0, restored 0 -- the only export on hand was the stale one of 7 Sep.',
     'Daily exports resumed, so the drill had a current sample: {cleared}.',
     'The monthly restore drill (the restore_table duty) reopens duty:restore_table:restore when a sample does not restore identical to live.',
     'restore_table', null),
    (25688, 'watch:queue_stalled:notifications_outbox',
     '{title}. The detector measures the age of the oldest notifications row with status = ''queued''; it does not record why the drain skipped them, so the cause is not determined.',
     'The rows drained with no change recorded against this occurrence: {cleared}.',
     'The queue_stalled detector re-measures the outbox every 15 minutes and reopens watch:queue_stalled:notifications_outbox past its 60-minute threshold.',
     null, 'The cause was not recorded while the rows were queued; a stall with an unknown cause has no deterministic remedy.'),
    (28947, 'watch:queue_stalled:notifications_outbox',
     '{title}. The detector measures the age of the oldest notifications row with status = ''queued''; it does not record why the drain skipped them, so the cause is not determined.',
     'The rows drained with no change recorded against this occurrence: {cleared}.',
     'The queue_stalled detector re-measures the outbox every 15 minutes and reopens watch:queue_stalled:notifications_outbox past its 60-minute threshold.',
     null, 'The cause was not recorded while the rows were queued; a stall with an unknown cause has no deterministic remedy.'),
    (29224, 'watch:queue_stalled:notifications_outbox',
     '{title}. The detector measures the age of the oldest notifications row with status = ''queued''; it does not record why the drain skipped them, so the cause is not determined.',
     'The rows drained with no change recorded against this occurrence: {cleared}.',
     'The queue_stalled detector re-measures the outbox every 15 minutes and reopens watch:queue_stalled:notifications_outbox past its 60-minute threshold.',
     null, 'The cause was not recorded while the rows were queued; a stall with an unknown cause has no deterministic remedy.'),
    (25845, 'duty:table_export:chain_stalled',
     '{title}. A hop that dies without saving (a CPU or memory kill, a crash, or a deploy killing the worker) cannot report its own cause; the duty records the table and page where it stopped.',
     'The chain resumed from its saved page as a later attempt: {cleared}. Since 22 Sep 2026 fn_table_export_due v2 also resumes a failed day from its failed page.',
     'fn_it_duty_settle reopens duty:table_export:chain_stalled when an export chain''s heartbeat stops.',
     null, 'A worker killed by the platform leaves no error to act on; the resume is already automatic.'),
    (32954, 'duty:table_export:day_failed',
     '{title}: fn_table_export_save hit the statement timeout.',
     'The day was re-run: {cleared}. fn_table_export_due v2 (22 Sep 2026) resumes a failed day from its failed page instead of from the start.',
     'fn_it_duty_settle reopens duty:table_export:day_failed when a daily export ends failed.',
     null, 'A save that outgrows the statement timeout is a sizing change in code, not a seat''s step.'),
    (29102, 'duty:journey_heartbeat:no_run',
     '{title}. The duty sees only that no journey report arrived in 26 hours; whether .github/workflows/nightly-journey.yml was not triggered, failed, or failed to report was not recorded.',
     'A nightly run reported again: {cleared}.',
     'fn_it_duties duty 1 reopens duty:journey_heartbeat:no_run after 26 hours with no journey report.',
     null, 'A GitHub Actions run that does not start or report is outside anything the database can remedy.'),
    (39023, 'monitor:detect_tick_blind',
     '{title}. The monitor sees the gap, not its cause (a timeout or error from fn_it_detect in resilience_ping''s response was not recorded on the finding).',
     'Detector ticks resumed: {cleared}.',
     'The detect_tick_blind monitor reopens the key when fn_it_detect persists no tick for 45 minutes.',
     null, 'A missed tick is the edge scheduler or a statement timeout; nothing in the database can restart it.'),
    (39841, 'duty:dependency:app:postcss:1117015',
     '{title} -- an npm advisory against the version pinned in package-lock.json.',
     '{cleared}.', 'fn_it_duty_settle reopens the key if the daily dependency duty finds the advisory again.',
     'dependency_advisory', null),
    (39842, 'duty:dependency:app:sharp:1124066',
     '{title} -- an npm advisory against the version pinned in package-lock.json.',
     '{cleared}.', 'fn_it_duty_settle reopens the key if the daily dependency duty finds the advisory again.',
     'dependency_advisory', null),
    (39843, 'duty:dependency:app:next:1193676',
     '{title} -- an npm advisory against the version pinned in package-lock.json.',
     '{cleared}.', 'fn_it_duty_settle reopens the key if the daily dependency duty finds the advisory again.',
     'dependency_advisory', null),
    (39844, 'duty:dependency:app:nanoid:1139427',
     '{title} -- an npm advisory against the version pinned in package-lock.json.',
     '{cleared}.', 'fn_it_duty_settle reopens the key if the daily dependency duty finds the advisory again.',
     'dependency_advisory', null),
    (39845, 'duty:db_backup:pitr',
     '{title}: the finding measured pitr_enabled = false.',
     '{cleared} Closed as a founder decision, not as a change.',
     'The db_backup duty measures pitr_enabled each run; company_policy_decision supabase_pitr_addon:declined records why it stays off.',
     null, 'Buying the add-on is the founder''s spending decision (instruction 585).'),
    (41935, 'duty:unsigned_revision:rev:14ad86a',
     '{title}. The finding lists the four routines applied from that revision.',
     '{cleared}.',
     'fn_it_duty_settle reopens the key when the unsigned_revision duty finds a routine change from a revision on neither main nor an open pull request.',
     'unreviewed_revision', null),
    (29101, 'duty:delivery:request:29000',
     '{title}. The delivery duty sees only that request 29000 had no loop verdict; the loop later closed it as ''escalated'' (a delivery_undelivered report to the CEO).',
     'The customer_support delivery loop returned its verdict: {cleared}.',
     'fn_it_duties duty 4 reopens a duty:delivery:request key for any request with no loop verdict past its window.',
     null, 'An undelivered message is decided on its own delivery_undelivered CEO report, not by the IT loop.'),
    (29219, 'watch:run_silent:send_whatsapp',
     '{title}. run_silent measures the gap against the function''s own 7-day cadence; it does not see why send_whatsapp stopped being invoked, so the cause is not determined.',
     'Invocations resumed: {cleared}.',
     'The run_silent detector re-measures send_whatsapp''s gap every 15 minutes against its cadence and reopens the key.',
     null, 'The cause of a silent function was not recorded; with no cause there is no deterministic remedy.'),
    (38849, 'watch:run_silent:send_whatsapp',
     '{title}. run_silent measures the gap against the function''s own 7-day cadence; it does not see why send_whatsapp stopped being invoked, so the cause is not determined.',
     'Invocations resumed: {cleared}.',
     'The run_silent detector re-measures send_whatsapp''s gap every 15 minutes against its cadence and reopens the key.',
     null, 'The cause of a silent function was not recorded; with no cause there is no deterministic remedy.'),
    (39010, 'watch:run_silent:send_whatsapp',
     '{title}. run_silent measures the gap against the function''s own 7-day cadence; it does not see why send_whatsapp stopped being invoked, so the cause is not determined.',
     'Invocations resumed: {cleared}.',
     'The run_silent detector re-measures send_whatsapp''s gap every 15 minutes against its cadence and reopens the key.',
     null, 'The cause of a silent function was not recorded; with no cause there is no deterministic remedy.'),
    (39847, 'duty:org_task_queue:knowledge_gap:customer_support',
     '{title}. The consumer''s own reason: no company knowledge ranked above the 1.5 floor for these questions -- the knowledge did not exist.',
     'The tasks left the assigned queue: {cleared}.',
     'fn_it_duty_settle reopens the key whenever org_tasks of this class sit on a seat whose consumer cannot finish them.',
     null, 'Writing missing knowledge into a corpus is authoring, not a routine step.'),
    (37240, 'duty:org_task_queue:knowledge_gap:sales_engineer',
     '{title}. The consumer''s own reason: no company knowledge ranked above the 1.5 floor for these questions -- the knowledge did not exist.',
     'The tasks left the assigned queue: {cleared}.',
     'fn_it_duty_settle reopens the key whenever org_tasks of this class sit on a seat whose consumer cannot finish them.',
     null, 'Writing missing knowledge into a corpus is authoring, not a routine step.'),
    (39707, 'duty:org_task_queue:routine_operational_decision:sales_engineer',
     '{title}. The consumer''s own reason: the task did not carry the supplier name, licence and decision in the form fn_founder_mail_route writes them.',
     'The tasks left the assigned queue: {cleared}.',
     'fn_it_duty_settle reopens the key whenever org_tasks of this class sit on a seat whose consumer cannot finish them.',
     null, 'A task produced in the wrong shape is fixed at its producer, which is a code change.'),
    (38480, 'browser_journey:arabic_dates_are_forced_left_to_right_in_the_supplier_portal',
     '{title}. Measured by the 18 Sep browser journey: every date was wrapped in <bdi dir="ltr">, so an Arabic month name ran right-to-left inside a forced left-to-right run.',
     '{cleared}.', 'scripts/checks/ltr_is_never_forced_onto_a_localised_date.test.mjs',
     null, c_code),
    (38481, 'browser_journey:a_revealed_request_still_shows_reveal_as_not_reached',
     '{title}. Measured by the 18 Sep browser journey: the stage rail lit its last node from the hired stage index, not from revealed.',
     '{cleared}.', 'scripts/checks/the_customer_portal_defects_of_the_18_september_journey_stay_fixed.test.mjs',
     null, c_code),
    (38619, 'browser_journey:no_customer_can_rate_a_supplier_the_stars_always_answer_500',
     '{title}. Measured 18 Sep 2026 in an aborted-transaction probe: reviews_reason_required refused a review with no comment and the star widget sends none, so customer_api answered HTTP 500.',
     '{cleared}.', 'supabase/functions/customer_api/rating_input.test.ts',
     null, c_code),
    (38847, 'browser_journey:the_first_request_flashes_the_you_have_none_empty_state_after_it_is_sent',
     '{title}. Measured by the 18 Sep browser journey: booting is true only before the first load, so the reload after a first request rendered the empty state for 0.3 to 1.5 s.',
     '{cleared}.', 'scripts/checks/the_customer_portal_defects_of_the_18_september_journey_stay_fixed.test.mjs',
     null, c_code)
  ) as t(id, issue_key, cause, fix, regression_check, playbook_class, reason) loop
    begin
      select * into h from public.agent_actions where id = v.id;
      if h.id is null or h.kind <> 'handoff' or h.detail->>'type' <> 'it.finding' then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: not an it.finding handoff', null); continue;
      end if;
      if h.status = 'done' then
        insert into _qd_resolution values ('handoff ' || v.id, 'ALREADY CLOSED', jsonb_build_object('decided_at', h.decided_at)); continue;
      end if;
      if h.status <> 'pending' or h.detail->>'issue_key' is distinct from v.issue_key then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: status or issue key differs from the list',
          jsonb_build_object('status', h.status, 'issue_key', h.detail->>'issue_key', 'listed', v.issue_key)); continue;
      end if;
      select * into f from public.it_engineer_finding where issue_key = v.issue_key;
      v_reopened := f.issue_key is not null and f.started_at > (h.detail->>'occurrence_started_at')::timestamptz;
      v_cleared := f.issue_key is null or f.closed_at is not null or v_reopened;
      if not v_cleared then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: the occurrence is still open',
          jsonb_build_object('issue_key', v.issue_key, 'started_at', f.started_at)); continue;
      end if;
      select * into i from public.it_incident where handoff_id = v.id;
      if i.id is null then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: no incident; fn_it_loop_reverify closes it on its next tick', null); continue;
      end if;

      v_done := case when v_reopened
                     then 'the occurrence ended before the finding reopened at ' || to_char(f.started_at at time zone 'UTC', 'DD Mon YYYY HH24:MI') || 'Z'
                     else coalesce(nullif(btrim(f.close_note), ''), 'the finding closed') || ' (closed '
                          || to_char(f.closed_at at time zone 'UTC', 'DD Mon YYYY HH24:MI') || 'Z)' end;
      v_cause := replace(v.cause, '{title}', regexp_replace(coalesce(h.detail->>'title', v.issue_key), '[.\s]+$', ''));
      v_fix   := replace(v.fix, '{cleared}', v_done);
      r := public.fn_it_attach_learning(v.id, v_cause, v_fix, v.regression_check, v.playbook_class, v.reason, c_by);

      update public.support_ceo_report
         set status = 'completed', completed_at = now(),
             completion_note = 'IT engineer re-verified: handoff ' || v.id || ' is closed with its learning recorded (' || c_by || ').'
       where idempotency_key = 'it_loop:' || v.id and status = 'accepted';
      get diagnostics n_rep = row_count;
      insert into _qd_resolution values ('handoff ' || v.id,
        case when coalesce((r->>'closed')::boolean, false) then 'CLOSED' else 'LEARNING RECORDED, NOT CLOSED' end,
        jsonb_build_object('issue_key', v.issue_key, 'incident_id', i.id, 'finding_closed_at', f.closed_at,
                           'reopened_later', v_reopened, 'report_completed', n_rep, 'attach', r));
    exception when others then
      insert into _qd_resolution values ('handoff ' || v.id, 'ERROR: ' || left(sqlerrm, 300), null);
    end;
  end loop;
end
$res$;

-- ── 2. THE TWO DELIVERY FINDINGS, BY EXACT KEY ──────────────────────────────────────────────────
do $res2$
declare
  v_req bigint; a public.agent_actions; f public.it_engineer_finding; x public.agent_actions; i public.it_incident; r jsonb;
  v_fixed boolean := exists (select 1 from pg_proc where oid = 'public.fn_it_duties(jsonb)'::regprocedure
                              and prosrc like '%fn_it_digest_hold_ends%');
begin
  foreach v_req in array array[48729, 50861]::bigint[] loop
    begin
      select * into f from public.it_engineer_finding where issue_key = 'duty:delivery:request:' || v_req;
      select * into a from public.agent_actions where id = v_req;
      if f.issue_key is null then
        insert into _qd_resolution values ('duty:delivery:request:' || v_req, 'SKIPPED: no such finding', null); continue;
      elsif f.closed_at is not null then
        insert into _qd_resolution values ('duty:delivery:request:' || v_req, 'ALREADY CLOSED', jsonb_build_object('close_note', f.close_note));
      elsif not v_fixed then
        insert into _qd_resolution values ('duty:delivery:request:' || v_req,
          'SKIPPED: apply every_handoff_is_answered_within_its_window.sql first, or the duty reopens it next hour', null); continue;
      elsif not (a.status = 'pending' and a.evidence->>'digest' = 'pending' and now() < public.fn_it_digest_hold_ends(a.created_at))
            and not (a.detail ? 'loop') then
        insert into _qd_resolution values ('duty:delivery:request:' || v_req,
          'SKIPPED: the digest no longer legitimately holds this request -- it is really late',
          jsonb_build_object('status', a.status, 'digest', a.evidence->>'digest', 'hold_ends', public.fn_it_digest_hold_ends(a.created_at)));
        continue;
      else
        perform public.fn_it_engineer_finding_close(f.issue_key,
          'Not late: request ' || v_req || ' is held by customer_support for the 19:00 Dubai IT digest (evidence.digest = '
          || coalesce(a.evidence->>'digest', 'n/a') || ', loop = ' || coalesce(a.detail->>'loop', 'none') || '); the delivery duty now waits until '
          || to_char(public.fn_it_digest_hold_ends(a.created_at) at time zone 'UTC', 'DD Mon HH24:MI') || 'Z (every_handoff_is_answered_within_its_window.sql).');
        insert into _qd_resolution values ('duty:delivery:request:' || v_req, 'CLOSED',
          jsonb_build_object('request_status', a.status, 'digest', a.evidence->>'digest', 'hold_ends', public.fn_it_digest_hold_ends(a.created_at)));
      end if;

      -- Its it.finding handoff: with no incident, fn_it_loop_reverify closes it on its next tick. With one
      -- (the CEO escalated it first), the learning is recorded here from what was measured today.
      for x in select * from public.agent_actions where kind = 'handoff' and status = 'pending'
                  and detail->>'type' = 'it.finding' and detail->>'issue_key' = 'duty:delivery:request:' || v_req loop
        select * into i from public.it_incident where handoff_id = x.id;
        if i.id is not null and coalesce(btrim(i.cause), '') = '' then
          r := public.fn_it_attach_learning(x.id,
            'The delivery duty raised a founder-bound request that customer_support holds for the 19:00 Dubai IT digest (evidence.digest = pending) as having no outcome after 2 h; it did not know the digest''s schedule. Measured 22 Sep 2026.',
            'every_handoff_is_answered_within_its_window.sql: the delivery duty skips such a request until fn_it_digest_hold_ends(created_at).',
            'scripts/checks/every_handoff_is_answered_within_its_window.test.mjs',
            null, 'A duty that misreads a schedule is corrected in code, through a pull request.',
            'ceo (every_parked_it_handoff_of_22_september_is_closed_by_its_exact_id.sql, 22 Sep 2026)');
          update public.support_ceo_report
             set status = 'completed', completed_at = now(), completion_note = 'IT engineer re-verified: handoff ' || x.id || ' closed with its learning recorded.'
           where idempotency_key = 'it_loop:' || x.id and status = 'accepted';
          insert into _qd_resolution values ('delivery-finding handoff ' || x.id, 'LEARNING RECORDED', r);
        else
          insert into _qd_resolution values ('delivery-finding handoff ' || x.id, 'LEFT FOR fn_it_loop_reverify (no incident to fill)', null);
        end if;
      end loop;
    exception when others then
      insert into _qd_resolution values ('duty:delivery:request:' || v_req, 'ERROR: ' || left(sqlerrm, 300), null);
    end;
  end loop;
end
$res2$;

-- ── 3. VERDICT ──────────────────────────────────────────────────────────────────────────────────
select subject, outcome, evidence from _qd_resolution
union all
select 'VERDICT',
       case when count(*) filter (where outcome like 'SKIPPED%' or outcome like 'ERROR%' or outcome like 'LEARNING RECORDED, NOT%') = 0
                 and count(*) filter (where subject like 'handoff %') = 29
            then 'PROBE OK' else 'PROBE FAILED' end,
       jsonb_build_object('rows', count(*), 'closed', count(*) filter (where outcome = 'CLOSED'),
                          'already_closed', count(*) filter (where outcome = 'ALREADY CLOSED'))
  from _qd_resolution;
