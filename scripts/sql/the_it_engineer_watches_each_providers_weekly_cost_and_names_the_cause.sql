-- THE IT ENGINEER WATCHES EACH PROVIDER'S WEEKLY COST AND NAMES THE CAUSE.
--
-- Seat: it_engineer (the watch); each finding is answered by the seat that owns the cause.
-- Founder instruction 1013, item 8 (29 Sep 2026): each week compare the spend on Supabase, Vercel, Resend,
-- Twilio and OpenRouter with the previous period, from their billing/usage APIs where available, otherwise
-- the accountant's journals and ai_cost_log. A jump above a stated threshold opens an it_engineer finding
-- with the cause, and the owning seat fixes it. Founder rule: NO spending caps. This routine only reads,
-- records and explains; nothing here refuses, pauses or throttles any call or any send.
--
-- WHERE EACH NUMBER COMES FROM (the best source that exists for each provider, measured 29 Sep 2026):
--   openrouter  ai_cost_log.cost_aed, every model call, per seat / task class / model. Metered, so the
--               period is 7 days against the 7 before.
--   twilio      it_spend_daily source 'twilio': Twilio's own Usage Records API, read daily by duty 11
--               (_shared/it_scheduled_readings.ts). USD, converted at the it_threshold usd_aed_rate.
--               7 days against the 7 before.
--   supabase    no billing API reachable from the edge (the bill needs a management token; duty 11 says
--   vercel      so) and Vercel's token has no billing scope; Resend publishes no billing API. These are
--   resend      read from the accountant's posted journals: expense lines (account 6xxx) whose line or
--               journal memo names the provider. A subscription is billed monthly, so a 7-day window
--               would jump every billing week; these compare 30 days against the 30 before.
--
-- A JUMP: this period > previous * cost_watch_jump_multiple AND this - previous >= cost_watch_floor_aed.
-- A provider with nothing before and at least the floor now is a jump (a new cost is news). Both numbers
-- are rows of public.it_threshold with their reason; a provider with no readings is recorded
-- 'unavailable', never a finding and never a pass.
--
-- THE CAUSE AND THE OWNER, in the finding's evidence and title:
--   openrouter  the seat / task class / model whose cost rose most; that seat owns it (ceo if unnamed).
--   twilio      the costliest day of the week and the WhatsApp replies sent this week vs last;
--               customer_support owns WhatsApp and OTP traffic.
--   resend      the journal entries of the period; customer_support owns sender health (duty 10's rule).
--   supabase, vercel  the journal entries of the period; it_engineer owns the platform.
-- Findings open and close through fn_it_duty_settle('cost_watch', ...): a provider back under the
-- threshold the next week closes its own finding, with the measurement.

insert into public.it_threshold (key, value, unit, basis) values
  ('cost_watch_jump_multiple', 1.5, 'x',
   'A provider costing more than 1.5 times its previous period is not drift: pre-launch weeks move by tens of percent, not by half again.'),
  ('cost_watch_floor_aed', 50, 'AED',
   'Under AED 50 of increase is never a finding whatever its multiple: at pre-launch volumes AED 2 becoming AED 6 is noise, not a cause to chase.'),
  ('usd_aed_rate', 3.6725, 'AED per USD',
   'The UAE dirham is pegged to the US dollar at 3.6725 by the Central Bank of the UAE.')
on conflict (key) do nothing;

create table if not exists public.it_cost_watch_week (
  week_ending  date not null,
  provider     text not null check (provider in ('supabase', 'vercel', 'resend', 'twilio', 'openrouter')),
  basis        text not null check (basis in ('usage_api', 'ai_cost_log', 'journals', 'unavailable')),
  period_days  integer not null check (period_days > 0),
  this_aed     numeric,
  prior_aed    numeric,
  jumped       boolean not null default false,
  owner_seat   text,
  cause        text,
  detail       jsonb not null default '{}'::jsonb,
  measured_at  timestamptz not null default now(),
  primary key (week_ending, provider)
);
comment on table public.it_cost_watch_week is
  'it_engineer: one row per provider per weekly cost watch (founder instruction 1013 item 8). Watches and explains; never caps.';
alter table public.it_cost_watch_week enable row level security;
drop policy if exists it_cost_watch_week_service_role_only on public.it_cost_watch_week;
create policy it_cost_watch_week_service_role_only on public.it_cost_watch_week
  as permissive for all to public using (false) with check (false);
revoke all on public.it_cost_watch_week from anon, authenticated;

-- The jump rule alone, so the probe and any reader apply exactly the same comparison.
create or replace function public.fn_it_cost_jumped(p_this numeric, p_prior numeric)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(p_this, 0) - coalesce(p_prior, 0) >= public.fn_it_threshold('cost_watch_floor_aed')
     and coalesce(p_this, 0) > coalesce(p_prior, 0) * public.fn_it_threshold('cost_watch_jump_multiple')
$fn$;
revoke execute on function public.fn_it_cost_jumped(numeric, numeric) from public, anon, authenticated;
grant execute on function public.fn_it_cost_jumped(numeric, numeric) to service_role;

create or replace function public.fn_it_cost_watch_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_now timestamptz := now();
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_fx numeric := public.fn_it_threshold('usd_aed_rate');
  v_items jsonb := '[]'::jsonb; v_rows jsonb := '[]'::jsonb;
  p text; v_this numeric; v_prior numeric; v_days int; v_basis text; v_owner text; v_cause text; v_detail jsonb;
  v_top record; v_n int;
begin
  foreach p in array array['openrouter', 'twilio', 'supabase', 'vercel', 'resend'] loop
    v_detail := '{}'::jsonb; v_cause := null; v_top := null;
    if p = 'openrouter' then
      v_days := 7; v_basis := 'ai_cost_log';
      select coalesce(sum(cost_aed) filter (where occurred_at >= v_now - interval '7 days'), 0),
             coalesce(sum(cost_aed) filter (where occurred_at < v_now - interval '7 days'), 0), count(*)
        into v_this, v_prior, v_n
        from public.ai_cost_log where occurred_at >= v_now - interval '14 days' and occurred_at < v_now;
      if v_n = 0 then v_basis := 'unavailable'; end if;
      select coalesce(seat, agent_key, 'unnamed') seat, coalesce(task_class, '?') task_class, coalesce(model_used, '?') model,
             round(coalesce(sum(cost_aed) filter (where occurred_at >= v_now - interval '7 days'), 0), 2) now_aed,
             round(coalesce(sum(cost_aed) filter (where occurred_at < v_now - interval '7 days'), 0), 2) before_aed
        into v_top
        from public.ai_cost_log where occurred_at >= v_now - interval '14 days' and occurred_at < v_now
       group by 1, 2, 3
       order by coalesce(sum(cost_aed) filter (where occurred_at >= v_now - interval '7 days'), 0)
              - coalesce(sum(cost_aed) filter (where occurred_at < v_now - interval '7 days'), 0) desc
       limit 1;
      v_owner := case when v_top.seat in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing')
                      then v_top.seat else 'ceo' end;
      if v_top.seat is not null then
        v_cause := format('%s / %s on %s rose from AED %s to AED %s', v_top.seat, v_top.task_class, v_top.model, v_top.before_aed, v_top.now_aed);
        v_detail := jsonb_build_object('top_rise', to_jsonb(v_top));
      end if;
    elsif p = 'twilio' then
      v_days := 7; v_basis := 'usage_api'; v_owner := 'customer_support';
      select coalesce(sum(d.amount_minor / 100.0 * case when upper(d.currency) = 'AED' then 1 else v_fx end)
                        filter (where d.day > v_week - 7), 0),
             coalesce(sum(d.amount_minor / 100.0 * case when upper(d.currency) = 'AED' then 1 else v_fx end)
                        filter (where d.day <= v_week - 7), 0), count(*)
        into v_this, v_prior, v_n
        from public.it_spend_daily d where d.source = 'twilio' and d.day > v_week - 14 and d.day <= v_week;
      if v_n = 0 then v_basis := 'unavailable'; end if;
      select d.day, round(d.amount_minor / 100.0, 2) amount, upper(d.currency) currency into v_top
        from public.it_spend_daily d where d.source = 'twilio' and d.day > v_week - 7 and d.day <= v_week
       order by d.amount_minor desc limit 1;
      v_detail := jsonb_build_object('costliest_day', to_jsonb(v_top),
        'whatsapp_replies_sent_this_week', (select count(*) from public.wa_messages w where w.created_at >= v_now - interval '7 days' and w.reply is not null and coalesce(w.sent, false)),
        'whatsapp_replies_sent_week_before', (select count(*) from public.wa_messages w where w.created_at >= v_now - interval '14 days' and w.created_at < v_now - interval '7 days' and w.reply is not null and coalesce(w.sent, false)));
      if v_top.day is not null then
        v_cause := format('the costliest day was %s (%s %s); WhatsApp replies sent %s this week against %s the week before',
                          v_top.day, v_top.amount, v_top.currency, v_detail->>'whatsapp_replies_sent_this_week', v_detail->>'whatsapp_replies_sent_week_before');
      end if;
    else
      v_days := 30; v_basis := 'journals';
      v_owner := case when p = 'resend' then 'customer_support' else 'it_engineer' end;
      select coalesce(sum(l.debit - l.credit) filter (where j.entry_date > v_week - 30), 0),
             coalesce(sum(l.debit - l.credit) filter (where j.entry_date <= v_week - 30), 0), count(*)
        into v_this, v_prior, v_n
        from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id
       where j.status = 'posted' and l.account_code like '6%'
         and j.entry_date > v_week - 60 and j.entry_date <= v_week
         and (coalesce(l.memo, '') ~* ('\m' || p || '\M') or coalesce(j.memo, '') ~* ('\m' || p || '\M'));
      if v_n = 0 then v_basis := 'unavailable'; v_this := null; v_prior := null; end if;
      v_detail := jsonb_build_object('entries_this_period', (
        select coalesce(jsonb_agg(jsonb_build_object('entry_no', j.entry_no, 'date', j.entry_date, 'memo', left(coalesce(l.memo, j.memo), 120),
                                                     'aed', l.debit - l.credit) order by l.debit - l.credit desc), '[]'::jsonb)
          from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id
         where j.status = 'posted' and l.account_code like '6%' and j.entry_date > v_week - 30 and j.entry_date <= v_week
           and (coalesce(l.memo, '') ~* ('\m' || p || '\M') or coalesce(j.memo, '') ~* ('\m' || p || '\M'))));
      if jsonb_array_length(v_detail->'entries_this_period') > 0 then
        v_cause := 'the journal entries of the period: ' || (select string_agg(format('%s %s AED %s', e->>'date', e->>'memo', e->>'aed'), '; ')
                                                               from (select e from jsonb_array_elements(v_detail->'entries_this_period') e limit 3) s);
      end if;
    end if;

    v_rows := v_rows || jsonb_build_object('provider', p, 'basis', v_basis, 'period_days', v_days,
      'this_aed', round(v_this, 2), 'prior_aed', round(v_prior, 2),
      'jumped', v_basis <> 'unavailable' and public.fn_it_cost_jumped(v_this, v_prior),
      'owner_seat', v_owner, 'cause', v_cause, 'detail', v_detail);

    insert into public.it_cost_watch_week (week_ending, provider, basis, period_days, this_aed, prior_aed, jumped, owner_seat, cause, detail, measured_at)
    values (v_week, p, v_basis, v_days, round(v_this, 2), round(v_prior, 2),
            v_basis <> 'unavailable' and public.fn_it_cost_jumped(v_this, v_prior), v_owner, v_cause, v_detail, v_now)
    on conflict (week_ending, provider) do update
      set basis = excluded.basis, period_days = excluded.period_days, this_aed = excluded.this_aed, prior_aed = excluded.prior_aed,
          jumped = excluded.jumped, owner_seat = excluded.owner_seat, cause = excluded.cause, detail = excluded.detail,
          measured_at = excluded.measured_at;

    if v_basis <> 'unavailable' and public.fn_it_cost_jumped(v_this, v_prior) then
      v_items := v_items || jsonb_build_object(
        'item', p, 'subject', p, 'owner_seat', v_owner, 'blast', 'agent_facing', 'affected', 1,
        'title', left(format('%s cost AED %s over the last %s days against AED %s the %s before: %s',
                             p, round(v_this, 2), v_days, round(v_prior, 2), v_days, coalesce(v_cause, 'no cause recorded')), 300),
        'evidence', jsonb_build_object('this_aed', round(v_this, 2), 'prior_aed', round(v_prior, 2), 'period_days', v_days,
                                       'basis', v_basis, 'cause', v_cause, 'detail', v_detail,
                                       'no_cap', 'founder rule: this watches and explains, it never blocks'));
    end if;
  end loop;

  return jsonb_build_object('week_ending', v_week, 'providers', v_rows,
                            'settled', public.fn_it_duty_settle('cost_watch', v_items));
end $fn$;
revoke execute on function public.fn_it_cost_watch_tick() from public, anon, authenticated;
grant execute on function public.fn_it_cost_watch_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.cost_watch', 'it_engineer', interval '7 days', 'fn_it_cost_watch_tick',
   'the weekly cost watch: Supabase, Vercel, Resend, Twilio and OpenRouter against the previous period; a jump opens a finding with its cause for the owning seat. Never a cap.',
   'scripts/sql/the_it_engineer_watches_each_providers_weekly_cost_and_names_the_cause.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
