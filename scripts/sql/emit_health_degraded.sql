-- The CTO subscribes to `health.degraded` — "OS interface: Technology OS consumes health.degraded"
-- — and that name has never been emitted. Meanwhile `os.health_changed` has fired 21 times and its
-- payload carries both numbers: leadership 81 -> 75 and marketplace 75 -> 69 at 04:45 TODAY, two
-- operating systems degrading with nobody woken.
--
-- Same class as the `inquiry.created` / `rfq.created` dead-name fix, but the honest repair is not to
-- repoint the subscription: CHANGED is not DEGRADED, and a health improvement should not page the
-- CTO. This derives the narrower event from the wider one, and only when the score actually fell.
--
-- fn_os_review is the emitter of os.health_changed and is 8 KB; a trigger keeps the change additive
-- rather than rewriting a routine that already works. No recursion: the WHEN clause fires only for
-- os.health_changed, and what it emits is a different type.
create or replace function public.fn_emit_health_degraded()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  perform fn_emit('health.degraded', 'operating_system', coalesce(new.payload->>'os_key','unknown'),
    'os_review',
    jsonb_build_object('os_key', new.payload->>'os_key',
                       'score', (new.payload->>'score')::numeric,
                       'previous_score', (new.payload->>'previous_score')::numeric,
                       'drop', (new.payload->>'previous_score')::numeric - (new.payload->>'score')::numeric,
                       'health', new.payload->>'health',
                       'period', new.payload->>'period',
                       'source_event', new.id));
  return null;
end $$;
drop trigger if exists trg_emit_health_degraded on public.company_event;
create trigger trg_emit_health_degraded after insert on public.company_event
  for each row
  when (new.event_type = 'os.health_changed'
        and new.payload ? 'previous_score' and new.payload ? 'score'
        and (new.payload->>'score') ~ '^[0-9.]+$' and (new.payload->>'previous_score') ~ '^[0-9.]+$'
        and (new.payload->>'score')::numeric < (new.payload->>'previous_score')::numeric)
  execute function public.fn_emit_health_degraded();

revoke execute on function public.fn_emit_health_degraded() from public, anon, authenticated;
