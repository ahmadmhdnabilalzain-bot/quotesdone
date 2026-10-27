-- AN AUTOMATIC REPLY NEVER TAKES AN INVITED SUPPLIER'S HANDOFF.
-- Seat: marketing. 27 Oct 2026, review of #1614.
--
-- fn_seat_handoff files ONE invite.reply per lead (target_id 'invite.reply:<lead id>'): a second reply is merged into
-- the first. So the first message has to be the supplier's own. Measured 27 Oct 2026 in supplier@quotesdone.com:
-- the two newest replies to an invitation were BOTH machine answers (a help-desk "We have received your email and
-- ... within the next 24 hours", 15 Aug; a ticket acknowledgement "a ticket ID 2871669 has been created", 14 Aug).
-- #1614 skipped only an RFC 3834 Auto-Submitted header. fn_inbound_is_auto_reply now also reads:
--   - X-Auto-Response-Suppress, Precedence (auto_reply/bulk/junk/list) and X-Autoreply/X-Autorespond, which
--     resend_inbound stores in inbound_messages.raw from this PR on;
--   - the subject ("Automatic reply:", "Out of Office", "Auto-Reply", "Undeliverable", "Delivery Status Notification");
--   - the opening of the body, for STRONG machine phrases only (a ticket number, "we have received your email and",
--     "this is an automated message", out-of-office). "Thank you for your email" alone is a person and is NOT matched.
-- An automatic reply files nothing, so the lead's handoff stays free for the supplier's real answer.
--
-- Prevented by: the verdict row below (each pattern and its near-miss), and
-- scripts/checks/the_supplier_invitation_carries_no_link.test.mjs (the filer calls fn_inbound_is_auto_reply).

create or replace function public.fn_inbound_is_auto_reply(p_subject text, p_body text, p_raw jsonb)
returns boolean
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select lower(coalesce(p_raw->>'auto_submitted', 'no')) not in ('', 'no')
      or btrim(coalesce(p_raw->>'x_auto_response_suppress', '')) <> ''
      or lower(btrim(coalesce(p_raw->>'precedence', ''))) in ('auto_reply', 'bulk', 'junk', 'list')
      or btrim(coalesce(p_raw->>'x_autoreply', '')) <> ''
      or coalesce(p_subject, '') ~* '(automatic reply|auto[- ]?reply|autoreply|out of (the )?office|\mooo\M|undeliverable|delivery status notification|r[ée]ponse automatique)'
      or left(coalesce(p_body, ''), 600) ~* '(ticket\s*(id|number|no\.?|#)|this is an auto(mated|matic) (reply|response|message|email)|we have received your (e-?mail|message|request|enquiry|inquiry) and|out of (the )?office|i am (currently )?(away|out of the office|on (annual )?leave)|do not reply to this (e-?mail|message))'
$fn$;
revoke execute on function public.fn_inbound_is_auto_reply(text, text, jsonb) from public, anon, authenticated;

create or replace function public.fn_marketing_files_invite_reply(p_inbound_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages; l public.leads;
  v_from text; v_boxes text[]; v_first text; v_reply text; v_id bigint;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then return jsonb_build_object('due', false, 'reason', 'no such inbound message'); end if;
  v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  select array_agg(lower(btrim(value))) into v_boxes from public.app_secrets
   where key in ('invite_m365_mailbox', 'email_reply_supplier') and btrim(coalesce(value, '')) <> '';
  if v_boxes is null or not exists (select 1 from unnest(v_boxes) b where position(b in lower(coalesce(m.to_email, ''))) > 0) then
    return jsonb_build_object('due', false, 'reason', 'not addressed to the invitation mailbox');
  end if;
  select * into l from public.leads x
   where (m.lead_id is not null and x.id = m.lead_id) or (m.lead_id is null and lower(btrim(x.email)) = v_from)
   order by x.id limit 1;
  if l.id is null then return jsonb_build_object('due', false, 'reason', 'the sender is no lead'); end if;
  if l.invited_at is null and l.invite_status is null then return jsonb_build_object('due', false, 'reason', 'the lead was never invited'); end if;
  if coalesce(l.claimed, false) then return jsonb_build_object('due', false, 'reason', 'the lead already has its company page'); end if;
  -- 27 Oct 2026: an out-of-office or help-desk acknowledgement never takes the lead's one handoff
  if public.fn_inbound_is_auto_reply(m.subject, m.body, m.raw) then return jsonb_build_object('due', false, 'reason', 'an automatic reply'); end if;
  -- the supplier's own words: everything above the quoted original
  -- (CRLF folded first: a Graph text body ends its lines with \r, measured 27 Oct 2026 end to end)
  v_reply := btrim(regexp_replace(replace(coalesce(m.body, ''), E'\r', ''), E'(\\n|^)\\s*(>|On [^\\n]{0,200}wrote:|-{2,}\\s*Original Message|From:\\s).*$', ''));
  v_first := lower(btrim(regexp_replace(split_part(v_reply, E'\n', 1), '[[:punct:][:space:]]+', ' ', 'g')));
  -- "stop" is an unsubscribe (resend_inbound), never a request for a page
  if v_first in ('stop', 'unsubscribe', 'stopall', 'end', 'cancel', 'opt out', 'optout', 'remove', 'remove me', 'please remove', 'not interested') then
    return jsonb_build_object('due', false, 'reason', 'a stop reply (handled as an unsubscribe)');
  end if;
  if v_reply = '' then return jsonb_build_object('due', false, 'reason', 'an empty reply'); end if;

  v_id := public.fn_seat_handoff('marketing', 'sales_engineer', 'invite.reply', 'leads', l.id::text,
    jsonb_build_object('lead_id', l.id, 'company_name', l.company_name, 'from_email', v_from,
                       'inbound_message_id', m.id, 'reply_text', left(v_reply, 4000),
                       'ask', 'Set up the company page for this supplier from the trades it listed in its reply.'));
  -- null = a demo lead (ruling 1199: a demo row files no handoff)
  return jsonb_build_object('due', true, 'reason', 'an invited supplier replied', 'lead_id', l.id, 'reply_text', left(v_reply, 4000), 'handoff_id', v_id);
end $fn$;

-- verdict: each machine mark is caught, and a person's reply that merely thanks us is not
select case
  when not public.fn_inbound_is_auto_reply('Re: Quote requests', 'x', '{"auto_submitted":"auto-replied"}') then 'PROBE FAILED: Auto-Submitted'
  when not public.fn_inbound_is_auto_reply('Re: Quote requests', 'x', '{"x_auto_response_suppress":"All"}') then 'PROBE FAILED: X-Auto-Response-Suppress'
  when not public.fn_inbound_is_auto_reply('Re: Quote requests', 'x', '{"precedence":"auto_reply"}') then 'PROBE FAILED: Precedence'
  when not public.fn_inbound_is_auto_reply('Automatic reply: Quote requests for X', 'x', '{}') then 'PROBE FAILED: Automatic reply subject'
  when not public.fn_inbound_is_auto_reply('Out of Office: Quote requests', 'x', '{}') then 'PROBE FAILED: Out of Office subject'
  when not public.fn_inbound_is_auto_reply('Re: Invitation', E'Dear Valued Customer,\r\n\r\nThank you for contacting us. We have received your email and would like to assure you that it is currently being reviewed', '{}') then 'PROBE FAILED: help-desk acknowledgement (15 Aug)'
  when not public.fn_inbound_is_auto_reply('Invitation', 'Dear Supplier, Thank you for contacting Lulu Customer care. We would like to acknowledge that we have received your request and a ticket ID 2871669 has been created', '{}') then 'PROBE FAILED: ticket acknowledgement (14 Aug)'
  when public.fn_inbound_is_auto_reply('Re: Tiling quote requests for X', E'Thank you for your email. We cover tiling and waterproofing.\n\nOn Tue, Ahmad wrote:\n> Hi', '{"auto_submitted":"no"}') then 'PROBE FAILED: a person''s reply was taken for a machine'
  when public.fn_inbound_is_auto_reply('Re: Quote requests', 'We do MEP and HVAC. Please set up our page.', null) then 'PROBE FAILED: a plain reply was taken for a machine'
  else 'PROBE OK' end as verdict;
