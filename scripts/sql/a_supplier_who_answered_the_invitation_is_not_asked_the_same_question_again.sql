-- A SUPPLIER WHO ANSWERED THE INVITATION IS NOT ASKED THE SAME QUESTION AGAIN (28 Oct 2026).
-- Assigned: sales_engineer (supplier invitations and their follow-up). Found by it_engineer in the supplier-journey
-- audit of 28 Oct 2026 (founder ledger 1401: "audit the supplier journey from the moment they receive an email up to
-- being verified by the sales agent").
--
-- MEASURED on production (htdblwldjkcgjvmqkbeh), read-only, 28 Oct 2026:
--   * The first real invitations went out today (20 queued 06:45Z, the first sent 07:01Z). The email is variant A:
--     "Would your company like to receive <trade> requests when they come in?", with no link (#1648).
--   * A supplier's reply reaches resend_inbound (the Microsoft 365 reader) and email_triage answers it with the
--     company's own registration link. fn_marketing_files_invite_reply files an invite.reply handoff. NOTHING on the
--     lead changes: invite_status stays 'sent' and invite_clicked_at stays null until the link itself is opened.
--   * fn_supplier_invite_nudges_due (the day-3/7/14 nudge list, read by fn_sales_engineer_nudges_invited_suppliers and
--     enqueue_supplier_invites) excludes a lead that clicked, claimed, registered, bounced, unsubscribed or is
--     suppressed. It does NOT exclude a lead that replied.
--   * send_outbox sends every nudge as the SAME variant A email (campaignMail rewrites the stored nudge body), with the
--     trade from leads.invite_trades in the subject.
-- So a supplier who answered "yes", asked what it costs, or wrote "we only do steel, not tiles", and has not yet opened
-- the link it was sent, receives the identical cold question three days later, again on day 7 and day 14. Replayed
-- through the real reply path on 28 Oct (auditor C, run tag ac4…): the "steel, not tiles" supplier was told "We will
-- not send you tiling requests", and this list would then have sent it "A question about your tiling work". With
-- today's batch the first such nudge could leave on Monday 2 Nov, 09:00 Dubai (the weekend holds Saturday and Sunday).
--
-- WHAT THIS CHANGES: one routine, fn_supplier_invite_nudges_due. A lead with a message in inbound_messages from its own
-- address (or matched to it) that arrived AFTER the invitation was sent is not nudged. An automatic reply (out of
-- office, a help-desk acknowledgement: fn_inbound_is_auto_reply, the same rule fn_marketing_files_invite_reply uses)
-- does not count: that supplier has not answered and is still nudged. A "stop" reply was already excluded through the
-- unsubscribe it causes; it is excluded here as well.
--
-- WHAT THIS DOES NOT CHANGE: fn_sales_engineer_nudges_invited_suppliers (the switch, window, cap, brakes, per-provider
-- placement gate and copy), enqueue_supplier_invites, the registration reminders, and the invite.reply handler. It does
-- not give a supplier who replied and never registered a follow-up of its own: that is a separate gap, recorded in
-- docs/reports/supplier_journey_audit_28_oct/sales_agent/ (finding "a replied lead gets no reminder").
--
-- CREATE OR REPLACE keeps the routine's ACL (owner only, revoked in the owning file), so there is no revoke here.
-- Signature, volatility, security and search_path are unchanged; the body is the live body (read back 28 Oct and
-- compared, identical) plus `i.sent_at` carried into c and the one `not exists` below.
-- Proof: a_supplier_who_answered_the_invitation_is_not_asked_the_same_question_again_probe.sql (rolled back).
-- Prevented by: scripts/checks/a_supplier_who_answered_the_invitation_is_not_asked_the_same_question_again.test.mjs

create or replace function public.fn_supplier_invite_nudges_due(p_now timestamptz default now(), p_include_fixtures boolean default false)
returns table (lead_id bigint, step integer, to_email text, lang text, dedupe_key text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with inv as (   -- the invitation as the OUTBOX recorded it, one per lead
    select n.lead_id, min(coalesce(n.sent_at, n.created_at)) as sent_at
      from public.notifications n
     where n.type = 'supplier_invite' and n.lead_id is not null
       and (n.status = 'sent' or n.sent_at is not null)
     group by n.lead_id
  ), c as (
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English, ledger 993). The column
    -- stays so the signature does not change; send_outbox would hold an Arabic row of this type anyway.
    select l.id, lower(btrim(l.email)) as to_email, 'en'::text as lang,
           l as lead, i.sent_at,
           case when p_now >= i.sent_at + interval '14 days' then 3
                when p_now >= i.sent_at + interval '7 days'  then 2
                when p_now >= i.sent_at + interval '3 days'  then 1 end as step
      from inv i join public.leads l on l.id = i.lead_id
     where l.invite_clicked_at is null and not coalesce(l.claimed, false) and l.approval_status is null
       and l.registration_submitted_at is null
       and p_now < i.sent_at + interval '21 days'
  )
  select c.id, c.step, c.to_email, c.lang, 'supplier_invite_nudge:' || c.id || ':' || c.step
    from c
   where c.step is not null
     and coalesce((c.lead).invite_status, '') not in ('bounced', 'complained', 'unsubscribed')
     and not exists (select 1 from public.email_suppressions s where lower(s.email) = c.to_email)
     and case when p_include_fixtures
              -- the test path can only ever see a fixture: both marks, asserted, never assumed
              then (c.lead).company_name like 'ZZ DEMO%' and c.to_email like '%@example.invalid'
              else public.fn_supplier_outreach_reachable(c.lead, c.to_email) end
     -- A SUPPLIER WHO ANSWERED IS NOT ASKED AGAIN (28 Oct 2026): any message of its own since the invitation was sent,
     -- an automatic reply excepted. The address is read out of a "Name <address>" From exactly as
     -- fn_marketing_files_invite_reply reads it.
     and not exists (select 1 from public.inbound_messages m
                      where (m.lead_id = c.id
                             or lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)')) = c.to_email)
                        and m.created_at >= c.sent_at
                        and not public.fn_inbound_is_auto_reply(m.subject, m.body, m.raw))
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'customer_support'
                        and a.target_id = 'delivery.request:supplier_invite_nudge:' || c.id || ':' || c.step)
   order by c.id
$fn$;
