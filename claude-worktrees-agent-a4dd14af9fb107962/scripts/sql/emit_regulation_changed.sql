-- `regulation.changed` has TEN active subscribers and has never been emitted once. The part-6 brief
-- put that down to `compliance_sources` being empty; measured 2026-08-10 it holds **17 active UAE
-- authorities** — Dubai Municipality, DEWA, RTA, Trakhees, SIRA, DHA, ADIBC, Estidama, TDRA and the
-- rest — all checked as recently as **04:18 today**, 16 carrying a content signature, 16 with a
-- downloaded document and **4 with a recorded change**. The watcher works.
--
-- What is missing is the emit. A change lands in `compliance_sources.last_changed_at` and is raised
-- as a `compliance_update` action, and the bus is never told, so ten subscribers wait on a name
-- nothing produces. Same shape as the five emitters added earlier today, with a real source behind
-- it: this fires only when last_changed_at actually moves.
create or replace function public.fn_emit_regulation_changed()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  perform fn_emit('regulation.changed', 'compliance_source', new.id::text, 'compliance',
    jsonb_build_object('authority', new.authority, 'topic', new.topic, 'url', new.url,
                       'summary', left(coalesce(new.last_summary,''), 600),
                       'previous_change', old.last_changed_at));
  return null;
end $$;
drop trigger if exists trg_emit_regulation_changed on public.compliance_sources;
create trigger trg_emit_regulation_changed after update of last_changed_at on public.compliance_sources
  for each row
  when (new.last_changed_at is not null
        and coalesce(old.last_changed_at, '-infinity'::timestamptz) is distinct from new.last_changed_at)
  execute function public.fn_emit_regulation_changed();

-- Postgres grants EXECUTE to PUBLIC on every new function, and this one is SECURITY DEFINER, so
-- without this line it joins the anon-executable count the founder is working through.
revoke execute on function public.fn_emit_regulation_changed() from public, anon, authenticated;
