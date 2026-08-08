-- Pin the supplier agreement version to the actual text it names.
--
-- The audit's finding was that "the certificate hash is computed at render time from mutable
-- storage" — app_secrets.supplier_terms_html is an editable-in-place blob, so a certificate issued
-- last week and one issued today can both say "v5" and refer to different text, with nothing able to
-- detect it. Recording the hash of the text at the moment the version was declared makes that
-- detectable: fn_terms_integrity() compares the live text against the pinned hash and reports drift.
--
-- This does not make the agreement immutable — it makes changing it without bumping the version
-- VISIBLE, which is the property that was missing.

insert into public.app_secrets(key, value)
select 'terms_sha256_supplier', encode(sha256(convert_to(value,'UTF8')),'hex')
from public.app_secrets where key = 'supplier_terms_html'
on conflict (key) do update set value = excluded.value;

insert into public.app_secrets(key, value)
select 'terms_sha256_supplier_version', (select value from public.app_secrets where key='terms_version')
on conflict (key) do update set value = excluded.value;

create or replace function public.fn_terms_integrity()
returns table(kind text, declared_version text, pinned_for_version text, pinned_sha text, live_sha text, ok boolean)
language sql stable security definer set search_path to 'public','pg_temp' as $$
  select 'supplier'::text,
         (select value from public.app_secrets where key='terms_version'),
         (select value from public.app_secrets where key='terms_sha256_supplier_version'),
         (select value from public.app_secrets where key='terms_sha256_supplier'),
         (select encode(sha256(convert_to(value,'UTF8')),'hex') from public.app_secrets where key='supplier_terms_html'),
         (select value from public.app_secrets where key='terms_sha256_supplier')
           is not distinct from
         (select encode(sha256(convert_to(value,'UTF8')),'hex') from public.app_secrets where key='supplier_terms_html')
         and (select value from public.app_secrets where key='terms_version')
           is not distinct from
         (select value from public.app_secrets where key='terms_sha256_supplier_version');
$$;
revoke execute on function public.fn_terms_integrity() from public, anon, authenticated;;
