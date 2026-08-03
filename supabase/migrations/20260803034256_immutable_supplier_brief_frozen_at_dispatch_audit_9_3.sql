-- Audit 9.3 "Immutable supplier_safe_brief" — completing it.
--
-- inquiries_supplier_safe already gave a single supplier-facing projection with hardened
-- write-time masking. What it did not give is IMMUTABILITY: it reads the live inquiry row, so the
-- brief a supplier quoted against could change underneath them, silently, after dispatch.
--
-- This freezes the brief at dispatch. Deliberately partial by design: the fields a supplier QUOTES
-- AGAINST are frozen; status, outcome and hired_supplier_id stay live because a supplier needs the
-- current state of the job, not the state at dispatch.
--
-- Re-dispatch after the buyer adds information writes a NEW VERSION rather than mutating the old
-- one, so the history of what was shown, and when, survives.

create table if not exists public.inquiry_supplier_brief (
  id            bigserial primary key,
  inquiry_id    uuid not null references public.inquiries(id) on delete cascade,
  version       integer not null,
  frozen_at     timestamptz not null default now(),
  frozen_reason text not null default 'dispatch',
  brief         jsonb not null,
  brief_sha256  text not null,
  unique (inquiry_id, version)
);
create index if not exists inquiry_supplier_brief_inquiry_idx on public.inquiry_supplier_brief(inquiry_id, version desc);
alter table public.inquiry_supplier_brief enable row level security;
revoke all on public.inquiry_supplier_brief from public, anon, authenticated;

-- Append-only. A frozen brief is evidence of what a supplier was shown; it is never edited.
-- DELETE is left available so removing an inquiry can cascade; UPDATE is refused outright.
create or replace function public.trg_supplier_brief_immutable() returns trigger
language plpgsql set search_path to 'public','pg_temp' as $$
begin raise exception 'inquiry_supplier_brief is append-only: freeze a new version instead of editing version %', OLD.version; end $$;
drop trigger if exists supplier_brief_immutable on public.inquiry_supplier_brief;
create trigger supplier_brief_immutable before update on public.inquiry_supplier_brief
  for each row execute function public.trg_supplier_brief_immutable();

create or replace function public.fn_jsonb_text_array(j jsonb) returns text[]
language sql immutable set search_path to 'public','pg_temp' as $$
  select case when j is null or jsonb_typeof(j) <> 'array' then null
              else (select array_agg(x) from jsonb_array_elements_text(j) x) end;
$$;

-- Freeze the current supplier-safe projection. Idempotent: refreezing identical content is a
-- no-op, so a retried dispatch does not inflate the version history.
create or replace function public.fn_freeze_supplier_brief(p_inquiry_id uuid, p_reason text default 'dispatch')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_brief jsonb; v_sha text; v_prev_sha text; v_ver integer;
begin
  select to_jsonb(s) - 'status' - 'outcome' - 'hired_supplier_id'
    into v_brief from public.inquiries_supplier_safe s where s.id = p_inquiry_id;
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
revoke execute on function public.fn_freeze_supplier_brief(uuid, text) from public, anon, authenticated;

-- Serve the frozen brief when one exists. Every reader of inquiries_supplier_safe inherits this,
-- so supplier_api needs no further change and no future endpoint can accidentally bypass it.
create or replace view public.inquiries_supplier_safe as
select
  i.id,
  case when b.brief is not null then b.brief->>'category'      else i.category      end as category,
  case when b.brief is not null then b.brief->>'emirate'       else i.emirate       end as emirate,
  case when b.brief is not null then b.brief->>'role_needed'   else i.role_needed   end as role_needed,
  i.status,
  case when b.brief is not null then (b.brief->>'created_at')::timestamptz else i.created_at end as created_at,
  case when b.brief is not null then b.brief->>'scope_type'    else i.scope_type    end as scope_type,
  case when b.brief is not null then public.fn_jsonb_text_array(b.brief->'trades')   else i.trades   end as trades,
  case when b.brief is not null then public.fn_jsonb_text_array(b.brief->'keywords') else i.keywords end as keywords,
  case when b.brief is not null then b.brief->>'brief_source'  else i.brief_source  end as brief_source,
  case when b.brief is not null then b.brief->>'urgency'       else i.urgency       end as urgency,
  case when b.brief is not null then b.brief->>'boq_confidence' else i.boq_confidence end as boq_confidence,
  case when b.brief is not null then public.fn_jsonb_text_array(b.brief->'drawing_redacted_paths') else i.drawing_redacted_paths end as drawing_redacted_paths,
  i.outcome,
  i.hired_supplier_id,
  case when b.brief is not null then b.brief->>'summary'   else i.summary_masked      end as summary,
  case when b.brief is not null then b.brief->>'raw_input' else i.raw_input_masked    end as raw_input,
  case when b.brief is not null then b.brief->>'budget'    else i.budget_masked       end as budget,
  case when b.brief is not null then b.brief->'spec'         else i.spec_masked         end as spec,
  case when b.brief is not null then b.brief->'boq'          else i.boq_masked          end as boq,
  case when b.brief is not null then b.brief->'completeness' else i.completeness_masked end as completeness
from public.inquiries i
left join lateral (
  select b2.brief from public.inquiry_supplier_brief b2
  where b2.inquiry_id = i.id order by b2.version desc limit 1
) b on true;;
