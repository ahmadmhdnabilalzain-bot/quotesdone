-- DOWN for O16. Classification: GRANT_RESTORE plus four additive triggers.
--
-- Reversing this REOPENS the hole it closed: four enforcing tables become truncatable by a service
-- key again and fn_kernel_truncate_protection_state goes red at 4 of 91 on both counts. Reverse it
-- only alongside the files that created those triggers (O04, O06, O07), and never on its own.
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_file_revision;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_quote_normalisation;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_legal_assertion;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.quotes;

GRANT TRUNCATE ON public.phase_d_file_revision       TO service_role;
GRANT TRUNCATE ON public.phase_d_quote_normalisation TO service_role;
GRANT TRUNCATE ON public.phase_d_legal_assertion     TO service_role;
GRANT TRUNCATE ON public.quotes                      TO service_role;
GRANT TRUNCATE ON public.phase_d_metadata_scan                       TO service_role;
GRANT TRUNCATE ON public.phase_d_personal_identifier_class           TO service_role;
GRANT TRUNCATE ON public.phase_d_legal_source                        TO service_role;
GRANT TRUNCATE ON public.phase_d_supplier_authored_field             TO service_role;
GRANT TRUNCATE ON public.phase_d_injected_defect_disposition_history TO service_role;
