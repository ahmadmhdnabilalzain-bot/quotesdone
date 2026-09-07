-- THE TERMS VERSION READS THE REGISTRY FIRST (6 Sep 2026). Records what production runs.
--
-- The customer-onboarding work of 6 Sep 2026 changed two routines on production without a change
-- file, and the canonical engine reported both as drift against
-- supabase/migrations_history/20260803022030_legal_version_single_source_and_immutable_acceptance.sql:
--   * fn_terms_version(kind) now resolves the version from the legal registry first — the document
--     phase_d_acceptance_document names for the kind, newest effective_date — and only then from the
--     app_secrets label; this is the pair BR-025 judges, so the product and the kernel agree.
--   * qd_norm_customer_ver() keeps its rule that a recorded acceptance version is evidence and is
--     never rewritten, with one exception: inside the acceptance's own trigger chain (z56, trigger
--     depth > 1) the row may be re-aligned to the version the registry publishes now, which is the
--     version fn_customer_terms_accept just recorded in the kernel.
-- Both definitions below are the live bodies read back from production, so the repository is the
-- source again. ACLs are unchanged (CREATE OR REPLACE keeps them; the migration revoked
-- fn_terms_version from public/anon/authenticated).
--
--   node scripts/apply_sql.mjs scripts/sql/the_terms_version_reads_the_registry_first.sql --apply --ddl

-- ROUTINE REMOVED 7 September 2026. public.fn_terms_version was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


CREATE OR REPLACE FUNCTION public.qd_norm_customer_ver()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if TG_OP = 'UPDATE' then
    if NEW.tos_accepted_at is not distinct from OLD.tos_accepted_at then
      -- Not a new acceptance: the recorded version is evidence and is never rewritten -- except
      -- (6 Sep 2026) by the acceptance's own trigger chain re-aligning the row to the version the
      -- registry publishes now, which is the version fn_customer_terms_accept just recorded in the
      -- kernel. Depth > 1 means we are inside z56's chain, not a later hand call or a profile edit.
      if pg_trigger_depth() > 1
         and NEW.tos_version is distinct from OLD.tos_version
         and NEW.tos_version = public.fn_terms_version('customer') then
        return NEW;
      end if;
      NEW.tos_version := OLD.tos_version;
      return NEW;
    end if;
    if NEW.tos_version is not distinct from OLD.tos_version then
      NEW.tos_version := public.fn_terms_version('customer');
      return NEW;
    end if;
  end if;
  if NEW.tos_accepted_at is not null and coalesce(NEW.tos_version,'') = '' then
    NEW.tos_version := public.fn_terms_version('customer');
  end if;
  return NEW;
end $function$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_terms_version_reads_the_registry_first.sql',
       evidence = 'live bodies of 6 Sep 2026 recorded in the repository (registry-first terms version; z56 re-alignment)'
 where schema_name = 'public' and routine_name in ('fn_terms_version', 'qd_norm_customer_ver');
