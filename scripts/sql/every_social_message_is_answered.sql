-- EVERY INSTAGRAM AND FACEBOOK MESSAGE IS ANSWERED, KEPT, AND HANDED TO THE FOUNDER WHEN A PERSON IS ASKED FOR.
--
-- Assigned: marketing. 22 Sep 2026. Founder: "if there was any communication on Instagram or any
-- social media platform, there should be an automated reply in which he [the marketing seat] is aware
-- of and he carries on. We will have some standard replies, automatic, and then the agent needs to be
-- able to carry on with the conversation. Only if a customer is asking 'I want to speak with an
-- agent', that's where I get a notification on my email, and I'll carry on. He should be wired to the
-- company knowledge. He knows everything."
--
-- MEASURED, read-only against htdblwldjkcgjvmqkbeh, 22 Sep 2026: no table, routine or edge function
-- receives Meta webhooks (no X-Hub-Signature-256 or hub.challenge handling anywhere in
-- supabase/functions); public.social_posts holds outgoing posts only. So a DM or comment on our
-- Instagram or Facebook Page today reaches nobody and is kept nowhere.
--
-- WHAT THIS CHANGES (read by the edge function supabase/functions/marketing_social_inbox):
--   1. social_conversation — one per person per platform, owner_seat 'marketing', status 'auto' (the seat
--      answers) or 'handed_to_human' (the seat is silent until the founder hands it back).
--   2. social_message — every inbound message/comment and every reply, in and out, kept forever (the
--      founder's 14 Sep ruling: conversations are never purged; only a fixture row may be deleted).
--      unique (platform, meta_message_id) is the webhook's idempotency key.
--   3. social_reply_library — the standard replies, EN + native Gulf Arabic, which the founder edits.
--      A row with a priority and match_words is matched on whole words; human_handoff, unknown and
--      knowledge_suffix are chosen by the code. Seeded with ON CONFLICT DO NOTHING so a re-apply never
--      overwrites the founder's edits.
--   4. fn_marketing_social_hand_to_human(conversation, reason): marks it handed_to_human and emails the founder
--      through fn_notify_founder(p_kind => 'social_human_request') with the platform, handle, the last
--      messages and where to continue. Only the transition notifies; a repeat ask does not re-email.
--   5. fn_marketing_social_set_status(conversation, status, by): the founder's word hands it back
--      ('auto') — from the OS or his command channel; an echo from the Meta inbox hands it to him.
--   6. v_marketing_social_volume — the counts the CEO's marketing report reads, fixtures excluded.
--
-- WHAT THIS DOES NOT CHANGE. It does not register the seat 'marketing', the founder mail kind
-- 'social_human_request' (until that row exists fn_notify_founder ROUTES the notice to an org_task
-- instead of emailing it), function_owner for marketing_social_inbox, or llm_seat_binding — those belong to
-- the_marketing_seat_exists (branch ceo/the-marketing-seat-exists). It does not add social_message to
-- v_conversation_message; the sales engineer reads the table directly until that view's owner does.
-- It sends nothing: the edge function sends only when app_secrets.social_send_enabled = 'on'.
--
--   node scripts/apply_sql.mjs scripts/sql/every_social_message_is_answered.sql --apply --ddl

-- ── 1. THE CONVERSATION ──────────────────────────────────────────────────────────────────────────
create table if not exists public.social_conversation (
  id               bigint generated always as identity primary key,
  platform         text not null check (platform in ('instagram', 'facebook')),
  user_id          text not null,                      -- IGSID / PSID / commenter id, as Meta sends it
  account_id       text,                               -- our Page / Instagram account id
  handle           text,
  owner_seat       text not null default 'marketing',
  status           text not null default 'auto' check (status in ('auto', 'handed_to_human')),
  handed_at        timestamptz,
  handed_reason    text,
  handoff_count    int not null default 0,
  resumed_at       timestamptz,
  resumed_by       text,
  last_inbound_at  timestamptz,
  is_demo          boolean generated always as (user_id ~* '^ZZDEMO' or coalesce(handle, '') ~* '^ZZ DEMO') stored,
  created_at       timestamptz not null default now(),
  unique (platform, user_id)
);
alter table public.social_conversation enable row level security;
drop policy if exists social_conversation_service_role_only on public.social_conversation;
create policy social_conversation_service_role_only on public.social_conversation
  as permissive for all to public using (false) with check (false);
revoke all on public.social_conversation from anon, authenticated;

-- ── 2. EVERY MESSAGE, BOTH WAYS ──────────────────────────────────────────────────────────────────
create table if not exists public.social_message (
  id               bigint generated always as identity primary key,
  conversation_id  bigint not null references public.social_conversation(id),
  platform         text not null check (platform in ('instagram', 'facebook')),
  channel          text not null check (channel in ('dm', 'comment')),
  direction        text not null check (direction in ('in', 'out')),
  author           text not null check (author in ('person', 'seat', 'human')),
  meta_message_id  text,                               -- mid / comment id; null until a reply is sent
  parent_id        text,                               -- the post or media a comment is on
  in_reply_to      bigint references public.social_message(id),
  body             text not null,
  reply_kind       text check (reply_kind in ('handoff', 'standard', 'faq', 'knowledge', 'unknown')),
  reply_key        text,
  send_status      text check (send_status in ('pending', 'held_switch_off', 'held_fixture', 'sent', 'failed')),
  send_error       text,
  sent_at          timestamptz,
  outcome          text,                               -- on an inbound row: what the seat did with it
  occurred_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  unique (platform, meta_message_id)
);
create index if not exists social_message_conversation_idx on public.social_message (conversation_id, created_at desc);
alter table public.social_message enable row level security;
drop policy if exists social_message_service_role_only on public.social_message;
create policy social_message_service_role_only on public.social_message
  as permissive for all to public using (false) with check (false);
revoke all on public.social_message from anon, authenticated;

-- ── 3. THE STANDARD REPLIES ──────────────────────────────────────────────────────────────────────
-- Every figure here is one the website already publishes (site_assistant FACTS and the approved FAQ):
-- free to post, 3% reveal fee plus card processing only on a reveal, refund if the supplier does not
-- respond, no supplier commission, verification up to 3 working days, the published contact line.
-- Supplier sign-up points to the website; it is not an invitation.
create table if not exists public.social_reply_library (
  key          text primary key,
  priority     int,                                    -- null: chosen by the code, never keyword-matched
  match_words  text[] not null default '{}',
  reply_en     text not null,
  reply_ar     text not null,
  active       boolean not null default true,
  updated_at   timestamptz not null default now(),
  updated_by   text
);
alter table public.social_reply_library enable row level security;
drop policy if exists social_reply_library_service_role_only on public.social_reply_library;
create policy social_reply_library_service_role_only on public.social_reply_library
  as permissive for all to public using (false) with check (false);
revoke all on public.social_reply_library from anon, authenticated;

insert into public.social_reply_library (key, priority, match_words, reply_en, reply_ar, updated_by) values
('pricing', 10,
 array['fee','fees','commission','is it free','for free','free to use','do you charge','how much do you charge','charges','pricing',
       'رسوم','عمولة','مجاني','مجانا','مجانية','تكلفة الخدمة','كم تاخذون','كم تأخذون'],
 'Posting a request and comparing quotes on QuotesDone is free. A 3% reveal fee, plus the card processing fee, applies only if you choose to reveal a supplier''s contact details; both are shown in full before you pay, and if the revealed supplier does not respond, everything you paid is refunded. Suppliers pay no commission. The price of the work itself comes from the suppliers'' quotes: post your request at https://quotesdone.com',
 'نشر الطلب ومقارنة العروض على QuotesDone مجاني. ولا تُستحق رسوم الكشف البالغة 3% مع رسوم معالجة البطاقة إلا إذا اخترتم كشف بيانات التواصل مع أحد الموردين، وتظهر الرسوم كاملةً قبل الدفع، وإن لم يتجاوب المورد بعد الكشف نُعيد إليكم كامل المبلغ. ولا يدفع الموردون أي عمولة. أما سعر العمل نفسه فيحدده الموردون في عروضهم، ويمكنكم نشر طلبكم عبر:
https://quotesdone.com',
 'marketing'),
('supplier_signup', 15,
 array['become a supplier','register as a supplier','join as a supplier','sign up as a supplier','i am a supplier','im a supplier','we are a supplier','we are suppliers','list my company','list our company','register my company','register our company','receive leads','get leads',
       'كمورد','التسجيل كمورد','انضم كمورد','تسجيل شركتي','تسجيل شركتنا','نحن موردين','انا مورد'],
 'Suppliers join by registering on our website with a valid UAE trade licence: https://quotesdone.com/portal. Verification takes up to 3 working days, and verified suppliers then receive customer requests that match their trade. There is no commission on the jobs you win.',
 'يمكن للموردين الانضمام بالتسجيل عبر موقعنا مع رخصة تجارية سارية في الإمارات:
https://quotesdone.com/portal
ويستغرق التحقق ما يصل إلى 3 أيام عمل، ثم تصلكم طلبات العملاء المطابقة لنشاطكم. ولا نتقاضى أي عمولة على الأعمال التي تفوزون بها.',
 'marketing'),
('how_it_works', 20,
 array['how does it work','how it works','how do you work','how does this work','what is quotesdone','what do you do','what does quotesdone do',
       'كيف تعمل','كيف يعمل','كيف تشتغلون','طريقة العمل','وش تسوون','ايش تسوون','ما هي خدمتكم'],
 'It works in three steps: describe the job once, by text, voice, photo or drawing; we send it anonymously to verified UAE suppliers in that trade; and you compare their quotes side by side. Your identity stays hidden until you choose to reveal a supplier. Start at https://quotesdone.com',
 'تتم العملية في ثلاث خطوات: تصفون العمل مرة واحدة كتابةً أو صوتًا أو بصورة أو مخطط، ثم نرسله دون الكشف عن هويتكم إلى موردين معتمدين في الإمارات متخصصين في المجال نفسه، ثم تقارنون عروضهم جنبًا إلى جنب. وتبقى هويتكم محجوبة حتى تختاروا كشف أحد الموردين. ابدؤوا من هنا:
https://quotesdone.com',
 'marketing'),
('contact', 30,
 array['contact','phone number','your number','email address','your email','call you','whatsapp number','reach you',
       'رقمكم','رقم التواصل','رقم الهاتف','رقم الجوال','الايميل','ايميلكم','البريد الالكتروني','كيف اتواصل معكم'],
 'You can reach our team on +971 50 931 9355 (call or WhatsApp, Sunday to Thursday, 9am to 6pm UAE time) or at management@quotesdone.com. If you would like a member of our team to continue this conversation here, just reply "agent".',
 'يمكنكم التواصل مع فريقنا اتصالًا أو عبر واتساب على:
+971 50 931 9355
(من الأحد إلى الخميس، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات)
أو عبر البريد الإلكتروني:
management@quotesdone.com
وإن رغبتم في أن يتابع أحد أعضاء فريقنا هذه المحادثة هنا، فاكتبوا «موظف».',
 'marketing'),
('hours', 40,
 array['opening hours','working hours','business hours','office hours','are you open','when are you open','what time do you open','timings',
       'ساعات العمل','اوقات العمل','أوقات العمل','مواعيد العمل','متى تفتحون','الدوام','دوامكم'],
 'Our team is available Sunday to Thursday, 9am to 6pm UAE time. You can post a request at https://quotesdone.com at any time, and messages here are answered straight away.',
 'فريقنا متاح من الأحد إلى الخميس، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات. ويمكنكم نشر طلبكم على موقعنا في أي وقت:
https://quotesdone.com
كما نرد على الرسائل هنا فور وصولها.',
 'marketing'),
('greeting', 90,
 array['hi','hello','hey','good morning','good afternoon','good evening','salam','assalamualaikum',
       'مرحبا','مرحبًا','السلام عليكم','اهلا','أهلا','هلا','صباح الخير','مساء الخير'],
 'Hello, and thank you for reaching out to QuotesDone. We help you get anonymous quotes from verified suppliers across the UAE: describe the job once and compare the offers side by side. How can we help you today?',
 'أهلًا بكم، وشكرًا لتواصلكم مع QuotesDone. نساعدكم في الحصول على عروض أسعار من موردين معتمدين في جميع أنحاء الإمارات دون الكشف عن هويتكم؛ تصفون العمل مرة واحدة، ثم تقارنون العروض جنبًا إلى جنب. كيف يمكننا خدمتكم اليوم؟',
 'marketing'),
('human_handoff', null, '{}',
 'Of course. I have passed this conversation to a member of our team, who will continue with you here as soon as possible (Sunday to Thursday, 9am to 6pm UAE time). Until then, no further automated replies will be sent in this conversation.',
 'بكل سرور. أحلنا محادثتكم إلى أحد أعضاء فريقنا، وسيتابع معكم هنا في أقرب وقت ممكن (من الأحد إلى الخميس، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات). ولن تصلكم ردود آلية أخرى في هذه المحادثة حتى ذلك الحين.',
 'marketing'),
('unknown', null, '{}',
 'I don''t have a confirmed answer to that, and I would rather not guess. I have recorded your question so it is answered properly. If you would like a member of our team to take this up now, reply "agent".',
 'لا تتوفر لديّ إجابة مؤكدة عن ذلك، ولا أودّ أن أجيبكم بالتخمين. سجّلنا سؤالكم ليُجاب عنه إجابة دقيقة، وإن رغبتم في أن يتابع أحد أعضاء فريقنا معكم الآن، فاكتبوا «موظف».',
 'marketing'),
('knowledge_suffix', null, '{}',
 'If you would like a member of our team to continue, reply "agent".',
 'وإن رغبتم في أن يتابع أحد أعضاء فريقنا معكم، فاكتبوا «موظف».',
 'marketing')
on conflict (key) do nothing;

-- ── 4. A PERSON IS ASKED FOR ─────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_social_hand_to_human(p_conversation_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c public.social_conversation%rowtype;
  v_last text;
  v_detail text;
begin
  select * into c from public.social_conversation where id = p_conversation_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_such_conversation'); end if;
  -- Already with him: a second "agent" in the same conversation does not email him twice.
  if c.status = 'handed_to_human' then return jsonb_build_object('ok', true, 'notified', false, 'reason', 'already_handed'); end if;

  update public.social_conversation
     set status = 'handed_to_human', handed_at = now(), handed_reason = left(coalesce(p_reason, ''), 500),
         handoff_count = handoff_count + 1
   where id = c.id;

  select string_agg(to_char(m.occurred_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || '  '
                    || case m.author when 'person' then coalesce(c.handle, 'them') when 'seat' then 'QuotesDone (auto)' else 'QuotesDone (team)' end
                    || ': ' || left(m.body, 400), E'\n' order by m.occurred_at)
    into v_last
    from (select * from public.social_message where conversation_id = c.id order by occurred_at desc limit 8) m;

  v_detail := 'Someone on ' || initcap(c.platform) || ' asked to speak with a person. The marketing seat has stopped '
    || 'auto-replying in this conversation and it is waiting for you.' || E'\n\n'
    || 'Platform: ' || initcap(c.platform) || E'\n'
    || 'Handle: ' || coalesce(nullif(c.handle, ''), '(not shared by Meta)') || '  (id ' || c.user_id || ')' || E'\n'
    || 'Conversation: #' || c.id || E'\n\n'
    || 'Last messages (Dubai time):' || E'\n' || coalesce(v_last, '(none)') || E'\n\n'
    || 'Continue in the Meta inbox: https://business.facebook.com/latest/inbox/all' || E'\n'
    || 'When you are done, hand it back to the seat: select public.fn_marketing_social_set_status('
    || c.id || ', ''auto'', ''founder'');';

  return jsonb_build_object('ok', true, 'notified', true, 'notify',
    public.fn_notify_founder(
      'Someone on ' || initcap(c.platform) || ' asked to speak with you' || coalesce(' (' || nullif(c.handle, '') || ')', ''),
      v_detail, 'high', 'social_human_request',
      'social_human:' || c.id || ':' || (c.handoff_count + 1), 'marketing'));
end
$fn$;
revoke execute on function public.fn_marketing_social_hand_to_human(bigint, text) from public, anon, authenticated;

-- ── 5. THE FOUNDER HANDS IT BACK (OR TAKES IT) ───────────────────────────────────────────────────
create or replace function public.fn_marketing_social_set_status(p_conversation_id bigint, p_status text, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if p_status not in ('auto', 'handed_to_human') then
    return jsonb_build_object('ok', false, 'reason', 'status must be auto or handed_to_human');
  end if;
  update public.social_conversation
     set status = p_status,
         resumed_at = case when p_status = 'auto' then now() else resumed_at end,
         resumed_by = case when p_status = 'auto' then left(coalesce(p_by, ''), 120) else resumed_by end,
         handed_at = case when p_status = 'handed_to_human' and status = 'auto' then now() else handed_at end,
         handed_reason = case when p_status = 'handed_to_human' and status = 'auto' then left(coalesce(p_by, ''), 500) else handed_reason end
   where id = p_conversation_id;
  return jsonb_build_object('ok', found, 'status', p_status);
end
$fn$;
revoke execute on function public.fn_marketing_social_set_status(bigint, text, text) from public, anon, authenticated;

-- ── 6. WHAT THE CEO'S MARKETING REPORT READS ─────────────────────────────────────────────────────
create or replace view public.v_marketing_social_volume with (security_invoker = true) as
select c.platform,
       count(distinct c.id)                                                                        as conversations,
       count(distinct c.id) filter (where c.status = 'handed_to_human')                            as waiting_for_founder,
       count(m.id) filter (where m.direction = 'in')                                               as inbound_total,
       count(m.id) filter (where m.direction = 'in' and m.occurred_at > now() - interval '1 day')  as inbound_24h,
       count(m.id) filter (where m.direction = 'in' and m.occurred_at > now() - interval '7 days') as inbound_7d,
       count(m.id) filter (where m.author = 'seat' and m.send_status = 'sent')                     as auto_replies_sent,
       count(m.id) filter (where m.author = 'seat' and m.send_status = 'held_switch_off')          as auto_replies_held_switch_off,
       count(m.id) filter (where m.author = 'seat' and m.reply_kind = 'handoff')                   as handoffs,
       count(m.id) filter (where m.author = 'seat' and m.reply_kind = 'unknown')                   as unanswered_gaps,
       count(m.id) filter (where m.author = 'human')                                               as founder_replies,
       max(m.occurred_at) filter (where m.direction = 'in')                                        as last_inbound_at
  from public.social_conversation c
  left join public.social_message m on m.conversation_id = c.id
 where not c.is_demo
 group by c.platform;
revoke all on public.v_marketing_social_volume from anon, authenticated;
