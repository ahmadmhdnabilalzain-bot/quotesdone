-- THE IT LEARNING GATE CLOSES WHAT THE PLAYBOOK ALREADY KNOWS, AND STILL REFUSES WHAT NOBODY HAS.
--
-- Assigned: it_engineer. 18 Sep 2026.
--
-- WHAT WAS MEASURED, against htdblwldjkcgjvmqkbeh on 18 Sep 2026 04:06 UTC, read-only:
--   public.it_incident                        110 rows; 110 with no cause, no fix, no regression check
--                                             and no playbook class. ZERO have ever been completed.
--   it.finding handoffs open                  144; 91 parked at awaiting_learning; the oldest 84 h
--                                             against a 4 h reply window.
--   support_ceo_report (source it_engineer)   112 accepted and never completed, every one past its
--                                             next_review_at; 110 of them are 'it_loop:%' -- one per
--                                             incident -- and complete only when that loop closes.
--   open findings by class                    journey 24, heartbeat 11, db_health 10, smoke 4; none
--                                             of those four classes had an it_playbook row.
--
-- THE SHAPE. fn_it_loop_reverify refuses to close a handoff whose incident lacks a cause, a fix, a
-- regression check and a playbook class (duty 17, trigger z62 -- correctly: a new bug that teaches
-- nothing is a bug that comes back). Only fn_it_attach_learning can supply those, and it is called by
-- a Claude session -- by no routine. Nothing in the running company could ever close the loop, so the
-- detector worked, the seats replied, fixes landed, and 110 records sat empty behind a gate with no
-- deterministic key. The estate's "finished capability with no entry point".
--
-- WHAT THIS CHANGES.
--   1. public.it_playbook gains typical_cause: the cause statement for the failure class, written
--      from what those failures have actually been. A row WITHOUT one cannot close anything.
--   2. fn_it_learning_from_playbook fills an incomplete incident from the playbook row whose
--      issue_prefix covers its issue key -- cause from typical_cause, fix from the remedy (or the
--      reason it cannot be automated), regression_check and playbook_class from the same row. Every
--      value is read out of it_playbook; nothing is invented, and anything a human already wrote is
--      left alone (coalesce, never overwrite).
--   3. fn_it_loop_reverify calls it once, on a cleared finding, before parking the handoff at
--      awaiting_learning. A class the playbook knows closes. A class it does not still waits for a
--      human, which is the point: THE BAR IS NOT LOWERED, the key is cut for the locks we own.
--   4. fn_it_loop_reverify's "incomplete" test now includes `fix`, which it omitted while trigger z62
--      demanded it. An incident with a cause, a check and a class but no fix would have been sent to
--      the close path, where z62 raises -- and that exception aborts the whole reverify loop, not one
--      handoff. No such row exists today (all 110 are empty on every field), so this changes no
--      number; it removes a way for one half-recorded incident to stop every other loop closing.
--   5. fn_it_ceo_silence_watch polices at the reply window, not at whatever review interval the
--      raising routine chose. MEASURED: 11 it_engineer reports sat 'sent' and unanswered for up to
--      87 h and only 2 had tripped next_review_at, because every one of them was raised with the
--      24 h default while the seats answering the same engineer are held to 4 h.
--
-- WHY THE SWEEP IS NOT ALSO CHANGED, said rather than left to be discovered. None of those 11 is an
-- 'it_loop:%' escalation: they are dropbox_backup_escalation (2) and delivery_undelivered (9), raised
-- by other builds' routines, and fn_ceo_it_reports_sweep has no branch that decides them. The tempting
-- fix -- give the sweep a catch-all that accepts them -- would turn eleven unanswered problems into
-- eleven closed ones without anybody deciding anything, which is the gate being lowered in the one
-- place this file exists to keep raised. They are escalated to the founder by the clock above instead.
--
-- WHAT THIS DOES NOT DO. It adds seven playbook classes and one cause backfill, all evidenced below.
-- It does NOT write a playbook for queue_stalled (3 parked handoffs), access (2), restore_table (2),
-- table_export (1), run_silent (1), credential (1) or delivery (1). Those eleven stay parked, which is
-- correct: nobody has yet decided what their cause is. restore_table is the clearest example -- it HAS
-- a playbook row, and that row's reason ("nothing in the repository has written a table export since
-- 7 Sep 2026") has been overtaken by the export work of 15-18 Sep, so writing a cause from it today
-- would record something no longer true. A class whose cause is unknown is exactly what the gate is
-- for; a class whose cause is stale is why it must not be guessed.
--
-- TWO THINGS THE REVIEWS RAISED THAT THIS FILE DELIBERATELY LEAVES ALONE, so they are not lost:
--   * fn_it_playbook_first (every_new_bug_leaves_a_playbook_entry_a_check_and_an_incident_record.sql)
--     matches its prefix with LIKE and has the same underscore-is-a-wildcard trap fixed here. It is
--     not redefined here -- a routine has one owning file, and this is not it. Its consequence is also
--     smaller: a near-miss there RUNS a remedy routine, it does not write an incident record.
--   * fn_it_ceo_silence_watch tells the founder at most once per report, ever, because its guard tests
--     that a delivery.request ROW EXISTS, not that anything was delivered -- a failed first attempt
--     leaves nothing watching. That is unchanged from the original and is the delivery loop's subject;
--     this file only tightened WHEN the watch fires.
--
-- MEASURED IN A ROLLED-BACK TRANSACTION AGAINST PRODUCTION, 18 Sep 2026, with this file applied:
--   parked at awaiting_learning   91 -> 11        incidents complete             0 -> 80
--   open it.finding handoffs     147 -> 57        incidents still incomplete   110 -> 30
--   CEO reports accepted-and-incomplete         112 -> 32   (84 completed, 4 of them already were)
--   fn_it_loop_reverify returned closed 90, learned_from_playbook 80, waiting 57, escalated 0.
--   fn_it_ceo_silence_watch told the founder about 1 unanswered report -- not 12: the other eleven
--   are either inside the 4 h window or already carry a delivery.request, so the tighter clock does
--   not become an alert storm.
--   The 11 that stay parked are exactly the seven classes named above; 19 of the 30 incidents still
--   incomplete belong to handoffs whose finding is still OPEN, so they are not waiting on learning at
--   all. Nothing was committed.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_learning_gate_closes_what_the_playbook_already_knows.sql --apply --ddl

-- ── 1. THE PLAYBOOK LEARNS TO STATE A CAUSE ──────────────────────────────────────────────────────
alter table public.it_playbook add column if not exists typical_cause text;
comment on column public.it_playbook.typical_cause is
  'What this failure class has actually been caused by, in one statement, written from measured occurrences. A row with no typical_cause can never complete an incident on its own: an unexplained class still waits for a human (fn_it_learning_from_playbook).';

-- ── 2. THE SEVEN CLASSES THAT ARE RE-FIRING, EACH WITH THE MEASUREMENT BEHIND ITS CAUSE ──────────
-- Every typical_cause below is quoted from a measurement already written down in this repository --
-- the file or the merged pull request is named in the comment above each row. None is inferred from
-- the class name.
insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values

  -- 24 open findings on 18 Sep. Two distinct measured causes, both of them the RUN rather than the
  -- product: (a) the customer overview's six reads were queued behind 1.35 MB of client JS because
  -- warmDashboard ran inside a React effect -- fn_customer_stats answers in 8 ms and the six authed
  -- calls take 876-923 ms wall, while the shell alone took 2,129-3,142 ms (PR #731, BootPrefetch.tsx
  -- moves them to HTML parse); (b) the crawl steps timed out at 8,000 ms with no navigation offered,
  -- on runs GitHub cancelled at its 30-minute ceiling mid-crawl (PR #728).
  ('journey', 'duty:journey:',
   'The seat named on the step owns it; the step is re-asserted by the next nightly run and the finding closes when it passes. A step that failed only because the run was cancelled carries run_complete=false and settles nothing.',
   null, null,
   '.github/workflows/nightly-journey.yml, with scripts/sql/a_truncated_journey_run_reports_but_settles_nothing.sql so a cancelled run cannot report a pass',
   'A step of the nightly full-journey run failed against production. Measured 15-18 Sep 2026: the overview steps failed because the six portal reads were issued from a React effect and so queued behind the whole client bundle (the reads themselves answer in 8 ms); the crawl steps failed on runs GitHub cancelled at its 30-minute maximum mid-crawl, which also left their demo fixtures behind. The step''s own evidence names which.',
   'it_engineer'),

  -- 11 open on 18 Sep, every one a resilience_ping step: 'canceling statement due to statement
  -- timeout' or 'not run: the tick passed its 110s deadline'. duty:heartbeat:itscheduled was raised
  -- 215 times between 15 Sep 19:02Z and 17 Sep 23:46Z by ONE plan-time error -- a table alias named d
  -- shadowing the PL/pgSQL record d in fn_it_duties_scheduled, so the routine never ran once (PR #727).
  ('heartbeat_step', 'duty:heartbeat:',
   'The step''s own error names the fault: a plan-time error is a code fix in the routine the step calls, a statement timeout or a passed deadline is work that no longer fits the tick and is split or bounded. The next tick closes the finding.',
   null, null, 'scripts/checks/resilience_ping_reports_every_tick.test.mjs',
   'A resilience_ping step failed. Measured 15-18 Sep 2026: an ambiguous column reference inside fn_it_duties_scheduled stopped the itscheduled step at plan time on every one of 215 sightings, and the remaining steps failed on the tick''s own statement timeout or its 110 s deadline -- work that outgrew the tick, not a fault in the thing being measured.',
   'it_engineer'),

  -- 10 open on 18 Sep, all of them arithmetically correct and about nothing that is happening.
  ('slow_statement', 'duty:db_health:slow:',
   'The duty now measures the mean over the interval between two public.it_query_stat_snapshot rows, so a statement that did not run in the interval has a zero denominator and cannot be raised at all; neither threshold was moved. A statement still raised after that is a real one and its cost, or the work calling it, is what changes.',
   null, null,
   'scripts/sql/the_slow_query_duty_measures_the_last_interval_not_the_lifetime_average.sql -- its probe: with a snapshot taken at the same instant the interval rule raises 0 where the lifetime rule raises 10, and with the snapshot rolled back by one statement''s own history it raises that statement again',
   'The duty read pg_stat_statements.mean_exec_time, which is total_exec_time/calls SINCE THE LAST RESET -- and the last reset was 6 Jun 2026. It answered "what is the slowest statement ever recorded here", never "is the database slow now". Measured 18 Sep 2026: all ten findings raised on 14 Sep had the SAME calls and the SAME mean four days later, none had run since, and eight carried the management API''s own marker -- introspection queries typed in past sessions, one of them calling a routine retired with the kernel boards.',
   'it_engineer'),

  -- 4 open and 9 parked on 18 Sep, every one "[a customer] overview data under 2.5 s", on all four
  -- locales, attributed to merge a5cdc79 -- which is the merge that happened to run the smoke, not
  -- the change that made it slow. Same cause as the journey overview steps.
  ('smoke_after_merge', 'duty:smoke:',
   'The seat owning most of the merge''s changed files answers it; the next post-deploy smoke re-runs the step and the finding closes when it passes. The merge named in a smoke finding is the one that RAN the test, which is not evidence that it caused the failure.',
   null, null, '.github/workflows/it-post-deploy-smoke.yml',
   'A step of the post-deploy smoke run failed after a merge. Measured 15-18 Sep 2026: every open smoke finding was the customer overview''s data budget on all four locales, failing since it began recording, and the cause was the load order rather than any merge -- the six reads were issued from a React effect and so followed 1.35 MB of client JS instead of overlapping it.',
   'it_engineer'),

  -- 4 parked on 18 Sep: duty:demo:leads (6 rows) and duty:demo:customers (2 rows), on tags 8a5b7ad5
  -- and 414bbb3e -- the two nightly runs GitHub cancelled at 30 minutes (PR #728).
  ('demo_fixture_outlived_run', 'duty:demo:',
   'The rows are the harness''s own ZZ DEMO fixtures, left behind because the run that created them was killed before its cleanup. The ceo closes the rehearsal window and the next completed run''s cleanup removes them; a run that reports a pass without completing cannot settle anything.',
   null, null,
   '.github/workflows/nightly-journey.yml, with scripts/sql/a_truncated_journey_run_reports_but_settles_nothing.sql',
   'Demo rows outlived their run because the run was cancelled, not because anything failed to clean up. Measured 18 Sep 2026: both open occurrences carry the run tags of the two nightly journeys GitHub cancelled at its 30-minute maximum (runs 35037401883 and 35164572430); a cancelled job skips every remaining step, so the harness''s own finally block never executed.',
   'it_engineer'),

  -- 51 parked on 18 Sep -- more than half the whole backlog, and one duty's worth of over-raising.
  -- Measured 15 Sep (PR #716): the duty raised EVERY registry row with backed_up = false, the
  -- reasoned exemptions included, and 4 more were simply stale. 18 of the 51 were real gaps.
  ('backup_gap', 'duty:backup_gap:',
   'dropbox_backup''s fn_enqueue_doc_backups queues the file for the off-site copy -- registry sources by their owner rule, anything else through the storage sweep, at most 200 per call, oldest first and idempotent on (bucket, path). The daily duty closes the finding once a verified doc_backups row exists.',
   null, null,
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs, with the storage sweep of scripts/sql/every_stored_file_reaches_dropbox_and_the_backup_gap_duty_raises_only_real_gaps.sql',
   'A registry source or a swept storage object has no verified Dropbox copy. Measured 15 Sep 2026: of the 51 findings then open, only 18 were real gaps -- the duty raised every registry row with backed_up = false, the reasoned exemptions included (doc_backups.dropbox_path, the PDPL erasure ledger, repository paths of the knowledge tables), and four more were stale rows the daily duty had not re-run. The duty now raises only an unexempted registry source or a swept file over 24 hours old with no doc_backups row, so an occurrence after 15 Sep 2026 is a real missing copy.',
   'it_engineer'),

  -- 10 parked on 18 Sep, every one a Stripe TEST object from the nightly payment journey.
  ('payment_unreconciled', 'duty:payment:',
   'A LIVE object with no transaction is the accountant''s to book. A TEST object whose payer is a reserved demo address is the harness''s own and is dropped from reconciliation by it_duty_readings.ts splitRehearsals, and recorded under stripe.test.rehearsal; fn_it_duty_settle closes any duty:payment key absent from the next run.',
   null, null, 'supabase/functions/_shared/stripe_rehearsal.test.ts',
   'A Stripe object had no transaction in our books. Measured 15 Sep 2026: all eight findings then open were TEST mode, and a read-only lookup of every object in Stripe found each payer email on @example.invalid -- the e2e harness teardown deletes the demo transaction while the Stripe TEST object stays. The rule that drops them is narrow on purpose: TEST mode AND a reserved demo payer address, with the key''s own sk_test_/rk_test_ prefix required before the test bucket counts as test at all. A LIVE object, or a test object with any other payer, still raises and is still a real gap.',
   'it_engineer')

on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix, remedy = excluded.remedy,
  remedy_routine = excluded.remedy_routine, not_automatable_reason = excluded.not_automatable_reason,
  regression_check = excluded.regression_check, typical_cause = excluded.typical_cause;

-- One backfill, on the one existing class with a parked handoff whose cause the finding itself states
-- ("quotesdone.com is listed on multi.uribl.com"). The other existing classes keep a null
-- typical_cause on purpose: their remedy is written down and their cause is not, and guessing one to
-- unlock a close is exactly the failure this file is built to prevent.
update public.it_playbook
   set typical_cause = 'A domain or an address we send from appeared on a public blocklist. Measured 18 Sep 2026: quotesdone.com listed on multi.uribl.com. A refusal by a list''s own server is NOT a listing and is not this class (scripts/sql/a_blocklist_refusal_is_never_a_listing.sql).'
 where failure_class = 'sender_blocklist' and coalesce(btrim(typical_cause), '') = '';

-- ── 3. THE LOOKUP, AND THE FILL ──────────────────────────────────────────────────────────────────
-- The longest matching prefix wins, as in fn_it_playbook_first, so a specific class beats a general
-- one -- and the typical_cause test is applied to THAT WINNER, not used to filter before it. Filtering
-- first would let a key fall through to a broader class and be closed with the wrong cause:
-- 'duty:demo:window:…' is stale_rehearsal_window, which has no cause written, and must wait for a
-- human rather than borrow demo_fixture_outlived_run's.
-- The match is left(), not LIKE. Review finding, 18 Sep 2026: an issue_prefix is a literal, and two
-- of them contain an underscore ('duty:db_health:slow:', 'duty:usage_'), which LIKE reads as "any one
-- character". Under LIKE a near-miss key would match, and here a match writes a cause and a fix into
-- an incident and closes the loop -- a wrong-but-plausible record, which is worse than no record.
-- The tiebreaker on failure_class is there because nothing stops two prefixes being the same length.
create or replace function public.fn_it_playbook_for(p_issue_key text)
returns public.it_playbook language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select p.* from (
    select b.* from public.it_playbook b
     where left(p_issue_key, length(b.issue_prefix)) = b.issue_prefix
     order by length(b.issue_prefix) desc, b.failure_class limit 1) p
   where coalesce(btrim(p.typical_cause), '') <> '';
$fn$;
revoke execute on function public.fn_it_playbook_for(text) from public, anon, authenticated;

-- Fills an incident from the playbook row covering its issue key. Returns the failure class it used,
-- or null when no row covers it -- and null is the gate staying shut, not an error. Never overwrites
-- a value a session already recorded.
create or replace function public.fn_it_learning_from_playbook(p_handoff_id bigint)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.it_playbook; v_key text; i public.it_incident;
begin
  -- A handoff id that is not an it.finding handoff is a caller's mistake, not a refusal, and is said
  -- so out loud: fn_it_loop_reverify only ever passes ids from its own filtered query, so this cannot
  -- fire from the loop. null is reserved for the two REFUSALS below -- no incident, no playbook class.
  select h.detail->>'issue_key' into v_key from public.agent_actions h
   where h.id = p_handoff_id and h.kind = 'handoff' and h.detail->>'type' = 'it.finding';
  if v_key is null then
    raise exception 'fn_it_learning_from_playbook: % is not an open it.finding handoff', p_handoff_id;
  end if;

  p := public.fn_it_playbook_for(v_key);
  if p.failure_class is null then return null; end if;

  update public.it_incident
     set cause                  = coalesce(nullif(btrim(cause), ''), p.typical_cause),
         fix                    = coalesce(nullif(btrim(fix), ''), nullif(btrim(p.remedy), ''), p.not_automatable_reason),
         regression_check       = coalesce(nullif(btrim(regression_check), ''), p.regression_check),
         playbook_class         = coalesce(playbook_class, p.failure_class),
         not_automatable_reason = coalesce(not_automatable_reason, p.not_automatable_reason),
         recorded_by            = coalesce(recorded_by, 'it_engineer (playbook: ' || p.failure_class || ')'),
         updated_at             = now()
   where handoff_id = p_handoff_id
  returning * into i;
  -- No incident row -- the handoff never became a new bug. Nothing to learn, and nothing is wrong.
  -- Tested on FOUND rather than on a separate exists() before the update: two statements with no lock
  -- between them can disagree, and the record `i` would then be all-NULL and read as "incomplete".
  if not found then return null; end if;

  -- it_playbook.regression_check is NOT NULL and a CHECK constraint makes remedy-or-reason non-empty,
  -- so a matched row always leaves a complete incident. If a later migration ever weakens that, this
  -- must NOT raise: fn_it_loop_reverify runs it inside a `for` loop with no per-row trap, so one
  -- poisoned incident would stop every OTHER handoff in the tick from closing or escalating -- and,
  -- ordered by id, would do it again on every tick after. It warns, returns null, and the handoff
  -- stays parked for a human, which is the same answer as an unknown class.
  if coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = '' or coalesce(btrim(i.regression_check), '') = '' then
    raise warning 'fn_it_learning_from_playbook: playbook % left incident % incomplete; leaving it parked', p.failure_class, i.id;
    return null;
  end if;
  return p.failure_class;
end $fn$;
revoke execute on function public.fn_it_learning_from_playbook(bigint) from public, anon, authenticated;

-- ── 4. RE-VERIFY: TRY THE PLAYBOOK FIRST, THEN PARK WHAT IT DOES NOT KNOW ─────────────────────────
-- Unchanged from the_it_engineer_closes_every_loop_it_opens.sql except for the cleared branch: the
-- playbook fill runs before the completeness test, and the test now includes `fix` so it agrees with
-- trigger z62 about what a complete incident is.
create or replace function public.fn_it_loop_reverify()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; f public.it_engineer_finding; v_window interval; v_rep jsonb; v_cleared boolean;
  n_closed int := 0; n_esc int := 0; n_wait int := 0; n_playbook int := 0; v_class text;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  -- Review finding, 18 Sep 2026: with no such row v_window is null, `now() > created_at + null` is
  -- null, and EVERY handoff fell quietly into 'waiting' -- the loop would never escalate again and
  -- would say nothing about why. A missing conversation row is a configuration fault, not a default.
  if v_window is null then
    raise exception 'fn_it_loop_reverify: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    -- The occurrence this loop tracked is over when the finding is closed, or when it has since
    -- closed and reopened (a later started_at is a different occurrence with its own loop).
    v_cleared := f.issue_key is null or f.closed_at is not null
                 or f.started_at > (h.detail->>'occurrence_started_at')::timestamptz;

    if v_cleared then
      -- A new bug that has cleared needs what was learned (trigger z62). Where the playbook already
      -- covers this failure class, the IT engineer records it from there and closes now; where it
      -- does not, the handoff waits for a human, which is what the gate is for.
      v_class := public.fn_it_learning_from_playbook(h.id);
      if v_class is not null then n_playbook := n_playbook + 1; end if;
    end if;

    if v_cleared and exists (select 1 from public.it_incident i where i.handoff_id = h.id
                              and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = ''
                                   or coalesce(btrim(i.regression_check), '') = ''
                                   or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = ''))) then
      if not (h.detail ? 'awaiting_learning') then
        update public.agent_actions set detail = detail || jsonb_build_object('awaiting_learning', now()) where id = h.id;
        update public.it_incident set ended_at = coalesce(f.closed_at, now()), updated_at = now() where handoff_id = h.id and ended_at is null;
      end if;
      n_wait := n_wait + 1;
    elsif v_cleared then
      update public.it_incident set ended_at = coalesce(ended_at, f.closed_at, now()), updated_at = now() where handoff_id = h.id;
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', coalesce(f.close_note, 'the finding is no longer open'),
        'learning_from_playbook', v_class,
        'reply_before_close', h.detail ? 'replied_at'));
      perform set_config('qd.handoff_closer', '', true);
      update public.support_ceo_report
         set status = 'completed', completed_at = now(),
             completion_note = 'IT engineer re-verified: ' || coalesce(f.close_note, 'the finding is no longer open') || ' (handoff ' || h.id || ').'
       where idempotency_key = 'it_loop:' || h.id and status = 'accepted';
      n_closed := n_closed + 1;
    elsif not (h.detail ? 'escalated_report_id') and now() > h.created_at + v_window then
      v_rep := public.fn_support_report_to_ceo(
        'it_loop:' || h.id,
        case when h.detail->>'severity' = 'critical' then 'critical' else 'serious' end,
        'Still broken after ' || h.agent || '''s reply window: ' || left(coalesce(h.detail->>'title', h.detail->>'issue_key'), 160),
        jsonb_build_object('handoff_id', h.id, 'issue_key', h.detail->>'issue_key', 'seat', h.agent,
                           'reply', h.evidence, 'finding', to_jsonb(f)),
        jsonb_build_array(jsonb_build_object('action', 'handed to ' || h.agent, 'handoff_id', h.id,
                                             'at', h.created_at, 'replied_at', h.detail->>'replied_at')),
        'Decide the remedy, or record that this is a new bug for the founder. The IT engineer keeps re-checking and closes the loop only when the finding is gone.',
        p_review_in => interval '2 hours', p_source_agent => 'it_engineer');
      if not coalesce((v_rep->>'ok')::boolean, false) then
        raise exception 'fn_it_loop_reverify: the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
      end if;
      update public.agent_actions
         set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
       where id = h.id;
      perform public.fn_ceo_it_escalation_decide((v_rep->>'report_id')::bigint);
      n_esc := n_esc + 1;
    else
      n_wait := n_wait + 1;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'escalated', n_esc, 'waiting', n_wait, 'learned_from_playbook', n_playbook);
end $fn$;
revoke execute on function public.fn_it_loop_reverify() from public, anon, authenticated;

-- ── 5. THE CEO IS POLICED AT THE WINDOW IT HOLDS EVERY OTHER SEAT TO ─────────────────────────────
-- Unchanged from the_it_engineer_closes_every_loop_it_opens.sql except for the due test. A report is
-- overdue at its own next_review_at OR at the it.finding reply window, whichever comes first: the
-- raising routine chooses next_review_at for its own subject, and on 18 Sep every one of the eleven
-- unanswered reports carried the 24 h default while the seats answering the same engineer have 4 h.
create or replace function public.fn_it_ceo_silence_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; n_told int := 0; v_window interval;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  -- Same fault, same answer as fn_it_loop_reverify above: a hardcoded 4 h fallback here would keep
  -- policing to a number nobody can see, after the row that is supposed to hold it had gone.
  if v_window is null then
    raise exception 'fn_it_ceo_silence_watch: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  for r in select * from public.support_ceo_report
            where source_agent = 'it_engineer' and status = 'sent'
              and least(next_review_at, created_at + v_window) < now()
              and not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.target_id = 'delivery.request:' || support_ceo_report.id)
            order by id loop
    perform public.fn_seat_handoff('it_engineer', 'customer_support', 'delivery.request', 'support_ceo_report', r.id::text,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
        'event', 'The CEO has not answered an IT report: ' || left(r.subject, 120),
        'detail', 'The IT engineer reported this to the CEO at '
                  || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai) and it was due an answer by '
                  || to_char(least(r.next_review_at, r.created_at + v_window) at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || E'. Nobody has answered.\n\n'
                  || 'Report: ' || r.subject || E'\n\nIt stays open until the CEO answers it. Reference: support_ceo_report ' || r.id || '.',
        'dedupe_key', 'it_ceo_silent:' || r.id));
    n_told := n_told + 1;
  end loop;
  return jsonb_build_object('founder_told', n_told);
end $fn$;
revoke execute on function public.fn_it_ceo_silence_watch() from public, anon, authenticated;

-- ── 6. PROBE ─────────────────────────────────────────────────────────────────────────────────────
-- This file defines routines, so the probe must NOT raise: a raise here would roll the definitions
-- back and the apply would report success over nothing. It is READ-ONLY -- it writes no row at all,
-- so it is incapable of reaching a real person rather than merely careful to clean up after itself.
-- The write path (a parked handoff closing, and one with no playbook entry refusing to) is proved
-- against production in a rolled-back transaction by scripts/checks/it_engineer_loop_is_closed.test.mjs.
do $probe$
declare
  v_known text; v_unknown text; v_narrow text; v_bad int; v_would int; v_parked int;
begin
  v_known   := (public.fn_it_playbook_for('duty:heartbeat:ZZ DEMO probe step')).failure_class;
  v_unknown := (public.fn_it_playbook_for('duty:zz_demo_no_such_class:ZZ DEMO')).failure_class;
  -- The more specific class has no cause written, so this key must NOT borrow the broader one's.
  v_narrow  := (public.fn_it_playbook_for('duty:demo:window:ZZ DEMO')).failure_class;
  if v_known is distinct from 'heartbeat_step' then
    raise exception 'the playbook does not cover duty:heartbeat: (got %)', coalesce(v_known, 'no match');
  end if;
  if v_unknown is not null then
    raise exception 'the gate opened for an unknown class: %', v_unknown;
  end if;
  if v_narrow is not null then
    raise exception 'duty:demo:window: fell through to the broader class %', v_narrow;
  end if;

  -- Every row that can complete an incident must carry everything an incident needs.
  select count(*) into v_bad from public.it_playbook
   where coalesce(btrim(typical_cause), '') <> ''
     and (coalesce(btrim(regression_check), '') = ''
          or (coalesce(btrim(remedy), '') = '' and coalesce(btrim(not_automatable_reason), '') = ''));
  if v_bad > 0 then
    raise exception '% playbook row(s) can complete an incident but do not carry a regression check and a remedy', v_bad;
  end if;

  select count(*) filter (where true),
         count(*) filter (where (public.fn_it_playbook_for(a.detail->>'issue_key')).failure_class is not null)
    into v_parked, v_would
    from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding'
     and a.status in ('pending', 'failed') and a.detail ? 'awaiting_learning';

  raise notice 'IT learning gate: % of % parked handoff(s) are now covered by a playbook class; % wait for a human.',
    v_would, v_parked, v_parked - v_would;
end
$probe$;
