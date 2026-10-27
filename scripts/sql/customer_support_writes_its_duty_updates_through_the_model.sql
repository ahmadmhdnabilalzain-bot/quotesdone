-- CUSTOMER SUPPORT WRITES ITS DUTY UPDATES THROUGH THE MODEL (27 Oct 2026). Assigned: customer_support.
-- Founder ruling, ledger 1339, verbatim: "the engineer and customer support never replies without llm unless the server
-- of open router is down". Scope reading pre-approved in ledger 1348: a message a person reads as a reply or an update
-- from customer_support is covered; legal and system notices (opt-out confirmation, sign-in codes, receipts) stay
-- code-written.
--
-- MEASURED 27 Oct 2026 (PR #1549 head 5b784df3c, read-only): two of its duties wrote the customer's words in SQL and
-- sent them through fn_customer_support_duty_send with no model in the path:
--   customer_support.complaint_deadlines  the complaint update ("Your complaint ... is now in review ...");
--   customer_support.incident_notices     the incident holding notice and the resolved notice.
-- SQL cannot call the model, so a duty that owes a message now RECORDS what is owed here, and the words are written in
-- TypeScript (supabase/functions/_shared/duty_voice.ts, resilience_ping step supportVoice, every 15 minutes):
--   * the duty decides WHAT and WHO (fn_customer_support_voice_owe): the stage and subject (the same once-per-key
--     identity fn_customer_support_duty_send keeps), the recipient, the language, the situation the model is to write
--     about, customer-safe facts (ledger 1338: no internal detail; an incident gives only it_engineer's customer note),
--     the text the reply must carry (a reference, a date), and the code-written DRAFT;
--   * duty_voice.ts asks aiReply (seat customer_support) for the words and sends modelOrOutage(reply, draft) through
--     fn_customer_support_voice_send -> fn_customer_support_duty_send (still the seat's one sending path). The draft
--     goes out ONLY when no call reached a model (5xx, network, timeout, open circuit; never a 4xx), and the send
--     refuses an 'outage_fallback' body that is not the recorded draft;
--   * the model up and nothing passing the guard: nothing is sent, fn_customer_support_voice_failed counts the
--     attempt, and the row is asked again next run; at VOICE_MAX_ATTEMPTS (6) it stops and the CEO is told once
--     (never for an example.invalid fixture).
-- Rows with the same voice_key share one model-written text (an incident notice is the same words for every person of
-- one side and language), so an incident costs one model call per language, not one per person.
-- WHAT THIS DOES NOT CHANGE: the email subject line stays code (a reference label, not prose); the opt-out
-- confirmation, sign-in codes and receipts stay code-written (legal/system notices, ledger 1348); every other duty
-- that still calls fn_customer_support_duty_send directly is out of this file's scope.
--
-- Prevented by: supabase/functions/_shared/duty_voice.test.ts and
-- scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs (static: neither duty calls
-- fn_customer_support_duty_send; aborted production probe: each duty records what it owes).
-- Apply at merge, BEFORE the two duty files of #1549 that call it:
--   node scripts/apply_sql.mjs scripts/sql/customer_support_writes_its_duty_updates_through_the_model.sql --apply --ddl

create table if not exists public.customer_support_voice_owed (
  stage        text not null check (stage ~ '^[a-z_]+\.[a-z_]+$'),
  subject_key  text not null check (btrim(subject_key) <> ''),
  voice_key    text not null check (btrim(voice_key) <> ''),
  to_role      text not null check (to_role in ('customer', 'supplier')),
  to_email     text not null,
  lang         text not null check (lang in ('en', 'ar')),
  subject      text not null,
  draft        text not null check (btrim(draft) <> ''),
  situation    text not null check (btrim(situation) <> ''),
  facts        text not null default '',
  must         text[] not null default '{}',
  attempts     int not null default 0,
  last_error   text,
  written_by   text check (written_by in ('model', 'outage_fallback')),
  written_at   timestamptz,
  result       jsonb,
  created_at   timestamptz not null default now(),
  primary key (stage, subject_key)
);
comment on table public.customer_support_voice_owed is
  'A customer_support duty message owed and not yet written. The duty records what to say; _shared/duty_voice.ts has the model write it (founder_instruction 1339); the draft is sent only on an OpenRouter outage.';
create index if not exists customer_support_voice_owed_due on public.customer_support_voice_owed (created_at) where written_at is null;
alter table public.customer_support_voice_owed enable row level security;
drop policy if exists customer_support_voice_owed_service_role_only on public.customer_support_voice_owed;
create policy customer_support_voice_owed_service_role_only on public.customer_support_voice_owed
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_support_voice_owed from anon, authenticated;

-- The duty's side: record a message owed. True when it is newly owed; false when it is already owed or already written
-- (fn_customer_support_duty_send's once-per-(stage, subject) record is read too, so nothing is ever written twice).
create or replace function public.fn_customer_support_voice_owe(p_stage text, p_key text, p_voice_key text, p_to_role text,
  p_email text, p_lang text, p_subject text, p_draft text, p_situation text, p_facts text, p_must text[] default '{}')
returns boolean
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_to text := lower(nullif(btrim(coalesce(p_email, '')), ''));
begin
  if v_to is null then return false; end if;
  if exists (select 1 from public.customer_support_duty_message where stage = p_stage and subject_key = p_key) then return false; end if;
  insert into public.customer_support_voice_owed (stage, subject_key, voice_key, to_role, to_email, lang, subject, draft, situation, facts, must)
  values (p_stage, p_key, p_voice_key, case when p_to_role = 'supplier' then 'supplier' else 'customer' end, v_to,
          case when p_lang = 'ar' and p_to_role <> 'supplier' then 'ar' else 'en' end,   -- suppliers always English (28 Sep)
          p_subject, p_draft, p_situation, coalesce(p_facts, ''), coalesce(p_must, '{}'))
  on conflict (stage, subject_key) do nothing;
  return found;
end $fn$;

-- What duty_voice.ts writes next: unwritten rows below the attempt limit, oldest first.
create or replace function public.fn_customer_support_voice_due(p_limit int default 50)
returns setof public.customer_support_voice_owed
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select * from public.customer_support_voice_owed
   where written_at is null and attempts < 6
   order by created_at, stage, subject_key
   limit greatest(1, least(coalesce(p_limit, 50), 200));
$fn$;

-- The send: the model's words, or (p_by = 'outage_fallback') exactly the recorded draft, through the seat's one path.
create or replace function public.fn_customer_support_voice_send(p_stage text, p_key text, p_body text, p_by text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.customer_support_voice_owed; v jsonb;
begin
  if p_by not in ('model', 'outage_fallback') then raise exception 'voice_send: p_by is model or outage_fallback, not %', p_by; end if;
  select * into r from public.customer_support_voice_owed where stage = p_stage and subject_key = p_key for update;
  if not found then return jsonb_build_object('sent', false, 'reason', 'nothing owed'); end if;
  if r.written_at is not null then return jsonb_build_object('sent', false, 'reason', 'already written'); end if;
  if coalesce(btrim(p_body), '') = '' then raise exception 'voice_send: an empty body is never sent'; end if;
  -- the code-written text may go out only as the reviewed draft, and only when the caller says the model was down
  if p_by = 'outage_fallback' and p_body is distinct from r.draft then
    raise exception 'voice_send: an outage fallback must be the recorded draft (founder_instruction 1339)';
  end if;
  v := public.fn_customer_support_duty_send(r.stage, r.subject_key, r.to_role, r.to_email, r.lang, r.subject, p_body);
  update public.customer_support_voice_owed set written_at = now(), written_by = p_by, result = v
   where stage = p_stage and subject_key = p_key;
  return v || jsonb_build_object('written_by', p_by);
end $fn$;

-- The model was up and nothing it wrote passed the guard (or the call threw): count it; at the limit the CEO is told once.
create or replace function public.fn_customer_support_voice_failed(p_stage text, p_key text, p_error text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.customer_support_voice_owed;
begin
  update public.customer_support_voice_owed set attempts = attempts + 1, last_error = left(coalesce(p_error, ''), 500)
   where stage = p_stage and subject_key = p_key and written_at is null
  returning * into r;
  if not found then return jsonb_build_object('ok', false, 'reason', 'nothing owed'); end if;
  if r.attempts >= 6 and not public.fn_is_demo_email(r.to_email) then
    perform public.fn_support_report_to_ceo(
      'voice_unwritten:' || r.stage || ':' || r.subject_key, 'elevated',
      'A customer_support ' || r.stage || ' message could not be written by the model after ' || r.attempts || ' tries',
      jsonb_build_object('stage', r.stage, 'subject', r.subject_key, 'to_role', r.to_role, 'lang', r.lang, 'last_error', r.last_error),
      jsonb_build_array('asked the model ' || r.attempts || ' times; every draft was refused by the reply guard'),
      'Decide what the person is told: the model was up, so no code-written text was sent (founder_instruction 1339).',
      p_source_agent => 'customer_support');
  end if;
  return jsonb_build_object('ok', true, 'attempts', r.attempts);
end $fn$;

revoke execute on function public.fn_customer_support_voice_owe(text, text, text, text, text, text, text, text, text, text, text[]) from public, anon, authenticated;
revoke execute on function public.fn_customer_support_voice_due(int) from public, anon, authenticated;
revoke execute on function public.fn_customer_support_voice_send(text, text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_customer_support_voice_failed(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_customer_support_voice_owe(text, text, text, text, text, text, text, text, text, text, text[]) to service_role;
grant execute on function public.fn_customer_support_voice_due(int) to service_role;
grant execute on function public.fn_customer_support_voice_send(text, text, text, text) to service_role;
grant execute on function public.fn_customer_support_voice_failed(text, text, text) to service_role;

-- The writer's clock: resilience_ping kicks supportVoice (detached, its own 120 s) every 15 minutes.
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('supportVoice', interval '15 min', 1500, 'plan', 0,
   'KICKED, not run inline: customer_support duty updates (complaint update, incident notices) are written by the model (_shared/duty_voice.ts, founder_instruction 1339); the draft only on an OpenRouter outage',
   'customer_support')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place, rank = excluded.rank,
       note = excluded.note, owner_seat = excluded.owner_seat;

-- PROBE: read-only. Returns ONE verdict row.
select case
  when has_function_privilege('anon', 'public.fn_customer_support_voice_send(text,text,text,text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_customer_support_voice_owe(text,text,text,text,text,text,text,text,text,text,text[])', 'execute')
    then 'PROBE FAILED: a voice routine is executable by anon or authenticated'
  when not exists (select 1 from public.resilience_step where step = 'supportVoice' and owner_seat = 'customer_support')
    then 'PROBE FAILED: the supportVoice step has no row or no owner'
  else 'PROBE OK' end as verdict;
