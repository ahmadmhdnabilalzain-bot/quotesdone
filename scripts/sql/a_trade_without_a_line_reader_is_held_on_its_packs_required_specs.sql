-- A TRADE WITHOUT A LINE READER IS HELD ON ITS PACK'S REQUIRED SPECS.
-- Seat: sales_engineer (the quote hold desk); built by it_engineer. 23 Sep 2026.
--
-- WHAT WAS WRONG. The founder's rule is "exact specs or the quote is held". The line readers in
-- supabase/functions/_shared/line_specs/model.ts cover the trades they were written for; PR #881 adds 153
-- trades and 123 of them have no reader, so a quote in one of those trades was never asked a single spec
-- and could not be held. The answer is not 123 more regex readers (founder_instruction 886-903: no word
-- matching). The trade KNOWLEDGE PACKS already say what an exact quote must state: every pack's
-- spec_checklist entries carry required_specs (measured 23 Sep 2026: 42 of 42 verified packs have them).
--
-- WHAT THIS ADDS.
--   * public.trade_spec_checklist: one row per checklist of a trade pack — its topic and its required
--     specs, each with a stable code (spec_<words>) and the English sentence the pack wrote. Loaded by
--     scripts/kb/load_trade_spec_checklists.mjs from the packs; the pack is the source, this is its copy.
--   * public.fn_trade_spec_checklist(p_category): the checklists of an inquiry's category, through the
--     taxonomy's own mapping (fn_taxonomy_trades_for: 'glass' -> glass, glazing).
-- Which checklist a quote is priced against, and whether each line states each spec, is judged by
-- reasoning (_shared/line_specs/reasoned_specs.ts, think()). Under the model hold nothing is judged and
-- every required spec is asked, so the quote is held until it is stated.
--
-- WHAT IT DOES NOT DO. It does not change a trade that has a reader, and it holds nothing for a trade with
-- no checklist (the gate logs that gap instead of holding on an empty list). Pending until applied:
-- scripts/sql/pending/a_trade_without_a_line_reader_is_held_on_its_packs_required_specs.txt.

create table if not exists public.trade_spec_checklist (
  trade_code   text not null check (trade_code ~ '^[a-z0-9_-]+$'),
  topic_id     text not null check (btrim(topic_id) <> ''),
  topic        text not null check (btrim(topic) <> ''),
  specs        jsonb not null check (jsonb_typeof(specs) = 'array' and jsonb_array_length(specs) > 0),
  source_pack  text not null,
  loaded_at    timestamptz not null default now(),
  primary key (trade_code, topic_id)
);
alter table public.trade_spec_checklist enable row level security;
drop policy if exists trade_spec_checklist_service_role_only on public.trade_spec_checklist;
create policy trade_spec_checklist_service_role_only on public.trade_spec_checklist
  as permissive for all to public using (false) with check (false);
revoke all on public.trade_spec_checklist from anon, authenticated;
comment on table public.trade_spec_checklist is
  'What an exact quote in a trade must state, per checklist of the trade''s knowledge pack (spec_checklist.required_specs). Read by fn_trade_spec_checklist; judged against quote lines by reasoning.';

create or replace function public.fn_trade_spec_checklist(p_category text)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('topic_id', c.topic_id, 'topic', c.topic, 'specs', c.specs) order by c.trade_code, c.topic_id), '[]'::jsonb)
    from public.trade_spec_checklist c
   where c.trade_code = p_category
      or c.trade_code = any(coalesce(public.fn_taxonomy_trades_for(array[p_category]), '{}'::text[]))
$fn$;
revoke execute on function public.fn_trade_spec_checklist(text) from public, anon, authenticated;
grant execute on function public.fn_trade_spec_checklist(text) to service_role;
