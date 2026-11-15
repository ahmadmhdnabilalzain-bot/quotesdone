-- PROBE for the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql. Seat: ceo. It always raises
-- CHK<<...>>, so every row it writes is rolled back; it writes rows only, names only its own ids and @example.invalid
-- addresses, and messages nobody (no sender is called). Run LOCALLY during work; on production only at release.
-- It proves: the limits are set; a change waits 24 hours whatever the writer asked, carries a reason and is one at a time;
-- the history is append-only; only the CEO changes a limit once it exists; a commitment is refused with no amount, above the
-- per-action limit and above what is left of today, and written when it fits; the classifiers read money by name (not
-- 'feedback' or 'payload'), a deploy, and a gate-weakening action; the message gates refuse a suppressed address, a mailbox
-- provider the placement bar keeps closed, an opted-out lead, WhatsApp with no opt-in and an unknown channel.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8); v_fail text := ''; v_r jsonb; v_per numeric; v_day numeric; v_n int;
  v_lead bigint; v_g text[];
begin
  v_per := public.fn_company_limit('per_action_aed'); v_day := public.fn_company_limit('daily_spend_aed');
  if v_per is null or v_day is null then v_fail := v_fail || 'the limits are not set; '; end if;

  -- a change waits a day, whatever the writer asked; the value in force does not move meanwhile
  if exists (select 1 from public.company_limit_change where limit_key = 'per_action_aed' and effective_at > now()) then
    v_r := public.fn_ceo_sets_company_limit('per_action_aed', v_per + 5, 'probe: a second waiting change must be refused here');
    if coalesce((v_r->>'ok')::boolean, true) then v_fail := v_fail || 'a second waiting change was taken; '; end if;
  else
    v_r := public.fn_ceo_sets_company_limit('per_action_aed', v_per + 5, 'probe ' || v_tag || ': the CEO raises the per-action limit');
    if not coalesce((v_r->>'ok')::boolean, false) then v_fail := v_fail || 'the CEO could not change a limit: ' || v_r::text || '; '; end if;
    if (v_r->>'effective_at')::timestamptz < now() + interval '23 hours 59 minutes' then v_fail := v_fail || 'a change took effect in under a day; '; end if;
    if public.fn_company_limit('per_action_aed') is distinct from v_per then v_fail := v_fail || 'the value in force moved before the day passed; '; end if;
    if coalesce((public.fn_ceo_sets_company_limit('per_action_aed', v_per + 9, 'probe ' || v_tag || ': another change while one waits')->>'ok')::boolean, true)
      then v_fail := v_fail || 'a second change was taken while one waited; '; end if;
  end if;
  insert into public.company_limit_change (limit_key, value_aed, reason, set_by, effective_at)
  values ('daily_spend_aed', v_day + 1, 'probe ' || v_tag || ': asking for an immediate change', 'ceo', now() - interval '1 day');
  if (select effective_at from public.company_limit_change where reason like 'probe ' || v_tag || ': asking%') < now() + interval '23 hours'
    then v_fail := v_fail || 'a direct insert chose its own effective time; '; end if;
  if coalesce((public.fn_ceo_sets_company_limit('daily_spend_aed', 1, 'too short')->>'ok')::boolean, true) then v_fail := v_fail || 'a change with no reason was taken; '; end if;
  begin
    insert into public.company_limit_change (limit_key, value_aed, reason, set_by, effective_at) values ('daily_spend_aed', 1, 'probe ' || v_tag || ': a seed after the first value', 'seed', now());
    v_fail := v_fail || 'a seed row was taken after the first value; ';
  exception when others then null; end;
  begin
    update public.company_limit_change set value_aed = value_aed + 1 where limit_key = 'daily_spend_aed';
    if found then v_fail := v_fail || 'a limit row was edited; '; end if;
  exception when others then null; end;
  begin
    delete from public.company_limit_change where limit_key = 'daily_spend_aed';
    if found then v_fail := v_fail || 'a limit row was deleted; '; end if;
  exception when others then null; end;

  -- commitments: refused with no amount, above the per-action limit, above what is left of today; written when it fits
  delete from public.company_spend_commitment where dubai_day = (now() at time zone 'Asia/Dubai')::date;   -- the probe's own day
  if coalesce((public.fn_company_spend_commit('marketing', 'probe.spend', 'probe:' || v_tag, null, 'probe')->>'committed')::boolean, true)
    then v_fail := v_fail || 'a commitment with no amount was written; '; end if;
  if coalesce((public.fn_company_spend_commit('marketing', 'probe.spend', 'probe:' || v_tag, v_per + 1, 'probe')->>'committed')::boolean, true)
    then v_fail := v_fail || 'a commitment above the per-action limit was written; '; end if;
  if least(v_per, v_day) >= 1 then
    v_r := public.fn_company_spend_commit('marketing', 'probe.spend', 'probe:' || v_tag, least(v_per, v_day), 'probe');
    if not coalesce((v_r->>'committed')::boolean, false) then v_fail := v_fail || 'a commitment that fits was refused: ' || v_r::text || '; '; end if;
    insert into public.company_spend_commitment (seat, action_class, subject, amount_aed, route) values ('marketing', 'probe.fill', 'probe', greatest(v_day, 0.01), 'probe');
    if coalesce((public.fn_company_spend_commit('marketing', 'probe.spend', 'probe:' || v_tag, 1, 'probe')->>'committed')::boolean, true)
      then v_fail := v_fail || 'a commitment past today''s limit was written; '; end if;
  end if;

  -- the classifiers
  if not (public.fn_action_is_money('meta_ads_spend') and public.fn_action_is_money('ad_spend') and public.fn_action_is_money('refund')
          and public.fn_action_is_money('boost_post') and public.fn_action_is_money('discount'))
     or public.fn_action_is_money('feedback') or public.fn_action_is_money('payload_check') or public.fn_action_is_money('matching')
     or public.fn_action_is_money('invitation') then v_fail := v_fail || 'money is misread by name; '; end if;
  if not (public.fn_action_is_destructive_production_change('deploy') and public.fn_action_is_destructive_production_change('migration_apply'))
     or public.fn_action_is_destructive_production_change('monitoring') then v_fail := v_fail || 'a deploy is misread; '; end if;
  if not (public.fn_action_weakens_a_message_gate('unsuppress_address') and public.fn_action_weakens_a_message_gate('resubscribe')
          and public.fn_action_weakens_a_message_gate('outreach', '{"bypasses_gate": true}'::jsonb))
     or public.fn_action_weakens_a_message_gate('invitation') then v_fail := v_fail || 'a gate-weakening action is misread; '; end if;

  -- the message gates for one named recipient (read, never changed)
  insert into public.email_suppressions (email, reason, source) values ('limits-probe-' || v_tag || '@example.invalid', 'unsubscribe', 'probe');
  v_g := public.fn_company_message_gates('email', 'limits-probe-' || v_tag || '@example.invalid', null);
  if not exists (select 1 from unnest(v_g) g where g like 'suppression:%') then v_fail := v_fail || 'a suppressed address passed: ' || array_to_string(v_g, ',') || '; '; end if;
  insert into public.leads (company_name, email, invite_status) values ('ZZ DEMO Limits Probe ' || v_tag, 'limits-probe-lead-' || v_tag || '@gmail.com', 'unsubscribed') returning id into v_lead;
  v_g := public.fn_company_message_gates('email', null, v_lead);
  if not exists (select 1 from unnest(v_g) g where g like 'opt-out:%') then v_fail := v_fail || 'an opted-out lead passed: ' || array_to_string(v_g, ',') || '; '; end if;
  update public.leads set invite_status = null, email = 'limits-probe-lead-' || v_tag || '@outlook.com' where id = v_lead;
  v_g := public.fn_company_message_gates('email', null, v_lead);
  if not exists (select 1 from unnest(v_g) g where g like 'inbox placement:%') then v_fail := v_fail || 'a Microsoft mailbox passed the placement bar (founder_instruction 1537): ' || array_to_string(v_g, ',') || '; '; end if;
  if cardinality(public.fn_company_message_gates('whatsapp', null, v_lead)) = 0 then v_fail := v_fail || 'WhatsApp with no opt-in passed; '; end if;
  if cardinality(public.fn_company_message_gates('sms', null, v_lead)) = 0 then v_fail := v_fail || 'an unknown channel passed; '; end if;

  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: limits per action % daily % >>', v_per, v_day;
end $probe$;
