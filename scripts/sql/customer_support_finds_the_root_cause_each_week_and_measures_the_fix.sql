-- CUSTOMER SUPPORT FINDS THE ROOT CAUSE EACH WEEK AND MEASURES THE FIX — customer_support, 29 Sep 2026.
-- Founder instruction 1009, upgrade 7. Every week: group support cases and complaints by cause, fix what support
-- owns (FAQ, knowledge entries, wording) and record each fix, hand the rest to the owning seat as a tracked
-- improvement, and measure whether that cause's volume falls afterwards. Plain code: grouping by case category and
-- topic tags; no word matching.
--
-- STACKED ON #1036 (every_support_conversation_is_one_case_measured_rated_and_recovered.sql): its
-- support_customer_profile, its support_case columns (case_kind, channel, reopen_count ...) and its z50_ wires.
--
-- WHAT WAS THERE (measured 29 Sep 2026 on htdblwldjkcgjvmqkbeh): support_case had no category and no tags, so
-- nothing could say what a case was about except its free text. The structured signals already exist on the
-- rows the wires read: wa_messages.meta->>'choice' (the WhatsApp menu the customer pressed: qd_new, qd_follow,
-- qd_supplier, qd_general, qd_problem, qd_person), wa_messages.meta->'topics', ->'matched_faq_ids' and
-- ->>'unanswered_reason'; assistant_logs.matched_ids and answered; inbound_messages.ai_category (the triage
-- label); company_faq.section of any FAQ matched. customer_support_case_review (weekly) counts volume but groups
-- nothing and measures no fix.
--
-- WHAT THIS BUILDS
--   1. support_case.category and support_case.topic_tags, set ONLY from those structured values through
--      public.support_signal_category (source, value) -> category — a lookup, never a text pattern.
--      public.support_category names each category's OWNER seat and whether support fixes it itself.
--      A service_recovery case (a CSAT of 1-2, #1036) is category 'complaint'; a case still unset at the weekly
--      run is 'uncategorised' (support's to classify, so an unmapped signal becomes a mapping fix, not a gap).
--   2. z51_ triggers on wa_messages, assistant_logs and inbound_messages, after #1036's z50_ wires, classify the
--      person's open case. Each catches its own error: classification can never refuse a customer's message.
--   3. fn_customer_support_root_cause_week() (weekly duty customer_support.root_cause_loop):
--        a. groups the week's cases by (category, tag) into support_cause_week — a case with no tag counts under
--           tag '-'; each formal complaint ticket (complaint_tickets) counts as cause complaint/complaint_ticket;
--        b. a cause with at least support_root_cause_min_cases (seat_clock_policy, default 2) cases and no live
--           root cause opens ONE support_root_cause with that week's count as its baseline:
--             support fixes it (support_category.support_fixes): status 'open' until a fix is recorded;
--             another seat owns it: fn_seat_handoff('customer_support', owner, 'support.root_cause', ...), the
--             owner's handler accepts it, and ONLY customer_support closes it, on the measurement;
--        c. MEASURES every acted root cause: once support_root_cause_measure_weeks (default 2) full weeks have
--           passed since the fix/handoff, the cause's cases per week after are compared with the baseline:
--           fewer -> 'fell' (the handoff is completed with the numbers); otherwise 'not_fallen' — a support fix
--           goes back to 'open' for another fix, a handoff stays open with the measurement on it.
--   4. fn_support_root_cause_fix(id, kind, target_table, target_id, note) — the ONE door that records a support
--      fix (kind faq | knowledge_entry | wording), refusing a target row that does not exist. A company_faq row
--      tagged 'root_cause:<id>' records itself through a trigger, so an FAQ written for a cause is never unrecorded.
--   With qd.duty_fixtures = 'on' the weekly run reads, opens and measures ONLY ZZ DEMO cases.
--
-- Proved by scripts/sql/customer_support_finds_the_root_cause_each_week_and_measures_the_fix_probe.sql (aborted
-- transaction on ZZ DEMO @example.invalid data; must print PROBE OK).

-- ── 1. the vocabulary ───────────────────────────────────────────────────────────────────────────
create table if not exists public.support_category (
  category     text primary key check (category ~ '^[a-z_]+$'),
  owner_seat   text not null check (owner_seat in ('customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo')),
  support_fixes boolean not null,
  meaning      text not null check (btrim(meaning) <> '')
);
create table if not exists public.support_signal_category (
  source   text not null check (source in ('wa_choice', 'email_category', 'case_kind', 'faq_section')),
  value    text not null,
  category text not null references public.support_category(category),
  primary key (source, value)
);
alter table public.support_category enable row level security;
alter table public.support_signal_category enable row level security;
drop policy if exists support_category_service_role_only on public.support_category;
create policy support_category_service_role_only on public.support_category as permissive for all to public using (false) with check (false);
drop policy if exists support_signal_category_service_role_only on public.support_signal_category;
create policy support_signal_category_service_role_only on public.support_signal_category as permissive for all to public using (false) with check (false);
revoke all on public.support_category from anon, authenticated;
revoke all on public.support_signal_category from anon, authenticated;

insert into public.support_category (category, owner_seat, support_fixes, meaning) values
  ('general_question',    'customer_support', true,  'a question about how QuotesDone works: an FAQ or knowledge entry answers it'),
  ('knowledge_gap',       'customer_support', true,  'support could not ground an answer: a knowledge entry or FAQ is missing'),
  ('human_request',       'customer_support', true,  'the person asked for a human: the automated wording did not serve them'),
  ('uncategorised',       'customer_support', true,  'no mapped signal: support adds the missing row to support_signal_category'),
  ('quote_request',       'sales_engineer',   false, 'a new request for quotations'),
  ('quote_followup',      'sales_engineer',   false, 'following up an inquiry or quotation already made'),
  ('supplier_onboarding', 'sales_engineer',   false, 'a supplier joining, verifying or completing a profile'),
  ('billing',             'accountant',       false, 'a charge, invoice, fee or refund'),
  ('problem_report',      'it_engineer',      false, 'something on the platform did not work'),
  ('complaint',           'ceo',              false, 'a complaint or a low satisfaction score (service recovery)')
on conflict (category) do update set owner_seat = excluded.owner_seat, support_fixes = excluded.support_fixes, meaning = excluded.meaning;

insert into public.support_signal_category (source, value, category) values
  ('wa_choice', 'qd_new', 'quote_request'), ('wa_choice', 'qd_follow', 'quote_followup'),
  ('wa_choice', 'qd_supplier', 'supplier_onboarding'), ('wa_choice', 'qd_general', 'general_question'),
  ('wa_choice', 'qd_problem', 'problem_report'), ('wa_choice', 'qd_person', 'human_request'),
  ('email_category', 'other', 'general_question'),
  ('case_kind', 'service_recovery', 'complaint')
on conflict (source, value) do update set category = excluded.category;

-- ── 2. the case carries its cause ───────────────────────────────────────────────────────────────
alter table public.support_case
  add column if not exists category   text references public.support_category(category),
  add column if not exists topic_tags text[] not null default '{}';
create index if not exists support_case_category_opened_idx on public.support_case (category, opened_at);

-- The ONE classifier: the first mapped category sticks (a later signal only adds tags); tags are a set.
create or replace function public.fn_support_case_classify(p_case_id bigint, p_source text, p_value text, p_tags text[])
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_cat text;
begin
  if p_case_id is null then return; end if;
  select category into v_cat from public.support_signal_category where source = p_source and value = p_value;
  update public.support_case c
     set category = coalesce(c.category, v_cat),
         topic_tags = (select coalesce(array_agg(distinct t order by t), '{}')
                         from unnest(c.topic_tags || coalesce(p_tags, '{}')) t where coalesce(btrim(t), '') <> '')
   where c.case_id = p_case_id;
end $fn$;
revoke execute on function public.fn_support_case_classify(bigint, text, text, text[]) from public, anon, authenticated;

create or replace function public.fn_support_case_kind_category()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.category is null then
    select category into new.category from public.support_signal_category where source = 'case_kind' and value = new.case_kind;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_support_case_kind_category() from public, anon, authenticated;
drop trigger if exists a11_support_case_kind_category on public.support_case;
create trigger a11_support_case_kind_category before insert on public.support_case
  for each row execute function public.fn_support_case_kind_category();

-- the open case of a profile
create or replace function public.fn_support_open_case_of(p_profile bigint)
returns bigint language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case_id from public.support_case where customer_profile_id = p_profile and state <> 'closed'
   order by last_activity_at desc limit 1
$fn$;
revoke execute on function public.fn_support_open_case_of(bigint) from public, anon, authenticated;

-- WhatsApp: the menu choice, the topics, the FAQ sections matched, and an unanswered reason
create or replace function public.fn_support_classify_whatsapp()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_prof bigint; v_tags text[] := '{}';
begin
  if coalesce(btrim(new.inbound), '') = '' or jsonb_typeof(new.meta) is distinct from 'object' then return null; end if;
  begin
    select id into v_prof from public.support_customer_profile
     where phone_tail = right(regexp_replace(coalesce(new.wa_from, ''), '[^0-9]', '', 'g'), 9) order by last_seen_at desc limit 1;
    if v_prof is null then return null; end if;
    if jsonb_typeof(new.meta->'topics') = 'array' then
      v_tags := v_tags || array(select 'topic:' || t from jsonb_array_elements_text(new.meta->'topics') t);
    end if;
    if jsonb_typeof(new.meta->'matched_faq_ids') = 'array' then
      v_tags := v_tags || array(select 'faq:' || f.section from public.company_faq f
                                 where f.id::text in (select jsonb_array_elements_text(new.meta->'matched_faq_ids')));
    end if;
    if new.meta->>'unanswered_reason' is not null then v_tags := v_tags || 'unanswered'::text; end if;
    perform public.fn_support_case_classify(public.fn_support_open_case_of(v_prof), 'wa_choice', new.meta->>'choice', v_tags);
    if new.meta->>'unanswered_reason' is not null then
      update public.support_case set category = coalesce(category, 'knowledge_gap') where case_id = public.fn_support_open_case_of(v_prof);
    end if;
  exception when others then
    raise warning 'fn_support_classify_whatsapp: wa_messages % not classified: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_support_classify_whatsapp() from public, anon, authenticated;
drop trigger if exists z51_support_classify_whatsapp on public.wa_messages;
create trigger z51_support_classify_whatsapp after insert or update of meta on public.wa_messages
  for each row execute function public.fn_support_classify_whatsapp();

-- the widget and the portal assistant: the FAQ sections matched, and a question it could not answer
create or replace function public.fn_support_classify_widget()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_prof bigint; v_kind text := split_part(coalesce(new.audience, ''), ':', 1); v_id text := split_part(coalesce(new.audience, ''), ':', 2);
        v_tags text[] := '{}';
begin
  begin
    if v_kind = 'customer' and v_id ~ '^[0-9a-f-]{36}$' then
      select id into v_prof from public.support_customer_profile where customer_id = v_id::uuid;
    elsif v_kind = 'supplier' and v_id ~ '^[0-9]+$' then
      select id into v_prof from public.support_customer_profile where lead_id = v_id::bigint;
    end if;
    if v_prof is null then return null; end if;
    if new.matched_ids is not null then
      v_tags := v_tags || array(select 'faq:' || f.section from public.company_faq f
                                 where f.id::text = any (string_to_array(regexp_replace(new.matched_ids::text, '[{}\[\]" ]', '', 'g'), ',')));
    end if;
    if new.answered = false then v_tags := v_tags || 'unanswered'::text; end if;
    perform public.fn_support_case_classify(public.fn_support_open_case_of(v_prof), 'faq_section', null, v_tags);
    if new.answered = false then
      update public.support_case set category = coalesce(category, 'knowledge_gap') where case_id = public.fn_support_open_case_of(v_prof);
    elsif v_tags <> '{}' then
      update public.support_case set category = coalesce(category, 'general_question') where case_id = public.fn_support_open_case_of(v_prof);
    end if;
  exception when others then
    raise warning 'fn_support_classify_widget: assistant_logs % not classified: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_support_classify_widget() from public, anon, authenticated;
drop trigger if exists z51_support_classify_widget on public.assistant_logs;
create trigger z51_support_classify_widget after insert or update of answered, matched_ids on public.assistant_logs
  for each row execute function public.fn_support_classify_widget();

-- email: the triage label
create or replace function public.fn_support_classify_email()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_prof bigint; v_from text := lower(substring(coalesce(new.from_email, '') from '([^<>\s"]+@[^<>\s"]+)'));
begin
  if new.triaged_at is null or old.triaged_at is not null or coalesce(new.ai_category, '') = '' then return null; end if;
  begin
    select id into v_prof from public.support_customer_profile where email = v_from order by last_seen_at desc limit 1;
    if v_prof is null then return null; end if;
    perform public.fn_support_case_classify(public.fn_support_open_case_of(v_prof), 'email_category', new.ai_category,
                                            array['email:' || new.ai_category]);
  exception when others then
    raise warning 'fn_support_classify_email: inbound_messages % not classified: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_support_classify_email() from public, anon, authenticated;
drop trigger if exists z51_support_classify_email on public.inbound_messages;
create trigger z51_support_classify_email after update of triaged_at on public.inbound_messages
  for each row execute function public.fn_support_classify_email();

-- ── 3. causes, root causes, fixes ───────────────────────────────────────────────────────────────
create table if not exists public.support_cause_week (
  week_ending date not null,
  cause_key   text not null,
  category    text not null,
  topic_tag   text not null,
  owner_seat  text not null,
  cases       integer not null check (cases >= 0),
  reopened    integer not null default 0,
  fixture     boolean not null default false,
  primary key (week_ending, cause_key, fixture)
);
create table if not exists public.support_root_cause (
  id                bigint generated always as identity primary key,
  cause_key         text not null,
  category          text not null references public.support_category(category),
  topic_tag         text not null,
  owner_seat        text not null,
  support_fixes     boolean not null,
  opened_week       date not null,
  baseline_per_week numeric not null check (baseline_per_week > 0),
  status            text not null default 'open' check (status in ('open', 'handed_off', 'measuring', 'fell', 'not_fallen')),
  acted_at          timestamptz,
  handoff_id        bigint,
  measurements      jsonb not null default '[]'::jsonb,
  fixture           boolean not null default false,
  opened_at         timestamptz not null default now(),
  closed_at         timestamptz
);
create unique index if not exists support_root_cause_one_live_idx on public.support_root_cause (cause_key, fixture)
  where status in ('open', 'handed_off', 'measuring', 'not_fallen');
create table if not exists public.support_root_cause_fix (
  id            bigint generated always as identity primary key,
  root_cause_id bigint not null references public.support_root_cause(id),
  fix_kind      text not null check (fix_kind in ('faq', 'knowledge_entry', 'wording')),
  target_table  text not null,
  target_id     text not null,
  note          text,
  fixed_at      timestamptz not null default now(),
  unique (root_cause_id, target_table, target_id)
);
alter table public.support_cause_week enable row level security;
alter table public.support_root_cause enable row level security;
alter table public.support_root_cause_fix enable row level security;
drop policy if exists support_cause_week_service_role_only on public.support_cause_week;
create policy support_cause_week_service_role_only on public.support_cause_week as permissive for all to public using (false) with check (false);
drop policy if exists support_root_cause_service_role_only on public.support_root_cause;
create policy support_root_cause_service_role_only on public.support_root_cause as permissive for all to public using (false) with check (false);
drop policy if exists support_root_cause_fix_service_role_only on public.support_root_cause_fix;
create policy support_root_cause_fix_service_role_only on public.support_root_cause_fix as permissive for all to public using (false) with check (false);
revoke all on public.support_cause_week from anon, authenticated;
revoke all on public.support_root_cause from anon, authenticated;
revoke all on public.support_root_cause_fix from anon, authenticated;

-- 4. the one door for a support fix
create or replace function public.fn_support_root_cause_fix(p_root_cause_id bigint, p_kind text, p_target_table text, p_target_id text, p_note text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare rc public.support_root_cause; v_exists boolean;
begin
  select * into rc from public.support_root_cause where id = p_root_cause_id for update;
  if rc.id is null then raise exception 'no root cause %', p_root_cause_id; end if;
  if not rc.support_fixes then raise exception 'root cause % belongs to %; support records fixes only for causes it owns', rc.id, rc.owner_seat; end if;
  if p_target_table not in ('company_faq', 'kb_chunks', 'seat_prompt', 'wa_template', 'company_knowledge', 'support_signal_category') then
    raise exception 'a support fix is an FAQ, a knowledge entry or wording; % is none of them', p_target_table;
  end if;
  execute format('select exists (select 1 from public.%I where %s::text = $1)', p_target_table,
                 case when p_target_table = 'support_signal_category' then 'source || '':'' || value' else 'id' end)
    into v_exists using p_target_id;
  if not v_exists then raise exception 'the fix names %.% which does not exist', p_target_table, p_target_id; end if;
  insert into public.support_root_cause_fix (root_cause_id, fix_kind, target_table, target_id, note)
  values (rc.id, p_kind, p_target_table, p_target_id, p_note)
  on conflict (root_cause_id, target_table, target_id) do nothing;
  update public.support_root_cause set status = 'measuring', acted_at = now() where id = rc.id and status in ('open', 'not_fallen');
  return jsonb_build_object('ok', true, 'root_cause_id', rc.id, 'status', 'measuring');
end $fn$;
revoke execute on function public.fn_support_root_cause_fix(bigint, text, text, text, text) from public, anon, authenticated;

create or replace function public.fn_support_faq_records_its_root_cause()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare t text;
begin
  for t in select x from unnest(coalesce(new.tags, '{}')) x where x ~ '^root_cause:[0-9]+$' loop
    begin
      perform public.fn_support_root_cause_fix(substring(t from 12)::bigint, 'faq', 'company_faq', new.id::text, 'FAQ tagged ' || t);
    exception when others then
      raise warning 'company_faq % names % but the fix was not recorded: %', new.id, t, sqlerrm;
    end;
  end loop;
  return null;
end $fn$;
revoke execute on function public.fn_support_faq_records_its_root_cause() from public, anon, authenticated;
drop trigger if exists z60_support_faq_records_its_root_cause on public.company_faq;
create trigger z60_support_faq_records_its_root_cause after insert or update of tags on public.company_faq
  for each row execute function public.fn_support_faq_records_its_root_cause();

-- the owning seat accepts a handed-off cause; customer_support closes it on the measurement
create or replace function public.fn_seat_takes_support_root_cause(p_id bigint)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'root_cause_id', a.detail->'root_cause_id', 'cause', a.detail->>'cause_key',
    'waiting', 'customer_support measures the cause''s weekly volume after the change and closes this when it falls');
end $fn$;
revoke execute on function public.fn_seat_takes_support_root_cause(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, originator_closes, owner_file)
select 'support.root_cause', 'customer_support', s,
       'A support cause (category and topic) recurring past the weekly threshold is this seat''s to remove: change what produces it. customer_support measures the cause''s weekly volume afterwards and closes it when it falls.',
       'fn_seat_takes_support_root_cause', true, 'scripts/sql/customer_support_finds_the_root_cause_each_week_and_measures_the_fix.sql'
  from unnest(array['sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo']) s
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ── the weekly loop ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_support_root_cause_week()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_from timestamptz := now() - interval '7 days';
  v_min int := greatest(1, public.fn_seat_clock_policy('support_root_cause_min_cases', 2)::int);
  v_mw int := greatest(1, public.fn_seat_clock_policy('support_root_cause_measure_weeks', 2)::int);
  r record; v_id bigint; v_hid bigint; v_after numeric; v_weeks numeric; v_verdict text;
  n_open int := 0; n_hand int := 0; n_meas int := 0; n_fell int := 0;
begin
  -- a case still unset is support's to classify
  update public.support_case c set category = 'uncategorised'
   where c.category is null and c.opened_at >= v_from
     and (c.subject like '%ZZ DEMO%' or exists (select 1 from public.support_customer_profile p
                                                where p.id = c.customer_profile_id and public.fn_is_demo_email(p.email))) = v_fx;

  -- a. group the week by cause
  delete from public.support_cause_week where week_ending = v_week and fixture = v_fx;
  insert into public.support_cause_week (week_ending, cause_key, category, topic_tag, owner_seat, cases, reopened, fixture)
  select v_week, x.category || '/' || x.tag, x.category, x.tag, sc.owner_seat, count(*), count(*) filter (where x.reopen_count > 0), v_fx
    from (select c.case_id, c.category, c.reopen_count, t.tag
            from public.support_case c
            left join public.support_customer_profile p on p.id = c.customer_profile_id
            cross join lateral unnest(case when cardinality(c.topic_tags) = 0 then array['-'] else c.topic_tags end) t(tag)
           where c.opened_at >= v_from and c.category is not null
             and (c.subject like '%ZZ DEMO%' or coalesce(public.fn_is_demo_email(p.email), false)) = v_fx
          union all
          -- a formal complaint (Complaints Policy ticket) is a complaint cause of its own
          select null, 'complaint', 0, 'complaint_ticket' from public.complaint_tickets t
           where t.created_at >= v_from and public.fn_is_demo_email(t.email) = v_fx) x
    join public.support_category sc on sc.category = x.category
   group by x.category, x.tag, sc.owner_seat;

  -- b. a recurring cause opens one root cause
  for r in select w.*, sc.support_fixes from public.support_cause_week w join public.support_category sc on sc.category = w.category
            where w.week_ending = v_week and w.fixture = v_fx and w.cases >= v_min
              and not exists (select 1 from public.support_root_cause rc where rc.cause_key = w.cause_key and rc.fixture = v_fx
                                 and rc.status in ('open', 'handed_off', 'measuring', 'not_fallen'))
            order by w.cases desc loop
    insert into public.support_root_cause (cause_key, category, topic_tag, owner_seat, support_fixes, opened_week, baseline_per_week, fixture)
    values (r.cause_key, r.category, r.topic_tag, r.owner_seat, r.support_fixes, v_week, r.cases, v_fx)
    returning id into v_id;
    n_open := n_open + 1;
    if not r.support_fixes then
      v_hid := public.fn_seat_handoff('customer_support', r.owner_seat, 'support.root_cause', 'support_root_cause', v_id::text,
        jsonb_build_object('root_cause_id', v_id, 'cause_key', r.cause_key, 'category', r.category, 'topic_tag', r.topic_tag,
                           'cases_this_week', r.cases, 'reopened', r.reopened, 'week_ending', v_week));
      update public.support_root_cause set status = 'handed_off', handoff_id = v_hid, acted_at = now() where id = v_id;
      n_hand := n_hand + 1;
    end if;
  end loop;

  -- c. measure every acted cause once its window has passed
  for r in select * from public.support_root_cause
            where fixture = v_fx and status in ('handed_off', 'measuring') and acted_at <= now() - make_interval(weeks => v_mw) loop
    v_weeks := greatest(1, floor(extract(epoch from now() - r.acted_at) / 604800));
    if r.topic_tag = 'complaint_ticket' then
      select count(*) / v_weeks into v_after from public.complaint_tickets t
       where t.created_at > r.acted_at and public.fn_is_demo_email(t.email) = r.fixture;
    else
      select count(*) / v_weeks into v_after
        from public.support_case c left join public.support_customer_profile p on p.id = c.customer_profile_id
       where c.category = r.category and c.opened_at > r.acted_at
         and ((r.topic_tag = '-' and cardinality(c.topic_tags) = 0) or r.topic_tag = any (c.topic_tags))
         and (c.subject like '%ZZ DEMO%' or coalesce(public.fn_is_demo_email(p.email), false)) = r.fixture;
    end if;
    v_verdict := case when v_after < r.baseline_per_week then 'fell' else 'not_fallen' end;
    update public.support_root_cause
       set measurements = measurements || jsonb_build_array(jsonb_build_object('at', now(), 'weeks', v_weeks,
                            'after_per_week', round(v_after, 2), 'baseline_per_week', r.baseline_per_week, 'verdict', v_verdict)),
           status = case when v_verdict = 'fell' then 'fell' when r.support_fixes then 'not_fallen' else 'handed_off' end,
           closed_at = case when v_verdict = 'fell' then now() end,
           acted_at = case when v_verdict = 'fell' or r.support_fixes then acted_at else now() end
     where id = r.id;
    n_meas := n_meas + 1;
    if v_verdict = 'fell' then
      n_fell := n_fell + 1;
      if r.handoff_id is not null then
        perform set_config('qd.handoff_closer', 'customer_support', true);
        perform public.fn_seat_handoff_complete(r.handoff_id, jsonb_build_object('verified_by', 'customer_support', 'root_cause_id', r.id,
          'baseline_per_week', r.baseline_per_week, 'after_per_week', round(v_after, 2)));
        perform set_config('qd.handoff_closer', '', true);
      end if;
    elsif r.handoff_id is not null then
      update public.agent_actions set detail = detail || jsonb_build_object('last_measurement',
               jsonb_build_object('at', now(), 'after_per_week', round(v_after, 2), 'baseline_per_week', r.baseline_per_week, 'verdict', 'not_fallen'))
       where id = r.handoff_id;
    end if;
  end loop;

  return jsonb_build_object('week_ending', v_week, 'fixture', v_fx,
    'causes', (select count(*) from public.support_cause_week where week_ending = v_week and fixture = v_fx),
    'root_causes_opened', n_open, 'handed_off', n_hand, 'measured', n_meas, 'fell', n_fell,
    'support_to_fix', (select count(*) from public.support_root_cause where fixture = v_fx and status in ('open', 'not_fallen')));
end $fn$;
revoke execute on function public.fn_customer_support_root_cause_week() from public, anon, authenticated;
grant execute on function public.fn_customer_support_root_cause_week() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.root_cause_loop', 'customer_support', interval '7 days', 'fn_customer_support_root_cause_week',
   'the weekly root-cause loop: cases grouped by category and topic, support''s own causes fixed and recorded, the rest handed to the owning seat, and each cause''s volume measured after the change',
   'scripts/sql/customer_support_finds_the_root_cause_each_week_and_measures_the_fix.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
