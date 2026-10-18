-- THE QUARTERLY REFRESH RE-CHECKS EVERY SEAT KNOWLEDGE ENTRY AGAINST ITS SOURCE (it_engineer, 5 Oct 2026, backlog T4).
-- Seat: it_engineer (it schedules and verifies; each seat owns its pack and its re-research queue).
-- Extends the live duty it_engineer.knowledge_refresh; it does not add a second owner of the subject.
--
-- WHAT WAS MEASURED (production, 5 Oct 2026)
--   * fn_it_engineer_knowledge_refresh files each seat's FIVE stalest items per quarter (rows for 2026-07-01 and
--     2026-10-01 exist, 5 items each). Nothing looks at the other ~8,300 entries fn_seat_knowledge_items serves:
--     support 716, sales 5,898, accountant 397, it_engineer 415, ceo 790, marketing 92 (agent_knowledge).
--   * 282 entries carry NO source at all (support 1, sales 74, ceo 207 have an empty source_ids). Nothing flags them.
--   * fn_knowledge_staleness_tag(review_due, validation_status) prints [STALE ...] for agent_knowledge rows whose
--     validation_status is 'stale' or whose review_due has passed. 17 marketing entries were last written before
--     2026-07-01 and still read as current. The five pack tables have no review_due and no validation_status.
--   * fn_seat_knowledge_items has exactly one caller family (this duty and fn_it_engineer_knowledge_exam, both by
--     column name), so its result can grow three columns.
--
-- WHAT THIS ADDS — once per seat per quarter, deterministic, no model:
--   every entry of the seat (quarantined agent_knowledge rows are not served and are skipped) is STALE when
--     no_source       it names no source (source_ids empty / source_ref blank);
--     review_overdue  its review_due has passed, or it is already marked stale;
--     source_old      it was last written or re-sourced before the start of the PREVIOUS quarter (so it has gone a
--                     full quarter without a re-check). ponytail: a fixed one-quarter age; a per-domain shelf life
--                     (law vs price vs method) is the upgrade when the packs carry one.
--   A stale entry is recorded in public.seat_knowledge_stale (the per-item stale status, with its reasons); an
--   agent_knowledge entry is also set validation_status = 'stale' so fn_knowledge_staleness_tag tags it in every
--   prompt. Each stale entry not already among the quarter's five is filed in THE OWNING SEAT'S OWN queue as a
--   held research question (fn_reason_hold, surface <seat>.knowledge_refresh — held behind the model hold, which
--   stays on) - NOT all at once: see THE DAILY CAP below. The per-quarter result (checked / stale / per reason / filed) is written on the seat's
--   seat_knowledge_refresh row as `recheck`.
--   VERIFY: a quarter is complete only when its five are done AND every stale entry it found was re-researched
--   (the apply stamps resolved_at). The finding is now BEHIND PACE, not "45 days old" (see the routine).
--
-- THE DAILY CAP (review of #1189: the re-check must stay inside the idle LLM ceiling, USD 1-2/day).
--   Each re-research question, once the hold lifts, is reasoned by resilience_ping's replay through think().
--   MEASURED on production 18 Oct 2026 (read-only): the 10 knowledge_refresh questions reasoned so far (all on
--   12 Oct, status applied), costed as the sum of ai_cost_log.cost_aed with fn = 'resilience_ping' for the same
--   seat in the 5 minutes up to reasoned_at (an upper bound: another call of that seat in the window counts too):
--     ceo (judgement on Opus)  3 questions  AED 1.31765  mean AED 0.4392 (USD 0.1196)  max AED 0.8023 (USD 0.2185)
--     the other seats          7 questions  AED 0.32077  mean AED 0.0458 (USD 0.0125)  max AED 0.0865 (USD 0.0236)
--     (AED 3.6725 = USD 1)
--   CAP: at most 2 ceo and 20 other-seat questions are filed per Dubai day, the quarter's five INCLUDED (re-review
--   of #1189: filed outside the cap, day 1 carried 30 more, 5 of them the ceo's). The count is read from the queue
--   (every krefresh:/krecheck: question created since Dubai midnight); the five go first, then the stale entries.
--     at the measured means:   2 x 0.1196 + 20 x 0.0125 = USD 0.49/day
--     at the measured maxima:  2 x 0.2185 + 20 x 0.0236 = USD 0.91/day  -> inside USD 1/day even then
--   Over a ~91-day quarter that is up to 182 ceo and 1,820 other questions, one batch a day, oldest flag first and
--   no_source before review_overdue before source_old. ponytail: two fixed count caps from a measured cost; a
--   spend-reading budget (today's resilience_ping cost) is the upgrade if the per-question cost moves.
--   Entries not reached in the quarter stay unfiled and the quarter does not verify; it is a finding only when its
--   class falls behind the pace the cap allows (the routine's BEHIND PACE block).
--
-- THE CEO SEES THE QUARTER (review of #1189). When all six seats are re-checked, the ceo seat receives ONE
-- summary per quarter (per seat: checked, stale, by reason) on the existing it_engineer -> ceo 'it.finding'
-- handoff, and each owning seat with stale entries (other than it_engineer, which files them) receives its own
-- 'it.finding' notice alongside the questions in its queue. Each closes when its quarter verifies.
--
-- WHAT THIS DOES NOT DO: it does not rewrite an entry's text (a refresh proposes a pending candidate, as before),
-- and it does not put a tag into the five pack tables' retrieval text — those tables have no status column; their
-- stale status is the seat_knowledge_stale row.

alter table public.seat_knowledge_refresh add column if not exists recheck jsonb;  -- {checked, stale, no_source, review_overdue, source_old, filed, at}

create table if not exists public.seat_knowledge_stale (
  quarter      date not null check (quarter = date_trunc('quarter', quarter)::date),
  item_key     text not null,
  seat         text not null references public.org_role (role_id),
  reasons      text[] not null check (cardinality(reasons) > 0 and reasons <@ array['no_source', 'review_overdue', 'source_old']),
  prior_status text,              -- agent_knowledge.validation_status before it was set to 'stale'
  held_id      bigint,            -- the research question in the seat's queue (one of the quarter's five reuses that one's)
  flagged_at   timestamptz not null default now(),
  resolved_at  timestamptz,       -- stamped when the re-research for this item was reasoned
  primary key (quarter, item_key)
);
alter table public.seat_knowledge_stale add column if not exists filed_at timestamptz;  -- when held_id was set (the daily cap counts these)
create index if not exists seat_knowledge_stale_unfiled on public.seat_knowledge_stale (quarter, flagged_at, item_key) where held_id is null;
create index if not exists seat_knowledge_stale_open on public.seat_knowledge_stale (seat, quarter) where resolved_at is null;
alter table public.seat_knowledge_stale enable row level security;
drop policy if exists seat_knowledge_stale_service_role_only on public.seat_knowledge_stale;
create policy seat_knowledge_stale_service_role_only on public.seat_knowledge_stale as permissive for all to public using (false) with check (false);
revoke all on public.seat_knowledge_stale from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('seat_knowledge_stale', true, 'knowledge', 'each quarter''s stale seat knowledge entries, their reasons and their re-research', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── the seat's own knowledge, one shape for all six packs, now with what the re-check reads ────────────────
-- The result type grows, so the routine is dropped and created (CREATE grants PUBLIC: revoked below).
drop function if exists public.fn_seat_knowledge_items(text);
create function public.fn_seat_knowledge_items(p_seat text)
returns table(item_key text, title text, content text, updated_at timestamptz,
              has_source boolean, review_due date, validation_status text)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select 'support_knowledge:' || record_id, title, body, imported_at, coalesce(cardinality(source_ids), 0) > 0, null::date, null::text
    from public.support_knowledge
   where p_seat = 'customer_support' and coalesce(runtime_index_eligible, true) and nullif(btrim(body), '') is not null
  union all
  select 'sales_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at), coalesce(cardinality(source_ids), 0) > 0, null, null
    from public.sales_knowledge
   where p_seat = 'sales_engineer' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'accountant_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at), coalesce(cardinality(source_ids), 0) > 0, null, null
    from public.accountant_knowledge
   where p_seat = 'accountant' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'it_engineer_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at), coalesce(cardinality(source_ids), 0) > 0, null, null
    from public.it_engineer_knowledge
   where p_seat = 'it_engineer' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'ceo_knowledge:' || record_id, title, body, imported_at, coalesce(cardinality(source_ids), 0) > 0, null, null
    from public.ceo_knowledge
   where p_seat = 'ceo' and coalesce(runtime_index_eligible, true) and nullif(btrim(body), '') is not null
  union all
  select 'agent_knowledge:' || id, topic, content, coalesce(updated_at, created_at), nullif(btrim(source_ref), '') is not null,
         review_due, validation_status
    from public.agent_knowledge
   where p_seat = 'marketing' and agent_key like 'marketing%' and nullif(btrim(content), '') is not null;
$fn$;
revoke execute on function public.fn_seat_knowledge_items(text) from public, anon, authenticated;
grant execute on function public.fn_seat_knowledge_items(text) to service_role;

-- ── the quarterly refresh: the five stalest, then every entry re-checked ─────────────────────────────────
create or replace function public.fn_it_engineer_knowledge_refresh()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare s text; i record; k record; v_q date := date_trunc('quarter', (now() at time zone 'Asia/Dubai'))::date;
  v_today date := (now() at time zone 'Asia/Dubai')::date; v_items jsonb; v_held bigint;
  v_opened int := 0; v_verified int := 0; v_overdue int := 0; v_rechecked int := 0; f record; v_text text;
  v_reasons text[]; v_checked int; v_stale int; v_filed int := 0; v_nosrc int; v_due int; v_old int; v_prior text;
  v_sum jsonb; v_behind text[] := '{}'; v_st public.seat_knowledge_stale; v_title text; v_content text; v_today_start timestamptz; v_cap_ceo int; v_cap_other int;
  c_cap_ceo constant int := 2;     -- measured: a ceo question mean USD 0.1196, max 0.2185 (THE DAILY CAP above)
  c_cap_other constant int := 20;  -- measured: another seat's question mean USD 0.0125, max 0.0236
begin
  foreach s in array array['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'] loop
    if not exists (select 1 from public.seat_knowledge_refresh where seat = s and quarter = v_q) then
      v_items := '[]'::jsonb;
      -- the quarter's five are CHOSEN here and FILED under THE DAILY CAP below (review of #1189: on day 1 they
      -- were 30 extra questions, 5 of them the ceo's, outside the cap)
      for i in select k2.item_key, k2.title from public.fn_seat_knowledge_items(s) k2
                order by k2.updated_at nulls first, k2.item_key limit 5 loop
        v_items := v_items || jsonb_build_object('item_key', i.item_key, 'title', left(i.title, 200), 'held_id', null, 'done_at', null);
      end loop;
      insert into public.seat_knowledge_refresh (seat, quarter, items) values (s, v_q, v_items);
      v_opened := v_opened + 1;
    end if;

    -- THE FULL RE-CHECK: every entry of the seat, once per quarter, against its source and its dates.
    if exists (select 1 from public.seat_knowledge_refresh where seat = s and quarter = v_q and recheck is null) then
      v_checked := 0; v_stale := 0; v_nosrc := 0; v_due := 0; v_old := 0;
      for k in select * from public.fn_seat_knowledge_items(s) x where coalesce(x.validation_status, '') <> 'quarantined' loop
        v_checked := v_checked + 1;
        v_reasons := array_remove(array[
          case when not k.has_source then 'no_source' end,
          case when k.review_due < v_today or k.validation_status = 'stale' then 'review_overdue' end,
          case when k.updated_at is null or k.updated_at < (v_q - interval '3 months') then 'source_old' end], null);
        continue when cardinality(v_reasons) = 0;
        v_stale := v_stale + 1;
        v_nosrc := v_nosrc + (('no_source' = any(v_reasons))::int);
        v_due := v_due + (('review_overdue' = any(v_reasons))::int);
        v_old := v_old + (('source_old' = any(v_reasons))::int);

        -- THE STALE STATUS: the ledger row for every pack; the agent_knowledge row itself so the prompt tag shows.
        v_prior := k.validation_status;
        if k.item_key like 'agent_knowledge:%' then
          update public.agent_knowledge set validation_status = 'stale'
           where id = split_part(k.item_key, ':', 2)::bigint and coalesce(validation_status, '') not in ('stale', 'quarantined');
        end if;
        insert into public.seat_knowledge_stale (quarter, item_key, seat, reasons, prior_status)
        values (v_q, k.item_key, s, v_reasons, v_prior) on conflict (quarter, item_key) do nothing;

        -- one of the quarter's five already has its research question: the stale row points at it, filed now.
        -- Every other stale entry waits for THE DAILY CAP below.
        update public.seat_knowledge_stale st set held_id = (x->>'held_id')::bigint, filed_at = now()
          from public.seat_knowledge_refresh r, jsonb_array_elements(r.items) x
         where r.seat = s and r.quarter = v_q and x->>'item_key' = k.item_key and (x->>'held_id') is not null
           and st.quarter = v_q and st.item_key = k.item_key and st.held_id is null;
      end loop;
      update public.seat_knowledge_refresh
         set recheck = jsonb_build_object('checked', v_checked, 'stale', v_stale, 'no_source', v_nosrc, 'review_overdue', v_due,
                                          'source_old', v_old, 'filed', 0, 'at', now())
       where seat = s and quarter = v_q;
      v_rechecked := v_rechecked + 1;
    end if;
  end loop;

  -- THE CEO SUMMARY AND THE OWNERS' NOTICES: once, when the whole quarter is re-checked (fn_seat_handoff dedupes
  -- on its subject, so a later run sends nothing twice).
  if v_rechecked > 0 and not exists (select 1 from public.seat_knowledge_refresh where quarter = v_q and recheck is null) then
    select jsonb_object_agg(r.seat, r.recheck - 'filed' - 'at'), sum((r.recheck->>'stale')::int)
      into v_sum, v_stale from public.seat_knowledge_refresh r where r.quarter = v_q;
    perform public.fn_seat_handoff('it_engineer', 'ceo', 'it.finding', 'seat_knowledge_stale', 'knowledge_recheck:' || v_q,
      jsonb_build_object('duty', 'knowledge_recheck', 'issue_key', 'knowledge_recheck:' || v_q, 'subject', 'every seat''s knowledge',
        'quarter', v_q, 'per_seat', v_sum, 'stale', v_stale, 'daily_cap', jsonb_build_object('ceo', c_cap_ceo, 'other', c_cap_other),
        'title', 'Quarterly knowledge re-check ' || to_char(v_q, 'YYYY "Q"Q') || ': ' || v_stale || ' stale entries across the seats; '
                 || 'each is re-researched in its own seat''s queue a daily batch at a time, and holding the seats to it is yours'));
    for f in select r.seat, r.recheck from public.seat_knowledge_refresh r
              where r.quarter = v_q and r.seat <> 'it_engineer' and (r.recheck->>'stale')::int > 0 loop
      perform public.fn_seat_handoff('it_engineer', f.seat, 'it.finding', 'seat_knowledge_stale', 'knowledge_recheck:' || v_q || ':' || f.seat,
        jsonb_build_object('duty', 'knowledge_recheck', 'issue_key', 'knowledge_recheck:' || v_q || ':' || f.seat, 'subject', f.seat || ' knowledge',
          'quarter', v_q, 'recheck', f.recheck - 'at',
          'title', 'Quarterly knowledge re-check ' || to_char(v_q, 'YYYY "Q"Q') || ': ' || (f.recheck->>'stale') || ' of your '
                   || (f.recheck->>'checked') || ' entries are stale; their re-research questions arrive in your queue a daily batch at a time'));
    end loop;
  end if;

  -- THE DAILY CAP: EVERY question this duty files counts, the quarter's five included. Today's count is read from
  -- the queue itself (every krefresh:/krecheck: question created since Dubai midnight), so no day exceeds 2 + 20.
  v_today_start := v_today::timestamp at time zone 'Asia/Dubai';
  select c_cap_ceo - count(*) filter (where h.seat = 'ceo'), c_cap_other - count(*) filter (where h.seat <> 'ceo')
    into v_cap_ceo, v_cap_other
    from public.reasoning_held_question h
   where h.created_at >= v_today_start and (h.dedupe_key like 'krefresh:%' or h.dedupe_key like 'krecheck:%');
  -- first the quarter's five (any quarter still open), ceo and others each within their own cap
  for i in select r.seat, r.quarter, x->>'item_key' item_key, o from public.seat_knowledge_refresh r,
                  jsonb_array_elements(r.items) with ordinality t(x, o)
            where r.verified_at is null and (x->>'held_id') is null and (x->>'done_at') is null
            order by r.quarter, r.seat, o loop
    exit when v_cap_ceo <= 0 and v_cap_other <= 0;
    continue when (i.seat = 'ceo' and v_cap_ceo <= 0) or (i.seat <> 'ceo' and v_cap_other <= 0);
    select k2.title, k2.content into v_title, v_content from public.fn_seat_knowledge_items(i.seat) k2 where k2.item_key = i.item_key;
    v_text := 'Quarterly knowledge refresh (' || to_char(i.quarter, 'YYYY "Q"Q') || '). Is this still correct and current in the '
           || 'UAE today? Check the authoritative source and state precisely what has changed, if anything. Item: '
           || coalesce(v_title, i.item_key) || E'\n' || left(coalesce(v_content, ''), 1500);
    v_held := public.fn_reason_hold(i.seat, i.seat || '.knowledge_refresh', v_text,
      jsonb_build_object('seat', i.seat, 'surface', i.seat || '.knowledge_refresh', 'question', v_text, 'research', true, 'stakes', 'high',
        'context', jsonb_build_object('audience', 'internal'),
        'subject', jsonb_build_object('item_key', i.item_key, 'quarter', i.quarter), 'dedupeKey', 'krefresh:' || i.quarter || ':' || i.item_key),
      jsonb_build_object('filed_by', 'it_engineer.knowledge_refresh'), jsonb_build_object('item_key', i.item_key, 'quarter', i.quarter),
      'seat_duty', 'krefresh:' || i.quarter || ':' || i.item_key);
    update public.seat_knowledge_refresh r
       set items = jsonb_set(r.items, array[(i.o - 1)::text, 'held_id'], to_jsonb(v_held))
     where r.seat = i.seat and r.quarter = i.quarter;
    -- a stale entry that is one of the five shares this question
    update public.seat_knowledge_stale set held_id = v_held, filed_at = now()
     where quarter = i.quarter and item_key = i.item_key and held_id is null;
    if i.seat = 'ceo' then v_cap_ceo := v_cap_ceo - 1; else v_cap_other := v_cap_other - 1; end if;
    v_filed := v_filed + 1;
  end loop;
  -- then this quarter's stale entries that are not among the five
  for v_st in select * from public.seat_knowledge_stale x
             where x.quarter = v_q and x.held_id is null
               and not exists (select 1 from public.seat_knowledge_refresh r, jsonb_array_elements(r.items) y
                                where r.seat = x.seat and r.quarter = x.quarter and y->>'item_key' = x.item_key)
             order by x.flagged_at, ('no_source' <> all(x.reasons)), ('review_overdue' <> all(x.reasons)), x.item_key loop
    exit when v_cap_ceo <= 0 and v_cap_other <= 0;
    continue when (v_st.seat = 'ceo' and v_cap_ceo <= 0) or (v_st.seat <> 'ceo' and v_cap_other <= 0);
    select k2.title, k2.content into v_title, v_content from public.fn_seat_knowledge_items(v_st.seat) k2 where k2.item_key = v_st.item_key;
    v_text := 'Quarterly knowledge re-check (' || to_char(v_q, 'YYYY "Q"Q') || ') found this entry stale ('
           || array_to_string(v_st.reasons, ', ') || '). Find its authoritative source, confirm it is correct and current '
           || 'in the UAE today, and state precisely what has changed, if anything, citing the source. Item: '
           || coalesce(v_title, v_st.item_key) || E'\n' || left(coalesce(v_content, ''), 1500);
    v_held := public.fn_reason_hold(v_st.seat, v_st.seat || '.knowledge_refresh', v_text,
      jsonb_build_object('seat', v_st.seat, 'surface', v_st.seat || '.knowledge_refresh', 'question', v_text, 'research', true, 'stakes', 'high',
        'context', jsonb_build_object('audience', 'internal'),
        'subject', jsonb_build_object('item_key', v_st.item_key, 'quarter', v_q, 'recheck', true), 'dedupeKey', 'krecheck:' || v_q || ':' || v_st.item_key),
      jsonb_build_object('filed_by', 'it_engineer.knowledge_refresh'), jsonb_build_object('item_key', v_st.item_key, 'quarter', v_q, 'recheck', true),
      'seat_duty', 'krecheck:' || v_q || ':' || v_st.item_key);
    update public.seat_knowledge_stale set held_id = v_held, filed_at = now() where quarter = v_q and item_key = v_st.item_key;
    if v_st.seat = 'ceo' then v_cap_ceo := v_cap_ceo - 1; else v_cap_other := v_cap_other - 1; end if;
    v_filed := v_filed + 1;
  end loop;
  update public.seat_knowledge_refresh r
     set recheck = r.recheck || jsonb_build_object(
           'filed', (select count(*) from public.seat_knowledge_stale st3 where st3.seat = r.seat and st3.quarter = r.quarter and st3.held_id is not null),
           'unfiled', (select count(*) from public.seat_knowledge_stale st3 where st3.seat = r.seat and st3.quarter = r.quarter and st3.held_id is null))
   where r.quarter = v_q and r.recheck is not null;

  -- VERIFY: a quarter is refreshed when every item it filed was reasoned (the apply stamps done_at) AND every
  -- stale entry its re-check found was re-researched (the apply stamps resolved_at). A quarter that closed before
  -- the re-check existed (recheck null, quarter past) is judged on its five alone.
  update public.seat_knowledge_refresh r set verified_at = now()
   where verified_at is null and jsonb_array_length(items) > 0 and (recheck is not null or quarter < v_q)
     and not exists (select 1 from jsonb_array_elements(r.items) x where x->>'done_at' is null)
     and not exists (select 1 from public.seat_knowledge_stale st where st.seat = r.seat and st.quarter = r.quarter and st.resolved_at is null);
  get diagnostics v_verified = row_count;
  -- a verified seat-quarter closes its owner's notice; the ceo summary closes when every seat of its quarter verified
  for f in select a.id, a.evidence, a.target_id from public.agent_actions a
            where a.kind = 'handoff' and a.target_id like 'it.finding:knowledge_recheck:%' and a.status not in ('done', 'failed') loop
    continue when exists (select 1 from public.seat_knowledge_refresh r
                           where r.verified_at is null
                             and (f.target_id = 'it.finding:knowledge_recheck:' || r.quarter
                                  or f.target_id = 'it.finding:knowledge_recheck:' || r.quarter || ':' || r.seat));
    perform public.fn_seat_handoff_complete(f.id, (coalesce(f.evidence, '{}'::jsonb) - 'waiting')
      || jsonb_build_object('verified_by', 'it_engineer', 'verified_at', now()));
  end loop;
  -- BEHIND PACE, NOT MERELY LONG (review of #1189): a capped backlog (the ceo's ~210 at 2 a day) runs past 45 days
  -- by design. A seat-quarter is a finding when its CLASS (ceo, or the other seats sharing 20) has re-researched
  -- fewer questions than the cap could have delivered since the quarter opened, allowing the same 45 days for a
  -- question to be reasoned once filed: due = least(total, cap x (days open - 45)). A small quarter (the five plus
  -- a few) is due in full on day 46, exactly as before.
  for f in with per_seat as (
             select r.seat, r.quarter, r.opened_at, r.verified_at, r.items, r.recheck, (r.seat = 'ceo') is_ceo,
                    jsonb_array_length(r.items)
                      + (select count(*) from public.seat_knowledge_stale x where x.seat = r.seat and x.quarter = r.quarter
                            and not exists (select 1 from jsonb_array_elements(r.items) y where y->>'item_key' = x.item_key)) total,
                    (select count(*) from jsonb_array_elements(r.items) y where y->>'done_at' is not null)
                      + (select count(*) from public.seat_knowledge_stale x where x.seat = r.seat and x.quarter = r.quarter and x.resolved_at is not null
                            and not exists (select 1 from jsonb_array_elements(r.items) y where y->>'item_key' = x.item_key)) done
               from public.seat_knowledge_refresh r),
           per_class as (
             select quarter, is_ceo, sum(total)::int total, sum(done)::int done,
                    least(sum(total), (case when is_ceo then c_cap_ceo else c_cap_other end)
                          * greatest(0, extract(day from now() - min(opened_at))::int - 45))::int due
               from per_seat group by quarter, is_ceo)
           select p.*, c.total class_total, c.done class_done, c.due class_due
             from per_seat p join per_class c using (quarter, is_ceo)
            where p.verified_at is null and c.done < c.due loop
    v_overdue := v_overdue + 1;
    v_behind := v_behind || ('knowledge_refresh:' || f.seat || ':' || f.quarter);
    perform public.fn_it_engineer_finding_upsert('knowledge_refresh:' || f.seat || ':' || f.quarter,
      'The ' || f.seat || ' seat''s knowledge refresh for ' || to_char(f.quarter, 'YYYY "Q"Q') || ' is behind its daily pace: '
        || f.class_done || ' of ' || f.class_due || ' due re-researched',
      'public.seat_knowledge_refresh / public.seat_knowledge_stale', 'agent_facing',
      (select count(*)::int from jsonb_array_elements(f.items) x where x->>'done_at' is null)
        + (select count(*)::int from public.seat_knowledge_stale st where st.seat = f.seat and st.quarter = f.quarter and st.resolved_at is null),
      jsonb_build_object('seat', f.seat, 'quarter', f.quarter, 'owner_seat', f.seat, 'recheck', f.recheck,
                         'class', case when f.is_ceo then 'ceo' else 'other' end, 'class_total', f.class_total,
                         'class_done', f.class_done, 'class_due', f.class_due), '{}'::text[],
      array['whether the model hold or a failing research step keeps the questions held'], 'it_engineer');
  end loop;
  update public.it_engineer_finding fi
     set closed_at = now(),
         close_note = case when exists (select 1 from public.seat_knowledge_refresh r
                                         where 'knowledge_refresh:' || r.seat || ':' || r.quarter = fi.issue_key and r.verified_at is not null)
                           then 'the quarter''s refresh completed' else 'the quarter''s refresh is back on its daily pace' end
   where fi.issue_key like 'knowledge_refresh:%' and fi.closed_at is null and not (fi.issue_key = any(v_behind))
     and exists (select 1 from public.seat_knowledge_refresh r where 'knowledge_refresh:' || r.seat || ':' || r.quarter = fi.issue_key);
  return jsonb_build_object('quarter', v_q, 'opened', v_opened, 'rechecked', v_rechecked, 'filed_today', v_filed,
                            'verified', v_verified, 'overdue', v_overdue);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_refresh() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_refresh() to service_role;

-- A refresh or re-check question was reasoned (its research proposed what changed as a pending candidate): stamp it done.
create or replace function public.fn_it_engineer_knowledge_refreshed(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_n int; v_s int;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'quarter') is null then
    -- a re-research filed by the pass-rate monitor: the exam row carries it
    return jsonb_build_object('applied', true, 'refiled_exam', r.subject->>'exam_id', 'sources', jsonb_array_length(coalesce(p_result->'sources', '[]'::jsonb)));
  end if;
  update public.seat_knowledge_refresh k
     set items = (select coalesce(jsonb_agg(case when x->>'item_key' = r.subject->>'item_key' and x->>'done_at' is null
                                        then x || jsonb_build_object('done_at', now(), 'sources', jsonb_array_length(coalesce(p_result->'sources', '[]'::jsonb)))
                                        else x end order by o), '[]'::jsonb)
                    from jsonb_array_elements(k.items) with ordinality t(x, o))
   where k.seat = r.seat and k.quarter = (r.subject->>'quarter')::date
     and exists (select 1 from jsonb_array_elements(k.items) x where x->>'item_key' = r.subject->>'item_key' and x->>'done_at' is null);
  get diagnostics v_n = row_count;
  with s as (
    update public.seat_knowledge_stale set resolved_at = now()
     where quarter = (r.subject->>'quarter')::date and item_key = r.subject->>'item_key' and resolved_at is null
    returning item_key, prior_status)
  -- re-researched: the agent_knowledge entry leaves 'stale' for the status it had (its candidate is reviewed as usual)
  update public.agent_knowledge a set validation_status = coalesce(s.prior_status, 'unvalidated')
    from s where s.item_key like 'agent_knowledge:%' and a.id = split_part(s.item_key, ':', 2)::bigint
     and a.validation_status = 'stale';
  v_s := (select count(*) from public.seat_knowledge_stale
           where quarter = (r.subject->>'quarter')::date and item_key = r.subject->>'item_key' and resolved_at is not null);
  return jsonb_build_object('applied', v_n > 0 or v_s > 0, 'item_stamped', v_n > 0, 'item_key', r.subject->>'item_key', 'stale_resolved', v_s > 0);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_refreshed(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_refreshed(bigint, jsonb) to service_role;

-- ── the clock: the same duty, its description now says what it does ─────────────────────────────────────
update public.seat_duty
   set what = 'Each quarter, every seat''s five stalest items AND every entry with no source, a passed review date or a source '
           || 'older than a quarter are re-researched in the seat''s own queue, at most 2 ceo and 20 other questions a day '
           || '(stale entries marked; the ceo gets the quarter''s summary); behind the pace the cap allows (after 45 days to reason) is a finding.',
       owner_file = 'scripts/sql/the_quarterly_refresh_rechecks_every_seat_knowledge_entry_against_its_source.sql'
 where duty = 'it_engineer.knowledge_refresh';
