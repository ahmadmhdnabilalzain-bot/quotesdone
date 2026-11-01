-- Pure probe: raises so everything rolls back; nobody outside this transaction ever sees its rows.
do $probe$
declare v_id bigint; n int; n_csat int; n_gaps int;
begin
  insert into public.contact_messages (name, email, message) values ('Probe', 'qd-probe@qd-probe-nobody.invalid.qd', 'A real-shaped question from the form') returning id into v_id;
  select count(*) into n from public.inbound_messages where raw->>'contact_message_id' = v_id::text and needs_review and owner_role is null and triaged_at is null;
  if n <> 1 then raise exception 'CHK<<FAIL contact form: % inbound row(s)>>', n; end if;
  insert into public.contact_messages (name, email, message) values ('ZZ DEMO', 'zz@example.invalid', 'ZZ DEMO question') returning id into v_id;
  select count(*) into n from public.inbound_messages where raw->>'contact_message_id' = v_id::text;
  if n <> 0 then raise exception 'CHK<<FAIL a demo form row reached triage>>'; end if;
  select count(*) into n_csat from public.notifications where type in ('support_csat_request', 'support_case_closed') and created_at = now();
  if n_csat <> 0 then raise exception 'CHK<<FAIL a closing case wrote % notice(s) to a person>>', n_csat; end if;
  select count(*) into n from public.support_case where state <> 'closed' and case_ref = 'QD-S-L5MLED';
  select count(*) into n_gaps from public.sales_knowledge_gap where status = 'open' and id in (195, 237);
  if n <> 0 or n_gaps <> 2 or exists (select 1 from public.agent_actions where id in (310914, 310916, 310918, 310921) and status <> 'done') then raise exception 'CHK<<FAIL settle: case open %, real questions open %>>', n, n_gaps; end if;
  raise exception 'CHK<<PROBE OK>>';
end $probe$;
