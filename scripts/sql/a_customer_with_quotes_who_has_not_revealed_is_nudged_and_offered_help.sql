-- A CUSTOMER WITH QUOTES WHO HAS NOT REVEALED IS NUDGED, TWICE AT MOST, AND OFFERED HELP.
-- Seat: sales_engineer (owns quotes, the comparison report and reveals, 24 Sep seat map); customer_support
-- delivers, as for every lifecycle duty (fn_customer_support_duty_send). Founder_instruction 1027 (backlog 1019, T1):
-- "a customer who compared quotes but did not reveal gets a timely nudge".
--
-- WHAT WAS MEASURED (5 Oct 2026, production, read-only): pg_proc has no routine that writes to a customer who has
-- quotes and no reveal (searched reveal + remind/nudge/follow, unrevealed). The lifecycle duties are activation (no
-- request / no quote), followup (after a reveal) and winback (60 days quiet) - none covers quoted-not-revealed.
-- The customer's 'new_quote' notifications cannot be the clock: all 12 on production are 'suppressed', so this
-- reads the quotes themselves.
--
-- WHAT THIS ADDS: fn_sales_engineer_reveal_followup_tick, duty sales_engineer.reveal_followup every 6 hours.
--   stage reveal.day_two   the first live quote is 2-6 days old, nothing revealed: one message.
--   stage reveal.day_seven the first live quote is 7-21 days old, still nothing revealed: one last message.
-- One subject per request (the parent of a split, so a project gets one message, not one per trade).
-- "Live" = quotes.status 'submitted' and not past expires_at. Nothing is sent once any quote on the request or
-- its parts is revealed, the request is hired/completed/closed/cancelled, or the customer is banned. Language is the
-- request's (fn_customer_message_lang). No model: fixed copy. A fixture run (set local qd.duty_fixtures = 'on')
-- selects ONLY demo customers, so a probe cannot reach a real person.
--
--   node scripts/apply_sql.mjs scripts/sql/a_customer_with_quotes_who_has_not_revealed_is_nudged_and_offered_help.sql --apply --ddl

create or replace function public.fn_sales_engineer_reveal_followup_tick()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v jsonb; v_lang text; v_ar boolean; v_name text; v_cat text; v_ref text; v_sent int := 0; v_seen int := 0;
begin
  for r in
    with q as (
      select coalesce(i.parent_inquiry_id, i.id) as root, min(qt.created_at) as first_at, count(*) as n
        from public.quotes qt join public.inquiries i on i.id = qt.inquiry_id
       where qt.status = 'submitted' and (qt.expires_at is null or qt.expires_at > now())
       group by 1)
    select q.root, q.first_at, q.n, p.rfq_no, p.category, c.id as cid, c.full_name, c.email, c.locale,
           case when q.first_at <= now() - interval '7 days' then 'day_seven' else 'day_two' end as stage
      from q join public.inquiries p on p.id = q.root join public.customers c on c.id = p.customer_id
     where ((q.first_at <= now() - interval '2 days' and q.first_at > now() - interval '6 days')
         or (q.first_at <= now() - interval '7 days' and q.first_at > now() - interval '21 days'))
       and p.hired_supplier_id is null and p.completed_at is null
       and coalesce(p.status, '') not in ('cancelled', 'closed', 'completed', 'revealed')
       and not coalesce(c.banned, false)
       and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
       and not exists (select 1 from public.transactions t join public.inquiries x on x.id = t.inquiry_id
                        where t.revealed_at is not null and coalesce(x.parent_inquiry_id, x.id) = q.root)
     order by q.first_at limit 200
  loop
    v_seen := v_seen + 1;
    v_lang := public.fn_customer_message_lang(r.root, r.locale);
    v_ar := v_lang = 'ar';
    v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v_cat := coalesce(public.fn_trade_label(r.category, v_lang), case when v_ar then 'طلبكم' else 'your request' end);
    v_ref := 'RFQ-' || coalesce(r.rfq_no::text, '-');
    v := public.fn_customer_support_duty_send('reveal.' || r.stage, r.root::text, 'customer', r.email, v_lang,
      case when v_ar then
        case when r.stage = 'day_two' then 'عروضكم جاهزة للمقارنة - ' || v_ref else 'تذكير أخير: عروض ' || v_ref || ' ما زالت بانتظاركم' end
      else
        case when r.stage = 'day_two' then 'Your quotes are ready to compare - ' || v_ref else 'Last reminder: your quotes on ' || v_ref || ' are waiting' end
      end,
      case when v_ar then
        case when nullif(btrim(r.full_name), '') is null then 'عميلنا الكريم،' else 'السادة/ ' || v_name || ' المحترمين،' end || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'وصلكم ' || r.n || ' من العروض على طلبكم ' || v_ref || ' (' || v_cat || ')، ويرتّب تقرير المقارنة أفضل ثلاثة منها من حيث القيمة. '
        || 'لا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% إلا حينها.' || chr(10) || chr(10)
        || 'وإن كان في أحد العروض ما يحتاج إلى توضيح - السعر أو النطاق أو الشروط - فأضيفوا ملاحظتكم أو سؤالكم من صفحة الطلب، فتصل إلى جميع المورّدين دون اسمكم أو رقمكم، أو ردّوا على هذه الرسالة لنساعدكم في المقارنة.' || chr(10) || chr(10)
        || 'افتحوا عروضكم من هنا: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'You have ' || r.n || case when r.n = 1 then ' quote' else ' quotes' end || ' on ' || v_ref || ' (' || v_cat || '), and your comparison report ranks the top three by value. '
        || 'You reveal only the supplier you choose, and pay 3% only then.' || chr(10) || chr(10)
        || 'If anything in a quote needs explaining - the price, the scope or the terms - add your note or question on the request page and it reaches every supplier without your name or number, or reply to this e-mail and we will help you compare.' || chr(10) || chr(10)
        || 'Open your quotes: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'Kind regards,'
      end,
      r.cid, null, r.root);
    if (v->>'sent')::boolean then v_sent := v_sent + 1; end if;
  end loop;
  return jsonb_build_object('seen', v_seen, 'sent', v_sent, 'fixture', v_fx);
end $fn$;
revoke execute on function public.fn_sales_engineer_reveal_followup_tick() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_reveal_followup_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.reveal_followup', 'sales_engineer', interval '6 hours', 'fn_sales_engineer_reveal_followup_tick',
   'a customer with live quotes and no reveal: one message 2 days after the first quote, one last at 7, with help to compare',
   'scripts/sql/a_customer_with_quotes_who_has_not_revealed_is_nudged_and_offered_help.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

select case
  when to_regprocedure('public.fn_sales_engineer_reveal_followup_tick()') is not null
   and exists (select 1 from public.seat_duty where duty = 'sales_engineer.reveal_followup' and enabled)
  then 'PROBE OK' else 'PROBE FAILED: routine or duty missing' end as verdict;
