-- Audit 3.1 "Every API action explicitly classified" — FAIL.
-- os_ops dispatches 30 actions, 18 of them mutating, and NONE of the 18 existed in
-- public.control_mode_action. An admin in Observe Mode could approve a supplier, post to the
-- general ledger, cancel an inquiry or set an arbitrary field without ever opening Control Mode.
--
-- Phase 1 emergency containment masked this by making os_ops read-only wholesale. That block was
-- removed on founder instruction 2026-08-03, which makes this urgent rather than optional: the 18
-- actions are reachable behind isAdmin() alone until the gate is enforced in os_ops.
--
-- requires_control is a GENERATED column (classification = 'mutating'), so classification is the
-- gate. Anything that changes state is therefore recorded as 'mutating' and will require an open
-- Control Mode session. That is deliberate and matches how os_api's 44 actions are already treated.

insert into public.control_mode_action (action, description, risk, classification) values
  ('gl_post',           'Posts a journal entry to the general ledger - moves money records.',          'critical', 'mutating'),
  ('po_approve',        'Approves a purchase order - commits company funds.',                          'critical', 'mutating'),
  ('field_set',         'Writes an arbitrary field on an arbitrary record.',                           'critical', 'mutating'),
  ('supplier_decide',   'Approves, rejects or bans a supplier - decides market access.',               'high',     'mutating'),
  ('customer_decide',   'Approves, rejects or bans a customer account.',                               'high',     'mutating'),
  ('cancel_inquiry',    'Cancels a live inquiry - irreversible for the buyer and matched suppliers.',  'high',     'mutating'),
  ('doc_review_decide', 'Accepts or rejects a supplier KYC document.',                                 'high',     'mutating'),
  ('action_decide',     'Approves or rejects a queued agent action.',                                  'high',     'mutating'),
  ('kb_approve',        'Publishes knowledge to the live agent corpus.',                               'medium',   'mutating'),
  ('kb_reject',         'Rejects proposed knowledge.',                                                 'medium',   'mutating'),
  ('kb_gov',            'Adjusts knowledge governance settings.',                                      'medium',   'mutating'),
  ('prompt_reject',     'Rejects a proposed prompt change.',                                           'medium',   'mutating'),
  ('content_save',      'Saves site or board content - can change published pages.',                   'medium',   'mutating'),
  ('rfq_stage',         'Moves an RFQ between pipeline stages.',                                       'low',      'mutating'),
  ('rfq_outcome',       'Records the outcome of an RFQ.',                                              'low',      'mutating'),
  ('note_add',          'Adds a note to a record.',                                                    'low',      'mutating'),
  ('task_create',       'Creates an internal task.',                                                   'low',      'mutating'),
  ('task_done',         'Marks an internal task complete.',                                            'low',      'mutating')
on conflict (action) do update
  set description = excluded.description, risk = excluded.risk, classification = excluded.classification;

-- The 12 read-only os_ops actions, recorded so the surface is completely described and a future
-- reader can distinguish "read-only" from "never classified".
insert into public.control_mode_action (action, description, risk, classification) values
  ('audit_log',      'Reads the OS audit log.',                'low', 'read_only'),
  ('content_get',    'Reads site or board content.',           'low', 'read_only'),
  ('customer_stats', 'Reads customer statistics.',             'low', 'read_only'),
  ('detail',         'Reads a single record.',                 'low', 'read_only'),
  ('dropbox',        'Lists Dropbox contents.',                'low', 'read_only'),
  ('dropbox_link',   'Creates a read link to a Dropbox file.', 'low', 'read_only'),
  ('expiring_docs',  'Reads documents nearing expiry.',        'low', 'read_only'),
  ('list',           'Lists records.',                         'low', 'read_only'),
  ('stages_list',    'Reads the pipeline stage list.',         'low', 'read_only'),
  ('supplier_stats', 'Reads supplier statistics.',             'low', 'read_only')
on conflict (action) do update
  set description = excluded.description, risk = excluded.risk, classification = excluded.classification;;
