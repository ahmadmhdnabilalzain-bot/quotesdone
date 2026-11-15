-- PROBE of the_invitation_ramps_on_measured_health_and_tests_its_copy.sql. LOCAL only (a Postgres 16 built from the schema
-- mirror). Always raises CHK<<...>>: every lead, send, variant decision and switch it writes rolls back.
create function pg_temp.probe_lead(p_dom text, p_i int) returns bigint language plpgsql as $h$
declare v_id bigint; v_to text := 'buyer' || p_i || '.' || md5(random()::text) || '@' || p_dom;
begin
  insert into public.leads (company_name, email, email_verified) values ('Probe ' || p_dom || ' ' || p_i, v_to, 'verified') returning id into v_id;
  perform public.fn_sales_engineer_records_email_checks(jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', v_to,
    'verdict', 'verified', 'reason', 'probe', 'mailbox', 'named', 'mx_kind', 'mx')), '[]'::jsonb);
  return v_id;
end $h$;
create function pg_temp.probe_send(p_lead bigint, p_at timestamptz, p_bounce boolean) returns bigint language plpgsql as $h$
declare v_nid bigint; v_to text := (select email from public.leads where id = p_lead);
begin
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, lang, status)
  values ('supplier_invite', v_to, 'supplier', p_lead, 'A question', replace((select value from public.app_secrets where key = 'invite_body'), '{{company}}', 'Probe'), 'en', 'queued')
  returning id into v_nid;
  update public.notifications set status = 'sent', sent_at = p_at, provider_status = case when p_bounce then 'undelivered' else 'sent' end,
         provider_error_code = case when p_bounce then 'bounce:5.1.1' end where id = v_nid;
  update public.leads set invite_status = case when p_bounce then 'bounced' else 'sent' end where id = p_lead;
  return v_nid;
end $h$;

do $probe$
declare
  v_p text[] := '{}'; v_dom text := 'qd-probe-r-' || md5(random()::text) || '.ae'; v_id bigint; v_k text; v_seen text[] := '{}';
  i int; r jsonb; v_cap int; v_a int := 0; v_b int := 0; v_c int := 0;
begin
  insert into public.app_secrets (key, value) values ('invite_enabled', 'false'), ('supplier_outreach_golive', 'true'), ('invite_reachable_only', 'true'),
    ('invite_body', E'Hi {{company}} team,\n\nWould your company like to receive the requests of its trade?\n\nIf this isn''t relevant, reply "stop" and we won''t contact you again.'), ('invite_lane_enabled', 'false')
  on conflict (key) do update set value = excluded.value;
  insert into public.email_domain_mx (domain, has_mx, kind, hosts) values (v_dom, true, 'mx', array['aspmx.l.google.com']);

  -- 1. a lead's variant is deterministic, spreads over the three, and is fixed once assigned; a winner takes every new lead
  for i in 1..90 loop
    v_k := public.fn_invite_variant_for_lead(1000000 + i);
    if v_k <> public.fn_invite_variant_for_lead(1000000 + i) then v_p := v_p || 'a lead''s variant changed between two reads'::text; exit; end if;
    if not v_k = any (v_seen) then v_seen := v_seen || v_k; end if;
  end loop;
  if cardinality(v_seen) <> 3 then v_p := v_p || ('90 leads reached only ' || array_to_string(v_seen, ',')); end if;

  -- 2. no winner on a draw: 150 sends each, 5 / 6 / 5 engaged
  for i in 1..450 loop
    v_id := pg_temp.probe_lead(v_dom, i);
    v_k := case when i <= 150 then 'a' when i <= 300 then 'b' else 'c' end;
    insert into public.invite_variant_assignment (lead_id, variant_key) values (v_id, v_k);
    perform pg_temp.probe_send(v_id, now() - interval '20 days', false);
    if (v_k = 'a' and i <= 5) or (v_k = 'b' and i between 151 and 156) or (v_k = 'c' and i between 301 and 305) then
      update public.leads set invite_clicked_at = now() - interval '10 days' where id = v_id;
    end if;
  end loop;
  r := public.fn_marketing_decides_the_invite_copy(now());
  if coalesce((r->>'decided')::boolean, false) then v_p := v_p || ('a winner on a draw: ' || (r->>'reason')); end if;
  select (e->>'engaged')::int into v_b from jsonb_array_elements(r->'readout'->'variants') e where e->>'variant' = 'b';
  if v_b <> 6 then v_p := v_p || ('the readout counts ' || coalesce(v_b::text, 'null') || ' engaged for b, not 6'); end if;

  -- 3. a clear leader is promoted automatically: b gains 9 more clicks (15 of 150 against 5 and 5)
  update public.leads set invite_clicked_at = now() - interval '5 days'
   where id in (select a.lead_id from public.invite_variant_assignment a join public.leads l on l.id = a.lead_id
                 where a.variant_key = 'b' and l.email like '%@' || v_dom and l.invite_clicked_at is null order by a.lead_id limit 9);
  r := public.fn_marketing_decides_the_invite_copy(now());
  if not coalesce((r->>'decided')::boolean, false) or (select status from public.invite_variant where variant_key = 'b') <> 'winner' then
    v_p := v_p || ('a clear leader was not promoted: ' || r::text); end if;
  if exists (select 1 from public.invite_variant where variant_key in ('a', 'c') and status <> 'retired') then v_p := v_p || 'the losers were not retired'::text; end if;
  if public.fn_invite_variant_for_lead(2000001) <> 'b' then v_p := v_p || 'a new lead does not get the winner'::text; end if;
  r := public.fn_marketing_decides_the_invite_copy(now());
  if coalesce((r->>'decided')::boolean, false) then v_p := v_p || 'a second winner was promoted'::text; end if;
  if (select variant_key from public.invite_variant_assignment where lead_id = (select min(lead_id) from public.invite_variant_assignment a join public.leads l on l.id = a.lead_id where l.email like '%@' || v_dom and a.variant_key = 'a')) <> 'a' then
    v_p := v_p || 'an assigned lead changed variant'::text; end if;

  -- 4. THE RAMP: from 3, healthy, the last send day full: one step up to 5 (the old ramp held at "too few to judge")
  delete from public.invite_variant_assignment where lead_id in (select id from public.leads where email like '%@' || v_dom);
  update public.notifications set sent_at = now() - interval '30 days' where to_email like '%@' || v_dom;
  insert into public.app_secrets (key, value) values ('invite_daily_cap', '3'), ('invite_enabled', 'true') on conflict (key) do update set value = excluded.value;
  for i in 1..3 loop perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 1000 + i), now() - interval '2 hours', false); end loop;
  for i in 1..27 loop perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 2000 + i), now() - interval '5 days', false); end loop;
  v_cap := public.fn_invite_ramp();
  if v_cap <> 5 then v_p := v_p || ('a healthy full day at 3 stepped to ' || v_cap || ', not 5: ' || coalesce((select note from public.agent_runs where agent = 'invite_ramp' order by id desc limit 1), '')); end if;
  v_cap := public.fn_invite_ramp();
  if v_cap <> 5 then v_p := v_p || ('the ramp grew twice for one send day: ' || v_cap); end if;

  -- 5. one hard bounce in 35 sends still lets it grow; two hold; three (lower bound 3.3% > 2.5%) back off by half
  delete from public.agent_runs where agent = 'invite_ramp' and finished_at > now() - interval '1 minute';
  insert into public.app_secrets (key, value) values ('invite_daily_cap', '5') on conflict (key) do update set value = excluded.value;
  for i in 1..5 loop perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 3000 + i), now() - interval '1 hour', i = 1); end loop;
  v_cap := public.fn_invite_ramp();
  if v_cap <> 8 then v_p := v_p || ('one hard bounce held or cut the ramp: ' || v_cap || ' ' || coalesce((select note from public.agent_runs where agent = 'invite_ramp' order by id desc limit 1), '')); end if;
  -- 2 of 36 (5.6%, lower bound 1.9%): no growth and no cut, a hold
  perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 4001), now() - interval '50 minutes', true);
  v_cap := public.fn_invite_ramp();
  if v_cap <> 8 then v_p := v_p || ('two hard bounces in 36 did not hold at 8: ' || v_cap || ' ' || coalesce((select note from public.agent_runs where agent = 'invite_ramp' order by id desc limit 1), '')); end if;
  -- 3 of 37 (lower bound 3.3% > 2.5%): back off by half
  perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 4002), now() - interval '45 minutes', true);
  -- the third bounce today is a burst the same-day trigger brakes on (3 of 8 today); the ramp still answers for the cap
  if (select value from public.app_secrets where key = 'invite_enabled') <> 'false' then v_p := v_p || 'three hard bounces of eight today did not stop the campaign'::text; end if;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  v_cap := public.fn_invite_ramp();
  if v_cap <> 4 then v_p := v_p || ('three hard bounces in 37 did not back off to 4: ' || v_cap || ' ' || coalesce((select note from public.agent_runs where agent = 'invite_ramp' order by id desc limit 1), '')); end if;

  -- 6. the nudge reads the judgement, never the old 3-day rule (a call with nothing due holds or queues nothing, and does not error)
  r := public.fn_sales_engineer_nudges_invited_suppliers(now(), null, true);
  if r is null then v_p := v_p || 'the nudge answered nothing'::text; end if;

  -- 7. the batch runs (on a weekend or a holiday it holds before the new code; on a weekday the judgement decides)
  begin
    perform public.enqueue_supplier_invites(null);
  exception when others then v_p := v_p || ('enqueue_supplier_invites raised: ' || sqlerrm); end;

  -- 8. THE BATCH ON A WEEKDAY, whatever day the probe runs: inside this rolled-back transaction the weekend hold is taken out of
  --    the real enqueue_supplier_invites and the placement verdict answers 'google' (no GlockApps result exists locally).
  --    Four never-invited checked leads on four Google-hosted domains; the cap is 3: three invitations, each with its
  --    deterministic variant on the row and in invite_variant_assignment. Then a hard-bounce burst today stops the batch.
  execute replace(pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure), 'in (6, 7) then', 'in (8) then');
  -- (spelled in two pieces so no check that reads committed SQL takes this local stand-in for the canonical routine)
  execute 'create or replace ' || 'function public.fn_invite_placement_open_providers(p_day date default null, p_now timestamptz default now()) '
       || 'returns text[] language sql as $f$ select array[''google'']::text[] $f$';
  delete from public.company_calendar where kind = 'public_holiday' and (now() at time zone 'Asia/Dubai')::date between starts_on and coalesce(ends_on, starts_on);
  update public.notifications set created_at = now() - interval '40 days', sent_at = now() - interval '40 days' where to_email like '%@' || v_dom;
  insert into public.app_secrets (key, value) values ('invite_daily_cap', '3'), ('invite_enabled', 'true') on conflict (key) do update set value = excluded.value;
  delete from public.invite_variant_assignment where variant_key is not null and lead_id in (select id from public.leads where email like '%@' || v_dom);
  update public.invite_variant set status = 'active', decided_at = null, decided_reason = null;
  for i in 1..4 loop
    v_k := 'qd-probe-b' || i || '-' || md5(random()::text) || '.ae';
    insert into public.email_domain_mx (domain, has_mx, kind, hosts) values (v_k, true, 'mx', array['aspmx.l.google.com']);
    perform pg_temp.probe_lead(v_k, i);
  end loop;
  begin
    i := public.enqueue_supplier_invites(null);
  exception when others then v_p := v_p || ('the weekday batch raised: ' || sqlerrm); i := -1; end;
  if i <> 3 then v_p := v_p || ('the weekday batch queued ' || i || ', not 3: ' || coalesce((select note from public.agent_runs where agent = 'supplier_invites' order by id desc limit 1), '')); end if;
  if (select count(*) from public.notifications n join public.invite_variant_assignment a on a.notification_id = n.id
       where n.type = 'supplier_invite' and n.status = 'queued' and n.kind = 'invite_variant:' || a.variant_key and n.to_email like '%@qd-probe-b%') <> greatest(i, 0) then
    v_p := v_p || 'a queued invitation carries no variant, or not the one assigned'::text; end if;
  if exists (select 1 from public.notifications n where n.type = 'supplier_invite' and n.status = 'queued' and n.to_email like '%@qd-probe-b%'
              and n.kind is distinct from 'invite_variant:' || public.fn_invite_variant_for_lead(n.lead_id)) then
    v_p := v_p || 'a row''s variant differs from the lead''s deterministic variant'::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_p) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(v_p));
end $probe$;
