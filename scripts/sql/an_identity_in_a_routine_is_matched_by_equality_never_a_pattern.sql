-- AN IDENTITY IS FOUND BY EQUALITY, NEVER BY A PATTERN, in the three routines that matched one with LIKE
-- (security audit of 17 Nov 2026, finding 1, docs/reports/2026-11-17-security-audit.md; seat it_engineer).
--
-- The edge functions are fixed in supabase/functions/_shared/address_filter.ts. A catalogue read of production on
-- 17 Nov 2026 (every public routine line with LIKE/ILIKE beside an address word, 135 lines) found three routines that
-- put a VALUE, not a constant, into a pattern; every other line is a constant ('%@example.invalid', 'expenses@%', ...).
-- None of the three is executable by anon or authenticated (SELECT of has_function_privilege, same day): the callers are
-- service-role seats, so this is the same defect behind a closed door, fixed so it cannot be reached by a new door.
--   1. fn_conversation_record(text,integer): `lower(v.cc) like '%' || v_email || '%'`, v_email the asked address,
--      unescaped. `a@x.com` matched a cc of `ba@x.com`, and `_` / `%` in the address were wildcards. Now: v_email is
--      one of the cc's addresses (split on , and ;, a "Name <addr>" read as addr), exactly.
--   2. fn_sales_engineer_follows_up_supplier_replies(): `lower(n.from_email) like '%' || lower(f.to_email) || '%'`.
--      A mail from `ba@x.com` dropped the follow-up owed to `a@x.com`. Now the sender address equals the supplier's.
--   3. fn_business_entity_lookup(text,text): `l.company_name ilike k`, k the asked key, unescaped: `%` answered the
--      first company of all. Now a company name is matched as itself, case and surrounding space ignored.
-- Each body is production's (pg_get_functiondef, 17 Nov 2026 ~09:15 UTC; md5 b8b62923d33d05564d9b3c74b45de116,
-- 497f270df73a54ffd6c1d428c2f04dea, ae0df9064145ee450b21ddb23ceba387) with the one line above changed and nothing else.
-- CREATE OR REPLACE keeps each routine's grants (service only), its SECURITY DEFINER and its pinned search_path.

CREATE OR REPLACE FUNCTION public.fn_conversation_record(p_contact text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_raw text := btrim(coalesce(p_contact, '')); v_email text; v_tail text;
        v_kind text; v_id text; v_msgs jsonb;
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if v_raw ~* '^(customer|supplier):.+' then
    v_kind := lower(split_part(v_raw, ':', 1)); v_id := substring(v_raw from position(':' in v_raw) + 1);
  elsif position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);
  else
    return jsonb_build_object('ok', false, 'reason', 'give an email, a phone number, customer:<id> or supplier:<id>');
  end if;
  if v_kind is null then
    select p.party_kind, p.party_id into v_kind, v_id
      from public.fn_conversation_party(null, null, null, v_email, v_tail) p;
    if v_kind = 'company' then v_kind := null; v_id := null; end if;
  end if;

  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) into v_msgs from (
    select jsonb_build_object(
             'at', v.occurred_at, 'channel', v.channel, 'direction', v.direction,
             'from', v.from_addr, 'to', v.to_addr, 'cc', v.cc, 'subject', v.subject,
             'body', v.body, 'has_html', v.html is not null, 'attachments', v.attachments,
             'party', v.party_kind, 'party_id', v.party_id, 'inquiry_id', v.inquiry_id,
             'ref', v.source_table || ':' || v.source_id,
             'pdf', case when a.pdf_path is not null then jsonb_build_object('bucket', a.pdf_bucket, 'path', a.pdf_path) end,
             'dropbox', case when b.id is not null then jsonb_build_object('path', b.dropbox_path, 'status', b.status) end) x
      from public.v_conversation_message v
      left join public.conversation_archive a on a.source_table = v.source_table and a.source_id = v.source_id
      left join public.doc_backups b on b.dedupe_key = 'CONV:' || v.source_table || ':' || v.source_id
     where (v_id is not null and v.party_kind = v_kind and v.party_id = v_id)
        or (v_email is not null and (lower(v.from_addr) = v_email or lower(v.to_addr) = v_email or v_email = any (select lower(btrim(coalesce(substring(t from '<([^>]+)>'), t))) from regexp_split_to_table(coalesce(v.cc, ''), '[,;]') t)))
        or (v_tail is not null and (right(regexp_replace(coalesce(v.from_addr, ''), '[^0-9]', '', 'g'), 9) = v_tail
                                 or right(regexp_replace(coalesce(v.to_addr, ''), '[^0-9]', '', 'g'), 9) = v_tail))
     order by v.occurred_at desc
     limit greatest(1, least(coalesce(p_limit, 200), 2000))) z;

  return jsonb_build_object('ok', true, 'contact', coalesce(v_email, v_tail, v_raw),
    'party', v_kind, 'party_id', v_id, 'message_count', jsonb_array_length(v_msgs), 'messages', v_msgs,
    'assembled_by', 'fn_conversation_record (deterministic; full text from every store; no model)');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_follows_up_supplier_replies()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record; f public.supplier_reply_followup; l public.leads; v_acted int := 0; v_sent int := 0; v_dropped int := 0; v_site text; v_body text; v_err jsonb := '[]'::jsonb;
begin
  -- 1. replies whose triage has spoken (or the hour passed)
  for h in select a.id from public.agent_actions a
             join public.inbound_messages m on m.id = (a.detail->>'inbound_message_id')::bigint
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' in ('invite.reply', 'mailbox.supplier_reply')
              and (m.triaged_at is not null or m.replied_at is not null or now() >= m.created_at + interval '1 hour')
            order by a.id limit 50 loop
    begin
      perform public.fn_seat_handoff_act(h.id);
      v_acted := v_acted + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- 2. a bounce the customer_support seat already acted on leaves review
  update public.inbound_messages i set needs_review = false
    from public.agent_actions b
   where b.kind = 'mail_bounce' and b.status = 'auto_done' and b.target_table = 'inbound_messages'
     and b.target_id = i.id::text and i.needs_review;

  -- 3. the one follow-up, on a Dubai weekday inside the sending window
  if extract(isodow from now() at time zone 'Asia/Dubai') not in (6, 7)
     and extract(hour from now() at time zone 'Asia/Dubai') between 9 and 16 then
    select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
    for f in select * from public.supplier_reply_followup where state = 'due' and due_at <= now() order by id limit 20 for update skip locked loop
      -- a follow-up only after an answer the reading allowed (ruling 1633): never to a vendor, a notification or a template answer
      if not public.fn_mailbox_followup_allowed(f.inbound_message_id) or public.fn_is_machine_sender(f.to_email) then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'the mail it follows was not one the reading allowed an answer to', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      l := null;
      if f.lead_id is not null then select * into l from public.leads where id = f.lead_id; end if;
      if f.intent <> 'subsidiary' and (coalesce(l.claimed, false) or l.registration_submitted_at is not null) then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'the company started registering', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      if public.fn_is_demo_email(f.to_email) or exists (select 1 from public.email_suppressions s where lower(s.email) = lower(f.to_email)) then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'suppressed or a fixture', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      if exists (select 1 from public.inbound_messages n where lower(btrim(coalesce(substring(n.from_email from '<([^>]+)>'), n.from_email))) = lower(btrim(f.to_email)) and n.id > f.inbound_message_id and n.owner_role is distinct from 'it_engineer') then
        update public.supplier_reply_followup set state = 'dropped', outcome = 'the supplier wrote again: that mail is answered on its own', done_at = now() where id = f.id;
        v_dropped := v_dropped + 1; continue;
      end if;
      v_body := case f.intent
        when 'subsidiary' then E'Hello,\n\nA week ago you asked about registering a separate company. It registers with its own trade licence and a different e-mail address: ' || coalesce(v_site, 'https://quotesdone.com') || E'/en/portal\n\nIf we can help, reply to this e-mail. This is the only reminder we will send about it.'
        when 'later' then E'Hello,\n\nYou told us a little while ago that later would suit you better. Registration is still free for our first 1,000 suppliers, and takes a few minutes: ' || coalesce(v_site, 'https://quotesdone.com') || E'/en/portal\n\nThis is the only reminder we will send about it.'
        else E'Hello,\n\nYou replied to us last week and your company has not registered yet. It takes a few minutes: ' || coalesce(v_site, 'https://quotesdone.com') || E'/en/portal\n\nIf something is stopping you, reply to this e-mail. This is the only reminder we will send about it.' end;
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'supplier_registration_reminder', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', f.to_email, 'to_role', 'supplier',
        'lead_id', f.lead_id, 'lang', 'en', 'subject', 'Your QuotesDone supplier registration', 'body', v_body,
        'dedupe_key', 'supplier_reply_followup:' || f.id)));
      update public.supplier_reply_followup set state = 'sent', outcome = 'follow-up queued', done_at = now() where id = f.id;
      v_sent := v_sent + 1;
    end loop;
  end if;
  return jsonb_build_object('acted', v_acted, 'followups_sent', v_sent, 'followups_dropped', v_dropped, 'errors', v_err);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_business_entity_lookup(p_entity text, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; e text := lower(btrim(coalesce(p_entity,''))); k text := btrim(coalesce(p_key,''));
begin
  if k = '' then return jsonb_build_object('ok',false,'error','a key is required (id, email, company name or phone)'); end if;
  if e in ('customer','buyer') then
    select to_jsonb(c) into v from public.customers c where c.id::text=k or lower(c.email)=lower(k) or c.phone=k limit 1;
  elsif e in ('supplier','lead','vendor') then
    select to_jsonb(l) into v from public.leads l where l.id::text=k or lower(l.email)=lower(k) or lower(btrim(l.company_name)) = lower(k) or l.phone=k limit 1;
  elsif e in ('inquiry','rfq','request') then
    select to_jsonb(i) into v from public.inquiries i where i.id::text=k limit 1;
  elsif e in ('quote','quotation','offer') then
    select to_jsonb(q) into v from public.quotes q where q.id::text=k limit 1;
  elsif e in ('transaction','payment','order','reveal') then
    select to_jsonb(t) into v from public.transactions t where t.id::text=k limit 1;
  else
    return jsonb_build_object('ok',false,'error','unknown entity "'||e||'". Use: customer, supplier, inquiry, quote or transaction.');
  end if;
  if v is null then return jsonb_build_object('ok',true,'entity',e,'key',k,'found',false); end if;
  return jsonb_build_object('ok',true,'entity',e,'found',true,'profile',v);
end $function$;

-- VERDICT: the three lines are gone and the new ones are live; the grants did not open.
select case
  when pg_get_functiondef('public.fn_conversation_record(text,integer)'::regprocedure) like '%like ''\%'' || v_email%' then 'PROBE FAILED: fn_conversation_record still matches the cc by a pattern'
  when pg_get_functiondef('public.fn_sales_engineer_follows_up_supplier_replies()'::regprocedure) like '%like ''\%'' || lower(f.to_email)%' then 'PROBE FAILED: the follow-up still matches the sender by a pattern'
  when pg_get_functiondef('public.fn_business_entity_lookup(text,text)'::regprocedure) like '%company_name ilike k%' then 'PROBE FAILED: the entity lookup still matches a company name by a pattern'
  when exists (select 1 from unnest(array['public.fn_conversation_record(text,integer)', 'public.fn_sales_engineer_follows_up_supplier_replies()',
                                          'public.fn_business_entity_lookup(text,text)']) s(sig)
                where has_function_privilege('anon', s.sig::regprocedure, 'execute') or has_function_privilege('authenticated', s.sig::regprocedure, 'execute'))
    then 'PROBE FAILED: a client role can execute one of the three'
  else 'PROBE OK' end as verdict;
