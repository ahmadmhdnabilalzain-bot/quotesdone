-- drawing_redact_verify was routed to the one model class it cannot read.
--
-- MEASURED ON PRODUCTION 2026-08-09: fn_task_class maps drawing_redact_verify to
-- 'document_extraction', and model_policy resolves that to google/gemini-3.5-flash.
--
-- verify_prod_readiness.mjs has carried the reason since it was written, from a measurement on
-- staging: mapping this function to document_extraction "took the journey from 37/37 to 35/37 —
-- that class resolves to google/gemini-3.5-flash, whose output this function cannot parse. It then
-- fails closed and publishes NO redacted page. Until the parser is fixed this function must not be
-- routed to a google model."
--
-- THE GATE SAID APPLIED THE WHOLE TIME. Its condition was `task_class IS NOT 'ABSENT'`, so ANY
-- mapping satisfied it — including the single value its own remediation text forbids. That is a
-- check passing by accident, which is worse than one that fails, and it would have reported green
-- forever. The check now asserts the VALUE; this statement gives it something true to assert.
--
-- LATENT, NOT FIRING, AND FIXED BEFORE IT MATTERS. Two drawings are on file and ZERO inquiries
-- carry a drawing_redacted_paths, so no redaction has been attempted on real work yet. Redaction is
-- the supplier-anonymity mechanism this marketplace is built on and the differentiator the period
-- report says none of the 27 competitors offer — it should be right before traffic arrives, not
-- diagnosed after a customer sees an unredacted drawing.
--
-- general_drafting resolves to ~anthropic/claude-haiku-latest. NOT document_extraction, and
-- deliberately not matched to its siblings drawing_redact/drawing_boq, which is the mistake that
-- produced this state.

insert into public.fn_task_class (fn, task_class, note, active, updated_at)
values ('drawing_redact_verify', 'general_drafting',
        'Vision check that a redaction landed. NOT document_extraction: that class resolves to '
        || 'google/gemini-3.5-flash, whose output this function cannot parse - it fails closed and '
        || 'publishes no redacted page (measured on staging, 37/37 -> 35/37). Restored to '
        || 'general_drafting 2026-08-10 after production was found holding the forbidden value '
        || 'while verify_prod_readiness reported APPLIED, because that gate only checked the row '
        || 'existed.',
        true, now())
    on conflict (fn) do update
       set task_class = excluded.task_class,
           note       = excluded.note,
           active     = true,
           updated_at = now();
