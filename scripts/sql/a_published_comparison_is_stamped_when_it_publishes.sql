-- A PUBLISHED COMPARISON IS STAMPED AT THE MOMENT IT PUBLISHES.
--
-- The publication time of a comparison is set by the transition that publishes it, not by whoever
-- writes the row. A stamp supplied by a caller is a claim about when something happened; this one
-- is a measurement.
--
-- This file carries the definition that is deployed on production, taken from pg_get_functiondef.
-- It is a repository reorganisation: the routine was written inside a file whose name belonged to a
-- programme that no longer exists, and the routine outlived it. Nothing about the behaviour changes.

CREATE OR REPLACE FUNCTION public.fn_quote_comparison_publication_stamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.publication_state = 'PUBLISHED' and NEW.published_at is null then
    NEW.published_at := now();
  end if;
  -- Leaving PUBLISHED does not erase when it was published; that is a fact about the past.
  return NEW;
end $function$;
