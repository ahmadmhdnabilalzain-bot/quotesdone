-- A CUSTOMER'S E-MAIL IS ANSWERED, IN ITS OWN THREAD, WITHIN THE MINUTE. Seat: customer_support. 28 Sep 2026.
--
-- The founder: a real customer e-mail got no answer. His rules: a customer gets a reply in under a minute, and
-- no person is brought in unless the customer explicitly asks for one.
--
-- MEASURED BEFORE THIS FILE (28 Sep 2026, production):
--   * app_secrets held no email_triage_enabled row, so fn_resilience_orphan_steps_due never opened the
--     email_triage step (four_live_functions_had_no_clock...sql shipped it absent on purpose);
--   * resend_inbound stored plain correspondence with needs_review = false, and email_triage selects
--     needs_review = true, so even with the flag on a customer's question was never read;
--   * email_triage only drafted: every draft became a pending inbound_review for a person to send.
-- The edge functions carry the rest (email_triage answers, resend_inbound wakes it for the one message,
-- send_outbox threads the reply). This file carries what the database owns:
--
--   1. notifications.in_reply_to - the inbound Message-ID the reply answers. send_outbox sends it as
--      In-Reply-To and References, so the reply lands in the customer's own thread.
--   2. fn_inbox_send - the Inbox's one send, now used by customer_support too: it threads the reply from
--      inbound_messages.raw->>'message_id'. search_path moves from (public, pg_catalog) to the estate's
--      (public, pg_temp). No canonical file owned it before; this one does.
--   3. fn_glm_judgement_resolve / _defer - an unknown sender's mail is now answered at once, so GLM's later
--      category must not file a "review and reply" item for a mail that was already replied to. That item
--      was a person brought in without the customer asking. Unchanged otherwise (copied from
--      four_judgements_move_to_glm_and_wait_in_a_queue_while_the_model_is_off.sql).
--   4. internal_credential scope: resend_inbound may wake email_triage, and email_triage may wake send_outbox.
--   5. email_triage_enabled = 'true': the 15-minute backstop tick runs. The value is written, never read here.

alter table public.notifications add column if not exists in_reply_to text;
comment on column public.notifications.in_reply_to is 'The Message-ID of the inbound e-mail this answers; send_outbox sends it as In-Reply-To and References so the reply threads (customer_support, 28 Sep 2026).';

create or replace function public.fn_inbox_send(p_id bigint, p_body text, p_by text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages%rowtype;
begin
  select * into m from public.inbound_messages where id=p_id;
  if m.id is null then return jsonb_build_object('error','message not found'); end if;
  if m.from_email is null then return jsonb_build_object('error','no sender address'); end if;
  if coalesce(trim(p_body),'')='' then return jsonb_build_object('error','empty reply'); end if;

  insert into public.notifications(type,to_email,to_role,channel,subject,body,in_reply_to)
    values('inbound_reply', m.from_email, null, 'email',
           case when coalesce(m.subject,'') ilike 're:%' then m.subject else 'Re: '||coalesce(nullif(m.subject,''),'your message') end,
           p_body, nullif(btrim(m.raw->>'message_id'), ''));

  update public.inbound_messages set replied_at=now(), replied_by=coalesce(p_by,'founder'), needs_review=false where id=p_id;
  update public.agent_actions set status='approved', decided_by=coalesce(p_by,'founder'), decided_at=now()
   where target_table='inbound_messages' and target_id=p_id::text
     and status in ('pending','held_for_review','proposed','open');
  return jsonb_build_object('ok',true, 'to', m.from_email);
end $fn$;
revoke execute on function public.fn_inbox_send(bigint, text, text) from public, anon, authenticated;
grant execute on function public.fn_inbox_send(bigint, text, text) to service_role;

-- Not judged this time. p_counts = a failed reading (counts toward the three); the model hold does not.
create or replace function public.fn_glm_judgement_defer(p_id bigint, p_error text, p_counts boolean)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare g public.glm_judgement;
begin
  update public.glm_judgement
     set leased_until = null, last_error = left(p_error, 500),
         attempts = attempts + case when p_counts then 1 else 0 end,
         status = case when p_counts and attempts + 1 >= 3 then 'failed' else status end,
         decided_at = case when p_counts and attempts + 1 >= 3 then now() else decided_at end
   where id = p_id and status = 'queued'
  returning * into g;
  if g.id is null or g.status <> 'failed' then return; end if;
  -- THE TERMINAL STATE HANDS EACH KIND BACK TO ITS OWNER (review of this PR): three failed readings never leave
  -- anything waiting on a judgement that will not come.
  if g.kind = 'unknown_sender_mail' then
    -- The mail leaves the 'glm_queued' mark (which email_triage skips) and goes to a person's review, unread.
    update public.inbound_messages set ai_category = 'other', ai_summary = 'Not read: GLM could not judge this mail after 3 tries.', triaged_at = now()
     where id = (g.input->>'message_id')::bigint and triaged_at is null;
    -- 28 Sep 2026: not when customer_support already answered it (the founder: no person unless asked for).
    if not exists (select 1 from public.inbound_messages where id = (g.input->>'message_id')::bigint and replied_at is not null) then
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
    values ('email', 'inbound_review', 'pending', 'low',
            left('Inbox (unknown sender, unread): ' || coalesce(g.input->>'subject', '(no subject)'), 70),
            'GLM could not read this mail from an unknown sender after 3 tries. Read it and reply from the Inbox.',
            'inbound_messages', g.input->>'message_id',
            jsonb_build_object('from', g.input->>'from', 'glm_judgement_id', g.id, 'last_error', g.last_error));
    end if;
  elsif g.kind = 'supplier_trade_words' then
    -- The proposal stays pending for the sales engineer (as before this PR), now saying why it was not offered.
    update public.taxonomy_trade_proposal set note = coalesce(note || ' ', '') || '[GLM could not map these words after 3 tries; decide by hand.]'
     where id = (g.input->>'proposal_id')::bigint and status = 'pending';
  end if;
  -- repeat_request: the inquiry simply stays unflagged (exactly its state before this PR; a flag only marks review).
  -- quote_spec_match: fn_quote_spec_mismatches reports the cells as 'unread', never as meeting the request.
end $fn$;
revoke execute on function public.fn_glm_judgement_defer(bigint, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_glm_judgement_defer(bigint, text, boolean) to service_role;

-- The answer and its one effect, in one transaction.
create or replace function public.fn_glm_judgement_resolve(p_id bigint, p_result jsonb, p_model text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare g public.glm_judgement; v_effect text := 'recorded'; v_codes text[]; v_n integer;
begin
  update public.glm_judgement set status = 'done', result = p_result, model = p_model, decided_at = now(), leased_until = null
   where id = p_id and status = 'queued' returning * into g;
  if g.id is null then return jsonb_build_object('ok', false, 'reason', 'not_queued'); end if;

  if g.kind = 'repeat_request' and p_result->>'verdict' = 'same' then
    update public.inquiries
       set plausibility = coalesce(plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true,
             'duplicate_of', g.input->>'earlier_id', 'duplicate_by', 'glm', 'glm_judgement_id', g.id)
     where id::text = g.input->>'inquiry_id'
       and not coalesce((plausibility->>'possible_duplicate')::boolean, false);
    v_effect := 'inquiry_flagged';

  elsif g.kind = 'supplier_trade_words' then
    -- Exact codes only: a code the taxonomy does not hold is never written (the caller already refused it; this
    -- is the second door).
    select array_agg(c) into v_codes from jsonb_array_elements_text(coalesce(p_result->'codes', '[]'::jsonb)) c
     where exists (select 1 from public.taxonomy_trade t where t.code = c and t.active);
    v_n := coalesce(array_length(v_codes, 1), 0);
    if v_n = 1 then
      update public.taxonomy_trade_proposal
         set status = 'map_offered', mapped_to = v_codes[1], decided_at = now(), decided_by = 'sales_engineer:glm',
             note = 'Offered to the supplier to confirm: ' || v_codes[1] || '. ' || coalesce(p_result->>'why', '')
       where id = (g.input->>'proposal_id')::bigint and status = 'pending';
      v_effect := 'map_offered';
    else
      update public.taxonomy_trade_proposal
         set note = case when v_n > 1
                      then 'Names several exact trades (' || array_to_string(v_codes, ', ') || '). Ask the supplier: '
                      else 'Names no exact taxonomy trade. Ask the supplier: ' end
                    || coalesce(nullif(p_result->>'ask', ''), 'which of our trades is this work?')
       where id = (g.input->>'proposal_id')::bigint and status = 'pending';
      v_effect := case when v_n > 1 then 'ask_several' else 'ask_none' end;
    end if;

  elsif g.kind = 'unknown_sender_mail' then
    update public.inbound_messages
       set ai_category = left(coalesce(p_result->>'category', 'other'), 40), ai_summary = left(p_result->>'summary', 500),
           triaged_at = now()
     where id = (g.input->>'message_id')::bigint and triaged_at is null;
    -- The same review item email_triage files for a drafted mail, so customer_support sees it; spam files nothing.
    -- 28 Sep 2026: nor a mail customer_support already answered (the founder: no person unless asked for).
    if coalesce(p_result->>'category', 'other') <> 'spam'
       and not exists (select 1 from public.inbound_messages where id = (g.input->>'message_id')::bigint and replied_at is not null) then
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
      values ('email', 'inbound_review', 'pending', 'low',
              left('Inbox (unknown sender): ' || coalesce(g.input->>'subject', '(no subject)'), 70) || ' - ' || coalesce(p_result->>'category', 'other'),
              'Unknown sender, read by GLM. Review and reply from the Inbox.', 'inbound_messages', g.input->>'message_id',
              jsonb_build_object('from', g.input->>'from', 'category', p_result->>'category', 'summary', p_result->>'summary', 'glm_judgement_id', g.id));
    end if;
    v_effect := 'mail_triaged';
  end if;
  return jsonb_build_object('ok', true, 'effect', v_effect);
end $fn$;
revoke execute on function public.fn_glm_judgement_resolve(bigint, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_glm_judgement_resolve(bigint, jsonb, text) to service_role;

update public.internal_credential set scope = array_append(scope, 'email_triage')
 where context = 'fn.resend_inbound' and not (scope @> array['email_triage']);
update public.internal_credential set scope = array_append(scope, 'send_outbox')
 where context = 'fn.email_triage' and not (scope @> array['send_outbox']);

insert into public.app_secrets (key, value) values ('email_triage_enabled', 'true')
on conflict (key) do update set value = excluded.value;

-- VERDICT (this file defines things, so it cleans up nothing and raises nothing: it reads what it set).
select case
  when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'notifications' and column_name = 'in_reply_to')
    then 'PROBE FAILED: notifications.in_reply_to missing'
  when position('in_reply_to' in pg_get_functiondef('public.fn_inbox_send(bigint,text,text)'::regprocedure)) = 0
    then 'PROBE FAILED: fn_inbox_send does not thread'
  when not exists (select 1 from public.app_secrets where key = 'email_triage_enabled' and value = 'true')
    then 'PROBE FAILED: email_triage_enabled is not on'
  when not exists (select 1 from public.internal_credential where context = 'fn.resend_inbound' and scope @> array['email_triage'])
    or not exists (select 1 from public.internal_credential where context = 'fn.email_triage' and scope @> array['send_outbox'])
    then 'PROBE FAILED: a credential scope is missing'
  else 'PROBE OK' end as verdict;
