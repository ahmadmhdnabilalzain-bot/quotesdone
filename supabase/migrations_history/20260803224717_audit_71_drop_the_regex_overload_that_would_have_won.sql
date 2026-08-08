-- AUDIT 7.1, second half. The previous migration would have been INERT without this one.
--
-- fn_dept_authority gained an optional p_amount_aed parameter, so `create or replace` did not replace
-- anything: it created fn_dept_authority(text,text,numeric) ALONGSIDE the existing
-- fn_dept_authority(text,text). Postgres resolves a two-argument call to the exact two-argument
-- signature in preference to a three-argument one with a default, so intent_router - the single live
-- caller - would have carried on running the regex, and every measurement of the new behaviour would
-- have been taken through the new function while production used the old one.
--
-- This is the same shape as the six-argument matcher overload dropped on 3 Aug
-- (20260803162356). Adding a defaulted parameter is not editing a function, it is publishing a
-- second one, and the older, narrower signature wins.
--
-- Verified before dropping: the only caller anywhere is intent_router/index.ts, which calls it with
-- two arguments and will resolve to the three-argument version once this is gone.
drop function if exists public.fn_dept_authority(text, text);

do $$
declare n int;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'fn_dept_authority';
  if n <> 1 then
    raise exception 'fn_dept_authority must have exactly one signature, found %', n;
  end if;

  -- Assert the invariant the whole item is about: nothing in the authority path decides by regex
  -- over the class name any more.
  if exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public'
                and p.proname in ('fn_dept_authority','fn_ops_authority_check')
                and p.prosrc ilike '%money|payout|payment%') then
    raise exception 'an authority function still caps by regex over the action class name';
  end if;
end $$;;
