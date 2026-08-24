-- DOWN for O06. Classification: ADDITIVE_DDL — two tables, three columns on quote_comparisons,
-- two constraints, four triggers, six routines, one committed field register.
-- O07's BR-018/BR-019 legs and GATE-018 read fn_phase_d_comparison_visible and
-- fn_phase_d_quote_original_intact, so run O07's down first.
DROP TRIGGER IF EXISTS a30_quote_supplier_is_immutable ON public.quotes;
DROP FUNCTION IF EXISTS public.fn_quote_supplier_is_immutable();
DROP TRIGGER IF EXISTS a30_phase_d_object_owner_is_stable ON public.phase_d_object_record;
DROP FUNCTION IF EXISTS public.fn_phase_d_object_owner_is_stable();
DROP FUNCTION IF EXISTS public.fn_phase_d_quote_original_intact(text);
DROP TRIGGER IF EXISTS a10_phase_d_normalisation_shape ON public.phase_d_quote_normalisation;
DROP FUNCTION IF EXISTS public.fn_phase_d_normalisation_does_not_restate_the_original() CASCADE;
DROP TABLE IF EXISTS public.phase_d_quote_normalisation;
DROP TABLE IF EXISTS public.phase_d_supplier_authored_field;
DROP FUNCTION IF EXISTS public.fn_phase_d_comparison_visible(text, text, text);
ALTER TABLE public.quote_comparisons DROP CONSTRAINT IF EXISTS quote_comparisons_published_is_stamped;
ALTER TABLE public.quote_comparisons DROP CONSTRAINT IF EXISTS quote_comparisons_publication_state_ck;
ALTER TABLE public.quote_comparisons DROP COLUMN IF EXISTS superseded_by_comparison_id;
ALTER TABLE public.quote_comparisons DROP COLUMN IF EXISTS published_at;
ALTER TABLE public.quote_comparisons DROP COLUMN IF EXISTS publication_state;
