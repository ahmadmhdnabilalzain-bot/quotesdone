-- PROBE (aborted transaction, commits nothing, emails nobody): the_founder_sees_tomorrows_supplier_invitations_at_six.sql
-- A ZZ DEMO lead is planted to prove a fixture never reaches the list; the day's row and the queued founder email
-- are rolled back by the final raise, so send_outbox never sees them. No real lead is written.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_sees_tomorrows_supplier_invitations_at_six_probe.sql --apply
do $probe$
declare
  v_bad text := ''; v_t jsonb; v_l jsonb; v_a jsonb; v_n int; v_same boolean; v_demo bigint; v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_at18 timestamptz := ((now() at time zone 'Asia/Dubai')::date + time '18:05') at time zone 'Asia/Dubai';
  v_leads_before bigint; v_leads_after bigint;
begin
  select count(*) into v_leads_before from public.leads where invite_status is not null;
  -- 1. before 18:00 nothing is due
  if (public.fn_customer_support_campaign_list_tick(((v_today + time '17:00') at time zone 'Asia/Dubai'))->>'due')::boolean then v_bad := v_bad || ' due_before_six'; end if;
  -- 2. the weekend is skipped: after Friday 25 Sep the next sending day is Monday 28 Sep
  v_l := public.fn_supplier_campaign_next_list('2026-09-25');
  if v_l->>'send_day' <> '2026-09-28' or jsonb_array_length(v_l->'skipped') <> 2 then v_bad := v_bad || ' weekend:' || (v_l->>'send_day'); end if;
  -- 3. a ZZ DEMO stub never reaches the list
  insert into public.leads (company_name, email, emirate)
  values ('ZZ DEMO supplier list probe', 'zz-demo-list-probe@example.invalid', 'Dubai') returning id into v_demo;
  -- 4. at 18:05 the list is the sender's own selection, in the sender's order, and the switch state is said
  v_t := public.fn_customer_support_campaign_list_tick(v_at18);
  if not coalesce((v_t->>'pdf_pending')::boolean, false) then v_bad := v_bad || ' not_due_at_six:' || v_t; end if;
  select rows into v_l from public.supplier_campaign_daily_list where id = (v_t->>'id')::bigint;
  select coalesce(array_agg((x->>'lead_id')::bigint order by (x->>'n')::int), '{}')
         = coalesce((select array_agg(c.lead_id) from public.fn_supplier_invite_candidates((v_t->>'planned')::int) c), '{}')
    into v_same from jsonb_array_elements(v_l) x;
  if not v_same then v_bad := v_bad || ' list_differs_from_sender'; end if;
  if jsonb_array_length(v_l) <> (v_t->>'planned')::int then v_bad := v_bad || ' rows<>planned'; end if;
  if exists (select 1 from jsonb_array_elements(v_l) x where (x->>'lead_id')::bigint = v_demo or x->>'company' ~* 'zz\s*demo') then v_bad := v_bad || ' demo_listed'; end if;
  if exists (select 1 from jsonb_array_elements(v_l) x where x->>'email' !~ '^.{0,2}\*\*\*@') then v_bad := v_bad || ' email_not_masked'; end if;
  if not (v_t->>'switch_on')::boolean and (select subject from public.supplier_campaign_daily_list where id = (v_t->>'id')::bigint) !~ 'OFF' then
    v_bad := v_bad || ' off_not_said';
  end if;
  -- 5. a failed render is retained; a rendered file is mailed once, to his one mailbox
  v_a := public.fn_customer_support_campaign_list_attach((v_t->>'id')::bigint, 'agent-docs', null, null, null, 'probe render failure');
  if coalesce((v_a->>'ok')::boolean, true) then v_bad := v_bad || ' failed_render_sent'; end if;
  v_a := public.fn_customer_support_campaign_list_attach((v_t->>'id')::bigint, 'agent-docs', 'zz-demo/probe.pdf', null, 1, null);
  if not coalesce((v_a->>'ok')::boolean, false) or v_a->>'to' is distinct from lower(split_part((select value from public.app_secrets where key = 'admin_emails'), ',', 1)) then
    v_bad := v_bad || ' attach:' || v_a;
  end if;
  if (public.fn_customer_support_campaign_list_tick(v_at18)->>'due')::boolean then v_bad := v_bad || ' sent_twice'; end if;
  select count(*) into v_leads_after from public.leads where invite_status is not null;
  if v_leads_after <> v_leads_before then v_bad := v_bad || ' leads_touched'; end if;
  raise exception 'CHK<<%>>', case when v_bad = '' then 'PROBE OK: ' || (v_t->>'planned') || ' supplier(s) listed = the sender''s selection; switch_on=' || (v_t->>'switch_on')
                                   || '; weekend skipped; ZZ DEMO excluded; mailed once to ' || (v_a->>'to')
                                   else 'PROBE FAILED:' || v_bad end;
end
$probe$;
