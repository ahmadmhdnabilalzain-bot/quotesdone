-- PROBE for a_dead_domain_is_caught_before_the_invitation_not_by_its_bounce.sql. Seat: sales_engineer. Always raises; rolled back.
-- 1. A lead whose verdict is 8 days old is due again; one checked 6 days ago is not.
-- 2. A cached answer hands over its MX hosts.
-- 3. The 7 bounced addresses of 29-30 Oct are suppressed and none is eligible for an invitation.
do $probe$
declare v_lead bigint; v_due jsonb; v_hosts jsonb; v_bad int;
begin
  select c.lead_id into v_lead from public.lead_email_check c join public.leads l on l.id = c.lead_id
   where c.verdict = 'verified' and l.invite_status is null and c.email_md5 = md5(lower(btrim(l.email))) order by c.lead_id limit 1;
  if v_lead is null then raise exception 'PROBE FAILED: no verified lead to test the recheck on'; end if;
  update public.lead_email_check set checked_at = now() - interval '8 days' where lead_id = v_lead;
  update public.lead_email_check set checked_at = now() where lead_id <> v_lead;   -- only this lead can be due
  v_due := public.fn_sales_engineer_email_check_batch(50000);
  if not exists (select 1 from jsonb_array_elements(v_due) e where (e->>'lead_id')::bigint = v_lead) then
    raise exception 'PROBE FAILED: a verdict 8 days old was not asked again';
  end if;
  update public.lead_email_check set checked_at = now() - interval '6 days' where lead_id = v_lead;
  update public.email_domain_mx m set checked_at = now() - interval '6 days'
   from public.leads l where l.id = v_lead and m.domain = split_part(lower(btrim(l.email)), '@', 2);
  v_due := public.fn_sales_engineer_email_check_batch(50000);
  if exists (select 1 from jsonb_array_elements(v_due) e where (e->>'lead_id')::bigint = v_lead) then
    raise exception 'PROBE FAILED: a verdict 6 days old was asked again';
  end if;
  update public.lead_email_check set checked_at = now() - interval '8 days' where lead_id = v_lead;
  select e->'mx_hosts' into v_hosts from jsonb_array_elements(public.fn_sales_engineer_email_check_batch(50000)) e where (e->>'lead_id')::bigint = v_lead;
  if (select m.kind from public.email_domain_mx m join public.leads l on m.domain = split_part(lower(btrim(l.email)), '@', 2) where l.id = v_lead) = 'mx'
     and coalesce(jsonb_array_length(v_hosts), 0) = 0 then
    raise exception 'PROBE FAILED: a cached MX answer came without its hosts';
  end if;
  select count(*) into v_bad from public.notifications n join public.leads l on l.id = n.lead_id
   where n.id in (117550, 117555, 117557, 117559, 117560, 117580, 117584)
     and (public.fn_supplier_invite_eligible(l) or not exists (select 1 from public.email_suppressions s where s.email = lower(btrim(n.to_email))));
  if v_bad > 0 then raise exception 'PROBE FAILED: % bounced address(es) could be invited again', v_bad; end if;
  raise exception 'PROBE OK: 8-day verdict due, 6-day not; cached hosts %; 0 of 7 bounced addresses invitable', v_hosts;
end
$probe$;
