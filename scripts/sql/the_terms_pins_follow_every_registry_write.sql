-- THE TERMS PINS FOLLOW EVERY REGISTRY WRITE (6 Sep 2026). Corrects the_terms_pins_follow_the_registry.sql.
--
-- MEASURED by the_refund_ladder_texts_agree after the label-only edit of the Supplier Agreement:
-- fn_terms_integrity() answered supplier ok=false — pinned_for_version v7 against declared v8, and the
-- pinned sha was the registry's PREVIOUS content_sha256. Two causes:
--   1. z20_terms_pins_sync was declared "after update OF version, content_sha256, effective_date". A
--      column list on an UPDATE trigger tests the columns the STATEMENT set, not the columns a BEFORE
--      trigger changed: trg_pages_legal_sync sets body_html and source, trg_legal_documents_hash then
--      sets content_sha256, and the AFTER trigger never fired. It now fires on every insert or update.
--   2. fn_terms_pins_sync did not write terms_sha256_supplier_version / terms_sha256_customer_version,
--      the "pinned for version" labels fn_terms_integrity compares with the declared version.
--
--   node scripts/apply_sql.mjs scripts/sql/the_terms_pins_follow_every_registry_write.sql --apply --ddl

begin;

create or replace function public.fn_terms_pins_sync()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_sv text; v_ss text; v_cv text; v_cs text;
begin
  select version, content_sha256 into v_sv, v_ss from public.legal_documents where slug = 'supplier-agreement' order by effective_date desc nulls last, version desc limit 1;
  select version, content_sha256 into v_cv, v_cs from public.legal_documents where slug = 'customer-terms' order by effective_date desc nulls last, version desc limit 1;
  if v_sv is not null then
    insert into public.app_secrets (key, value)
    values ('supplier_terms_version', v_sv), ('terms_version', v_sv), ('terms_sha256_supplier_version', v_sv)
      on conflict (key) do update set value = excluded.value, updated_at = now() where app_secrets.value is distinct from excluded.value;
    if v_ss is not null then
      insert into public.app_secrets (key, value) values ('terms_sha256_supplier', v_ss)
        on conflict (key) do update set value = excluded.value, updated_at = now() where app_secrets.value is distinct from excluded.value;
    end if;
  end if;
  if v_cv is not null then
    insert into public.app_secrets (key, value)
    values ('customer_terms_version', v_cv), ('terms_sha256_customer_version', v_cv)
      on conflict (key) do update set value = excluded.value, updated_at = now() where app_secrets.value is distinct from excluded.value;
    if v_cs is not null then
      insert into public.app_secrets (key, value) values ('terms_sha256_customer', v_cs)
        on conflict (key) do update set value = excluded.value, updated_at = now() where app_secrets.value is distinct from excluded.value;
    end if;
  end if;
end $function$;

drop trigger if exists z20_terms_pins_sync on public.legal_documents;
create trigger z20_terms_pins_sync
  after insert or update on public.legal_documents
  for each statement execute function public.trg_terms_pins_sync();

select public.fn_terms_pins_sync();

do $$
declare n int;
begin
  select count(*) into n from public.fn_terms_integrity() where not ok;
  if n <> 0 then raise exception 'fn_terms_integrity still reports % kind(s) not ok', n; end if;
end $$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_terms_pins_follow_every_registry_write.sql',
       evidence = 'pins derived from the legal registry on every write (6 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_terms_pins_sync';

commit;
