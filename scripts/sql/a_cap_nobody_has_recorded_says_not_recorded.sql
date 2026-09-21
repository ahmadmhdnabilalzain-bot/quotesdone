-- A CAP NOBODY HAS RECORDED SAYS "NOT RECORDED".
-- Assigned: it_engineer (the rule belongs to duty 22, provider usage against caps). 22 Sep 2026.
--
-- ══ MEASURED, 22 Sep 2026, htdblwldjkcgjvmqkbeh, read-only ════════════════════════════════════════
-- it_threshold has two NULL caps: cap_vercel_charges_month and floor_twilio_balance. Both bases read
--   "set by the accountant on 21 Sep 2026 from: needs the founder's dashboard …". #784
--   (the_open_account_facts_of_21_september_are_recorded.sql) called fn_it_cap_set(key, NULL, …), and
--   fn_it_cap_set writes 'set by the <seat>' whatever the value. So an EMPTY cap reads like a recorded
--   one — the confusion two standing checks exist to prevent, and both are red against production:
--     scripts/checks/a_configuration_gap_is_recorded_once_not_every_tick.test.mjs:99
--       "cap_vercel_charges_month is null and does not say it is not recorded"
--     scripts/checks/it_engineer_duties_9_to_18.test.mjs:34
--       [cap_vercel_charges_month, floor_twilio_balance] expected []
--   Both caps are still the founder's to set (the_founders_decisions_of_21_september_… leaves their
--   cap_unknown findings open), so NULL is right; only the wording lies.
--
-- ══ CHANGES ══════════════════════════════════════════════════════════════════════════════════════
-- 1. fn_it_cap_set: a NULL value writes 'not recorded: <source> (noted by the <seat> on <date>)'; a
--    value writes 'set by the <seat> on <date> from: <source>' exactly as before.
-- 2. The two live rows are rewritten to that shape, keeping their measured source text.
--
-- ══ NOT CHANGED ══════════════════════════════════════════════════════════════════════════════════
-- Validation in fn_it_cap_set (key shape, seat list, source required, value > 0). No cap value. The
-- #784 file's one-time apply probe asserted no basis began 'not recorded'; it is superseded by this
-- file and by the two standing checks above, which state the enduring rule.
--
-- Prevented by: the two checks named above (red today, green after this apply) and the verdict row below.
-- Apply: node scripts/apply_sql.mjs scripts/sql/a_cap_nobody_has_recorded_says_not_recorded.sql --apply --ddl

create or replace function public.fn_it_cap_set(p_key text, p_value numeric, p_by text, p_source text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if coalesce(p_key, '') !~ '^(cap|floor)_[a-z0-9_]+$' or p_key = 'cap_warn_ratio' then
    raise exception 'fn_it_cap_set sets a provider cap (cap_*) or floor (floor_*), not %', coalesce(p_key, 'nothing');
  end if;
  if p_by is null or p_by not in ('accountant', 'ceo', 'founder', 'it_engineer') then
    raise exception 'a cap is set by the accountant, the ceo, the founder or the it_engineer, not %', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_source), '') = '' then raise exception 'say where the cap comes from: the plan page or the invoice'; end if;
  if p_value is not null and p_value <= 0 then raise exception 'a cap must be above zero, or NULL for not recorded'; end if;
  update public.it_threshold
     set value = p_value,
         basis = left(case when p_value is null
                           then 'not recorded: ' || p_source || ' (noted by the ' || p_by || ' on '
                                || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || ')'
                           else 'set by the ' || p_by || ' on ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY')
                                || ' from: ' || p_source end, 500)
   where key = p_key;
  if not found then raise exception 'no cap % in public.it_threshold', p_key; end if;
  return jsonb_build_object('key', p_key, 'value', p_value, 'set_by', p_by);
end $function$;

revoke execute on function public.fn_it_cap_set(text, numeric, text, text) from public, anon, authenticated;

-- 2. The two NULL rows, rewritten in place: the source text after "from: " is kept verbatim.
update public.it_threshold
   set basis = left('not recorded: ' || substring(basis from 'from: (.*)$') || ' (noted by the accountant on 21 Sep 2026)', 500)
 where key in ('cap_vercel_charges_month', 'floor_twilio_balance')
   and value is null and basis like 'set by the accountant on 21 Sep 2026 from: %';

-- VERDICT: one row. Every NULL provider cap says it is not recorded; every valued one keeps provenance.
select case when not exists (select 1 from public.it_threshold
                              where key ~ '^(cap|floor)_' and key <> 'cap_warn_ratio' and value is null
                                and basis not like 'not recorded:%')
             and not exists (select 1 from public.it_threshold
                              where key ~ '^(cap|floor)_' and key <> 'cap_warn_ratio' and value is not null
                                and basis !~* 'set by the|includes|plan')
             and not has_function_privilege('anon', 'public.fn_it_cap_set(text,numeric,text,text)'::regprocedure, 'execute')
            then 'PROBE OK' else 'PROBE FAILED' end as verdict;
