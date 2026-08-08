-- Defect found by the behavioural test of the previous migration, before it could reach anyone.
--
-- fn_freeze_supplier_brief read inquiries_supplier_safe to build the snapshot. That view now
-- PREFERS the frozen brief, so after the first freeze the function was reading its own output:
-- the sha never changed, "unchanged" was returned forever, and a genuine re-dispatch after the
-- buyer edited their inquiry would never have produced version 2. Suppliers on the second
-- dispatch would have been shown the first brief.
--
-- Split the two roles explicitly:
--   inquiries_supplier_live  - the live masked projection. The freeze function reads this.
--   inquiries_supplier_safe  - what readers get: the frozen brief when one exists, else live.

create or replace view public.inquiries_supplier_live as
select
  i.id, i.category, i.emirate, i.role_needed, i.status, i.created_at, i.scope_type,
  i.trades, i.keywords, i.brief_source, i.urgency, i.boq_confidence,
  i.drawing_redacted_paths, i.outcome, i.hired_supplier_id,
  i.summary_masked      as summary,
  i.raw_input_masked    as raw_input,
  i.budget_masked       as budget,
  i.spec_masked         as spec,
  i.boq_masked          as boq,
  i.completeness_masked as completeness
from public.inquiries i;

revoke all on public.inquiries_supplier_live from public, anon, authenticated;

create or replace function public.fn_freeze_supplier_brief(p_inquiry_id uuid, p_reason text default 'dispatch')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_brief jsonb; v_sha text; v_prev_sha text; v_ver integer;
begin
  -- MUST read the live projection. Reading inquiries_supplier_safe here would mean reading the
  -- previously frozen brief back, and no later change could ever be detected.
  select to_jsonb(s) - 'status' - 'outcome' - 'hired_supplier_id'
    into v_brief from public.inquiries_supplier_live s where s.id = p_inquiry_id;
  if v_brief is null then
    return jsonb_build_object('frozen', false, 'reason', 'inquiry_not_found');
  end if;
  v_sha := encode(sha256(convert_to(v_brief::text, 'UTF8')), 'hex');
  select b.brief_sha256, b.version into v_prev_sha, v_ver
    from public.inquiry_supplier_brief b where b.inquiry_id = p_inquiry_id order by b.version desc limit 1;
  if v_prev_sha is not null and v_prev_sha = v_sha then
    return jsonb_build_object('frozen', false, 'reason', 'unchanged', 'version', v_ver, 'sha256', v_sha);
  end if;
  insert into public.inquiry_supplier_brief(inquiry_id, version, frozen_reason, brief, brief_sha256)
  values (p_inquiry_id, coalesce(v_ver, 0) + 1, coalesce(p_reason, 'dispatch'), v_brief, v_sha)
  returning version into v_ver;
  return jsonb_build_object('frozen', true, 'version', v_ver, 'sha256', v_sha);
end $$;
revoke execute on function public.fn_freeze_supplier_brief(uuid, text) from public, anon, authenticated;;
