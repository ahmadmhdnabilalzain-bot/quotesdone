-- THE OS IS OPEN TO EVERY SIGNED-IN PERSON.
--
-- The single predicate the OS row policies call. It is deliberately one place: an access rule
-- spread across forty policies is forty rules that can disagree, and this one is read by all of
-- them.
--
-- This file carries the definition that is deployed on production, taken from pg_get_functiondef.
-- It is a repository reorganisation: the routine was written inside a file whose name belonged to a
-- programme that no longer exists, and the routine outlived it. Nothing about the behaviour changes.

CREATE OR REPLACE FUNCTION public.fn_os_open_access()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select state = 'open' from public.os_open_access_log order by id desc limit 1), false);
$function$;
