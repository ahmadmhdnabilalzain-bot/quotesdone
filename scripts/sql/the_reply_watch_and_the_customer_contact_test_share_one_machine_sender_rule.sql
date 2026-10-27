-- THE REPLY WATCH AND THE CUSTOMER-CONTACT TEST SHARE ONE MACHINE-SENDER RULE (27 Oct 2026).
-- Assigned: customer_support — the first-reply watch and the triage of inbound email.
--
-- MEASURED 27 Oct 2026, read from LIVE pg_get_functiondef (not the mirror): two routines answered "is this sender
-- a machine?" with two different rules.
--   (a) fn_support_reply_watch_tick()  (md5 feb885a1f92467e5581590da21cf0f49, = #1686's file byte for byte) read
--       the address inside <...> first, then a bare address, and matched whole tokens
--       (^|[-_])(no[-_]?reply|do[-_]?not[-_]?reply|mailer[-_]?daemon)([-_+.0-9]|$) on the local part.
--       It did not know postmaster or bounce(s), and it read inside quoted display names: for
--       "Support <noreply@spoof.com>" <bob@client.ae> and "noreply@spoof.com" bob@client.ae it read noreply and
--       exempted bob, a customer (the 2 misses the review of #1686 found).
--   (b) fn_support_email_is_a_customer_contact(text,text,text,text,boolean) (md5 af308424e649ff5a773b21a5c38a94df),
--       the test used by the unanswered-inbound tick, the case review and the weekly reply-quality review, matched
--       ^[^@]*(mailer-daemon|postmaster|no-?reply|do-?not-?reply|bounces?)[^@]*@ against the WHOLE From string:
--       "Bounce Fitness <info@...>", "Postmaster General <pm@...>", alice.noreply.fan@ and noreplying@ were all
--       machines, so those customers would never have been counted as waiting.
--
-- THIS FILE: one rule, public.fn_is_machine_sender(text), immutable, and both routines call it.
--   1. strip quoted strings ("..." in a display name can contain @ and <, and is never the address);
--   2. the address inside the FIRST <...> if there is one (an unclosed < still counts), else the first bare x@;
--   3. lower-case the local part;
--   4. a whole token: it starts the local part or follows - or _, and it ends at - _ + . a digit or the end:
--        noreply / no-reply / no_reply, do-not-reply (any of - _ or none), mailer-daemon, postmaster, bounce(s).
--      A dot or a plus does not open a token on the left (alice.noreply.fan@ and alice+noreply@ are people), and a
--      longer word that merely starts with one is a person (noreplying@, donotreplyteam@, bounced@).
--   NULL or no address at all is not a machine (false, never null), so a NOT in a caller keeps the message.
--   Each routine changes on ONE line, its sender predicate; every other line is the live body read 27 Oct 2026.
--
-- DOES NOT CHANGE: (a)'s calendar+/expenses@/accountant/demo exclusions or (b)'s to/owner/founder/fixture tests;
-- which other tables hold addresses (doc_reviews, chat_violations) - neither routine reads them; and a quoted LOCAL
-- part ("john doe"@x.com) is stripped with the display names and reads as no address, i.e. not a machine.
-- Measured over all 44 stored inbound_messages, 27 Oct 2026: 0 change side under (a) and 0 under (b).
--
-- ACL: fn_is_machine_sender is NEW, so CREATE granted EXECUTE to PUBLIC: revoked below from public, anon and
-- authenticated on its only signature (text). Its callers are SECURITY DEFINER routines owned by postgres and need
-- no grant; service_role gets one so a service-side caller uses this rule instead of writing a third. It is
-- SECURITY INVOKER: it reads no table. The two callers are CREATE OR REPLACE, which keeps their ACL
-- (service_role only, read live 27 Oct 2026), so they are not revoked again.
-- Probe: the_reply_watch_and_the_customer_contact_test_share_one_machine_sender_rule_probe.sql (always raises).
-- Prevented by: scripts/checks/detectors_stop_escalating_what_is_not_a_fault.test.mjs 6c, 6f, 6g, 6h.

create or replace function public.fn_is_machine_sender(p_from text)
returns boolean
language sql
immutable parallel safe
set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(
           lower(coalesce(substring(s.v from '<([^<>\s"]+)@'), substring(s.v from '([^<>\s"]+)@')))
             ~ '(^|[-_])(no[-_]?reply|do[-_]?not[-_]?reply|mailer[-_]?daemon|postmaster|bounces?)([-_+.0-9]|$)',
           false)
    from (select regexp_replace(coalesce(p_from, ''), '"[^"]*"', '', 'g') as v) s
$function$;
revoke execute on function public.fn_is_machine_sender(text) from public, anon, authenticated;
grant execute on function public.fn_is_machine_sender(text) to service_role;

CREATE OR REPLACE FUNCTION public.fn_support_reply_watch_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sla numeric := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24);
  v_cut timestamptz; v_founder text[]; c text; v_n int; v_oldest timestamptz; v_ids jsonb; v_median numeric;
  v_out jsonb := '{}'::jsonb;
begin
  v_cut := now() - make_interval(secs => (v_sla * 3600)::double precision);
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  foreach c in array array['email', 'whatsapp', 'chat'] loop
    if c = 'email' then
      select count(*), min(m.created_at), coalesce(jsonb_agg(m.id order by m.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.inbound_messages m
       where m.created_at > now() - interval '30 days' and m.created_at < v_cut and m.replied_at is null
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
         -- 19 Oct 2026: a machine sender cannot be answered, and calendar+ is the founder's own approval inbox.
         -- 27 Oct 2026: the machine word is matched anywhere in the sender's LOCAL PART as a whole token (start,
         -- or bounded by hyphen/underscore), not only at its start: security-noreply@ waited 30 days as a customer.
         -- A dot does not bound it on the left, so a person whose name merely contains the word stays counted.
         -- 27 Oct 2026 (review of #1684): the local part is read from the address inside <...> first, so a quoted
         -- display name that itself looks like a machine address cannot hide the real sender, and the word must
         -- END at a separator, digit or the end of the local part, so a longer word that merely starts with it is
         -- a person.
         and coalesce(m.to_email, '') !~* '^calendar\+'
         and not public.fn_is_machine_sender(m.from_email)
         and not public.fn_is_demo_email(m.from_email);
      select percentile_cont(0.5) within group (order by extract(epoch from m.replied_at - m.created_at) / 60) into v_median
        from public.inbound_messages m
       where m.replied_at is not null and m.created_at > now() - interval '7 days'
         and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant';
    elsif c = 'whatsapp' then
      select count(*), min(w.created_at), coalesce(jsonb_agg(w.id order by w.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.wa_messages w
       where w.created_at > now() - interval '30 days' and w.created_at < v_cut
         and coalesce(btrim(w.inbound), '') <> '' and (w.reply is null or not coalesce(w.sent, false))
         and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder));
      v_median := null;   -- the WhatsApp reply is written in the same row as the inbound: minutes are not recorded
    else
      select count(*), min(g.created_at), coalesce(jsonb_agg(g.id order by g.id), '[]'::jsonb)
        into v_n, v_oldest, v_ids
        from public.assistant_logs g
        left join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and g.created_at > now() - interval '30 days' and g.created_at < v_cut
         and coalesce(t.status, 'open') not in ('done', 'cancelled');
      select percentile_cont(0.5) within group (order by extract(epoch from t.updated_at - g.created_at) / 60) into v_median
        from public.assistant_logs g join public.org_tasks t on t.id = g.gap_task_id
       where g.answered = false and t.status = 'done' and t.updated_at > g.created_at and g.created_at > now() - interval '7 days';
    end if;

    if v_n > 0 then
      perform public.fn_it_engineer_finding_upsert('support_reply_sla:' || c,
        v_n || ' ' || c || ' message(s) have waited more than ' || v_sla || ' h for a first reply (oldest '
          || to_char(v_oldest at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai)',
        'customer_support first-reply watch (fn_support_reply_watch_tick) -> ' || c, 'customer_facing', v_n,
        jsonb_build_object('channel', c, 'sla_hours', v_sla, 'waiting', v_n, 'oldest', v_oldest,
                           'ids', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_ids) x limit 20) z),
                           'median_first_reply_minutes_7d', round(v_median), 'owner_seat', 'customer_support', 'duty', 'reply_time'),
        '{}'::text[], array['whether the customer was answered on another channel'], 'customer_support');
    elsif exists (select 1 from public.it_engineer_finding where issue_key = 'support_reply_sla:' || c and closed_at is null) then
      -- 27 Oct 2026: the note says what cleared each message it last listed (answered, aged out, no longer
      -- counted, gone), never a reply that did not happen.
      perform public.fn_it_engineer_finding_close('support_reply_sla:' || c,
        public.fn_support_reply_watch_close_note(c,
          (select f.evidence from public.it_engineer_finding f where f.issue_key = 'support_reply_sla:' || c and f.closed_at is null),
          v_sla));
    end if;
    v_out := v_out || jsonb_build_object(c, jsonb_build_object('over_sla', v_n, 'median_first_reply_minutes_7d', round(v_median)));
  end loop;
  return jsonb_build_object('ok', true, 'sla_hours', v_sla) || v_out;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_support_email_is_a_customer_contact(p_from text, p_to text, p_owner_role text, p_subject text, p_fixtures boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select not public.fn_is_machine_sender(p_from)
     and coalesce(p_to, '') !~* '^(expenses@|calendar\+|approve\+)'
     and coalesce(p_owner_role, '') <> 'accountant'
     and lower(btrim(coalesce(p_from, ''))) <> all (
           select lower(btrim(e)) from public.app_secrets s, unnest(string_to_array(s.value, ',')) e
            where s.key in ('admin_emails', 'founder_email') and btrim(e) <> '')
     and (public.fn_is_demo_email(p_from) or coalesce(p_subject, '') like 'ZZ DEMO%') = p_fixtures
$function$;
