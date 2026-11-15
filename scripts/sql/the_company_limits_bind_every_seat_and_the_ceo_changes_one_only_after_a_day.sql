-- THE COMPANY LIMITS BIND EVERY MONEY ACTION THE AUTHORITY CHECK ALLOWS, AND THE CEO CHANGES ONE ONLY AFTER A DAY. Seat: ceo.
-- 15 Nov 2026. (The file name says "every seat"; what is bound is exactly this: every money action a seat or the CEO takes
-- through fn_agent_may_act. The subject-aware form commits it against the limits; the three-argument form refuses money,
-- refunds excepted, and points the caller at the subject-aware form. NOT bound here: the refund path, the ad platforms' own
-- caps and model spend; see WHAT THIS DOES NOT CHANGE.)
-- Founder, ledger 1696 (15 Nov 2026): "CEO is having full authority. He can do whatever is needed to achieve the target we
-- have for the company. He doesnt rely on me in anything. He is fully responsible about his decisions and their outcomes".
-- Founder, ledger 1701 (15 Nov 2026): "I want to be profitable and that should be the main concern for the CEO ... i want him
-- to be able to take actions and give tasks to the agent".
--
-- WHAT WAS THERE (read from the branch every_seat_reads_one_pool_and_every_hand_over_comes_back, third review of 15 Nov):
--   * the authority path asked the FOUNDER (ask_founder, needs_founder:*) for money, a person's data or a switch; ruling 1696
--     removes the founder from every decision. What stays is a set of HARD LIMITS the CEO's own decisions cannot pass.
--   * review 3, item 1 (LOCAL): a CEO grant with no amount let marketing spend AED 10,000 once; nothing counted what the
--     company had already committed that day.
--   * the only daily money cap in the estate is public.ad_spend_policy (SELECT 15 Nov 2026, row 'default': daily_cap_aed 30,
--     max_daily_per_campaign_aed 30, monthly_cap_aed null). It binds the ad platforms only.
-- WHAT THIS ADDS (data, read by code; never a sentence in a prompt):
--   1. public.company_limit_change: the company's spending limits as an append-only history. Two limits:
--        daily_spend_aed   what all seats together may commit in one Dubai day through the authority check;
--        per_action_aed    what one action may commit.
--      THE FIRST VALUE of a limit takes effect at once (the seed below); EVERY LATER CHANGE takes effect 24 hours after it is
--      written, whatever the writer asked, and carries a written reason (20 characters or more). A row is never updated or
--      deleted. fn_company_limit(key) is the value in force NOW, so nothing lets any seat exceed the current value while a
--      change waits. The CEO changes a limit through fn_ceo_sets_company_limit (one waiting change per limit); the change and
--      its reason are in the founder's daily summary (information, not approval:
--      the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql).
--   2. public.company_spend_commitment: every AED a seat commits through the authority check, by Dubai day. The check and the
--      write are one step under one advisory lock (fn_company_spend_commit), so two sessions can never both fit the last
--      dirham of the day.
--   3. The classifiers the authority check uses: a money action (by its NAME, so an ask with no amount is still money: review 3,
--      item 1), a destructive production change (it stays outside the authority check: ruling 1696 as settled on 15 Nov, "the
--      IT engineer's refusals and questions now go to the CEO, EXCEPT a destructive production deploy"), and an action that
--      would weaken a message gate.
--   4. fn_company_message_gates: the existing consent, suppression, opt-out and inbox-placement gates, read for ONE named
--      recipient, so a CEO decision can never let a seat message a person those gates refuse. The gates themselves are not
--      changed: fn_email_sendable (suppressions, address shape, dead domain, block patterns), fn_invite_placement_open_providers
--      (public.invite_placement_bar; never Microsoft or Yahoo/AOL, founder_instruction 1537), the lead's own opt-out
--      (leads.invite_status complained/unsubscribed) and the WhatsApp opt-in (public.supplier_whatsapp_optin, fn_wa_optin_rule,
--      ledger 1341). The senders keep enforcing them; this is the same reading made BEFORE a decision.
-- SEED: the two limits start at public.ad_spend_policy's 'default' row as it is at apply (daily_cap_aed and
-- max_daily_per_campaign_aed; AED 30 and AED 30 on 15 Nov 2026), else AED 30: the one daily money limit the company already
-- runs, so the CEO's new authority starts no looser than the ads he could already buy. He raises it, with a reason, a day later.
-- WHAT THIS DOES NOT CHANGE: public.ad_spend_policy and the ad platforms' own caps; the refund path (the accountant prepares,
-- fn_ceo_request_decision and ceo_agent review_refund decide: returning a customer's own fee is not company spending); the
-- three-argument fn_agent_may_act (its callers keep their own ceilings: refund 0, meta_ads_spend 0); model spend (OpenRouter's
-- cap, memory: never-raise-openrouter-again). Only the subject-aware authority check and the CEO's orders read these limits.
-- prevented by: scripts/checks/the_ceo_acts_within_company_limits.test.mjs (text), the probe
-- the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day_probe.sql (LOCAL, every rule executed)
-- APPLY ORDER: this file, then every_seat_reads_one_pool_and_every_hand_over_comes_back.sql (its authority check reads these),
-- then the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql.
-- LOCKS: two new tables and routines only; nothing here touches a busy table.
set local lock_timeout = '1500ms';

-- ── 1. THE LIMITS: append-only, the first value at once, every later change a day later ─────────────────────────────
create table if not exists public.company_limit_change (
  id bigserial primary key,
  limit_key text not null check (limit_key in ('daily_spend_aed', 'per_action_aed')),
  value_aed numeric(12,2) not null check (value_aed >= 0 and value_aed <= 1000000),
  reason text not null check (length(btrim(reason)) >= 20),
  set_by text not null check (set_by in ('ceo', 'seed')),
  set_at timestamptz not null default now(),
  effective_at timestamptz not null);
comment on table public.company_limit_change is 'The company''s spending limits (founder ledger 1696): append-only; the first value of a limit is in force at once, every later change 24 hours after it is written; fn_company_limit(key) is the value in force now. the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql';

create or replace function public.trg_company_limit_change_waits_a_day()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if tg_op <> 'INSERT' then
    raise exception 'company_limit_change is append-only: a limit is changed by a new row (fn_ceo_sets_company_limit), never edited';
  end if;
  -- review 4, item 2: under REPEATABLE READ or SERIALIZABLE the check below reads the transaction's old snapshot, so two
  -- writers could both see "nothing waits"; only READ COMMITTED gives each statement a fresh one after the lock
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'a company limit is changed only under READ COMMITTED (this transaction is %)', current_setting('transaction_isolation');
  end if;
  perform pg_advisory_xact_lock(hashtext('qd.company_limit_change:' || new.limit_key));   -- one writer per limit at a time
  -- clock_timestamp, not now(): a row written late in a long transaction would otherwise wait less than a day (review 4, item 1)
  new.set_at := clock_timestamp();
  if exists (select 1 from public.company_limit_change c where c.limit_key = new.limit_key) then
    if new.set_by <> 'ceo' then raise exception 'only the CEO changes a company limit once it exists'; end if;
    if exists (select 1 from public.company_limit_change c where c.limit_key = new.limit_key and c.effective_at > clock_timestamp()) then
      raise exception 'a change of % already waits; it takes effect first (one waiting change per limit)', new.limit_key;
    end if;
    new.effective_at := clock_timestamp() + interval '24 hours';   -- whatever the writer asked: a change waits a day
  else
    new.effective_at := now();   -- the first value of a limit is in force at once (now(): also inside the transaction that wrote it)
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_company_limit_change_waits_a_day() from public, anon, authenticated;
-- CREATE OR REPLACE TRIGGER (SHARE ROW EXCLUSIVE), not drop and create (ACCESS EXCLUSIVE on every re-run, measured LOCAL): the
-- authority check reads this table on every money decision
create or replace trigger trg_company_limit_change_waits_a_day before insert or update or delete on public.company_limit_change
  for each row execute function public.trg_company_limit_change_waits_a_day();

-- A TRUNCATE fires no row trigger: without this, the next row after one would count as a "first value", in force at once
-- (review 4, item 1, LOCAL: truncate + insert put both limits at AED 100,000 at once).
create or replace function public.trg_company_limits_refuse_truncate()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  raise exception '% is append-only: it is never truncated', tg_table_name;
end $fn$;
revoke execute on function public.trg_company_limits_refuse_truncate() from public, anon, authenticated;
create or replace trigger trg_company_limit_change_no_truncate before truncate on public.company_limit_change
  for each statement execute function public.trg_company_limits_refuse_truncate();

create table if not exists public.company_spend_commitment (
  id bigserial primary key,
  seat text not null,
  action_class text not null,
  subject text not null,
  amount_aed numeric(12,2) not null check (amount_aed > 0),
  route text not null,
  grant_once_id bigint,
  dubai_day date not null default ((now() at time zone 'Asia/Dubai')::date),
  committed_at timestamptz not null default now());
comment on table public.company_spend_commitment is 'Every AED a seat commits through the subject-aware authority check, by Dubai day; fn_company_spend_commit checks the per-action and daily limits and writes the row under one lock. the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql';

do $guard$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.company_limit_change'::regclass) then
    alter table public.company_limit_change enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'company_limit_change' and policyname = 'company_limit_change_service_role_only') then
    create policy company_limit_change_service_role_only on public.company_limit_change as permissive for all to public using (false) with check (false);
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.company_spend_commitment'::regclass) then
    alter table public.company_spend_commitment enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'company_spend_commitment' and policyname = 'company_spend_commitment_service_role_only') then
    create policy company_spend_commitment_service_role_only on public.company_spend_commitment as permissive for all to public using (false) with check (false);
  end if;
end $guard$;
revoke all on public.company_limit_change from anon, authenticated;
revoke all on public.company_spend_commitment from anon, authenticated;
-- Review 4, item 1 (LOCAL, production's grants copied): service_role holds arwdDxtm by the default ACL and bypasses RLS, so any
-- edge function could delete today's commitments or write a limit row through PostgREST. The seats read; only the SECURITY
-- DEFINER routines of this file write (fn_ceo_sets_company_limit, fn_company_spend_commit).
revoke insert, update, delete, truncate on public.company_limit_change from service_role;
revoke insert, update, delete, truncate on public.company_spend_commitment from service_role;
revoke usage, update on sequence public.company_limit_change_id_seq, public.company_spend_commitment_id_seq from service_role;

-- Commitments are append-only too: a deleted commitment would give today's money back. A probe that always rolls back may clear
-- its own day as the table owner (service_role holds no DELETE), by setting qd.limits_probe = 'rollback' for its transaction.
create or replace function public.trg_company_spend_commitment_append_only()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(current_setting('qd.limits_probe', true), '') = 'rollback' and session_user not in ('service_role', 'authenticator', 'anon', 'authenticated') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'company_spend_commitment is append-only: a commitment is never edited, deleted or truncated';
end $fn$;
revoke execute on function public.trg_company_spend_commitment_append_only() from public, anon, authenticated;
create or replace trigger trg_company_spend_commitment_append_only before update or delete on public.company_spend_commitment
  for each row execute function public.trg_company_spend_commitment_append_only();
create or replace trigger trg_company_spend_commitment_no_truncate before truncate on public.company_spend_commitment
  for each statement execute function public.trg_company_limits_refuse_truncate();
revoke all on sequence public.company_limit_change_id_seq from anon, authenticated;
revoke all on sequence public.company_spend_commitment_id_seq from anon, authenticated;

-- The value in force NOW (a waiting change is not in force). Null only for a key that was never set.
create or replace function public.fn_company_limit(p_key text)
returns numeric language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select c.value_aed from public.company_limit_change c
   where c.limit_key = p_key and c.effective_at <= now()
   order by c.effective_at desc, c.id desc limit 1
$fn$;
revoke execute on function public.fn_company_limit(text) from public, anon, authenticated;

-- Both limits as the CEO and the founder read them: in force, waiting, and what is committed today.
create or replace function public.fn_company_limits()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'daily_spend_aed', public.fn_company_limit('daily_spend_aed'), 'per_action_aed', public.fn_company_limit('per_action_aed'),
    'spent_today_aed', coalesce((select sum(s.amount_aed) from public.company_spend_commitment s
                                  where s.dubai_day = (now() at time zone 'Asia/Dubai')::date), 0),
    'waiting', coalesce((select jsonb_agg(jsonb_build_object('limit', c.limit_key, 'value_aed', c.value_aed, 'reason', c.reason,
                                  'set_at', c.set_at, 'effective_at', c.effective_at) order by c.id)
                           from public.company_limit_change c where c.effective_at > now()), '[]'::jsonb))
$fn$;
revoke execute on function public.fn_company_limits() from public, anon, authenticated;

-- ── 2. WHAT KIND OF ACTION IT IS (by name: an ask with no amount is still money) ─────────────────────────────────
create or replace function public.fn_action_is_money(p_action_class text)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  -- word-anchored where a short word would catch another ('fee' in feedback, 'pay' in payload, 'buy' in buyer); in a Postgres
  -- regex the underscore is a word character, so meta_ads_spend is caught by 'spend' and ad_spend by 'spend'
  select lower(coalesce(p_action_class, '')) ~ '(spend|\mads?\M|budget|\mpay(ment|out)?s?\M|payout|refund|discount|credit\M|credits\M|\mfees?\M|price|pricing|money|purchase|\mbuy\M|invoice|write_?off|charge|subscription|voucher|\mcosts?\M|\mbid\M|boost)'
$fn$;
revoke execute on function public.fn_action_is_money(text) from public, anon, authenticated;

-- Ruling 1696 as settled 15 Nov 2026: a destructive production change (a deploy, a migration, a drop, a production rewrite)
-- keeps its release path and is never decided through the authority check, by any seat.
create or replace function public.fn_action_is_destructive_production_change(p_action_class text)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select lower(coalesce(p_action_class, '')) ~ '(deploy|migrat|\mdrop|truncate|delete_prod|prod(uction)?_(write|rewrite|delete)|schema_change|rollback_prod)'
$fn$;
revoke execute on function public.fn_action_is_destructive_production_change(text) from public, anon, authenticated;

-- An action that would message a person the gates refuse, or change a gate itself (re-subscribe, un-suppress, skip the
-- placement bar, send without the opt-in): never allowed, by any seat or the CEO.
create or replace function public.fn_action_weakens_a_message_gate(p_action_class text, p_ask jsonb default null)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((case when jsonb_typeof(p_ask) = 'object' then p_ask->>'bypasses_gate' end)::boolean, false)
      or lower(coalesce(p_action_class, '')) ~ '(unsuppress|re_?subscribe|bypass|force_send|(override|ignore|skip|waive)_(consent|opt|optin|opt_in|optout|opt_out|placement|suppression|unsubscribe|gate))'
$fn$;
revoke execute on function public.fn_action_weakens_a_message_gate(text, jsonb) from public, anon, authenticated;

-- ── 3. THE MESSAGE GATES FOR ONE NAMED RECIPIENT (read, never changed) ─────────────────────────────────────────────
-- Which existing gate would refuse a message to this person on this channel; empty = every gate lets it through. A channel
-- this does not know is refused (fail closed). The senders apply the same gates again at send time.
create or replace function public.fn_company_message_gates(p_channel text, p_email text default null, p_lead_id bigint default null)
returns text[] language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_out text[] := '{}'; v_email text; v_lead public.leads; v_s jsonb; v_prov text;
begin
  if p_lead_id is not null then select * into v_lead from public.leads where id = p_lead_id; end if;
  v_email := lower(nullif(btrim(coalesce(p_email, v_lead.email, '')), ''));
  if v_lead.id is not null and coalesce(v_lead.invite_status, '') in ('complained', 'unsubscribed', 'opted_out') then
    v_out := v_out || ('opt-out: the person ' || v_lead.invite_status);
  end if;
  if v_lead.id is not null and (coalesce(v_lead.banned, false) or coalesce(v_lead.permanently_closed, false)) then
    v_out := v_out || 'the company is banned or closed'::text;
  end if;
  if lower(coalesce(p_channel, '')) = 'email' then
    if v_email is null then return v_out || 'no e-mail address'::text; end if;
    v_s := public.fn_email_sendable(v_email);
    if not coalesce((v_s->>'ok')::boolean, false) then v_out := v_out || ('suppression: ' || coalesce(v_s->>'reason', 'not sendable')); end if;
    if v_lead.id is not null then   -- a supplier invitation also passes the inbox-placement bar for its mailbox provider
      v_prov := public.fn_mail_provider_of_email(v_email);
      if not (v_prov = any (coalesce(public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date), '{}'::text[]))) then
        v_out := v_out || ('inbox placement: the ' || coalesce(v_prov, 'unknown') || ' provider is not open on invite_placement_bar');
      end if;
    end if;
  elsif lower(coalesce(p_channel, '')) = 'whatsapp' then
    if v_lead.id is null or not exists (select 1 from public.supplier_whatsapp_optin o where o.lead_id = v_lead.id) then
      v_out := v_out || 'consent: no WhatsApp opt-in on record (ledger 1341: the button or a yes to the consent question)'::text;
    end if;
  else
    v_out := v_out || ('unknown channel ' || coalesce(p_channel, '-') || ': only e-mail and WhatsApp have gates')::text;
  end if;
  return v_out;
end $fn$;
revoke execute on function public.fn_company_message_gates(text, text, bigint) from public, anon, authenticated;

-- ── 4. A COMMITMENT: checked and written in one step ─────────────────────────────────────────────────────────────
-- Refused (nothing written) when the amount is missing, above the per-action limit, or above what is left of today.
create or replace function public.fn_company_spend_fits(p_amount_aed numeric)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_per numeric := public.fn_company_limit('per_action_aed'); v_day numeric := public.fn_company_limit('daily_spend_aed');
        v_spent numeric := coalesce((select sum(s.amount_aed) from public.company_spend_commitment s
                                      where s.dubai_day = (now() at time zone 'Asia/Dubai')::date), 0);
        v_why text;
begin
  v_why := case when p_amount_aed is null or p_amount_aed <= 0 then 'a money action names its amount in AED'
                when v_per is null or v_day is null then 'the company limits are not set'
                when p_amount_aed > v_per then format('AED %s is above the per-action limit of AED %s', p_amount_aed, v_per)
                when v_spent + p_amount_aed > v_day then format('AED %s is above what is left of today''s company limit (AED %s of AED %s committed)', p_amount_aed, v_spent, v_day) end;
  return jsonb_build_object('fits', v_why is null, 'why', v_why, 'per_action_aed', v_per, 'daily_spend_aed', v_day,
                            'spent_today_aed', v_spent, 'left_today_aed', greatest(coalesce(v_day, 0) - v_spent, 0));
end $fn$;
revoke execute on function public.fn_company_spend_fits(numeric) from public, anon, authenticated;

create or replace function public.fn_company_spend_commit(p_seat text, p_action_class text, p_subject text, p_amount_aed numeric, p_route text, p_grant_once_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb; v_id bigint;
begin
  -- review 4, item 2 (LOCAL race): under REPEATABLE READ the total below is read from a snapshot taken before the lock, and two
  -- commitments of 20 against 30 both went through. Only READ COMMITTED reads today's total fresh after the lock.
  if current_setting('transaction_isolation') <> 'read committed' then
    return jsonb_build_object('fits', false, 'committed', false,
      'why', 'a commitment is written only under READ COMMITTED (this transaction is ' || current_setting('transaction_isolation') || '), so the day''s total is read after the lock');
  end if;
  -- one writer at a time for the whole company's day: the read of today's total (the next statement, a fresh snapshot) and the
  -- write are serialised
  perform pg_advisory_xact_lock(hashtext('qd.company_spend_commitment'));
  v := public.fn_company_spend_fits(p_amount_aed);
  if not (v->>'fits')::boolean then return v || jsonb_build_object('committed', false); end if;
  insert into public.company_spend_commitment (seat, action_class, subject, amount_aed, route, grant_once_id)
  values (p_seat, p_action_class, coalesce(nullif(btrim(p_subject), ''), '-'), p_amount_aed, p_route, p_grant_once_id)
  returning id into v_id;
  return v || jsonb_build_object('committed', true, 'commitment_id', v_id,
    'spent_today_aed', (v->>'spent_today_aed')::numeric + p_amount_aed, 'left_today_aed', (v->>'left_today_aed')::numeric - p_amount_aed);
end $fn$;
revoke execute on function public.fn_company_spend_commit(text, text, text, numeric, text, bigint) from public, anon, authenticated;

-- ── 5. THE CEO CHANGES A LIMIT: with a reason, in force a day later, one waiting change per limit ─────────────────
create or replace function public.fn_ceo_sets_company_limit(p_key text, p_value_aed numeric, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.company_limit_change;
begin
  if p_key not in ('daily_spend_aed', 'per_action_aed') then return jsonb_build_object('ok', false, 'reason', 'no such limit: daily_spend_aed or per_action_aed'); end if;
  if p_value_aed is null or p_value_aed < 0 then return jsonb_build_object('ok', false, 'reason', 'a limit is a number of AED, 0 or more'); end if;
  if length(btrim(coalesce(p_reason, ''))) < 20 then return jsonb_build_object('ok', false, 'reason', 'say why, in a sentence (20 characters or more)'); end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    return jsonb_build_object('ok', false, 'reason', 'a company limit is changed only under READ COMMITTED');
  end if;
  perform pg_advisory_xact_lock(hashtext('qd.company_limit_change:' || p_key));   -- two changes at once leave one (review 4, item 2)
  if exists (select 1 from public.company_limit_change x where x.limit_key = p_key and x.effective_at > clock_timestamp()) then
    return jsonb_build_object('ok', false, 'reason', 'a change of ' || p_key || ' already waits; it takes effect first', 'limits', public.fn_company_limits());
  end if;
  insert into public.company_limit_change (limit_key, value_aed, reason, set_by, effective_at)
  values (p_key, p_value_aed, btrim(p_reason), 'ceo', clock_timestamp()) returning * into c;   -- the trigger moves effective_at a day on
  return jsonb_build_object('ok', true, 'id', c.id, 'limit', c.limit_key, 'value_aed', c.value_aed, 'in_force_now', public.fn_company_limit(p_key),
                            'effective_at', c.effective_at, 'told', 'in the founder''s daily summary');
end $fn$;
revoke execute on function public.fn_ceo_sets_company_limit(text, numeric, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_sets_company_limit(text, numeric, text) to service_role;

-- ── 6. THE SEED: the ads cap the company already runs (first value: in force at once) ─────────────────────────────
insert into public.company_limit_change (limit_key, value_aed, reason, set_by, effective_at)
select 'daily_spend_aed', coalesce((select p.daily_cap_aed from public.ad_spend_policy p where p.policy_key = 'default'), 30),
       'Seed (founder ledger 1696): public.ad_spend_policy default daily_cap_aed at apply, the one daily money limit the company already ran; the CEO raises it with a reason, a day later.',
       'seed', now()
 where not exists (select 1 from public.company_limit_change where limit_key = 'daily_spend_aed');
insert into public.company_limit_change (limit_key, value_aed, reason, set_by, effective_at)
select 'per_action_aed', coalesce((select p.max_daily_per_campaign_aed from public.ad_spend_policy p where p.policy_key = 'default'), 30),
       'Seed (founder ledger 1696): public.ad_spend_policy default max_daily_per_campaign_aed at apply, the largest single commitment the company already allowed; the CEO raises it with a reason, a day later.',
       'seed', now()
 where not exists (select 1 from public.company_limit_change where limit_key = 'per_action_aed');

-- ── 7. THE THREE-ARGUMENT RULE REFUSES MONEY (review 4, item 3) ───────────────────────────────────────────────────────
-- fn_agent_may_act(seat, action, amount) said may_act true for ('marketing', 'ad_boost', 1000) under a standing grant with
-- no ceiling, outside every company limit. The standing-grant reading moves, unchanged, into fn_agent_standing_grant (the
-- subject-aware form reads it and commits money against the limits); the three-argument form answers it for every action
-- that is not money, and for a refund (the CEO's refund path decides those: returning a customer's own fee is not company
-- spending). Any other money action with an amount is refused here and pointed at the subject-aware form, which commits it.
-- Production's body of the three-argument form (mirror 03_functions_before_fn_c.sql) is the body of fn_agent_standing_grant.
create or replace function public.fn_agent_standing_grant(p_grantee_role_id text, p_action_class text, p_amount_aed numeric default null)
returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $fn$
declare g record;
begin
  select * into g from public.ceo_standing_grant
   where grantee_role_id = p_grantee_role_id and action_class = p_action_class and active
     and (expires_at is null or expires_at > now())
   order by issued_at desc limit 1;
  if not found then
    return jsonb_build_object('may_act', false, 'route', 'ceo_case_decision',
      'reason', format('No current standing grant covers %L for %L. This needs a scoped CEO decision -- not a founder approval, which does not exist.', p_action_class, p_grantee_role_id));
  end if;
  if g.max_amount_aed is not null and p_amount_aed is not null and p_amount_aed > g.max_amount_aed then
    return jsonb_build_object('may_act', false, 'route', 'ceo_case_decision',
      'reason', format('AED %s exceeds the standing limit of AED %s on %L.', p_amount_aed, g.max_amount_aed, g.grant_key));
  end if;
  return jsonb_build_object('may_act', true, 'grant', g.grant_key, 'scope', g.scope_note, 'limit', g.limit_note);
end $fn$;
revoke execute on function public.fn_agent_standing_grant(text, text, numeric) from public, anon, authenticated;

create or replace function public.fn_agent_may_act(p_grantee_role_id text, p_action_class text, p_amount_aed numeric default null)
returns jsonb language plpgsql stable set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := public.fn_agent_standing_grant(p_grantee_role_id, p_action_class, p_amount_aed);
begin
  if public.fn_action_is_money(p_action_class) and lower(coalesce(p_action_class, '')) !~ 'refund'
     and coalesce(p_amount_aed, 0) > 0 and coalesce((v->>'may_act')::boolean, false) then
    return jsonb_build_object('may_act', false, 'route', 'hard_limit', 'grant', v->>'grant',
      'reason', format('Money (%s, AED %s) is allowed only through the subject-aware authority check, fn_agent_may_act(seat, action, amount, subject, ask), which commits it against the company limits (founder ledger 1696).', p_action_class, p_amount_aed));
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_agent_may_act(text, text, numeric) from public, anon, authenticated;   -- as on production (SELECT 15 Nov)
grant execute on function public.fn_agent_may_act(text, text, numeric) to service_role;
