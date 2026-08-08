-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260620114145   name: workflow_completion_expiry_noquotes
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.inquiries
  add column if not exists hired_supplier_id bigint references public.leads(id),
  add column if not exists completed_at timestamptz,
  add column if not exists outcome text,
  add column if not exists no_quote_notified boolean default false;
alter table public.quotes add column if not exists expires_at timestamptz;

-- Quote expiry: parse the free-text validity, default 14 days, clamp 1..180
create or replace function public.trg_quote_expiry() returns trigger language plpgsql as $f$
declare days int := 14; m text; n int;
begin
  if NEW.expires_at is null then
    m := lower(coalesce(NEW.validity,''));
    n := nullif((regexp_match(m,'(\d+)'))[1],'')::int;
    if n is not null and n > 0 then
      if m ~ 'week' then days := n*7;
      elsif m ~ 'month' then days := n*30;
      else days := n; end if;
    end if;
    if days < 1 then days := 14; end if;
    if days > 180 then days := 180; end if;
    NEW.expires_at := coalesce(NEW.created_at, now()) + make_interval(days => days);
  end if;
  return NEW;
end $f$;
drop trigger if exists trg_quote_expiry_b on public.quotes;
create trigger trg_quote_expiry_b before insert on public.quotes
  for each row execute function public.trg_quote_expiry();

-- No-quotes nudge (hourly)
create or replace function public.run_no_quote_nudges() returns int language plpgsql security definer as $f$
declare r record; n int := 0; cemail text;
begin
  for r in
    select i.id, i.customer_id, i.summary, i.category from public.inquiries i
    where i.status='sent' and i.created_at < now() - interval '12 hours'
      and coalesce(i.no_quote_notified,false)=false
      and not exists (select 1 from public.quotes q where q.inquiry_id=i.id)
  loop
    select email into cemail from public.customers where id=r.customer_id;
    if cemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('no_quotes_yet', cemail,'customer', r.id,
        'We are still sourcing quotes for your request',
        'Thanks for your patience — no quote has come in yet for '||coalesce(r.summary,r.category)||'. Suppliers are still reviewing it. You can add detail or widen the request in the app, and we will email you the moment a quote arrives.','queued');
    end if;
    update public.inquiries set no_quote_notified=true where id=r.id;
    n := n+1;
  end loop;
  return n;
end $f$;
select cron.schedule('no_quote_nudges','17 * * * *', $cr$select public.run_no_quote_nudges()$cr$);

-- Funnel: add completed + cancelled
create or replace function public.funnel_metrics(days int default 30) returns json language sql stable security definer as $f$
  with w as (select (now() - make_interval(days => days)) as since)
  select json_build_object(
    'days', days,
    'inquiries', (select count(*) from public.inquiries i, w where i.created_at>=w.since),
    'matched', (select count(distinct m.inquiry_id) from public.inquiry_matches m join public.inquiries i on i.id=m.inquiry_id, w where i.created_at>=w.since),
    'quoted', (select count(distinct q.inquiry_id) from public.quotes q join public.inquiries i on i.id=q.inquiry_id, w where i.created_at>=w.since),
    'revealed', (select count(*) from public.transactions t join public.inquiries i on i.id=t.inquiry_id, w where t.revealed_at is not null and i.created_at>=w.since),
    'completed', (select count(*) from public.inquiries i, w where i.status='completed' and i.created_at>=w.since),
    'cancelled', (select count(*) from public.inquiries i, w where i.status='cancelled' and i.created_at>=w.since),
    'reveal_fees', (select coalesce(sum(t.reveal_fee),0) from public.transactions t join public.inquiries i on i.id=t.inquiry_id, w where t.revealed_at is not null and i.created_at>=w.since)
  );
$f$;
