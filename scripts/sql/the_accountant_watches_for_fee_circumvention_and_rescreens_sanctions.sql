-- THE ACCOUNTANT WATCHES FOR DUPLICATE ACCOUNTS AND FEE CIRCUMVENTION, AND RE-SCREENS SUPPLIERS FOR SANCTIONS.
-- Seat: accountant (the CEO decides what a finding leads to). 23 Sep 2026, founder_instruction 898 ("no new
-- agents": these are extra duties of the seats that exist). Builds on
-- every_seat_duty_has_an_owner_a_clock_and_a_check.sql (#901), which must be applied first.
--
-- WHAT WAS MEASURED (23 Sep 2026, production, read-only):
--   * public.fraud_flags (primary key kind, subject_type, subject_id) holds 7 rows, all 'dismissed', and NO
--     routine writes it: fn_ws_fraud reads it for the workspace, fn_fraud_resolve closes a flag (and bans or
--     unbans). Nothing detects a duplicate account or a deal taken off the platform.
--   * Sanctions: fn_supplier_sanctions_screen(run_ids) screens every registered or approved supplier's legal
--     name, licence name, signatory, contact and e-mail domain against the stored lists (screening_entry) and
--     opens one CEO decision and one sales_engineer hold per hit. It runs only when the sanctions_screen edge
--     function fetches fresh lists, weekly, from resilience_ping's orphans step. The latest ok runs are 81
--     (un_consolidated) and 80 (uae_local_terrorist_list), both 18 Sep 2026. So a supplier approved on a Monday
--     was not screened until the next weekly fetch, and no seat owned "the lists are stale". There is no UBO
--     register: the names this estate holds for a supplier are the ones above, and all of them are screened.
--
-- WHAT THIS ADDS
--   1. accountant.fraud_watch (every 6 hours, fn_accountant_fraud_watch_tick), deterministic, written to
--      fraud_flags once per (kind, subject) and never re-opened once a person closed it:
--        duplicates, by EQUALITY of normalised identifiers (never by words): two customers on one phone
--        (last 9 digits) or one e-mail (lower case, +tag removed); two suppliers on one trade licence (letters and
--        digits) or one TRN (digits); a customer whose phone or e-mail is a supplier's.
--        circumvention signals, each measurable: a request marked hired with no paid reveal for that supplier;
--        a reveal refunded after the supplier acknowledged the customer; a paid reveal followed by 60 days of
--        silence from the customer with the job never marked complete.
--      Whether a circumvention signal IS circumvention is reasoned by the accountant (surface
--      accountant.circumvention) and applied by fn_reason_apply_accountant__circumvention: a 'circumvention'
--      finding goes to the CEO with a cross-family review (deliberation.review accountant -> ceo, registered
--      here); 'benign' dismisses the flag. What the CEO then does is the existing fn_fraud_resolve.
--   2. accountant.sanctions_rescreen (daily, fn_accountant_sanctions_rescreen): every registered or approved
--      supplier re-screened against the LATEST ok list per source with the existing fn_supplier_sanctions_screen
--      (so a hit follows the existing path, and a new supplier is screened within a day, not a week), and a list
--      older than 8 days is a finding the accountant owns. No ok list at all fails the duty, which
--      fn_seat_duty_health turns into a finding.
--   A fixture run (set local qd.duty_fixtures = 'on') selects ONLY demo rows.
--
-- WHAT THIS DOES NOT DO: it bans nobody (a ban is the CEO's, through fn_fraud_resolve); it does not fetch the
-- lists (the weekly sanctions_screen fetch stays where it is); it adds no UBO capture to the registration form.

create or replace function public.fn_accountant_fraud_watch_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v_dup int := 0; v_sig int := 0; v_filed int := 0;
begin
  create temp table if not exists tmp_fraud_new (kind text, subject_type text, subject_id text, severity text, detail jsonb) on commit drop;
  truncate tmp_fraud_new;

  -- ── duplicates: equality of normalised identifiers ──
  insert into tmp_fraud_new
  select 'dup_customer_phone', 'cphone', k, 'medium', jsonb_build_object('customer_ids', ids, 'count', n)
    from (select right(regexp_replace(c.phone, '\D', '', 'g'), 9) k, jsonb_agg(c.id order by c.id) ids, count(*) n
            from public.customers c
           where length(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g')) >= 9
             and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
           group by 1 having count(*) > 1) x;
  insert into tmp_fraud_new
  select 'dup_customer_email', 'cemail', k, 'medium', jsonb_build_object('customer_ids', ids, 'count', n)
    from (select regexp_replace(lower(btrim(c.email)), '[+][^@]*@', '@') k, jsonb_agg(c.id order by c.id) ids, count(*) n
            from public.customers c
           where position('@' in coalesce(c.email, '')) > 1
             and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
           group by 1 having count(*) > 1) x;
  insert into tmp_fraud_new
  select 'duplicate_license', 'licence', k, 'high', jsonb_build_object('lead_ids', ids, 'count', n)
    from (select upper(regexp_replace(l.trade_license_no, '[^A-Za-z0-9]', '', 'g')) k, jsonb_agg(l.id order by l.id) ids, count(*) n
            from public.leads l
           where length(regexp_replace(coalesce(l.trade_license_no, ''), '[^A-Za-z0-9]', '', 'g')) >= 4
             and (l.lifecycle_stage = 'registered' or l.approval_status is not null)
             and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx
           group by 1 having count(*) > 1) x;
  insert into tmp_fraud_new
  select 'dup_trn', 'trn', k, 'high', jsonb_build_object('lead_ids', ids, 'count', n)
    from (select regexp_replace(l.trn, '\D', '', 'g') k, jsonb_agg(l.id order by l.id) ids, count(*) n
            from public.leads l
           where length(regexp_replace(coalesce(l.trn, ''), '\D', '', 'g')) = 15
             and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx
           group by 1 having count(*) > 1) x;
  insert into tmp_fraud_new
  select 'customer_matches_supplier', 'customer', c.id::text, 'high',
         jsonb_build_object('lead_ids', jsonb_agg(distinct l.id), 'on', jsonb_agg(distinct m.what))
    from public.customers c
    join public.leads l on (coalesce(l.is_demo, false) or coalesce(l.company_name, '') like 'ZZ DEMO%' or public.fn_is_demo_email(l.email)) = v_fx
    cross join lateral (select 'phone' as what
                         where length(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g')) >= 9
                           and right(regexp_replace(c.phone, '\D', '', 'g'), 9)
                               in (right(regexp_replace(coalesce(l.phone_e164, ''), '\D', '', 'g'), 9),
                                   right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 9))
                        union all
                        select 'email' where lower(btrim(coalesce(c.email, ''))) <> ''
                           and lower(btrim(c.email)) in (lower(btrim(coalesce(l.email, ''))), lower(btrim(coalesce(l.claimed_by, ''))))) m
   where (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
   group by c.id;

  -- ── circumvention signals: each a measurable fact about money not reaching the platform ──
  insert into tmp_fraud_new
  select 'hired_without_fee', 'inquiry', i.id::text, 'high',
         jsonb_build_object('inquiry_id', i.id, 'hired_supplier_id', i.hired_supplier_id, 'customer_id', i.customer_id,
                            'completed_at', i.completed_at, 'outcome', i.outcome)
    from public.inquiries i join public.customers c on c.id = i.customer_id
   where i.hired_supplier_id is not null
     and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
     and not exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.supplier_id = i.hired_supplier_id
                        and t.fee_status = 'paid' and t.refund_confirmed_at is null);
  insert into tmp_fraud_new
  select 'refund_after_supplier_contact', 'transaction', t.id::text, 'high',
         jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id, 'customer_id', t.customer_id,
                            'revealed_at', t.revealed_at, 'supplier_ack_at', t.supplier_ack_at,
                            'refund_requested_at', t.refund_requested_at, 'refund_confirmed_at', t.refund_confirmed_at)
    from public.transactions t join public.customers c on c.id = t.customer_id
   where t.refund_confirmed_at is not null and t.supplier_ack_at is not null
     and t.supplier_ack_at < coalesce(t.refund_requested_at, t.refund_confirmed_at)
     and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx;
  insert into tmp_fraud_new
  select 'silent_after_reveal', 'transaction', t.id::text, 'medium',
         jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id, 'customer_id', t.customer_id,
                            'revealed_at', t.revealed_at, 'days_silent', extract(day from now() - t.revealed_at)::int)
    from public.transactions t join public.customers c on c.id = t.customer_id
    left join public.inquiries i on i.id = t.inquiry_id
   where t.fee_status = 'paid' and t.revealed_at < now() - interval '60 days' and t.refund_confirmed_at is null
     and i.completed_at is null and i.outcome is null
     and not exists (select 1 from public.inquiries i2 where i2.customer_id = t.customer_id and i2.created_at > t.revealed_at)
     and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx;

  -- ── write each once; a flag a person closed is never re-opened ──
  for r in select * from tmp_fraud_new loop
    insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail, status, created_at, updated_at)
    values (r.kind, r.subject_type, r.subject_id, r.severity, r.detail || jsonb_build_object('raised_by', 'accountant'), 'open', now(), now())
    on conflict (kind, subject_type, subject_id) do nothing;
    if not found then continue; end if;
    if r.kind in ('hired_without_fee', 'refund_after_supplier_contact', 'silent_after_reveal') then
      v_sig := v_sig + 1;
      perform public.fn_seat_duty_reason('accountant', 'accountant.circumvention',
        case when v_fx then 'ZZ DEMO ' else '' end
        || 'A measured signal suggests a customer and a supplier may have completed a job without the platform''s fee. On the facts, is this fee circumvention?',
        jsonb_build_array(
          jsonb_build_object('id', 'circumvention', 'meaning', 'the parties most likely dealt directly to avoid the fee; the CEO should act'),
          jsonb_build_object('id', 'benign', 'meaning', 'the facts have an ordinary explanation (the job fell through, a refund was due, the customer simply stopped)'),
          jsonb_build_object('id', 'insufficient_evidence', 'meaning', 'the facts cannot tell; keep the flag open and watch')),
        jsonb_build_object('signal', r.kind, 'subject_type', r.subject_type, 'subject_id', r.subject_id, 'facts', r.detail),
        jsonb_build_object('kind', r.kind, 'subject_type', r.subject_type, 'subject_id', r.subject_id),
        'circumvention:' || r.kind || ':' || r.subject_id);
      v_filed := v_filed + 1;
    else
      v_dup := v_dup + 1;
    end if;
  end loop;
  return jsonb_build_object('duplicates_flagged', v_dup, 'signals_flagged', v_sig, 'reasoning_filed', v_filed);
end $fn$;
revoke execute on function public.fn_accountant_fraud_watch_tick() from public, anon, authenticated;
grant execute on function public.fn_accountant_fraud_watch_tick() to service_role;

create or replace function public.fn_reason_apply_accountant__circumvention(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; f public.fraud_flags; v_rev jsonb;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('circumvention', 'benign', 'insufficient_evidence') then
    return jsonb_build_object('applied', false, 'reason', 'the choice is not one of the options: ' || coalesce(v_choice, 'none'));
  end if;
  select * into f from public.fraud_flags
   where kind = h.subject->>'kind' and subject_type = h.subject->>'subject_type' and subject_id = h.subject->>'subject_id' for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'the flag no longer exists'); end if;
  if f.status <> 'open' then return jsonb_build_object('applied', true, 'changed', false, 'reason', 'a person already closed the flag'); end if;
  update public.fraud_flags
     set detail = detail || jsonb_build_object('accountant_verdict', v_choice, 'verdict_model', p_result->>'model',
                                               'verdict_reasoning', left(p_result->>'answer', 4000), 'held_question_id', p_id),
         status = case v_choice when 'benign' then 'dismissed' when 'circumvention' then 'escalated' else 'open' end,
         updated_at = now()
   where kind = f.kind and subject_type = f.subject_type and subject_id = f.subject_id;
  if v_choice = 'circumvention' then
    v_rev := public.fn_seat_duty_cross_review('fee_circumvention', 'accountant', 'ceo',
      case when h.question like 'ZZ DEMO%' then 'ZZ DEMO ' else '' end
        || 'Review a reasoned verdict on a measured signal about a revealed job and the platform''s fee.',
      jsonb_build_object('signal', f.kind, 'subject_type', f.subject_type, 'subject_id', f.subject_id, 'facts', f.detail - 'raised_by'),
      jsonb_build_object('verdict', v_choice), p_result, 'fraud_flags', f.kind || ':' || f.subject_type || ':' || f.subject_id);
    update public.fraud_flags set detail = detail || jsonb_build_object('review', v_rev)
     where kind = f.kind and subject_type = f.subject_type and subject_id = f.subject_id;
  end if;
  return jsonb_build_object('applied', true, 'verdict', v_choice, 'review', v_rev);
end $fn$;
revoke execute on function public.fn_reason_apply_accountant__circumvention(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_accountant__circumvention(bigint, jsonb) to service_role;

create or replace function public.fn_accountant_sanctions_rescreen()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_runs bigint[]; v_oldest timestamptz; v_res jsonb;
begin
  select array_agg(id order by id), min(fetched_at) into v_runs, v_oldest
    from (select distinct on (source) id, fetched_at from public.screening_run where status = 'ok'
           order by source, fetched_at desc, id desc) x;
  if v_runs is null then raise exception 'no sanctions list has ever been fetched successfully (screening_run has no ok row)'; end if;
  if v_oldest < now() - interval '8 days' then
    perform public.fn_it_engineer_finding_upsert('sanctions_list_stale',
      'The sanctions lists the accountant re-screens against are older than 8 days',
      'public.screening_run / sanctions_screen (weekly fetch)', 'agent_facing', 1,
      jsonb_build_object('oldest_list_fetched_at', v_oldest, 'runs', to_jsonb(v_runs), 'owner_seat', 'accountant'),
      '{}'::text[], array['why the weekly sanctions_screen fetch has not produced an ok run'], 'accountant');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'a fresh sanctions list was fetched'
     where issue_key = 'sanctions_list_stale' and closed_at is null;
  end if;
  -- the screen builds a temp table that drops at commit; a second call in one transaction must not collide
  drop table if exists tmp_screen_sup;
  v_res := public.fn_supplier_sanctions_screen(v_runs, case when v_fx then 'zz_demo_duty' end);
  return v_res || jsonb_build_object('runs', to_jsonb(v_runs), 'oldest_list', v_oldest);
end $fn$;
revoke execute on function public.fn_accountant_sanctions_rescreen() from public, anon, authenticated;
grant execute on function public.fn_accountant_sanctions_rescreen() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.fraud_watch', 'accountant', interval '6 hours', 'fn_accountant_fraud_watch_tick',
   'duplicate accounts by equal identifiers and fee-circumvention signals written to fraud_flags; circumvention reasoned',
   'scripts/sql/the_accountant_watches_for_fee_circumvention_and_rescreens_sanctions.sql'),
  ('accountant.sanctions_rescreen', 'accountant', interval '1 day', 'fn_accountant_sanctions_rescreen',
   'every registered or approved supplier re-screened against the latest sanctions lists; a stale list is a finding',
   'scripts/sql/the_accountant_watches_for_fee_circumvention_and_rescreens_sanctions.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, owner_file)
values ('deliberation.review', 'accountant', 'ceo',
        'the CEO reviews the accountant''s reasoned verdict that a signal is fee circumvention on a model of another family',
        'fn_seat_deliberation_acts_on_handoff', interval '2 days',
        'scripts/sql/the_accountant_watches_for_fee_circumvention_and_rescreens_sanctions.sql')
on conflict do nothing;
