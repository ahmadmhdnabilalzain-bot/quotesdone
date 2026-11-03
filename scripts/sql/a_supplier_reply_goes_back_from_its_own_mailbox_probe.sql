-- PROBE for a_supplier_reply_goes_back_from_its_own_mailbox.sql. Seat: sales_engineer. 3 Nov 2026.
-- Pure probe, no DDL: it always raises CHK<<...>> and rolls back. Fixtures only (ZZ DEMO lead, @example.invalid senders);
-- nothing here can send: every row it writes is rolled back before send_outbox could claim it. PROBE OK only if
--   A. a message that came INTO the supplier mailbox from a lead's address (inbound lead_id NULL) is answered with
--      to_role 'supplier', that lead, kind 'supplier_mailbox_reply' and in_reply_to = the supplier's Message-ID;
--   B. a supplier's message to another mailbox (management@, lead_id set) is answered with to_role 'supplier' and the
--      lead, but NO kind (it keeps its Resend route);
--   C. an unknown sender's message to info@ is answered exactly as before: to_role, lead_id and kind NULL, threaded;
--   D. no reply is twinned on WhatsApp (fn_wa_fanout), even for a lead whose WhatsApp answer is 'none';
--   E. fn_inbox_send stays service_role only; the real rows of the defect (notifications 125102 and 125121,
--      inbound_messages 1829) are untouched.
do $probe$
declare
  f text[] := '{}'; v_mailbox text; v_lead bigint; ia bigint; ib bigint; ic bigint; na record; nb record; nc record;
  v_wa int; v_open text; r0 text; r1 text;
  pa text := '<zz-demo-reply-lane-a@example.invalid>'; pb text := '<zz-demo-reply-lane-b@example.invalid>'; pc text := '<zz-demo-reply-lane-c@example.invalid>';
begin
  select md5(string_agg(id || coalesce(status,'') || coalesce(to_role,'') || coalesce(provider_message_id,'') || coalesce(sent_at::text,''), ',' order by id))
    || coalesce((select replied_at::text from public.inbound_messages where id = 1829), '') into r0
    from public.notifications where id in (125102, 125121);
  select coalesce(nullif(lower(btrim(value)), ''), 'supplier@quotesdone.com') into v_mailbox from public.app_secrets where key = 'invite_m365_mailbox';
  v_mailbox := coalesce(v_mailbox, 'supplier@quotesdone.com');

  insert into public.leads (company_name, email, whatsapp_opt)
  values ('ZZ DEMO reply-lane probe LLC', 'zz-demo-reply-lane@example.invalid', 'none') returning id into v_lead;

  insert into public.inbound_messages (from_email, to_email, subject, body, raw, lead_id)
  values ('zz-demo-reply-lane@example.invalid', v_mailbox, 'Re: A question about your work in the UAE', 'ZZ DEMO yes', jsonb_build_object('message_id', pa), null)
  returning id into ia;
  insert into public.inbound_messages (from_email, to_email, subject, body, raw, lead_id)
  values ('zz-demo-reply-lane@example.invalid', 'management@quotesdone.com', 'ZZ DEMO question', 'ZZ DEMO body', jsonb_build_object('message_id', pb), v_lead)
  returning id into ib;
  insert into public.inbound_messages (from_email, to_email, subject, body, raw, lead_id)
  values ('zz-demo-reply-lane-customer@example.invalid', 'info@quotesdone.com', 'ZZ DEMO enquiry', 'ZZ DEMO body', jsonb_build_object('message_id', pc), null)
  returning id into ic;

  perform public.fn_inbox_send(ia, 'Hello,' || chr(10) || chr(10) || 'ZZ DEMO probe reply A.' || chr(10) || chr(10) || 'Kind regards,' || chr(10) || 'The QuotesDone Team', 'sales_engineer');
  perform public.fn_inbox_send(ib, 'ZZ DEMO probe reply B.', 'sales_engineer');
  perform public.fn_inbox_send(ic, 'ZZ DEMO probe reply C.', 'customer_support');

  select * into na from public.notifications where type = 'inbound_reply' and channel = 'email' and in_reply_to = pa order by id desc limit 1;
  select * into nb from public.notifications where type = 'inbound_reply' and channel = 'email' and in_reply_to = pb order by id desc limit 1;
  select * into nc from public.notifications where type = 'inbound_reply' and channel = 'email' and in_reply_to = pc order by id desc limit 1;

  if na.id is null then f := f || 'A: no reply row';
  else
    if na.to_role is distinct from 'supplier' then f := f || ('A: to_role ' || coalesce(na.to_role, 'NULL')); end if;
    if na.lead_id is distinct from v_lead then f := f || ('A: lead_id ' || coalesce(na.lead_id::text, 'NULL') || ', expected ' || v_lead); end if;
    if na.kind is distinct from 'supplier_mailbox_reply' then f := f || ('A: kind ' || coalesce(na.kind, 'NULL')); end if;
    if na.lang is distinct from 'en' then f := f || ('A: lang ' || coalesce(na.lang, 'NULL')); end if;
    if na.body not like '%ZZ DEMO probe reply A.%' then f := f || 'A: the reply body was replaced'; end if;
  end if;
  if nb.id is null then f := f || 'B: no reply row';
  else
    if nb.to_role is distinct from 'supplier' or nb.lead_id is distinct from v_lead then f := f || ('B: to_role ' || coalesce(nb.to_role, 'NULL') || ' lead ' || coalesce(nb.lead_id::text, 'NULL')); end if;
    if nb.kind is not null then f := f || ('B: a reply to management@ took kind ' || nb.kind); end if;
  end if;
  if nc.id is null then f := f || 'C: no reply row';
  elsif nc.to_role is not null or nc.lead_id is not null or nc.kind is not null then
    f := f || ('C: the customer-side reply changed: ' || coalesce(nc.to_role, 'NULL') || '/' || coalesce(nc.lead_id::text, 'NULL') || '/' || coalesce(nc.kind, 'NULL'));
  end if;

  select count(*) into v_wa from public.notifications where type = 'inbound_reply' and channel = 'whatsapp' and to_email like 'zz-demo-reply-lane%@example.invalid';
  if v_wa <> 0 then f := f || ('D: ' || v_wa || ' WhatsApp twin(s) of a reply'); end if;

  select string_agg(r.rolname, ',') into v_open from pg_roles r
   where r.rolname in ('anon', 'authenticated') and has_function_privilege(r.rolname, 'public.fn_inbox_send(bigint,text,text)', 'execute');
  if v_open is not null then f := f || ('E: fn_inbox_send executable by ' || v_open); end if;
  select md5(string_agg(id || coalesce(status,'') || coalesce(to_role,'') || coalesce(provider_message_id,'') || coalesce(sent_at::text,''), ',' order by id))
    || coalesce((select replied_at::text from public.inbound_messages where id = 1829), '') into r1
    from public.notifications where id in (125102, 125121);
  if r1 is distinct from r0 then f := f || 'E: a real row of the defect changed'; end if;

  raise exception 'CHK<<%>> A=%/%/% B=%/% C=%/% wa=%',
    case when cardinality(f) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(f, '; ') end,
    coalesce(na.to_role, 'NULL'), coalesce(na.kind, 'NULL'), coalesce(na.in_reply_to, 'NULL'),
    coalesce(nb.to_role, 'NULL'), coalesce(nb.kind, 'NULL'), coalesce(nc.to_role, 'NULL'), coalesce(nc.in_reply_to, 'NULL'), v_wa;
end
$probe$;
