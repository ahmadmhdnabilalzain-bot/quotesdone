-- PROBE for the_referral_thanks_is_said_in_the_formal_plural.sql. Seat: customer_support. Never applied: it writes nothing and always raises CHK<<...>>. Run after
-- the file. Asserts from the catalogue: the routine's body is exactly the plural version (md5 of prosrc), and it is closed.
do $probe$
declare v_bad text := ''; f regprocedure := 'public.fn_customer_referral_record(uuid,text,text,text)'::regprocedure;
begin
  if (select md5(prosrc) from pg_proc where oid = f) <> '7c248ed7919c328b9505c2d61224274a' then v_bad := v_bad || ' body-not-the-plural-version'; end if;
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then v_bad := v_bad || ' open'; end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK the referral thanks is the formal plural, and the routine is closed>>';
end $probe$;
