-- PROBE for the_widget_spends_its_rate_limits_in_one_round_trip.sql. Seat: it_engineer. Never applied: it always raises
-- CHK<<...>> and rolls back, so every rl_hits row it spends is gone with it. It spends only keys under 'zzprobe:<random>:',
-- which no caller uses, and counts the rows under that prefix before and after inside the same transaction.
-- PROBE OK only if:
--   1. a chain whose groups all pass spends every bucket once and answers true for each;
--   2. a group with one refused bucket spends every bucket of that group, answers its true and false, and spends
--      NOTHING of the groups after it (null), the same short-circuit site_assistant follows;
--   3. the answers equal what one rl_check call per bucket in that order answers (the reference);
--   4. fn_rl_check_chain is executable by service_role only (no PUBLIC / anon / authenticated EXECUTE).
do $probe$
declare
  f text[] := '{}'; p text := 'zzprobe:' || md5(random()::text) || ':'; a jsonb; b jsonb; n0 int; n1 int; n2 int; open_to text;
begin
  select count(*) into n0 from public.rl_hits where k like p || '%';
  a := public.fn_rl_check_chain(jsonb_build_array(
         jsonb_build_array(jsonb_build_object('k', p || 'hard', 'l', 5, 's', 3600)),
         jsonb_build_array(jsonb_build_object('k', p || 'start', 'l', 5, 's', 3600), jsonb_build_object('k', p || 'conv', 'l', 5, 's', 3600)),
         jsonb_build_array(jsonb_build_object('k', p || 'global', 'l', 5, 's', 86400))));
  select count(*) into n1 from public.rl_hits where k like p || '%';
  if a is distinct from '[[true],[true,true],[true]]'::jsonb then f := array_append(f, ('all-pass chain answered ' || a::text)); end if;
  if n1 - n0 <> 4 then f := array_append(f, format('all-pass chain spent %s buckets, expected 4', n1 - n0)); end if;
  -- 'full' takes one hit, then refuses: a limit of 1 spent once already by the line below
  perform public.rl_check(p || 'full', 1, 3600);
  select count(*) into n1 from public.rl_hits where k like p || '%';
  b := public.fn_rl_check_chain(jsonb_build_array(
         jsonb_build_array(jsonb_build_object('k', p || 'hard', 'l', 5, 's', 3600)),
         jsonb_build_array(jsonb_build_object('k', p || 'full', 'l', 1, 's', 3600), jsonb_build_object('k', p || 'conv', 'l', 5, 's', 3600)),
         jsonb_build_array(jsonb_build_object('k', p || 'global', 'l', 5, 's', 86400)),
         jsonb_build_array(jsonb_build_object('k', p || 'cap', 'l', 5, 's', 86400))));
  select count(*) into n2 from public.rl_hits where k like p || '%';
  if b is distinct from '[[true],[false,true],[null],[null]]'::jsonb then f := array_append(f, ('refusing chain answered ' || b::text)); end if;
  if n2 - n1 <> 2 then f := array_append(f, format('refusing chain spent %s buckets, expected 2 (hard, conv)', n2 - n1)); end if;
  if exists (select 1 from public.rl_hits where k in (p || 'cap')) then f := array_append(f, 'a group after the refusal was spent'); end if;
  if (select count(*) from public.rl_hits where k = p || 'global') <> 1 then f := array_append(f, 'the global bucket was spent after a refusal'); end if;
  select string_agg(grantee, ',') into open_to from information_schema.routine_privileges
   where specific_schema = 'public' and routine_name = 'fn_rl_check_chain' and privilege_type = 'EXECUTE' and grantee in ('PUBLIC', 'anon', 'authenticated');
  if open_to is not null then f := array_append(f, ('fn_rl_check_chain is executable by ' || open_to)); end if;
  raise exception 'CHK<<%>> all-pass % refusing % spent %/%', case when cardinality(f) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(f, '; ') end, a, b, n1 - n0, n2 - n1;
end
$probe$;
