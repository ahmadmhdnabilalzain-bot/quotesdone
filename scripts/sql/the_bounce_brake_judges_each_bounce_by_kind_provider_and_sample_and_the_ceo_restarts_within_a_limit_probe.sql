-- PROBE of the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql. LOCAL only
-- (a Postgres 16 built from the schema mirror; never production: it writes sends and brakes). Always raises CHK<<...>>, so every
-- row, the pg_temp helper and the switches it moves roll back. Every address is on a domain made inside this transaction.
create function pg_temp.probe_sends(p_dom text, p_n int, p_kind text, p_k int, p_verified boolean, p_at timestamptz)
returns void language plpgsql as $h$
declare i int; v_id bigint; v_nid bigint; v_to text;
begin
  for i in 1..p_n loop
    v_to := 'buyer' || i || '.' || md5(random()::text) || '@' || p_dom;
    insert into public.leads (company_name, email, email_verified) values ('Probe ' || p_dom || ' ' || i, v_to, case when p_verified then 'verified' end)
    returning id into v_id;
    perform public.fn_sales_engineer_records_email_checks(jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', v_to,
      'verdict', 'verified', 'reason', 'probe', 'mailbox', 'named', 'mx_kind', 'mx')), '[]'::jsonb);
    insert into public.notifications (type, to_email, to_role, lead_id, subject, body, lang, status)
    values ('supplier_invite', v_to, 'supplier', v_id, 'A question', replace((select value from public.app_secrets where key = 'invite_body'), '{{company}}', 'Probe'), 'en', 'queued')
    returning id into v_nid;
    update public.notifications set status = 'sent', sent_at = p_at,
           provider_status = case when i <= p_k and p_kind in ('hard', 'policy', 'soft') then 'undelivered' else 'sent' end,
           provider_error_code = case when i <= p_k then case p_kind when 'hard' then 'bounce:5.1.1' when 'policy' then 'bounce:5.7.1' when 'soft' then 'bounce:5.2.2' end end
     where id = v_nid;
    if i <= p_k and p_kind in ('hard', 'complaint') then
      update public.leads set invite_status = case p_kind when 'hard' then 'bounced' else 'complained' end where id = v_id;
    else
      update public.leads set invite_status = 'sent' where id = v_id;
    end if;
  end loop;
end $h$;

do $probe$
declare
  v_p text[] := '{}'; j jsonb; r jsonb; v_g text := 'qd-probe-g-' || md5(random()::text) || '.ae'; v_o text := 'qd-probe-o-' || md5(random()::text) || '.ae';
  v_u text := 'qd-probe-u-' || md5(random()::text) || '.ae'; v_bid bigint; v_n int; v_id bigint; v_lim numeric;
begin
  -- the world this probe needs, every value rolled back by the raise
  insert into public.app_secrets (key, value) values ('invite_enabled', 'false'), ('supplier_outreach_golive', 'true'), ('invite_reachable_only', 'true'),
    ('invite_body', E'Hi {{company}} team,\n\nWould your company like to receive the requests of its trade?\n\nIf this isn''t relevant, reply "stop" and we won''t contact you again.')
  on conflict (key) do update set value = excluded.value;
  update public.invite_brake set resumed_at = coalesce(resumed_at, now() - interval '40 days'), fired_at = least(fired_at, now() - interval '41 days')
   where resumed_at is null or resumed_at > now() - interval '40 days';
  insert into public.email_domain_mx (domain, has_mx, kind, hosts) values (v_g, true, 'mx', array['aspmx.l.google.com']),
    (v_o, true, 'mx', array['mx1.' || v_o]), (v_u, true, 'mx', array['aspmx.l.google.com']);

  -- 1. the kind of a bounce
  if public.fn_invite_bounce_kind('bounce:5.1.1', 'undelivered', 'bounced') <> 'hard' then v_p := v_p || 'kind: 5.1.1 is not hard'::text; end if;
  if public.fn_invite_bounce_kind('bounce:gmail:NoSuchUser', 'undelivered', 'bounced') <> 'hard' then v_p := v_p || 'kind: gmail NoSuchUser is not hard'::text; end if;
  if public.fn_invite_bounce_kind('bounce:5.4.310', 'undelivered', 'bounced') <> 'hard' then v_p := v_p || 'kind: 5.4.310 is not hard'::text; end if;
  if public.fn_invite_bounce_kind('bounce:5.7.368', 'undelivered', 'sent') <> 'policy' then v_p := v_p || 'kind: 5.7.368 is not policy'::text; end if;
  if public.fn_invite_bounce_kind('bounce:5.4.316', 'undelivered', 'sent') <> 'soft' then v_p := v_p || 'kind: 5.4.316 is not soft'::text; end if;
  if public.fn_invite_bounce_kind(null, null, 'bounced') <> 'hard' then v_p := v_p || 'kind: a bounced lead with no code is not hard'::text; end if;
  if public.fn_invite_bounce_kind(null, 'sent', 'complained') <> 'complaint' then v_p := v_p || 'kind: a complaint is not a complaint'::text; end if;
  if public.fn_invite_bounce_kind(null, 'sent', 'sent') is not null then v_p := v_p || 'kind: a delivered send is a bounce'::text; end if;

  -- 2. the lower bound: 2 of 32 is under 3%, 3 of 20 over it, nothing of anything is 0
  if not (public.fn_invite_wilson_lower(2, 32) between 0.015 and 0.03) then v_p := v_p || ('wilson(2,32) = ' || public.fn_invite_wilson_lower(2, 32)); end if;
  if public.fn_invite_wilson_lower(3, 20) <= 0.03 then v_p := v_p || ('wilson(3,20) = ' || public.fn_invite_wilson_lower(3, 20)); end if;
  if public.fn_invite_wilson_lower(0, 10) <> 0 or public.fn_invite_wilson_lower(0, 0) <> 0 then v_p := v_p || 'wilson of nothing is not 0'::text; end if;

  -- 3. THE 13 NOV CASE: 2 hard bounces of 32 checked sends to Google mailboxes over 3 days. The old rule braked; this must not.
  perform pg_temp.probe_sends(v_g, 32, 'hard', 2, true, now() - interval '2 days');
  j := public.fn_invite_bounce_judgement(now());
  if (j->>'company_brake')::boolean then v_p := v_p || ('2 of 32 stopped the company: ' || coalesce(j->>'why', '')); end if;
  if jsonb_array_length(j->'held_classes') > 0 then v_p := v_p || ('2 of 32 held a class: ' || (j->>'held_classes')); end if;
  if coalesce((j->'cells'->'google:checked'->>'hard')::int, -1) <> 2 then v_p := v_p || ('the google:checked cell reads ' || coalesce(j->'cells'->>'google:checked', 'nothing')); end if;

  -- 4. the unchecked segment, which reachable_only does not send to, never stops the company (4 of 10 hard)
  perform pg_temp.probe_sends(v_u, 10, 'hard', 4, false, now() - interval '1 day');
  j := public.fn_invite_bounce_judgement(now());
  if (j->>'company_brake')::boolean then v_p := v_p || 'the unchecked segment stopped the company while reachable_only is on'::text; end if;

  -- 5. policy refusals confined to one provider class hold that class only (3 of 20 at 'other')
  perform pg_temp.probe_sends(v_o, 20, 'policy', 3, true, now() - interval '1 day');
  j := public.fn_invite_bounce_judgement(now());
  if not (j->'held_classes') ? 'other' then v_p := v_p || ('3 policy refusals of 20 did not hold the class: ' || (j->>'held_classes')); end if;
  if (j->>'company_brake')::boolean then v_p := v_p || 'a policy breach in one class stopped the company'::text; end if;
  if (j->'held_classes') ? 'google' then v_p := v_p || 'a clean class was held'::text; end if;

  -- 6. a real hard breach in the sent segment stops the company: 4 more hard bounces today at Google (6 of 52, 4 of 20 today)
  perform pg_temp.probe_sends(v_g, 20, 'hard', 4, true, now() - interval '5 minutes');
  j := public.fn_invite_bounce_judgement(now());
  if not coalesce((j->>'company_brake')::boolean, false) or j->>'company_reason' <> 'hard' then
    v_p := v_p || ('a statistically meaningful hard breach did not stop the company: ' || j::text); end if;

  -- 7. the judgement becomes a brake in one place, with its reason, and only while sending is on
  r := public.fn_invite_judge_and_brake('probe');
  if (r->>'braked')::boolean then v_p := v_p || 'braked while invite_enabled was already false'::text; end if;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  r := public.fn_invite_judge_and_brake('probe');
  select id into v_bid from public.invite_brake where resumed_at is null;
  if not coalesce((r->>'braked')::boolean, false) or v_bid is null then v_p := v_p || ('no brake: ' || r::text); end if;
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'false' then v_p := v_p || 'the brake left invite_enabled on'::text; end if;
  if not exists (select 1 from public.invite_brake_decision d where d.brake_id = v_bid and d.decision = 'brake' and d.actor = 'judge' and d.reason like '%hard bounce%') then
    v_p := v_p || 'the brake has no decision row with its reason'::text; end if;
  if not exists (select 1 from public.invite_brake_decision d where d.decision = 'class_held' and d.provider_class = 'other') then
    v_p := v_p || 'the held class has no decision row'::text; end if;
  begin
    update public.invite_brake_decision set reason = 'rewritten history here' where brake_id = v_bid;
    v_p := v_p || 'a decision was rewritten'::text;
  exception when raise_exception then null; end;

  -- 8. THE CEO'S RESTART: refused under 24 h; then allowed twice in 30 days by the seeded limit; the third is refused
  r := public.fn_ceo_restarts_invites('Probe: the CEO restarts after reading the judgement and the suppressions.');
  if coalesce((r->>'ok')::boolean, false) or r->>'reason' not like '%24 hours%' then v_p := v_p || ('a restart under 24 hours: ' || r::text); end if;
  if not exists (select 1 from public.invite_brake_decision where brake_id = v_bid and decision = 'restart_refused' and actor = 'ceo') then
    v_p := v_p || 'a refused restart was not recorded'::text; end if;
  r := public.fn_ceo_restarts_invites('too short');
  if coalesce((r->>'ok')::boolean, false) then v_p := v_p || 'a restart without a reason went through'::text; end if;
  v_lim := public.fn_growth_limit('ceo_invite_restarts_per_30d');
  if v_lim is distinct from 2 then v_p := v_p || ('the seeded limit reads ' || coalesce(v_lim::text, 'null')); end if;
  -- a lead the CEO can restart to (one checked Google lead never invited)
  insert into public.leads (company_name, email, email_verified) values ('Probe Fresh Trading', 'owner@' || v_g, 'verified') returning id into v_id;
  perform public.fn_sales_engineer_records_email_checks(jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', 'owner@' || v_g,
    'verdict', 'verified', 'reason', 'probe', 'mailbox', 'named', 'mx_kind', 'mx')), '[]'::jsonb);
  for v_n in 1..3 loop
    update public.invite_brake set fired_at = now() - interval '2 days' where resumed_at is null;
    r := public.fn_ceo_restarts_invites('Probe restart ' || v_n || ': bounced addresses suppressed, probation at ten invitations.');
    if v_n <= 2 and not coalesce((r->>'ok')::boolean, false) and r->>'reason' not like '%no checked lead%' then
      v_p := v_p || ('restart ' || v_n || ' within the limit was refused: ' || r::text); end if;
    if v_n <= 2 and coalesce((r->>'ok')::boolean, false) then
      if (select value from public.app_secrets where key = 'invite_enabled') <> 'true' then v_p := v_p || 'a CEO restart left invite_enabled off'::text; end if;
      if not exists (select 1 from public.invite_brake where restarted_by = 'ceo' and restarted_by_seat and resumed_at is not null) then
        v_p := v_p || 'a CEO restart is not on the seat''s probation'::text; end if;
      if exists (select 1 from public.leads where email like '%@' || v_g and invite_status = 'bounced'
                  and lower(email) not in (select email from public.email_suppressions)) then v_p := v_p || 'a bounced address was not suppressed'::text; end if;
      -- the next stop
      update public.app_secrets set value = 'false' where key = 'invite_enabled';
      insert into public.invite_brake (source, why) values ('probe', 'probe brake ' || v_n);
    end if;
    if v_n = 3 and (coalesce((r->>'ok')::boolean, false) or (r->>'reason' not like '%limit is reached%' and r->>'reason' not like '%no checked lead%')) then
      v_p := v_p || ('a third CEO restart in 30 days was not refused on the limit: ' || r::text); end if;
  end loop;

  -- 9. the CEO's limit is data: a change waits a day and the old value binds meanwhile; a seed cannot change it; rows are history
  r := public.fn_ceo_sets_growth_limit('ceo_invite_restarts_per_30d', 3, 'Probe: one more restart a month while the list is cleaned.');
  if not coalesce((r->>'ok')::boolean, false) or (r->>'effective_at')::timestamptz < now() + interval '23 hours' or public.fn_growth_limit('ceo_invite_restarts_per_30d') <> 2 then
    v_p := v_p || ('a limit change did not wait a day: ' || r::text); end if;
  begin
    update public.growth_limit_change set value = 99;
    v_p := v_p || 'a limit row was edited'::text;
  exception when raise_exception then null; end;

  -- 10. the CEO's review restarts a second-breach brake that the judgement of today does not support, with the evidence as reason
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  delete from public.invite_brake_decision where false;   -- (history stays)
  update public.invite_brake set resumed_at = now() where resumed_at is null;
  update public.notifications set provider_status = 'sent', provider_error_code = null where to_email like '%@' || v_g and sent_at > now() - interval '1 hour';
  update public.leads set invite_status = 'sent' where email like '%@' || v_g and invite_status = 'bounced'
     and id in (select lead_id from public.notifications where sent_at > now() - interval '1 hour');
  insert into public.invite_brake (source, why, fired_at, ceo_task_opened_at) values ('probe', 'bounce rate 6.3% over 3 days (2/32)', now() - interval '30 hours', now() - interval '29 hours')
  returning id into v_bid;
  r := public.fn_ceo_reviews_the_invite_brake();
  if r->>'decided' = 'restart' then
    -- the review's reason is the evidence; the restart itself is still bound by the limit (two were spent in step 8)
    if r->>'reason' not like 'Re-judged by bounce kind%2 hard of 32 sent%' then
      v_p := v_p || ('the CEO review decided without the evidence as its reason: ' || r::text); end if;
    if not (coalesce((r->'result'->>'ok')::boolean, false) or r->'result'->>'reason' like '%limit is reached%') then
      v_p := v_p || ('the CEO review''s restart failed for another reason: ' || r::text); end if;
    if not exists (select 1 from public.invite_brake_decision where brake_id = v_bid and actor = 'ceo' and decision in ('restart', 'restart_refused')) then
      v_p := v_p || 'the CEO review''s decision was not recorded'::text; end if;
  elsif r->>'decided' = 'hold' then
    if not exists (select 1 from public.invite_brake_decision where brake_id = v_bid and actor = 'ceo' and decision = 'hold') then v_p := v_p || 'a hold was not recorded'::text; end if;
  else
    v_p := v_p || ('the CEO review did not decide: ' || r::text);
  end if;

  -- 11. a complaint stops the campaign the same hour (the trigger)
  update public.invite_brake set resumed_at = now() where resumed_at is null;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  update public.leads set invite_status = 'complained'
   where id = (select n.lead_id from public.notifications n where n.to_email like '%@' || v_g and n.sent_at > now() - interval '1 hour' order by n.id limit 1);
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'false' then v_p := v_p || 'a complaint today did not stop the campaign'::text; end if;
  r := public.fn_ceo_restarts_invites('Probe: the CEO tries to restart over a complaint, which it may never do.');
  if coalesce((r->>'ok')::boolean, false) then v_p := v_p || 'the CEO restarted over a complaint'::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_p) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(v_p));
end $probe$;
