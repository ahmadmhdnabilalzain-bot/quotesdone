-- A NUMBER CARRIES ITS MEANING, AND A RECORD PROVES IT IS REAL.
--
-- The founder, 9 September 2026, after I made the same class of mistake twice in one report:
--
--   "for the credit, you did that twice. You read it wrong in compared to the cap. So there must be
--    something wrong in the way you read that you repeated the mistake twice. That's what you need
--    to fix. And for the customer, again, this is not the first time you talk about something which
--    is in demo and you think it's real. So this is fundamental issue with you how you read stuff...
--    You need to find the reason why such mistakes are happening... If your audit is wrong,
--    definitely, you will build something wrong."
--
-- He is right that these are one fault, not two. Both are cases where a NARROW CHECK DID NOT
-- CONTRADICT ME, so I let the convenient reading stand. I confirmed instead of trying to disprove.
-- This file removes the ambiguity that made each reading possible, so the next reader — me, a seat,
-- or a future session — cannot make the same choice.
--
-- ══ FAULT 1: I REPORTED A SPENDING CAP AS A BANK BALANCE, TWICE ═════════════════════════════════
--
-- openrouter_meter already stores every number needed. It stores them well:
--   credits_total_usd    210.00     what the ACCOUNT was topped up with, lifetime
--   cumulative_usd       195.93     what the ACCOUNT has spent, lifetime, monotonic
--   limit_remaining_usd    4.07     what remains against a CAP SET ON ONE API KEY
--
-- The account has 210 - 195.93 = 14.07 left. The key is separately capped at 200 and has 4.07 of
-- that cap left. Two different constraints, and NEITHER is named `balance`. I reached for the column
-- whose name contained "remaining" and reported 4.07 as the money left in the company's account.
--
-- When the founder challenged it I called the live API and checked whether 4.07 was ACCURATE. It
-- was — and that is exactly why I repeated the error. I verified the VALUE and never verified the
-- MEANING. The estate already carries this lesson under the name "an instrument measuring the wrong
-- subject", and a lesson that only exists as prose does not stop anything.
--
-- THE FIX: compute the account balance explicitly, name the cap explicitly as a cap, and state
-- which of the two actually binds. A view that answers "how much money is left" with one number and
-- its definition cannot be misread the way three unnamed numbers could.
--
-- ══ FAULT 2: I TREATED THE ABSENCE OF A DEMO MARKER AS PROOF OF A REAL CUSTOMER ═════════════════
--
-- The estate's demo convention is a `ZZ DEMO` name and an @example.invalid address. I tested for
-- both, found neither, and reported the row as the company's first real customer. I then built a
-- whole section of an audit on it.
--
-- Absence of a marker is not evidence of realness. And the positive evidence was on my screen:
-- no name, no mobile, no accepted terms, a free-mail address, created the day after we shipped the
-- login flow, and no activity of any kind since. Every one of those says test signup. I read the
-- same row as "an incomplete registration" — a defect story I was already looking for — which is
-- confirmation bias with a query attached.
--
-- THE FIX: score a business record on the evidence that it is REAL, rather than on the absence of a
-- marker that says it is fake. A record with no name, no phone, no terms and no activity is not
-- something to count, whatever it is called.

-- ── 1. HOW MUCH MONEY IS ACTUALLY LEFT ──────────────────────────────────────────────────────────
drop view if exists public.v_openrouter_position;
create view public.v_openrouter_position as
select
  m.read_at,
  -- THE ACCOUNT. This is money.
  m.credits_total_usd                                    as account_topped_up_usd,
  m.cumulative_usd                                       as account_spent_usd,
  round(m.credits_total_usd - m.cumulative_usd, 4)       as account_balance_usd,
  -- THE KEY. This is a SETTING, not money. It can be raised without paying anyone.
  m.limit_remaining_usd                                  as key_cap_remaining_usd,
  -- WHICH ONE ACTUALLY STOPS THE COMPANY FIRST, stated rather than left to the reader.
  case
    when m.limit_remaining_usd is null then 'account_balance'
    when m.limit_remaining_usd <= round(m.credits_total_usd - m.cumulative_usd, 4) then 'key_cap'
    else 'account_balance'
  end                                                    as binding_constraint,
  least(coalesce(m.limit_remaining_usd, 'infinity'::numeric),
        round(m.credits_total_usd - m.cumulative_usd, 4)) as spendable_now_usd,
  'account_balance_usd is money the company owns. key_cap_remaining_usd is a per-key spending limit '
  'that can be raised in the OpenRouter dashboard at no cost. They are different things and they '
  'run out at different times; spendable_now_usd is whichever binds first.' as reading_note
from public.openrouter_meter m
where m.ok
order by m.read_at desc
limit 1;

comment on view public.v_openrouter_position is
  'The one place to read how much AI budget is left. Exists because on 9 Sep 2026 the key''s spending CAP (4.07) was twice reported to the founder as the account BALANCE (14.07). Every figure here is named for what it is, and binding_constraint says which one actually stops the company.';

-- ── 2. IS THIS BUSINESS RECORD REAL? ────────────────────────────────────────────────────────────
-- Scored on evidence of realness, never on the absence of a demo marker. Returns a verdict AND its
-- reasons, so a caller that disagrees has to argue with the specific evidence rather than the label.
create or replace function public.fn_customer_is_substantiated(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare c public.customers; v_for text[] := '{}'; v_against text[] := '{}'; v_activity int;
begin
  select * into c from public.customers where id = p_customer_id;
  if c.id is null then
    return jsonb_build_object('verdict','unknown','reason','no such customer');
  end if;

  -- Evidence FOR a real person
  if coalesce(trim(c.full_name),'') <> ''   then v_for := v_for || 'has a name'::text;        else v_against := v_against || 'no name'::text; end if;
  if coalesce(trim(c.phone),'')     <> ''   then v_for := v_for || 'has a mobile'::text;      else v_against := v_against || 'no mobile'::text; end if;
  if c.tos_accepted_at is not null          then v_for := v_for || 'accepted the terms'::text;else v_against := v_against || 'never accepted the terms'::text; end if;
  if c.phone_verified                       then v_for := v_for || 'verified a mobile'::text; end if;

  select (select count(*) from public.inquiries  i where i.customer_id = c.id)
       + (select count(*) from public.transactions t where t.customer_id = c.id)
    into v_activity;
  if v_activity > 0 then v_for := v_for || (v_activity || ' business record(s)')::text;
                    else v_against := v_against || 'no inquiry and no transaction, ever'::text; end if;

  -- The marker test is kept, but ONLY as an additional way to be fake — never as a way to be real.
  if c.full_name ilike 'ZZ DEMO%' or c.email ilike '%@example.invalid' then
    v_against := v_against || 'carries an explicit demo marker'::text;
  end if;

  return jsonb_build_object(
    'verdict', case when array_length(v_for,1) is null then 'not_substantiated'
                    when array_length(v_against,1) is null then 'substantiated'
                    else 'partial' end,
    'evidence_for', coalesce(to_jsonb(v_for), '[]'::jsonb),
    'evidence_against', coalesce(to_jsonb(v_against), '[]'::jsonb),
    'basis', 'Scored on evidence that this is a real buyer. The absence of a ZZ DEMO name or an '
          || '@example.invalid address is NOT evidence of realness — that inference is what caused a '
          || 'test signup to be reported to the founder as the company''s first customer on 9 Sep 2026.');
end $fn$;
revoke execute on function public.fn_customer_is_substantiated(uuid) from public;

-- The number any report should quote: customers with evidence behind them.
create or replace function public.fn_customer_counts()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_all int; v_sub int; v_part int; v_none int;
begin
  select count(*) into v_all from public.customers;
  select count(*) filter (where (public.fn_customer_is_substantiated(id)->>'verdict') = 'substantiated'),
         count(*) filter (where (public.fn_customer_is_substantiated(id)->>'verdict') = 'partial'),
         count(*) filter (where (public.fn_customer_is_substantiated(id)->>'verdict') = 'not_substantiated')
    into v_sub, v_part, v_none from public.customers;
  return jsonb_build_object(
    'rows_in_table', v_all,
    'substantiated', v_sub,
    'partial', v_part,
    'not_substantiated', v_none,
    'report_this_one', v_sub,
    'basis', 'rows_in_table counts anything that signed up, including test traffic. Quote '
          || 'substantiated when reporting how many customers the company has.');
end $fn$;
revoke execute on function public.fn_customer_counts() from public;

-- ── 3. PROVE BOTH, INCLUDING THE CASE THAT FOOLED ME ────────────────────────────────────────────
do $do$
declare v jsonb; c jsonb; v_id uuid; v_probe jsonb;
begin
  -- (a) the money view must separate the two numbers and pick the binding one
  select to_jsonb(t) into v from public.v_openrouter_position t;
  if v is null then raise exception 'POSITIVE CONTROL FAILED: no successful meter reading exists to test against'; end if;
  if (v->>'account_balance_usd')::numeric = (v->>'key_cap_remaining_usd')::numeric then
    raise notice 'the two figures happen to be equal today, so this reading cannot demonstrate the distinction';
  end if;
  if (v->>'binding_constraint') is null then raise exception 'the view does not say which constraint binds'; end if;

  -- (b) THE CASE THAT FOOLED ME, replayed. A row exactly like the deleted test signup —
  --     no name, no phone, no terms, no activity, and NO demo marker — must not score as real.
  insert into public.customers (id, email, email_verified, locale)
  values (gen_random_uuid(), 'probe-not-a-real-buyer@gmail.com', true, 'en')
  returning id into v_id;
  v_probe := public.fn_customer_is_substantiated(v_id);
  if (v_probe->>'verdict') = 'substantiated' then
    raise exception 'a row with no name, no phone, no terms and no activity scored as a real customer — the fix does not work';
  end if;

  c := public.fn_customer_counts();
  if (c->>'report_this_one')::int <> 0 then
    raise exception 'the probe row was counted as a customer to report';
  end if;

  delete from public.customers where id = v_id;
  if exists (select 1 from public.customers where id = v_id) then
    raise exception 'the probe left its own row behind';
  end if;

  raise notice 'MONEY: account balance $% (topped up $%, spent $%), key cap remaining $%, binding constraint = %. CUSTOMERS: the unmarked test row scored "%" on evidence [%], and the reportable count stayed 0.',
    v->>'account_balance_usd', v->>'account_topped_up_usd', v->>'account_spent_usd',
    v->>'key_cap_remaining_usd', v->>'binding_constraint',
    v_probe->>'verdict', v_probe->>'evidence_against';
end
$do$;
