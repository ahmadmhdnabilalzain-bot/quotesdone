-- ---------------------------------------------------------------------------------------------
-- THE MARKETPLACE FUNNEL WAS 100% FIXTURE DATA.
--
-- Founder instruction, 16 Aug 2026: "delete those demo files from all sources."
--
-- A systematic scan of every text/varchar/char/json/jsonb column of every base table in the public
-- schema — generated from information_schema, not a hand-picked list, because the previous audit
-- guessed at tables and missed rows — found 186 fixture rows across 12 tables. The first version
-- of that scan concatenated the columns of each row with ||, which returns NULL if ANY column is
-- null, and reported 46. Coalescing each column first took it to 186. A scan is only as honest as
-- its null handling.
--
-- THE MATERIAL FINDING IS NOT THE FILE COUNT. It is company_event:
--
--   event_type          total   fixture   fixture app_fee
--   quote.received         52        52   AED 1,917,033
--   rfq.created            12        12   —
--   payment.received        8         7   AED   412,875
--
-- Every quote and every RFQ the company has ever recorded is a demo row, and seven of the eight
-- payments carry AED 412,875 of fees that were never earned. That is the ledger the funnel tiles
-- and the marketplace analytics read. The founder was looking at a marketplace built entirely out
-- of fixtures — which is a far worse version of the "where do these numbers come from" problem than
-- any display bug in this session.
--
-- Deleting them takes the funnel to zero. That is the correct direction and the uncomfortable one:
-- zero is what a pre-revenue marketplace has actually done.
--
-- WHAT IS DELETED, and the dependency order, measured from pg_constraint before writing a word of
-- this file:
--   company_event      107   → event_delivery 126 and event_assessment 107 CASCADE automatically;
--                              event_rollup 107 is ON DELETE SET NULL and is therefore removed
--                              EXPLICITLY FIRST, because a rollup whose root event is gone is not a
--                              rollup, it is a row that will quietly count toward nothing for ever.
--                              workflow_run and decision_trace both reference company_event with NO
--                              ACTION and would BLOCK the delete — measured at 0 fixture rows each,
--                              so nothing is being forced past a guard.
--   dropbox_files       12   the index of the six fixture folders, already deleted from the
--                            founder's Dropbox in this session and verified gone by re-search.
--   doc_backups          6   backup records pointing at those folders.
--   doc_versions        14   generated PDFs for companies that never existed.
--   notifications        4   the "6 suppliers awaiting approval" digests, all four of which counted
--                            fixtures. Deleting four named rows is not the mass wipe that would
--                            unmute 18 send-dedupe routines and re-mail real customers.
--   agent_actions        1   one fixture-derived action.
--   rl_hits              1   a rate-limit record.
--
-- WHAT IS DELIBERATELY KEPT, having been read rather than pattern-matched:
--   decision_policy 'demo_rehearsal_active'  — a live SAFETY switch that HOLDS every notification
--                                              to a non-.invalid address while a rehearsal runs.
--                                              It only mentions ZZ-DEMO in its description.
--                                              Deleting it would remove a guard, not a fixture.
--   undo_log (5)                             — the audit trail of toggling that switch.
--   qa_fixture_purge_archive (33)            — the record of a PREVIOUS fixture purge.
--   escalations_archive_20260724 (1)         — the archive of the 24 Jul escalation clear-out.
--   decision_log (1)                         — append-only by trigger; cannot be deleted and does
--                                              not need to be, it is behind the fresh-start
--                                              watermark.
-- ---------------------------------------------------------------------------------------------

-- No temp table: apply_sql runs statements independently, so the fixture predicate is repeated
-- rather than materialised. Deleting the rollups FIRST while their parent events still exist is
-- what makes the subquery resolve.
delete from public.event_rollup
 where root_event_id in (select id from public.company_event
                          where payload::text ilike any (array['%ZZ DEMO%','%ZZ-DEMO%','%@example.invalid%']));

-- event_delivery and event_assessment follow by ON DELETE CASCADE.
delete from public.company_event
 where payload::text ilike any (array['%ZZ DEMO%','%ZZ-DEMO%','%@example.invalid%']);

delete from public.dropbox_files
 where coalesce(path,'') ilike any (array['%ZZ DEMO%','%ZZ-DEMO%','%@example.invalid%']);

delete from public.doc_backups
 where coalesce(path,'')||' '||coalesce(dropbox_path,'') ilike any (array['%ZZ DEMO%','%ZZ-DEMO%','%@example.invalid%']);

delete from public.doc_versions d
 where (select coalesce(string_agg(coalesce(v::text,''), ' '), '')
          from jsonb_each_text(to_jsonb(d)) t(k, v))
       ilike any (array['%ZZ DEMO%','%ZZ-DEMO%','%@example.invalid%']);

delete from public.notifications n
 where coalesce(n.subject,'')||' '||coalesce(n.body,'')||' '||coalesce(n.to_email,'')
       ilike any (array['%ZZ DEMO%','%ZZ-DEMO%','%@example.invalid%']);

delete from public.agent_actions a
 where coalesce(a.title,'')||' '||coalesce(a.recommendation,'')||' '||coalesce(a.detail::text,'')
       ilike any (array['%ZZ DEMO%','%ZZ-DEMO%','%@example.invalid%']);

delete from public.rl_hits r
 where (select coalesce(string_agg(coalesce(v::text,''), ' '), '')
          from jsonb_each_text(to_jsonb(r)) t(k, v))
       ilike any (array['%ZZ DEMO%','%ZZ-DEMO%','%@example.invalid%']);
