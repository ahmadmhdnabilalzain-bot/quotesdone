-- Pure probe: raises so everything rolls back; nobody outside this transaction ever sees its rows.
do $probe$
declare v_id bigint; n int; n_csat int; n_gaps int; v_sup text; r record; v_row public.inbound_messages;
begin
  -- A clean first message is released to triage: no owner, no hold.
  insert into public.contact_messages (name, email, message) values ('Probe', 'qd-ok@qd-probe-nobody.invalid.qd', 'A real-shaped question from the form') returning id into v_id;
  select count(*) into n from public.inbound_messages where raw->>'contact_message_id' = v_id::text and needs_review and owner_role is null and triaged_at is null and raw->>'held_reason' is null;
  if n <> 1 then raise exception 'CHK<<FAIL a clean first message was not released: % row(s)>>', n; end if;
  -- KNOWN-BAD CONTROLS: each must be HELD for the seat (owner set, an action item, the status says so), never lost, never released.
  insert into public.email_suppressions (email, reason) values ('qd-sup@qd-probe-nobody.invalid.qd', 'hard_bounce:permanent');
  select l.email into v_sup from public.leads l where l.email ~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' and public.fn_mail_sender_known(l.email) = 'supplier' limit 1;
  for r in select * from (values
    ('qd-ok@qd-probe-nobody.invalid.qd', null, 'second_message_in_24h'),
    ('qd-sup@qd-probe-nobody.invalid.qd', null, 'suppressed_or_bounced'),
    ('management@quotesdone.com', null, 'founder_address'),
    ('postmaster@qd-probe-nobody.invalid.qd', null, 'role_address'),
    ('noreply@qd-probe-nobody.invalid.qd', null, 'role_address'),
    ('qd-nomx@qd-probe-nobody.invalid.qd', 'held:no_mx', 'no_mx'),
    ('qd-ip@qd-probe-nobody.invalid.qd', 'held:ip_daily_limit', 'ip_daily_limit'),
    ('not-an-address', null, 'address_shape'),
    (v_sup, null, 'known_supplier_lane')) x(addr, src, want) where x.addr is not null loop
    insert into public.contact_messages (name, email, message, source) values ('Probe', r.addr, 'A real-shaped question from the form', r.src) returning id into v_id;
    select * into v_row from public.inbound_messages where raw->>'contact_message_id' = v_id::text;
    if v_row.id is null then raise exception 'CHK<<FAIL % was LOST: no inbound row>>', r.want; end if;
    if v_row.owner_role is distinct from 'customer_support' or v_row.raw->>'held_reason' is distinct from r.want then
      raise exception 'CHK<<FAIL % was not held (owner %, reason %)>>', r.want, v_row.owner_role, v_row.raw->>'held_reason'; end if;
    if not exists (select 1 from public.agent_actions where kind = 'inbound_review' and target_table = 'inbound_messages' and target_id = v_row.id::text and status = 'pending') then
      raise exception 'CHK<<FAIL % was held but no seat item names it>>', r.want; end if;
    if (select status from public.contact_messages where id = v_id) <> 'held_for_customer_support' then raise exception 'CHK<<FAIL % status>>', r.want; end if;
  end loop;
  -- THE DAY'S CEILING: 20 released answers already today, the 21st is held.
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review) select 'qd-fill' || g || '@qd-probe-nobody.invalid.qd', 'contact-form@quotesdone.com', 'fill', 'fill', true from generate_series(1, 20) g;
  insert into public.contact_messages (name, email, message) values ('Probe', 'qd-ceiling@qd-probe-nobody.invalid.qd', 'A real-shaped question from the form') returning id into v_id;
  if (select raw->>'held_reason' from public.inbound_messages where raw->>'contact_message_id' = v_id::text) is distinct from 'daily_ceiling' then raise exception 'CHK<<FAIL the daily ceiling did not hold>>'; end if;
  -- a demo row never reaches triage; a complaint keeps its own path
  insert into public.contact_messages (name, email, message) values ('ZZ DEMO', 'zz@example.invalid', 'ZZ DEMO question') returning id into v_id;
  select count(*) into n from public.inbound_messages where raw->>'contact_message_id' = v_id::text;
  if n <> 0 then raise exception 'CHK<<FAIL a demo form row reached triage>>'; end if;
  -- nothing in this probe wrote a notice to anyone
  select count(*) into n from public.notifications where to_email like '%qd-probe-nobody.invalid.qd' and created_at >= now() - interval '1 minute';
  if n <> 0 then raise exception 'CHK<<FAIL the form wrote % notice(s)>>', n; end if;
  select count(*) into n_csat from public.notifications where type in ('support_csat_request', 'support_case_closed') and created_at = now();
  if n_csat <> 0 then raise exception 'CHK<<FAIL a closing case wrote % notice(s) to a person>>', n_csat; end if;
  select count(*) into n from public.support_case where state <> 'closed' and case_ref = 'QD-S-L5MLED';
  select count(*) into n_gaps from public.sales_knowledge_gap where status = 'open' and id in (195, 237);
  if n <> 0 or n_gaps <> 2 or exists (select 1 from public.agent_actions where id in (310914, 310916, 310918, 310921) and status <> 'done') then raise exception 'CHK<<FAIL settle: case open %, real questions open %>>', n, n_gaps; end if;
  raise exception 'CHK<<PROBE OK>>';
end $probe$;
