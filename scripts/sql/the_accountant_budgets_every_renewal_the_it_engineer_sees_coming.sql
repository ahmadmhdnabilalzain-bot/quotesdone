-- THE ACCOUNTANT BUDGETS EVERY RENEWAL THE IT ENGINEER SEES COMING: THE LICENCE, THE NOL AND THE DOMAINS.
--
-- Assigned: accountant (the budget and its answer); the watch and the close are the it_engineer's.
-- Founder, 14 Sep 2026: "add all for accountant and IT" — duty 5 of the five further accountant duties.
--
-- WHAT WAS MEASURED (14 Sep 2026, the repository at #645's head, which carries main through #656):
--   * public.it_expiry (the_it_engineer_runs_its_duties_every_hour.sql) is the one list of what the company
--     must renew: trade_licence_det_1633275 (24 Jun 2027), tdra_nol_26_100000665 (14 Sep 2027) and the two
--     domains (dates from RDAP). Its route column already says the fee is the accountant's. Nothing held a
--     budget for any of them, and nothing turned "expires on" into "pay this much by".
--   * The IT engineer's renewal watch is being built in parallel (branch it-engineer/duties-19-24). The
--     agreed conversation is written here, as data, so the watch only has to start it. Its name is
--     'renewal.due', not 'renewal_due': public.seat_handoff_kind.type must match ^[a-z]+(\.[a-z_]+)+$ and
--     refuses a name with no dot.
--
-- THE CONTRACT WITH THE IT ENGINEER:
--   fn_seat_handoff('it_engineer', 'accountant', 'renewal.due', 'it_expiry', <item> || '@' || <expires_on>,
--                   jsonb_build_object('item', <it_expiry.item>))
--   The accountant answers at once with the budget and waits (originator_closes): the it_engineer closes the
--   conversation when its own reading shows the new expiry date.
--
-- WHAT THIS BUILDS: accountant_renewal_budget, one row per it_expiry licence or domain, holding the fee to
-- set aside and the date to pay by. The fee is ONLY the last payment booked in expense_entries for that
-- vendor (decision_policy accountant_renewal_vendor_patterns); with none booked the budget is null and says
-- why, and once the expiry is inside accountant_renewal_unbudgeted_warn_days that is an accountant finding
-- until a payment is booked. TLS certificates are not budgeted: Vercel renews them at no charge.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_budgets_every_renewal_the_it_engineer_sees_coming.sql --apply --ddl

create table if not exists public.accountant_renewal_budget (
  item            text primary key,
  kind            text          not null,
  expires_on      date,
  pay_by          date,
  budget_aed      numeric(14,2) check (budget_aed is null or budget_aed > 0),
  basis           text          not null check (btrim(basis) <> ''),
  last_expense_id bigint,
  handoff_id      bigint,
  updated_at      timestamptz   not null default now()
);
comment on table public.accountant_renewal_budget is
  'The fee the accountant sets aside for each licence and domain in public.it_expiry, and the date to pay it by. budget_aed is the last payment booked in expense_entries for that vendor, or null with the reason: never an estimate.';
alter table public.accountant_renewal_budget enable row level security;
drop policy if exists accountant_renewal_budget_service_role_only on public.accountant_renewal_budget;
create policy accountant_renewal_budget_service_role_only on public.accountant_renewal_budget
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_renewal_budget from anon, authenticated;

insert into public.decision_policy (key, value, description) values
  ('accountant_renewal_vendor_patterns',
   '[{"item": "^trade_licence", "vendor": "(department of economy|dubai economy|\\mDET\\M|invest ?in ?dubai)"},
     {"item": "^tdra_nol", "vendor": "(\\mTDRA\\M|telecommunications and digital government)"},
     {"item": "^domain:", "vendor": "(godaddy)"}]'::jsonb,
   'For each it_expiry item (regex on the item), the regex on expense_entries.vendor whose last booked payment is the renewal budget.'),
  ('accountant_renewal_horizon_days', '365'::jsonb, 'How far ahead of an expiry the accountant keeps a renewal budget line.'),
  ('accountant_renewal_pay_days_before', '14'::jsonb, 'The renewal is budgeted to be paid this many days before the expiry.'),
  ('accountant_renewal_unbudgeted_warn_days', '90'::jsonb, 'Inside this many days of the expiry, a renewal with no booked fee to budget from is an accountant finding.')
on conflict (key) do nothing;

-- ── 1. ONE BUDGET LINE, FROM WHAT WAS BOOKED ─────────────────────────────────────────────────────
create or replace function public.fn_accountant_renewal_budget_line(p_item text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  x public.it_expiry; v_pat text; v_before int; v_fx numeric; v_basis text; v_amt numeric;
  v_eid bigint; v_vendor text; v_amount numeric; v_cur text; v_on date;
begin
  select * into x from public.it_expiry where item = p_item;
  if not found then raise exception 'public.it_expiry has no item %', p_item; end if;
  v_before := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_pay_days_before');
  if v_before is null then raise exception 'decision_policy accountant_renewal_pay_days_before is missing'; end if;
  select r->>'vendor' into v_pat
    from jsonb_array_elements(coalesce((select value from public.decision_policy where key = 'accountant_renewal_vendor_patterns'), '[]'::jsonb)) r
   where p_item ~ (r->>'item') limit 1;
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);
  if v_pat is not null then
    select id, vendor, amount, upper(currency), charged_on into v_eid, v_vendor, v_amount, v_cur, v_on
      from public.expense_entries
     where vendor ~* v_pat and upper(currency) in ('AED', 'USD') and amount > 0
     order by charged_on desc, id desc limit 1;
  end if;
  if v_pat is null then
    v_basis := 'MISSING: no vendor pattern in decision_policy accountant_renewal_vendor_patterns matches ' || p_item || ', so no booked payment can be found for it';
  elsif v_eid is null then
    v_basis := 'MISSING: no payment booked in expense_entries matches ' || v_pat || '; the fee is unknown until the receipt is booked';
  else
    v_amt := round(v_amount * case v_cur when 'USD' then v_fx else 1 end, 2);
    v_basis := 'the last booked payment: expense_entries #' || v_eid || ', ' || v_vendor || ', ' || v_cur || ' ' || v_amount || ' on ' || v_on;
  end if;
  insert into public.accountant_renewal_budget (item, kind, expires_on, pay_by, budget_aed, basis, last_expense_id, updated_at)
  values (x.item, x.kind, x.expires_on, x.expires_on - v_before, v_amt, v_basis, v_eid, now())
  on conflict (item) do update set kind = excluded.kind, expires_on = excluded.expires_on, pay_by = excluded.pay_by,
                                   budget_aed = excluded.budget_aed, basis = excluded.basis,
                                   last_expense_id = excluded.last_expense_id, updated_at = now();
  return jsonb_build_object('item', x.item, 'kind', x.kind, 'expires_on', x.expires_on, 'pay_by', x.expires_on - v_before,
                            'budget_aed', v_amt, 'basis', v_basis);
end $fn$;
revoke execute on function public.fn_accountant_renewal_budget_line(text) from public, anon, authenticated;

-- ── 2. THE ACCOUNTANT'S ANSWER TO THE IT ENGINEER'S renewal.due ──────────────────────────────────
create or replace function public.fn_accountant_budgets_renewal(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_item text; b jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'renewal.due' then
    raise exception 'fn_accountant_budgets_renewal: % is not a renewal.due handoff', p_id;
  end if;
  v_item := nullif(btrim(a.detail->>'item'), '');
  if v_item is null then raise exception 'renewal.due handoff % names no item: the payload carries {item: it_expiry.item}', p_id; end if;
  b := public.fn_accountant_renewal_budget_line(v_item);
  update public.accountant_renewal_budget set handoff_id = p_id where item = v_item;
  return jsonb_build_object('waiting', 'it_engineer re-verification of the new expiry of ' || v_item,
    'seat', 'accountant', 'budget', b,
    'reply', case when b->>'budget_aed' is null
                  then 'accountant: ' || v_item || ' is not budgeted. ' || (b->>'basis') || '. It is an open accountant finding until a payment is booked.'
                  else 'accountant: AED ' || (b->>'budget_aed') || ' is set aside for ' || v_item || ', to pay by ' || (b->>'pay_by')
                       || ' (' || (b->>'basis') || ').' end);
end $fn$;
revoke execute on function public.fn_accountant_budgets_renewal(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('renewal.due', 'it_engineer', 'accountant',
   'A company licence, NOL or domain in public.it_expiry is inside its renewal window: the accountant budgets the fee from the last payment booked, and the it_engineer closes the conversation once it reads the new expiry.',
   'fn_accountant_budgets_renewal', interval '1 day', true,
   'scripts/sql/the_accountant_budgets_every_renewal_the_it_engineer_sees_coming.sql')
on conflict (type, from_seat, to_seat) do nothing;

-- ── 3. WHAT IS COMING, FOR THE CEO'S MONTHLY REPORT ──────────────────────────────────────────────
create or replace function public.fn_accountant_renewal_position()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'budgeted_aed', coalesce(sum(budget_aed), 0),
    'lines', count(*),
    'unbudgeted', count(*) filter (where budget_aed is null),
    'items', coalesce(jsonb_agg(jsonb_build_object('item', item, 'kind', kind, 'expires_on', expires_on, 'pay_by', pay_by,
                                                   'budget_aed', budget_aed, 'basis', basis) order by expires_on nulls last, item), '[]'::jsonb),
    'basis', 'Each licence and domain in it_expiry expiring within decision_policy accountant_renewal_horizon_days, budgeted at the last payment booked for its vendor. budgeted_aed adds only the lines that have one; unbudgeted counts the rest.')
  from public.accountant_renewal_budget
  where item !~* 'zz[_ -]?demo'
    and (expires_on is null or expires_on <= (now() at time zone 'Asia/Dubai')::date
           + coalesce((select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_horizon_days'), 365));
$fn$;
revoke execute on function public.fn_accountant_renewal_position() from public, anon, authenticated;

-- ── 4. THE DUTY ──────────────────────────────────────────────────────────────────────────────────
-- Works whether or not the IT engineer's watch has started the conversation yet: every licence and domain
-- inside the horizon gets its line every hour, and an unbudgeted one close to expiry is a finding.
create or replace function public.fn_accountant_renewals_tick(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_horizon int := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_horizon_days');
  v_warn int := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_renewal_unbudgeted_warn_days');
  x public.it_expiry; b jsonb; n int := 0; v_items jsonb := '[]'::jsonb;
begin
  if v_horizon is null or v_warn is null then
    raise exception 'decision_policy accountant_renewal_horizon_days and accountant_renewal_unbudgeted_warn_days are required';
  end if;
  for x in select * from public.it_expiry
            where kind in ('licence', 'domain') and (expires_on is null or expires_on <= v_as_of + v_horizon) order by item loop
    b := public.fn_accountant_renewal_budget_line(x.item);
    n := n + 1;
    if b->>'budget_aed' is null and x.expires_on is not null and x.expires_on <= v_as_of + v_warn then
      v_items := v_items || jsonb_build_object('item', 'unbudgeted:' || x.item, 'owner_seat', 'accountant', 'subject', 'accountant_renewal_budget',
        'title', x.item || ' must be renewed by ' || x.expires_on || ' and has no budget: ' || (b->>'basis'),
        'blast', 'agent_facing', 'affected', 1, 'demo', x.item ~* 'zz[_ -]?demo', 'evidence', b);
    end if;
  end loop;
  return jsonb_build_object('lines', n, 'position', public.fn_accountant_renewal_position(),
                            'findings', public.fn_accountant_duty_settle('renewals', v_items));
end $fn$;
revoke execute on function public.fn_accountant_renewals_tick(date) from public, anon, authenticated;
