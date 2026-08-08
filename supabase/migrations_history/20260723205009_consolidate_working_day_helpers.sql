-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260723205009   name: consolidate_working_day_helpers
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #97 consolidation: single source of truth for the working-day rule = fn_is_working_day.
-- The date overload's inline weekday+holiday predicate was proven equivalent to
-- fn_is_working_day (0 mismatches across all 365 days of 2026 incl. 13 holidays); delegate to it.
CREATE OR REPLACE FUNCTION public.add_working_days(d date, n integer)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cur date := d; added int := 0;
begin
  while added < n loop
    cur := cur + 1;
    if public.fn_is_working_day(cur) then added := added + 1; end if;
  end loop;
  return cur;
end;$function$;

-- Drop the redundant, timezone-buggy timestamptz overload. It read isodow off the raw
-- UTC timestamp but checked holidays in Dubai-local date, so near midnight Dubai it
-- diverged by a full working day from the Dubai-correct fn_add_working_days. Its only
-- callers (stripe_confirm, stripe_webhook) were rerouted to fn_add_working_days first.
DROP FUNCTION public.add_working_days(timestamp with time zone, integer);
