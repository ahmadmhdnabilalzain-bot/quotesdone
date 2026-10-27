-- PROBE (pure, rolled back): the supplier invitation carries no link, and a reply with trades reaches the sales engineer.
-- Seat: marketing. Run after the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql.
-- It always raises CHK<<...>>, so every row it writes is rolled back; nothing here can reach a person (no row commits,
-- and the handler it runs queues no mail).
--
--  A. the daily list and the plan builder run on the approved, link-free template (they raised before);
--  B. a ZZ DEMO lead, invited, replies to supplier@quotesdone.com with its trades: the reply is recognised, the quoted
--     original is cut off, and ruling 1199 files NO handoff for a demo lead;
--  C. a "stop" reply and a reply to another mailbox are not due;
--  D. the same lead with its demo marks (name, address; is_demo is generated from them) lifted inside this transaction: the AFTER INSERT trigger files exactly ONE
--     invite.reply handoff for the sales engineer, carrying the lead id and the reply text, waiting on the page.
do $$
declare v_lead bigint; v_m bigint; r jsonb; v_cand int; v_cand_link int; v_plans jsonb; v_plan_link int;
  v_demo_handoffs int; v_stop jsonb; v_other jsonb; v_h int; a public.agent_actions; v_real_before int; v_real_after int;
begin
  v_real_before := (select count(*) from public.agent_actions where kind = 'handoff' and detail->>'type' = 'invite.reply');

  -- A
  select count(*), count(*) filter (where body ~* '(https?://|www\.|\{\{link\}\})') into v_cand, v_cand_link
    from public.fn_supplier_invite_candidates(3);
  v_plans := public.fn_marketing_gap_recruitment_plans();
  v_plan_link := (select count(*) from public.marketing_gap_recruitment_plan where invite_body ~* '(https?://|www\.|\{\{link\}\})');

  -- B
  insert into public.leads (company_name, email, invited_at, invite_status, invite_trades)
  values ('ZZ DEMO Invite Reply Probe', 'zz-demo-invite-reply-probe@example.invalid', now() - interval '1 day', 'invited', array['tiling'])
  returning id into v_lead;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, raw)
  values (v_lead, 'zz-demo-invite-reply-probe@example.invalid', 'supplier@quotesdone.com', 'Re: Tiling quote requests for ZZ DEMO',
          E'We cover tiling and waterproofing.\n\nOn Tue, 27 Oct 2026, Ahmad Alzain wrote:\n> Hi team,\n> I''m Ahmad', '{}'::jsonb)
  returning id into v_m;
  r := public.fn_marketing_files_invite_reply(v_m);
  v_demo_handoffs := (select count(*) from public.agent_actions where kind = 'handoff' and target_id = 'invite.reply:' || v_lead);

  -- C
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, raw)
  values (v_lead, 'zz-demo-invite-reply-probe@example.invalid', 'supplier@quotesdone.com', 'Re: x', E'Stop.\n\n> quoted', '{}')
  returning id into v_m;
  v_stop := public.fn_marketing_files_invite_reply(v_m);
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, raw)
  values (v_lead, 'zz-demo-invite-reply-probe@example.invalid', 'info@quotesdone.com', 'Re: x', 'We cover tiling.', '{}')
  returning id into v_m;
  v_other := public.fn_marketing_files_invite_reply(v_m);

  -- D
  update public.leads set company_name = 'Invite Reply Probe Trading', email = 'invite-reply-probe@quotesdone.com' where id = v_lead;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, raw)
  values (v_lead, 'invite-reply-probe@quotesdone.com', 'supplier@quotesdone.com', 'Re: Tiling quote requests for Invite Reply Probe Trading',
          E'We cover tiling and waterproofing.\n\nOn Tue, 27 Oct 2026, Ahmad Alzain wrote:\n> Hi team,', '{}');
  v_h := (select count(*) from public.agent_actions where kind = 'handoff' and target_id = 'invite.reply:' || v_lead);
  select * into a from public.agent_actions where kind = 'handoff' and target_id = 'invite.reply:' || v_lead order by id limit 1;
  v_real_after := (select count(*) from public.agent_actions where kind = 'handoff' and detail->>'type' = 'invite.reply') - v_h;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when v_cand_link = 0 and v_plan_link = 0
                     and (r->>'due')::boolean and r->>'handoff_id' is null and v_demo_handoffs = 0
                     and r->>'reply_text' = 'We cover tiling and waterproofing.'
                     and not (v_stop->>'due')::boolean and not (v_other->>'due')::boolean
                     and v_h = 1 and a.agent = 'sales_engineer' and a.status = 'pending'
                     and (a.detail->>'lead_id')::bigint = v_lead and a.detail->>'reply_text' = 'We cover tiling and waterproofing.'
                     and a.detail->>'from' = 'marketing' and coalesce(a.detail->>'awaiting', '') like 'sales_engineer: set up the company page%'
                     and v_real_after = v_real_before
                    then 'PROBE OK' else 'PROBE FAILED' end,
    'A_candidates', v_cand, 'A_candidates_with_link', v_cand_link, 'A_plans', v_plans->'plans_written', 'A_plans_with_link', v_plan_link,
    'B_demo_reply', r, 'B_demo_handoffs', v_demo_handoffs, 'C_stop', v_stop->>'reason', 'C_other_mailbox', v_other->>'reason',
    'D_handoffs', v_h, 'D_agent', a.agent, 'D_status', a.status, 'D_lead_id', a.detail->'lead_id', 'D_reply_text', a.detail->'reply_text',
    'D_awaiting', a.detail->'awaiting', 'D_title', a.title, 'real_invite_reply_handoffs_untouched', v_real_after = v_real_before);
end $$;
