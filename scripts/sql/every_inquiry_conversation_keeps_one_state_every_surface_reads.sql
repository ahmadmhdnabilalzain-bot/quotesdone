-- EVERY INQUIRY CONVERSATION KEEPS ONE STATE THAT EVERY SURFACE READS (10 Nov 2026, sales_engineer; founder ledger 1572).
-- Seat: sales_engineer (with customer_support for the shared state: WhatsApp and the website widget write it too).
--
-- MEASURED (design audit of 10 Nov 2026, read-only, production htdblwldjkcgjvmqkbeh):
--   * three customer surfaces (the request chat inquiry_intake, the portal assistant sales_engineer 'assist', WhatsApp and
--     the widget) share nothing but the stored transcript. The request chat keeps slots on its own row (brief.details);
--     the portal rebuilds its state from the transcript by regex on every turn and persists nothing; WhatsApp and the
--     widget keep no state at all. So "New request" after a portal chat opened a BLANK conversation and the customer
--     retold everything (src/components/me/dashboard/Dashboard.tsx, initialText = the homepage draft only).
--   * no per-inquiry message limit existed anywhere (grep for a cap found nothing; the only limit was 60 intake turns an
--     hour per email). The founder, 10 Nov 2026 (ledger 1572): "Hard limit 100 messages per inquiry, and nothing said in
--     message 2 may be forgotten by message 30+."
--   * a customer who said "I don't know" in Egyptian or Lebanese Arabic (mesh 3aref, ma ba3ref, madri) was not recorded as
--     not knowing, so the same spec could be asked again.
--
-- WHAT THIS ADDS:
--   * public.inquiry_state, one row per inquiry conversation (conv_key):
--       'intake:<inquiry_intake.id>'        the request chat
--       '<account key>#<episode start>'     the portal assistant: one job per episode (a confirmed summary starts the next)
--       'wa:<phone>' / '<widget conv id>'   WhatsApp and the widget (count, language and dialect only: no spec state there)
--     It holds the trade, every spec collected with the customer message it came from (specs: key -> {value, turn,
--     first_turn, changed_from, src}), the specs asked and still unanswered with how often (asked: key -> {count,
--     last_turn}), the "customer does not know" answers (unknown: key -> {turn, said}), the language, the dialect and
--     the script, the message count, and the status (open -> converging at 80 -> summarising at 95 -> handed_off at
--     100; carried when a portal chat became a request; closed).
--   * public.fn_inquiry_state_merge(conv_key, surface, patch): the ONE writer. Each surface sends what its own turn
--     established (the extraction the code already runs: no new model call). Merging is deterministic: a new spec is
--     added with its turn; a changed value keeps the earlier one in changed_from; nothing is deleted; a spec given later
--     clears its "does not know"; message_count only grows (a retried turn never counts twice, because the surface sends
--     the count of its own transcript, not +1); the status only moves forward on the open -> handed_off chain.
--   * public.fn_inquiry_state_carry(from_key, to_key, surface, intake_id): the portal chat's state becomes the request's
--     (the request chat opens pre-filled), and the portal episode is marked carried. The count carries too: the limit is
--     per inquiry, wherever its messages were written.
--
-- WHAT THIS DOES NOT DO:
--   * it decides nothing about the conversation. Which question is next, the 80/95/100 stages and "never ask a held or
--     unknown spec again" are code (supabase/functions/_shared/inquiry_state.ts, tested offline); this table is what that
--     code reads and writes.
--   * it does not replace inquiry_intake.brief.details or category_specs: the request's dispatch gate still reads the row's
--     canonical keys (fn_rfq_required_check, trg_rfq_complete), unchanged.
--   * no expert solutioning (condition, options offered, solution catalogue): phase 2 adds those columns.
--
-- PHASE 2 (10 Nov 2026, sales_engineer; founder ledger 1572, 1579 and 1586: "reason like a real expert staff member" for
-- EVERY trade, product and service, not only the PVC example). The same table, never a second store. Four columns, each
-- written only through fn_inquiry_state_merge and carried by fn_inquiry_state_carry:
--   condition        what the customer told us about the thing itself: key -> {value, turn, changed_from} (object,
--                    material, state, location, use, constraints such as a wet area or a children's room)
--   options_offered  the solutions put to them: [{problem, option, turn, src}], each (problem, option) once, at most 60;
--                    problem and option are the codes of supabase/functions/_shared/solution_catalogue.json
--   chosen_option    the one they chose: {problem, option, label, turn, src, changed_from}; a change keeps the earlier
--   budget           {value, turn, changed_from}; a budget given clears a "does not know" on it
-- The service keys a chosen option names go into specs under 'service_keys' (the same merge, changed_from kept), and the
-- taxonomy codes the conversation is about into trade_codes, as before. Added with ALTER ... IF NOT EXISTS so the file
-- applies whether or not phase 1 is already live. What decides WHICH options are offered is not here: the model reasons
-- it from the catalogue and the trade's packs (_shared/solution_catalogue.ts, _shared/inquiry_trades.ts).
--
-- SECURITY: RLS on with a deliberate service-role-only policy, every grant to anon and authenticated revoked; both
-- routines SECURITY DEFINER with search_path pinned and EXECUTE revoked from public, anon and authenticated (CREATE grants
-- EXECUTE to PUBLIC; the edge functions call them as service_role).
-- prevented by: scripts/checks/every_inquiry_conversation_keeps_one_state.test.mjs (this file's shape) and
--               supabase/functions/_shared/inquiry_state.test.ts (the code that reads it); probe:
--               every_inquiry_conversation_keeps_one_state_every_surface_reads_probe.sql (the merge and carry, rolled back).

create table if not exists public.inquiry_state (
  conv_key        text primary key check (btrim(conv_key) <> ''),
  surface         text not null check (surface in ('request_chat', 'portal_assistant', 'widget', 'whatsapp')),
  party_key       text,
  episode_from    integer not null default 0 check (episode_from >= 0),
  intake_id       uuid references public.inquiry_intake(id) on delete set null,
  source_key      text references public.inquiry_state(conv_key) on delete set null,
  carried_to      text,
  trade           text,
  trade_codes     text[] not null default '{}',
  specs           jsonb not null default '{}'::jsonb check (jsonb_typeof(specs) = 'object'),
  unknown         jsonb not null default '{}'::jsonb check (jsonb_typeof(unknown) = 'object'),
  asked           jsonb not null default '{}'::jsonb check (jsonb_typeof(asked) = 'object'),
  language        text check (language in ('en', 'ar')),
  dialect         text check (dialect in ('gulf', 'egyptian', 'levantine', 'msa', 'english', 'arabizi', 'mixed')),
  dialect_by      text check (dialect_by in ('model', 'markers')),
  script          text check (script in ('arabic', 'latin', 'arabizi', 'mixed')),
  message_count   integer not null default 0 check (message_count >= 0),
  status          text not null default 'open' check (status in ('open', 'converging', 'summarising', 'handed_off', 'carried', 'closed')),
  handoff_id      bigint,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.inquiry_state is
  'One durable state per inquiry conversation, shared by the request chat, the portal assistant, WhatsApp and the widget (founder ledger 1572). Written only through fn_inquiry_state_merge / fn_inquiry_state_carry. scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads.sql';

-- phase 2: the expert's half of the state (see the header)
alter table public.inquiry_state add column if not exists condition jsonb not null default '{}'::jsonb check (jsonb_typeof(condition) = 'object');
alter table public.inquiry_state add column if not exists options_offered jsonb not null default '[]'::jsonb check (jsonb_typeof(options_offered) = 'array');
alter table public.inquiry_state add column if not exists chosen_option jsonb check (chosen_option is null or jsonb_typeof(chosen_option) = 'object');
alter table public.inquiry_state add column if not exists budget jsonb check (budget is null or jsonb_typeof(budget) = 'object');

create index if not exists inquiry_state_party_recent_idx on public.inquiry_state (party_key, updated_at desc);
create index if not exists inquiry_state_intake_idx on public.inquiry_state (intake_id) where intake_id is not null;

alter table public.inquiry_state enable row level security;
drop policy if exists inquiry_state_service_role_only on public.inquiry_state;
create policy inquiry_state_service_role_only on public.inquiry_state
  as permissive for all to public using (false) with check (false);
revoke all on public.inquiry_state from anon, authenticated;

-- In the daily export with the request it belongs to (the conversation's facts are part of the inquiry record).
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('inquiry_state', true, 'inquiry', 'The one state per inquiry conversation (specs with their message, unknowns, count, dialect, status), ledger 1572.', 'sales_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- The status chain. carried and closed stand outside it: carried is set by the carry, closed by a person.
create or replace function public.fn_inquiry_state_merge(p_conv_key text, p_surface text, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  s public.inquiry_state;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_turn integer := case when (v_patch->>'turn') ~ '^\d+$' then (v_patch->>'turn')::integer end;
  v_src text := coalesce(nullif(v_patch->>'src', ''), p_surface);
  k text; v jsonb; old jsonb; v_val text; v_t integer;
  v_rank_old integer; v_rank_new integer; v_status text;
begin
  if coalesce(btrim(p_conv_key), '') = '' then raise exception 'an inquiry state must name its conversation'; end if;
  if jsonb_typeof(v_patch) <> 'object' then raise exception 'an inquiry state patch is a json object'; end if;
  insert into public.inquiry_state (conv_key, surface, party_key, episode_from)
  values (p_conv_key, p_surface, nullif(v_patch->>'party_key', ''),
          case when (v_patch->>'episode_from') ~ '^\d+$' then (v_patch->>'episode_from')::integer else 0 end)
  on conflict (conv_key) do nothing;
  select * into s from public.inquiry_state where conv_key = p_conv_key for update;

  -- specs: key -> {value, turn}. Added with its turn; a different value keeps the earlier one; nothing is removed.
  if jsonb_typeof(v_patch->'specs') = 'object' then
    for k, v in select e.key, e.value from jsonb_each(v_patch->'specs') e loop
      v_val := left(btrim(case when jsonb_typeof(v) = 'object' then v->>'value' else v #>> '{}' end), 500);
      continue when coalesce(v_val, '') = '';
      v_t := case when jsonb_typeof(v) = 'object' and (v->>'turn') ~ '^\d+$' then (v->>'turn')::integer else v_turn end;
      old := s.specs->k;
      if old is null then
        s.specs := s.specs || jsonb_build_object(k, jsonb_build_object('value', v_val, 'turn', v_t, 'first_turn', v_t, 'src', v_src));
      elsif old->>'value' is distinct from v_val then
        s.specs := s.specs || jsonb_build_object(k, jsonb_build_object('value', v_val, 'turn', v_t, 'first_turn', coalesce(old->'first_turn', old->'turn'),
                                                                       'changed_from', old->>'value', 'src', v_src));
      end if;
      s.unknown := s.unknown - k;   -- they gave it after all
    end loop;
  end if;

  -- unknown: key -> {turn, said}. Only for a spec not held; the first time it was said is kept.
  if jsonb_typeof(v_patch->'unknown') = 'object' then
    for k, v in select e.key, e.value from jsonb_each(v_patch->'unknown') e loop
      continue when s.specs ? k or s.unknown ? k or (k = 'budget' and s.budget is not null);
      s.unknown := s.unknown || jsonb_build_object(k, jsonb_build_object(
        'turn', case when jsonb_typeof(v) = 'object' and (v->>'turn') ~ '^\d+$' then (v->>'turn')::integer else v_turn end,
        'said', left(coalesce(case when jsonb_typeof(v) = 'object' then v->>'said' else v #>> '{}' end, ''), 300), 'src', v_src));
    end loop;
  end if;

  -- condition: key -> {value, turn}. A different value keeps the earlier one; nothing is removed.
  if jsonb_typeof(v_patch->'condition') = 'object' then
    for k, v in select e.key, e.value from jsonb_each(v_patch->'condition') e loop
      v_val := left(btrim(case when jsonb_typeof(v) = 'object' then v->>'value' else v #>> '{}' end), 300);
      continue when coalesce(v_val, '') = '' or k !~ '^[a-z_]{1,40}$';
      old := s.condition->k;
      if old is null then
        s.condition := s.condition || jsonb_build_object(k, jsonb_build_object('value', v_val, 'turn', v_turn));
      elsif old->>'value' is distinct from v_val then
        s.condition := s.condition || jsonb_build_object(k, jsonb_build_object('value', v_val, 'turn', v_turn, 'changed_from', old->>'value'));
      end if;
    end loop;
  end if;

  -- options_offered: each (problem, option) once, with the turn it was first put to them; at most 60.
  if jsonb_typeof(v_patch->'options_offered') = 'array' then
    for v in select x from jsonb_array_elements(v_patch->'options_offered') x loop
      continue when jsonb_typeof(v) <> 'object' or coalesce(btrim(v->>'option'), '') = '' or jsonb_array_length(s.options_offered) >= 60;
      continue when exists (select 1 from jsonb_array_elements(s.options_offered) o
                             where o->>'problem' is not distinct from left(v->>'problem', 60) and o->>'option' = left(v->>'option', 60));
      s.options_offered := s.options_offered || jsonb_build_array(jsonb_build_object('problem', left(v->>'problem', 60), 'option', left(v->>'option', 60),
        'turn', v_turn, 'src', v_src));
    end loop;
  end if;

  -- chosen_option: the latest choice; a different one keeps the earlier in changed_from.
  if jsonb_typeof(v_patch->'chosen_option') = 'object' and coalesce(btrim(v_patch->'chosen_option'->>'option'), '') <> '' then
    if s.chosen_option is null or s.chosen_option->>'option' is distinct from left(v_patch->'chosen_option'->>'option', 60)
       or s.chosen_option->>'problem' is distinct from left(v_patch->'chosen_option'->>'problem', 60) then
      s.chosen_option := jsonb_build_object('problem', left(v_patch->'chosen_option'->>'problem', 60), 'option', left(v_patch->'chosen_option'->>'option', 60),
          'label', left(coalesce(v_patch->'chosen_option'->>'label', ''), 160), 'turn', v_turn, 'src', v_src)
        || case when s.chosen_option is null then '{}'::jsonb
                else jsonb_build_object('changed_from', jsonb_build_object('problem', s.chosen_option->>'problem', 'option', s.chosen_option->>'option')) end;
    end if;
  end if;

  -- budget: {value, turn}; a change keeps the earlier; a budget given clears its "does not know".
  v_val := left(btrim(case when jsonb_typeof(v_patch->'budget') = 'object' then v_patch->'budget'->>'value'
                           when jsonb_typeof(v_patch->'budget') = 'string' then v_patch->>'budget' end), 200);
  if coalesce(v_val, '') <> '' then
    if s.budget is null then s.budget := jsonb_build_object('value', v_val, 'turn', v_turn);
    elsif s.budget->>'value' is distinct from v_val then s.budget := jsonb_build_object('value', v_val, 'turn', v_turn, 'changed_from', s.budget->>'value');
    end if;
    s.unknown := s.unknown - 'budget';
  end if;

  -- asked: the specs this turn's reply asked -> count + 1 and the turn.
  if jsonb_typeof(v_patch->'asked') = 'array' then
    for k in select distinct x from jsonb_array_elements_text(v_patch->'asked') x where btrim(x) <> '' loop
      s.asked := s.asked || jsonb_build_object(k, jsonb_build_object('count', coalesce((s.asked->k->>'count')::integer, 0) + 1, 'last_turn', v_turn));
    end loop;
  end if;

  -- the count of the surface's own transcript: it only grows, so a retried turn never counts twice
  if (v_patch->>'message_count') ~ '^\d+$' then s.message_count := greatest(s.message_count, (v_patch->>'message_count')::integer); end if;
  if v_patch->>'language' in ('en', 'ar') then s.language := v_patch->>'language'; end if;
  if v_patch->>'dialect' in ('gulf', 'egyptian', 'levantine', 'msa', 'english', 'arabizi', 'mixed') then
    -- a reading by the model is not replaced by the code's markers
    if s.dialect_by is distinct from 'model' or v_patch->>'dialect_by' = 'model' then
      s.dialect := v_patch->>'dialect';
      s.dialect_by := case when v_patch->>'dialect_by' = 'model' then 'model' else 'markers' end;
    end if;
  end if;
  if v_patch->>'script' in ('arabic', 'latin', 'arabizi', 'mixed') then s.script := v_patch->>'script'; end if;
  if coalesce(v_patch->>'trade', '') <> '' then s.trade := left(v_patch->>'trade', 80); end if;
  if jsonb_typeof(v_patch->'trade_codes') = 'array' and jsonb_array_length(v_patch->'trade_codes') > 0 then
    s.trade_codes := array(select distinct left(x, 80) from jsonb_array_elements_text(v_patch->'trade_codes') x where btrim(x) <> '' order by 1);
  end if;
  if coalesce(v_patch->>'intake_id', '') ~* '^[0-9a-f-]{36}$' then s.intake_id := (v_patch->>'intake_id')::uuid; end if;
  if (v_patch->>'handoff_id') ~ '^\d+$' then s.handoff_id := (v_patch->>'handoff_id')::bigint; end if;
  if coalesce(s.party_key, '') = '' and coalesce(v_patch->>'party_key', '') <> '' then s.party_key := v_patch->>'party_key'; end if;

  -- status: forward only on open -> converging -> summarising -> handed_off; closed always wins; carried stays carried
  v_status := v_patch->>'status';
  if v_status = 'closed' then s.status := 'closed';
  elsif v_status in ('open', 'converging', 'summarising', 'handed_off') and s.status not in ('closed') then
    v_rank_old := array_position(array['open', 'converging', 'summarising', 'handed_off'], s.status);
    v_rank_new := array_position(array['open', 'converging', 'summarising', 'handed_off'], v_status);
    if s.status = 'carried' then
      if v_status = 'handed_off' then s.status := 'handed_off'; end if;
    elsif v_rank_new > coalesce(v_rank_old, 0) then s.status := v_status;
    end if;
  end if;

  s.updated_at := now();
  update public.inquiry_state set
    party_key = s.party_key, intake_id = s.intake_id, trade = s.trade, trade_codes = s.trade_codes, specs = s.specs,
    unknown = s.unknown, asked = s.asked, language = s.language, dialect = s.dialect, dialect_by = s.dialect_by,
    script = s.script, message_count = s.message_count, status = s.status, handoff_id = s.handoff_id,
    condition = s.condition, options_offered = s.options_offered, chosen_option = s.chosen_option, budget = s.budget, updated_at = s.updated_at
  where conv_key = p_conv_key;
  return to_jsonb(s);
end $fn$;
revoke execute on function public.fn_inquiry_state_merge(text, text, jsonb) from public, anon, authenticated;
comment on function public.fn_inquiry_state_merge(text, text, jsonb) is
  'The one writer of public.inquiry_state: merges one surface turn''s patch (specs with their turn, unknown, asked, count, language, dialect, status; phase 2: condition, options offered, the chosen option, budget). scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads.sql';

create or replace function public.fn_inquiry_state_carry(p_from_key text, p_to_key text, p_surface text, p_intake_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare f public.inquiry_state; t public.inquiry_state;
begin
  if coalesce(btrim(p_to_key), '') = '' or p_to_key = p_from_key then raise exception 'a carry names a new conversation'; end if;
  select * into f from public.inquiry_state where conv_key = p_from_key for update;
  if not found then return null; end if;
  insert into public.inquiry_state (conv_key, surface, party_key, intake_id, source_key, trade, trade_codes, specs, unknown, asked,
                                    language, dialect, dialect_by, script, message_count, status, condition, options_offered, chosen_option, budget)
  values (p_to_key, p_surface, f.party_key, p_intake_id, f.conv_key, f.trade, f.trade_codes, f.specs, f.unknown, f.asked,
          f.language, f.dialect, f.dialect_by, f.script, f.message_count,
          case when f.status in ('converging', 'summarising', 'handed_off') then f.status else 'open' end,
          f.condition, f.options_offered, f.chosen_option, f.budget)
  on conflict (conv_key) do update set
    source_key = excluded.source_key,
    intake_id = coalesce(public.inquiry_state.intake_id, excluded.intake_id),
    trade = coalesce(public.inquiry_state.trade, excluded.trade),
    specs = excluded.specs || public.inquiry_state.specs,        -- what the request already holds wins
    unknown = (excluded.unknown || public.inquiry_state.unknown) - array(select jsonb_object_keys(excluded.specs || public.inquiry_state.specs)),
    message_count = greatest(public.inquiry_state.message_count, excluded.message_count),
    language = coalesce(public.inquiry_state.language, excluded.language),
    dialect = coalesce(public.inquiry_state.dialect, excluded.dialect),
    dialect_by = coalesce(public.inquiry_state.dialect_by, excluded.dialect_by),
    trade_codes = case when cardinality(public.inquiry_state.trade_codes) > 0 then public.inquiry_state.trade_codes else excluded.trade_codes end,
    condition = excluded.condition || public.inquiry_state.condition,     -- what the request already holds wins
    options_offered = case when jsonb_array_length(public.inquiry_state.options_offered) > 0 then public.inquiry_state.options_offered else excluded.options_offered end,
    chosen_option = coalesce(public.inquiry_state.chosen_option, excluded.chosen_option),
    budget = coalesce(public.inquiry_state.budget, excluded.budget),
    updated_at = now()
  returning * into t;
  update public.inquiry_state set carried_to = p_to_key, intake_id = coalesce(intake_id, p_intake_id), updated_at = now(),
         status = case when status in ('handed_off', 'closed') then status else 'carried' end
   where conv_key = p_from_key;
  return to_jsonb(t);
end $fn$;
revoke execute on function public.fn_inquiry_state_carry(text, text, text, uuid) from public, anon, authenticated;
comment on function public.fn_inquiry_state_carry(text, text, text, uuid) is
  'A portal chat''s state becomes its request''s (New request opens pre-filled); the source episode is marked carried. scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads.sql';
