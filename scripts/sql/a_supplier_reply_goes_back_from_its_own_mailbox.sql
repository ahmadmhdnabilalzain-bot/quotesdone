-- A SUPPLIER'S REPLY GOES BACK FROM ITS OWN MAILBOX. Seat: sales_engineer. 3 Nov 2026.
--
-- MEASURED (production, 3 Nov 2026 08:35Z):
--   * notification 125102 (supplier_invite, lead 19820, info@hindco.co.in) left the Microsoft 365 lane from
--     supplier@quotesdone.com at 06:31Z (provider_message_id m365:<qd-notif-125102...>), so it is in supplier@'s
--     Sent Items;
--   * the supplier answered supplier@ at 07:00Z (inbound_messages 1829, lead_id 19820, In-Reply-To = that Message-ID);
--   * email_triage answered at 07:34Z through this function, which wrote notification 125121 as inbound_reply with
--     to_role NULL and lead_id NULL. send_outbox's Microsoft 365 lane carries only to_role 'supplier', so the answer
--     went through Resend (01a1a054-..., delivered, threaded), From "QuotesDone <info@quotesdone.com>" (email_from_info,
--     the From of every non-supplier row) with Reply-To supplier@ (conversationReplyTo, reader proven 07:30Z). It is
--     not in supplier@'s Sent Items: in Outlook the founder sees the supplier's reply and then nothing.
--   * every inbound_reply since invite_m365_enabled was last set (19 Oct 14:18Z) went to a supplier and through
--     Resend: 3 rows, 117599 and 125121 answering supplier@, 121564 answering management@ (lead 19398).
--
-- 1. fn_inbox_send names the supplier on the reply. When the sender is not staff or a customer
--    (fn_mail_sender_known) and the message carries a lead, the sender is a lead, or it came into the supplier mailbox
--    (app_secrets.invite_m365_mailbox), the reply is to_role 'supplier' with the lead (the message's own, else the lead
--    whose email or claimed_by is the sender), so the lead's history counts it. Only a reply to a message that came
--    INTO the supplier mailbox also carries kind 'supplier_mailbox_reply' (m365_lane.ts M365_REPLY_KIND): that row is
--    the one the Microsoft 365 lane sends back from the same mailbox, threaded on in_reply_to. A customer's or an
--    unknown sender's reply elsewhere is written exactly as before (to_role, lead_id and kind NULL).
-- 2. fn_wa_fanout makes no WhatsApp twin of a reply. With to_role NULL a reply was never twinned; with 'supplier' a
--    registered supplier with a confirmed number would have had the email answer repeated on WhatsApp. An answer goes
--    back on the channel the message came in on. Otherwise the live body unchanged (read 3 Nov 2026).
--
-- Order: deploy send_outbox BEFORE this applies. The new send_outbox sends a to_role 'supplier' inbound_reply on the
-- Resend route exactly as the old one sent a to_role NULL one; the old send_outbox would read the new role as supplier
-- mail (Reply-To suppliers@mail.quotesdone.com, the supplier frame and footer).
-- CREATE OR REPLACE keeps both ACLs (fn_inbox_send: service_role only, measured); no revoke here on purpose.
-- prevented by: supabase/functions/send_outbox/m365_reply.test.ts and a_supplier_reply_goes_back_from_its_own_mailbox_probe.sql

create or replace function public.fn_inbox_send(p_id bigint, p_body text, p_by text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  m public.inbound_messages%rowtype;
  v_mailbox text; v_to text; v_known text; v_role text; v_lead bigint; v_kind text;
begin
  select * into m from public.inbound_messages where id=p_id;
  if m.id is null then return jsonb_build_object('error','message not found'); end if;
  if m.from_email is null then return jsonb_build_object('error','no sender address'); end if;
  if coalesce(trim(p_body),'')='' then return jsonb_build_object('error','empty reply'); end if;

  -- Which mailbox the message came into, and who wrote it.
  select lower(btrim(value)) into v_mailbox from public.app_secrets where key = 'invite_m365_mailbox';
  v_mailbox := coalesce(nullif(v_mailbox, ''), 'supplier@quotesdone.com');
  v_to := lower(btrim(coalesce(substring(m.to_email from '<([^>]+)>'), m.to_email, '')));
  v_known := public.fn_mail_sender_known(m.from_email);
  if coalesce(v_known, '') not in ('staff', 'customer')
     and (m.lead_id is not null or v_known = 'supplier' or v_to = v_mailbox) then
    v_role := 'supplier';
    v_lead := coalesce(m.lead_id, (select l.id from public.leads l
                                     where lower(btrim(l.email)) = lower(btrim(m.from_email))
                                        or lower(btrim(l.claimed_by)) = lower(btrim(m.from_email))
                                     order by l.id limit 1));
    if v_to = v_mailbox then v_kind := 'supplier_mailbox_reply'; end if;
  end if;

  insert into public.notifications(type,to_email,to_role,lead_id,kind,channel,subject,body,in_reply_to)
    values('inbound_reply', m.from_email, v_role, v_lead, v_kind, 'email',
           case when coalesce(m.subject,'') ilike 're:%' then m.subject else 'Re: '||coalesce(nullif(m.subject,''),'your message') end,
           p_body, nullif(btrim(m.raw->>'message_id'), ''));

  update public.inbound_messages set replied_at=now(), replied_by=coalesce(p_by,'founder'), needs_review=false where id=p_id;
  update public.agent_actions set status='approved', decided_by=coalesce(p_by,'founder'), decided_at=now()
   where target_table='inbound_messages' and target_id=p_id::text
     and status in ('pending','held_for_review','proposed','open');
  return jsonb_build_object('ok',true, 'to', m.from_email, 'to_role', v_role, 'lead_id', v_lead);
end $function$;

create or replace function public.fn_wa_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_dest text; v_opt text;
begin
  -- only fan out plain email rows; never recurse on whatsapp rows
  if coalesce(new.channel, 'email') <> 'email' or new.to_email is null or coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  -- a reply answers on the channel the message came in on (3 Nov 2026, sales_engineer): never twinned
  if new.type = 'inbound_reply' then return new; end if;
  v_dest := public.fn_whatsapp_destination(new.to_role, null, new.lead_id, new.to_email);
  if v_dest is null then
    if new.to_role = 'customer' then
      select c.whatsapp_opt into v_opt from public.customers c where lower(c.email) = lower(new.to_email) limit 1;
    else
      select l.whatsapp_opt into v_opt from public.leads l where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(new.to_email)) order by l.id limit 1;
    end if;
    -- 'none' is recorded (a03 marks the twin skipped with the reason); unanswered makes no twin.
    if v_opt is distinct from 'none' then return new; end if;
  end if;
  insert into public.notifications (type, to_email, to_role, to_phone, lead_id, inquiry_id, quote_id, subject, body, channel, status)
  values (new.type, new.to_email, new.to_role, v_dest, new.lead_id, new.inquiry_id, new.quote_id, new.subject, new.body, 'whatsapp', 'queued');
  return new;
end $function$;
