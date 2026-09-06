-- THE SUPPLIER AGREEMENT PRICES BY COUNT, NOT BY DATE (6 Sep 2026).
--
-- Founder ruling, 6 Sep 2026, final: "supplier registration is free for the first 1000 registration.
-- after that its 1000 AED per year. dont use a deadline with dates." pricing_config already carries
-- supplier_charging_starts = NULL (pricing_has_no_date_no_discount_and_no_cap.sql), but the published
-- Supplier Agreement (public.pages.legal_supplier_body, mirrored by the legal registry through
-- trg_pages_legal_sync) still said "free of charge until 31 July 2027. From 1 August 2027 a
-- subscription fee ... applies ... The first 1,000 businesses to register ... are permanently exempt".
-- The same sentence is replaced in src/content/legal.json, src/content/marketing.json (FAQ, four
-- places, English and Arabic) and the supplier portal strings in the same change.
--
-- The trigger chain bumps legal_documents.supplier-agreement (version, effective_date, sha256) on
-- this write, which is what BR-025 judges; the app_secrets pins follow through the same sync.
--
--   node scripts/apply_sql.mjs scripts/sql/the_supplier_agreement_prices_by_count_not_by_date.sql --apply --ddl

begin;

update public.pages
   set html = replace(html,
     'Supplier registration is <b>free of charge until 31 July 2027</b>. From <b>1 August 2027</b> a subscription fee of <b>AED 1,000 per year</b> applies, payable annually in advance. The <b>first 1,000 businesses to register</b> on the Platform are permanently exempt from that fee.',
     'Supplier registration is <b>free of charge for the first 1,000 businesses to register</b> on the Platform, permanently. From the <b>1,001st registration</b> a subscription fee of <b>AED 1,000 per year</b> applies, payable annually in advance.')
 where slug = 'legal_supplier_body'
   and html like '%free of charge until 31 July 2027%';

do $$
declare n int;
begin
  select count(*) into n from public.pages where slug = 'legal_supplier_body' and html like '%2027%';
  if n <> 0 then raise exception 'legal_supplier_body still carries a 2027 date'; end if;
  select count(*) into n from public.pages where slug = 'legal_supplier_body' and html like '%first 1,000 businesses to register</b> on the Platform, permanently%';
  if n <> 1 then raise exception 'legal_supplier_body does not carry the count-based sentence'; end if;
end $$;

commit;
