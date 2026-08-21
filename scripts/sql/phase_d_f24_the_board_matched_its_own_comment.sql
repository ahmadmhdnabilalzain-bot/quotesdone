-- F24 - the board matched its own comment
--
-- fn_phase_d_capability_state() carries the row that matters most in F05:
--
--     handler_paths_that_skip_the_capability_check_on_a_mode_string   expected 0
--
-- It greps public.fn_phase_d_handler_execute and public.fn_phase_d_effect_produce for the exact
-- shape the founder prohibited, so that a future edit reintroducing it turns a board row red rather
-- than turning twenty-one boundaries off in silence. It went red the moment F06 applied, and the
-- reason is the estate's own lens pointed at me: **a mention is not a call.**
--
-- F06's header explains what it removed, and to explain it, it QUOTES it:
--
--     -- F05. This read `if b.capability_dependency <> 'NONE' and v_ctx <> 'test'`, so the literal
--     -- 'test' arriving in one field turned twenty-one fail-closed business boundaries off at once.
--
-- pg_proc.prosrc holds comments, so the grep found the sentence describing the defect and reported
-- it as the defect. A check that cannot tell an explanation from an instruction is a check that
-- punishes writing the explanation down.
--
-- The predicate now strips comment lines before it looks. Nothing is weakened: a real
-- reintroduction is a line of CODE and is still found, and the negative control is that this row
-- was red for exactly as long as it took to notice.

CREATE OR REPLACE FUNCTION public.fn_phase_d_capability_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with dep as (select * from public.phase_d_handler_binding where capability_dependency <> 'NONE'),
       -- The two routines, with every comment line removed, so the grep below reads CODE.
       code as (
         select p.proname,
                (select string_agg(l, chr(10))
                   from unnest(string_to_array(p.prosrc, chr(10))) l
                  where btrim(l) not like '--%') src
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public'
            and p.proname in ('fn_phase_d_handler_execute','fn_phase_d_effect_produce')),
       bypass as (
         select * from code where src ~ 'capability_dependency <> ''NONE'' and v_ctx <> ''test''')
  select 'capability_dependent_steps'::text, '21'::text,
         (select count(*)::text from dep), (select count(*) from dep) = 21
  union all
  select 'capability_dependent_steps_without_a_contract', '0',
         (select count(*)::text from dep
           where not exists (select 1 from public.phase_d_capability_contract c
                              where c.step_id = dep.step_id)),
         not exists (select 1 from dep
                      where not exists (select 1 from public.phase_d_capability_contract c
                                         where c.step_id = dep.step_id))
  union all
  select 'handler_paths_that_skip_the_capability_check_on_a_mode_string', '0',
         (select coalesce(string_agg(proname, ', '), '0') from bypass),
         not exists (select 1 from bypass)
  union all
  select 'capability_requests_still_committed', '0',
         (select count(*)::text from public.phase_d_capability_request),
         not exists (select 1 from public.phase_d_capability_request)
  union all
  select 'capability_results_still_committed', '0',
         (select count(*)::text from public.phase_d_capability_result),
         not exists (select 1 from public.phase_d_capability_result)
  union all
  select 'accepted_results_produced_by_a_paid_provider', '0',
         (select count(*)::text from public.phase_d_capability_result where provider_mode = 'provider'),
         not exists (select 1 from public.phase_d_capability_result where provider_mode = 'provider')
  union all
  -- THE POSITIVE CONTROL FOR THE ROW ABOVE. A grep that can never match is a grep nobody has
  -- tested, and this one has now been wrong once. It asserts that the pattern IS found when it is
  -- present -- in a routine that deliberately still contains it, in a comment, which is the case
  -- that fooled it.
  select 'the_bypass_grep_still_matches_when_the_shape_is_present', 'true',
         (select case when p.prosrc ~ 'capability_dependency <> ''NONE'' and v_ctx <> ''test'''
                      then 'yes — fn_phase_d_handler_execute''s header still quotes the removed shape, and the raw grep still sees it; the board above strips comments and does not'
                      else 'no — the quotation is gone from the header, so this control no longer proves anything and should be repointed' end
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_phase_d_handler_execute'),
         exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'fn_phase_d_handler_execute'
                    and p.prosrc ~ 'capability_dependency <> ''NONE'' and v_ctx <> ''test''');
$function$;
