-- THE MARKETING SEAT ANSWERS PUBLIC COMMENTS ON EVERY CHANNEL SYNCED IN POSTIZ, AND NO PERSON APPROVES A REPLY.
--
-- Assigned: marketing (the two handoff kinds are received by customer_support and sales_engineer).
-- Founder, instruction 866, 23 Sep 2026: "the marketing agent need to be able to reply to the comments as
-- well. If someone said something, he should be able to reply … that applies to all the platforms on social
-- media." Same day: "I don't want to be approving every comment … Otherwise, this is not automation."
--
-- MEASURED, read-only against htdblwldjkcgjvmqkbeh, 23 Sep 2026:
--   social_message 0 rows, social_conversation 0 rows — nothing has ever been read or answered;
--   no cron job names the inbox; app_secrets holds meta_app_secret, meta_access_token, meta_webhook_verify_token,
--   meta_app_id, postiz_api_key, social_send_enabled = 'off', social_model_enabled = 'off', and NO X, YouTube
--   or LinkedIn credential; the platform checks on both tables admit only 'instagram' and 'facebook'.
--   Postiz's public API (docs.postiz.com/llms.txt) has no endpoint that reads or answers a comment.
--
-- WHAT THIS CHANGES (read by supabase/functions/_shared/marketing_social_comments.ts and _store.ts):
--   1. youtube is a platform the inbox can hold (through the founder's Postiz connection). X is NOT: the founder
--      ruled on 23 Sep 2026 that there is no paid X API, and nothing reads or answers X.
--   2. every comment row carries its classification, who decided the reply (rule / model / guard_fallback),
--      the guard failures of a rejected model draft, and the handoff it raised — the audit the founder and the
--      month-end review read. send_status gains the outcomes that send nothing: held_model (the model is held:
--      "held, not run"), rate_limited, not_sent, hidden.
--   3. two seat conversations, CLOSED BY MARKETING (originator_closes) once the receiving seat has answered: social.escalation (marketing -> customer_support: a complaint, a dispute, a
--      legal threat, a request for a person, or a model draft that failed its guards) and social.lead
--      (marketing -> sales_engineer: a customer or a supplier asking to work with us). Both wait in the
--      receiving seat's inbox (fn_agent_handoff_inbox) for that seat to answer the commenter privately.
--   4. the fixed public comment replies, EN + native Gulf Arabic. Every figure is published: the first 1,000
--      suppliers free permanently, AED 1,000 a year from the 1,001st registration (portal copy, supplier
--      agreement v12). ON CONFLICT DO NOTHING: the seat's later edits are never walked over.
-- Nothing here switches anything on. social_send_enabled stays the emergency stop, and stays 'off'.

alter table public.social_conversation drop constraint if exists social_conversation_platform_check;
alter table public.social_conversation add constraint social_conversation_platform_check
  check (platform in ('instagram', 'facebook', 'youtube'));
alter table public.social_message drop constraint if exists social_message_platform_check;
alter table public.social_message add constraint social_message_platform_check
  check (platform in ('instagram', 'facebook', 'youtube'));

alter table public.social_message
  add column if not exists classification text,
  add column if not exists decided_by     text,
  add column if not exists guard_failures text[] not null default '{}',
  add column if not exists handoff_id     bigint;
alter table public.social_message drop constraint if exists social_message_classification_check;
alter table public.social_message add constraint social_message_classification_check check (classification in
  ('question', 'praise', 'complaint', 'spam_abuse', 'sales_lead', 'supplier_enquiry', 'sensitive_legal', 'off_topic'));
alter table public.social_message drop constraint if exists social_message_decided_by_check;
alter table public.social_message add constraint social_message_decided_by_check check (decided_by in ('rule', 'model', 'guard_fallback'));
alter table public.social_message drop constraint if exists social_message_send_status_check;
alter table public.social_message add constraint social_message_send_status_check check (send_status in
  ('pending', 'held_switch_off', 'held_fixture', 'sent', 'failed', 'held_model', 'rate_limited', 'not_sent', 'hidden'));
alter table public.social_message drop constraint if exists social_message_reply_kind_check;
alter table public.social_message add constraint social_message_reply_kind_check check (reply_kind in
  ('handoff', 'standard', 'faq', 'knowledge', 'unknown', 'model', 'escalated'));

-- The receiving seat's handler: the handoff waits for that seat to answer the commenter privately.
create or replace function public.fn_marketing_social_handoff_waits(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('waiting', coalesce(a.detail ->> 'waiting_for', a.agent || ' to answer the commenter privately'))
    from public.agent_actions a where a.id = p_id
$fn$;
revoke all on function public.fn_marketing_social_handoff_waits(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('social.escalation', 'marketing', 'customer_support',
   'a public comment that must not be answered in public (complaint, dispute, legal, identity, a request for a person, or a model draft that failed its guards)',
   'fn_marketing_social_handoff_waits', interval '24 hours', true, 'scripts/sql/the_marketing_seat_answers_comments_on_every_channel.sql'),
  ('social.lead', 'marketing', 'sales_engineer',
   'a public comment from a customer asking for quotes or a supplier asking to join',
   'fn_marketing_social_handoff_waits', interval '24 hours', true, 'scripts/sql/the_marketing_seat_answers_comments_on_every_channel.sql')
on conflict (type, from_seat, to_seat) do update set originator_closes = excluded.originator_closes, handler = excluded.handler,
  meaning = excluded.meaning, reply_within = excluded.reply_within, owner_file = excluded.owner_file;

-- THE RECEIVING SEAT ANSWERS: it has written to the commenter privately (or reviewed a hide). p_unhide asks
-- marketing to restore a comment that was hidden and was not abuse. Only the addressed seat may answer.
create or replace function public.fn_marketing_social_handoff_answered(p_id bigint, p_seat text, p_note text, p_unhide boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions
   where id = p_id and kind = 'handoff' and status = 'pending' and detail->>'type' in ('social.escalation', 'social.lead') for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no pending social handoff ' || p_id); end if;
  if a.agent is distinct from p_seat then
    return jsonb_build_object('ok', false, 'reason', 'handoff ' || p_id || ' is addressed to ' || a.agent || ', not ' || coalesce(p_seat, 'nobody'));
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('ok', false, 'reason', 'an answer needs a note of what was done'); end if;
  update public.agent_actions
     set detail = detail || jsonb_build_object('answered_at', now(), 'answered_by', p_seat, 'answer', left(p_note, 1000))
                         || case when p_unhide then jsonb_build_object('unhide', true) else '{}'::jsonb end
   where id = p_id;
  return jsonb_build_object('ok', true, 'handoff_id', p_id);
end $fn$;
revoke all on function public.fn_marketing_social_handoff_answered(bigint, text, text, boolean) from public, anon, authenticated;

-- THE ORIGINATOR RE-CHECKS AND CLOSES (marketing duty social_comments, every 30 minutes): a social handoff closes
-- when the receiving seat has answered and, if it asked for the comment back, the comment has been un-hidden.
create or replace function public.fn_marketing_social_handoffs_close()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h record; n_closed int := 0; n_waiting int := 0;
begin
  for h in select a.id, a.detail from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'from' = 'marketing'
              and a.detail->>'type' in ('social.escalation', 'social.lead')
  loop
    if h.detail ? 'answered_at' and (coalesce((h.detail->>'unhide')::boolean, false) = false or h.detail ? 'unhidden_at') then
      perform set_config('qd.handoff_closer', 'marketing', true);
      perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'marketing', 'verified_at', now(),
        'answer', h.detail->>'answer', 'answered_by', h.detail->>'answered_by', 'unhidden_at', h.detail->>'unhidden_at'));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    else
      n_waiting := n_waiting + 1;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'waiting', n_waiting);
end $fn$;
revoke all on function public.fn_marketing_social_handoffs_close() from public, anon, authenticated;

insert into public.social_reply_library (key, priority, match_words, reply_en, reply_ar, updated_by) values
('comment_praise', null, '{}',
 'Thank you, we truly appreciate it. If you have a job that needs quotes, you can post it at https://quotesdone.com',
 'شكرًا جزيلًا، نقدّر كلماتكم الطيبة. وإن كان لديكم عمل تحتاجون فيه إلى عروض أسعار، فيمكنكم نشر طلبكم عبر:
https://quotesdone.com',
 'marketing'),
('comment_escalated_ack', null, '{}',
 'Thank you for letting us know. We have passed this to our team; please send us a direct message so we can look into it with you privately.',
 'شكرًا لإبلاغنا. أحلنا الموضوع إلى فريقنا، ونرجو مراسلتنا برسالة خاصة لنتابعه معكم مباشرةً.',
 'marketing'),
('comment_lead', null, '{}',
 'Thank you! Describe the job once at https://quotesdone.com and verified UAE suppliers in that trade send you quotes to compare, while your identity stays hidden.',
 'شكرًا لكم. صفوا العمل مرة واحدة عبر موقعنا، ويرسل إليكم موردون معتمدون في الإمارات متخصصون في المجال نفسه عروضهم لتقارنوا بينها، مع بقاء هويتكم محجوبة:
https://quotesdone.com',
 'marketing'),
('comment_supplier', null, '{}',
 'Suppliers register at https://quotesdone.com/portal with a valid UAE trade licence. It is free permanently for the first 1,000 suppliers; from the 1,001st registration the fee is AED 1,000 a year. No commission on jobs you win.',
 'يسجّل الموردون عبر موقعنا برخصة تجارية سارية في الإمارات:
https://quotesdone.com/portal
والتسجيل مجاني بصفة دائمة لأول 1,000 مورد، وتُطبَّق رسوم سنوية قدرها 1,000 درهم اعتبارًا من التسجيل رقم 1,001. ولا نتقاضى أي عمولة على الأعمال التي تفوزون بها.',
 'marketing')
on conflict (key) do nothing;
