-- Seat: sales_engineer. Assigned: sales_engineer (customer-journey follow-up, 10 Nov 2026; founder ruling 1608).
--
-- MEASURED on origin/main (each canonical body read back equal to production):
--   * fn_cancel_inquiry refused a revealed request with "You can close it instead", and no customer close action exists
--     anywhere (portal, customer_api, WhatsApp). customer_api passed only that English sentence back, so the portal fell
--     to its generic "could not cancel" in both languages.
--   * fn_cancel_inquiry knew 'cancelled' and the revealed states, not 'closed', 'expired' or 'lost': a request the
--     platform had already ended could be cancelled on top, its suppliers told "the customer cancelled".
--   * fn_cancel_inquiry on a SPLIT request cancelled the parent only. Its parts — the requests suppliers quote — stayed
--     'sent', and their suppliers, who are matched to the parts and never to the parent, were never told.
--   * fn_edit_inquiry and fn_inquiry_add_missing_specs refused a closed request by a list without 'expired' and 'lost'.
--   _shared/request_closed.ts holds the list of the ends of a request: completed, closed, cancelled, expired, lost.
-- WHAT THIS CHANGES: the three routines refuse every end on that list; a revealed request is refused with what the
-- customer can actually do ("I hired this supplier", or the automatic close request_revealed_close_days after the
-- reveal), in English and Arabic, and customer_api now passes code, message and message_ar through; a split request is
-- cancelled with its parts and the suppliers of every part are told about their part.
-- scripts/checks/one_list_says_a_request_is_closed.test.mjs now reads these three bodies (and the concierge's) too.
-- NOT CHANGED: the 30-day cancellation warning, the edit window, the add-missing-specs answers.
-- prevented by: scripts/checks/one_list_says_a_request_is_closed.test.mjs and this file's _probe.sql.
-- Pending until the release applies it: scripts/sql/pending/a_closed_request_is_not_cancelled_edited_or_completed_again_and_a_revealed_one_says_what_to_do.txt

create or replace function public.fn_cancel_inquiry(p_inquiry uuid, p_customer uuid, p_reason text DEFAULT NULL::text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v inquiries%rowtype; v_paid boolean; v_cnt int; v_warned boolean:=false; v_email text; v_locale text;
        l record; v_told int := 0; v_failed int := 0; v_cust_told boolean := false; v_ar boolean; v_d jsonb;
        v_close int := public.fn_seat_clock_policy('request_revealed_close_days', 60)::int;
begin
  -- review of #1844: locked, so a concurrent reveal or a second cancel cannot interleave with the checks below
  select * into v from inquiries where id=p_inquiry for update;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  if v.status='cancelled' or v.pipeline_stage='cancelled' then
    return jsonb_build_object('ok',true,'already_cancelled',true); end if;
  -- 10 Nov 2026 (sales_engineer): a request the platform already ended (expired, lost, closed) is not cancelled on top:
  -- that wrote 'cancelled' over the real end and told its suppliers "the customer cancelled". One list with
  -- _shared/request_closed.ts (scripts/checks/one_list_says_a_request_is_closed.test.mjs reads this one).
  if v.status in ('closed','expired','lost') then
    return jsonb_build_object('error','inquiry_closed','message','This request is already closed.','message_ar','هذا الطلب مغلق.'); end if;
  -- A split request's parts are the requests suppliers quote: a reveal on any part is a reveal on the request.
  select exists(select 1 from transactions t join inquiries u on u.id = t.inquiry_id where u.id = p_inquiry or u.parent_inquiry_id = p_inquiry) into v_paid;
  if v_paid or v.status in ('revealed','completed') or v.pipeline_stage in ('revealed','won')
     or exists (select 1 from inquiries u where u.parent_inquiry_id = p_inquiry and u.status in ('revealed','completed')) then
    -- 10 Nov 2026: it pointed the customer at a close action, and no customer close action exists. What there is: Hire,
    -- and the automatic close of a revealed request with no hire (fn_sales_engineer_request_outcomes, C).
    return jsonb_build_object('error','already_revealed',
      'message','This request has a revealed supplier, so it cannot be cancelled. When the work is agreed, press "I hired this supplier" on their quote; if no hire is recorded, we close the request ' || v_close || ' days after the reveal.',
      'message_ar','لهذا الطلب مورّد كشفتَ بياناته، ولذلك لا يمكن إلغاؤه. وعند الاتفاق على العمل اضغط "تعاقدتُ مع هذا المورّد" على عرضه، وإن لم يُسجَّل أي تعاقد أغلقنا الطلب بعد ' || public.fn_ar_days(v_close) || ' من الكشف.'); end if;

  -- 10 Nov 2026: a split request is cancelled with its parts, which carried on as 'sent' while the parent read cancelled.
  update inquiries set status='cancelled', pipeline_stage='cancelled', outcome='cancelled',
      lost_reason=coalesce(p_reason,'customer_cancelled'), completed_at=now(), stage_changed_at=now()
    where id=p_inquiry or parent_inquiry_id=p_inquiry;
  insert into inquiry_cancellations(inquiry_id,customer_id,reason) values (p_inquiry, v.customer_id, p_reason);

  -- 3 Nov 2026: NOTHING IS ONE-WAY. Every supplier invited to quote is told the job is off (suppliers are written in
  -- English), through customer_support's door, once per request and supplier.
  -- 10 Nov 2026: the suppliers of every part (a split's suppliers are matched to its parts, never to the parent), each
  -- told about the part they were invited to, keyed per part and supplier (a single request keeps its old key).
  for l in select le.id, coalesce(nullif(btrim(le.claimed_by), ''), le.email) as to_email, u.id as unit, u.category, u.emirate, u.rfq_no
             from inquiry_matches x join leads le on le.id = x.supplier_id join inquiries u on u.id = x.inquiry_id
            where (u.id = p_inquiry or u.parent_inquiry_id = p_inquiry) and not coalesce(le.banned, false)
              and coalesce(nullif(btrim(le.claimed_by), ''), le.email, '') like '%@%' loop
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'rfq_cancelled', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', l.to_email,
      'to_role', 'supplier', 'lead_id', l.id, 'inquiry_id', l.unit, 'lang', 'en',
      'subject', 'A request you were invited to quote was cancelled',
      'body', 'The customer cancelled the ' || coalesce(l.category, '') || coalesce(' job in ' || nullif(l.emirate, ''), ' job')
              || ' (request ' || coalesce(l.rfq_no::text, '') || ') you were invited to quote. No quote is needed for it any more, '
              || 'and a quote you already sent will not be used. Thank you for your time.',
      'dedupe_key', 'rfq_cancelled:' || l.unit || ':' || l.id)));
    -- counted as told only when the delivery took it (re-review of #1844)
    if coalesce(v_d->0->>'status', '') in ('done', 'demo_captured') then v_told := v_told + 1; else v_failed := v_failed + 1; end if;
  end loop;

  select email, locale into v_email, v_locale from customers where id=v.customer_id;
  -- ...and the customer gets the confirmation in the request's own language (founder, 28 Sep 2026).
  if v_email is not null and position('@' in v_email)>1 then
    v_ar := coalesce(v.lang, v_locale) = 'ar';
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'inquiry_cancelled', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', v_email,
      'to_role', 'customer', 'inquiry_id', p_inquiry, 'lang', case when v_ar then 'ar' else 'en' end,
      'subject', case when v_ar then 'أُلغي طلبكم رقم ' || coalesce(v.rfq_no::text, '')
                      else 'Your request ' || coalesce(v.rfq_no::text, '') || ' is cancelled' end,
      'body', case when v_ar
        then 'أُلغي طلبكم رقم ' || coalesce(v.rfq_no::text, '') || ' بناءً على رغبتكم، وأبلغنا بذلك المورّدين الذين دعوناهم إلى تقديم عروضهم. '
             || 'وإن كان الإلغاء عن طريق الخطأ، فبإمكانكم نشر الطلب من جديد على https://quotesdone.com'
        else 'Your request ' || coalesce(v.rfq_no::text, '') || ' is cancelled, as you asked, and the suppliers invited to quote have been told. '
             || 'If this was a mistake, you can post the request again at https://quotesdone.com' end,
      'dedupe_key', 'inquiry_cancelled:' || p_inquiry)));
    v_cust_told := coalesce(v_d->0->>'status', '') in ('done', 'demo_captured');
  end if;

  select count(*) into v_cnt from inquiry_cancellations where customer_id=v.customer_id and created_at > now()-interval '30 days';
  if v.customer_id is not null and v_cnt >= 3 then
    if v_email is not null and position('@' in v_email)>1
       and not exists (select 1 from notifications where type='cancel_warning' and to_email=v_email and created_at > now()-interval '30 days') then
      insert into notifications(type,to_email,to_role,inquiry_id,subject,body,channel,status)
      values('cancel_warning', v_email, 'customer', p_inquiry,
        'A quick note about cancelled requests',
        'We noticed a few of your recent requests were cancelled. That is completely fine — but every request you post is prepared and quoted by suppliers who set aside real time for it. To keep things fair for them, we kindly ask that you post requests you intend to proceed with. If you would like help scoping a job before posting, our team is glad to assist.',
        'email','queued');
      v_warned:=true;
    end if;
  end if;
  return jsonb_build_object('ok',true,'cancelled',true,'cancellations_30d',v_cnt,'warned',v_warned,
                            'suppliers_told',v_told,'suppliers_not_reached',v_failed,'customer_told',v_cust_told);
end $function$;

create or replace function public.fn_edit_inquiry(p_inquiry uuid, p_customer uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  v inquiries%rowtype; v_paid boolean; v_deadline timestamptz;
  v_material boolean := false; v_reason text; v_stale int := 0; v_notified int := 0;
  v_cust_email text; v_admin text;
begin
  select * into v from inquiries where id=p_inquiry;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  -- 10 Nov 2026: expired and lost are ends too (one list with _shared/request_closed.ts)
  if v_paid or v.status in ('revealed','completed','cancelled','closed','expired','lost') or v.pipeline_stage in ('revealed','won','cancelled') then
    return jsonb_build_object('error','not_editable','status',v.status,
      'message','This request can no longer be edited.'); end if;
  v_deadline := v.created_at + interval '1 hour';
  if now() > v_deadline then
    return jsonb_build_object('error','edit_window_closed','editable_until',v_deadline,
      'message','Inquiries can be edited within 1 hour of submitting. Please create a new request for changes after that.'); end if;

  -- Decide materiality BEFORE the update, while the old row is still in hand.
  v_material :=
       (p_patch ? 'spec'       and (p_patch->'spec')       is distinct from v.spec)
    or (p_patch ? 'boq'        and (p_patch->'boq')        is distinct from v.boq)
    or (p_patch ? 'budget'     and (p_patch->>'budget')    is distinct from v.budget)
    or (p_patch ? 'scope_type' and (p_patch->>'scope_type') is distinct from v.scope_type)
    or (p_patch ? 'emirate'    and (p_patch->>'emirate')   is distinct from v.emirate)
    or (p_patch ? 'trades'     and array(select jsonb_array_elements_text(p_patch->'trades')) is distinct from v.trades);

  update inquiries set
    summary   = coalesce(p_patch->>'summary', summary),
    raw_input = coalesce(p_patch->>'raw_input', raw_input),
    budget    = coalesce(p_patch->>'budget', budget),
    emirate   = coalesce(p_patch->>'emirate', emirate),
    scope_type= coalesce(p_patch->>'scope_type', scope_type),
    spec      = case when p_patch ? 'spec' then p_patch->'spec' else spec end,
    boq       = case when p_patch ? 'boq' then p_patch->'boq' else boq end,
    trades    = case when p_patch ? 'trades' then array(select jsonb_array_elements_text(p_patch->'trades')) else trades end,
    keywords  = case when p_patch ? 'keywords' then array(select jsonb_array_elements_text(p_patch->'keywords')) else keywords end
    where id=p_inquiry;

  if v_material then
    v_reason := 'The customer changed the requirements of this request on '
             || to_char(now() at time zone 'Asia/Dubai','DD Mon YYYY HH24:MI')
             || ' (Dubai), after this quote was submitted.';

    -- Stale the live quotes and tell each supplier, in one statement so a quote can never be
    -- reverted without its supplier being told.
    with staled as (
      update quotes q
         set stale_at = now(), stale_reason = v_reason, status = 'draft'
       where q.inquiry_id = p_inquiry
         and q.stale_at is null
         and coalesce(q.status,'') in ('submitted','draft')
      returning q.id, q.supplier_id
    ),
    told as (
      insert into notifications(type, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status)
      select 'quote_requirements_changed',
             coalesce(l.claimed_by, l.email), 'supplier', s.supplier_id, p_inquiry, s.id, 'email',
             'The customer changed this request — please re-quote',
             'Hello ' || coalesce(l.company_name,'') || ',' || chr(10) || chr(10) ||
             'A customer has changed the requirements of a request you had already quoted, so your quote has been set back to draft and is no longer being shown to them.' || chr(10) || chr(10) ||
             v_reason || chr(10) || chr(10) ||
             'Please open the request in your supplier portal, review what changed, and submit an updated quote. Your original figures are still there — nothing has been deleted.' || chr(10) || chr(10) ||
             'QuotesDone',
             'queued'
        from staled s join leads l on l.id = s.supplier_id
       where coalesce(l.claimed_by, l.email) is not null
      returning 1
    )
    select (select count(*) from staled), (select count(*) from told) into v_stale, v_notified;

    if v_stale > 0 then
      select email into v_cust_email from customers where id = v.customer_id;
      v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),
                          'management@quotesdone.com');

      -- The customer must know their edit cost them their quotes, or they will wait for prices
      -- that are never coming back on their own. The type now has a notification_copy row in both
      -- languages (above), so a04 states THIS in Arabic rather than the generic fallback (CP-04).
      if v_cust_email is not null then
        insert into notifications(type, to_email, to_role, inquiry_id, channel, subject, body, status)
        values ('inquiry_edit_staled_quotes', v_cust_email, 'customer', p_inquiry, 'email',
                'Your change means we have asked for fresh prices',
                'Hello,' || chr(10) || chr(10) ||
                'You changed the requirements on your request, so the ' || v_stale ||
                ' quote(s) already submitted no longer match what you are asking for. We have asked those suppliers to re-quote against your updated requirements.' || chr(10) || chr(10) ||
                'You do not need to do anything — the new prices will appear as they arrive.' || chr(10) || chr(10) ||
                'QuotesDone', 'queued');
      end if;

      -- THE SALES ENGINEER OWNS AN RFQ WHOSE QUOTES WENT BACK (CP-04). This said 'procurement',
      -- which is not one of the estate's seats, so the follow-up reached nobody.
      insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer','requote_required','needs_review','medium',
              'Requirements changed after ' || v_stale || ' quote(s) were submitted',
              'Watch that the invited suppliers actually re-quote. If they do not, the customer is left with a request that had prices and now has none.',
              jsonb_build_object('inquiry_id', p_inquiry, 'quotes_staled', v_stale,
                                 'suppliers_notified', v_notified, 'changed_at', now()),
              'inquiries', p_inquiry::text);
    end if;
  end if;

  return jsonb_build_object('ok',true,'edited',true,'editable_until',v_deadline,
                            'material_change', v_material,
                            'quotes_staled', v_stale,
                            'suppliers_notified', v_notified);
end $function$;

create or replace function public.fn_inquiry_add_missing_specs(p_inquiry uuid, p_customer uuid, p_answers jsonb, p_source text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  i public.inquiries; v_missing jsonb; v_add jsonb := '{}'::jsonb; v_lines text := ''; v_held text := ''; e record; v_val text; v_ask text;
  v_note bigint; v_held_note bigint; v_after public.inquiries; v_told int := 0; l record; v_res jsonb; v_head text; v_q text; v_kept jsonb := '[]'::jsonb;
begin
  if p_source not in ('customer_portal', 'email_reply') then raise exception 'missing specs come from customer_portal or email_reply, not %', p_source; end if;
  if p_source = 'customer_portal' and p_customer is null then raise exception 'a portal answer names its customer'; end if;
  select * into i from public.inquiries where id = p_inquiry for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'inquiry_not_found'); end if;
  if p_customer is not null and i.customer_id is distinct from p_customer then return jsonb_build_object('ok', false, 'error', 'not_your_inquiry'); end if;
  -- 10 Nov 2026: expired and lost are ends too (one list with _shared/request_closed.ts)
  if coalesce(i.status, '') in ('cancelled', 'closed', 'completed', 'expired', 'lost') then return jsonb_build_object('ok', false, 'error', 'inquiry_closed'); end if;
  if jsonb_typeof(p_answers) is distinct from 'object' then return jsonb_build_object('ok', false, 'error', 'answers_required'); end if;

  -- Only what is missing NOW, keyed as the check reads it; anything else is not this door's to write.
  v_missing := public.fn_inquiry_missing_specs(i.id, 'en')->'missing';
  for e in select a.key, a.value from jsonb_each_text(p_answers) a loop
    v_val := left(btrim(coalesce(e.value, '')), 300);
    select m->>'ask' into v_ask from jsonb_array_elements(v_missing) m where m->>'key' = lower(btrim(e.key));
    if v_ask is null or not public._rfq_answered(v_val) then continue; end if;
    -- Budget and emirate are columns every supplier copy reads raw (inquiries_supplier_safe.emirate, the invitation):
    -- in Arabic script they are NOT written and stay missing, so the page asks them again; digits and English pass
    -- (Arabic-Indic digits are written as the same Western digits first, so "٥٠٠٠" is 5000).
    if lower(btrim(e.key)) in ('budget', 'emirate') then
      v_val := translate(v_val, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
    end if;
    if lower(btrim(e.key)) in ('budget', 'emirate') and v_val ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]' then
      v_kept := v_kept || jsonb_build_array(lower(btrim(e.key))); continue;
    end if;
    v_add := v_add || jsonb_build_object(lower(btrim(e.key)), v_val);
    -- Suppliers read English only: an answer in Arabic script waits for its English on the held note.
    if v_val ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]' then
      v_held := v_held || case when v_held = '' then '' else chr(10) end || v_ask || ' ' || v_val;
    else
      v_lines := v_lines || case when v_lines = '' then '' else chr(10) end || v_ask || ' ' || v_val;
    end if;
  end loop;
  if v_add = '{}'::jsonb then return jsonb_build_object('ok', false, 'error', 'nothing_to_add', 'missing', v_missing, 'kept_missing', v_kept); end if;

  -- The row's own trigger (trg_rfq_complete) re-runs the hold check on this write: every answer, Arabic included,
  -- counts as answered. Budget and emirate are the request's own columns; every other answer is a spec under its key.
  update public.inquiries
     set spec = case when jsonb_typeof(spec) = 'object' then spec else '{}'::jsonb end || (v_add - 'budget' - 'emirate'),
         budget = coalesce(v_add->>'budget', budget),
         emirate = coalesce(v_add->>'emirate', emirate)
   where id = i.id returning * into v_after;

  v_head := case when p_source = 'email_reply' then 'The customer replied with the details this trade needs:' else 'The customer added the details this trade needs:' end;

  if v_held <> '' then
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answer_as_written, english_held_at, answered_at, source)
    values (i.id, null, 'note', null, v_head || chr(10) || v_held, now(), now(), 'missing_specs')
    returning id into v_held_note;
    -- The same request _shared/supplier_english.ts holdForEnglish files (englishQuestion), filed here so the note
    -- and its English can never be separated.
    v_q := 'Translate this message from a customer into clear, professional English for the suppliers quoting the job, '
        || 'as a UAE sales engineer would write it. Keep every measurement, quantity, brand, model and grade code exactly as written. '
        || 'Add nothing and leave nothing out. Put ONLY the English text in "answer".' || chr(10) || chr(10) || v_head || chr(10) || v_held;
    perform public.fn_reason_hold('sales_engineer', 'sales_engineer.supplier_english', left(v_q, 8000),
      jsonb_build_object('seat', 'sales_engineer', 'surface', 'sales_engineer.supplier_english', 'question', v_q,
        'context', jsonb_build_object('audience', 'internal', 'language', 'en'), 'research', false,
        'subject', jsonb_build_object('clarification_id', v_held_note), 'dedupeKey', 'supplier_english:' || v_held_note),
      '{}'::jsonb, jsonb_build_object('clarification_id', v_held_note), 'filed_from_a_request_path', 'supplier_english:' || v_held_note);
  end if;

  if v_lines <> '' then
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source)
    values (i.id, null, 'note', v_head || chr(10) || v_lines, now(), 'missing_specs')
    returning id into v_note;

    -- Every supplier already invited is told, through customer_support's door (suppliers are written in English).
    for l in select le.id, coalesce(nullif(btrim(le.claimed_by), ''), le.email) as to_email
               from public.inquiry_matches x join public.leads le on le.id = x.supplier_id
              where x.inquiry_id = i.id and not coalesce(le.banned, false)
                and coalesce(nullif(btrim(le.claimed_by), ''), le.email, '') like '%@%' loop
      v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'rfq_addendum', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', l.to_email,
        'to_role', 'supplier', 'lead_id', l.id, 'inquiry_id', i.id, 'lang', 'en',
        'subject', 'The customer added detail to a request you were invited to quote',
        'body', 'The customer added this to the ' || coalesce(i.category, '') || coalesce(' job in ' || nullif(i.emirate, ''), ' job')
                || ' you were invited to quote:' || chr(10) || chr(10) || v_lines || chr(10) || chr(10)
                || 'It is now part of the request. Log in to your QuotesDone supplier portal to see the full request and quote.',
        'dedupe_key', 'missing_specs:' || v_note || ':' || l.id)));
      v_told := v_told + 1;
    end loop;
  end if;

  v_missing := public.fn_inquiry_missing_specs(i.id, null);
  return jsonb_build_object('ok', true, 'added', (select jsonb_agg(k) from jsonb_object_keys(v_add) k),
    'ready', coalesce(v_after.rfq_ready, false), 'still_missing', v_missing->'missing',
    'reached_suppliers', (v_missing->>'reached_suppliers')::boolean, 'suppliers_told', v_told, 'note_id', v_note,
    'held_for_english', v_held_note is not null, 'held_note_id', v_held_note, 'kept_missing', v_kept);
end $function$;

select case
  when position('''expired'',''lost''' in pg_get_functiondef('public.fn_edit_inquiry(uuid, uuid, jsonb)'::regprocedure)) = 0 then 'PROBE FAILED: fn_edit_inquiry edits an expired or lost request'
  when position('close it instead' in pg_get_functiondef('public.fn_cancel_inquiry(uuid, uuid, text)'::regprocedure)) > 0 then 'PROBE FAILED: the cancel refusal still offers a close action that does not exist'
  else 'PROBE OK' end as verdict;
