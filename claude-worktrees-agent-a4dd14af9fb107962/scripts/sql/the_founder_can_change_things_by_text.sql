-- THE COMMAND CHANNEL COULD ANSWER BUT NOT ACT.
--
-- Measured 13 Aug 2026: fn_identify_contact('whatsapp:+971509319355') returns
-- {audience: founder, name: management@quotesdone.com}, and wa_inbound's founder branch routes his
-- message to agent_brain, which answers anything and can queue agent_actions. wa_messages proves it
-- works - "print me last month revenue" on 10 Aug came back with "Last month's revenue: AED 0. No
-- transactions recorded in July 2026."
--
-- What it could not do is OBEY. "Change the weekly cap for emails into 15 instead of 10" became an
-- agent_actions row for somebody else to action, and there are 199 pending ones nothing drains. A
-- directive that becomes a queue entry is not a directive.
--
-- THE SHAPE. A language model never writes SQL here and never picks a table. It maps his sentence
-- to a KEY IN THIS REGISTRY, and this function does the rest: type check, bounds check, write,
-- audit, and return the old and new value so the reply can state what actually changed. A key that
-- is not in the registry is refused by name, not silently ignored.
--
-- WHAT IS DELIBERATELY ABSENT FROM THE REGISTRY, and why: the three go-live switches, every Stripe
-- and refund setting, and auto_action_max_aed. He reserved money and go-live to himself, and a
-- WhatsApp message is the wrong instrument for a decision he asked to make deliberately.
--
-- THE BOUNDS ARE RAILS ON A TEXT MESSAGE, NOT POLICY. They exist so a mistyped "150" cannot become
-- a sending reputation incident before anyone reads the reply. Every one of them is wide enough to
-- contain any number he would actually intend.

create table if not exists public.founder_directive (
  id            bigserial primary key,
  received_at   timestamptz not null default now(),
  actor         text        not null,
  channel       text        not null default 'whatsapp',
  inbound       text        not null,
  setting_key   text,
  old_value     text,
  new_value     text,
  applied       boolean     not null default false,
  refusal       text,
  meta          jsonb       not null default '{}'::jsonb
);
comment on table public.founder_directive is
  'Every instruction the founder sent over a message channel, what it resolved to, and whether it was applied. One row per directive, applied or refused - a refused directive is the more interesting half.';
create index if not exists founder_directive_received_idx on public.founder_directive (received_at desc);

-- ---------------------------------------------------------------------------------------------
-- THE REGISTRY. Read by the classifier prompt and by the writer below, so they can never disagree.
create or replace function public.fn_founder_settings()
 returns table (setting_key text, store text, kind text, min_val numeric, max_val numeric, current_value text, description text)
 language sql
 stable security definer
 set search_path to 'public', 'pg_catalog'
as $function$
  with reg(setting_key, store, kind, min_val, max_val, description) as (values
    ('invite_daily_cap',                 'app_secrets',     'int',    1,   200, 'How many supplier invitations may be sent in one day. fn_invite_ramp raises it on its own while the list behaves; setting it here overrides today.'),
    ('invite_max_bounce_rate',           'app_secrets',     'number', 0.01, 0.20,'The hard-bounce rate at which invites auto-pause.'),
    ('invite_enabled',                   'app_secrets',     'bool',   null, null,'Whether supplier invitations send at all.'),
    ('invite_target_per_category',       'app_secrets',     'int',    1,   100, 'How many confirmed suppliers a trade category is aiming for before it stops being prioritised.'),
    ('supplier_emails_enabled',          'app_secrets',     'bool',   null, null,'Whether any email may be sent to suppliers.'),
    ('email_enabled',                    'app_secrets',     'bool',   null, null,'The master switch for outbound email.'),
    ('wa_daily_cap',                     'app_secrets',     'int',    1,   500, 'How many WhatsApp messages the company may send in a day.'),
    ('wa_per_recipient_24h',             'app_secrets',     'int',    1,    10, 'How many WhatsApp messages one recipient may get in 24 hours.'),
    ('wa_autoreply_enabled',             'app_secrets',     'bool',   null, null,'Whether inbound WhatsApp gets an automatic reply.'),
    ('workflow_reflection_steps_per_day','decision_policy', 'int',    1,   200, 'How many non-demand workflow steps - health reports, forecasts, recommendations - may run in a day.'),
    ('cos_reflection_tasks_per_day',     'decision_policy', 'int',    1,   100, 'How many non-revenue tasks the chief of staff may hand to a large model in a day.'),
    ('match_max_fanout',                 'decision_policy', 'int',    1,    20, 'How many suppliers one RFQ may be sent to.'),
    ('match_max_fanout_per_trade',       'decision_policy', 'int',    1,    10, 'How many suppliers within a single trade one RFQ may reach.'),
    ('match_relevance_floor',            'decision_policy', 'int',    0,   100, 'The relevance score below which a supplier is not matched to an RFQ at all.'),
    ('confidence_min',                   'decision_policy', 'number', 0,     1, 'The confidence below which an agent escalates instead of acting.'),
    ('matching_strike_limit',            'decision_policy', 'int',    1,    10, 'How many times a supplier may ignore an RFQ before the matcher stops offering them work.')
  )
  select r.setting_key, r.store, r.kind, r.min_val, r.max_val,
         case r.store
           when 'app_secrets'     then (select s.value from public.app_secrets s where s.key = r.setting_key)
           when 'decision_policy' then (select d.value #>> '{}' from public.decision_policy d where d.key = r.setting_key)
         end,
         r.description
  from reg r;
$function$;

revoke all on function public.fn_founder_settings() from public;
revoke all on function public.fn_founder_settings() from anon;

-- ---------------------------------------------------------------------------------------------
-- THE WRITER. Validates against the registry, writes, audits, and reports the change in words.
create or replace function public.fn_founder_apply_setting(
  p_key text, p_value text, p_inbound text, p_actor text default 'founder', p_channel text default 'whatsapp')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_old text; v_new text; v_num numeric; v_bool boolean; v_refusal text;
begin
  select * into r from public.fn_founder_settings() s where s.setting_key = p_key;

  if not found then
    v_refusal := 'I cannot change "' || coalesce(p_key,'(nothing)') || '" from a message. '
              || 'The settings I can change this way are: '
              || (select string_agg(s.setting_key, ', ' order by s.setting_key) from public.fn_founder_settings() s)
              || '. Money, refunds and the three go-live switches are deliberately not on that list.';
    insert into public.founder_directive(actor, channel, inbound, setting_key, applied, refusal)
    values (p_actor, p_channel, left(coalesce(p_inbound,''), 2000), p_key, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal);
  end if;

  v_old := r.current_value;

  -- TYPE AND BOUNDS. A mistyped number must not become an incident before anyone reads the reply.
  if r.kind in ('int','number') then
    begin v_num := p_value::numeric; exception when others then
      v_refusal := '"' || p_value || '" is not a number, and ' || p_key || ' takes one.'; end;
    if v_refusal is null and r.kind = 'int' and v_num <> trunc(v_num) then
      v_refusal := p_key || ' takes a whole number; "' || p_value || '" is not one.';
    end if;
    if v_refusal is null and r.min_val is not null and v_num < r.min_val then
      v_refusal := p_key || ' has a floor of ' || r.min_val || ' on this channel, and you asked for ' || v_num || '.';
    end if;
    if v_refusal is null and r.max_val is not null and v_num > r.max_val then
      v_refusal := p_key || ' has a ceiling of ' || r.max_val || ' on this channel, and you asked for ' || v_num
                || '. Change it in the OS if you really mean that.';
    end if;
    v_new := case when r.kind = 'int' then trunc(v_num)::bigint::text else v_num::text end;
  elsif r.kind = 'bool' then
    v_bool := case lower(btrim(p_value))
                when 'true' then true when 'on' then true when 'yes' then true when 'enable' then true when 'enabled' then true when '1' then true
                when 'false' then false when 'off' then false when 'no' then false when 'disable' then false when 'disabled' then false when '0' then false
                else null end;
    if v_bool is null then v_refusal := '"' || p_value || '" is not on or off, and ' || p_key || ' is a switch.';
    else v_new := case when v_bool then 'true' else 'false' end; end if;
  else
    v_new := p_value;
  end if;

  if v_refusal is not null then
    insert into public.founder_directive(actor, channel, inbound, setting_key, old_value, applied, refusal)
    values (p_actor, p_channel, left(coalesce(p_inbound,''), 2000), p_key, v_old, false, v_refusal);
    return jsonb_build_object('ok', false, 'refusal', v_refusal, 'key', p_key, 'old', v_old);
  end if;

  if v_old is not distinct from v_new then
    insert into public.founder_directive(actor, channel, inbound, setting_key, old_value, new_value, applied, refusal)
    values (p_actor, p_channel, left(coalesce(p_inbound,''), 2000), p_key, v_old, v_new, false, 'already at that value');
    return jsonb_build_object('ok', true, 'unchanged', true, 'key', p_key, 'old', v_old, 'new', v_new,
      'message', p_key || ' is already ' || v_new || '. Nothing to change.');
  end if;

  if r.store = 'app_secrets' then
    update public.app_secrets set value = v_new, updated_at = now() where key = p_key;
  else
    update public.decision_policy set value = to_jsonb(v_new), updated_at = now() where key = p_key;
    -- decision_policy holds real jsonb types, not strings: keep numbers as numbers.
    if r.kind in ('int','number') then
      update public.decision_policy set value = to_jsonb(v_new::numeric) where key = p_key;
    elsif r.kind = 'bool' then
      update public.decision_policy set value = to_jsonb(v_new::boolean) where key = p_key;
    end if;
  end if;

  insert into public.founder_directive(actor, channel, inbound, setting_key, old_value, new_value, applied)
  values (p_actor, p_channel, left(coalesce(p_inbound,''), 2000), p_key, v_old, v_new, true);

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('founder_directive', 'ok',
          jsonb_build_object('key', p_key, 'old', v_old, 'new', v_new, 'channel', p_channel),
          'The founder changed ' || p_key || ' from ' || coalesce(v_old,'(unset)') || ' to ' || v_new
          || ' by ' || p_channel || '. Instruction: ' || left(coalesce(p_inbound,''), 200), now(), now());

  return jsonb_build_object('ok', true, 'key', p_key, 'old', v_old, 'new', v_new,
    'message', 'Done — ' || p_key || ' changed from ' || coalesce(v_old,'(unset)') || ' to ' || v_new || '. ' || r.description);
end $function$;

revoke all on function public.fn_founder_apply_setting(text, text, text, text, text) from public;
revoke all on function public.fn_founder_apply_setting(text, text, text, text, text) from anon;
