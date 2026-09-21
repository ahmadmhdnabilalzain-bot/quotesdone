-- THE IT ENGINEER WATCHES EVERY BILL BEFORE ITS CAP.
--
-- Assigned: it_engineer (the reading, the comparison, the re-check). The accountant owns every bill, so
-- every finding goes round the IT loop (the_it_engineer_closes_every_loop_it_opens.sql) to the accountant;
-- the founder hears only when the accountant and the ceo could not close it.
--
-- Founder, 14 Sep 2026, approving IT duty 22 ("add all for accountant and IT"): Supabase, Vercel, Resend,
-- Twilio and Stripe usage against plan limits, warned before the cap. No model call anywhere.
--
-- WHAT WAS ALREADY BUILT, AND IS REUSED (the_it_engineer_takes_on_seven_more_duties.sql): duty 11 compares
-- each day's Twilio and Stripe spend with its own 14-day baseline - a spike - and duty 14 compares the
-- database with the disk the plan gives it (db_disk_limit_bytes, from the management API). Neither says
-- how close a provider is to the CAP of its plan. That is what this file adds. Every cap is a row of
-- public.it_threshold, the table duties 9-18 made for exactly this, and the cadence is a row of
-- public.it_duty_schedule.
--
-- WHAT IS MEASURED, AND HOW:
--   supabase  stored bytes (storage.objects), inside Postgres. Measured 14 Sep 2026: 14,209,421,506 bytes,
--             about 13 GB of it in the 'backups' bucket. The database's own size is duty 14's.
--   resend    emails the outbox marked sent this calendar month (UTC) and today. Resend counts by its own
--             billing cycle and counts mail sent outside the outbox, so ours is a lower bound.
--   twilio    the prepaid balance (GET /Accounts/{sid}/Balance.json). On a prepaid account the balance IS
--             the cap, so it is judged against a floor.
--   vercel    charges billed this calendar month (GET /v1/billing/charges, FOCUS BilledCost). Duty 11's
--             reading assumes the stored token has no billing scope; this one asks, and a refusal is
--             reported as not read.
--   stripe    has no plan cap: it charges per payment, and every fee is already duty 11's and the
--             accountant's. Deliberately not watched here.
--
-- EVERY CAP STARTS NULL and none was typed from memory. A NULL cap is a quiet ledger finding owned by the
-- accountant ("no cap recorded"), never a guess. The accountant, the ceo or the founder sets one from the
-- plan page or the invoice with fn_it_cap_set, which records who and from what. A cap warns at
-- cap_warn_ratio (80%); a floor warns at or below its value. Each provider settles its own duty
-- (usage_<provider>) only when its figures were read.

insert into public.it_threshold (key, value, unit, basis) values
  ('cap_warn_ratio',             0.8,  'ratio',            'Warn at 80% of any provider cap, so there is time to act; the ratio the disk check uses.'),
  ('cap_supabase_storage_bytes', null, 'bytes',            'not recorded: the accountant enters the storage the Supabase plan includes, from the invoice'),
  ('cap_resend_emails_month',    null, 'emails',           'not recorded: the accountant enters the monthly send quota of the Resend plan'),
  -- cap_resend_emails_day was here: the Resend Pro plan has no daily limit (the_open_account_facts_of_21_september_are_recorded.sql).
  ('cap_vercel_charges_month',   null, 'billing currency', 'not recorded: the accountant enters the monthly Vercel budget'),
  ('floor_twilio_balance',       null, 'account currency', 'not recorded: the accountant enters the lowest balance the prepaid Twilio account may fall to')
-- Re-applying this file never wipes a cap somebody set: value and basis are kept once a value exists.
on conflict (key) do update set unit = excluded.unit,
  basis = case when public.it_threshold.value is null then excluded.basis else public.it_threshold.basis end;

insert into public.it_duty_schedule (duty, every, note) values
  ('usage', interval '1 hour', 'duty 22: provider usage against the caps in it_threshold (cap_* and floor_*)')
on conflict (duty) do update set every = excluded.every, note = excluded.note;

create or replace function public.fn_it_cap_set(p_key text, p_value numeric, p_by text, p_source text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(p_key, '') !~ '^(cap|floor)_[a-z0-9_]+$' or p_key = 'cap_warn_ratio' then
    raise exception 'fn_it_cap_set sets a provider cap (cap_*) or floor (floor_*), not %', coalesce(p_key, 'nothing');
  end if;
  if p_by is null or p_by not in ('accountant', 'ceo', 'founder') then
    raise exception 'a cap is set by the accountant, the ceo or the founder, not %', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_source), '') = '' then raise exception 'say where the cap comes from: the plan page or the invoice'; end if;
  if p_value is not null and p_value <= 0 then raise exception 'a cap must be above zero, or NULL for not recorded'; end if;
  update public.it_threshold
     set value = p_value,
         basis = left('set by the ' || p_by || ' on ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' from: ' || p_source, 500)
   where key = p_key;
  if not found then raise exception 'no cap % in public.it_threshold', p_key; end if;
  return jsonb_build_object('key', p_key, 'value', p_value, 'set_by', p_by);
end $fn$;
revoke execute on function public.fn_it_cap_set(text, numeric, text, text) from public, anon, authenticated;

create or replace function public.fn_it_usage_watch(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_vals jsonb; v_not jsonb := '{}'::jsonb; v_prov text; v_items jsonb; t public.it_threshold; v_metric text;
  v_floor boolean; v numeric; v_ratio numeric; v_fmt text; v_lim text; v_out jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_it_usage_watch takes the readings object from takeUsageReadings';
  end if;
  v_ratio := coalesce(public.fn_it_threshold('cap_warn_ratio'), 0.8);
  v_vals := jsonb_build_object(
    'supabase_storage_bytes', (select coalesce(sum((o.metadata->>'size')::bigint), 0) from storage.objects o),
    'resend_emails_month', (select count(*) from public.notifications n
                             where n.channel = 'email' and n.status = 'sent' and n.sent_at >= date_trunc('month', now())),
    'resend_emails_day',   (select count(*) from public.notifications n
                             where n.channel = 'email' and n.status = 'sent' and n.sent_at >= date_trunc('day', now())));
  if p_r->'twilio'->>'basis' = 'measured' then
    v_vals := v_vals || jsonb_build_object('twilio_balance', (p_r->'twilio'->>'balance')::numeric);
  else
    v_not := v_not || jsonb_build_object('twilio', coalesce(p_r->'twilio'->>'reason', 'no reading'));
  end if;
  if p_r->'vercel'->>'basis' = 'measured' then
    v_vals := v_vals || jsonb_build_object('vercel_charges_month', (p_r->'vercel'->>'charges_month')::numeric);
  else
    v_not := v_not || jsonb_build_object('vercel', coalesce(p_r->'vercel'->>'reason', 'no reading'));
  end if;

  for v_prov in select distinct split_part(regexp_replace(key, '^(cap|floor)_', ''), '_', 1) from public.it_threshold
                 where key ~ '^(cap|floor)_' and key <> 'cap_warn_ratio' order by 1 loop
    -- A provider none of whose figures were read settles nothing: its open findings stay as they were.
    continue when not exists (select 1 from jsonb_object_keys(v_vals) k where k like v_prov || '\_%');
    v_items := '[]'::jsonb;
    for t in select * from public.it_threshold where key ~ ('^(cap|floor)_' || v_prov || '_') order by key loop
      v_metric := regexp_replace(t.key, '^(cap|floor)_', '');
      v_floor := t.key like 'floor\_%';
      v := (v_vals->>v_metric)::numeric;
      continue when v is null;
      v_fmt := case when t.unit = 'bytes' then pg_size_pretty(v) else round(v, 2)::text || ' ' || t.unit end;
      if t.value is null then
        v_items := v_items || jsonb_build_object('item', 'cap_unknown:' || v_metric, 'owner_seat', 'accountant', 'subject', v_prov,
          'title', replace(v_metric, '_', ' ') || ' is ' || v_fmt || ' and no ' || case when v_floor then 'floor' else 'cap' end
                   || ' is recorded to judge it against',
          'blast', 'internal', 'affected', 0,
          'evidence', jsonb_build_object('value', v, 'unit', t.unit, 'key', t.key, 'basis', t.basis, 'set_with', 'public.fn_it_cap_set'));
      elsif (not v_floor and v >= v_ratio * t.value) or (v_floor and v <= t.value) then
        v_lim := case when t.unit = 'bytes' then pg_size_pretty(t.value) else round(t.value, 2)::text || ' ' || t.unit end;
        v_items := v_items || jsonb_build_object('item', v_metric, 'owner_seat', 'accountant', 'subject', v_prov,
          'title', case when v_floor
                        then replace(v_metric, '_', ' ') || ' is down to ' || v_fmt || ', at or below the floor of ' || v_lim
                        else replace(v_metric, '_', ' ') || ' is at ' || coalesce(round(100 * v / nullif(t.value, 0))::text, '?')
                             || '% of its cap (' || v_fmt || ' of ' || v_lim || ')' end,
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('value', v, 'cap', t.value, 'unit', t.unit, 'key', t.key, 'warn_ratio', v_ratio, 'basis', t.basis));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('usage_' || v_prov, public.fn_it_duty_settle('usage_' || v_prov, v_items));
  end loop;

  perform public.fn_it_duty_ran('usage', v_out || jsonb_build_object('values', v_vals, 'not_read', v_not));
  return v_out || jsonb_build_object('not_read', v_not);
end $fn$;
revoke execute on function public.fn_it_usage_watch(jsonb) from public, anon, authenticated;
