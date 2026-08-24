-- O16. FOUR ENFORCING TABLES THIS SESSION CREATED AND LEFT TRUNCATABLE.
--
-- `public.fn_kernel_truncate_protection_state` is a GATE, not a ratchet — it is not named in
-- scripts/checks/kernel-boards.json, so every one of its checks must be green and any red fails the
-- suite. It went red at **4 of 91** on both of its counts, and CI caught it:
--
--   a kernel board is red and kernel-boards.json does not disclose it. Either the estate regressed,
--   or this is a gap that must be recorded with an owner and a reason before it is allowed to stand.
--   Do not add it to kernel-boards.json to make this pass unless the gap is genuinely deliberate.
--
-- It is a regression, and it is mine. The board's definition of an ENFORCING table is any table
-- carrying a non-statement BEFORE/AFTER row trigger whose function contains `raise exception`, and
-- three tables this session created plus one it gave a new trigger now meet it:
--
--   public.phase_d_file_revision        a10_phase_d_file_revision_reviewer          (O04)
--   public.phase_d_quote_normalisation  a10_phase_d_normalisation_shape             (O06)
--   public.phase_d_legal_assertion      a10_phase_d_legal_assertion_source          (O07)
--   public.quotes                       a30_quote_supplier_is_immutable             (O06)
--
-- Each refuses a write and none of them refused a TRUNCATE, so the refusal was one statement away
-- from being irrelevant: `truncate public.phase_d_file_revision` would have removed every redaction
-- verdict without the reviewer-independence trigger having anything to say about it. And all four
-- still granted TRUNCATE to service_role, because TRUNCATE arrives with ALL and nothing had taken
-- it away.
--
-- THE FIX IS THE ESTATE'S OWN PATTERN, applied without inventing anything: attach
-- `z00_kernel_truncate_guard` — the same statement-level guard the other 87 enforcing tables carry —
-- and revoke the privilege. Both halves are needed and the board counts them separately: a guard
-- with the grant still in place is a control the owner can walk around, and a revoke with no guard
-- leaves the table open to anyone who later regains the privilege.
--
-- WHY `quotes` IS INCLUDED. `a30_quote_supplier_is_immutable` (O06) is what made it enforcing, so
-- it is this session's regression on the same board as the other three, and the marketplace's
-- quotation table is the last one that should be truncatable by a service key.
--
-- NOTHING ELSE IS TOUCHED. The eight other tables this session created carry no raising row trigger
-- and are not enforcing tables, so adding a guard to them would be adding a control the board does
-- not ask for and nobody has driven.

DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_file_revision;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_d_file_revision
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_quote_normalisation;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_d_quote_normalisation
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_legal_assertion;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_d_legal_assertion
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.quotes;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.quotes
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

REVOKE TRUNCATE ON public.phase_d_file_revision       FROM service_role, authenticated, anon;
REVOKE TRUNCATE ON public.phase_d_quote_normalisation FROM service_role, authenticated, anon;
REVOKE TRUNCATE ON public.phase_d_legal_assertion     FROM service_role, authenticated, anon;
REVOKE TRUNCATE ON public.quotes                      FROM service_role, authenticated, anon;

-- AND THE SIBLING TABLES, SO THE NEXT TRIGGER ADDED TO ONE DOES NOT REOPEN THIS.
-- These five carry no raising row trigger today, so the board does not count them and this is not
-- required to make it green. It is here because the only thing standing between them and the same
-- red is that nobody has yet added a guard to them — and a registry of redaction verdicts, metadata
-- scans, identifier classes, legal sources and closed dispositions is not something a service key
-- should be able to empty in one statement.
REVOKE TRUNCATE ON public.phase_d_metadata_scan                    FROM service_role, authenticated, anon;
REVOKE TRUNCATE ON public.phase_d_personal_identifier_class        FROM service_role, authenticated, anon;
REVOKE TRUNCATE ON public.phase_d_legal_source                     FROM service_role, authenticated, anon;
REVOKE TRUNCATE ON public.phase_d_supplier_authored_field          FROM service_role, authenticated, anon;
REVOKE TRUNCATE ON public.phase_d_injected_defect_disposition_history FROM service_role, authenticated, anon;
