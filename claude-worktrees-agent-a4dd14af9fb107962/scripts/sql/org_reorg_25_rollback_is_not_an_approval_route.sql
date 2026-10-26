-- REORGANISING THE AGENT COMPANY - 25: rollback was a way to activate a never-approved prompt.
--
-- fn_prompt_rollback existence check, before this file:
--
--   if not exists(select 1 from prompt_versions where prompt_key=p_key and version=p_to_version)
--
-- It does not look at status. So "rolling back" to a DRAFT that no one ever approved sets it
-- status='active' and points prompts.active_version at it. The approval gate - fn_prompt_approve_draft,
-- which exists precisely so a prompt reaches production only after someone signs it - is bypassed
-- entirely by calling the rollback function instead. Rollback is meant to RESTORE a version that
-- was already trusted, not to confer trust on one that never was.
--
-- Latent rather than exploited: prompt_versions is empty on staging today, so nothing has gone
-- through this path. That is the reason to fix it now rather than the reason not to.
--
-- Two more defects in the same four lines:
--
--   * `set status='active', approved_by=p_by` OVERWRITES the record of who approved that version
--     with whoever happened to run the rollback. The approver of v3 is not the person restoring it.
--     Restoring a version must not rewrite its history.
--   * rollout_pct is never set, so a version restored from a partial rollout goes active at
--     whatever percentage it was cut off at - possibly 0, which is "active" serving nobody.
--
-- The refusal returns a reason rather than a bare error, so a caller that hits it learns that the
-- right route is the approval gate.

begin;

create or replace function public.fn_prompt_rollback(p_key text, p_to_version integer, p_by text default 'agent'::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_status text; v_approved text;
begin
  select status, approved_by into v_status, v_approved
    from prompt_versions where prompt_key = p_key and version = p_to_version;

  if v_status is null then
    return jsonb_build_object('error', 'version not found');
  end if;

  -- ROLLBACK RESTORES TRUST, IT DOES NOT CONFER IT.
  if v_approved is null or v_status not in ('deprecated', 'active') then
    return jsonb_build_object(
      'error', 'refused',
      'reason', format(
        'version %s of %s is %s and was approved by %s, so it has never been trusted in '
        || 'production. Rollback restores a version that was previously approved; it is not a '
        || 'route to activate one that was not. Use fn_prompt_approve_draft to approve it first.',
        p_to_version, p_key, v_status, coalesce(v_approved, 'nobody')),
      'status', v_status, 'approved_by', v_approved);
  end if;

  update prompt_versions set status = 'deprecated'
   where prompt_key = p_key and status = 'active';

  -- approved_by is NOT touched: it records who approved this version, not who restored it.
  -- rollout_pct is set, or a version cut off mid-rollout returns to serving that fraction.
  update prompt_versions set status = 'active', rollout_pct = 100
   where prompt_key = p_key and version = p_to_version;

  update prompts set active_version = p_to_version, updated_at = now() where key = p_key;

  return jsonb_build_object('ok', true, 'active_version', p_to_version,
    'approved_by', v_approved, 'rolled_back_by', p_by);
end $function$;

commit;
