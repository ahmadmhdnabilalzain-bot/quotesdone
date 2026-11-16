-- info@ AND management@ MAIL IS READ BEFORE IT IS ANSWERED (it_engineer for the mail path, customer_support reads and answers;
-- 16 Nov 2026; ledger 1446, 1453, 1543; the coordinator's condition for answering strangers there).
--
-- The founder: "Every email from a supplier to management@, supplier@ or info@ requires a reply, except mail from the bank and
-- such services; the agent must tell them apart" (1543); "An agent must understand an email before it replies" (1633).
--
-- WHAT CHANGES (the reading of supplier@, reused, not a second one: email_triage/supplier_mailbox_reading.ts):
--   1. fn_is_supplier_mailbox_mail also names info@quotesdone.com and management@quotesdone.com. So fn_mailbox_reply_rules sends
--      every mail into them through the code rules and the model's reading, fn_inbox_send refuses a seat's answer without a
--      decision that says answer, and send_outbox's gate (fn_mailbox_reply_may_leave) checks the same row. supplier@ is
--      unchanged; info@mail.quotesdone.com (the Resend address) is not named and keeps its path.
--   2. One more reading, legal_or_press (a lawyer, court, regulator or authority, or the press). It is never answered:
--      the CHECK on mailbox_reply_decision.reading and fn_mailbox_reply_decide's list take it; may_reply's generated
--      expression is unchanged (still only supplier_registration, supplier_account_question, customer).
--   3. A mail that is read and not answered can be ROUTED: handoff kind mail.routed, customer_support -> accountant,
--      it_engineer, marketing or ceo (the seat the model names for vendor mail, a pitch or an invoice; legal and press always
--      the CEO). The handoff is the seat's to act on within 2 days; its handler fn_mail_routed_waits only says what it waits for.
--      Nothing is routed to the founder.
-- Built from production's bodies read 16 Nov 2026: fn_is_supplier_mailbox_mail md5 d220a86e4b37eea7db464ac5ae2fe249,
--   fn_mailbox_reply_decide md5 b364567c600ca1bded70a66a8d32cc93 (the only overload of each; the local mirror matches both).
-- ORDER: deploy email_triage FIRST (it reads info@/management@ only when this predicate says so, and parses legal_or_press),
--   then this file and its probe, and only then a_stranger_writing_to_info_or_management_reaches_the_seats.sql.
-- prevented by: email_triage/supplier_mailbox_reading.test.ts (info@ and management@ cases; 6 fail without this predicate) and
--   scripts/sql/info_and_management_mail_is_read_before_it_is_answered_probe.sql.

CREATE OR REPLACE FUNCTION public.fn_is_supplier_mailbox_mail(p_to text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1
      from public.app_secrets s,
           regexp_split_to_table(lower(coalesce(p_to, '')), '[,;]') a
     where s.key in ('invite_m365_mailbox', 'email_reply_supplier') and btrim(coalesce(s.value, '')) <> ''
       and coalesce(substring(a from '<([^<>[:space:]]+@[^<>[:space:]]+)>'), btrim(a)) = lower(btrim(s.value)))
  -- info@ and management@ are read the same way (16 Nov 2026, ledger 1446, 1453, 1543): every mail into them has a decision
  -- before a seat may answer it (fn_inbox_send) and before an automatic answer leaves (fn_mailbox_reply_may_leave)
  or exists (
    select 1
      from regexp_split_to_table(lower(coalesce(p_to, '')), '[,;]') a
     where coalesce(substring(a from '<([^<>[:space:]]+@[^<>[:space:]]+)>'), btrim(a)) in ('info@quotesdone.com', 'management@quotesdone.com'))
$function$;

alter table public.mailbox_reply_decision drop constraint mailbox_reply_decision_reading_check,
  add constraint mailbox_reply_decision_reading_check check (reading = any (array['supplier_registration', 'supplier_account_question',
    'customer', 'vendor_our_account', 'automated_notice', 'bounce', 'founder_correspondence', 'spam_or_irrelevant', 'unclear', 'legal_or_press']));

CREATE OR REPLACE FUNCTION public.fn_mailbox_reply_decide(p_inbound_id bigint, p_reading text, p_why text, p_quote text, p_method text, p_model text DEFAULT NULL::text, p_effort text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rule text; v_reading text; v_may boolean;
begin
  if not exists (select 1 from public.inbound_messages where id = p_inbound_id) then
    raise exception 'fn_mailbox_reply_decide: no inbound message %', p_inbound_id;
  end if;
  v_rule := public.fn_mailbox_reply_hard_rule(p_inbound_id);
  -- the code's reading wins where it has one; an answer outside the ten is 'unclear', held and never answered
  v_reading := coalesce(public.fn_mailbox_reading_of_rule(v_rule), p_reading);
  if v_reading is null or v_reading not in ('supplier_registration', 'supplier_account_question', 'customer', 'vendor_our_account',
       'automated_notice', 'bounce', 'founder_correspondence', 'spam_or_irrelevant', 'unclear', 'legal_or_press') then v_reading := 'unclear'; end if;
  insert into public.mailbox_reply_decision (inbound_message_id, reading, hard_rule, why, quote, method, model, effort, decided_by, decided_at)
  values (p_inbound_id, v_reading, v_rule, left(p_why, 1000), left(p_quote, 500),
          case when p_method in ('model', 'code', 'no_model') then p_method else 'code' end, p_model, p_effort, 'customer_support', now())
  on conflict (inbound_message_id) do update
     set reading = excluded.reading, hard_rule = excluded.hard_rule, why = excluded.why, quote = excluded.quote,
         method = excluded.method, model = excluded.model, effort = excluded.effort, decided_at = excluded.decided_at
  returning may_reply into v_may;
  return jsonb_build_object('reading', v_reading, 'hard_rule', v_rule, 'may_reply', v_may);
end $function$;

-- the handler of mail.routed: the seat acts on the mail; this only says what the handoff waits for
create or replace function public.fn_mail_routed_waits(p_id bigint)
 returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object('waiting', 'the ' || a.agent || ' seat acts on inbound mail ' || coalesce(a.detail ->> 'inbound_message_id', '?')
                            || ' that customer_support read as ' || coalesce(a.detail ->> 'reading', '?') || ' and did not answer')
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_mail_routed_waits(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'mail.routed', 'customer_support', s, 'customer_support read a mail to info@ or management@ and did not answer it: it is this seat''s (vendor mail, a sales pitch or an invoice; legal and press to the CEO). Act on it as the seat that owns it.',
       'fn_mail_routed_waits', interval '2 days', false, 'scripts/sql/info_and_management_mail_is_read_before_it_is_answered.sql'
  from unnest(array['accountant', 'it_engineer', 'marketing', 'ceo']) s
on conflict (type, from_seat, to_seat) do nothing;

select case
  when public.fn_is_supplier_mailbox_mail('info@quotesdone.com') and public.fn_is_supplier_mailbox_mail('Management <management@quotesdone.com>')
   and not public.fn_is_supplier_mailbox_mail('info@mail.quotesdone.com')
   and (select count(*) from public.seat_handoff_kind where type = 'mail.routed' and from_seat = 'customer_support') = 4
   and pg_get_constraintdef((select oid from pg_constraint where conname = 'mailbox_reply_decision_reading_check')) like '%legal_or_press%'
  then 'PROBE OK: info@ and management@ are read before they are answered; legal_or_press is a reading; mail.routed reaches 4 seats'
  else 'PROBE FAILED: the mailbox predicate, the reading list or the mail.routed kinds are not as this file sets them' end as verdict;
