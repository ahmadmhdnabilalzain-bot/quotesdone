-- THE QUOTATION ALERT READS THE COMMITTED STATE AND NOTHING ELSE
--
-- Build spec §3. "Only trigger from the committed canonical publication state, not drafts or failed
-- uploads. Recheck withdrawals and current visibility before sending. Deduplicate by business event,
-- recipient, channel, purpose and relevant publication version."
--
-- public.quotes carries committed_at and committed_hash. Those two are the canonical publication
-- state, and this function reads no other signal: a row that exists is not a published quotation,
-- and a draft that a supplier is still editing must never reach a customer's phone.
--
-- committed_hash IS the publication version in the dedupe key. That is what makes an EDIT different
-- from a NEW quotation: re-committing changes the hash and is allowed to notify again; the same
-- commit arriving twice is the same hash and is not. The spec says it in one line -- "Do not call a
-- quotation edit a new supplier" -- and the hash is how that is enforced rather than described.

-- First, a correction to the scan: public.quotes has quote_amount, not total_amount. A scan that
-- names a column which does not exist would throw at send time, and a scan that throws is a scan
-- that never ran.
create or replace function public.fn_support_anonymity_scan(
  p_text text,
  p_subject text,
  p_attachment_ref text,
  p_supplier_lead_id bigint,
  p_quote_id text default null)
returns jsonb
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  s record; v_hay text; v_hits text[] := '{}'; v_digits text;
begin
  v_hay := lower(coalesce(p_text,'') || ' ' || coalesce(p_subject,'') || ' ' || coalesce(p_attachment_ref,''));

  select company_name, email, phone, trade_license_no into s from public.leads where id = p_supplier_lead_id;
  if not found then
    return jsonb_build_object('safe', false, 'reason',
      'the supplier row could not be read, so nothing about it could be checked for', 'hits', '[]'::jsonb);
  end if;

  if coalesce(btrim(s.company_name),'') <> '' and position(lower(btrim(s.company_name)) in v_hay) > 0
    then v_hits := array_append(v_hits, 'company_name'); end if;
  if coalesce(btrim(s.email),'') <> '' and position(lower(btrim(s.email)) in v_hay) > 0
    then v_hits := array_append(v_hits, 'email'); end if;
  v_digits := regexp_replace(coalesce(s.phone,''), '[^0-9]', '', 'g');
  if length(v_digits) >= 7 and position(v_digits in regexp_replace(v_hay, '[^0-9]', '', 'g')) > 0
    then v_hits := array_append(v_hits, 'phone'); end if;
  if coalesce(btrim(s.trade_license_no),'') <> '' and position(lower(btrim(s.trade_license_no)) in v_hay) > 0
    then v_hits := array_append(v_hits, 'trade_license_no'); end if;

  if p_quote_id is not null then
    if exists (select 1 from public.quotes q
                where q.id::text = p_quote_id and q.quote_amount is not null
                  and position(regexp_replace(round(q.quote_amount)::text, '[^0-9]', '', 'g')
                               in regexp_replace(v_hay, '[^0-9]', '', 'g')) > 0)
      then v_hits := array_append(v_hits, 'quoted_amount'); end if;
  end if;

  return jsonb_build_object(
    'safe', array_length(v_hits, 1) is null,
    'hits', to_jsonb(v_hits),
    'checked', jsonb_build_array('company_name','email','phone','trade_license_no','quoted_amount'),
    'scanned_at', now(),
    'note', case when array_length(v_hits,1) is null
                 then 'No supplier-identifying or commercial value from the live row appears in the subject, body or attachment name.'
                 else 'REFUSED: the message contains ' || array_to_string(v_hits, ', ') || ' from the live supplier row.' end);
end $function$;

-- ---------------------------------------------------------------------------------------------
-- THE ALERT
-- ---------------------------------------------------------------------------------------------
-- p_quote_id is a UUID. public.quotes.id is uuid and so is public.inquiries.id; declaring it
-- bigint meant this function could never be called with a real quotation id -- it would have
-- failed at the first genuine event, not in a probe.
drop function if exists public.fn_support_notify_new_quotation(bigint);
create or replace function public.fn_support_notify_new_quotation(p_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  q record; c record; v_case bigint; v_ref text; v_portal text;
  v_body text; v_subject text; v_scan jsonb;
  v_queued jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb;
  v_dedupe text; v_id bigint;
begin
  -- THE COMMITTED STATE, AND THE CURRENT ONE. Both are required: committed_at proves it was
  -- published, and the status re-read proves it has not been withdrawn since. A quotation withdrawn
  -- between publication and this call must not be announced, and only a fresh read can know that.
  select qq.id, qq.inquiry_id, qq.supplier_id, qq.committed_at, qq.committed_hash, qq.status, qq.anonymized
    into q from public.quotes qq where qq.id = p_quote_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', format('no quotation %s', p_quote_id::text));
  end if;
  if q.committed_at is null then
    return jsonb_build_object('ok', false, 'reason',
      'this quotation is not committed. A draft or a failed upload is not a publication and must never reach a customer.');
  end if;
  if coalesce(q.status,'') in ('withdrawn','cancelled','rejected','expired') then
    return jsonb_build_object('ok', false, 'reason',
      format('the quotation is %L now. It was committed once; it is not visible today, and the customer is not told about it.', q.status));
  end if;

  select i.rfq_no, cu.id cust_id, cu.full_name, cu.phone, cu.email, cu.wa_optin, cu.banned
    into c
    from public.inquiries i
    join public.customers cu on cu.id = i.customer_id
   where i.id = q.inquiry_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason',
      'the inquiry or its owner could not be read. Nothing is sent: a notification with no verified recipient is a message to a guess.');
  end if;
  if coalesce(c.banned, false) then
    return jsonb_build_object('ok', false, 'reason', 'the inquiry owner is banned; no notification is sent.');
  end if;

  -- rfq_no is an INTEGER sequence number. The customer-facing reference is rendered from it when
  -- it exists and from the inquiry id when it does not, so the shape is stable either way.
  v_ref := case when c.rfq_no is not null then 'RFQ-' || c.rfq_no::text
                else 'INQ-' || q.inquiry_id::text end;
  v_portal := coalesce((select value from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com') || '/portal';

  -- DETERMINISTIC RENDERING. The spec requires it for notifications, and it is also the only way the
  -- anonymity scan means anything: a model could compose a different sentence next time, and the
  -- scan would be checking a message nobody will send.
  v_body := 'You have received a new quotation for inquiry ' || v_ref
         || '. Sign in to your QuotesDone portal to review it: ' || v_portal || '.';
  v_subject := 'A new quotation for inquiry ' || v_ref;

  -- THE SCAN, before anything is queued. It reads the live supplier row and the live quotation, so
  -- it is checking for THIS supplier's actual name, email, phone and amount -- not a word list.
  v_scan := public.fn_support_anonymity_scan(v_body, v_subject, null, q.supplier_id, q.id::text);
  if (v_scan->>'safe') <> 'true' then
    return jsonb_build_object('ok', false, 'blocked', true, 'reason', v_scan->>'note', 'scan', v_scan);
  end if;

  -- The case that owns this conversation.
  insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject)
  values ('case:quote:' || q.id::text, 'customer', c.cust_id::text, v_ref,
          'New quotation published for ' || v_ref)
  on conflict (case_ref) do update set last_activity_at = now()
  returning case_id into v_case;
  if v_case is null then
    select case_id into v_case from public.support_case where case_ref = 'case:quote:' || q.id::text;
  end if;

  -- BOTH CHANNELS, EACH JUDGED ON ITS OWN PERMISSION. The spec: "Check both-channel permissions
  -- independently and record blocked/suppressed outcomes honestly." A missing email is not a reason
  -- to skip WhatsApp, and no consent on WhatsApp is not a reason to skip email.
  --
  -- The dedupe key carries the publication version (committed_hash), so re-committing a changed
  -- quotation notifies again and the same commit arriving twice does not.
  if coalesce(btrim(c.phone),'') <> '' and coalesce(c.wa_optin, false) then
    v_dedupe := 'quote_published|' || q.id::text || '|' || coalesce(q.committed_hash,'nohash') || '|whatsapp|' || c.phone;
    insert into public.support_notification
      (dedupe_key, case_id, purpose, channel, recipient, inquiry_ref, publication_version,
       subject, body, anonymity_checked_at, anonymity_result)
    values (v_dedupe, v_case, 'quote_published', 'whatsapp', c.phone, v_ref, q.committed_hash,
            null, v_body, now(), v_scan)
    on conflict (dedupe_key) do nothing
    returning id into v_id;
    v_queued := v_queued || jsonb_build_object('channel','whatsapp','queued', v_id is not null,
                  'note', case when v_id is null then 'already queued for this publication version' else 'queued' end);
  else
    v_skipped := v_skipped || jsonb_build_object('channel','whatsapp','reason',
      case when coalesce(btrim(c.phone),'') = '' then 'no mobile on the customer record'
           else 'no WhatsApp opt-in recorded' end);
  end if;

  if coalesce(btrim(c.email),'') <> '' then
    v_dedupe := 'quote_published|' || q.id::text || '|' || coalesce(q.committed_hash,'nohash') || '|email|' || c.email;
    insert into public.support_notification
      (dedupe_key, case_id, purpose, channel, recipient, inquiry_ref, publication_version,
       subject, body, anonymity_checked_at, anonymity_result)
    values (v_dedupe, v_case, 'quote_published', 'email', c.email, v_ref, q.committed_hash,
            v_subject, v_body, now(), v_scan)
    on conflict (dedupe_key) do nothing
    returning id into v_id;
    v_queued := v_queued || jsonb_build_object('channel','email','queued', v_id is not null,
                  'note', case when v_id is null then 'already queued for this publication version' else 'queued' end);
  else
    v_skipped := v_skipped || jsonb_build_object('channel','email','reason','no email on the customer record');
  end if;

  return jsonb_build_object(
    'ok', true, 'quote_id', q.id, 'inquiry_ref', v_ref, 'case_id', v_case,
    'publication_version', q.committed_hash,
    'queued', v_queued, 'skipped', v_skipped, 'anonymity', v_scan,
    'note', 'Queued only. Delivery is the sender''s job and its outcome is recorded on the row, never assumed here.');
end $function$;

comment on function public.fn_support_notify_new_quotation(uuid) is
  'Announces a committed quotation to the inquiry owner on both channels without naming the supplier. Refuses a draft, refuses a withdrawn quotation on a fresh read, scans the rendered message against the live supplier and quotation rows before queueing, judges each channel''s permission independently, and deduplicates on the publication version so an edit notifies and a repeat does not.';

revoke execute on function public.fn_support_notify_new_quotation(uuid) from public;
revoke execute on function public.fn_support_notify_new_quotation(uuid) from anon;
revoke execute on function public.fn_support_notify_new_quotation(uuid) from authenticated;
revoke execute on function public.fn_support_anonymity_scan(text,text,text,bigint,text) from public;
revoke execute on function public.fn_support_anonymity_scan(text,text,text,bigint,text) from anon;
revoke execute on function public.fn_support_anonymity_scan(text,text,text,bigint,text) from authenticated;
