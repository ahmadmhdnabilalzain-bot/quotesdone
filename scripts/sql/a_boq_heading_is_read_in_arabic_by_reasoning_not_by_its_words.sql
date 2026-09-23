-- A BOQ HEADING IS READ IN ARABIC BY REASONING, NOT BY ITS WORDS — decision point documents.boq_arabic.
-- Seat: sales_engineer. 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
--
-- WHY. The supplier inbox printed a BOQ section's Arabic heading from a regex list over the section's words
-- (supabase/functions/_shared/boq_arabic.ts SECTION_AR, "\bceilings?\b|\bbulkheads?\b" -> الأسقف) with a
-- service-alias fallback: meaning decided by word matching. It now asks think() which glossary heading a
-- section means (_shared/reasoned_documents.ts sectionReading), over the served, gated BOQ only.
--
-- WHAT.
--   * public.boq_section_reading — one reasoned reading per section text (trimmed, lower-cased key), so a
--     heading is reasoned once, not on every inbox read. Service role only (RLS on, one policy).
--   * public.fn_reason_apply_documents__boq_arabic(p_id, p_result) — the replay effect fn_reason_held_resolve
--     calls (a_reasoned_answer_is_applied_by_its_own_surface.sql) when a heading held under the model hold is
--     reasoned: it writes the reasoned choice for the held row's subject.section_key. It reads no free text:
--     the key and the choice come from the held row and the reasoned result.
-- MEASURED. Headings are free text: drawing_boq/boq_from_sheet.ts copies a spreadsheet's own heading rows.
-- Pending: scripts/sql/pending/a_boq_heading_is_read_in_arabic_by_reasoning_not_by_its_words.txt.

create table if not exists public.boq_section_reading (
  section_key  text primary key check (btrim(section_key) <> '' and length(section_key) <= 200),
  section      text not null check (length(section) <= 200),
  reading      text not null check (reading ~ '^[a-z_]+$'),
  reasoned_by  text not null default 'reasoning' check (reasoned_by in ('reasoning', 'replay')),
  held_id      bigint,
  reasoned_at  timestamptz not null default now()
);
alter table public.boq_section_reading enable row level security;
drop policy if exists boq_section_reading_service_role_only on public.boq_section_reading;
create policy boq_section_reading_service_role_only on public.boq_section_reading
  for all to service_role using (true) with check (true);
revoke all on public.boq_section_reading from public, anon, authenticated;
grant select, insert, update on public.boq_section_reading to service_role;

create or replace function public.fn_reason_apply_documents__boq_arabic(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_key text; v_choice text;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  v_key := nullif(btrim(r.subject ->> 'section_key'), '');
  v_choice := nullif(p_result #>> '{decision,choice}', '');
  if v_key is null or v_choice is null or v_choice !~ '^[a-z_]+$' then
    return jsonb_build_object('applied', false, 'reason', 'no section key or no reasoned choice');
  end if;
  insert into public.boq_section_reading (section_key, section, reading, reasoned_by, held_id)
  values (left(v_key, 200), left(coalesce(r.subject ->> 'section', v_key), 200), v_choice, 'replay', p_id)
  on conflict (section_key) do update set reading = excluded.reading, reasoned_by = 'replay', held_id = excluded.held_id, reasoned_at = now();
  return jsonb_build_object('applied', true, 'section_key', v_key, 'reading', v_choice);
end
$fn$;
revoke execute on function public.fn_reason_apply_documents__boq_arabic(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_documents__boq_arabic(bigint, jsonb) to service_role;
