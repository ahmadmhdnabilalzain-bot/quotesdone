-- PROBE: a conversation too big to draw is kept as a text copy (2 Nov 2026). Seat: it_engineer.
-- No DDL. Run AFTER a_conversation_too_big_to_draw_is_kept_as_a_text_copy.sql is applied. It counts three attempts on a
-- ZZ DEMO key inside a block whose own raise rolls it back, so nothing is left behind, and checks the grants.
do $probe$
declare f text[] := '{}'; n1 int; n2 int; n3 int;
begin
  if to_regprocedure('public.fn_conversation_archive_attempt(text,text)') is null then
    raise exception 'PROBE FAILED: fn_conversation_archive_attempt(text,text) does not exist';
  end if;
  if has_function_privilege('anon', 'public.fn_conversation_archive_attempt(text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_conversation_archive_attempt(text,text)', 'execute') then
    f := f || text 'anon or authenticated can execute fn_conversation_archive_attempt'; end if;
  if has_table_privilege('anon', 'public.conversation_archive_attempt', 'select') then
    f := f || text 'anon can read conversation_archive_attempt'; end if;
  n1 := public.fn_conversation_archive_attempt('zz_demo_probe', 'zz-demo-1');
  n2 := public.fn_conversation_archive_attempt('zz_demo_probe', 'zz-demo-1');
  n3 := public.fn_conversation_archive_attempt('zz_demo_probe', 'zz-demo-1');
  if (n1, n2, n3) is distinct from (1, 2, 3) then f := f || ('the counter read ' || n1 || ',' || n2 || ',' || n3 || ', not 1,2,3'); end if;
  if cardinality(f) > 0 then raise exception 'PROBE FAILED: %', array_to_string(f, '; '); end if;
  raise exception 'PROBE OK: attempts count 1, 2, 3 per message; only service_role reaches the counter (rolled back)';
end $probe$;
