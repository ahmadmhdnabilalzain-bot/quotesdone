-- Phase C — register founder_command_thread in the database gate.
--
-- os_api enforces two independent gates over one vocabulary: ACTION_CLASS in the edge function and
-- public.control_mode_action in the database. An action present in one and absent from the other is
-- the defect that once made read-only screens demand a phone code. founder_command_thread is added
-- to both in the same change as the UI that calls it.
--
-- read_only, deliberately: "report progress back to me" must never be gated behind a phone code.
-- Issuing an order is mutating and stays gated; reading what happened to it is not.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

insert into public.control_mode_action (action, description, risk, classification) values
  ('founder_command_thread',
   'Founder Command Center: the founder-facing thread for one command — what he said, what was understood, who has it, where each owner is, every progress note, and the completion summary.',
   'low', 'read_only')
on conflict (action) do update set description = excluded.description, risk = excluded.risk,
  classification = excluded.classification;
