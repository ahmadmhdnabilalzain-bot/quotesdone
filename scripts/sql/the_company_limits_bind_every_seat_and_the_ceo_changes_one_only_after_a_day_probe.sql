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
  v_lead bigint; v_g text[]; v_locks int;
begin
  perform set_config('qd.limits_probe', 'rollback', true);   -- the owner may clear the probe's own day; it always rolls back
  v_per := public.fn_company_limit('per_action_aed'); v_day := public.fn_company_limit('daily_spend_aed');
  if v_per is null or v_day is null then v_fail := v_fail || 'the limits are not set; '; end if;

  -- REVIEW 4, item 1: a change written late in a long transaction still waits a full day from when it is written
  if not exists (select 1 from public.company_limit_change where limit_key = 'per_action_aed' and effective_at > clock_timestamp()) then
    perform pg_sleep(1.1);
    v_r := public.fn_ceo_sets_company_limit('per_action_aed', v_per + 5, 'probe ' || v_tag || ': written a second into a long transaction');
    if (v_r->>'effective_at')::timestamptz < now() + interval '24 hours 1 second' then
      v_fail := v_fail || 'a change late in a transaction waits less than a day (now(), not clock_timestamp()): ' || v_r::text || '; '; end if;
  end if;

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
  -- REVIEW_ceoplan item 4 (LOCAL): a real change of daily_spend_aed waiting made this insert raise and the probe fail. The probe
  -- reads the real state: with a change waiting, a second one is refused; with none, a direct insert waits a day whatever it asked.
  if exists (select 1 from public.company_limit_change where limit_key = 'daily_spend_aed' and effective_at > clock_timestamp()) then
    begin
      insert into public.company_limit_change (limit_key, value_aed, reason, set_by, effective_at)
      values ('daily_spend_aed', v_day + 1, 'probe ' || v_tag || ': asking for an immediate change', 'ceo', now() - interval '1 day');
      v_fail := v_fail || 'a second waiting change of daily_spend_aed was taken by a direct insert; ';
    exception when others then null; end;
  else
    insert into public.company_limit_change (limit_key, value_aed, reason, set_by, effective_at)
    values ('daily_spend_aed', v_day + 1, 'probe ' || v_tag || ': asking for an immediate change', 'ceo', now() - interval '1 day');
    if (select effective_at from public.company_limit_change where reason like 'probe ' || v_tag || ': asking%') < now() + interval '23 hours'
      then v_fail := v_fail || 'a direct insert chose its own effective time; '; end if;
  end if;
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

  -- REVIEW 4, item 1: the seats' role holds no write on either table, a TRUNCATE is refused, a commitment cannot be deleted
  -- (outside the probe's own seam), and a change written late in a long transaction still waits a full day
  if has_table_privilege('service_role', 'public.company_limit_change', 'INSERT') or has_table_privilege('service_role', 'public.company_limit_change', 'TRUNCATE')
     or has_table_privilege('service_role', 'public.company_spend_commitment', 'DELETE') or has_table_privilege('service_role', 'public.company_spend_commitment', 'UPDATE')
     or has_table_privilege('service_role', 'public.company_spend_commitment', 'INSERT')
    then v_fail := v_fail || 'service_role can write the limit tables directly; '; end if;
  -- REVIEW_ceoplan: nor its own authority or the CEO's caps
  if has_table_privilege('service_role', 'public.ceo_standing_grant', 'INSERT') or has_table_privilege('service_role', 'public.ceo_standing_grant', 'UPDATE')
     or has_table_privilege('service_role', 'public.ceo_standing_grant', 'DELETE') or has_table_privilege('service_role', 'public.decision_policy', 'INSERT')
     or has_table_privilege('service_role', 'public.decision_policy', 'UPDATE') or has_table_privilege('service_role', 'public.decision_policy', 'DELETE')
     or not has_table_privilege('service_role', 'public.decision_policy', 'SELECT') or not has_table_privilege('service_role', 'public.ceo_standing_grant', 'SELECT')
    then v_fail := v_fail || 'service_role can write ceo_standing_grant or decision_policy (a seat could grant itself authority or raise a cap), or can no longer read them; '; end if;
  begin
    truncate public.company_limit_change;
    v_fail := v_fail || 'company_limit_change was truncated; ';
  exception when others then null; end;
  begin
    truncate public.company_spend_commitment;
    v_fail := v_fail || 'company_spend_commitment was truncated; ';
  exception when others then null; end;
  perform set_config('qd.limits_probe', '', true);
  insert into public.company_spend_commitment (seat, action_class, subject, amount_aed, route) values ('marketing', 'probe.keep', 'probe:' || v_tag, 0.01, 'probe');
  begin
    delete from public.company_spend_commitment where subject = 'probe:' || v_tag;
    if found then v_fail := v_fail || 'a commitment was deleted (today''s money given back); '; end if;
  exception when others then null; end;
  begin
    update public.company_spend_commitment set amount_aed = 0.02 where subject = 'probe:' || v_tag;
    if found then v_fail := v_fail || 'a commitment was edited; '; end if;
  exception when others then null; end;
  perform set_config('qd.limits_probe', 'rollback', true);

  -- commitments: refused with no amount, above the per-action limit, above what is left of today; written when it fits
  delete from public.company_spend_commitment where dubai_day = (now() at time zone 'Asia/Dubai')::date;   -- the probe's own day
  select count(*) into v_locks from pg_locks where locktype = 'advisory' and pid = pg_backend_pid();
  if coalesce((public.fn_company_spend_commit('marketing', 'probe.spend', 'probe:' || v_tag, null, 'probe')->>'committed')::boolean, true)
    then v_fail := v_fail || 'a commitment with no amount was written; '; end if;
  if coalesce((public.fn_company_spend_commit('marketing', 'probe.spend', 'probe:' || v_tag, v_per + 1, 'probe')->>'committed')::boolean, true)
    then v_fail := v_fail || 'a commitment above the per-action limit was written; '; end if;
  if least(v_per, v_day) >= 1 then
    v_r := public.fn_company_spend_commit('marketing', 'probe.spend', 'probe:' || v_tag, least(v_per, v_day), 'probe');
    if not coalesce((v_r->>'committed')::boolean, false) then v_fail := v_fail || 'a commitment that fits was refused: ' || v_r::text || '; '; end if;
    -- review 4, item 2: the day's total is read and written under one company-wide lock, held to the end of the transaction
    if (select count(*) from pg_locks where locktype = 'advisory' and pid = pg_backend_pid()) <= v_locks
      then v_fail := v_fail || 'a commitment was written without the company''s spend lock; '; end if;
    insert into public.company_spend_commitment (seat, action_class, subject, amount_aed, route) values ('marketing', 'probe.fill', 'probe', greatest(v_day, 0.01), 'probe');
    if coalesce((public.fn_company_spend_commit('marketing', 'probe.spend', 'probe:' || v_tag, 1, 'probe')->>'committed')::boolean, true)
      then v_fail := v_fail || 'a commitment past today''s limit was written; '; end if;
  end if;

  -- REVIEW 4, item 3: the three-argument rule refuses money under a standing grant with no ceiling (it said may_act true for
  -- ('marketing', 'ad_boost', 1000)); a refund keeps its own path; a non-money action is answered as before
  insert into public.ceo_standing_grant (grant_key, grantee_role_id, action_class, scope_note, issued_by)
  values ('probe.ad_boost_' || v_tag, 'marketing', 'probe.ad_boost_' || v_tag, 'probe', 'ceo'),
         ('probe.refund_' || v_tag, 'accountant', 'probe.refund_' || v_tag, 'probe', 'ceo'),
         ('probe.report_' || v_tag, 'marketing', 'probe.report_' || v_tag, 'probe', 'ceo');
  if coalesce((public.fn_agent_may_act('marketing', 'probe.ad_boost_' || v_tag, 1000)->>'may_act')::boolean, true)
    then v_fail := v_fail || 'the three-argument rule allowed AED 1000 of ad spend outside the limits; '; end if;
  -- REVIEW_ceoplan item 6: with no amount, or zero, money is refused too
  if coalesce((public.fn_agent_may_act('marketing', 'probe.ad_boost_' || v_tag, null)->>'may_act')::boolean, true)
     or coalesce((public.fn_agent_may_act('marketing', 'probe.ad_boost_' || v_tag, 0)->>'may_act')::boolean, true)
     or coalesce((public.fn_agent_may_act('marketing', 'probe.ad_boost_' || v_tag)->>'may_act')::boolean, true)
    then v_fail := v_fail || 'the three-argument rule allowed ad spend with no amount or zero; '; end if;
  if not coalesce((public.fn_agent_may_act('accountant', 'probe.refund_' || v_tag, 50)->>'may_act')::boolean, false)
     or not coalesce((public.fn_agent_may_act('marketing', 'probe.report_' || v_tag)->>'may_act')::boolean, false)
    then v_fail := v_fail || 'the three-argument rule changed for a refund or a non-money action; '; end if;

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
  -- REVIEW_ceoplan item 6: the same Microsoft address named ONLY as an address (no lead id) is read against the bar (1537), and
  -- an address alone finds its lead's opt-out
  v_g := public.fn_company_message_gates('email', 'limits-probe-lead-' || v_tag || '@outlook.com', null);
  if not exists (select 1 from unnest(v_g) g where g like 'inbox placement:%') then v_fail := v_fail || 'a Microsoft address with no lead passed the placement bar: ' || array_to_string(v_g, ',') || '; '; end if;
  v_g := public.fn_company_message_gates('email', 'limits-probe-free-' || v_tag || '@hotmail.com', null);
  if not exists (select 1 from unnest(v_g) g where g like 'inbox placement:%') then v_fail := v_fail || 'an unknown Microsoft address passed the placement bar: ' || array_to_string(v_g, ',') || '; '; end if;
  update public.leads set invite_status = 'unsubscribed' where id = v_lead;
  v_g := public.fn_company_message_gates('email', 'LIMITS-PROBE-LEAD-' || v_tag || '@outlook.com', null);
  if not exists (select 1 from unnest(v_g) g where g like 'opt-out:%') then v_fail := v_fail || 'an opted-out lead named by its address alone passed: ' || array_to_string(v_g, ',') || '; '; end if;
  update public.leads set invite_status = null where id = v_lead;
  if cardinality(public.fn_company_message_gates('whatsapp', null, v_lead)) = 0 then v_fail := v_fail || 'WhatsApp with no opt-in passed; '; end if;
  if cardinality(public.fn_company_message_gates('sms', null, v_lead)) = 0 then v_fail := v_fail || 'an unknown channel passed; '; end if;

  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: limits per action % daily % >>', v_per, v_day;
end $probe$;
