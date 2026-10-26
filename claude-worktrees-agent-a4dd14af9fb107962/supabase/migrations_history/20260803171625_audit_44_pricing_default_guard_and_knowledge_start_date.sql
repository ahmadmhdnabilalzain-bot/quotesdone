-- AUDIT 4.4 "all five surfaces agree" — two of the disagreements are in the database and can be
-- closed here. The rest are Arabic content and are listed in the next-session brief.
--
-- 1. pricing_config's fee column still defaults to 100 with NO value CHECK, while every other
--    surface says 1,000. An order-of-magnitude difference sitting in a column default is the kind
--    of thing that only shows up as a row nobody meant to insert — and the audit found exactly
--    that shape already published: portal_backup_predesign says "AED 100 / year".
-- 2. agent_knowledge#279 still says it "OVERRIDES any pricing figure stated elsewhere" and still
--    contains no 2027 date. A corpus row that claims authority over pricing and omits the start
--    date is worse than one that says nothing: every agent reading it will state the fee as though
--    it applies today.
do $mig$
declare v_col text; v_def text; n int;
begin
  select column_name, column_default into v_col, v_def
    from information_schema.columns
   where table_schema='public' and table_name='pricing_config' and column_name like '%fee%'
   order by ordinal_position limit 1;
  if v_col is null then raise exception '4.4: no fee column on pricing_config — refusing to guess'; end if;

  execute format('alter table public.pricing_config alter column %I set default 1000', v_col);

  -- A ceiling and a floor, not an exact value: the founder may change the price, but not by a
  -- factor of ten by accident. 100 is now outside the permitted range, which is the point.
  if not exists (select 1 from pg_constraint
                  where conrelid='public.pricing_config'::regclass and conname='pricing_config_fee_range_ck') then
    execute format(
      'alter table public.pricing_config add constraint pricing_config_fee_range_ck check (%I is null or (%I >= 500 and %I <= 5000))',
      v_col, v_col, v_col);
  end if;
  raise notice '4.4: pricing_config.% default % -> 1000, range check added', v_col, coalesce(v_def,'null');

  update public.agent_knowledge
     set content = content ||
       E'\n\nSTART DATE (audit 4.4, 3 Aug 2026): the AED 1,000/year supplier subscription begins '
       || '1 August 2027. It is NOT charged before that date. The first 1,000 registered suppliers '
       || 'are exempt PERMANENTLY and never pay it. This row previously claimed to override every '
       || 'other pricing figure while omitting the start date, so any agent reading it would have '
       || 'stated the fee as though it applied today.'
   where id = 279 and content not like '%2027%';
  get diagnostics n = row_count;
  raise notice '4.4: agent_knowledge#279 rows updated = %', n;
end $mig$;;
