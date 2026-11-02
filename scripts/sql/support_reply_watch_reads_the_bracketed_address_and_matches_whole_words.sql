-- THE FIRST-REPLY WATCH READS THE ADDRESS INSIDE <...> AND MATCHES THE MACHINE WORD AS A WHOLE WORD (27 Oct 2026).
-- Assigned: customer_support — the first-reply watch over inbound email.
--
-- Follow-up to support_reply_watch_exempts_machine_senders_and_says_why_it_closed.sql (#1684, applied 27 Oct).
-- Built on the LIVE pg_get_functiondef of fn_support_reply_watch_tick() read 27 Oct 2026 20:29 UTC (md5
-- af022966e022c66d99316153d8cf2d3c), identical to that file. ONE predicate changes, on the sender of an email;
-- every other line is the live body. The review of #1684 found two ways the rule could hide a real customer:
--
-- 1. THE LOCAL PART WAS THE FIRST `x@` IN THE HEADER. For a From of the shape
--      "noreply@spoof.com" <bob@client.ae>
--    the old extraction read `noreply` out of the quoted display name and exempted bob, a customer. Now the
--    address inside <...> is read first and the first `x@` is only the fallback for a bare address.
-- 2. THE START OF THE LOCAL PART HAD NO RIGHT-HAND BOUNDARY. `^(no-?reply…)` also matched noreplying@. Both
--    positions now need the word to END at -, _, +, ., a digit, or the end of the local part:
--      (^|[-_])(no[-_]?reply|do[-_]?not[-_]?reply|mailer[-_]?daemon)([-_+.0-9]|$)
--    A dot still does not open the word on the left (alice.noreply.fan@ is a person), and neither does a plus
--    (alice+noreply@ is a person's own sub-address).
--
-- Measured over all 44 inbound_messages, 27 Oct 2026: none of them carries <...>, and the new rule exempts exactly
-- the 2 messages (security-noreply@) the live rule exempts -- no message changes side today. The change closes
-- the two shapes before a sender uses them.
--
-- CREATE OR REPLACE keeps the routine's ACL (service_role only, read 27 Oct 2026), so it is not revoked again.
-- Probe: support_reply_watch_reads_the_bracketed_address_and_matches_whole_words_probe.sql (always ends in a
-- raise, so it can never commit). Prevented by: scripts/checks/detectors_stop_escalating_what_is_not_a_fault.test.mjs
-- 6c and 6f, which replay this routine's own extraction and pattern over named From headers.

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
         and coalesce(substring(m.from_email from '<([^<>\s"]+)@'), substring(m.from_email from '([^<>\s"]+)@'), '') !~* '(^|[-_])(no[-_]?reply|do[-_]?not[-_]?reply|mailer[-_]?daemon)([-_+.0-9]|$)'
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
