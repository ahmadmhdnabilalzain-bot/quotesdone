-- TWO CUSTOMER_SUPPORT DUTIES OF #1844 READ ONLY THEIR OWN KIND OF ROW: REAL WITHOUT THE FIXTURE SWITCH, DEMO WITH IT.
-- Seat: customer_support (both duties are hers; the status chase is answered for the sales_engineer). Written by it_engineer,
-- 10 Nov 2026. Founder ruling 1199 (12 Oct 2026): demo data is marked "so no agent ever works on it as if it were real".
--
-- MEASURED 10 Nov 2026 (production, read-only): no_seat_duty_reads_demo_rows.test.mjs fails on three enabled duties. Two of
-- them, registered by a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.sql (#1844,
-- 3 Nov), read customers / inquiries with no demo predicate at all:
--   * customer_support.status_chase_close -> fn_customer_support_closes_status_chases reads inquiries, customers and quotes
--     for every pending inquiry.status_chase handoff, and messages the customer (WhatsApp, or e-mail after a failed try);
--   * customer_support.person_followup_email -> fn_wa_human_request_email_followup resolves the number to a customer or
--     supplier and e-mails them.
-- A demo party's message is captured by the outbox, but the duty still worked the demo request as real: it closed the
-- chase, counted it, and wrote its verdict into the real handoff stream.
-- (The third, customer_support.public_complaints, already selects (text like 'ZZ DEMO%') = v_fx; the check could not see
-- that switch because it strips string literals first. That is fixed in the check, not here.)
--
-- WHAT THIS CHANGES: each routine reads qd.duty_fixtures, the convention of every other duty, and skips a row whose party is
-- demo in real mode, or real in fixture mode (inquiry: fn_inquiry_is_demo or fn_customer_is_demo; number: fn_is_demo_phone
-- or the customer / supplier it resolves to). Nothing else moves: both bodies are the live definitions read with
-- pg_get_functiondef on 10 Nov, with only those lines added. CREATE OR REPLACE keeps their grants. Idempotent.
-- The probe that drives the status chase on ZZ DEMO fixtures
-- (a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop_probe.sql) sets the switch for its calls.
-- Prevented by: scripts/checks/no_seat_duty_reads_demo_rows.test.mjs (production read; and both canonical bodies by name).

CREATE OR REPLACE FUNCTION public.fn_customer_support_closes_status_chases()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.agent_actions; i public.inquiries; c public.customers; v_new int; v_live int; v_due timestamptz; v_ar boolean;
        v_dest text; v_res jsonb; v_st text; v_lang text; v_qkey text; v_tries int; v_verdict text; v_outcome text;
        v_first_new timestamptz; v_ptold boolean; v_pwait boolean;
        n_closed int := 0; n_wait int := 0; n_failed int := 0; n_stuck int := 0; v_err jsonb := '[]'::jsonb;
        v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- 10 Nov 2026: ruling 1199
begin
  for h in select * from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.status = 'pending'
              and a.detail->>'type' = 'inquiry.status_chase' and a.detail->>'from' = 'customer_support'
            order by a.id limit 100 loop
    begin
      v_verdict := null; v_outcome := null; v_res := null; v_st := null; v_dest := null; v_lang := null;
      v_tries := coalesce((h.detail->>'followup_attempts')::int, 0);
      v_ptold := null; v_pwait := null;
      select * into i from public.inquiries where id = (h.detail->>'inquiry_id')::uuid;
      select * into c from public.customers where id = i.customer_id;
      -- ruling 1199 (10 Nov 2026): a demo request's chase is worked only under the duty's fixture switch, a real one only without it
      if (coalesce(public.fn_inquiry_is_demo(i.id), false) or coalesce(public.fn_customer_is_demo(c.id), false)) is distinct from v_fx then
        continue;
      end if;
      v_due := coalesce((h.evidence->>'next_update_by')::timestamptz, (h.detail->>'next_update_by')::timestamptz, h.created_at + interval '24 hours');
      select w.language into v_lang from public.wa_conversation w where w.phone_e164 = h.detail->>'phone_digits';
      v_ar := case when v_lang in ('ar', 'en') then v_lang = 'ar' else coalesce(i.lang, c.locale) = 'ar' end;
      select count(*) filter (where q.created_at > h.created_at), count(*),
             md5(string_agg(q.id::text, ',' order by q.id) filter (where q.created_at > h.created_at)),
             min(q.created_at) filter (where q.created_at > h.created_at)
        into v_new, v_live, v_qkey, v_first_new from public.quotes q
       where q.inquiry_id = i.id and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
         and q.stale_at is null;
      -- The platform's own new-quote notice for THESE quotes (measured 3 Nov 2026: its rows carry inquiry_id, not quote_id,
      -- so it is tied by time: written at or after the first new quote). Every such row counts (it may write one per
      -- channel): any delivered one means told; else any still queued under an hour means wait; else we send.
      if v_new > 0 then
        select bool_or(coalesce(n.status, 'queued') not in ('failed', 'skipped', 'queued', 'pending')),
               bool_or(coalesce(n.status, 'queued') in ('queued', 'pending') and n.created_at > now() - interval '1 hour')
          into v_ptold, v_pwait from public.notifications n
         where n.inquiry_id = i.id and n.type = 'new_quote' and n.to_role = 'customer' and n.created_at >= v_first_new;
      end if;
      if i.id is null or coalesce(i.status, '') not in ('sent', 'quoted', 'open', 'split') then
        -- read before the retry cap, so a stuck chase still closes when its request moves on
        v_outcome := 'request_moved_on'; v_st := 'nothing_to_send';
        v_verdict := 'the request is ' || coalesce(i.status, 'gone') || ': nothing is left to chase';
      elsif v_tries >= 3 then
        -- three failed follow-ups wait on it_engineer's finding, never a fourth identical try
        n_stuck := n_stuck + 1; continue;
      elsif v_new > 0 and coalesce(v_ptold, false) then
        -- sent, delivered, or (demo only, measured 3 Nov 2026) suppressed, as ours would be: the customer was told
        v_outcome := 'quote_arrived'; v_st := 'platform_new_quote_notice';
        v_verdict := v_new || ' new quote(s) arrived and the platform''s new-quote notice told the customer; nothing more was sent';
      elsif v_new > 0 and coalesce(v_pwait, false) then
        -- the platform's notice is still on its way: wait for it rather than send a second message
        n_wait := n_wait + 1; continue;
      elsif v_new > 0 then
        -- A quote arrived: the customer hears it on the WhatsApp they asked on (the approved customer_new_quote template);
        -- after a failed try, by the email on file instead, so a WhatsApp that keeps failing is not retried alone.
        v_dest := public.fn_whatsapp_destination('customer', c.id);
        if v_tries >= 1 and coalesce(c.email, '') like '%@%' then v_dest := null; end if;
        v_outcome := 'quote_arrived';
        if v_dest is null and coalesce(c.email, '') not like '%@%' then v_st := 'no_channel';
        else
          v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
            'type', 'quote_received', 'requested_by', 'customer_support', 'channel', case when v_dest is null then 'email' else 'whatsapp' end,
            'to_phone', v_dest, 'to_email', c.email, 'to_role', 'customer', 'inquiry_id', i.id, 'lang', case when v_ar then 'ar' else 'en' end,
            'subject', case when v_ar then 'مستجدات العروض على طلبكم رقم ' || coalesce(i.rfq_no::text, '') else 'A new quote arrived on your request ' || coalesce(i.rfq_no::text, '') end,
            'body', case when v_ar
              then 'كما وعدناكم، وصل إلى طلبكم رقم ' || coalesce(i.rfq_no::text, '') || ' ما عدده ' || v_new || ' من العروض الجديدة، ليصبح مجموع العروض لديكم ' || v_live
                   || '. وبإمكانكم مقارنتها في حسابكم على https://quotesdone.com'
              else 'As promised: ' || v_new || ' new quote(s) arrived on your request ' || coalesce(i.rfq_no::text, '') || ', so you now have ' || v_live
                   || '. You can compare them in your account at https://quotesdone.com' end,
            'dedupe_key', 'status_chase_quote:' || i.id || ':' || v_qkey || case when v_dest is null then ':email' else '' end)));
          v_st := v_res->0->>'status';
        end if;
        v_verdict := v_new || ' new quote(s) arrived; the customer was told (' || case when v_dest is null then 'email' else 'WhatsApp' end || ')';
      elsif now() >= v_due then
        v_outcome := 'dated_update_sent';
        if coalesce(c.email, '') not like '%@%' then v_st := 'no_channel';
        else
          v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
            'type', 'inquiry_status_update', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', c.email,
            'to_role', 'customer', 'inquiry_id', i.id, 'lang', case when v_ar then 'ar' else 'en' end,
            'subject', case when v_ar then 'مستجدات طلبكم رقم ' || coalesce(i.rfq_no::text, '') else 'An update on your request ' || coalesce(i.rfq_no::text, '') end,
            'body', case when v_ar
              then 'كما وعدناكم، إليكم مستجدات طلبكم رقم ' || coalesce(i.rfq_no::text, '') || ': وصلكم حتى الآن ' || v_live || ' من أصل 3 عروض نسعى إلى توفيرها. '
                   || 'وقد ذكّر مهندس المبيعات لدينا المورّدين المدعوين الذين لم يقدّموا عروضهم بعد، ويبقى طلبكم متاحًا لمورّدين آخرين في المجال نفسه، وسنوافيكم فور وصول أي عرض جديد.'
              else 'As promised, an update on your request ' || coalesce(i.rfq_no::text, '') || ': you have ' || v_live || ' of the 3 quotes we aim for. '
                   || 'Our sales engineer reminded the invited suppliers who had not quoted, and the request stays open to more suppliers in its trade. '
                   || 'We will tell you as soon as a new quote arrives.' end,
            'dedupe_key', 'status_chase_update:' || h.id)));
          v_st := v_res->0->>'status';
        end if;
        v_verdict := 'no new quote by ' || v_due || '; the dated update was sent to the customer by email';
      end if;

      if v_verdict is null then n_wait := n_wait + 1; continue; end if;
      -- NOT TOLD IS NOT CLOSED. The chase stays pending and is tried again on the next tick.
      if coalesce(v_st, '') not in ('done', 'platform_new_quote_notice', 'nothing_to_send') then
        v_tries := v_tries + 1;
        update public.agent_actions set detail = detail || jsonb_build_object('followup_attempts', v_tries,
                 'followup_last_status', coalesce(v_st, 'unknown'), 'followup_last_error', v_res->0->>'error', 'followup_last_at', now())
         where id = h.id;
        if v_tries >= 3 then
          perform public.fn_it_engineer_finding_upsert('customer_support:status_chase_followup_undelivered:' || h.id,
            'A status-chase follow-up could not reach the customer after 3 tries (handoff ' || h.id || ')',
            'public.fn_customer_support_closes_status_chases', 'customer_facing', 1,
            jsonb_build_object('handoff_id', h.id, 'inquiry_id', i.id, 'outcome', v_outcome, 'delivery_status', v_st,
                               'error', v_res->0->>'error', 'owner_seat', 'customer_support'),
            '{}'::text[], array['why the follow-up could not be delivered: no confirmed WhatsApp and no email on file, or the delivery handoff failed'],
            'customer_support');
        end if;
        n_failed := n_failed + 1;
        continue;
      end if;
      perform set_config('qd.handoff_closer', 'customer_support', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) - 'waiting' || jsonb_build_object(
        'verified_by', 'customer_support', 'verified_at', now(), 'outcome', v_outcome, 'verdict', v_verdict,
        'delivery_status', v_st, 'followup', v_res -> 0));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'closed', n_closed, 'waiting', n_wait,
                            'not_delivered', n_failed, 'stuck_after_3_tries', n_stuck, 'errors', v_err);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_wa_human_request_email_followup()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.agent_actions; o record; v_email text; v_ar boolean; v_res jsonb; n_sent int := 0; n_none int := 0;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- 10 Nov 2026: ruling 1199
begin
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'support.human_requested'
              and a.detail->>'followup_skipped' = 'the 24-hour WhatsApp window had closed' and not (a.detail ? 'email_followup_at')
            order by a.id limit 50 loop
    v_email := null;
    select * into o from public.fn_whatsapp_owner('+' || (r.detail->>'phone_digits')) limit 1;
    -- ruling 1199 (10 Nov 2026): a demo party (its number, or the customer or supplier it resolves to) only under the switch
    if (coalesce(public.fn_is_demo_phone('+' || (r.detail->>'phone_digits')), false)
        or (o.party_kind = 'customer' and coalesce(public.fn_customer_is_demo(o.customer_id), false))
        or (o.party_kind = 'supplier' and coalesce(public.fn_supplier_is_demo(o.lead_id), false))) is distinct from v_fx then
      continue;
    end if;
    if o.party_kind = 'customer' then select email into v_email from public.customers where id = o.customer_id;
    elsif o.party_kind = 'supplier' then select coalesce(nullif(btrim(claimed_by), ''), email) into v_email from public.leads where id = o.lead_id;
    end if;
    -- suppliers are written in English (founder, 28 Sep 2026); a customer in the conversation's language
    v_ar := o.party_kind = 'customer' and exists (select 1 from public.wa_conversation w where w.phone_e164 = r.detail->>'phone_digits' and w.language = 'ar');
    if coalesce(v_email, '') like '%@%' then
      v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'support_person_followup', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', v_email,
        'to_role', o.party_kind, 'lead_id', o.lead_id, 'lang', case when v_ar then 'ar' else 'en' end,
        'subject', case when v_ar then 'بخصوص طلبكم التحدث إلى أحد أعضاء الفريق' else 'About your request to speak to a person' end,
        'body', case when v_ar
          then 'نعتذر عن تأخر ردنا عليكم بعد طلبكم على واتساب التحدث إلى أحد أعضاء الفريق، وقد ذكّرنا الفريق بطلبكم مجددًا. '
               || 'ويمكنكم الرد على هذه الرسالة أو مراسلتنا على واتساب في أي وقت، وستصلكم الإجابات الفورية مباشرة.' || E'\n\nفريق خدمة العملاء في QuotesDone'
          else 'We are sorry you have not heard from us since you asked on WhatsApp to speak to a person. We have reminded the team of your request. '
               || 'You can reply to this email, or message us on WhatsApp at any time and instant answers are back on there.' || E'\n\nQuotesDone Customer Support' end,
        'dedupe_key', 'wa_human_email_followup:' || r.id)));
      update public.agent_actions set detail = detail || jsonb_build_object('email_followup_at', now(), 'email_followup', v_res->0) where id = r.id;
      n_sent := n_sent + 1;
    else
      update public.agent_actions set detail = detail || jsonb_build_object('email_followup_at', now(), 'email_followup', 'no email on file for this number') where id = r.id;
      n_none := n_none + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'emailed', n_sent, 'no_email', n_none);
end $function$;
