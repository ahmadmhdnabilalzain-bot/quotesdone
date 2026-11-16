-- SUPPORT AND THE IT ENGINEER HAND A FAULT BOTH WAYS: "IT IS BROKEN" REACHES THE IT ENGINEER AS A REAL HAND-OVER, AND THE
-- PERSON IS TOLD THROUGH SUPPORT WHEN THE FIX LANDS. Seats: customer_support (the hand-over, the person) and it_engineer
-- (the repair). Founder rulings 1574 (standing: "the IT engineer fixes the glitches it can fix itself") and 1705 (15 Nov 2026:
-- "Someone is registering and there is an issue ... The IT engineer should solve it, not report it ... the knowledge loop in the
-- company, where everyone knows what everyone else is doing, is extremely important"); 1706 (bring solutions, not issues).
--
-- MEASURED BEFORE WRITING (15 Nov 2026; SP/audit/SUPPORT_IT.md, light SELECTs and the code on origin/main 06881a2d6):
--   * support.root_cause hand-overs to it_engineer in 30 days: 0 (SELECT). The support reply names it_engineer as the owner of
--     "the site or app is broken, an error, a login or upload fault" (_shared/support_reply.ts ROUTE_SEATS) and only returns the
--     name; supportReply() itself has NO live caller today (READ: no surface imports it). The live surfaces (widget, WhatsApp,
--     e-mail) read every message with the reasoned decision needs_a_person (_shared/reasoned_decisions.ts), so that decision now
--     carries a third option, site_fault, chosen by the MODEL (ruling 1663: the LLM understands, code only checks), and each
--     surface hands a chosen site_fault here through _shared/support_fault_handover.ts.
--   * the existing conversation support.root_cause customer_support -> it_engineer (handler fn_seat_takes_support_root_cause,
--     originator_closes) is reused with payload path = 'live_fault' and subject table 'support_fault_report', so the weekly
--     root-cause loop (support_root_cause rows) is untouched.
--
-- WHAT THIS FILE DOES:
--   1. public.support_fault_report: one row per person per hour who told support something is broken: the channel, the case key,
--      the person's turns MASKED (no e-mail, phone, URL or long number), their e-mail when the channel knows it (e-mail, a
--      signed-in portal; never looked up from a phone: "a phone may confirm, never select"), the lead or customer the e-mail
--      owns, the hand-over, the IT finding, and when and how the person was told it was fixed. Service-role only.
--   2. fn_support_hands_it_a_fault(...): files the report, opens the finding support:fault:<case hash> (owner it_engineer) and
--      the support.root_cause hand-over (path live_fault), once per case per hour. A demo report is never filed (ruling 1199)
--      except under the duty fixtures switch.
--   3. fn_seat_takes_support_root_cause: the live body, plus the live_fault branch (fn_it_engineer_takes_a_support_fault),
--      which accepts the fault and waits for the repair.
--   4. fn_it_tells_the_person(...): the IT engineer's one way to reach a person: an owed message in customer_support's voice
--      (fn_customer_support_voice_owe -> _shared/duty_voice.ts: the MODEL writes it, the draft goes out only on an OpenRouter
--      outage, ruling 1339), suppression checked at the send (fn_customer_support_duty_send -> fn_email_sendable). A demo
--      address is reached only under the fixtures switch, a real one never under it.
--   5. fn_support_fault_fixed(p_issue_key, p_lead_id, p_observed): when the repair is verified, every open report for that
--      finding or that lead is told "fixed, here is the next step" (once), its hand-over completed with the observation, and
--      support.registration_rescued emitted for a registration. A person with no known e-mail is recorded as not told, never
--      silently skipped.
--   6. fn_it_mask_text: the identity mask for anything the IT engineer stores from a person's words.
--
-- NOT DONE HERE: no WhatsApp message (outside a 24-hour session only an approved template may be sent); no reply text written
-- by code (the reply in the moment stays the surface's model reply).
--
-- Prevented by: scripts/checks/the_it_engineer_repairs_a_registration_and_learns.test.mjs (source shape, and the local-database
-- replay of a planted fault: filed once per hour, told once when fixed, demo never filed).
--   node scripts/apply_sql.mjs scripts/sql/support_and_the_it_engineer_hand_a_fault_both_ways.sql --apply --ddl --seat customer_support

-- ── 6. THE MASK ─────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_mask_text(p_text text)
returns text language sql immutable set search_path to 'pg_catalog', 'pg_temp' as $fn$
  select left(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p_text, ''),
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
    '(https?://|www\.)[^\s,;)\]]+', '[link]', 'g'),
    '\+?[0-9٠-٩][0-9٠-٩ \-]{6,}[0-9٠-٩]', '[number]', 'g'),
    '\s+', ' ', 'g'), 1000)
$fn$;
revoke execute on function public.fn_it_mask_text(text) from public, anon, authenticated;

-- ── 1. THE REPORT ───────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.support_fault_report (
  id bigint generated always as identity primary key,
  reported_at timestamptz not null default now(),
  channel text not null check (channel in ('widget', 'whatsapp', 'email', 'portal')),
  case_key text not null check (length(btrim(case_key)) between 3 and 200),
  hour_key text not null,
  lang text not null default 'en' check (lang in ('en', 'ar')),
  audience text not null default 'visitor' check (audience in ('customer', 'supplier', 'visitor')),
  email text,                                          -- only what the channel already knows; never looked up from a phone
  lead_id bigint,
  customer_id uuid,
  turns jsonb not null default '[]'::jsonb,            -- masked by fn_it_mask_text
  handoff_id bigint,
  issue_key text not null,
  fixture boolean not null default false,
  told_at timestamptz,
  told text,                                           -- 'owed' | 'no_email' | 'not_sendable: ...'
  fixed_observed text,
  defect_id bigint,                                    -- the code defect it went into (fn_it_registration_watch), so it goes in once
  unique (case_key, hour_key)
);
alter table public.support_fault_report add column if not exists defect_id bigint;
create index if not exists support_fault_report_issue_idx on public.support_fault_report (issue_key) where told_at is null;
create index if not exists support_fault_report_lead_idx on public.support_fault_report (lead_id) where told_at is null and lead_id is not null;
alter table public.support_fault_report enable row level security;
drop policy if exists support_fault_report_service_role_only on public.support_fault_report;
create policy support_fault_report_service_role_only on public.support_fault_report as permissive for all to public using (false) with check (false);
revoke all on public.support_fault_report from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('support_fault_report', true, 'decision', 'a person told support something is broken: the masked turns, the hand-over to the IT engineer and when they were told it was fixed (ruling 1705)', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

-- ── 4. THE IT ENGINEER REACHES A PERSON ONLY THROUGH SUPPORT ────────────────────────────────────────────────────────
-- ONE PERSON, ONE REPAIR, ONE MESSAGE (review of f79833d44, FIX 3: one licence repair sent it_repair.done and three it_fault.fixed,
-- one per hourly report row; a verified defect sent it_defect.fixed and then it_fault.fixed to the same fault). The notices fall
-- in two classes, and a person hears at most one of a class inside its window, whichever routine reaches them first:
--   fixed   it_repair.done, it_fault.fixed, it_defect.fixed   one an hour (one repair is one tick or one verification)
--   opened  it_defect.opened                                    one a day ("we are fixing it" is said once)
-- fn_it_told_recently answers the stage already owed (or null), so a caller records the person as told by that notice.
-- (the owed row, and the sent record customer_support_duty_message in case an owed row was ever cleared)
create or replace function public.fn_it_told_recently(p_email text, p_class text)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select o.stage from (select stage, to_email, created_at from public.customer_support_voice_owed
                       union all select stage, lower(to_email), created_at from public.customer_support_duty_message where stage like 'it\_%') o
   where o.to_email = lower(btrim(coalesce(p_email, '')))
     and ((p_class = 'fixed' and o.stage in ('it_repair.done', 'it_fault.fixed', 'it_defect.fixed') and o.created_at > now() - interval '1 hour')
       or (p_class = 'opened' and o.stage = 'it_defect.opened' and o.created_at > now() - interval '1 day'))
   order by o.created_at desc limit 1
$fn$;
revoke execute on function public.fn_it_told_recently(text, text) from public, anon, authenticated;

create or replace function public.fn_it_tells_the_person(p_stage text, p_key text, p_role text, p_email text, p_lang text,
  p_subject text, p_draft text, p_situation text, p_facts text)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; v_to text := lower(nullif(btrim(coalesce(p_email, '')), ''));
  v_role text := case when p_role = 'supplier' then 'supplier' else 'customer' end;
  v_lang text := case when p_lang = 'ar' and p_role <> 'supplier' then 'ar' else 'en' end;
begin
  if v_to is null or p_stage !~ '^it_[a-z]+\.[a-z_]+$' then return false; end if;
  -- a fixture run reaches only a demo address, and a live run never reaches one
  if public.fn_is_demo_email(v_to) is distinct from v_fx then return false; end if;
  if p_stage in ('it_repair.done', 'it_fault.fixed', 'it_defect.fixed') and public.fn_it_told_recently(v_to, 'fixed') is not null then return false; end if;
  if p_stage = 'it_defect.opened' and public.fn_it_told_recently(v_to, 'opened') is not null then return false; end if;
  return public.fn_customer_support_voice_owe(p_stage, p_key, p_stage || ':' || v_lang || ':' || v_role, v_role, v_to, v_lang,
    p_subject, p_draft, p_situation, coalesce(p_facts, ''), '{}'::text[]);
end $fn$;
revoke execute on function public.fn_it_tells_the_person(text, text, text, text, text, text, text, text, text) from public, anon, authenticated;

-- ── 2. SUPPORT FILES THE FAULT ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_support_hands_it_a_fault(p_channel text, p_case_key text, p_lang text, p_audience text,
  p_turns jsonb, p_email text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
  v_hour text := to_char(now() at time zone 'UTC', 'YYYYMMDDHH24');
  v_key text := 'support:fault:' || left(md5(coalesce(p_case_key, '')), 16);
  v_turns jsonb; v_lead bigint; v_cust uuid; v_demo boolean; r public.support_fault_report; v_h bigint;
begin
  if p_channel is null or p_channel not in ('widget', 'whatsapp', 'email', 'portal') then
    return jsonb_build_object('filed', false, 'reason', 'unknown channel');
  end if;
  if coalesce(length(btrim(p_case_key)), 0) not between 3 and 200 then return jsonb_build_object('filed', false, 'reason', 'no case key'); end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then v_email := null; end if;
  -- the person's last turns, masked, at most 3, each at most 1000 characters
  select coalesce(jsonb_agg(jsonb_build_object('role', left(coalesce(t->>'role', 'person'), 20), 'text', public.fn_it_mask_text(t->>'text'))), '[]'::jsonb)
    into v_turns
    from (select t from jsonb_array_elements(case when jsonb_typeof(p_turns) = 'array' then p_turns else '[]'::jsonb end) with ordinality x(t, n)
           order by n desc limit 3) z;
  v_demo := (v_email is not null and public.fn_is_demo_email(v_email)) or coalesce(p_turns::text, '') ~* 'ZZ DEMO' or p_case_key ~* 'demo';
  if v_demo is distinct from v_fx then return jsonb_build_object('filed', false, 'reason', case when v_demo then 'a demo report is not filed (ruling 1199)' else 'a live report is not filed in a fixture run' end); end if;

  if v_email is not null then
    select l.id into v_lead from public.leads l where lower(btrim(l.claimed_by)) = v_email and not coalesce(l.banned, false) order by l.id desc limit 1;
    if v_lead is null then select c.id into v_cust from public.customers c where lower(btrim(c.email)) = v_email order by c.created_at desc limit 1; end if;
  end if;

  insert into public.support_fault_report (channel, case_key, hour_key, lang, audience, email, lead_id, customer_id, turns, issue_key, fixture)
  values (p_channel, p_case_key, v_hour, case when p_lang = 'ar' then 'ar' else 'en' end,
          case when p_audience in ('customer', 'supplier') then p_audience else 'visitor' end, v_email, v_lead, v_cust, v_turns, v_key, v_fx)
  on conflict (case_key, hour_key) do nothing
  returning * into r;
  if r.id is null then return jsonb_build_object('filed', false, 'reason', 'already filed for this case this hour', 'issue_key', v_key); end if;

  perform public.fn_it_engineer_finding_upsert(v_key,
    'A person told support something is broken (' || p_channel || ')',
    'customer_support -> it_engineer (support.root_cause, live_fault)', 'internal', 1,
    jsonb_build_object('owner_seat', 'it_engineer', 'subject', 'support', 'duty', 'support_fault', 'report_id', r.id, 'channel', p_channel,
                       'lead_id', v_lead, 'customer_id', v_cust, 'can_tell', v_email is not null, 'turns', v_turns, 'demo', v_fx),
    '{}'::text[], array['which fault the person hit: the IT engineer reads their account and the telemetry of the hour'], 'customer_support');

  if v_fx then perform set_config('qd.probe_files_demo_handoff', 'on', true); end if;
  v_h := public.fn_seat_handoff('customer_support', 'it_engineer', 'support.root_cause', 'support_fault_report', r.id::text,
    jsonb_build_object('path', 'live_fault', 'report_id', r.id, 'issue_key', v_key, 'channel', p_channel, 'lead_id', v_lead,
                       'customer_id', v_cust, 'can_tell', v_email is not null, 'turns', v_turns, 'demo', v_fx));
  if v_fx then perform set_config('qd.probe_files_demo_handoff', '', true); end if;
  update public.support_fault_report set handoff_id = v_h where id = r.id;
  return jsonb_build_object('filed', true, 'report_id', r.id, 'issue_key', v_key, 'handoff_id', v_h, 'can_tell', v_email is not null, 'lead_id', v_lead);
end $fn$;
revoke execute on function public.fn_support_hands_it_a_fault(text, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_support_hands_it_a_fault(text, text, text, text, jsonb, text) to service_role;

-- ── 3. THE IT ENGINEER TAKES IT ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_takes_a_support_fault(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'seat', 'it_engineer', 'report_id', a.detail->'report_id', 'issue_key', a.detail->>'issue_key',
    'waiting', 'the IT engineer repairs it within its guardrails (it_safe_fix_family) or opens a code defect for the engineer session; '
               || 'the person is told through support when the fix is verified (fn_support_fault_fixed)');
end $fn$;
revoke execute on function public.fn_it_engineer_takes_a_support_fault(bigint) from public, anon, authenticated;

-- the live body (customer_support_finds_the_root_cause_each_week_and_measures_the_fix.sql), plus the live_fault branch
create or replace function public.fn_seat_takes_support_root_cause(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  if a.agent = 'it_engineer' and a.detail->>'path' = 'live_fault' then
    return public.fn_it_engineer_takes_a_support_fault(p_id);
  end if;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'root_cause_id', a.detail->'root_cause_id', 'cause', a.detail->>'cause_key',
    'waiting', 'customer_support measures the cause''s weekly volume after the change and closes this when it falls');
end $fn$;
revoke execute on function public.fn_seat_takes_support_root_cause(bigint) from public, anon, authenticated;

-- ── 5. FIXED -> TOLD ────────────────────────────────────────────────────────────────────────────────────────────────
-- Every open report for the finding or the lead is closed with the observation, but ONE PERSON HEARS ONE "fixed" (FIX 3): the
-- first report of an address carries the message, the others (an hour apart, the same case) and any person a repair notice
-- already reached this hour are recorded as covered by it. Each support:fault finding whose reports are all told is closed
-- (FIX 9: a lead's support:fault findings stayed open when the repair was told by lead).
create or replace function public.fn_support_fault_fixed(p_issue_key text, p_lead_id bigint, p_observed text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_fault_report; v_owed boolean; n_told int := 0; n_no_email int := 0; n_covered int := 0; v_ar boolean; v_prev text;
  v_reached text[] := '{}'; v_keys text[] := '{}'; v_leads bigint[] := '{}'; k text;
begin
  if coalesce(btrim(p_observed), '') = '' then raise exception 'fn_support_fault_fixed: a fix is told only against what was observed'; end if;
  for r in select * from public.support_fault_report
            where told_at is null and ((p_issue_key is not null and issue_key = p_issue_key) or (p_lead_id is not null and lead_id = p_lead_id))
            order by id for update skip locked loop
    v_ar := r.lang = 'ar' and r.audience <> 'supplier';
    v_keys := v_keys || r.issue_key;
    if r.email is null then
      update public.support_fault_report set told_at = now(), told = 'no_email: the channel gave no address to write to', fixed_observed = left(p_observed, 500) where id = r.id;
      n_no_email := n_no_email + 1;
    elsif r.email = any (v_reached) or public.fn_it_told_recently(r.email, 'fixed') is not null then
      v_prev := coalesce(public.fn_it_told_recently(r.email, 'fixed'), 'it_fault.fixed');
      update public.support_fault_report set told_at = now(), told = 'covered: told once by ' || v_prev || ' (one notice per person per repair)',
             fixed_observed = left(p_observed, 500) where id = r.id;
      n_covered := n_covered + 1;
    else
      v_owed := public.fn_it_tells_the_person('it_fault.fixed', r.id::text, r.audience, r.email, r.lang,
        case when v_ar then 'QuotesDone: تم إصلاح المشكلة' else 'QuotesDone: the problem you told us about is fixed' end,
        case when v_ar then 'أخبرتمونا أن شيئًا لا يعمل على QuotesDone. تم إصلاحه الآن، ويمكنكم المتابعة من حيث توقفتم.' || chr(10) || chr(10) || 'فريق QuotesDone'
             else 'You told us something was not working on QuotesDone. It is fixed now, and you can carry on from where you stopped.' || chr(10) || chr(10) || 'The QuotesDone team' end,
        'Write a short e-mail telling them the problem they reported to us is fixed and they can carry on from where they stopped. Thank them for telling us.',
        'STATUS: fixed' || chr(10) || 'WHAT THEY CAN DO NOW: carry on from where they stopped');
      update public.support_fault_report set told_at = now(), told = case when v_owed then 'owed' else 'not_owed: already told or not reachable in this mode' end,
             fixed_observed = left(p_observed, 500) where id = r.id;
      v_reached := v_reached || r.email;
      if v_owed then n_told := n_told + 1; end if;
    end if;
    if r.handoff_id is not null then
      -- the originator (customer_support) closes its hand-over once the fix is observed (trg_handoff_only_originator_closes)
      perform set_config('qd.handoff_closer', 'customer_support', true);
      perform public.fn_seat_handoff_complete(r.handoff_id, jsonb_build_object('verdict', 'fixed', 'observed', left(p_observed, 500), 'told', r.email is not null,
                                                                          'closed_by', 'customer_support'));
      perform set_config('qd.handoff_closer', '', true);
    end if;
    if r.lead_id is not null and not r.lead_id = any (v_leads) then
      v_leads := v_leads || r.lead_id;
      perform public.fn_emit('support.registration_rescued', 'leads', r.lead_id::text, 'customer_support',
        jsonb_build_object('supplier_id', r.lead_id, 'issue_key', r.issue_key, 'report_id', r.id, 'told', r.email is not null, 'observed', left(p_observed, 300)));
    end if;
  end loop;
  if p_issue_key like 'support:fault:%' then v_keys := v_keys || p_issue_key; end if;
  foreach k in array array(select distinct x from unnest(v_keys) x where x like 'support:fault:%') loop
    if not exists (select 1 from public.support_fault_report where issue_key = k and told_at is null) then
      perform public.fn_it_engineer_finding_close(k, 'fixed and verified: ' || left(p_observed, 400));
    end if;
  end loop;
  return jsonb_build_object('told', n_told, 'covered', n_covered, 'no_email', n_no_email);
end $fn$;
revoke execute on function public.fn_support_fault_fixed(text, bigint, text) from public, anon, authenticated;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('fn_it_tells_the_person', 'fn_support_hands_it_a_fault', 'fn_it_engineer_takes_a_support_fault',
                                                  'fn_seat_takes_support_root_cause', 'fn_support_fault_fixed', 'fn_it_told_recently')
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'the mask is executable by a client' where has_function_privilege('anon', 'public.fn_it_mask_text(text)', 'execute')
    union all select 'the mask leaves an e-mail or a number' where public.fn_it_mask_text('write to a.b@c.ae or +971 50 123 4567') ~ '@|4567'
    union all select 'the report table is readable by a client' where has_table_privilege('anon', 'public.support_fault_report', 'select')
                                                                 or has_table_privilege('authenticated', 'public.support_fault_report', 'select')
    union all select 'the conversation support.root_cause customer_support -> it_engineer is not registered'
     where not exists (select 1 from public.seat_handoff_kind where type = 'support.root_cause' and from_seat = 'customer_support' and to_seat = 'it_engineer'
                         and handler = 'fn_seat_takes_support_root_cause')
  ) z) y;
