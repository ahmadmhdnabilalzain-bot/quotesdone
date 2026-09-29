-- THE ACCOUNTANT SCREENS EVERY PARTY AND HOLDS MONEY FOR REVIEW BEFORE IT MOVES (29 Sep 2026).
-- Seat: accountant (fraud and risk). customer_support answers the two handoffs this file registers, because
-- a held reveal or refund leaves a customer waiting and that customer is told, in their language, by support.
-- Founder ledger 1018 (round 3 of the agent upgrades): "fraud and risk screening". Plain code, no model.
--
-- WHAT WAS MEASURED (29 Sep 2026, production htdblwldjkcgjvmqkbeh, read-only):
--   * public.fraud_flags (pk kind, subject_type, subject_id) holds 7 rows, all 'dismissed'. Its one writer is
--     fn_accountant_fraud_watch_tick (the_accountant_watches_for_fee_circumvention_and_rescreens_sanctions.sql,
--     every 6 hours): duplicate licence / TRN / customer phone / customer e-mail, a customer who is a supplier,
--     and three fee-circumvention signals. That file is NOT changed here; duplicate trade licences across
--     suppliers stay its detector (kind duplicate_license, subject the licence key, lead ids in detail).
--   * NOTHING compared a supplier's company details with each other. leads carries company_name, the name the
--     licence prints (licence_legal_name, written by process_docs since #994) and the website domain;
--     fn_supplier_licence_name_mismatch(leads) already compares the two names (legal forms and spelling folded)
--     and only the sales engineer's approval read it.
--   * E-mail domains: is_disposable_email() reads app_blocked_domains (24 rows) and refuses a disposable address
--     at sign-up (trg_block_disposable_*); email_platform_domain (47 rows) lists directories, hosts and 8
--     disposable domains. NO table knows a free webmail domain: gmail.com is in neither. One real supplier
--     account (lead 126561) signs in with a gmail.com address.
--   * NOTHING read refund or dispute patterns per party: transactions.refund_requested_at, post_reveal_dispute
--     (raised_by customer|supplier) and stripe_dispute (card chargebacks) were each read one case at a time.
--   * NO money door asked about fraud. _shared/reveal_guard.ts canReveal (the one door stripe_checkout,
--     stripe_confirm and customer_api reveal all pass) checks ownership, request status, sanctions and the spec
--     hold; accountant execute_refunds sends every CEO-approved refund to Stripe after the refund window. A flag
--     on a party changed nothing about their money.
--
-- WHAT THIS ADDS
--   1. public.free_email_domain — the free webmail domains (gmail.com, outlook.com, the UAE ISP mailboxes ...).
--      fn_email_domain_class(email) -> 'disposable' | 'free' | 'company' | null, reading the three lists.
--   2. fn_accountant_party_flags(customer, supplier) writes fraud_flags, once per (kind, subject), never
--      re-opening a flag a person closed; a severity that rises on an OPEN flag is raised. Every rule is an
--      equality or a count, never a word match:
--        supplier (claimed, registered or under review), subject 'lead':
--          company_name_mismatch   licence name <> registered name (fn_supplier_licence_name_mismatch)   high
--          disposable_email        the account address is on a disposable list                           high
--          email_domain_mismatch   a company address whose domain is not the website's own domain        medium
--          free_email_company      the company account signs in with free webmail                        low
--          dispute_pattern         in 90 days, disputes raised against it + refunds paid on its reveals: 2 medium, 3+ high
--        customer, subject 'customer':
--          disposable_email                                                                               high
--          refund_pattern          refund requests in 90 days: 2 medium, 3+ high
--          dispute_pattern         a card chargeback in 180 days (high), or post-reveal disputes it raised in 90 days: 2 medium, 3+ high
--   3. public.money_move_hold and fn_accountant_money_screen(move, ref, customer, supplier) — THE SCREEN BEFORE
--      MONEY MOVES. It re-screens both parties now (not at the next tick), gathers every open or escalated flag
--      touching either of them (their own flags, and the duplicate / circumvention flags that name them in
--      detail), and answers:
--        a high-severity flag  -> HOLD: one 'held' row per (move, ref); the money does not move.
--        only lower flags      -> a 'noted' row: the money moves and the accountant can see which flagged
--                                 parties it moved between.
--        no flag               -> nothing written.
--      NO AUTOMATIC BAN. A hold is released when no high flag touches either party any more (a person closed
--      the flags through the existing fn_fraud_resolve, which is also the only way anyone is banned), or by
--      fn_money_move_hold_release (a reviewer lets this one move go with the flags still open; the same flags
--      do not hold the same move again).
--      Callers (same pull request): _shared/reveal_guard.ts before any reveal is charged, accountant
--      execute_refunds before any refund reaches Stripe. Both fail CLOSED on an error, like the sanctions read.
--   4. customer_support is handed every hold and every release (fraud.money_held / fraud.money_released):
--      fn_customer_support_tells_the_customer_about_held_money writes the waiting customer one neutral e-mail
--      in their language through fn_customer_support_duty_send (once per hold, fixture addresses refused by
--      fn_email_sendable). The supplier is never told: nothing was charged to him, and a flag is not a verdict.
--   5. accountant.risk_screen (every 6 hours, fn_accountant_risk_screen_tick): all parties re-flagged,
--      every held move re-screened (so a hold whose flags were closed is released and the customer told), and
--      a hold unreviewed for 48 hours raises money_hold_unreviewed:<id> to the accountant (the one new alarm;
--      replayed on the healthy days in scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs).
--      A fixture run (set local qd.duty_fixtures = 'on') selects only demo parties.
--   6. free_email_domain, money_move_hold and fraud_flags join the daily table export.
--
-- WHAT THIS DOES NOT DO: it bans nobody and refuses no sign-up (a free webmail supplier is flagged low and
-- trades normally); it does not change the fee-circumvention watch; it does not tell a supplier anything.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql --apply --ddl
--   proved before apply by the _probe.sql beside it, in one rolled-back transaction with this file.

set local lock_timeout = '5s';

-- ── 1. free webmail, and the class of an address ────────────────────────────────────────────────────
create table if not exists public.free_email_domain (
  domain     text primary key check (domain = lower(btrim(domain)) and domain ~ '^[a-z0-9.-]+[.][a-z]{2,}$'),
  provider   text not null,
  created_at timestamptz not null default now()
);
alter table public.free_email_domain enable row level security;
drop policy if exists free_email_domain_service_role_only on public.free_email_domain;
create policy free_email_domain_service_role_only on public.free_email_domain
  as permissive for all to public using (false) with check (false);
revoke all on public.free_email_domain from anon, authenticated;
comment on table public.free_email_domain is
  'Free webmail domains. A company account signing in with one is flagged low (free_email_company) by the accountant; nothing is refused.';

insert into public.free_email_domain (domain, provider) values
  ('gmail.com', 'Google'), ('googlemail.com', 'Google'),
  ('yahoo.com', 'Yahoo'), ('yahoo.co.uk', 'Yahoo'), ('yahoo.co.in', 'Yahoo'), ('ymail.com', 'Yahoo'), ('rocketmail.com', 'Yahoo'),
  ('hotmail.com', 'Microsoft'), ('hotmail.co.uk', 'Microsoft'), ('outlook.com', 'Microsoft'), ('live.com', 'Microsoft'),
  ('msn.com', 'Microsoft'), ('windowslive.com', 'Microsoft'),
  ('icloud.com', 'Apple'), ('me.com', 'Apple'), ('mac.com', 'Apple'),
  ('aol.com', 'AOL'), ('gmx.com', 'GMX'), ('gmx.net', 'GMX'), ('mail.com', 'mail.com'),
  ('yandex.com', 'Yandex'), ('yandex.ru', 'Yandex'), ('mail.ru', 'Mail.ru'),
  ('proton.me', 'Proton'), ('protonmail.com', 'Proton'), ('zoho.com', 'Zoho (free plan)'),
  ('rediffmail.com', 'Rediff'), ('qq.com', 'Tencent'), ('163.com', 'NetEase'), ('126.com', 'NetEase'),
  ('emirates.net.ae', 'Etisalat (e&) ISP mailbox'), ('eim.ae', 'du ISP mailbox')
on conflict (domain) do nothing;

create or replace function public.fn_email_domain_class(p_email text)
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with d as (select lower(btrim(split_part(coalesce(p_email, ''), '@', 2))) as dom)
  select case
    when position('@' in coalesce(p_email, '')) = 0 or (select dom from d) = '' then null
    when exists (select 1 from public.app_blocked_domains b, d where b.domain = d.dom)
      or exists (select 1 from public.email_platform_domain e, d where e.kind = 'disposable' and e.domain = d.dom) then 'disposable'
    when exists (select 1 from public.free_email_domain f, d where f.domain = d.dom) then 'free'
    else 'company' end
$fn$;
revoke execute on function public.fn_email_domain_class(text) from public, anon, authenticated;
grant execute on function public.fn_email_domain_class(text) to service_role;

-- ── 2. the party flags ────────────────────────────────────────────────────────────────────────────────
-- p_customer / p_supplier given: that party only, whatever it is (the money screen). Both null: every party of
-- the kind the duty is running for (qd.duty_fixtures = 'on' -> demo parties only, otherwise real ones only).
create or replace function public.fn_accountant_party_flags(p_customer uuid default null, p_supplier bigint default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_all boolean := p_customer is null and p_supplier is null;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_new int := 0; v_raised int := 0;
begin
  create temp table if not exists tmp_party_flag (kind text, subject_type text, subject_id text, severity text, detail jsonb) on commit drop;
  truncate tmp_party_flag;

  -- ── suppliers ──
  with s as (
    select l.id, l.company_name, l.licence_legal_name, l as lrow,
           lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email, ''))) as acct,
           lower(regexp_replace(btrim(coalesce(l.domain, '')), '^(https?://)?(www[.])?', '')) as site
      from public.leads l
     where (v_all and (coalesce(l.claimed, false) or l.lifecycle_stage = 'registered' or l.approval_status is not null)
                  and not coalesce(l.banned, false)
                  and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx)
        or l.id = p_supplier
  ), c as (
    select s.*, public.fn_email_domain_class(s.acct) as cls, split_part(s.acct, '@', 2) as edom from s
  )
  insert into tmp_party_flag
  select 'company_name_mismatch', 'lead', c.id::text, 'high',
         jsonb_build_object('company_name', c.company_name, 'licence_legal_name', c.licence_legal_name)
    from c where public.fn_supplier_licence_name_mismatch(c.lrow)
  union all
  select 'disposable_email', 'lead', c.id::text, 'high', jsonb_build_object('account_email_domain', c.edom)
    from c where c.cls = 'disposable'
  union all
  select 'free_email_company', 'lead', c.id::text, 'low', jsonb_build_object('account_email_domain', c.edom, 'company_name', c.company_name)
    from c where c.cls = 'free'
  union all
  -- The website must be the company's OWN domain: a directory, host or marketplace page (email_platform_domain)
  -- says nothing about which domain the company mails from. A subdomain either way is the same company.
  select 'email_domain_mismatch', 'lead', c.id::text, 'medium',
         jsonb_build_object('account_email_domain', c.edom, 'website_domain', c.site, 'company_name', c.company_name)
    from c where c.cls = 'company' and c.site ~ '[.]' and c.edom <> c.site
     and c.edom not like '%.' || c.site and c.site not like '%.' || c.edom
     and not exists (select 1 from public.email_platform_domain e where e.domain in (c.site, c.edom))
  union all
  select 'dispute_pattern', 'lead', x.id::text, case when x.n >= 3 then 'high' else 'medium' end,
         jsonb_build_object('disputes_90d', x.d, 'refunds_paid_90d', x.r, 'window_days', 90)
    from (select c.id,
                 (select count(*) from public.post_reveal_dispute p where p.supplier_id = c.id and p.opened_at > now() - interval '90 days') as d,
                 (select count(*) from public.transactions t where t.supplier_id = c.id and t.refund_confirmed_at > now() - interval '90 days') as r,
                 (select count(*) from public.post_reveal_dispute p where p.supplier_id = c.id and p.opened_at > now() - interval '90 days')
                 + (select count(*) from public.transactions t where t.supplier_id = c.id and t.refund_confirmed_at > now() - interval '90 days') as n
            from c) x
   where x.n >= 2;

  -- ── customers ──
  with k as (
    select cu.* from public.customers cu
     where (v_all and not coalesce(cu.banned, false) and (coalesce(cu.is_demo, false) or public.fn_is_demo_email(cu.email)) = v_fx)
        or cu.id = p_customer
  )
  insert into tmp_party_flag
  select 'disposable_email', 'customer', k.id::text, 'high', jsonb_build_object('email_domain', split_part(lower(k.email), '@', 2))
    from k where public.fn_email_domain_class(k.email) = 'disposable'
  union all
  select 'refund_pattern', 'customer', x.id::text, case when x.n >= 3 then 'high' else 'medium' end,
         jsonb_build_object('refund_requests_90d', x.n, 'window_days', 90)
    from (select k.id, (select count(*) from public.transactions t
                         where t.customer_id = k.id and t.refund_requested_at > now() - interval '90 days') as n from k) x
   where x.n >= 2
  union all
  select 'dispute_pattern', 'customer', x.id::text, case when x.cb > 0 or x.d >= 3 then 'high' else 'medium' end,
         jsonb_build_object('chargebacks_180d', x.cb, 'disputes_raised_90d', x.d)
    from (select k.id,
                 (select count(*) from public.stripe_dispute sd join public.transactions t on t.id = sd.transaction_id
                   where t.customer_id = k.id and sd.first_seen_at > now() - interval '180 days') as cb,
                 (select count(*) from public.post_reveal_dispute p
                   where p.customer_id = k.id and p.raised_by = 'customer' and p.opened_at > now() - interval '90 days') as d
            from k) x
   where x.cb > 0 or x.d >= 2;

  -- ── write: once per (kind, subject); a closed flag stays closed; an OPEN flag whose severity rose is raised ──
  with ins as (
    insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail, status, created_at, updated_at)
    select kind, subject_type, subject_id, severity,
           detail || jsonb_build_object('raised_by', 'accountant', 'owner_seat', 'accountant'), 'open', now(), now()
      from tmp_party_flag
    on conflict (kind, subject_type, subject_id) do nothing
    returning 1)
  select count(*) into v_new from ins;
  with up as (
    update public.fraud_flags f
       set severity = t.severity, detail = f.detail || t.detail || jsonb_build_object('severity_raised_at', now()), updated_at = now()
      from tmp_party_flag t
     where f.kind = t.kind and f.subject_type = t.subject_type and f.subject_id = t.subject_id and f.status = 'open'
       and array_position(array['low', 'medium', 'high'], t.severity) > coalesce(array_position(array['low', 'medium', 'high'], f.severity), 0)
    returning 1)
  select count(*) into v_raised from up;
  return jsonb_build_object('flagged', (select count(*) from tmp_party_flag), 'new', v_new, 'severity_raised', v_raised);
end $fn$;
revoke execute on function public.fn_accountant_party_flags(uuid, bigint) from public, anon, authenticated;
grant execute on function public.fn_accountant_party_flags(uuid, bigint) to service_role;

-- Every open or escalated flag that touches this customer or this supplier: their own flags, and the flags of
-- the fee-circumvention watch that name them inside detail (duplicate licence / TRN lists, the customer a
-- supplier also is, a transaction's two parties).
create or replace function public.fn_accountant_flags_touching(p_customer uuid, p_supplier bigint)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('key', f.kind || ':' || f.subject_type || ':' || f.subject_id,
           'kind', f.kind, 'subject_type', f.subject_type, 'subject_id', f.subject_id, 'severity', f.severity,
           'status', f.status, 'party', case when (f.subject_type = 'customer' and f.subject_id = p_customer::text)
                                                or f.detail->'customer_ids' ? coalesce(p_customer::text, '')
                                                or f.detail->>'customer_id' = p_customer::text then 'customer' else 'supplier' end)
           order by f.kind, f.subject_type, f.subject_id), '[]'::jsonb)
    from public.fraud_flags f
   where f.status in ('open', 'escalated')
     and ((p_customer is not null and ((f.subject_type = 'customer' and f.subject_id = p_customer::text)
                                        or f.detail->'customer_ids' ? p_customer::text
                                        or f.detail->>'customer_id' = p_customer::text))
       or (p_supplier is not null and ((f.subject_type in ('lead', 'supplier') and f.subject_id = p_supplier::text)
                                        or f.detail->'lead_ids' @> to_jsonb(p_supplier)
                                        or f.detail->>'supplier_id' = p_supplier::text
                                        or f.detail->>'hired_supplier_id' = p_supplier::text)))
$fn$;
revoke execute on function public.fn_accountant_flags_touching(uuid, bigint) from public, anon, authenticated;
grant execute on function public.fn_accountant_flags_touching(uuid, bigint) to service_role;

-- ── 3. the hold, and the screen before money moves ──────────────────────────────────────────────────────
create table if not exists public.money_move_hold (
  id             bigint generated always as identity primary key,
  move           text not null check (move in ('reveal', 'refund')),
  ref            text not null check (btrim(ref) <> ''),
  customer_id    uuid,
  supplier_id    bigint,
  status         text not null check (status in ('noted', 'held', 'released')),
  flag_keys      text[] not null default '{}',
  flags          jsonb not null default '[]'::jsonb,
  opened_at      timestamptz not null default now(),
  screened_at    timestamptz not null default now(),
  released_at    timestamptz,
  released_by    text,
  release_reason text,
  check ((status = 'released') = (released_at is not null)),
  check (status <> 'released' or btrim(coalesce(released_by, '')) <> '')
);
create unique index if not exists money_move_hold_one_open_per_move
  on public.money_move_hold (move, ref) where status <> 'released';
create index if not exists money_move_hold_held on public.money_move_hold (opened_at) where status = 'held';
alter table public.money_move_hold enable row level security;
drop policy if exists money_move_hold_service_role_only on public.money_move_hold;
create policy money_move_hold_service_role_only on public.money_move_hold
  as permissive for all to public using (false) with check (false);
revoke all on public.money_move_hold from anon, authenticated;
comment on table public.money_move_hold is
  'The accountant''s screen before money moves (fn_accountant_money_screen): held = a high-severity flag touches the customer or the supplier and the reveal or refund waits for review; noted = lower flags, the money moved. Released by the flags being closed (fn_fraud_resolve) or by fn_money_move_hold_release. No ban is ever automatic.';

create or replace function public.fn_accountant_money_screen(p_move text, p_ref text, p_customer uuid, p_supplier bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_flags jsonb; v_high jsonb; v_keys text[]; h public.money_move_hold; v_id bigint;
begin
  if p_move is null or p_move not in ('reveal', 'refund') then raise exception 'a money screen names its move (reveal or refund), not %', p_move; end if;
  if coalesce(btrim(p_ref), '') = '' then raise exception 'a money screen names what is moving (the quote or the refund)'; end if;

  -- NOW, not at the next tick: a disposable address or a third refund request is seen before this money moves.
  perform public.fn_accountant_party_flags(p_customer, null) where p_customer is not null;
  perform public.fn_accountant_party_flags(null, p_supplier) where p_supplier is not null;
  v_flags := public.fn_accountant_flags_touching(p_customer, p_supplier);
  select coalesce(jsonb_agg(e.f), '[]'::jsonb), coalesce(array_agg(e.f->>'key' order by e.f->>'key'), '{}')
    into v_high, v_keys from jsonb_array_elements(v_flags) as e(f) where e.f->>'severity' = 'high';

  select * into h from public.money_move_hold where move = p_move and ref = p_ref and status <> 'released' for update;

  if jsonb_array_length(v_high) = 0 then
    if h.status = 'held' then
      update public.money_move_hold set status = 'released', released_at = now(), released_by = 'screen', screened_at = now(),
             release_reason = 'no open high-severity flag touches either party any more', flags = v_flags
       where id = h.id;
      perform public.fn_seat_handoff('accountant', 'customer_support', 'fraud.money_released', 'money_move_hold', h.id::text,
        jsonb_build_object('hold_id', h.id, 'move', p_move, 'ref', p_ref));
      return jsonb_build_object('hold', false, 'released', h.id, 'flags', v_flags);
    end if;
    if jsonb_array_length(v_flags) > 0 then
      insert into public.money_move_hold (move, ref, customer_id, supplier_id, status, flag_keys, flags)
      values (p_move, p_ref, p_customer, p_supplier, 'noted',
              (select array_agg(e.f->>'key' order by e.f->>'key') from jsonb_array_elements(v_flags) as e(f)), v_flags)
      on conflict (move, ref) where status <> 'released'
      do update set flags = excluded.flags, flag_keys = excluded.flag_keys, screened_at = now()
      returning id into v_id;
    end if;
    return jsonb_build_object('hold', false, 'noted', v_id, 'flags', v_flags);
  end if;

  -- A reviewer already let THIS move go with these very flags open: the same flags do not hold it twice.
  if exists (select 1 from public.money_move_hold r where r.move = p_move and r.ref = p_ref and r.status = 'released'
                and r.released_by <> 'screen' and r.flag_keys @> v_keys) then
    return jsonb_build_object('hold', false, 'reviewed', true, 'flags', v_flags);
  end if;

  if h.id is null then
    insert into public.money_move_hold (move, ref, customer_id, supplier_id, status, flag_keys, flags)
    values (p_move, p_ref, p_customer, p_supplier, 'held', v_keys, v_flags)
    on conflict (move, ref) where status <> 'released' do nothing
    returning id into v_id;
    if v_id is null then  -- a concurrent screen of the same move wrote the row first; answer as it did
      select * into h from public.money_move_hold where move = p_move and ref = p_ref and status <> 'released';
      return jsonb_build_object('hold', h.status = 'held', 'hold_id', h.id, 'flags', h.flags);
    end if;
  else
    v_id := h.id;
    update public.money_move_hold set status = 'held', flag_keys = v_keys, flags = v_flags, screened_at = now(),
           opened_at = case when h.status = 'held' then h.opened_at else now() end
     where id = h.id;
  end if;
  if h.id is null or h.status <> 'held' then
    perform public.fn_seat_handoff('accountant', 'customer_support', 'fraud.money_held', 'money_move_hold', v_id::text,
      jsonb_build_object('hold_id', v_id, 'move', p_move, 'ref', p_ref));
  end if;
  return jsonb_build_object('hold', true, 'hold_id', v_id, 'flags', v_flags);
end $fn$;
revoke execute on function public.fn_accountant_money_screen(text, text, uuid, bigint) from public, anon, authenticated;
grant execute on function public.fn_accountant_money_screen(text, text, uuid, bigint) to service_role;

-- A reviewer lets one held move go with its flags still open (the flags stay for the CEO; nobody is banned).
create or replace function public.fn_money_move_hold_release(p_hold_id bigint, p_by text, p_note text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.money_move_hold;
begin
  if coalesce(btrim(p_by), '') in ('', 'screen') then raise exception 'a release names the person or seat who reviewed it'; end if;
  if coalesce(btrim(p_note), '') = '' then raise exception 'a release says why the money may move'; end if;
  select * into h from public.money_move_hold where id = p_hold_id for update;
  if not found then raise exception 'no money hold %', p_hold_id; end if;
  if h.status <> 'held' then return jsonb_build_object('released', false, 'reason', 'the move is ' || h.status || ', not held'); end if;
  update public.money_move_hold set status = 'released', released_at = now(), released_by = btrim(p_by), release_reason = btrim(p_note)
   where id = h.id;
  perform public.fn_seat_handoff('accountant', 'customer_support', 'fraud.money_released', 'money_move_hold', h.id::text,
    jsonb_build_object('hold_id', h.id, 'move', h.move, 'ref', h.ref));
  return jsonb_build_object('released', true, 'hold_id', h.id);
end $fn$;
revoke execute on function public.fn_money_move_hold_release(bigint, text, text) from public, anon, authenticated;
grant execute on function public.fn_money_move_hold_release(bigint, text, text) to service_role;

-- ── 4. customer_support tells the waiting customer ───────────────────────────────────────────────────────
-- The words, apart from the sending, so a probe can read exactly what the customer would be told.
create or replace function public.fn_customer_support_held_money_message(p_hold_id bigint, p_type text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  h public.money_move_hold; c public.customers; v_type text := p_type; v_ar boolean; v_name text;
  v_rfq text; v_inq uuid; v_subj text; v_body text;
begin
  if p_type not in ('fraud.money_held', 'fraud.money_released') then raise exception 'no money-hold message of type %', p_type; end if;
  select * into h from public.money_move_hold where id = p_hold_id;
  if not found then return jsonb_build_object('not_sent', 'the hold no longer exists'); end if;
  select * into c from public.customers where id = h.customer_id;
  if not found then return jsonb_build_object('not_sent', 'no customer waits on this move'); end if;
  -- The request the customer knows: the quote's request for a reveal, the refund's request for a refund.
  -- A refund row may carry no inquiry_id: its transaction's request is the one the customer knows, so the
  -- reference is never blank (re-review of #1110).
  if h.move = 'reveal' then
    select q.inquiry_id into v_inq from public.quotes q where q.id::text = h.ref;
  else
    select coalesce(r.inquiry_id, t.inquiry_id) into v_inq
      from public.refunds r left join public.transactions t on t.id = r.transaction_id where r.id::text = h.ref;
  end if;
  if v_inq is not null then v_rfq := 'QD-' || public.fn_job_no(v_inq); end if;
  -- The request's own language first (founder, 28 Sep 2026: every message about a request is in the language it
  -- was made in), the registered one otherwise.
  v_ar := coalesce(public.fn_inquiry_locale(v_inq), c.locale) = 'ar';
  v_name := coalesce(nullif(btrim(c.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);

  if v_type = 'fraud.money_held' and h.move = 'reveal' then
    v_subj := case when v_ar then 'طلب الكشف قيد المراجعة' else 'Your reveal is being checked' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'قبل كشف أي مورّد نُجري تحققًا اعتياديًا على الحسابات المعنية، ويحتاج أحد هذه التحققات إلى مراجعة من أحد موظفينا، لذا أوقفنا مؤقتًا كشف المورّد على الطلب '
        || coalesce(v_rfq, '') || '، ولم يُخصم منكم أي مبلغ.' || chr(10) || chr(10)
        || 'لا يلزمكم أي إجراء. سنراسلكم فور اكتمال المراجعة، وعادةً خلال يومي عمل، وبعدها يمكنكم كشف المورّد كالمعتاد.' || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Before a supplier is revealed we run a routine check on the accounts involved, and one of those checks needs a person to look at it. The reveal on request '
        || coalesce(v_rfq, '') || ' is paused until then, and you have not been charged.' || chr(10) || chr(10)
        || 'Nothing is needed from you. We will write as soon as the check is complete, normally within two working days, and you can then reveal the supplier as usual.' || chr(10) || chr(10)
        || 'If you have a question, reply to this e-mail.' end;
  elsif v_type = 'fraud.money_held' then
    v_subj := case when v_ar then 'طلب الاسترداد قيد المراجعة' else 'Your refund is being checked' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'قبل صرف أي مبلغ مسترد نُجري تحققًا اعتياديًا على الحسابات المعنية، ويحتاج أحد هذه التحققات إلى مراجعة من أحد موظفينا، لذا أوقفنا مؤقتًا صرف المبلغ المسترد على الطلب '
        || coalesce(v_rfq, '') || ' حتى تكتمل المراجعة.' || chr(10) || chr(10)
        || 'لا يلزمكم أي إجراء. سنراسلكم فور اكتمال المراجعة، وعادةً خلال يومي عمل.' || chr(10) || chr(10)
        || 'ولأي استفسار، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Before a refund is paid we run a routine check on the accounts involved, and one of those checks needs a person to look at it. The refund on request '
        || coalesce(v_rfq, '') || ' is paused until the check is complete.' || chr(10) || chr(10)
        || 'Nothing is needed from you. We will write as soon as the check is complete, normally within two working days.' || chr(10) || chr(10)
        || 'If you have a question, reply to this e-mail.' end;
  elsif h.move = 'reveal' then
    v_subj := case when v_ar then 'يمكنكم الآن كشف المورّد' else 'You can now reveal the supplier' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'اكتملت المراجعة، ويمكنكم الآن كشف المورّد على الطلب ' || coalesce(v_rfq, '') || ' من حسابكم: https://quotesdone.com/ar/me' || chr(10) || chr(10)
        || 'شكرًا لصبركم.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'The check is complete. You can now reveal the supplier on request ' || coalesce(v_rfq, '') || ' from your account: https://quotesdone.com/me' || chr(10) || chr(10)
        || 'Thank you for your patience.' end;
  else
    v_subj := case when v_ar then 'اكتملت مراجعة طلب الاسترداد' else 'The check on your refund is complete' end;
    v_body := case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'اكتملت المراجعة، ويواصل طلب الاسترداد على الطلب ' || coalesce(v_rfq, '') || ' مساره المعتاد، وسنؤكد لكم فور صرف المبلغ.' || chr(10) || chr(10)
        || 'شكرًا لصبركم.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'The check is complete, and the refund on request ' || coalesce(v_rfq, '') || ' continues through the usual process. We will confirm as soon as it is paid.' || chr(10) || chr(10)
        || 'Thank you for your patience.' end;
  end if;

  return jsonb_build_object('lang', case when v_ar then 'ar' else 'en' end, 'subject', v_subj, 'body', v_body, 'ref', v_rfq,
                            'inquiry_id', v_inq, 'customer_id', c.id, 'email', c.email, 'hold_id', h.id, 'move', h.move);
end $fn$;
revoke execute on function public.fn_customer_support_held_money_message(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_customer_support_held_money_message(bigint, text) to service_role;

create or replace function public.fn_customer_support_tells_the_customer_about_held_money(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; m jsonb; v_res jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff'
     and detail->>'type' in ('fraud.money_held', 'fraud.money_released');
  if not found then raise exception 'fn_customer_support_tells_the_customer_about_held_money: % is not a money-hold handoff', p_id; end if;
  m := public.fn_customer_support_held_money_message((a.detail->>'hold_id')::bigint, a.detail->>'type');
  if m ? 'not_sent' then return m; end if;
  -- The stage is the handoff type ('fraud.money_held' / 'fraud.money_released'): once per hold, per stage.
  v_res := public.fn_customer_support_duty_send(a.detail->>'type', m->>'hold_id', 'customer', m->>'email',
    m->>'lang', m->>'subject', m->>'body', (m->>'customer_id')::uuid, null, (m->>'inquiry_id')::uuid);
  return v_res || jsonb_build_object('hold_id', (m->>'hold_id')::bigint, 'move', m->>'move', 'lang', m->>'lang', 'ref', m->>'ref');
end $fn$;
revoke execute on function public.fn_customer_support_tells_the_customer_about_held_money(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('fraud.money_held', 'accountant', 'customer_support',
   'The accountant''s screen held a reveal or a refund because a high-severity fraud flag touches the customer or the supplier. customer_support tells the waiting customer, in their language, that the money is paused for a routine check and nothing is needed from them. The supplier is never told.',
   'fn_customer_support_tells_the_customer_about_held_money', null, false,
   'scripts/sql/the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql'),
  ('fraud.money_released', 'accountant', 'customer_support',
   'A held reveal or refund was released (its flags were closed, or a reviewer let it go). customer_support tells the customer they can reveal now, or that the refund continues.',
   'fn_customer_support_tells_the_customer_about_held_money', null, false,
   'scripts/sql/the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql')
on conflict (type, from_seat, to_seat) do update
   set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within,
       originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ── 5. the duty ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_risk_screen_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_flags jsonb; h record; v_rescreened int := 0; v_released int := 0; v_overdue int := 0; v jsonb;
begin
  v_flags := public.fn_accountant_party_flags(null, null);

  for h in select m.id, m.move, m.ref, m.customer_id, m.supplier_id, m.opened_at, m.flag_keys
             from public.money_move_hold m left join public.customers c on c.id = m.customer_id
            where m.status = 'held'
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by m.id loop
    v := public.fn_accountant_money_screen(h.move, h.ref, h.customer_id, h.supplier_id);
    v_rescreened := v_rescreened + 1;
    if not coalesce((v->>'hold')::boolean, false) then v_released := v_released + 1; continue; end if;
    if h.opened_at < now() - interval '48 hours' then
      v_overdue := v_overdue + 1;
      perform public.fn_it_engineer_finding_upsert('money_hold_unreviewed:' || h.id,
        left('A held ' || h.move || ' has waited ' || extract(day from now() - h.opened_at)::int || ' days for a fraud review', 300),
        'public.money_move_hold / fn_accountant_money_screen', 'agent_facing', 1,
        jsonb_build_object('hold_id', h.id, 'move', h.move, 'ref', h.ref, 'opened_at', h.opened_at, 'flags', to_jsonb(h.flag_keys),
                           'owner_seat', 'accountant',
                           'fix', 'review the flags in the fraud workspace: fn_fraud_resolve dismisses or bans; fn_money_move_hold_release lets this one move go'),
        '{}'::text[], array['whether the flags that hold this money are real'], 'accountant');
    end if;
  end loop;

  update public.it_engineer_finding f set closed_at = now(), close_note = 'the held money was released'
   where f.issue_key like 'money_hold_unreviewed:%' and f.closed_at is null
     and exists (select 1 from public.money_move_hold m where m.id::text = split_part(f.issue_key, ':', 2) and m.status <> 'held');

  return v_flags || jsonb_build_object('holds_rescreened', v_rescreened, 'holds_released', v_released, 'holds_overdue', v_overdue);
end $fn$;
revoke execute on function public.fn_accountant_risk_screen_tick() from public, anon, authenticated;
grant execute on function public.fn_accountant_risk_screen_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.risk_screen', 'accountant', interval '6 hours', 'fn_accountant_risk_screen_tick',
   'every party flagged for mismatched company details, disposable or free e-mail and refund or dispute patterns; every held reveal or refund re-screened; a hold unreviewed for 48 hours is a finding',
   'scripts/sql/the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- ── 6. the daily table export ─────────────────────────────────────────────────────────────────────────
-- Redefined from #1108's body (a_quote_is_checked_for_specs_prices_and_terms_before_the_customer_sees_it.sql at
-- cc78eaa: #1106's list, itself main's plus #1105's stalled_inquiry_rescue, plus quote_quality_hold), with only
-- fraud_flags, money_move_hold and free_email_domain added here, and supplier_availability: #1105 (applied) created it
-- without listing it, the live list (152 rows on 29 Sep 2026) does not name it, and no file in the #1105-#1106-#1108
-- chain adds it, so this last file in the chain does. It has no *_path column, so fn_backup_source_registry is unchanged. Depends-on: #1108 (and through it #1106 and #1105):
-- apply it first, so every table this list names exists when it is applied.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('stalled_inquiry_rescue','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'), ('quote_quality_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'), ('seat_handoff_kind','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_calendar_resend_decision','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('marketing_recruitment_source','marketing'), ('marketing_gap_recruitment_plan','marketing'), ('marketing_plan_doc','marketing'),
    ('fraud_flags','risk'), ('money_move_hold','risk'), ('free_email_domain','risk'),
    ('supplier_availability','supplier'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

