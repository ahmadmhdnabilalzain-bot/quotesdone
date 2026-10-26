-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708100414   name: erp_gl_double_entry_core
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================
-- ERP: Double-entry General Ledger core
-- Base currency AED, accrual basis. Posted journals are immutable and must balance.
-- New public tables auto-get RLS via the guardrail trigger (deny-all; access via admin funcs).
-- ============================================================

-- 1) Chart of Accounts
create table if not exists public.gl_accounts (
  code           text primary key,
  name           text not null,
  type           text not null check (type in ('asset','liability','equity','revenue','expense')),
  subtype        text,
  normal_balance char(1) not null check (normal_balance in ('D','C')),
  parent_code    text references public.gl_accounts(code),
  is_active      boolean not null default true,
  description    text,
  created_at     timestamptz not null default now()
);

-- 2) Journal (entry header)
create table if not exists public.gl_journal (
  id          bigint generated always as identity primary key,
  entry_no    text unique,
  entry_date  date not null default (now() at time zone 'utc')::date,
  memo        text,
  source      text not null default 'manual',   -- manual | reveal_fee | supplier_commission | expense | po | inventory | depreciation | reversal | opening
  source_ref  text,
  currency    text not null default 'AED',
  status      text not null default 'draft' check (status in ('draft','posted','void')),
  reverses    bigint references public.gl_journal(id),
  created_by  text,
  created_at  timestamptz not null default now(),
  posted_at   timestamptz
);
create index if not exists idx_gl_journal_date on public.gl_journal(entry_date);
create index if not exists idx_gl_journal_source on public.gl_journal(source, source_ref);
create index if not exists idx_gl_journal_status on public.gl_journal(status);

-- 3) Journal lines (exactly one of debit/credit is non-zero)
create table if not exists public.gl_journal_lines (
  id           bigint generated always as identity primary key,
  journal_id   bigint not null references public.gl_journal(id) on delete cascade,
  line_no      int,
  account_code text not null references public.gl_accounts(code),
  debit        numeric(18,2) not null default 0 check (debit  >= 0),
  credit       numeric(18,2) not null default 0 check (credit >= 0),
  memo         text,
  constraint gl_line_one_side check ((debit = 0) <> (credit = 0))
);
create index if not exists idx_gl_lines_journal on public.gl_journal_lines(journal_id);
create index if not exists idx_gl_lines_account on public.gl_journal_lines(account_code);

-- 4) Immutability: posted journals + their lines cannot be mutated (reverse instead)
create or replace function public.fn_gl_journal_immutable()
returns trigger language plpgsql security definer set search_path=public,pg_catalog as $$
begin
  if tg_op in ('UPDATE','DELETE') and old.status = 'posted'
     and not (tg_op='UPDATE' and new.status='void' and old.status='posted' and new.reverses is not null) then
    -- allow only the controlled void marking done by fn_gl_reverse (new.status='void')
    if tg_op='DELETE' or (tg_op='UPDATE' and old.status='posted' and new.status='posted'
         and (new.entry_date<>old.entry_date or new.memo is distinct from old.memo or new.source<>old.source)) then
      raise exception 'Posted journal % is immutable (reverse it instead)', old.id;
    end if;
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;
drop trigger if exists trg_gl_journal_immutable on public.gl_journal;
create trigger trg_gl_journal_immutable before update or delete on public.gl_journal
  for each row execute function public.fn_gl_journal_immutable();

create or replace function public.fn_gl_lines_immutable()
returns trigger language plpgsql security definer set search_path=public,pg_catalog as $$
declare st text;
begin
  select status into st from public.gl_journal where id = coalesce(new.journal_id, old.journal_id);
  if st = 'posted' then
    raise exception 'Cannot modify lines of a posted journal (reverse it instead)';
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;
drop trigger if exists trg_gl_lines_immutable on public.gl_journal_lines;
create trigger trg_gl_lines_immutable before insert or update or delete on public.gl_journal_lines
  for each row execute function public.fn_gl_lines_immutable();

-- 5) Post a journal (validates double-entry balance), assign entry_no
create or replace function public.fn_gl_post(p_journal bigint)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare d numeric(18,2); c numeric(18,2); n int; st text;
begin
  select status into st from public.gl_journal where id=p_journal;
  if st is null then raise exception 'journal % not found', p_journal; end if;
  if st='posted' then return p_journal; end if;
  select coalesce(sum(debit),0), coalesce(sum(credit),0), count(*) into d,c,n from public.gl_journal_lines where journal_id=p_journal;
  if n < 2 then raise exception 'journal % needs >= 2 lines', p_journal; end if;
  if d <> c then raise exception 'journal % out of balance: debits %.2f <> credits %.2f', p_journal, d, c; end if;
  if d = 0 then raise exception 'journal % has zero amount', p_journal; end if;
  update public.gl_journal
     set status='posted', posted_at=now(),
         entry_no = coalesce(entry_no, 'JE-'||lpad(p_journal::text,6,'0'))
   where id=p_journal;
  return p_journal;
end $$;

-- 6) Create + post a balanced entry in one call. p_lines: [{"account":"4000","credit":100,"memo":".."}, {"account":"1200","debit":100}]
create or replace function public.fn_gl_entry(p_date date, p_memo text, p_source text, p_ref text, p_lines jsonb, p_created_by text default 'system')
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare jid bigint; ln jsonb; i int := 0;
begin
  insert into public.gl_journal(entry_date, memo, source, source_ref, created_by)
    values (coalesce(p_date, (now() at time zone 'utc')::date), p_memo, coalesce(p_source,'manual'), p_ref, p_created_by)
    returning id into jid;
  for ln in select * from jsonb_array_elements(p_lines) loop
    i := i + 1;
    insert into public.gl_journal_lines(journal_id, line_no, account_code, debit, credit, memo)
      values (jid, i, (ln->>'account'),
              round(coalesce((ln->>'debit')::numeric,0),2),
              round(coalesce((ln->>'credit')::numeric,0),2),
              ln->>'memo');
  end loop;
  perform public.fn_gl_post(jid);
  return jid;
end $$;

-- 7) Reverse a posted entry (mirror lines on p_date)
create or replace function public.fn_gl_reverse(p_journal bigint, p_date date, p_memo text default null)
returns bigint language plpgsql security definer set search_path=public,pg_catalog as $$
declare jid bigint; r record;
begin
  if (select status from public.gl_journal where id=p_journal) <> 'posted' then
    raise exception 'can only reverse a posted journal'; end if;
  insert into public.gl_journal(entry_date, memo, source, source_ref, reverses, created_by)
    values (coalesce(p_date,(now() at time zone 'utc')::date),
            coalesce(p_memo,'Reversal of JE '||p_journal), 'reversal', p_journal::text, p_journal, 'system')
    returning id into jid;
  for r in select account_code, debit, credit, line_no from public.gl_journal_lines where journal_id=p_journal loop
    insert into public.gl_journal_lines(journal_id, line_no, account_code, debit, credit)
      values (jid, r.line_no, r.account_code, r.credit, r.debit);  -- swap
  end loop;
  perform public.fn_gl_post(jid);
  return jid;
end $$;

-- 8) Reporting views (posted only)
create or replace view public.gl_ledger as
  select j.id journal_id, j.entry_no, j.entry_date, j.source, j.source_ref, j.memo,
         l.account_code, a.name account_name, a.type account_type, l.debit, l.credit
  from public.gl_journal j
  join public.gl_journal_lines l on l.journal_id=j.id
  join public.gl_accounts a on a.code=l.account_code
  where j.status='posted';

create or replace view public.gl_account_balances as
  select a.code, a.name, a.type, a.normal_balance,
         coalesce(sum(l.debit),0)  as debit_total,
         coalesce(sum(l.credit),0) as credit_total,
         case when a.normal_balance='D' then coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0)
              else coalesce(sum(l.credit),0)-coalesce(sum(l.debit),0) end as balance
  from public.gl_accounts a
  left join public.gl_journal_lines l on l.account_code=a.code
  left join public.gl_journal j on j.id=l.journal_id and j.status='posted'
  group by a.code, a.name, a.type, a.normal_balance;

create or replace view public.gl_trial_balance as
  select code, name, type,
         case when balance>=0 and normal_balance='D' then balance else 0 end as debit,
         case when balance>=0 and normal_balance='C' then balance else 0 end as credit,
         balance
  from public.gl_account_balances
  where debit_total<>0 or credit_total<>0
  order by code;

create or replace view public.gl_pnl as
  select type, code, name, balance as amount
  from public.gl_account_balances
  where type in ('revenue','expense')
  order by type desc, code;

create or replace view public.gl_balance_sheet as
  select type, code, name, balance as amount
  from public.gl_account_balances
  where type in ('asset','liability','equity')
  order by type, code;

-- Net income + financial-position summary helpers
create or replace function public.fn_gl_net_income()
returns numeric language sql stable set search_path=public,pg_catalog as $$
  select coalesce(sum(case when type='revenue' then balance else -balance end),0)
  from public.gl_account_balances where type in ('revenue','expense');
$$;

-- 9) Seed a standard chart of accounts (idempotent)
insert into public.gl_accounts(code,name,type,subtype,normal_balance) values
  ('1000','Cash & Bank','asset','cash','D'),
  ('1050','Stripe Clearing','asset','cash','D'),
  ('1100','Accounts Receivable','asset','ar','D'),
  ('1110','Supplier Commission Receivable','asset','ar','D'),
  ('1400','Prepaid Expenses','asset','current','D'),
  ('1500','Inventory','asset','inventory','D'),
  ('1600','Fixed Assets - Cost','asset','ppe','D'),
  ('1650','Accumulated Depreciation','asset','contra','C'),
  ('2000','Accounts Payable','liability','ap','C'),
  ('2100','VAT Payable','liability','tax','C'),
  ('2200','Accrued Expenses','liability','current','C'),
  ('2300','Customer Refunds Payable','liability','current','C'),
  ('2400','Deferred Revenue','liability','current','C'),
  ('3000','Owner Capital','equity','capital','C'),
  ('3100','Retained Earnings','equity','retained','C'),
  ('4000','Reveal Fee Revenue','revenue','operating','C'),
  ('4100','Supplier Commission Revenue','revenue','operating','C'),
  ('4200','Supplier Registration Revenue','revenue','operating','C'),
  ('5000','Cost of Goods Sold','expense','cogs','D'),
  ('6000','Software & AI','expense','opex','D'),
  ('6100','Payment Processing Fees','expense','opex','D'),
  ('6200','Marketing & Advertising','expense','opex','D'),
  ('6300','General & Administrative','expense','opex','D'),
  ('6400','Depreciation Expense','expense','opex','D'),
  ('6900','Refunds & Bad Debt','expense','opex','D')
on conflict (code) do nothing;
