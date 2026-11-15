-- Assigned: customer_support
-- PURE PROBE (no DDL, no row written) for an_ampersand_in_a_licensing_authority_reads_as_and.sql. It always ends in
-- raise exception 'CHK<<...>>'. The ampersand spellings now answer 'uae'; every answer measured on production on 15 Nov 2026 for a
-- name with no ampersand is unchanged, the non-licensing bodies stay 'unknown', a foreign one stays 'foreign'.
do $$
declare bad text := ''; r record;
begin
  for r in select * from (values
      ('Department of Economy & Tourism', 'uae'), ('Department of Economy &amp; Tourism', 'uae'), ('Department of Economy &Tourism', 'uae'),
      ('Government of Dubai - Department of Economy & Tourism', 'uae'), ('Department of Economy and Tourism', 'uae'),
      ('Abu Dhabi Chamber of Commerce & Industry', 'unknown'), ('Sharjah Chamber of Commerce and Industry', 'unknown'),
      ('Economic Department', 'unknown'), ('TAMM', 'unknown'), ('Ministry of Commerce, Saudi Arabia', 'foreign'), ('', 'unread'),
      ('Jebel Ali Free Zone Authority', 'uae'), ('Sharjah Airport International Free Zone Authority', 'uae'), ('Masdar City Free Zone', 'uae'),
      ('Khalifa Economic Zones Abu Dhabi - KEZAD Group', 'uae'), ('Ajman Free Zone Authority', 'uae'), ('Hamriyah Free Zone Authority', 'uae'),
      ('Fujairah Free Zone Authority', 'uae'), ('Umm Al Quwain Free Trade Zone Authority', 'uae'), ('Abu Dhabi Registration and Licensing Authority', 'uae'),
      ('دائرة الاقتصاد والسياحة', 'uae'), ('Sharjah Media City (Shams)', 'uae'), ('Dubai International Financial Centre', 'uae')) v(name, want) loop
    if public.fn_licence_authority_class(r.name) is distinct from r.want then
      bad := bad || format('%s -> %s (want %s); ', r.name, public.fn_licence_authority_class(r.name), r.want);
    end if;
  end loop;
  if public.fn_licence_authority_norm('Department of Economy & Tourism') is distinct from 'department of economy and tourism' then
    bad := bad || 'norm of the ampersand spelling is ' || public.fn_licence_authority_norm('Department of Economy & Tourism') || '; ';
  end if;
  if public.fn_licence_authority_norm('Abu-Dhabi  Dept. (ADDED)') is distinct from 'abu dhabi dept added' then
    bad := bad || 'a name with no ampersand normalises differently: ' || public.fn_licence_authority_norm('Abu-Dhabi  Dept. (ADDED)') || '; ';
  end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when bad = '' then 'PROBE OK' else 'PROBE FAILED: ' || bad end);
end $$;
