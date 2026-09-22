-- AN EDIT IS OWNED BY A LIVE SEAT, AND ITS CUSTOMER NOTICE SPEAKS THEIR LANGUAGE.
--
-- Customer-portal audit CP-04, 22 Sep 2026. Two defects in public.fn_edit_inquiry, both about who
-- the work belongs to and who reads the result. The field gate itself — only the summary, budget
-- and emirate may be edited in place, and the summary is scrubbed of the customer's own identity
-- before it is written — is enforced in customer_api's edit_inquiry action, which builds the patch;
-- this file is the two things that live in the database.
--
-- 1. THE FOLLOW-UP WAS ADDRESSED TO A SEAT THAT DOES NOT EXIST. When a customer's change staled
--    quotes, the routine filed an agent_actions row for agent 'procurement'. There is no such seat
--    (the estate runs ceo, customer_support, sales_engineer, accountant, it_engineer — the
--    founder's rule of 7 Sep 2026: no job or task without an agent), so "watch that the invited
--    suppliers actually re-quote" has been sitting in a queue nobody reads since the routine was
--    written. It is the sales engineer's work: it is about quotes coming back on an RFQ.
--
-- 2. THE CUSTOMER'S NOTICE WAS ENGLISH-ONLY. The row was inserted with an English subject and body
--    whatever the customer registered in. The estate already has one answer to this — the
--    notification_copy table, which a04_notifications_speak_the_recipients_language uses to replace
--    a message queued wholly in the other language (the registered language follows the whole
--    workflow, founder 14 Sep 2026). The type had no row, so the trigger could only fall back to
--    the generic '*' wording: an Arabic customer was told "you have an update", not that their edit
--    had sent their quotes back for re-pricing. The wording is added below; the routine's own
--    English text is unchanged and is what an English customer still receives.
--
-- Nothing else in the routine changes: the ownership check, the 1-hour window, the materiality
-- test, the staling and the supplier notices are all as they were.
insert into public.notification_copy (type, subject_en, body_en, subject_ar, body_ar, note) values
('inquiry_edit_staled_quotes',
 'Your change means we have asked for fresh prices',
 'You changed the requirements on your request {ref}, so the quotes already submitted no longer match what you are asking for. We have asked those suppliers to re-quote against your updated requirements. You do not need to do anything — the new prices will appear as they arrive.',
 'تغييرك يعني أننا طلبنا أسعارًا جديدة',
 'غيّرت متطلبات طلبك {ref}، فلم تعد العروض المقدَّمة مطابقة لما تطلبه. وقد طلبنا من هؤلاء المورّدين إعادة التسعير وفق متطلباتك المحدّثة. لا حاجة إلى أي إجراء منك — ستظهر الأسعار الجديدة فور وصولها.',
 'fn_edit_inquiry, the customer notice when an edit staled live quotes (CP-04)')
on conflict (type) do update set subject_en = excluded.subject_en, body_en = excluded.body_en,
  subject_ar = excluded.subject_ar, body_ar = excluded.body_ar, note = excluded.note, updated_at = now();

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
  if v_paid or v.status in ('revealed','completed','cancelled','closed') or v.pipeline_stage in ('revealed','won','cancelled') then
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

revoke execute on function public.fn_edit_inquiry(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.fn_edit_inquiry(uuid, uuid, jsonb) to service_role;
