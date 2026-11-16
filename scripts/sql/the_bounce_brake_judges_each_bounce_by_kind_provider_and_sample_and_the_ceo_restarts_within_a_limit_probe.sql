-- PROBE of the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql. LOCAL only
-- (a Postgres 16 built from the schema mirror, service_role given BYPASSRLS and the default table grants as on Supabase; never
-- production: it writes sends and brakes). Always raises CHK<<...>>, so every
-- row, the pg_temp helper and the switches it moves roll back. Every address is on a domain made inside this transaction.
create function pg_temp.probe_sends(p_dom text, p_n int, p_kind text, p_k int, p_verified boolean, p_at timestamptz,
                                     p_type text default 'supplier_invite', p_note_kind text default null)
returns void language plpgsql as $h$
declare i int; v_id bigint; v_nid bigint; v_to text;
begin
  for i in 1..p_n loop
    v_to := 'buyer' || i || '.' || md5(random()::text) || '@' || p_dom;
    insert into public.leads (company_name, email, email_verified) values ('Probe ' || p_dom || ' ' || i, v_to, case when p_verified then 'verified' end)
    returning id into v_id;
    perform public.fn_sales_engineer_records_email_checks(jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', v_to,
      'verdict', 'verified', 'reason', 'probe', 'mailbox', 'named', 'mx_kind', 'mx')), '[]'::jsonb);
    insert into public.notifications (type, kind, to_email, to_role, lead_id, subject, body, lang, status)
    values (p_type, p_note_kind, v_to, 'supplier', v_id, 'A question', replace((select value from public.app_secrets where key = 'invite_body'), '{{company}}', 'Probe'), 'en', 'queued')
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

-- one QUEUED campaign row to a fresh, checked lead (an invitation needs an eligible lead: fn_notifications_supplier_invite_is_whole)
create function pg_temp.probe_queued(p_to text, p_type text, p_kind text default null)
returns bigint language plpgsql as $h$
declare v_id bigint; v_nid bigint;
begin
  insert into public.leads (company_name, email, email_verified) values ('Probe Queued ' || p_to, p_to, 'verified') returning id into v_id;
  perform public.fn_sales_engineer_records_email_checks(jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', p_to,
    'verdict', 'verified', 'reason', 'probe', 'mailbox', 'named', 'mx_kind', 'mx')), '[]'::jsonb);
  insert into public.notifications (type, kind, to_email, to_role, lead_id, subject, body, lang, status)
  values (p_type, p_kind, p_to, 'supplier', v_id, 'A question', replace((select value from public.app_secrets where key = 'invite_body'), '{{company}}', 'Probe'), 'en', 'queued')
  returning id into v_nid;
  return v_nid;
end $h$;

-- the send-time check, or null when the routine does not exist (the probe then records it instead of stopping)
create function pg_temp.send_check(p_ids bigint[]) returns jsonb language plpgsql as $h$
begin
  return public.fn_invite_campaign_send_check(p_ids);
exception when undefined_function then return null;
end $h$;
create function pg_temp.verdict(p jsonb, p_id bigint) returns text language sql as $h$
  select coalesce((select e->>'verdict' || ':' || coalesce(e->>'why', '') from jsonb_array_elements(p) e where (e->>'id')::bigint = p_id), 'no answer')
$h$;

do $probe$
declare
  v_p text[] := '{}'; j jsonb; r jsonb; v_g text := 'qd-probe-g-' || md5(random()::text) || '.ae'; v_o text := 'qd-probe-o-' || md5(random()::text) || '.ae';
  v_u text := 'qd-probe-u-' || md5(random()::text) || '.ae'; v_bid bigint; v_n int; v_id bigint; v_lim numeric;
  v_x text := 'qd-probe-x-' || md5(random()::text) || '.ae'; v_c text := 'qd-probe-c-' || md5(random()::text) || '.ae';
  v_q text := 'qd-probe-q-' || md5(random()::text) || '.ae'; v_qa bigint; v_qb bigint; v_qs bigint; v_qx bigint; v_before int; v_after int;
  v_fut timestamptz := now() + interval '30 days';
begin
  -- the world this probe needs, every value rolled back by the raise
  insert into public.app_secrets (key, value) values ('invite_enabled', 'false'), ('supplier_outreach_golive', 'true'), ('invite_reachable_only', 'true'),
    ('invite_body', E'Hi {{company}} team,\n\nWould your company like to receive the requests of its trade?\n\nIf this isn''t relevant, reply "stop" and we won''t contact you again.')
  on conflict (key) do update set value = excluded.value;
  update public.invite_brake set resumed_at = coalesce(resumed_at, now() - interval '40 days'), fired_at = least(fired_at, now() - interval '41 days')
   where resumed_at is null or resumed_at > now() - interval '40 days';
  insert into public.email_domain_mx (domain, has_mx, kind, hosts) values (v_g, true, 'mx', array['aspmx.l.google.com']),
    (v_o, true, 'mx', array['mx1.' || v_o]), (v_u, true, 'mx', array['aspmx.l.google.com']),
    (v_x, true, 'mx', array[replace(v_x, '.', '-') || '.mail.protection.outlook.com']), (v_c, true, 'mx', array['aspmx.l.google.com']),
    (v_q, true, 'mx', array['mx1.' || v_q]);
  -- the placement gate, stubbed inside this transaction: Google and 'other' open (Microsoft never is, founder instruction 1537)
  create or replace function public.fn_invite_placement_open_providers(p_day date default null, p_now timestamptz default now())
  returns text[] language sql as $stub$ select array['google', 'other']::text[] $stub$;

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

  -- 2b. WHAT IS QUEUED OBEYS THE LIVE SWITCHES AT SEND TIME (review item 4): send_outbox asks fn_invite_campaign_send_check.
  --     (invite_enabled is on only while the check is asked: the sends written below must not brake through the trigger)
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  v_qa := pg_temp.probe_queued('a1@' || v_g, 'supplier_invite');
  v_qb := pg_temp.probe_queued('b1@' || v_o, 'supplier_invite_nudge');
  v_qs := pg_temp.probe_queued('seed@' || v_g, 'supplier_invite_seed', 'invite_m365_seed');
  v_qx := pg_temp.probe_queued('x1@' || v_x, 'supplier_invite');
  r := pg_temp.send_check(array[v_qa, v_qb, v_qs, v_qx]);
  if pg_temp.verdict(r, v_qa) not like 'send:%' then v_p := v_p || ('send check: an open google invitation is not sent: ' || coalesce(r::text, 'no check')); end if;
  if pg_temp.verdict(r, v_qb) not like 'send:%' then v_p := v_p || ('send check: an open nudge is not sent: ' || coalesce(r::text, 'no check')); end if;
  if pg_temp.verdict(r, v_qs) not like 'send:%' then v_p := v_p || 'send check: the placement seed is held'::text; end if;
  if pg_temp.verdict(r, v_qx) not like 'requeue:%' then v_p := v_p || ('send check: a Microsoft row (closed on the placement gate) is sent: ' || coalesce(r::text, 'no check')); end if;
  update public.app_secrets set value = 'false' where key = 'invite_enabled';

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
  -- the nudge already queued to the held class waits; the google invitation still goes
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  r := pg_temp.send_check(array[v_qa, v_qb]);
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  if pg_temp.verdict(r, v_qb) not like 'requeue:%held by the bounce judgement%' then
    v_p := v_p || ('send check: a nudge queued to a held class is sent: ' || coalesce(r::text, 'no check')); end if;
  if pg_temp.verdict(r, v_qa) not like 'send:%' then v_p := v_p || 'send check: a class hold stopped another class'::text; end if;

  -- 6. a real hard breach in the sent segment stops the company: 4 more hard bounces today at Google (6 of 52, 4 of 20 today)
  perform pg_temp.probe_sends(v_g, 20, 'hard', 4, true, now() - interval '5 minutes');
  j := public.fn_invite_bounce_judgement(now());
  if not coalesce((j->>'company_brake')::boolean, false) or j->>'company_reason' <> 'hard' then
    v_p := v_p || ('a statistically meaningful hard breach did not stop the company: ' || j::text); end if;
  -- a company stop cancels at send time, before any brake is written
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  r := pg_temp.send_check(array[v_qa]);
  if pg_temp.verdict(r, v_qa) not like 'cancel:%' then v_p := v_p || ('send check: a stopped company sends: ' || coalesce(r::text, 'no check')); end if;
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  r := pg_temp.send_check(array[v_qa]);
  if pg_temp.verdict(r, v_qa) not like 'cancel:%invite_enabled is false%' then v_p := v_p || ('send check: a paused campaign sends: ' || coalesce(r::text, 'no check')); end if;

  -- 7. the judgement becomes a brake in one place, with its reason, and only while sending is on
  r := public.fn_invite_judge_and_brake('probe');
  if (r->>'braked')::boolean then v_p := v_p || 'braked while invite_enabled was already false'::text; end if;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  r := public.fn_invite_judge_and_brake('probe');
  select id into v_bid from public.invite_brake where resumed_at is null;
  if not coalesce((r->>'braked')::boolean, false) or v_bid is null then v_p := v_p || ('no brake: ' || coalesce(r::text, 'no check')); end if;
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'false' then v_p := v_p || 'the brake left invite_enabled on'::text; end if;
  -- the pause cancelled every queued campaign row, the nudge included, with the reason; the seed is not campaign mail
  if (select count(*) from public.notifications where id in (v_qa, v_qb, v_qx) and status = 'cancelled' and last_error like 'cancelled: the supplier campaign was paused%') <> 3 then
    v_p := v_p || ('the pause left a queued invitation or nudge: ' || (select string_agg(id || ' ' || type || ' ' || status, ', ') from public.notifications where id in (v_qa, v_qb, v_qx))); end if;
  if (select status from public.notifications where id = v_qs) <> 'queued' then v_p := v_p || 'the pause cancelled the placement seed'::text; end if;
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
  if coalesce((r->>'ok')::boolean, false) or r->>'reason' not like '%24 hours%' then v_p := v_p || ('a restart under 24 hours: ' || coalesce(r::text, 'no check')); end if;
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
      v_p := v_p || ('restart ' || v_n || ' within the limit was refused: ' || coalesce(r::text, 'no check')); end if;
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
      v_p := v_p || ('a third CEO restart in 30 days was not refused on the limit: ' || coalesce(r::text, 'no check')); end if;
  end loop;

  -- 9. the CEO's limit is data: a change waits a day and the old value binds meanwhile; a seed cannot change it; rows are history
  r := public.fn_ceo_sets_growth_limit('ceo_invite_restarts_per_30d', 3, 'Probe: one more restart a month while the list is cleaned.');
  if not coalesce((r->>'ok')::boolean, false) or (r->>'effective_at')::timestamptz < now() + interval '23 hours' or public.fn_growth_limit('ceo_invite_restarts_per_30d') <> 2 then
    v_p := v_p || ('a limit change did not wait a day: ' || coalesce(r::text, 'no check')); end if;
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
      v_p := v_p || ('the CEO review decided without the evidence as its reason: ' || coalesce(r::text, 'no check')); end if;
    if not (coalesce((r->'result'->>'ok')::boolean, false) or r->'result'->>'reason' like '%limit is reached%') then
      v_p := v_p || ('the CEO review''s restart failed for another reason: ' || coalesce(r::text, 'no check')); end if;
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

  -- 12. ANY COMPLAINT, ON ANY CAMPAIGN MAIL, STOPS THE COMPANY (review item 2). A window 30 days on, apart from everything above:
  --     300 clean invitations and one complaint on a NUDGE. The Wilson rule let it pass (lower bound 0.07% at 300) and the old
  --     judgement never read a nudge.
  perform pg_temp.probe_sends(v_c, 300, 'none', 0, true, v_fut);
  perform pg_temp.probe_sends(v_c, 1, 'complaint', 1, true, v_fut + interval '1 hour', 'supplier_invite_nudge');
  j := public.fn_invite_bounce_judgement(v_fut + interval '1 day');
  if not coalesce((j->>'company_brake')::boolean, false) or j->>'company_reason' <> 'complaint' then
    v_p := v_p || ('one complaint on a nudge in 301 sends did not stop the company: ' || coalesce(j->>'why', '') || ' sent ' || coalesce(j->'all'->>'sent', '?')); end if;
  if coalesce((j->'all'->>'sent')::int, 0) <> 301 then v_p := v_p || ('the judgement does not read every campaign type: sent ' || coalesce(j->'all'->>'sent', '?')); end if;
  -- one lead with an invitation AND a nudge, marked bounced (no code): one hard bounce, not two
  v_n := pg_temp.probe_queued('twice@' || v_c, 'supplier_invite');
  select lead_id into v_id from public.notifications where id = v_n;
  update public.notifications set status = 'sent', sent_at = v_fut + interval '2 hours' where id = v_n;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, lang, status, sent_at)
  values ('supplier_invite_nudge', 'twice@' || v_c, 'supplier', v_id, 'q', 'Hi', 'en', 'sent', v_fut + interval '3 hours');
  update public.leads set invite_status = 'bounced' where id = v_id;
  j := public.fn_invite_bounce_judgement(v_fut + interval '1 day');
  if coalesce((j->'all'->>'hard')::int, -1) <> 1 then v_p := v_p || ('a lead mailed twice and bounced once counts ' || coalesce(j->'all'->>'hard', '?') || ' hard bounces'); end if;

  -- 13. POLICY REFUSALS HOLD A CLASS ON TWO (review item 4): 2 of 50 at 'other' in a window 60 days on; 1 of 50 90 days on does not
  perform pg_temp.probe_sends(v_q, 50, 'policy', 2, true, now() + interval '60 days');
  j := public.fn_invite_bounce_judgement(now() + interval '61 days');
  if not (j->'held_classes') ? 'other' then v_p := v_p || ('2 policy refusals of 50 did not hold the class: ' || (j->>'held_classes')); end if;
  perform pg_temp.probe_sends(v_q, 50, 'policy', 1, true, now() + interval '90 days');
  j := public.fn_invite_bounce_judgement(now() + interval '91 days');
  if (j->'held_classes') ? 'other' then v_p := v_p || 'a single policy refusal held the class'::text; end if;

  -- 14. A COMPLAINT ON THE LAST NOTE STOPS THE COMPANY THE SAME HOUR (the trigger; the last note is a nudge of kind invite_final_touch)
  update public.invite_brake set resumed_at = now() where resumed_at is null;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  insert into public.leads (company_name, email, email_verified, invite_status, lifecycle_stage) values ('Probe Parked Trading', 'parked@' || v_c, 'verified', 'sent', 'no_response')
  returning id into v_id;
  insert into public.notifications (type, kind, to_email, to_role, lead_id, subject, body, lang, status, sent_at)
  values ('supplier_invite_nudge', 'invite_final_touch', 'parked@' || v_c, 'supplier', v_id, 'One last note', 'Hi', 'en', 'sent', now() - interval '1 hour');
  update public.leads set invite_status = 'complained' where id = v_id;
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'false' then v_p := v_p || 'a complaint on the last note did not stop the company'::text; end if;
  if not exists (select 1 from public.invite_brake b join public.invite_brake_decision d on d.brake_id = b.id
                  where b.resumed_at is null and b.source = 'invite_same_day_brake' and d.decision = 'brake' and d.reason like '%invite_final_touch%') then
    v_p := v_p || 'the complaint stop has no brake row and decision naming the last note'::text; end if;

  -- 15. THE LIMITS ARE LOCKED (review item 3): service_role writes neither table; nobody truncates them; one waiting change per limit
  select count(*) into v_before from public.invite_brake_decision where actor = 'ceo' and decision = 'restart';
  begin
    set local role service_role;
    truncate public.invite_brake_decision;
    v_p := v_p || 'service_role truncated invite_brake_decision'::text;
    raise exception using errcode = 'P0099';
  exception when insufficient_privilege then null; when sqlstate 'P0099' then null; end;
  begin
    set local role service_role;
    insert into public.invite_brake_decision (decision, actor, reason) values ('restart', 'ceo', 'a forged restart row');
    v_p := v_p || 'service_role inserted into invite_brake_decision'::text;
    raise exception using errcode = 'P0099';
  exception when insufficient_privilege then null; when sqlstate 'P0099' then null; end;
  begin
    -- the reviewer's bypass: empty the history, then a "first" value is in force at once
    set local role service_role;
    truncate public.growth_limit_change;
    insert into public.growth_limit_change (limit_key, value, reason, set_by, effective_at)
    values ('ceo_invite_restarts_per_30d', 1000, 'raised by a direct write, no CEO, no wait', 'seed', now());
    v_p := v_p || 'service_role truncated growth_limit_change and wrote a first value of 1000, in force at once'::text;
    raise exception using errcode = 'P0099';
  exception when insufficient_privilege then null; when sqlstate 'P0099' then null; end;
  begin
    set local role service_role;
    insert into public.growth_limit_change (limit_key, value, reason, set_by, effective_at)
    values ('ceo_invite_restarts_per_30d', 1000, 'raised by a direct write, no CEO, no wait', 'ceo', now());
    v_p := v_p || 'service_role inserted a growth limit change'::text;
    raise exception using errcode = 'P0099';
  exception when insufficient_privilege then null; when raise_exception then null; when sqlstate 'P0099' then null; end;
  begin
    truncate public.growth_limit_change;   -- even the owner: the BEFORE TRUNCATE trigger refuses
    v_p := v_p || 'the owner truncated growth_limit_change'::text;
    raise exception using errcode = 'P0099';
  exception when raise_exception then null; when sqlstate 'P0099' then null; end;
  begin
    truncate public.invite_brake_decision;
    v_p := v_p || 'the owner truncated invite_brake_decision'::text;
    raise exception using errcode = 'P0099';
  exception when raise_exception then null; when sqlstate 'P0099' then null; end;
  select count(*) into v_after from public.invite_brake_decision where actor = 'ceo' and decision = 'restart';
  if v_after <> v_before then v_p := v_p || ('the CEO''s counted restarts changed from ' || v_before || ' to ' || v_after); end if;
  if public.fn_growth_limit('ceo_invite_restarts_per_30d') <> 2 then v_p := v_p || ('the limit in force moved: ' || public.fn_growth_limit('ceo_invite_restarts_per_30d')); end if;
  if has_table_privilege('service_role', 'public.growth_limit_change', 'INSERT') or has_table_privilege('service_role', 'public.growth_limit_change', 'TRUNCATE')
     or has_table_privilege('service_role', 'public.invite_brake_decision', 'INSERT') or has_table_privilege('service_role', 'public.invite_brake_decision', 'TRUNCATE') then
    v_p := v_p || 'service_role still holds a write privilege on the limits'::text; end if;
  -- one waiting change per limit (step 9 left one waiting): the routine refuses a second, and so does the trigger
  r := public.fn_ceo_sets_growth_limit('ceo_invite_restarts_per_30d', 4, 'Probe: a second change while the first still waits a day.');
  if coalesce((r->>'ok')::boolean, false) then v_p := v_p || 'a second waiting change was written'::text; end if;
  begin
    insert into public.growth_limit_change (limit_key, value, reason, set_by, effective_at)
    values ('ceo_invite_restarts_per_30d', 5, 'Probe: a direct second waiting change by the owner.', 'ceo', now());
    v_p := v_p || 'the trigger let a second waiting change in'::text;
    raise exception using errcode = 'P0099';
  exception when raise_exception then null; when sqlstate 'P0099' then null; end;
  if (select count(*) from public.growth_limit_change where limit_key = 'ceo_invite_restarts_per_30d' and effective_at > clock_timestamp()) <> 1 then
    v_p := v_p || 'not exactly one waiting change'::text; end if;
  -- the day of waiting is stamped on the wall clock, not the transaction's start
  if not exists (select 1 from public.growth_limit_change where limit_key = 'ceo_invite_restarts_per_30d' and set_by = 'ceo' and set_at > now()) then
    v_p := v_p || 'a change is stamped with the transaction start (now()), not clock_timestamp()'::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_p) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(v_p));
end $probe$;
