-- Assigned: sales_engineer
-- PURE PROBE (no DDL, no row written) for a_chamber_of_commerce_or_a_residency_office_is_not_a_licensing_authority.sql. It always ends
-- in raise exception 'CHK<<...>>'. It asks the classifier only: the non-licensing bodies answer 'unknown'; every licensing authority of
-- the corpus, mainland and free zone, still answers 'uae'; a foreign one still 'foreign'.
do $$
declare bad text := ''; r record;
begin
  for r in select * from (values
      ('Dubai Chamber of Commerce and Industry', 'unknown'), ('Dubai Chambers', 'unknown'), ('Abu Dhabi Chamber of Commerce & Industry', 'unknown'),
      ('Sharjah Chamber of Commerce and Industry', 'unknown'), ('غرفة تجارة وصناعة دبي', 'unknown'), ('Dubai Municipality', 'unknown'),
      ('GDRFA Dubai', 'unknown'), ('General Directorate of Residency and Foreigners Affairs - Dubai', 'unknown'), ('Federal Tax Authority', 'unknown'),
      ('Department of Economy and Tourism', 'uae'), ('Dubai Department of Economy and Tourism', 'uae'), ('Dubai Economic Department', 'uae'),
      ('Abu Dhabi Department of Economic Development (ADDED)', 'uae'), ('Sharjah Economic Development Department', 'uae'),
      ('Ajman Department of Economic Development', 'uae'), ('RAK DED', 'uae'), ('Fujairah Department of Economic Development', 'uae'),
      ('Umm Al Quwain Department of Economic Development', 'uae'), ('Dubai Multi Commodities Centre (DMCC)', 'uae'),
      ('Jebel Ali Free Zone Authority (JAFZA)', 'uae'), ('Ras Al Khaimah Economic Zone (RAKEZ)', 'uae'), ('Sharjah Media City (Shams)', 'uae'),
      ('Abu Dhabi Global Market', 'uae'), ('Dubai Airport Free Zone Authority', 'uae'), ('دائرة الاقتصاد والسياحة', 'uae'),
      ('Ministry of Commerce, Saudi Arabia', 'foreign'), ('', 'unread')) v(name, want) loop
    if public.fn_licence_authority_class(r.name) is distinct from r.want then
      bad := bad || format('%s -> %s (want %s); ', r.name, public.fn_licence_authority_class(r.name), r.want);
    end if;
  end loop;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when bad = '' then 'PROBE OK' else 'PROBE FAILED: ' || bad end);
end $$;
