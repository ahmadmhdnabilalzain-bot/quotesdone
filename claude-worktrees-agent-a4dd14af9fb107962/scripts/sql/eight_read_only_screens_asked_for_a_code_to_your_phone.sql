-- EIGHT READ-ONLY SCREENS ASKED THE FOUNDER FOR A CODE SENT TO HIS PHONE.
--
-- SEEN, not inferred: opened /os as management@quotesdone.com on 13 Aug 2026, clicked System
-- Health, and the Control Mode panel took over the right-hand third of the screen with
--
--     "ws.exec_home" was refused: This action has not been classified as read-only or mutating,
--     so it was refused.
--     WHY ARE YOU MAKING THIS CHANGE?  [ Send a code to my phone ]
--
-- Nothing was being changed. ws.exec_home is a dashboard read.
--
-- THE CAUSE IS TWO LISTS THAT DISAGREE. An os_api action must appear in BOTH os_api's ACTION_CLASS
-- and public.control_mode_action; each gate refuses independently, which is the right design and
-- is stated as such in os_api. But nothing keeps them in step, and they have drifted:
--
--     ACTION_CLASS               73 actions
--     control_mode_action        90 actions
--     in the code, NOT in the db 11
--
-- and those eleven are refused by the database gate with `action_classification_required`, which
-- the console renders as the Control Mode panel — an MFA challenge, with a "why are you making
-- this change?" box, for a screen that changes nothing.
--
--     read_only, and therefore refused for no reason at all:
--       drilldown, memory, transcribe, ws.company_os, ws.exec_home, ws.intelligence,
--       ws.live_company, ws.notifications
--
--     mutating, refused for the WRONG reason:
--       report_recommend_approve, simulate, simulation_approve
--
-- The three mutating ones were failing CLOSED, which is the correct outcome reached by the wrong
-- route: they were refused as unclassified rather than gated as mutations, so the founder was told
-- "nobody has classified this" instead of "this changes something, open Control Mode". They are
-- registered here as requires_control = true and keep needing Control Mode. NOTHING IS OPENED THAT
-- WAS CLOSED: every action below carries the classification os_api already gives it.
--
-- This is why the estate looked like it was demanding a text message to log in. It was not the
-- login. It was a read being refused as if it were an unreviewed mutation.
--
--   node scripts/apply_sql.mjs scripts/sql/eight_read_only_screens_asked_for_a_code_to_your_phone.sql --promote --ddl

-- requires_control IS NOT SET HERE, and the attempt to set it is worth recording: the first draft
-- of this file wrote it explicitly and Postgres refused —
--
--     cannot insert a non-DEFAULT value into column "requires_control"
--     DETAIL: Column "requires_control" is a generated column.
--
-- It is GENERATED from classification, so the gate and its label can never drift apart. Writing it
-- by hand would have been the same class of defect this file exists to fix, one table lower down.
insert into public.control_mode_action (action, description, risk, classification)
values
  ('drilldown',                'fn_os_drilldown - read.',                              'low',   'read_only'),
  ('memory',                   'Company memory - read.',                               'low',   'read_only'),
  ('transcribe',               'Speech-to-text on caller-supplied audio - read, but a paid call.', 'low', 'read_only'),
  ('ws.company_os',            'Workspace read.',                                      'low',   'read_only'),
  ('ws.exec_home',             'Workspace read.',                                      'low',   'read_only'),
  ('ws.intelligence',          'Workspace read.',                                      'low',   'read_only'),
  ('ws.live_company',          'Workspace read.',                                      'low',   'read_only'),
  ('ws.notifications',         'Workspace read.',                                      'low',   'read_only'),
  ('report_recommend_approve', 'Approves a recommendation on a report - acts on it.',  'high',  'mutating'),
  ('simulate',                 'Runs a what-if simulation and stores the run.',        'medium','mutating'),
  ('simulation_approve',       'Approves a simulation and applies what it proposed.',  'high',  'mutating')
on conflict (action) do nothing;
