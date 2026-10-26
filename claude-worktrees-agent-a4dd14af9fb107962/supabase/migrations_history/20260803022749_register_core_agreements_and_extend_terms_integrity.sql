-- The two documents that actually bind anyone — the Supplier Agreement and the Customer Terms —
-- were the only two NOT in the legal register. They lived as an app_secrets blob and a pages row.
-- Register them from their canonical sources, and extend the integrity check to cover both.
--
-- Canonical sources, confirmed from compliance_archive v6 (which hashes the accepted text into the
-- certificate):
--   supplier -> app_secrets.supplier_terms_html , label app_secrets.supplier_terms_label
--   customer -> pages.legal_terms_body          , label app_secrets.customer_terms_label

insert into public.legal_documents (slug, title, category, version, effective_date, summary, body_html, updated_at)
select 'supplier-agreement', 'Supplier Agreement & Platform Terms', 'agreement',
       (select value from public.app_secrets where key='terms_version'),
       current_date,
       'The agreement presented and accepted at supplier registration. Canonical source: app_secrets.supplier_terms_html.',
       (select value from public.app_secrets where key='supplier_terms_html'), now()
on conflict (slug) do update set version=excluded.version, body_html=excluded.body_html,
       effective_date=excluded.effective_date, summary=excluded.summary, updated_at=now();

insert into public.legal_documents (slug, title, category, version, effective_date, summary, body_html, updated_at)
select 'customer-terms', 'Customer Terms & Conditions', 'agreement',
       (select value from public.app_secrets where key='customer_terms_version'),
       current_date,
       'The terms presented and accepted at customer registration. Canonical source: pages.legal_terms_body.',
       (select html from public.pages where slug='legal_terms_body'), now()
on conflict (slug) do update set version=excluded.version, body_html=excluded.body_html,
       effective_date=excluded.effective_date, summary=excluded.summary, updated_at=now();

drop function if exists public.fn_terms_integrity();

create function public.fn_terms_integrity()
returns table(kind text, declared_version text, pinned_for_version text, pinned_sha text, live_sha text, published_matches_signed boolean, ok boolean)
language sql stable security definer set search_path to 'public','pg_temp' as $$
  with s as (
    select 'supplier'::text kind,
           (select value from public.app_secrets where key='terms_version') dv,
           (select value from public.app_secrets where key='terms_sha256_supplier_version') pv,
           (select value from public.app_secrets where key='terms_sha256_supplier') psha,
           (select encode(sha256(convert_to(value,'UTF8')),'hex') from public.app_secrets where key='supplier_terms_html') lsha,
           (select encode(sha256(convert_to(html,'UTF8')),'hex') from public.pages where slug='legal_supplier_body') pubsha
    union all
    select 'customer',
           (select value from public.app_secrets where key='customer_terms_version'),
           (select value from public.app_secrets where key='terms_sha256_customer_version'),
           (select value from public.app_secrets where key='terms_sha256_customer'),
           (select encode(sha256(convert_to(html,'UTF8')),'hex') from public.pages where slug='legal_terms_body'),
           (select encode(sha256(convert_to(html,'UTF8')),'hex') from public.pages where slug='legal_terms_body')
  )
  select kind, dv, pv, psha, lsha,
         pubsha is not distinct from lsha,
         (psha is not distinct from lsha) and (dv is not distinct from pv) and (pubsha is not distinct from lsha)
  from s;
$$;
revoke execute on function public.fn_terms_integrity() from public, anon, authenticated;;
