-- THE TWELVE OPEN IT FINDINGS THAT WERE ALREADY FIXED CLOSE, EACH WITH THE MEASUREMENT THAT SAYS SO.
--
-- Assigned: it_engineer. 21 Sep 2026. Data only: no routine, table or grant changes.
--
-- ══ MEASURED, 21 Sep 2026 15:43 UTC, htdblwldjkcgjvmqkbeh (read-only) ══════════════════════════
-- public.it_engineer_finding held 40 rows with closed_at null. Twelve of them describe a cause that
-- is no longer present; nothing would close them before the producer next runs (tomorrow for the
-- daily duties, never for the browser_journey keys, which no duty settles):
--   A. 4 x duty:dependency:app:{next,postcss,sharp,nanoid} raised 10:06Z. `npm audit
--      --package-lock-only` on main a3cee88 (#776: next 16.3.5, postcss 8.5.28, sharp 0.35.4,
--      nanoid 3.3.19): info 0, low 0, moderate 0, high 0, critical 0.
--   B. 4 x duty:db_health:slow:<queryid> whose statement text carries the management API stamp
--      "-- source: POST /v1/projects/:ref/database/query" (fn_kb_embed_dispatch 82.7 s x 18,
--      kb_chunks counts 28.7 s / 29.6 s, fn_kb_embed_harvest 3.2 s x 19) — an operator's session,
--      not the product. They got through because the only db_health run since (01:46:10Z) predates
--      #767 (merged 14:12Z): that run's output has no db_health_operator_statements_excluded key.
--      The live fn_it_duties_scheduled now carries the exclusion. No detector change is needed.
--   C. 4 x browser_journey:* from the 18 Sep crawl, all fixed on main:
--      rating 500 — live reviews_reason_required is CHECK (comment IS NULL OR length(btrim(comment))
--        >= 10), validated (#761); dates forced LTR (#761, src/lib/Ltr.tsx); reveal node grey on a
--        revealed request (Journey lights its last node from `revealed`); empty-state flash after the
--        first post (`booting || posting` skeleton).
--
-- ══ WHAT THIS FILE DOES ═══════════════════════════════════════════════════════════════════════
-- Closes each through the seat's own close path, public.fn_it_engineer_finding_close(key, note) —
-- the routine fn_it_duty_settle and fn_it_engineer_ingest_watch_findings use — with the
-- measurement as close_note. Where the fact is readable in SQL the close is GUARDED by re-reading it
-- (B: the stamp is in the finding's own evidence AND the live duty excludes stamped statements; C1:
-- the live constraint admits a null comment). A guard that no longer holds leaves the row open and
-- the probe FAILS. fn_it_engineer_alert_tick sends a RESOLVED note only for rows he was emailed about.
--
-- RECURRENCE: fn_it_engineer_finding_upsert REOPENS a closed key the moment its producer sees it
-- again (and flags it as a recurrence). Per class the check that fails if the cause returns:
--   A. duty:dependency (daily npm audit on the lockfile).
--   B. scripts/sql/the_slow_statement_duty_does_not_page_about_an_operators_session.sql probe.
--   C. scripts/checks/ltr_is_never_forced_onto_a_localised_date.test.mjs,
--      supabase/functions/customer_api/rating_input.test.ts,
--      scripts/checks/the_customer_portal_defects_of_the_18_september_journey_stay_fixed.test.mjs.
--
-- NOT CHANGED: the other 28 open rows (real defects, configuration gaps and founder decisions).
--
--   node scripts/apply_sql.mjs scripts/sql/the_twelve_open_it_findings_that_were_already_fixed_close_with_their_measurement.sql --apply

-- ── A. dependency advisories fixed by #776 ──
select public.fn_it_engineer_finding_close(k,
  'Fixed by #776 (next 16.3.5, postcss 8.5.28, sharp 0.35.4, nanoid 3.3.19). Measured 21 Sep 2026 15:50Z: '
  || 'npm audit --package-lock-only on main a3cee88 = 0 advisories at every severity. '
  || 'The daily dependency duty reopens this key if the advisory returns.')
  from unnest(array['duty:dependency:app:next:1193676', 'duty:dependency:app:postcss:1117015',
                    'duty:dependency:app:sharp:1124066', 'duty:dependency:app:nanoid:1139427']) k
 where exists (select 1 from public.it_engineer_finding f where f.issue_key = k and f.closed_at is null);

-- ── B. operator-session statements the 01:46Z db_health run raised before #767's exclusion ──
select public.fn_it_engineer_finding_close(f.issue_key,
  'Operator session, not the product: the statement text carries the management API stamp '
  || '(/v1/projects/:ref/database/query). Raised by the 21 Sep 01:46Z db_health run, which predates the '
  || 'exclusion shipped in #767 (merged 14:12Z); the live duty now leaves stamped statements out and '
  || 'publishes the count as db_health_operator_statements_excluded.')
  from public.it_engineer_finding f
 where f.closed_at is null
   and f.issue_key in ('duty:db_health:slow:-3555723878668831129', 'duty:db_health:slow:-5243621260964040806',
                       'duty:db_health:slow:1515201696749337055', 'duty:db_health:slow:5606240269240456555')
   and coalesce(f.evidence->>'query', '') like '%/v1/projects/:ref/database/query%'
   and pg_get_functiondef('public.fn_it_duties_scheduled(jsonb)'::regprocedure) like '%where not s.operator_session%';

-- ── C. the 18 Sep browser-journey defects, fixed on main ──
select public.fn_it_engineer_finding_close('browser_journey:no_customer_can_rate_a_supplier_the_stars_always_answer_500',
  'Fixed by #761: live reviews_reason_required = CHECK (comment IS NULL OR length(btrim(comment)) >= 10), validated; '
  || 'customer_api rate_supplier parses input in rating_input.ts (tested) and answers 4xx, not 500, on a refusal.')
 where exists (select 1 from pg_constraint c where c.conrelid = 'public.reviews'::regclass
                 and c.conname = 'reviews_reason_required' and c.convalidated
                 and pg_get_constraintdef(c.oid) ilike '%comment IS NULL%')
   and exists (select 1 from public.it_engineer_finding f
                where f.issue_key = 'browser_journey:no_customer_can_rate_a_supplier_the_stars_always_answer_500' and f.closed_at is null);

select public.fn_it_engineer_finding_close(k, n)
  from (values
    ('browser_journey:arabic_dates_are_forced_left_to_right_in_the_supplier_portal',
     'Fixed by #761: one Ltr (src/lib/Ltr.tsx) decides direction per string, so an Arabic date is no longer forced LTR. '
     || 'Guarded by scripts/checks/ltr_is_never_forced_onto_a_localised_date.test.mjs (3/3 pass on main a3cee88).'),
    ('browser_journey:a_revealed_request_still_shows_reveal_as_not_reached',
     'Fixed on main: CustomerPortal Journey lights its last node from `revealed` (not from rfqStageIdx, which means hired). '
     || 'Guarded by scripts/checks/the_customer_portal_defects_of_the_18_september_journey_stay_fixed.test.mjs.'),
    ('browser_journey:the_first_request_flashes_the_you_have_none_empty_state_after_it_is_sent',
     'Fixed on main: the request-list skeleton is gated on `booting || posting`, and posting clears in the refresh''s .finally. '
     || 'Guarded by scripts/checks/the_customer_portal_defects_of_the_18_september_journey_stay_fixed.test.mjs.')
  ) v(k, n)
 where exists (select 1 from public.it_engineer_finding f where f.issue_key = v.k and f.closed_at is null);

-- ── PROBE ──
select case when n_closed = 12 then 'PROBE OK: 12 already-fixed IT findings closed with their measurement; '
            else 'PROBE FAILED: ' end
       || n_closed || ' of 12 closed, ' || n_open_other || ' other findings still open' as verdict
  from (select count(*) filter (where closed_at is not null) n_closed from public.it_engineer_finding
         where issue_key in ('duty:dependency:app:next:1193676', 'duty:dependency:app:postcss:1117015',
                             'duty:dependency:app:sharp:1124066', 'duty:dependency:app:nanoid:1139427',
                             'duty:db_health:slow:-3555723878668831129', 'duty:db_health:slow:-5243621260964040806',
                             'duty:db_health:slow:1515201696749337055', 'duty:db_health:slow:5606240269240456555',
                             'browser_journey:no_customer_can_rate_a_supplier_the_stars_always_answer_500',
                             'browser_journey:arabic_dates_are_forced_left_to_right_in_the_supplier_portal',
                             'browser_journey:a_revealed_request_still_shows_reveal_as_not_reached',
                             'browser_journey:the_first_request_flashes_the_you_have_none_empty_state_after_it_is_sent')) a,
       (select count(*) n_open_other from public.it_engineer_finding where closed_at is null) b;
