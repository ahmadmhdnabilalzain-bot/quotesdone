-- PostgREST only exposes functions in the API schemas, and kb_stage is deliberately not one of
-- them. This wrapper is the single public entry point, callable by service_role only, so the
-- rollback path stays testable from the importer without opening the staging schema to the API.
create or replace function public.rollback_ingestion_run(p_run_id uuid)
returns jsonb language sql security definer set search_path = kb_stage, public as $$
  select kb_stage.rollback_ingestion_run(p_run_id);
$$;
revoke all on function public.rollback_ingestion_run(uuid) from public, anon, authenticated;
grant execute on function public.rollback_ingestion_run(uuid) to service_role;
