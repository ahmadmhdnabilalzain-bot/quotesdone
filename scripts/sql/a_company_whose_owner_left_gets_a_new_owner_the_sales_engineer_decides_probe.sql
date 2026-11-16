-- PROBE: A COMPANY WHOSE OWNER LEFT GETS A NEW OWNER; THE SALES ENGINEER DECIDES. Seats: sales_engineer (decides), customer_support.
-- Agent: W3_PEOPLE, 16 Nov 2026. Pure probe: no DDL, never applied; run after
-- a_company_whose_owner_left_gets_a_new_owner_the_sales_engineer_decides.sql on a LOCAL Postgres 16. It always raises, so every row
-- is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. only a member of the company may ask (the owner and a stranger are refused); the ask is ONE case per company, holding the
--      evidence the sales engineer reasons over (the licence's name and number, the members, the owner's last sign-in and the mail
--      that bounced from him, earlier hand-overs); it is a pending task on the sales engineer's queue; the member and the owner are
--      each told at once (never silent);
--   2. it is listed for the sales engineer's decision until decided;
--   3. "ask" sends his question to the member and waits; the member's next word reopens the same case;
--   4. "transfer" never moves the company at once: the owner has three days to keep it, and if he does nothing moves and the member
--      is told;
--   5. after the three days the company is the member's: he signs, the old owner's address, listed e-mail and WhatsApp stop speaking
--      as the owner and he is NOT kept as a member (he left); both are told; the task is closed;
--   6. "refuse" tells the member why; an unknown decision and a second decision are refused.
do $probe$
declare
  fails text := ''; s_a bigint; s_b bigint; s_c bigint; j jsonb; v_claim bigint; v_claim_b bigint; v_claim_c bigint; n int;
  v_owner text := 'zz-demo-w3o-owner@example.invalid'; v_mem text := 'zz-demo-w3o-mem@example.invalid'; v_view text := 'zz-demo-w3o-view@example.invalid';
  v_owner_b text := 'zz-demo-w3o-ownerb@example.invalid'; v_mem_b text := 'zz-demo-w3o-memb@example.invalid';
  v_owner_c text := 'zz-demo-w3o-ownerc@example.invalid'; v_mem_c text := 'zz-demo-w3o-memc@example.invalid';
begin
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, licence_legal_name, trade_license_no,
                            contact_name, whatsapp_opt, owner_phone_verified)
  values ('ZZ DEMO W3O Company', v_owner, v_owner, true, 'Dubai', '+971500000731', true, 'ZZ DEMO W3O COMPANY L.L.C', 'ZZ-123456', 'ZZ DEMO Old Owner', 'same', true)
  returning id into s_a;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, licence_legal_name, whatsapp_opt, whatsapp_phone, whatsapp_verified_at)
  values ('ZZ DEMO W3O Second', v_owner_b, v_owner_b, true, 'Dubai', '+971500000732', true, 'ZZ DEMO W3O SECOND L.L.C', 'other', '+971500000733', now())
  returning id into s_b;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified)
  values ('ZZ DEMO W3O Third', v_owner_c, v_owner_c, true, 'Sharjah', '+971500000734', true) returning id into s_c;
  insert into public.supplier_member (lead_id, email, name, role, status, invited_by, accepted_at, email_verified_at)
  values (s_a, v_mem, 'ZZ DEMO Member Estimator', 'estimator', 'active', v_owner, now() - interval '200 days', now() - interval '200 days'),
         (s_a, v_view, 'ZZ DEMO Member Viewer', 'viewer', 'active', v_owner, now() - interval '20 days', now() - interval '20 days'),
         (s_b, v_mem_b, 'ZZ DEMO Member B', 'estimator', 'active', v_owner_b, now() - interval '300 days', now() - interval '300 days'),
         (s_c, v_mem_c, 'ZZ DEMO Member C', 'viewer', 'active', v_owner_c, now() - interval '5 days', now() - interval '5 days');
  -- his mail bounces: evidence the case shows
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status, provider_status, created_at)
  values ('supplier_strike_warning', v_owner, 'supplier', s_a, 'ZZ DEMO', 'ZZ DEMO', 'email', 'sent', 'undelivered', now() - interval '10 days');

  -- 1. who may ask, and the case
  if coalesce(public.fn_supplier_ownership_claim_open(s_a, v_owner, 'ZZ DEMO me', 'portal')->>'code', '') <> 'is_owner' then fails := fails || ' 1:owner_claimed'; end if;
  if coalesce(public.fn_supplier_ownership_claim_open(s_a, 'zz-demo-w3o-stranger@example.invalid', 'ZZ DEMO', 'portal')->>'code', '') <> 'not_a_member' then fails := fails || ' 1:stranger'; end if;
  j := public.fn_supplier_ownership_claim_open(s_a, upper(v_mem), 'ZZ DEMO the owner left the company in October and his mailbox is closed', 'email');
  v_claim := (j->>'claim_id')::bigint;
  if not coalesce((j->>'ok')::boolean, false) or v_claim is null then fails := fails || ' 1:open(' || coalesce(j::text, '') || ')'; end if;
  if coalesce((public.fn_supplier_ownership_claim_open(s_a, v_view, 'ZZ DEMO me too', 'portal')->>'already')::boolean, false) is not true then fails := fails || ' 1:second_case'; end if;
  j := (select evidence from public.supplier_ownership_claim where id = v_claim);
  if coalesce(j->'company'->>'licence_legal_name', '') <> 'ZZ DEMO W3O COMPANY L.L.C' or coalesce(j->'company'->>'trade_licence_no', '') <> 'ZZ-123456'
     or jsonb_array_length(coalesce(j->'members', '[]'::jsonb)) <> 2 or coalesce((j->'owner'->>'mail_bounced_90d')::int, 0) < 1
     or coalesce(j->'claimant'->>'role', '') <> 'estimator' or not (j->'owner' ? 'last_sign_in_at') then
    fails := fails || ' 1:evidence(' || coalesce(left(j::text, 400), 'none') || ')'; end if;
  if not exists (select 1 from public.agent_actions a where a.kind = 'supplier_ownership_claim' and a.agent = 'sales_engineer' and a.status = 'pending'
                  and a.target_id = 'supplier_ownership_claim:' || v_claim) then fails := fails || ' 1:no_task'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_ownership_claim_received' and lower(to_email) = v_mem) then fails := fails || ' 1:member_not_told'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_ownership_claim_owner_notice' and lower(to_email) = v_owner and body ~ 'Keep ownership') then fails := fails || ' 1:owner_not_told'; end if;

  -- 2. listed for the decision
  if not exists (select 1 from jsonb_array_elements(public.fn_supplier_ownership_claims_due(10)) x where (x->>'claim_id')::bigint = v_claim and x ? 'evidence') then fails := fails || ' 2:not_due'; end if;

  -- 3. ask, then his next word reopens the same case
  j := public.fn_supplier_ownership_claim_decide(v_claim, 'ask', 'ZZ DEMO the owner signed in last week; proof needed', 'Please send the current trade licence page that names the manager, or a letter on the company letterhead.', 'sales_engineer');
  if not coalesce((j->>'ok')::boolean, false) or (select state from public.supplier_ownership_claim where id = v_claim) <> 'waiting_claimant' then fails := fails || ' 3:ask(' || coalesce(j::text, '') || ')'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_ownership_claim_question' and lower(to_email) = v_mem and body ~ 'letterhead') then fails := fails || ' 3:question_not_sent'; end if;
  if exists (select 1 from jsonb_array_elements(public.fn_supplier_ownership_claims_due(10)) x where (x->>'claim_id')::bigint = v_claim) then fails := fails || ' 3:due_while_waiting'; end if;
  j := public.fn_supplier_ownership_claim_open(s_a, v_mem, 'ZZ DEMO attached the licence page naming me as manager', 'portal');
  if (j->>'claim_id')::bigint is distinct from v_claim or (select state from public.supplier_ownership_claim where id = v_claim) <> 'open'
     or (select reason from public.supplier_ownership_claim where id = v_claim) !~ 'naming me as manager' then fails := fails || ' 3:reopen(' || coalesce(j::text, '') || ')'; end if;

  -- 4. transfer waits three days; the owner keeps it
  j := public.fn_supplier_ownership_claim_decide(v_claim, 'transfer', 'ZZ DEMO licence names him; owner mail bounces', 'The company passes to you in three days unless the owner keeps it.', 'sales_engineer');
  if (select state from public.supplier_ownership_claim where id = v_claim) <> 'approved_waiting'
     or (select effective_at from public.supplier_ownership_claim where id = v_claim) < now() + interval '2 days' then fails := fails || ' 4:not_waiting(' || coalesce(j::text, '') || ')'; end if;
  perform public.fn_supplier_ownership_claims_complete();
  if (select claimed_by from public.leads where id = s_a) <> v_owner then fails := fails || ' 4:moved_early'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_ownership_claim_owner_notice' and lower(to_email) = v_owner and body ~ 'three days|3 days') then fails := fails || ' 4:owner_not_warned'; end if;
  if coalesce(public.fn_supplier_ownership_claim_object(s_a, v_mem)->>'code', '') <> 'owner_only' then fails := fails || ' 4:member_objected'; end if;
  j := public.fn_supplier_ownership_claim_object(s_a, v_owner);
  if not coalesce((j->>'ok')::boolean, false) or (select state from public.supplier_ownership_claim where id = v_claim) <> 'objected' then fails := fails || ' 4:object(' || coalesce(j::text, '') || ')'; end if;
  update public.supplier_ownership_claim set effective_at = now() - interval '1 minute' where id = v_claim;
  perform public.fn_supplier_ownership_claims_complete();
  if (select claimed_by from public.leads where id = s_a) <> v_owner then fails := fails || ' 4:moved_after_objection'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_ownership_claim_kept' and lower(to_email) = v_mem) then fails := fails || ' 4:member_not_told_kept'; end if;

  -- 5. the second company passes after the three days
  j := public.fn_supplier_ownership_claim_open(s_b, v_mem_b, 'ZZ DEMO the owner sold his share and left the UAE', 'whatsapp');
  v_claim_b := (j->>'claim_id')::bigint;
  perform public.fn_supplier_ownership_claim_decide(v_claim_b, 'transfer', 'ZZ DEMO evidence holds', 'The company passes to you in three days unless the owner keeps it.', 'sales_engineer');
  update public.supplier_ownership_claim set effective_at = now() - interval '1 minute' where id = v_claim_b;
  j := public.fn_supplier_ownership_claims_complete();
  if coalesce((j->>'transferred')::int, 0) <> 1 then fails := fails || ' 5:complete(' || coalesce(j::text, '') || ')'; end if;
  if (select claimed_by from public.leads where id = s_b) <> v_mem_b or (select email from public.leads where id = s_b) <> v_mem_b
     or (select whatsapp_phone from public.leads where id = s_b) is not null or (select whatsapp_opt from public.leads where id = s_b) <> 'none' then
    fails := fails || ' 5:not_moved'; end if;
  if (select status from public.supplier_member where lead_id = s_b and email = v_mem_b) <> 'became_owner' then fails := fails || ' 5:member_row'; end if;
  if exists (select 1 from public.supplier_member where lead_id = s_b and email = v_owner_b and status in ('invited', 'active', 'screening')) then fails := fails || ' 5:old_owner_kept'; end if;
  if (select state from public.supplier_ownership_claim where id = v_claim_b) <> 'transferred' then fails := fails || ' 5:state'; end if;
  if not exists (select 1 from public.agent_actions a where a.target_id = 'supplier_ownership_claim:' || v_claim_b and a.status = 'done') then fails := fails || ' 5:task_open'; end if;
  select count(*) into n from public.notifications where type = 'supplier_ownership_claim_done' and lower(to_email) in (v_mem_b, v_owner_b);
  if n < 2 then fails := fails || ' 5:not_both_told(' || n || ')'; end if;
  if (select o.lead_id from public.fn_whatsapp_owner('+971500000733') o) is not null then fails := fails || ' 5:old_whatsapp_speaks'; end if;

  -- 6. refuse, and what is refused
  j := public.fn_supplier_ownership_claim_open(s_c, v_mem_c, 'ZZ DEMO I want to be the owner', 'portal');
  v_claim_c := (j->>'claim_id')::bigint;
  if coalesce(public.fn_supplier_ownership_claim_decide(v_claim_c, 'make_me_owner', 'x', 'x', 'sales_engineer')->>'code', '') <> 'bad_decision' then fails := fails || ' 6:bad_decision'; end if;
  j := public.fn_supplier_ownership_claim_decide(v_claim_c, 'refuse', 'ZZ DEMO a viewer of five days and the owner is active', 'The owner is active on QuotesDone, so only he can hand the company over (Settings, Team).', 'sales_engineer');
  if (select state from public.supplier_ownership_claim where id = v_claim_c) <> 'refused'
     or not exists (select 1 from public.notifications where type = 'supplier_ownership_claim_refused' and lower(to_email) = v_mem_c and body ~ 'only he can hand') then fails := fails || ' 6:refuse(' || coalesce(j::text, '') || ')'; end if;
  if coalesce(public.fn_supplier_ownership_claim_decide(v_claim_c, 'transfer', 'x', 'x', 'sales_engineer')->>'code', '') <> 'not_open' then fails := fails || ' 6:decided_twice'; end if;
  if (select claimed_by from public.leads where id = s_c) <> v_owner_c then fails := fails || ' 6:moved'; end if;

  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: only a member asks; one case with the evidence on the sales engineer''s queue, member and owner told at once; ask waits and his next word reopens it; transfer waits three days and the owner can keep it; then the company is his, the old owner''s channels stop and he is not kept; refuse says why; nonsense and a second decision refused>>';
end $probe$;
