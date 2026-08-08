-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623204455   name: docs_collections
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create or replace function add_working_days(d date, n int) returns date language plpgsql immutable as $$
declare cur date := d; added int := 0; dow int;
begin
  while added < n loop
    cur := cur + 1; dow := extract(dow from cur);
    if dow <> 0 and dow <> 6 then added := added + 1; end if;
  end loop;
  return cur;
end;$$;

create table if not exists supplier_dues (
  id bigint generated always as identity primary key,
  transaction_id bigint unique,
  supplier_id bigint,
  quote_id bigint,
  quote_amount numeric,
  commission_pct numeric default 2,
  amount_due numeric,
  currency text default 'AED',
  reveal_date date,
  due_date date,
  due_date_30 date,
  status text default 'pending',
  reminders int default 0,
  last_reminder_at timestamptz,
  overdue_emailed_at timestamptz,
  fine_pct numeric default 0,
  fine_amount numeric default 0,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);
alter table supplier_dues enable row level security;

create or replace function fn_doc_control() returns void language plpgsql security definer as $$
declare v_run bigint; v_remind int := 0; v_expired int := 0; r record; v_days int;
begin
  insert into agent_runs(agent, started_at) values ('docs', now()) returning id into v_run;
  for r in select id, company_name, claimed_by, email, license_expiry from leads
           where approval_status='approved' and claimed=true and license_expiry is not null
  loop
    v_days := r.license_expiry - current_date;
    if v_days between 0 and 7 then
      if not exists (select 1 from notifications where lead_id=r.id and type='licence_expiry_reminder' and created_at > now()-interval '6 days') then
        insert into notifications(type,to_email,to_role,channel,lead_id,subject,body)
          values ('licence_expiry_reminder', coalesce(r.claimed_by,r.email), 'supplier', 'email', r.id,
            'Your trade licence expires in '||v_days||' day(s) - QuotesDone',
            'Dear '||coalesce(r.company_name,'partner')||', our records show your trade licence expires on '||to_char(r.license_expiry,'DD Mon YYYY')||' ('||v_days||' day(s) away). Please upload your renewed trade licence in your supplier portal to keep your account active and continue receiving job matches. Portal: https://quotesdone.com/suppliers/');
        v_remind := v_remind + 1;
      end if;
    elsif v_days < 0 then
      if not exists (select 1 from notifications where lead_id=r.id and type='licence_expired' and created_at > now()-interval '7 days') then
        insert into notifications(type,to_email,to_role,channel,lead_id,subject,body)
          values ('licence_expired', coalesce(r.claimed_by,r.email), 'supplier', 'email', r.id,
            'Action needed: your trade licence has expired - QuotesDone',
            'Dear '||coalesce(r.company_name,'partner')||', our records show your trade licence expired on '||to_char(r.license_expiry,'DD Mon YYYY')||'. To keep receiving jobs on QuotesDone, please upload your renewed licence in your portal as soon as possible: https://quotesdone.com/suppliers/');
        insert into agent_actions(agent,kind,status,risk,title,recommendation,target_table,target_id,detail)
          values ('docs','licence_expired','pending','medium',coalesce(r.company_name,'Supplier #'||r.id)||' - trade licence EXPIRED','suspend or chase renewal','leads',r.id::text,jsonb_build_object('expiry',r.license_expiry));
        v_expired := v_expired + 1;
      end if;
    end if;
  end loop;
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('reminders',v_remind,'expired',v_expired) where id=v_run;
end;$$;

create or replace function fn_collections() returns void language plpgsql security definer as $$
declare v_run bigint; v_created int:=0; v_reminded int:=0; v_overdue int:=0; v_fined100 int:=0; r record; v_owner text; v_amt numeric;
begin
  insert into agent_runs(agent, started_at) values ('collections', now()) returning id into v_run;
  for r in select t.id, t.supplier_id, t.quote_id, t.quote_amount, t.revealed_at::date as rdate
           from transactions t
           where t.revealed_at is not null and coalesce(t.quote_amount,0) > 0
             and not exists (select 1 from supplier_dues d where d.transaction_id=t.id)
  loop
    v_amt := round(coalesce(r.quote_amount,0)*0.02, 2);
    insert into supplier_dues(transaction_id,supplier_id,quote_id,quote_amount,commission_pct,amount_due,reveal_date,due_date,due_date_30,status)
      values (r.id,r.supplier_id,r.quote_id,r.quote_amount,2,v_amt,r.rdate,add_working_days(r.rdate,14),add_working_days(r.rdate,30),'pending');
    v_created := v_created + 1;
  end loop;
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  for r in select d.*, l.claimed_by, l.email as lead_email, l.company_name
           from supplier_dues d join leads l on l.id=d.supplier_id
           where d.status not in ('paid','waived')
  loop
    if current_date >= r.due_date_30 and r.status <> 'fined_30' then
      update supplier_dues set status='fined_30', fine_pct=100, fine_amount=round(r.quote_amount,2) where id=r.id;
      insert into notifications(type,to_email,to_role,channel,lead_id,subject,body)
        values ('commission_overdue', coalesce(r.claimed_by,r.lead_email), 'supplier', 'email', r.supplier_id,
          'URGENT: overdue commission + 100% penalty - QuotesDone',
          'Dear '||coalesce(r.company_name,'partner')||', the 2% platform commission of AED '||round(r.amount_due)||' on your won job (quote #'||coalesce(r.quote_id::text,'-')||') remains unpaid beyond 30 working days. Per the Terms you accepted at sign-up, a penalty of 100% of the quotation value (AED '||round(r.quote_amount)||') now applies. Please settle immediately to avoid suspension. Reply to this email for transfer details.');
      v_fined100 := v_fined100 + 1;
      if v_owner is not null then insert into notifications(type,to_email,to_role,channel,subject,body) values ('collections_alert',v_owner,'admin','email','Supplier 100% penalty triggered',coalesce(r.company_name,'A supplier')||' is over 30 working days overdue on commission AED '||round(r.amount_due)||'. 100% penalty applied.'); end if;
    elsif current_date >= r.due_date and r.overdue_emailed_at is null then
      update supplier_dues set status='overdue', fine_pct=greatest(fine_pct,10), fine_amount=greatest(fine_amount, round(r.quote_amount*0.10,2)), overdue_emailed_at=now() where id=r.id;
      insert into notifications(type,to_email,to_role,channel,lead_id,subject,body)
        values ('commission_overdue', coalesce(r.claimed_by,r.lead_email), 'supplier', 'email', r.supplier_id,
          'Payment overdue - 2% commission, QuotesDone',
          'Dear '||coalesce(r.company_name,'partner')||', we have not received the 2% platform commission of AED '||round(r.amount_due)||' due on your won job (quote #'||coalesce(r.quote_id::text,'-')||'), payable within 14 working days. Per the Terms you accepted at sign-up, a penalty of 10% of the quotation value (AED '||round(r.quote_amount*0.10)||') now applies, rising to 100% if unpaid after 30 working days. Please transfer as soon as possible - reply to this email for bank details.');
      v_overdue := v_overdue + 1;
      if v_owner is not null then insert into notifications(type,to_email,to_role,channel,subject,body) values ('collections_alert',v_owner,'admin','email','Supplier commission overdue',coalesce(r.company_name,'A supplier')||' missed the 14-working-day commission of AED '||round(r.amount_due)||'. 10% penalty applied and overdue email sent.'); end if;
    elsif current_date < r.due_date and (r.last_reminder_at is null or r.last_reminder_at < now()-interval '4 days') and r.reminders < 3 then
      update supplier_dues set status=case when status='pending' then 'reminded' else status end, reminders=reminders+1, last_reminder_at=now() where id=r.id;
      insert into notifications(type,to_email,to_role,channel,status,lead_id,subject,body)
        values ('commission_reminder', coalesce(r.claimed_by,r.lead_email), 'supplier', 'portal', 'portal', r.supplier_id,
          'Reminder: 2% commission due by '||to_char(r.due_date,'DD Mon'),
          'Reminder: the 2% platform commission of AED '||round(r.amount_due)||' on your won job (quote #'||coalesce(r.quote_id::text,'-')||') is due by '||to_char(r.due_date,'DD Mon YYYY')||' (14 working days). Please arrange the bank transfer; settling on time avoids the 10% late penalty in the Terms.');
      v_reminded := v_reminded + 1;
    end if;
  end loop;
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('dues_created',v_created,'reminders',v_reminded,'overdue',v_overdue,'fined_100',v_fined100) where id=v_run;
end;$$;

