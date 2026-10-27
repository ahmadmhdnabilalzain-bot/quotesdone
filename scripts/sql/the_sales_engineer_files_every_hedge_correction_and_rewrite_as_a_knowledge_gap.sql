-- THE SALES ENGINEER FILES EVERY HEDGE, CORRECTION AND REWRITE AS A KNOWLEDGE GAP (sales_engineer, 12 Oct 2026)
--
-- Founder rulings 1195-1200 (12 Oct 2026): customer-facing agents hold adaptive, expert conversations from knowledge
-- GIVEN in context (knowledge/brief/*.md, compiled by scripts/kb/compile_brief.mjs). Zero tolerance for "I don't know".
-- Where the knowledge falls short, the gap must be found and filled -- by Claude in a session, on the subscription,
-- never by an agent through OpenRouter.
--
-- MEASURED before this file: public.sales_knowledge_gap (28 rows) is filed only at the moment of a REFUSAL by
-- site_assistant / wa_inbound (retrieval era). Nothing read the conversations afterwards for the quieter failures:
-- a reply that hedged ("I'm not sure", "I'll check", "لا أعرف"), a customer who corrected the agent ("that's wrong",
-- "غلط"), or a reply the figure/policy guard refused and the model had to rewrite.
--
-- THIS FILE:
--   * adds kind/source/source_ref/excerpt/detector to sales_knowledge_gap (existing refusal rows keep kind 'refusal');
--   * columns verified against the live schema 12 Oct 2026 (review of #1352): quote_review_messages.role is
--     'sales_engineer' | 'supplier' (no 'assistant'), social_message.direction 'in' | 'out', guard_failures text[],
--     wa_messages.meta jsonb, agent_chats.role 'assistant' | 'user'.
--   * fn_knowledge_gap_sweep(p_hours, p_dry_run): code only, no model -- reads the last p_hours of
--       wa_messages (reply + inbound + meta.attempts), quote_review_messages (sales_engineer body, issues),
--       social_message (outbound body, guard_failures) and agent_chats (cat:* and brief assistant turns),
--     and files each hit once (question_norm = kind:source:ref is UNIQUE, so a re-run never doubles);
--   * registers the daily seat duty sales_engineer.knowledge_gap_sweep.
-- Filling a gap is NOT done here: Claude reads the open rows in a session, edits knowledge/brief/*.md, recompiles,
-- and closes the row with status 'knowledge_added'.
-- DOES NOT: score with a model (the existing judge is not called; phrases are enough to file, a human-grade read
-- happens when Claude fills it), or touch the refusal path that already files gaps.

-- review of #1352: a long export query held an AccessShareLock on this table on 12 Oct 2026 and the ALTER queued
-- behind it until statement_timeout. Fail fast instead of blocking every reader queued behind the ALTER.
set lock_timeout = '3s';
alter table public.sales_knowledge_gap add column if not exists kind text not null default 'refusal';
alter table public.sales_knowledge_gap add column if not exists source text;
alter table public.sales_knowledge_gap add column if not exists source_ref text;
alter table public.sales_knowledge_gap add column if not exists excerpt text;
alter table public.sales_knowledge_gap add column if not exists detector text;
do $$ begin
  alter table public.sales_knowledge_gap add constraint sales_knowledge_gap_kind_chk
    check (kind in ('refusal','hedge','corrected','guard_rewrite','asked_known'));
exception when duplicate_object then null; end $$;

-- The phrases. One place, so the test and the sweep agree. Arabic and English.
create or replace function public.fn_knowledge_gap_kind(p_agent text, p_customer text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $$
  select case
    when coalesce(p_agent,'') ~* '(i don.?t (know|have)|i do not (know|have)|rather not guess|i.?m not sure|i am not sure|not certain|i.?ll (check|confirm|get back)|i will (check|confirm|get back)|let me (check|confirm)|unable to (answer|say)|cannot (answer|say|confirm)|لا أعرف|لا اعرف|لست متأكد|غير متأكد|سأتحقق|سوف أتحقق|سأعود إليك)' then 'hedge'
    when coalesce(p_customer,'') ~* '(that.?s (wrong|not right|incorrect)|this is (wrong|incorrect)|you are wrong|not correct|incorrect|i already (told|said|sent)|as i said|غلط|خطأ|غير صحيح|قلت لك|ذكرت سابقا)' then
      case when p_customer ~* '(i already (told|said|sent)|as i said|قلت لك|ذكرت سابقا)' then 'asked_known' else 'corrected' end
    else null end
$$;

create or replace function public.fn_knowledge_gap_sweep(p_hours int default 26, p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_from timestamptz := now() - make_interval(hours => greatest(p_hours, 1));
  v_found int := 0; v_filed int := 0; v_by jsonb := '{}'::jsonb; r record;
begin
  for r in
    -- WhatsApp: the reply hedged, the next inbound corrected, or the gateway rewrote the reply
    select 'wa_messages' src, m.id::text ref, m.inbound q, m.reply a,
           coalesce(public.fn_knowledge_gap_kind(m.reply, null),
             public.fn_knowledge_gap_kind(null, m.inbound),
             case when m.meta::text ~ 'rewrite:' then 'guard_rewrite' end) kind
      from public.wa_messages m where m.created_at >= v_from
    union all
    select 'quote_review_messages', m.id::text, null, m.body,
           coalesce(case when m.role <> 'supplier' then public.fn_knowledge_gap_kind(m.body, null) end,
                    case when m.role = 'supplier' then public.fn_knowledge_gap_kind(null, m.body) end,
                    case when m.role <> 'supplier' and jsonb_typeof(m.issues) = 'array' and jsonb_array_length(m.issues) > 0 then 'guard_rewrite' end)
      from public.quote_review_messages m where m.created_at >= v_from
    union all
    select 'social_message', m.id::text, null, m.body,
           coalesce(case when m.direction = 'out' then public.fn_knowledge_gap_kind(m.body, null) end,
                    case when m.direction = 'in' then public.fn_knowledge_gap_kind(null, m.body) end,
                    case when coalesce(cardinality(m.guard_failures), 0) > 0 then 'guard_rewrite' end)
      from public.social_message m where m.created_at >= v_from
    union all
    select 'agent_chats', c.id::text, null, c.content,
           case when c.role = 'assistant' then public.fn_knowledge_gap_kind(c.content, null)
                else public.fn_knowledge_gap_kind(null, c.content) end
      from public.agent_chats c where c.created_at >= v_from and (c.agent_key like 'cat:%' or c.agent_key = 'brief')
  loop
    continue when r.kind is null;
    v_found := v_found + 1;
    v_by := jsonb_set(v_by, array[r.kind], to_jsonb(coalesce((v_by->>r.kind)::int, 0) + 1));
    if not p_dry_run then
      insert into public.sales_knowledge_gap (question_norm, question, refusal, kind, source, source_ref, excerpt, detector)
      values (r.kind || ':' || r.src || ':' || r.ref, left(coalesce(r.q, r.a, ''), 2000), left(coalesce(r.a, ''), 2000),
              r.kind, r.src, r.ref, left(coalesce(r.a, r.q, ''), 500), 'fn_knowledge_gap_sweep')
      on conflict (question_norm) do nothing;
      if found then v_filed := v_filed + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('from', v_from, 'found', v_found, 'filed', v_filed, 'by_kind', v_by, 'dry_run', p_dry_run,
    'open', (select count(*) from public.sales_knowledge_gap where status = 'open' and kind <> 'refusal'),
    'filled_by', 'Claude in a session on the subscription: edit knowledge/brief/*.md, recompile, set status knowledge_added');
end $$;

-- the duty runner calls the routine with no arguments
create or replace function public.fn_sales_engineer_knowledge_gap_tick()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $$ select public.fn_knowledge_gap_sweep(26, false) $$;

revoke execute on function public.fn_knowledge_gap_sweep(int, boolean) from public, anon, authenticated;
revoke execute on function public.fn_sales_engineer_knowledge_gap_tick() from public, anon, authenticated;
revoke execute on function public.fn_knowledge_gap_kind(text, text) from public, anon, authenticated;

insert into public.seat_duty (duty, what, every, enabled, routine, owner_file, owner_seat)
values ('sales_engineer.knowledge_gap_sweep',
  'Daily: every conversation where an agent hedged, was corrected, was told the customer already said it, or had its reply rewritten by the figure/policy guard is filed in sales_knowledge_gap (code only, no model). Claude fills them on the subscription (rulings 1195-1200).',
  '1 day', true, 'fn_sales_engineer_knowledge_gap_tick',
  'scripts/sql/the_sales_engineer_files_every_hedge_correction_and_rewrite_as_a_knowledge_gap.sql', 'sales_engineer')
on conflict (duty) do update set what = excluded.what, routine = excluded.routine, owner_file = excluded.owner_file,
  owner_seat = excluded.owner_seat, enabled = true;

-- PROBE: the phrase classifier on fixed strings; returns a verdict row, never raises.
select case when public.fn_knowledge_gap_kind('Sorry, I don''t know the lead time.', null) = 'hedge'
             and public.fn_knowledge_gap_kind('سأتحقق وأعود إليك', null) = 'hedge'
             and public.fn_knowledge_gap_kind(null, 'No, that''s wrong, it is a villa') = 'corrected'
             and public.fn_knowledge_gap_kind(null, 'I already told you the width') = 'asked_known'
             and public.fn_knowledge_gap_kind('A sliding door saves space in a studio.', 'ok thanks') is null
            then 'PROBE OK' else 'PROBE FAILED: fn_knowledge_gap_kind' end as verdict;
