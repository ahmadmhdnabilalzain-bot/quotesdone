-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711231319   name: localize_reveal_nudges_arabic
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.qd_reveal_nudges()
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare base text := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_ack';
begin
  with due as (
    select t.id, t.inquiry_id, t.supplier_id, t.ack_token, l.email, coalesce(l.locale,'en') as locale
    from transactions t join leads l on l.id=t.supplier_id
    where t.revealed_at is not null and t.revealed_at < now()-interval '24 hours'
      and t.nudged_24_at is null and coalesce(t.fee_status,'')='paid' and t.refund_status is null and t.supplier_ack_at is null
      and not exists (select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
      and l.email ~ '@'
  ), ins as (
    insert into notifications(type,to_email,to_role,inquiry_id,subject,body)
    select 'supplier_nudge', d.email, 'supplier', d.inquiry_id,
      case when d.locale='ar' then 'عميل دافع بانتظارك — يُرجى الرد'
           else 'A paying customer is waiting for you — please respond' end,
      (case when d.locale='ar'
        then 'دفع أحد العملاء لكشف بيانات تواصلك على QuotesDone وهو بانتظار ردك. يُرجى التواصل معه في أقرب وقت. وفقاً لاتفاقية المورّد، إذا لم ترد خلال ٣ أيام عمل وتم استرداد المبلغ للعميل، تُطبَّق رسوم عدم استجابة تعادل رسوم الكشف (٣٪ من قيمة العرض) على حسابك.'
        else 'A customer has paid to reveal your contact on QuotesDone and is waiting to hear from you. Please contact them as soon as possible. Under the Supplier Agreement, if you do not respond within 3 working days and the customer is refunded, a non-response charge equal to the reveal fee (3% of the quoted value) applies to your account.' end)
      || E'\n\n' ||
      (case when d.locale='ar' then 'هل تواصلت مع العميل بالفعل؟ أكّد هنا لإيقاف هذه التذكيرات: '
            else 'Already contacted this customer? Confirm here to stop these reminders: ' end)
      || base || '?tx=' || d.id || '&token=' || d.ack_token
    from due d returning 1
  )
  update transactions set nudged_24_at=now() where id in (select id from due);

  with due as (
    select t.id, t.inquiry_id, t.supplier_id, t.ack_token, l.email, coalesce(l.locale,'en') as locale
    from transactions t join leads l on l.id=t.supplier_id
    where t.revealed_at is not null and t.revealed_at < now()-interval '48 hours'
      and t.nudged_48_at is null and coalesce(t.fee_status,'')='paid' and t.refund_status is null and t.supplier_ack_at is null
      and not exists (select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
      and l.email ~ '@'
  ), ins as (
    insert into notifications(type,to_email,to_role,inquiry_id,subject,body)
    select 'supplier_nudge', d.email, 'supplier', d.inquiry_id,
      case when d.locale='ar' then 'تذكير أخير: عميل لا يزال بانتظارك — يُرجى الرد اليوم'
           else 'Final reminder: a customer is still waiting — please respond today' end,
      (case when d.locale='ar'
        then 'هذا تذكير أخير بأن عميلاً دافعاً بانتظار ردك على QuotesDone. إذا لم ترد وتم استرداد المبلغ للعميل، تُطبَّق رسوم عدم استجابة تعادل رسوم الكشف (٣٪ من قيمة العرض)، وقد يؤدي تكرار عدم الرد إلى إزالتك من المنصّة.'
        else 'This is a final reminder that a paying customer is waiting for your response on QuotesDone. If you do not respond and the customer is refunded, a non-response charge equal to the reveal fee (3% of the quoted value) applies, and repeated non-response may lead to removal from the Platform.' end)
      || E'\n\n' ||
      (case when d.locale='ar' then 'هل تواصلت مع العميل بالفعل؟ أكّد هنا لإيقاف هذه التذكيرات: '
            else 'Already contacted this customer? Confirm here to stop these reminders: ' end)
      || base || '?tx=' || d.id || '&token=' || d.ack_token
    from due d returning 1
  )
  update transactions set nudged_48_at=now() where id in (select id from due);
end $function$;
