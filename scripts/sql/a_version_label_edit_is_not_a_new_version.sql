-- A VERSION LABEL EDIT IS NOT A NEW VERSION (6 Sep 2026). Follows the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql.
--
-- MEASURED by the_refund_ladder_texts_agree: the Supplier Agreement page says "Version 7" in its body
-- and "Version v7 · Last updated 6 September 2026" in its header while the registry holds v8 — the
-- pricing sentence changed at 20:36Z, trg_pages_legal_sync copied the body into legal_documents, and
-- trg_legal_documents_hash bumped v7 -> v8 as designed. Writing "Version 8" into the page would copy
-- again and bump to v9: with a version label inside the body, the page can never name the version the
-- registry holds. That circle is what the check reports.
--
-- The hash trigger now compares the OLD and NEW bodies with their version labels and "last updated"
-- dates stripped: a body whose only change is the label it prints is re-hashed but NOT re-versioned.
-- Any change to the words a customer or supplier accepts still bumps. Then the page labels are set to
-- the registry's version (8) in one statement, the sync copies them, the hash updates, v8 stays v8,
-- and the pins follow through z20_terms_pins_sync.
--
--   node scripts/apply_sql.mjs scripts/sql/a_version_label_edit_is_not_a_new_version.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_legal_body_without_labels(p_html text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- the parts of a legal body that name its own version or date, in either language
  select regexp_replace(
           regexp_replace(coalesce(p_html, ''), '(Version|الإصدار)\s*v?[0-9]+(\.[0-9]+)?', '', 'g'),
           '(Last updated|effective|آخر تحديث|ساري(ة)? من)\s*[0-9]{1,2}\s+[^<·|,.]{3,20}\s+20[0-9]{2}', '', 'g');
$function$;

CREATE OR REPLACE FUNCTION public.trg_legal_documents_hash()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  NEW.content_sha256 := encode(sha256(convert_to(coalesce(NEW.body_html, ''), 'UTF8')), 'hex');
  if TG_OP = 'UPDATE' and NEW.body_html is distinct from OLD.body_html then
    -- 6 SEP 2026: a body whose only change is the version label or date it prints is the SAME
    -- version, re-hashed. The words a party accepts changing is what makes a new version.
    if public.fn_legal_body_without_labels(NEW.body_html) is distinct from public.fn_legal_body_without_labels(OLD.body_html) then
      -- a changed body is a new version unless the statement set one itself
      if NEW.version is not distinct from OLD.version then
        NEW.version := public.fn_legal_version_bump(OLD.version);
      end if;
      NEW.effective_date := current_date;
    end if;
    NEW.updated_at := now();
  elsif TG_OP = 'UPDATE' and NEW.version is distinct from OLD.version then
    NEW.updated_at := now();
  end if;
  return NEW;
end $function$;

-- the page labels follow the registry: supplier-agreement v8 (6 Sep 2026)
update public.pages
   set html = regexp_replace(html, 'Version 7 &middot; governed by the laws', 'Version 8 &middot; governed by the laws')
 where slug = 'legal_supplier_body' and html like '%Version 7 &middot; governed by the laws%';

do $$
declare v text; n int;
begin
  select version into v from public.legal_documents where slug = 'supplier-agreement';
  if v <> 'v8' then raise exception 'supplier-agreement is % after a label-only edit (expected v8)', v; end if;
  select count(*) into n from public.pages where slug = 'legal_supplier_body' and html like '%Version 8 &middot; governed by the laws%';
  if n <> 1 then raise exception 'the supplier page does not name Version 8'; end if;
  select count(*) into n from public.legal_documents where slug = 'supplier-agreement' and body_html like '%Version 8 &middot; governed by the laws%';
  if n <> 1 then raise exception 'the registry body does not name Version 8'; end if;
end $$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/a_version_label_edit_is_not_a_new_version.sql',
       evidence = 'a label-only edit re-hashes without re-versioning (6 Sep 2026)'
 where schema_name = 'public' and routine_name in ('trg_legal_documents_hash', 'fn_legal_body_without_labels');

commit;
