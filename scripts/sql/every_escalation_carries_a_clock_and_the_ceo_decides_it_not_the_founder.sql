-- EVERY ESCALATION CARRIES A CLOCK, AND THE CEO DECIDES IT, NOT THE FOUNDER
-- customer_support (owner of the reply) + ceo (the decider). Agent: FOUNDER_CLOCK. 16 Nov 2026.
-- Founder rulings 1696, 1706, 1710 (15-16 Nov 2026): the CEO has full authority and does not rely on the founder; the seats never
-- bring him issues; "don't wait on me". Hole hunt of 16 Nov 2026 (FAILURES items 1, 4, 7, 11).
--
-- WHAT WAS WRONG (READ from origin/main 55489dde7; SELECT = a light production read of 16 Nov, counts only):
--   1. fn_review_request_open filed an explicit person request, paged the founder and set the row 'with_founder'. Nothing else ever
--      reads 'with_founder' (SELECT on pg_proc: only the opener and a runway figure). The e-mail reply had promised "a member of the
--      team will reply to them in this same thread" (email_triage/index.ts, the person branch): a promise with no owner and no
--      deadline. SELECT: 5 rows 'with_founder' -- 4 from reserved fixture numbers (+971 50 000 00xx, fn_is_demo_phone true; the hole
--      report called them real, they are not) and 1 site-chat visitor, 5 days old, with no e-mail or phone on file.
--      A WhatsApp escalation became a support_ceo_report 'serious' that the CEO "accepts" daily for ever (137 accepted, 0 completed).
--   7. A payer held by the stripe_live_hold switch is told "our team has been told and will be in touch with you"
--      (_shared/stripe_live_hold.ts); no routine reads the switch or tells anyone when it opens. SELECT: 0 held payers today; the
--      switch does not read 'off'.
--  11. No seat can see that the founder has not answered for days, or that a channel is down because only he can renew its credential
--      (ruling 1090 keeps that silent, correctly), so seats promise on a dead channel or wait on a man who is away.
--
-- WHAT IS NOW TRUE:
--   - public.escalation_clock: every escalation is a case with a clock -- what was promised, on which channel, when, and when the
--     person is next owed word. customer_support owns the reply (owner_seat), the CEO seat decides (decider_seat).
--   - fn_review_request_open's person route opens a clock and hands the matter to the CEO seat. The founder is no longer paged for a
--     person request (rulings 1696/1706/1710 supersede 1264 on this point). The row reads 'with_ceo'.
--   - fn_escalation_clocks_due feeds the CEO seat's heartbeat (ceo_agent action escalation_clocks, _shared/escalation_clock.ts): the
--     CEO's MODEL decides within its authority; customer_support's MODEL writes the person the decision or, when the clock runs out
--     with no decision, an honest status; the founder is told ONLY what the CEO answered it cannot decide by law
--     (fn_escalation_clock_ceo_decided, state 'founder_by_law', founder_mail_policy kind 'escalation_by_law').
--   - fn_escalation_clock_deliver sends on the person's own channel through the normal paths: WhatsApp only inside their 24-hour
--     window (no template: a message they sent is not an opt-in, ruling 1341), otherwise e-mail through
--     fn_customer_support_duty_send (fn_email_sendable: a bounced or complained address is never written; once per stage); a fixture
--     is never sent outside the duty-fixture switch (ruling 1199).
--   - fn_held_payers_sync puts every payer the live hold stopped on a clock (kind held_payment); the heartbeat reads the switch
--     (fn_stripe_live_hold_reads_off, READ ONLY: nothing here writes it) and tells each the day it reads 'off'.
--   - fn_founder_availability and fn_escalation_case_facts: "founder last answered at" and "channel down (founder credential)" are
--     facts every seat's case context reads (_shared/case_context.ts), with the person's own open escalations, so a seat gives an
--     honest status or switches channel without paging him.
--   - fn_escalation_clock_adopts_stale_person_requests: the ONE-OFF for the requests left 'with_founder'. Dry run by default.
--
-- prevented by: scripts/sql/every_escalation_carries_a_clock_and_the_ceo_decides_it_not_the_founder_probe.sql,
--               supabase/functions/_shared/escalation_clock.test.ts
set lock_timeout = '3s';

-- ---------------------------------------------------------------------------------------------
-- 1. THE CASE WITH A CLOCK
-- ---------------------------------------------------------------------------------------------
create table if not exists public.escalation_clock (
  id              bigint generated always as identity primary key,
  source_table    text not null,
  source_id       text not null,
  kind            text not null,
  channel         text not null,
  requester       text not null,
  audience        text not null default 'customer',
  lang            text not null default 'en',
  subject_line    text,
  request_text    text,
  promised        text not null,
  promised_at     timestamptz not null default now(),
  status_due_at   timestamptz not null,
  owner_seat      text not null default 'customer_support',
  decider_seat    text not null default 'ceo',
  state           text not null default 'open',
  statuses_sent   integer not null default 0,
  last_told_at    timestamptz,
  last_told_via   text,
  last_told_text  text,
  ceo_tried_at    timestamptz,
  ceo_attempts    integer not null default 0,
  ceo_decision    text,
  ceo_reason      text,
  ceo_model       text,
  decided_at      timestamptz,
  founder_reason  text,
  founder_told_at timestamptz,
  attempts        integer not null default 0,
  last_error      text,
  closed_at       timestamptz,
  closed_reason   text,
  fixture         boolean not null default false,
  detail          jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint escalation_clock_kind_known check (kind in ('person', 'escalation', 'press', 'legal', 'regulator', 'held_payment')),
  constraint escalation_clock_channel_known check (channel in ('email', 'whatsapp', 'site_chat', 'portal')),
  constraint escalation_clock_state_known check (state in ('open', 'decided', 'founder_by_law', 'closed')),
  constraint escalation_clock_audience_known check (audience in ('customer', 'supplier', 'visitor', 'press', 'counsel', 'regulator')),
  constraint escalation_clock_lang_known check (lang in ('en', 'ar')),
  constraint escalation_clock_has_a_requester check (btrim(requester) <> ''),
  constraint escalation_clock_has_a_promise check (btrim(promised) <> ''),
  -- a decision is never recorded without its reasoning; the founder is never told without the law that needs him
  constraint escalation_clock_decided_has_its_reason check (state not in ('decided', 'founder_by_law') or (btrim(coalesce(ceo_reason, '')) <> '' and decided_at is not null)),
  constraint escalation_clock_founder_only_by_law check (state <> 'founder_by_law' or btrim(coalesce(founder_reason, '')) <> ''),
  constraint escalation_clock_closed_has_its_reason check (state <> 'closed' or (closed_at is not null and btrim(coalesce(closed_reason, '')) <> ''))
);
comment on table public.escalation_clock is
  'Every escalation as a case with a clock: what was promised, on which channel, when, and when the person is next owed word. customer_support owns the reply, the CEO seat decides; the founder only for what the law reserves to him (rulings 1696/1706/1710). every_escalation_carries_a_clock_and_the_ceo_decides_it_not_the_founder.sql';
-- one live clock per subject; a closed one does not stop the next escalation from the same person opening its own
create unique index if not exists escalation_clock_one_live_per_subject on public.escalation_clock (source_table, source_id) where state <> 'closed';
create index if not exists escalation_clock_due_idx on public.escalation_clock (status_due_at) where state <> 'closed';
alter table public.escalation_clock enable row level security;
drop policy if exists escalation_clock_service_role_only on public.escalation_clock;
create policy escalation_clock_service_role_only on public.escalation_clock as permissive for all to public using (false) with check (false);
revoke all on public.escalation_clock from anon, authenticated;

-- a person request now reads 'with_ceo' (the CEO seat holds it on its clock); 'with_founder' stays legal for the rows already there
-- until the one-off below adopts them
alter table public.decision_review_request drop constraint if exists decision_review_request_status_check;
alter table public.decision_review_request add constraint decision_review_request_status_check
  check (status = any (array['open'::text, 'decided'::text, 'with_founder'::text, 'with_ceo'::text]));

-- the clock's three numbers, the CEO's to move (decision_policy, read by fn_seat_clock_policy)
insert into public.decision_policy (key, value, description) values
  ('escalation_status_after_hours', to_jsonb(4), 'Hours after an escalation was promised before customer_support writes the person an honest status if the CEO has not decided (escalation_clock).'),
  ('escalation_status_repeat_hours', to_jsonb(24), 'Hours between two honest statuses on the same open escalation (escalation_clock).'),
  ('escalation_status_max', to_jsonb(5), 'At most this many statuses on one escalation; after it the case stays on the CEO''s board and the person is not written again (escalation_clock).')
on conflict (key) do nothing;

-- the one founder route left here: what the CEO answered the law reserves to him (never a person request, never a complaint)
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('escalation_by_law', true,
        'Rulings 1696/1706/1710: the CEO decides every escalation; the founder is told only of one the CEO answered it cannot decide by law (a court or regulator demanding the licence holder in person), with that law named.',
        'ceo')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role;

-- ---------------------------------------------------------------------------------------------
-- 2. OPEN A CLOCK (idempotent per live subject)
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_escalation_clock_open(
  p_source_table text, p_source_id text, p_kind text, p_channel text, p_requester text,
  p_promised text default null, p_request_text text default null, p_subject_line text default null,
  p_detail jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_after numeric := public.fn_seat_clock_policy('escalation_status_after_hours', 4);
  v_generic boolean := coalesce(btrim(p_promised), '') = '';
  v_promised text := coalesce(nullif(btrim(p_promised), ''),
    'They asked on ' || replace(coalesce(p_channel, 'a channel'), '_', ' ') || ' for a person; the reply on that channel acknowledged it (its words are not recorded here).');
  v_detail jsonb := coalesce(p_detail, '{}'::jsonb);
  v_fixture boolean := public.fn_is_demo_phone(p_requester) or public.fn_is_demo_email(p_requester)
                       or coalesce((p_detail->>'fixture')::boolean, false);
  c public.escalation_clock;
begin
  if coalesce(btrim(p_source_table), '') = '' or coalesce(btrim(p_source_id), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'a clock must name its subject');
  end if;
  if coalesce(btrim(p_requester), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'a clock must name who is waiting');
  end if;
  select * into c from public.escalation_clock where source_table = p_source_table and source_id = p_source_id and state <> 'closed';
  if found then
    -- the later caller knows more: the exact words that were sent replace a generic promise; a press, legal or regulator reading
    -- is a fact that sharpens the kind; nothing else changes and the clock keeps its time
    update public.escalation_clock
       set promised = case when not v_generic and coalesce((detail->>'promise_generic')::boolean, false) then left(v_promised, 2000) else promised end,
           detail = case when not v_generic then detail - 'promise_generic' else detail end || (v_detail - 'fixture'),
           kind = case when p_kind in ('press', 'legal', 'regulator') then p_kind else kind end,
           request_text = coalesce(request_text, left(p_request_text, 4000)),
           updated_at = now()
     where id = c.id;
    return jsonb_build_object('ok', true, 'id', c.id, 'existing', true);
  end if;
  insert into public.escalation_clock (source_table, source_id, kind, channel, requester, audience, lang, subject_line, request_text,
                                       promised, promised_at, status_due_at, fixture, detail)
  values (p_source_table, p_source_id, p_kind, p_channel, btrim(p_requester),
          case when v_detail->>'audience' in ('customer', 'supplier', 'visitor', 'press', 'counsel', 'regulator') then v_detail->>'audience' else 'customer' end,
          case when v_detail->>'lang' = 'ar' then 'ar' else 'en' end,
          left(p_subject_line, 300), left(p_request_text, 4000), left(v_promised, 2000),
          coalesce((v_detail->>'promised_at')::timestamptz, now()),
          coalesce((v_detail->>'promised_at')::timestamptz, now()) + make_interval(secs => v_after * 3600),
          v_fixture,
          (v_detail - 'fixture' - 'promised_at' - 'audience' - 'lang') || case when v_generic then jsonb_build_object('promise_generic', true) else '{}'::jsonb end)
  returning * into c;
  return jsonb_build_object('ok', true, 'id', c.id, 'existing', false, 'fixture', c.fixture, 'status_due_at', c.status_due_at);
end $fn$;
revoke execute on function public.fn_escalation_clock_open(text, text, text, text, text, text, text, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. THE PERSON ROUTE GOES TO THE CEO WITH A CLOCK (was: the founder paged, the row left 'with_founder')
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_review_request_open(p_decision_type text, p_channel text, p_requester text, p_request_text text, p_subject_table text DEFAULT NULL::text, p_subject_id text DEFAULT NULL::text, p_original_seat text DEFAULT NULL::text, p_original_model text DEFAULT NULL::text, p_original_decision_log_id bigint DEFAULT NULL::bigint, p_dedupe_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_route public.review_route; v_id bigint; v_handoff bigint; v_clock jsonb;
begin
  select * into v_route from public.review_route where decision_type = p_decision_type;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no review_route for decision type ' || coalesce(p_decision_type, 'null'));
  end if;
  -- ruling 1264: no portal (or any other) option; a contest or a person request enters only from chat or e-mail
  if coalesce(p_channel, '') not in ('whatsapp', 'site_chat', 'email') then
    return jsonb_build_object('ok', false, 'error', 'a contest or a person request enters only from chat or e-mail, not ' || coalesce(p_channel, 'null'));
  end if;
  if p_dedupe_key is not null then
    select id, handoff_id into v_id, v_handoff from public.decision_review_request where dedupe_key = p_dedupe_key;
    if v_id is not null then
      return jsonb_build_object('ok', true, 'id', v_id, 'owner_seat', v_route.owner_seat, 'handoff_id', v_handoff, 'existing', true);
    end if;
  end if;
  insert into public.decision_review_request (decision_type, owner_seat, channel, requester, subject_table, subject_id,
         request_text, original_seat, original_model, original_decision_log_id, dedupe_key)
  values (v_route.decision_type, v_route.owner_seat, p_channel, p_requester, p_subject_table, p_subject_id,
          left(p_request_text, 4000), p_original_seat, p_original_model, p_original_decision_log_id, p_dedupe_key)
  returning id into v_id;
  -- AN EXPLICIT PERSON REQUEST IS THE CEO'S, WITH A CLOCK (16 Nov 2026, rulings 1696/1706/1710; was ruling 1264's one founder
  -- route). The clock is keyed on the message's own subject when the channel names one (the e-mail, the WhatsApp number), so the
  -- channel's own call after its reply (which knows the exact words sent) lands on the same clock. customer_support owns the reply;
  -- the CEO seat decides; the founder hears only what the CEO says the law reserves to him. The review row is never decided by a
  -- model (decision_review_a_person_request_is_never_decided_by_a_model): the clock is where the matter is worked.
  if v_route.decision_type = 'person' then
    v_clock := public.fn_escalation_clock_open(coalesce(p_subject_table, 'decision_review_request'), coalesce(p_subject_id, v_id::text),
                 'person', p_channel, p_requester, null, p_request_text, null,
                 jsonb_build_object('review_request_id', v_id));
    update public.decision_review_request set status = 'with_ceo',
           evidence = evidence || jsonb_build_object('escalation_clock_id', v_clock->'id')
     where id = v_id;
    return jsonb_build_object('ok', true, 'id', v_id, 'owner_seat', 'ceo', 'escalation_clock', v_clock);
  end if;
  -- the owning seat's queue; null for a demo subject (fn_seat_handoff files no handoff from a demo row)
  v_handoff := public.fn_seat_handoff('customer_support', v_route.owner_seat, 'review.requested',
                 'decision_review_request', v_id::text,
                 jsonb_build_object('review_request_id', v_id, 'decision_type', v_route.decision_type,
                                    'channel', p_channel, 'requester', p_requester, 'original_model', p_original_model,
                                    'request', left(p_request_text, 500), 'email', case when p_requester like '%@%' then p_requester end,
                                    'subject_table', p_subject_table, 'subject_ref', p_subject_id));
  update public.decision_review_request set handoff_id = v_handoff where id = v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'owner_seat', v_route.owner_seat, 'handoff_id', v_handoff);
end $function$;
revoke execute on function public.fn_review_request_open(text, text, text, text, text, text, text, text, bigint, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 4. WHAT EVERY SEAT KNOWS ABOUT THE FOUNDER'S ABSENCE (item 11; ruling 1090 respected: read, never reminded)
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_founder_availability()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with last_word as (
    select greatest((select max(received_at) from public.ceo_command where from_identity = 'founder'),
                    (select max(received_at) from public.founder_directive),
                    (select max(said_at) from public.founder_instruction)) at_
  )
  select jsonb_build_object(
    'founder_last_answered_at', (select at_ from last_word),
    'founder_hours_since', (select floor(extract(epoch from now() - at_) / 3600)::int from last_word),
    -- a credential only the founder can renew is recorded by the IT engineer and never reminded (ruling 1090); the customer-facing
    -- seats read it so they never promise on that channel, and never page him about it
    'channels_down_founder_credential', coalesce((
      select jsonb_agg(jsonb_build_object('integration', split_part(f.issue_key, ':', 3), 'what', left(f.title, 200), 'since', f.started_at)
                       order by f.started_at)
        from public.it_engineer_finding f
       where f.closed_at is null and coalesce((f.evidence->>'founder_required_credential')::boolean, false)), '[]'::jsonb))
$fn$;
revoke execute on function public.fn_founder_availability() from public, anon, authenticated;

-- The person's own open escalations (their promises and clocks) and the founder facts, for the case context of every channel.
-- Matched on the exact e-mail (case-blind) or the last nine digits of the phone, the same identity fn_support_touch uses.
create or replace function public.fn_escalation_case_facts(p_email text default null, p_phone text default null)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with who as (select lower(nullif(btrim(coalesce(p_email, '')), '')) e,
                      nullif(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), '') p)
  select jsonb_build_object(
    'open_escalations', coalesce((
      select jsonb_agg(jsonb_build_object('ref', 'ESC-' || c.id, 'kind', c.kind, 'channel', c.channel, 'promised', left(c.promised, 400),
                                          'promised_at', c.promised_at, 'next_word_due', c.status_due_at, 'state', c.state,
                                          'decision', c.ceo_decision, 'statuses_sent', c.statuses_sent) order by c.id)
        from public.escalation_clock c, who
       where c.state <> 'closed'
         and ((who.e is not null and lower(c.requester) = who.e)
           -- a phone is a WhatsApp clock's requester only: a site visitor is named by an address whose digits must never match a number
           or (who.p is not null and length(who.p) = 9 and c.channel = 'whatsapp' and right(regexp_replace(c.requester, '[^0-9]', '', 'g'), 9) = who.p))), '[]'::jsonb))
    || public.fn_founder_availability()
$fn$;
revoke execute on function public.fn_escalation_case_facts(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5. THE LIVE STRIPE HOLD: READ, NEVER WRITTEN; EVERY HELD PAYER ON A CLOCK (item 7)
-- ---------------------------------------------------------------------------------------------
-- The same rule as _shared/stripe_live_hold.ts liveChargeHeld: only the exact value 'off' (case and spaces ignored) opens it.
create or replace function public.fn_stripe_live_hold_reads_off()
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((select lower(btrim(value)) = 'off' from public.app_secrets where key = 'stripe_live_hold'), false)
$fn$;
revoke execute on function public.fn_stripe_live_hold_reads_off() from public, anon, authenticated;

-- Every person stripe_checkout or supplier_pay held (their CEO handoff, held_by stripe_live_hold) gets a clock: promised what the
-- held answer told them, owed word the day the switch reads off and an honest status until then. Idempotent.
create or replace function public.fn_held_payers_sync()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a record; v_email text; v_aud text; v_lang text; v_cust uuid; v_lead bigint; v jsonb; n_open int := 0; n_noemail int := 0;
begin
  for a in select x.* from public.agent_actions x
            where x.kind = 'handoff' and x.agent = 'ceo' and x.detail->>'held_by' = 'stripe_live_hold' and x.status <> 'failed'
              and not exists (select 1 from public.escalation_clock c where c.source_table = 'agent_actions' and c.source_id = x.id::text)
            order by x.id limit 50 loop
    v_email := null; v_cust := null; v_lead := null; v_lang := 'en';
    if a.target_table = 'quotes' or a.detail ? 'customer_id' then
      v_aud := 'customer';
      v_cust := nullif(a.detail->>'customer_id', '')::uuid;
      if v_cust is null and a.detail ? 'quote_id' then
        select i.customer_id into v_cust from public.quotes q join public.inquiries i on i.id = q.inquiry_id
         where q.id::text = a.detail->>'quote_id';
      end if;
      select c.email, case when c.locale = 'ar' then 'ar' else 'en' end into v_email, v_lang from public.customers c where c.id = v_cust;
    else
      v_aud := 'supplier';
      v_lead := nullif(a.detail->>'supplier_id', '')::bigint;
      select coalesce(nullif(btrim(l.claimed_by), ''), l.email) into v_email from public.leads l where l.id = v_lead;
    end if;
    if coalesce(v_email, '') !~ '@' then n_noemail := n_noemail + 1; continue; end if;
    v := public.fn_escalation_clock_open('agent_actions', a.id::text, 'held_payment', 'email', v_email,
           case when v_aud = 'customer'
                then 'Card payment opens shortly. Your quotes are safe, and our team has been told and will be in touch with you.'
                else 'Card payment opens shortly. Nothing has been charged, and our team has been told and will be in touch with you.' end,
           null, null,
           jsonb_build_object('audience', v_aud, 'lang', v_lang, 'promised_at', a.created_at, 'handoff_id', a.id,
                              'customer_id', v_cust, 'lead_id', v_lead, 'what', coalesce(a.detail->>'action', a.detail->>'kind', 'payment'),
                              'fixture', (v_aud = 'customer' and coalesce(public.fn_customer_is_demo(v_cust), false))
                                         or (v_aud = 'supplier' and coalesce(public.fn_supplier_is_demo(v_lead), false))));
    if not coalesce((v->>'existing')::boolean, true) then n_open := n_open + 1; end if;
  end loop;
  return jsonb_build_object('opened', n_open, 'no_email', n_noemail, 'switch_reads_off', public.fn_stripe_live_hold_reads_off(),
    'held_payers_waiting', (select count(*) from public.escalation_clock where kind = 'held_payment' and state <> 'closed' and not fixture));
end $fn$;
revoke execute on function public.fn_held_payers_sync() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 6. THE CEO SEAT'S QUEUE: WHAT IS DUE, AND WHY
-- ---------------------------------------------------------------------------------------------
-- due_for: 'decide'   -- the CEO has not decided (never tried, or not for 6 hours, at most 8 tries)
--          'tell'     -- decided, the person not yet told; or the switch reads off for a held payer
--          'status'   -- the clock ran out: an honest status is owed
create or replace function public.fn_escalation_clocks_due(p_limit integer default 3)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with fx as (select coalesce(current_setting('qd.duty_fixtures', true), '') = 'on' on_),
       off as (select public.fn_stripe_live_hold_reads_off() v),
       pol as (select public.fn_seat_clock_policy('escalation_status_max', 5) max_,
                      public.fn_seat_clock_policy('escalation_status_repeat_hours', 24) rep_),
       due as (
    select c.*,
           -- a failed delivery waits for its retry time (status_due_at, an hour on) and stops after six
           case when (c.state = 'decided' or (c.kind = 'held_payment' and (select v from off)))
                     and c.attempts < 6 and (c.attempts = 0 or c.status_due_at <= now()) then 'tell'
                when c.kind <> 'held_payment' and c.state = 'open' and c.ceo_attempts < 8
                     and (c.ceo_tried_at is null or c.ceo_tried_at < now() - interval '6 hours') then 'decide'
                when c.status_due_at <= now() and c.statuses_sent < (select max_ from pol) and c.attempts < 6 then 'status'
           end due_for
      from public.escalation_clock c
     where c.state <> 'closed' and c.fixture = (select on_ from fx))
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'ref', 'ESC-' || d.id, 'due_for', d.due_for, 'kind', d.kind, 'channel', d.channel, 'audience', d.audience,
           'lang', d.lang, 'state', d.state, 'subject_line', d.subject_line, 'request_text', d.request_text, 'promised', d.promised,
           'promised_at', d.promised_at, 'hours_waiting', floor(extract(epoch from now() - d.promised_at) / 3600)::int,
           'statuses_sent', d.statuses_sent, 'status_due', d.status_due_at <= now(), 'last_told_at', d.last_told_at, 'last_told_text', d.last_told_text,
           'ceo_decision', d.ceo_decision, 'ceo_reason', d.ceo_reason, 'founder_reason', d.founder_reason,
           'next_word_in_hours', (select rep_ from pol), 'switch_reads_off', (select v from off),
           'has_contact', d.requester ~ '@' or (d.channel = 'whatsapp' and length(regexp_replace(d.requester, '[^0-9]', '', 'g')) >= 9),
           'stale_days', d.detail->'stale_days', 'founder', public.fn_founder_availability()) order by d.status_due_at), '[]'::jsonb)
    from (select * from due where due_for is not null order by status_due_at limit greatest(1, least(coalesce(p_limit, 3), 10))) d
$fn$;
revoke execute on function public.fn_escalation_clocks_due(integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 7. WHAT THE CEO DECIDED (by its model, _shared/escalation_clock.ts), AND THE ONE FOUNDER ROUTE
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_escalation_clock_ceo_decided(p_id bigint, p_decision text, p_outcome text, p_reasons text,
  p_model text, p_law text default null, p_standing text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c public.escalation_clock; v_note jsonb;
begin
  select * into c from public.escalation_clock where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no clock ' || p_id); end if;
  if c.state <> 'open' then return jsonb_build_object('ok', false, 'reason', 'clock ' || p_id || ' is already ' || c.state); end if;
  if coalesce(btrim(p_reasons), '') = '' then return jsonb_build_object('ok', false, 'reason', 'a decision is recorded with its reasons'); end if;
  if p_decision not in ('decided', 'not_yet', 'founder_by_law') then
    return jsonb_build_object('ok', false, 'reason', 'decision is decided, not_yet or founder_by_law, not ' || coalesce(p_decision, 'null'));
  end if;
  if p_decision = 'founder_by_law' and coalesce(btrim(p_law), '') = '' then
    -- a "founder" answer that names no law is not one: it stays the CEO's to decide (rulings 1696/1706/1710)
    p_decision := 'not_yet';
    p_reasons := p_reasons || ' [Recorded as not yet decided: the answer sent it to the founder without naming the law that requires him.]';
  end if;
  update public.escalation_clock
     set ceo_tried_at = now(), ceo_attempts = ceo_attempts + 1, ceo_model = left(p_model, 120),
         kind = case when p_standing in ('press', 'legal', 'regulator') and kind in ('person', 'escalation') then p_standing else kind end,
         state = case p_decision when 'decided' then 'decided' when 'founder_by_law' then 'founder_by_law' else state end,
         ceo_decision = case when p_decision = 'not_yet' then ceo_decision else left(p_outcome, 2000) end,
         ceo_reason = left(p_reasons, 3000),
         decided_at = case when p_decision = 'not_yet' then decided_at else now() end,
         founder_reason = case when p_decision = 'founder_by_law' then left(p_law, 1000) else founder_reason end,
         updated_at = now()
   where id = p_id;
  if p_decision = 'founder_by_law' and not c.fixture and c.founder_told_at is null then
    begin
      v_note := public.fn_notify_founder(
        p_event => 'The CEO cannot decide escalation ESC-' || p_id || ' by law',
        p_detail => 'The law it named: ' || left(p_law, 600) || E'\nWhat it is: ' || c.kind || ' on ' || replace(c.channel, '_', ' ')
                    || ', promised ' || to_char(c.promised_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai.'
                    || E'\nThe CEO''s reasons: ' || left(p_reasons, 800)
                    || E'\ncustomer_support keeps the person informed; nothing else is asked of you.',
        p_level => 'high', p_kind => 'escalation_by_law', p_dedupe_key => 'escalation_by_law:' || p_id, p_owner_agent => 'ceo');
      update public.escalation_clock set founder_told_at = now(), detail = detail || jsonb_build_object('founder_note', v_note) where id = p_id;
    exception when others then
      update public.escalation_clock set last_error = left('founder note: ' || sqlerrm, 500) where id = p_id;
    end;
  end if;
  return jsonb_build_object('ok', true, 'id', p_id, 'decision', p_decision);
end $fn$;
revoke execute on function public.fn_escalation_clock_ceo_decided(bigint, text, text, text, text, text, text) from public, anon, authenticated;

create or replace function public.fn_escalation_clock_ceo_failed(p_id bigint, p_error text)
returns jsonb
language sql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  update public.escalation_clock set ceo_tried_at = now(), ceo_attempts = ceo_attempts + 1, last_error = left('ceo: ' || coalesce(p_error, '?'), 500), updated_at = now()
   where id = p_id
  returning jsonb_build_object('ok', true, 'id', id, 'ceo_attempts', ceo_attempts)
$fn$;
revoke execute on function public.fn_escalation_clock_ceo_failed(bigint, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 8. DELIVERY ON THE PERSON'S OWN CHANNEL, CONSENT RULES RESPECTED
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_escalation_clock_deliver(p_id bigint, p_stage text, p_subject text, p_body text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c public.escalation_clock; v_digits text; v_email text; v_role text; o record; w public.wa_conversation;
  v_ref text; v_secret text; v_req bigint; v_res jsonb;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
begin
  -- locked: two heartbeats working the same clock send one message per stage, not two
  select * into c from public.escalation_clock where id = p_id for update;
  if not found then return jsonb_build_object('sent', false, 'reason', 'no clock ' || p_id); end if;
  if coalesce(c.detail->'wa_stages', '[]'::jsonb) ? p_stage then return jsonb_build_object('sent', false, 'reason', 'already written at this stage'); end if;
  if coalesce(btrim(p_body), '') = '' then return jsonb_build_object('sent', false, 'reason', 'empty message'); end if;
  -- ruling 1199: a fixture is written only under the duty-fixture switch, and then only into the capture
  if c.fixture is distinct from v_fx then return jsonb_build_object('sent', false, 'reason', 'fixture: never sent outside the duty-fixture switch'); end if;
  v_role := case when c.audience = 'supplier' then 'supplier' else 'customer' end;
  if c.requester ~ '@' then
    v_email := lower(btrim(c.requester));
  elsif c.channel = 'whatsapp' then
    -- only a WhatsApp clock's requester is a number: a site visitor is named by an address whose digits are no one's phone
    v_digits := regexp_replace(c.requester, '[^0-9]', '', 'g');
    if length(v_digits) >= 9 then
      -- WhatsApp only inside the person's own 24-hour window: outside it a free message is refused by Meta, and a template needs an
      -- opt-in that a message they sent is not (ruling 1341)
      -- the exact number (wa_conversation.phone_e164 is the full digits): a nine-digit tail can be another country's number
      select * into w from public.wa_conversation where phone_e164 = v_digits;
      if w.id is not null and w.window_expires_at > now() then
        select value into v_ref from public.app_secrets where key = 'project_ref';
        select value into v_secret from public.app_secrets where key = 'cred_fn_resilience_ping';
        if v_ref is not null and v_secret is not null then
          select net.http_post(
            url := 'https://' || v_ref || '.supabase.co/functions/v1/send_whatsapp',
            headers := jsonb_build_object('Content-Type', 'application/json'),
            body := jsonb_build_object('__secret', v_secret, 'to', '+' || w.phone_e164, 'body', left(p_body, 1500)),
            timeout_milliseconds := 15000) into v_req;
          update public.escalation_clock set detail = jsonb_set(detail, '{wa_stages}', coalesce(detail->'wa_stages', '[]'::jsonb) || to_jsonb(p_stage)) where id = p_id;
          return jsonb_build_object('sent', true, 'via', 'whatsapp', 'request_id', v_req);
        end if;
      end if;
      -- the window is closed: the e-mail of the customer or supplier the number belongs to, when there is one
      select * into o from public.fn_whatsapp_owner('+' || v_digits) limit 1;
      if o.party_kind = 'customer' then select email into v_email from public.customers where id = o.customer_id; v_role := 'customer';
      elsif o.party_kind = 'supplier' then select coalesce(nullif(btrim(claimed_by), ''), email) into v_email from public.leads where id = o.lead_id; v_role := 'supplier';
      end if;
    end if;
  end if;
  if coalesce(v_email, '') !~ '@' then
    return jsonb_build_object('sent', false, 'reason', 'no open channel: ' || case when c.channel = 'whatsapp' then 'their WhatsApp window is closed and no e-mail is on file'
                                                                            else 'no e-mail or phone on file for ' || replace(c.channel, '_', ' ') end);
  end if;
  -- e-mail through customer_support's duty send: once per clock and stage, never to a bounced or complained address (fn_email_sendable)
  -- customer_support_duty_message.stage must read ^[a-z_]+\.[a-z_]+$ (no digit): a numbered stage (status_2) keeps its number in
  -- the key, so each status is still sent once
  v_res := public.fn_customer_support_duty_send('escalation.' || regexp_replace(lower(p_stage), '[^a-z_]', '', 'g'),
             c.id::text || case when p_stage ~ '[^a-z_]' then ':' || p_stage else '' end, v_role, v_email, c.lang,
             coalesce(nullif(btrim(p_subject), ''), case when c.lang = 'ar' then 'بخصوص طلبكم لدى QuotesDone' else 'About your request to QuotesDone' end),
             p_body, null, null, null);
  return jsonb_build_object('sent', coalesce((v_res->>'sent')::boolean, false), 'via', 'email', 'reason', v_res->>'reason', 'handoff_id', v_res->'handoff_id');
end $fn$;
revoke execute on function public.fn_escalation_clock_deliver(bigint, text, text, text) from public, anon, authenticated;

-- What was told (or why it could not be): the clock moves on. A decision told closes the case (and completes the CEO report it came
-- from); a held payer told the switch is off is closed; a status moves the clock by the repeat hours. A failed delivery is retried in
-- an hour, six times at most.
create or replace function public.fn_escalation_clock_told(p_id bigint, p_stage text, p_result jsonb, p_text text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c public.escalation_clock; v_sent boolean := coalesce((p_result->>'sent')::boolean, false);
  v_rep numeric := public.fn_seat_clock_policy('escalation_status_repeat_hours', 24); v_close text;
begin
  select * into c from public.escalation_clock where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no clock ' || p_id); end if;
  if not v_sent then
    update public.escalation_clock
       set attempts = attempts + 1, last_error = left(coalesce(p_result->>'reason', 'not sent'), 500), status_due_at = now() + interval '1 hour', updated_at = now()
     where id = p_id returning * into c;
    if c.attempts >= 6 and c.state = 'decided' then
      update public.escalation_clock set state = 'closed', closed_at = now(), closed_reason = 'decided; the person could not be reached on any channel: ' || coalesce(c.last_error, '?')
       where id = p_id;
    end if;
    return jsonb_build_object('ok', true, 'id', p_id, 'sent', false, 'attempts', c.attempts);
  end if;
  v_close := case when p_stage = 'decision' then 'decided and told: ' || left(coalesce(c.ceo_decision, ''), 300)
                  when p_stage = 'payment_open' then 'the live hold reads off and the payer was told'
                  else null end;
  update public.escalation_clock
     set statuses_sent = statuses_sent + 1, last_told_at = now(), last_told_via = p_result->>'via', last_told_text = left(p_text, 2000),
         attempts = 0, last_error = null,
         status_due_at = now() + make_interval(secs => v_rep * 3600),
         state = case when v_close is not null then 'closed' else state end,
         closed_at = case when v_close is not null then now() else closed_at end,
         closed_reason = coalesce(v_close, closed_reason),
         updated_at = now()
   where id = p_id;
  -- the CEO report the escalation came from (a WhatsApp escalation names it in detail.report_id) is completed with the decision
  if v_close is not null and coalesce(case when c.source_table = 'support_ceo_report' then c.source_id end, c.detail->>'report_id') is not null then
    update public.support_ceo_report set status = 'completed', completed_at = now(),
           completion_note = left('Decided by the CEO seat on escalation clock ESC-' || p_id || ' and told to the person by ' || coalesce(p_result->>'via', '?') || ': ' || coalesce(c.ceo_decision, ''), 1000)
     where id::text = coalesce(case when c.source_table = 'support_ceo_report' then c.source_id end, c.detail->>'report_id') and status in ('sent', 'accepted');
  end if;
  return jsonb_build_object('ok', true, 'id', p_id, 'sent', true, 'closed', v_close is not null);
end $fn$;
revoke execute on function public.fn_escalation_clock_told(bigint, text, jsonb, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 9. THE ONE-OFF FOR THE REQUESTS LEFT 'with_founder' (dry run by default; the main session runs it once, after release)
-- ---------------------------------------------------------------------------------------------
-- For every person request still 'with_founder' that is not a fixture: a clock (promised when it was asked, due now), the review row
-- moved to 'with_ceo' (the founder note kept in evidence), and ONE fixed, reviewed apology sent on the person's own channel through
-- fn_escalation_clock_deliver. It is a status notice of the kind of the held notice (ruling 1197): it answers nothing and promises
-- only what the clock keeps (the next word, and the CEO's decision, both written by the model). After it, every word is the model's.
-- Fixture rows (reserved +971 50 000 00xx numbers, demo e-mails) are counted and left alone. Returns NO personal detail.
create or replace function public.fn_escalation_clock_adopts_stale_person_requests(p_dry_run boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v jsonb; v_id bigint; v_body text; v_sub text; v_ar boolean; v_res jsonb; v_out jsonb := '[]'::jsonb;
  n_fixture int := 0; n_adopted int := 0; n_sent int := 0; n_unreached int := 0;
  v_rep numeric := public.fn_seat_clock_policy('escalation_status_repeat_hours', 24); v_next timestamptz;
begin
  for r in select * from public.decision_review_request
            where decision_type = 'person' and status = 'with_founder' order by id loop
    if public.fn_is_demo_phone(r.requester) or public.fn_is_demo_email(r.requester) then n_fixture := n_fixture + 1; continue; end if;
    v_ar := r.request_text ~ '[؀-ۿ]';
    v_next := now() + make_interval(secs => v_rep * 3600);
    v_body := public.fn_escalation_stale_apology(r.channel, r.created_at, v_next, v_ar);
    v_sub := case when v_ar then 'اعتذار بخصوص طلبكم التحدث إلى أحد أعضاء الفريق' else 'We are sorry: your request to speak to a person' end;
    if p_dry_run then
      v_out := v_out || jsonb_build_array(jsonb_build_object('review_request_id', r.id, 'channel', r.channel,
        'days_waiting', floor(extract(epoch from now() - r.created_at) / 86400)::int,
        'has_contact', r.requester ~ '@' or (r.channel = 'whatsapp' and length(regexp_replace(r.requester, '[^0-9]', '', 'g')) >= 9), 'lang', case when v_ar then 'ar' else 'en' end));
      continue;
    end if;
    v := public.fn_escalation_clock_open(coalesce(r.subject_table, 'decision_review_request'), coalesce(r.subject_id, r.id::text),
           'person', r.channel, r.requester, null, r.request_text, null,
           jsonb_build_object('review_request_id', r.id, 'promised_at', r.created_at, 'lang', case when v_ar then 'ar' else 'en' end,
                              'stale_days', floor(extract(epoch from now() - r.created_at) / 86400)::int, 'adopted_from', 'with_founder'));
    v_id := (v->>'id')::bigint;
    update public.decision_review_request
       set status = 'with_ceo', evidence = evidence || jsonb_build_object('founder_notified_then', founder_notified, 'escalation_clock_id', v_id),
           founder_notified = null
     where id = r.id;
    n_adopted := n_adopted + 1;
    v_res := public.fn_escalation_clock_deliver(v_id, 'apology', v_sub, v_body);
    perform public.fn_escalation_clock_told(v_id, 'apology', v_res, v_body);
    if coalesce((v_res->>'sent')::boolean, false) then n_sent := n_sent + 1; else n_unreached := n_unreached + 1; end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('review_request_id', r.id, 'clock', 'ESC-' || v_id, 'channel', r.channel,
      'sent', coalesce((v_res->>'sent')::boolean, false), 'via', v_res->>'via', 'reason', v_res->>'reason'));
  end loop;
  return jsonb_build_object('dry_run', p_dry_run, 'fixtures_left_alone', n_fixture, 'adopted', n_adopted, 'sent', n_sent,
                            'unreached', n_unreached, 'rows', v_out);
end $fn$;
revoke execute on function public.fn_escalation_clock_adopts_stale_person_requests(boolean) from public, anon, authenticated;

-- The fixed apology (reviewed wording). Dates are Dubai dates. Nothing here names the person or anyone else.
create or replace function public.fn_escalation_stale_apology(p_channel text, p_asked_at timestamptz, p_next_by timestamptz, p_ar boolean)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case when p_ar then
      'نعتذر إليكم. في ' || to_char(p_asked_at at time zone 'Asia/Dubai', 'DD/MM/YYYY') || ' طلبتم عبر '
      || case p_channel when 'whatsapp' then 'واتساب' when 'email' then 'البريد الإلكتروني' else 'محادثة الموقع' end
      || ' التحدث إلى أحد أعضاء فريقنا، ولم نرد عليكم كما وعدنا. هذا تقصير منا.' || E'\n\n'
      || 'أصبح طلبكم الآن لدى المدير المسؤول عن القرار في QuotesDone، وستصلكم منا رسالة أخرى في موعد أقصاه '
      || to_char(p_next_by at time zone 'Asia/Dubai', 'DD/MM/YYYY') || '، بالقرار أو بما وصلنا إليه.' || E'\n'
      || 'ويمكنكم الرد على هذه الرسالة في أي وقت بأي تفاصيل تودون إضافتها.' || E'\n\nفريق خدمة العملاء في QuotesDone'
    else
      'We are sorry. On ' || to_char(p_asked_at at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' you asked on '
      || case p_channel when 'whatsapp' then 'WhatsApp' when 'email' then 'e-mail' else 'our website chat' end
      || ' to speak to a member of our team, and we did not come back to you as we said we would. That was our failure.' || E'\n\n'
      || 'Your request is now with the manager who makes the decision at QuotesDone. You will hear from us again by '
      || to_char(p_next_by at time zone 'Asia/Dubai', 'DD Mon YYYY') || ', with the decision or with where it stands.' || E'\n'
      || 'You can reply to this message at any time with anything you would like to add.' || E'\n\nQuotesDone Customer Support'
  end
$fn$;
revoke execute on function public.fn_escalation_stale_apology(text, timestamptz, timestamptz, boolean) from public, anon, authenticated;
