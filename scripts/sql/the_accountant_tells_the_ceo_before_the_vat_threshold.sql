-- THE ACCOUNTANT TELLS THE CEO BEFORE THE VAT THRESHOLD IS CROSSED (legal finding 14).
--
-- Assigned: ceo (the decision to register); the accountant watches and sends. 19 Oct 2026.
-- UAE Federal Decree-Law 8/2017 Art. 13: registration is mandatory once taxable supplies over the previous 12
-- months exceed AED 375,000, or are expected to within the next 30 days; the application is due within 30 days.
--
-- WHAT THIS ADDS
--   decision_policy keys vat_watch_warn_aed (300000) and vat_mandatory_threshold_aed (375000).
--   fn_accountant_vat_threshold_levels(trailing, largest_pending) -> the thresholds crossed (pure, probed below).
--   fn_accountant_vat_threshold_watch() -> trailing-12-month reveal fees (paid, net of refunds) and the largest
--     pending reveal fee; for each crossed level ONE handoff accountant -> ceo of kind accountant.vat_threshold.
--     fn_seat_handoff dedupes on type + subject_id; subject_id = level + calendar year, so one alert per level
--     per year. ponytail: a year key, not a crossing streak; a drop below and a re-cross in the same year is silent.
--   The CEO's handler keeps the handoff waiting: registration is the CEO's act and it closes the handoff itself.
--   Daily seat_duty accountant.vat_threshold_watch. Empty tables (pre-launch): total 0, nothing raised.
--
-- Pending: scripts/sql/pending/the_accountant_tells_the_ceo_before_the_vat_threshold.txt.

insert into public.decision_policy (key, value, description) values
  ('vat_watch_warn_aed', '300000'::jsonb,
   'Accountant warns the CEO when trailing-12-month reveal fees reach this (AED). Legal finding 14.'),
  ('vat_mandatory_threshold_aed', '375000'::jsonb,
   'UAE mandatory VAT registration threshold (AED, trailing 12 months; register within 30 days). Legal finding 14.')
on conflict (key) do nothing;

create or replace function public.fn_accountant_vat_threshold_levels(p_trailing_aed numeric, p_largest_pending_aed numeric)
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select array_remove(array[
    case when coalesce(p_trailing_aed, 0) >= (select (value #>> '{}')::numeric from public.decision_policy where key = 'vat_watch_warn_aed')
         then 'warn_300000' end,
    case when coalesce(p_trailing_aed, 0) > (select (value #>> '{}')::numeric from public.decision_policy where key = 'vat_mandatory_threshold_aed')
         then 'mandatory_375000_reached'
         when coalesce(p_trailing_aed, 0) + coalesce(p_largest_pending_aed, 0)
              > (select (value #>> '{}')::numeric from public.decision_policy where key = 'vat_mandatory_threshold_aed')
         then 'mandatory_375000_next_reveal' end
  ], null)
$fn$;
revoke execute on function public.fn_accountant_vat_threshold_levels(numeric, numeric) from public, anon, authenticated;

create or replace function public.fn_accountant_vat_threshold_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_trailing numeric; v_pending numeric; v_levels text[]; v_level text; v_ids bigint[] := '{}';
begin
  select coalesce(sum(coalesce(reveal_fee, 0) - coalesce(refund_amount_aed, 0)), 0) into v_trailing
    from public.transactions
   where fee_status = 'paid' and revealed_at >= now() - interval '12 months';
  select coalesce(max(reveal_fee), 0) into v_pending
    from public.transactions where fee_status = 'pending' and reveal_fee > 0;
  v_levels := public.fn_accountant_vat_threshold_levels(v_trailing, v_pending);
  foreach v_level in array v_levels loop
    v_ids := v_ids || public.fn_seat_handoff('accountant', 'ceo', 'accountant.vat_threshold', 'transactions',
      v_level || ':' || to_char(now(), 'YYYY'),
      jsonb_build_object('level', v_level, 'trailing_12m_fees_aed', v_trailing, 'largest_pending_fee_aed', v_pending,
        'rule', 'UAE mandatory VAT registration above AED 375,000 taxable supplies in 12 months; apply within 30 days'));
  end loop;
  return jsonb_build_object('trailing_12m_fees_aed', v_trailing, 'largest_pending_fee_aed', v_pending,
                            'levels', to_jsonb(v_levels), 'handoffs', to_jsonb(v_ids));
end $fn$;
revoke execute on function public.fn_accountant_vat_threshold_watch() from public, anon, authenticated;

create or replace function public.fn_ceo_takes_vat_threshold(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'level', a.detail->>'level',
    'waiting', 'the CEO decides the VAT registration (due within 30 days of the 375,000 crossing) and closes this handoff');
end $fn$;
revoke execute on function public.fn_ceo_takes_vat_threshold(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('accountant.vat_threshold', 'accountant', 'ceo',
        'Trailing-12-month reveal fees reached AED 300,000, or AED 375,000 (mandatory VAT registration, due within 30 days) is reached or the next pending reveal would cross it.',
        'fn_ceo_takes_vat_threshold', interval '7 days', false,
        'scripts/sql/the_accountant_tells_the_ceo_before_the_vat_threshold.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, owner_file = excluded.owner_file;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.vat_threshold_watch', 'accountant', interval '1 day', 'fn_accountant_vat_threshold_watch',
   'Trailing-12-month reveal fees against the VAT thresholds (300,000 warn, 375,000 mandatory); the CEO is handed each crossing once.',
   'scripts/sql/the_accountant_tells_the_ceo_before_the_vat_threshold.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- PROBE: the pure level function only; no row is written.
select case
  when public.fn_accountant_vat_threshold_levels(0, 0) <> '{}'::text[] then 'PROBE FAILED: empty books raised a level'
  when public.fn_accountant_vat_threshold_levels(299999, 0) <> '{}'::text[] then 'PROBE FAILED: 299,999 raised a level'
  when public.fn_accountant_vat_threshold_levels(300000, 0) <> array['warn_300000'] then 'PROBE FAILED: 300,000 did not warn'
  when public.fn_accountant_vat_threshold_levels(370000, 6000) <> array['warn_300000', 'mandatory_375000_next_reveal'] then 'PROBE FAILED: next reveal over 375,000 not raised'
  when public.fn_accountant_vat_threshold_levels(375001, 0) <> array['warn_300000', 'mandatory_375000_reached'] then 'PROBE FAILED: 375,001 not raised'
  when not exists (select 1 from public.seat_duty where duty = 'accountant.vat_threshold_watch' and owner_seat = 'accountant') then 'PROBE FAILED: no daily duty'
  when not exists (select 1 from public.seat_handoff_kind where type = 'accountant.vat_threshold' and to_seat = 'ceo') then 'PROBE FAILED: handoff kind not registered'
  else 'PROBE OK' end as verdict;
