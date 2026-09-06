-- THE TERMS PINS FOLLOW THE REGISTRY (6 Sep 2026).
--
-- MEASURED after the Supplier Agreement's pricing sentence changed at 20:36Z: legal_documents.supplier-agreement
-- moved to v8 (sha 4ec73754…) through trg_pages_legal_sync + trg_legal_documents_hash, but
-- app_secrets.supplier_terms_version / terms_version still said v7 (hand-pinned at 19:24Z) — the pins
-- are what the kyc function stamps into a supplier's accepted_terms_version, while BR-025 judges the
-- registry pair. Two versions for one acceptance is exactly the mismatch BR-025 refuses.
--
-- fn_terms_version() already reads the registry first (the_terms_version_reads_the_registry_first.sql);
-- this makes the pins a derived value: an AFTER trigger on legal_documents writes
-- supplier_terms_version / terms_version / terms_sha256_supplier from the supplier-agreement row and
-- customer_terms_version / terms_sha256_customer from the customer-terms row on every change, and the
-- file syncs them once now. Nothing pins a version by hand again.
--
--   node scripts/apply_sql.mjs scripts/sql/the_terms_pins_follow_the_registry.sql --apply --ddl

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
    insert into public.app_secrets (key, value) values ('supplier_terms_version', v_sv), ('terms_version', v_sv)
      on conflict (key) do update set value = excluded.value, updated_at = now() where app_secrets.value is distinct from excluded.value;
    if v_ss is not null then
      insert into public.app_secrets (key, value) values ('terms_sha256_supplier', v_ss)
        on conflict (key) do update set value = excluded.value, updated_at = now() where app_secrets.value is distinct from excluded.value;
    end if;
  end if;
  if v_cv is not null then
    insert into public.app_secrets (key, value) values ('customer_terms_version', v_cv)
      on conflict (key) do update set value = excluded.value, updated_at = now() where app_secrets.value is distinct from excluded.value;
    if v_cs is not null then
      insert into public.app_secrets (key, value) values ('terms_sha256_customer', v_cs)
        on conflict (key) do update set value = excluded.value, updated_at = now() where app_secrets.value is distinct from excluded.value;
    end if;
  end if;
end $function$;

revoke execute on function public.fn_terms_pins_sync() from public, anon, authenticated;

create or replace function public.trg_terms_pins_sync()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  perform public.fn_terms_pins_sync();
  return null;
end $function$;

revoke execute on function public.trg_terms_pins_sync() from public, anon, authenticated;

drop trigger if exists z20_terms_pins_sync on public.legal_documents;
create trigger z20_terms_pins_sync
  after insert or update of version, content_sha256, effective_date on public.legal_documents
  for each statement execute function public.trg_terms_pins_sync();

select public.fn_terms_pins_sync();

do $$
declare v_reg text; v_pin text;
begin
  select version into v_reg from public.legal_documents where slug = 'supplier-agreement' order by effective_date desc nulls last, version desc limit 1;
  select value into v_pin from public.app_secrets where key = 'supplier_terms_version';
  if v_reg is distinct from v_pin then raise exception 'supplier pin % != registry %', v_pin, v_reg; end if;
  select version into v_reg from public.legal_documents where slug = 'customer-terms' order by effective_date desc nulls last, version desc limit 1;
  select value into v_pin from public.app_secrets where key = 'customer_terms_version';
  if v_reg is distinct from v_pin then raise exception 'customer pin % != registry %', v_pin, v_reg; end if;
  if public.fn_terms_version('supplier') is distinct from (select value from public.app_secrets where key = 'supplier_terms_version') then
    raise exception 'fn_terms_version(supplier) and the pin disagree';
  end if;
end $$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_terms_pins_follow_the_registry.sql',
       evidence = 'pins derived from the legal registry (6 Sep 2026)'
 where schema_name = 'public' and routine_name in ('fn_terms_pins_sync', 'trg_terms_pins_sync');

commit;
