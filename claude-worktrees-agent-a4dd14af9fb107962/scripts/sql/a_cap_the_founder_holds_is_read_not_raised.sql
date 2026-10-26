-- A CAP THE FOUNDER HOLDS IS READ, NOT RAISED.
--
-- Assigned: it_engineer. 22 Sep 2026.
--
-- MEASURED (production, 22 Sep 2026 11:30Z):
--   duty:usage_twilio:cap_unknown:twilio_balance        open since 14 Sep 20:45Z, "twilio balance is 11.25
--                                                        account currency and no floor is recorded"
--   duty:usage_vercel:cap_unknown:vercel_charges_month  open since 14 Sep 20:45Z, "vercel charges month is
--                                                        48.63 billing currency and no cap is recorded"
--   Both are held open every usage tick by fn_it_duty_settle's configuration rule, because
--   fn_it_usage_watch emits a 'cap_unknown:<metric>' item for every it_threshold row whose value is NULL.
--   it_threshold: floor_twilio_balance NULL, cap_vercel_charges_month NULL -- on purpose.
--
-- WHAT IS WRONG: founder instruction 639 (22 Sep 2026): Vercel caps and subscriptions are his, added when
--   reached; the Twilio balance is raised only when it is actually a blocker. "No cap is recorded" is
--   therefore not a fault of anything, and a finding that says so is a question put to him in another form.
--   every_provider_cap_and_renewal_date_is_recorded.test.mjs already keeps it from being MAILED to him;
--   this stops it being raised at all.
--
-- WHAT CHANGES:
--   1. fn_it_usage_watch: a metric whose cap/floor is NULL is read and recorded under 'unjudged' (value,
--      unit, the row's basis) in the duty's agent_runs row and in its return value. It raises nothing.
--      A cap or floor that IS set and is breached raises exactly as before (owner accountant).
--   2. The two open findings are closed by their EXACT keys, with this reason (never by pattern:
--      memory close-a-finding-by-its-exact-key-never-by-title-match).
--
-- WHAT DOES NOT CHANGE: fn_it_duty_settle (it still holds any other configuration item an other producer
--   raises); it_threshold values; the breach arm; fn_it_cap_set. A cap the founder sets later is judged
--   from the next tick.
--
-- PREVENTED BY: scripts/checks/it_engineer_duties_19_to_24.test.mjs ("a cap nobody set is read and
--   recorded, never raised; a set cap that is breached still is" -- rolled-back probe with its control).
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/a_cap_the_founder_holds_is_read_not_raised.sql --apply
--   The file's last statement returns a PROBE OK / PROBE FAILED verdict row.

create or replace function public.fn_it_usage_watch(p_r jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_vals jsonb; v_not jsonb := '{}'::jsonb; v_prov text; v_items jsonb; t public.it_threshold; v_metric text;
  v_floor boolean; v numeric; v_ratio numeric; v_fmt text; v_lim text; v_out jsonb := '{}'::jsonb;
  v_unjudged jsonb := '{}'::jsonb;
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
        -- 22 Sep 2026, instruction 639: nobody set a number, so there is nothing to judge. The reading is
        -- kept, with where the number would come from, and nothing is raised.
        v_unjudged := v_unjudged || jsonb_build_object(v_metric, jsonb_build_object('value', v, 'unit', t.unit, 'basis', t.basis));
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

  perform public.fn_it_duty_ran('usage', v_out || jsonb_build_object('values', v_vals, 'not_read', v_not, 'unjudged', v_unjudged));
  return v_out || jsonb_build_object('not_read', v_not, 'unjudged', v_unjudged);
end $function$;

revoke execute on function public.fn_it_usage_watch(jsonb) from public, anon, authenticated;

-- The two findings instruction 639 retired, by exact key.
select public.fn_it_engineer_finding_close('duty:usage_twilio:cap_unknown:twilio_balance',
  'Founder instruction 639 (22 Sep 2026): the Twilio balance is raised only when it is actually a blocker, and the floor is his to set. '
  || 'fn_it_usage_watch now records the reading (unjudged) and raises nothing for a floor nobody set. a_cap_the_founder_holds_is_read_not_raised.sql')
 where exists (select 1 from public.it_engineer_finding where issue_key = 'duty:usage_twilio:cap_unknown:twilio_balance' and closed_at is null);
select public.fn_it_engineer_finding_close('duty:usage_vercel:cap_unknown:vercel_charges_month',
  'Founder instruction 639 (22 Sep 2026): Vercel caps and subscriptions are his, added when reached. '
  || 'fn_it_usage_watch now records the reading (unjudged) and raises nothing for a cap nobody set. a_cap_the_founder_holds_is_read_not_raised.sql')
 where exists (select 1 from public.it_engineer_finding where issue_key = 'duty:usage_vercel:cap_unknown:vercel_charges_month' and closed_at is null);

-- VERDICT: the routine no longer emits a cap_unknown item, and neither exact key is open.
select case when p.prosrc not like '%''cap_unknown:''%'
             and p.prosrc like '%v_unjudged%'
             and not exists (select 1 from public.it_engineer_finding
                              where closed_at is null
                                and issue_key in ('duty:usage_twilio:cap_unknown:twilio_balance',
                                                  'duty:usage_vercel:cap_unknown:vercel_charges_month'))
            then 'PROBE OK: fn_it_usage_watch records an unset cap as unjudged; both instruction-639 findings are closed by exact key'
            else 'PROBE FAILED: fn_it_usage_watch still emits cap_unknown, or an instruction-639 finding is still open' end verdict
  from pg_proc p where p.oid = 'public.fn_it_usage_watch(jsonb)'::regprocedure;
