-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260619150926   name: disputes_lifecycle_funnel
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- A1: reveal opens a 72h refund window (BEFORE so we set columns on the row)
create or replace function public.trg_reveal_window() returns trigger language plpgsql as $f1$
begin
  if NEW.revealed_at is not null and NEW.refund_deadline is null then
    NEW.refund_deadline := NEW.revealed_at + interval '72 hours';
    if NEW.refund_status is null then NEW.refund_status := 'window_open'; end if;
  end if;
  return NEW;
end $f1$;
drop trigger if exists trg_reveal_window_b on public.transactions;
create trigger trg_reveal_window_b before insert or update on public.transactions
  for each row execute function public.trg_reveal_window();

-- A2 + B-reveal: reveal receipt email (once)
create or replace function public.trg_reveal_receipt() returns trigger language plpgsql security definer as $f2$
declare cemail text; comp text; inq record;
begin
  if NEW.revealed_at is not null and (TG_OP='INSERT' or OLD.revealed_at is null) then
    select email into cemail from public.customers where id = NEW.customer_id;
    select company_name into comp from public.leads where id = NEW.supplier_id;
    select summary, category into inq from public.inquiries where id = NEW.inquiry_id;
    if cemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('reveal_receipt', cemail, 'customer', NEW.inquiry_id,
        'Reveal confirmed — '||coalesce(comp,'supplier'),
        'You have unlocked '||coalesce(comp,'the supplier')||'''s contact details'||coalesce(' for: '||left(inq.summary,80),'')||'. You can now message them directly in the app. If they do not respond within 72 hours, open the request and Report an issue to request a refund of your reveal fee.',
        'queued');
    end if;
  end if;
  return NEW;
end $f2$;
drop trigger if exists trg_reveal_receipt_a on public.transactions;
create trigger trg_reveal_receipt_a after insert or update on public.transactions
  for each row execute function public.trg_reveal_receipt();

-- B: inquiry received email
create or replace function public.trg_inquiry_received() returns trigger language plpgsql security definer as $f3$
declare cemail text;
begin
  select email into cemail from public.customers where id = NEW.customer_id;
  if cemail is not null then
    insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
    values('inquiry_received', cemail, 'customer', NEW.id,
      'We have received your request',
      'Thanks — your request'||coalesce(' for '||left(NEW.summary,80),'')||' is in. We are matching it to relevant '||coalesce(NEW.category,'')||' suppliers in '||coalesce(NEW.emirate,'the UAE')||'. You will be notified as quotes come in — track everything in the app.',
      'queued');
  end if;
  return NEW;
end $f3$;
drop trigger if exists trg_inquiry_received_a on public.inquiries;
create trigger trg_inquiry_received_a after insert on public.inquiries
  for each row execute function public.trg_inquiry_received();

-- B: 'supplier hasn't replied' nudge (run hourly by cron)
create or replace function public.run_reveal_nudges() returns int language plpgsql security definer as $f4$
declare r record; n int := 0; cemail text; supemail text; comp text;
begin
  for r in
    select t.inquiry_id, t.supplier_id, t.customer_id
    from public.transactions t
    where t.revealed_at is not null
      and t.revealed_at < now() - interval '24 hours'
      and coalesce(t.refund_status,'') = 'window_open'
      and not exists (select 1 from public.messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier')
      and not exists (select 1 from public.notifications x where x.type='reveal_nudge' and x.inquiry_id=t.inquiry_id)
  loop
    select email into cemail from public.customers where id=r.customer_id;
    select company_name, claimed_by into comp, supemail from public.leads where id=r.supplier_id;
    if cemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('reveal_nudge', cemail,'customer', r.inquiry_id,
        coalesce(comp,'Your supplier')||' has not replied yet',
        'It has been 24 hours and '||coalesce(comp,'the supplier')||' has not responded in the app. Try messaging again — or open the request and Report an issue to request a reveal-fee refund (within 72 hours of reveal).','queued');
    end if;
    if supemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('reveal_nudge_sup', supemail,'supplier', r.inquiry_id,
        'A customer is waiting for your reply',
        'A customer unlocked your quote on QuotesDone and is waiting to hear from you. Please log in and reply in the app to win the job.','queued');
    end if;
    n := n + 1;
  end loop;
  return n;
end $f4$;

-- C: funnel metrics
create or replace function public.funnel_metrics(days int default 30) returns json language sql stable security definer as $f5$
  with w as (select (now() - make_interval(days => days)) as since)
  select json_build_object(
    'days', days,
    'inquiries', (select count(*) from public.inquiries i, w where i.created_at>=w.since),
    'matched', (select count(distinct m.inquiry_id) from public.inquiry_matches m join public.inquiries i on i.id=m.inquiry_id, w where i.created_at>=w.since),
    'quoted', (select count(distinct q.inquiry_id) from public.quotes q join public.inquiries i on i.id=q.inquiry_id, w where i.created_at>=w.since),
    'revealed', (select count(*) from public.transactions t join public.inquiries i on i.id=t.inquiry_id, w where t.revealed_at is not null and i.created_at>=w.since),
    'reveal_fees', (select coalesce(sum(t.reveal_fee),0) from public.transactions t join public.inquiries i on i.id=t.inquiry_id, w where t.revealed_at is not null and i.created_at>=w.since)
  );
$f5$;

select cron.schedule('reveal_nudges','7 * * * *', $cr$select public.run_reveal_nudges()$cr$);
