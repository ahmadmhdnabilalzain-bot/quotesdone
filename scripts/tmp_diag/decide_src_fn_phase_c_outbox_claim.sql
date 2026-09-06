CREATE OR REPLACE FUNCTION public.fn_phase_c_outbox_claim(p_limit integer DEFAULT 20)
 RETURNS SETOF phase_c_event_outbox
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return query
  update public.phase_c_event_outbox o set status = 'claimed', claimed_at = now(), attempts = o.attempts + 1
  where o.outbox_id in (
    select outbox_id from public.phase_c_event_outbox
    where status in ('pending','retry_wait') and next_attempt_at <= now()
    order by outbox_id for update skip locked limit greatest(1, coalesce(p_limit, 20)))
  returning *;
end $function$
