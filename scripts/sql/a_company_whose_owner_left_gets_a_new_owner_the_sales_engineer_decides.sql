-- A COMPANY WHOSE OWNER LEFT GETS A NEW OWNER; THE SALES ENGINEER DECIDES.
--
-- Assigned: sales_engineer (decides), customer_support. Agent: W3_PEOPLE, 16 Nov 2026. Founder ledgers 1711-1713; wave-3 brief item 4;
-- SUPPLIER hole 4 and REVIEW_supplierw2 (lines 23-24).
--
-- MEASURED BEFORE WRITING (16 Nov 2026, light SELECTs on production):
--   * The former owner's channels after a hand-over are CLOSED on production: fn_supplier_transfer_confirm (md5
--     3d73b8d16f91d65163c869c11d57f5b7) clears leads.whatsapp_opt/whatsapp_phone/whatsapp_verified_at and moves the listed
--     leads.email to the new owner (the review supplierw2 fix shipped with #2017). Nothing to build there.
--   * But the ONLY way to a new owner is fn_supplier_transfer_start / _confirm, whose code goes to the OWNER's mailbox. An owner who
--     has LEFT (sold his share, left the UAE, his mailbox closed) can never confirm, and the company's remaining people can never
--     sign for it again: a dead end with no case and no person.
--
-- WHO DECIDES WHAT (rulings 1663/1664): whether the member's story holds is JUDGEMENT, so the sales engineer's model reasons over the
-- evidence and decides (sales_engineer/lib/ownership_claim.ts, on the supplier loops beat). Code only does what must be exact or safe:
-- who may ask (an active member of THAT company, never the owner, never a stranger), one case per company, the evidence read from
-- the record, and the OWNER'S THREE DAYS: a "transfer" never moves the company at once; the owner is told at every address we hold
-- and may keep it (portal Settings, Team, "Keep ownership"; or a reply the sales engineer reads), and only an untouched claim passes.
--
-- THE PARTS
--   supplier_ownership_claim                   the case: who asked, his words, the evidence, the state, the decision and its reasons.
--   fn_supplier_ownership_claim_open           a member asks (portal, e-mail or WhatsApp). The evidence is read: the licence's name
--                                              and number, the members and when each joined, the owner's last sign-in and portal
--                                              activity, mail that bounced from his address in 90 days, earlier hand-overs and
--                                              claims. A pending task goes on the sales engineer's queue; the member is told it is
--                                              received and the owner is told at once (never silent). A second ask on an open case
--                                              adds his words to it; an ask while we wait for his proof reopens it.
--   fn_supplier_ownership_claims_due           the open cases the sales engineer has not decided.
--   fn_supplier_ownership_claim_decide         transfer (after the owner's three days) | ask (his question goes to the member) |
--                                              refuse (the member is told why). One decision per open case.
--   fn_supplier_ownership_claim_object         the owner keeps his company: nothing moves; the member is told.
--   fn_supplier_ownership_claims_complete      a transfer whose three days passed untouched: the member becomes the owner, the old
--                                              owner's address, listed e-mail and WhatsApp stop speaking as the owner, and the old
--                                              owner is NOT kept as a member (he left; the new owner can invite him). Both are told.
--
-- prevented by: a_company_whose_owner_left_gets_a_new_owner_the_sales_engineer_decides_probe.sql (LOCAL Postgres 16),
-- sales_engineer/lib/ownership_claim.test.ts (the model's decision, checked), _shared/supplier_company_instruction.test.ts (owner_left).

set local lock_timeout = '3s';

create table if not exists public.supplier_ownership_claim (
  id             bigint generated always as identity primary key,
  lead_id        bigint not null references public.leads(id),
  claimant_email text not null,
  member_id      bigint not null references public.supplier_member(id),
  reason         text not null,
  channel        text not null check (channel in ('portal', 'email', 'whatsapp')),
  evidence       jsonb not null default '{}'::jsonb,
  state          text not null default 'open' check (state in ('open', 'waiting_claimant', 'approved_waiting', 'transferred', 'refused', 'objected')),
  decision       text check (decision in ('transfer', 'ask', 'refuse')),
  reasoning      text,
  message        text,
  decided_by     text,
  decided_at     timestamptz,
  effective_at   timestamptz,
  objected_at    timestamptz,
  completed_at   timestamptz,
  opened_at      timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists supplier_ownership_claim_one_live_per_company on public.supplier_ownership_claim (lead_id)
  where state in ('open', 'waiting_claimant', 'approved_waiting');
create index if not exists supplier_ownership_claim_state_idx on public.supplier_ownership_claim (state, effective_at);
alter table public.supplier_ownership_claim enable row level security;
drop policy if exists supplier_ownership_claim_service_role_only on public.supplier_ownership_claim;
create policy supplier_ownership_claim_service_role_only on public.supplier_ownership_claim as permissive for all to public using (false) with check (false);
revoke all on public.supplier_ownership_claim from anon, authenticated;

-- The record the sales engineer reasons over, read when the case opens and again when it is listed.
create or replace function public.fn_supplier_ownership_claim_evidence(p_lead bigint, p_member bigint)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'company', (select jsonb_build_object('name', l.company_name, 'licence_legal_name', l.licence_legal_name, 'trade_licence_no', l.trade_license_no,
                       'licence_authority', l.license_authority, 'licence_expiry', l.license_expiry, 'licence_on_file', l.license_doc_path is not null,
                       'listed_email_domain', l.email_domain, 'approval_status', l.approval_status)
                  from public.leads l where l.id = p_lead),
    'owner', (select jsonb_build_object('email', l.claimed_by, 'name_we_hold', l.contact_name,
                     'last_sign_in_at', (select max(u.last_sign_in_at) from auth.users u where lower(u.email) = lower(l.claimed_by)),
                     'last_portal_change_at', l.portal_updated_at,
                     'mail_bounced_90d', (select count(*) from public.notifications n where lower(n.to_email) = lower(l.claimed_by)
                                           and n.created_at > now() - interval '90 days'
                                           and (n.provider_status in ('undelivered', 'failed') or n.status in ('bounced', 'failed'))),
                     'mail_delivered_90d', (select count(*) from public.notifications n where lower(n.to_email) = lower(l.claimed_by)
                                             and n.created_at > now() - interval '90 days' and n.provider_status in ('delivered', 'read')),
                     'quotes_sent_90d', (select count(*) from public.quotes q where q.supplier_id = l.id and q.created_at > now() - interval '90 days'))
                from public.leads l where l.id = p_lead),
    'claimant', (select jsonb_build_object('email', m.email, 'name', m.name, 'role', m.role, 'member_since', m.accepted_at,
                        'email_domain', split_part(m.email, '@', 2), 'phone_confirmed', m.phone_confirmed_at is not null)
                   from public.supplier_member m where m.id = p_member),
    'members', coalesce((select jsonb_agg(jsonb_build_object('name', m.name, 'role', m.role, 'member_since', m.accepted_at,
                                 'email_domain', split_part(m.email, '@', 2)) order by m.accepted_at)
                           from public.supplier_member m where m.lead_id = p_lead and m.status in ('active', 'screening')), '[]'::jsonb),
    'earlier_hand_overs', coalesce((select jsonb_agg(jsonb_build_object('from', t.from_email, 'to', t.to_email, 'at', coalesce(t.confirmed_at, t.created_at),
                                           'confirmed', t.confirmed_at is not null) order by t.id)
                                      from public.supplier_ownership_transfer t where t.lead_id = p_lead), '[]'::jsonb),
    'earlier_claims', coalesce((select jsonb_agg(jsonb_build_object('by', c.claimant_email, 'state', c.state, 'decision', c.decision, 'at', c.opened_at) order by c.id)
                                  from public.supplier_ownership_claim c where c.lead_id = p_lead and c.state in ('transferred', 'refused', 'objected')), '[]'::jsonb));
$fn$;
revoke execute on function public.fn_supplier_ownership_claim_evidence(bigint, bigint) from public, anon, authenticated;

create or replace function public.fn_supplier_ownership_claim_open(p_lead bigint, p_actor text, p_reason text, p_channel text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_e text := lower(btrim(coalesce(p_actor, ''))); v_why text := nullif(left(btrim(coalesce(p_reason, '')), 1500), '');
        l record; m record; c public.supplier_ownership_claim; v_id bigint; v_cc text[];
begin
  if p_channel not in ('portal', 'email', 'whatsapp') then return jsonb_build_object('ok', false, 'code', 'bad_channel'); end if;
  select id, claimed_by, email, company_name into l from public.leads where id = p_lead;
  if not found or l.claimed_by is null then return jsonb_build_object('ok', false, 'code', 'no_company'); end if;
  if lower(l.claimed_by) = v_e then
    return jsonb_build_object('ok', false, 'code', 'is_owner', 'error', 'You are the owner. To hand the company to a member, use Settings, Team, Hand over.');
  end if;
  select * into m from public.supplier_member where lead_id = p_lead and email = v_e and status in ('active', 'screening') order by id limit 1;
  if not found or not public.fn_supplier_member_counts(m.id) then
    return jsonb_build_object('ok', false, 'code', 'not_a_member', 'error', 'Only a member of this company can ask to take it over.');
  end if;

  select * into c from public.supplier_ownership_claim where lead_id = p_lead and state in ('open', 'waiting_claimant', 'approved_waiting') for update;
  if found then
    if c.state = 'approved_waiting' then
      return jsonb_build_object('ok', true, 'already', true, 'claim_id', c.id, 'state', c.state, 'effective_at', c.effective_at);
    end if;
    -- his (or a colleague's) next word joins the same case; one we were waiting on is open again for the sales engineer
    update public.supplier_ownership_claim
       set reason = left(reason || E'\n[' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ', ' || m.name || '] '
                         || coalesce(v_why, '(no new words)'), 6000),
           state = 'open', evidence = public.fn_supplier_ownership_claim_evidence(p_lead, c.member_id), updated_at = now()
     where id = c.id;
    return jsonb_build_object('ok', true, 'already', true, 'claim_id', c.id, 'state', 'open');
  end if;
  if v_why is null then
    return jsonb_build_object('ok', false, 'code', 'reason_required', 'error', 'Tell us what happened to the owner, in a sentence or two.');
  end if;

  insert into public.supplier_ownership_claim (lead_id, claimant_email, member_id, reason, channel, evidence)
  values (p_lead, v_e, m.id, v_why, p_channel, public.fn_supplier_ownership_claim_evidence(p_lead, m.id))
  returning id into v_id;

  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_ownership_claim', 'pending', 'medium',
          left('A member asks to take over ' || coalesce(l.company_name, 'supplier #' || p_lead) || ': the owner has left', 200),
          'Read the evidence on the case and decide: transfer (after the owner''s three days), ask the member for proof, or refuse with the reason.',
          jsonb_build_object('claim_id', v_id, 'supplier_id', p_lead, 'claimant', v_e, 'channel', p_channel),
          'supplier_ownership_claim', 'supplier_ownership_claim:' || v_id);

  perform public.fn_sales_engineer_writes('supplier_ownership_claim_received', 'supplier', v_e, p_lead, null, null, null,
    'We have your request to take over ' || coalesce(l.company_name, 'your company') || ' on QuotesDone',
    'We received your request to become the owner of ' || coalesce(l.company_name, 'your company') || ' on QuotesDone, because the owner ('
    || l.claimed_by || ') has left.' || E'\n\nOur sales engineer reads the company''s record and decides within two working days. He may ask you '
    || 'for proof, for example the current trade licence page that names the manager. We have also told the owner at the addresses we hold: '
    || 'if he is still with the company he can keep it. Nothing changes until then.',
    null, null, '{}'::text[], 'supplier_ownership_claim_received:' || v_id);
  v_cc := case when l.email is not null and lower(l.email) <> lower(l.claimed_by) then array[l.email] else '{}'::text[] end;
  perform public.fn_sales_engineer_writes('supplier_ownership_claim_owner_notice', 'supplier', l.claimed_by, p_lead, null, null, null,
    'A member asks to take over ' || coalesce(l.company_name, 'your company') || ' on QuotesDone',
    m.name || ' (' || v_e || '), a member of ' || coalesce(l.company_name, 'your company') || ' on QuotesDone, tells us that you have left the '
    || 'company and asks to become its owner.' || E'\n\nIf you are still the owner, sign in and press "Keep ownership" (Settings, Team), or '
    || 'reply to this e-mail. Nothing changes while our sales engineer looks into it, and if he approves, the hand-over still waits three days for you.',
    null, null, v_cc, 'supplier_ownership_claim_owner_notice:' || v_id);
  return jsonb_build_object('ok', true, 'claim_id', v_id, 'state', 'open');
end $fn$;
revoke execute on function public.fn_supplier_ownership_claim_open(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_ownership_claim_open(bigint, text, text, text) to service_role;

create or replace function public.fn_supplier_ownership_claims_due(p_limit integer default 5)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('claim_id', c.id, 'supplier_id', c.lead_id, 'opened_at', c.opened_at, 'channel', c.channel,
                    'his_words', c.reason, 'evidence', public.fn_supplier_ownership_claim_evidence(c.lead_id, c.member_id)) order by c.opened_at), '[]'::jsonb)
    from (select * from public.supplier_ownership_claim where state = 'open' order by opened_at limit greatest(1, least(coalesce(p_limit, 5), 20))) c;
$fn$;
revoke execute on function public.fn_supplier_ownership_claims_due(integer) from public, anon, authenticated;
grant execute on function public.fn_supplier_ownership_claims_due(integer) to service_role;

create or replace function public.fn_supplier_ownership_claim_decide(p_claim bigint, p_decision text, p_reasoning text, p_message text, p_decided_by text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare c public.supplier_ownership_claim; l record; v_msg text := nullif(left(btrim(coalesce(p_message, '')), 1500), '');
        v_why text := nullif(left(btrim(coalesce(p_reasoning, '')), 3000), ''); v_at timestamptz; v_cc text[];
begin
  if p_decision not in ('transfer', 'ask', 'refuse') then return jsonb_build_object('ok', false, 'code', 'bad_decision'); end if;
  if v_why is null or v_msg is null then return jsonb_build_object('ok', false, 'code', 'reasons_required'); end if;
  select * into c from public.supplier_ownership_claim where id = p_claim for update;
  if not found or c.state <> 'open' then return jsonb_build_object('ok', false, 'code', 'not_open'); end if;
  select id, claimed_by, email, company_name into l from public.leads where id = c.lead_id;
  if p_decision = 'transfer' then
    -- THE OWNER'S THREE DAYS: from the moment he was told, and never less than three days from now
    v_at := greatest(c.opened_at, now()) + interval '3 days';
    update public.supplier_ownership_claim set state = 'approved_waiting', decision = 'transfer', reasoning = v_why, message = v_msg,
           decided_by = coalesce(p_decided_by, 'sales_engineer'), decided_at = now(), effective_at = v_at, updated_at = now() where id = c.id;
    perform public.fn_sales_engineer_writes('supplier_ownership_claim_approved', 'supplier', c.claimant_email, c.lead_id, null, null, null,
      'Your request to take over ' || coalesce(l.company_name, 'the company') || ' is approved',
      v_msg || E'\n\nThe company passes to you on ' || to_char(v_at at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' unless the owner keeps it before then.',
      null, null, '{}'::text[], 'supplier_ownership_claim_approved:' || c.id);
    v_cc := case when l.email is not null and lower(l.email) <> lower(l.claimed_by) then array[l.email] else '{}'::text[] end;
    perform public.fn_sales_engineer_writes('supplier_ownership_claim_owner_notice', 'supplier', l.claimed_by, c.lead_id, null, null, null,
      coalesce(l.company_name, 'Your company') || ' passes to ' || c.claimant_email || ' in three days',
      'Our sales engineer has approved the request of ' || c.claimant_email || ', a member of ' || coalesce(l.company_name, 'your company')
      || ', to become its owner, because you have left the company. It takes effect on ' || to_char(v_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
      || ' (in three days).' || E'\n\nIf you are still the owner, sign in and press "Keep ownership" (Settings, Team), or reply to this e-mail, before then.',
      null, null, v_cc, 'supplier_ownership_claim_owner_final:' || c.id);
  elsif p_decision = 'ask' then
    update public.supplier_ownership_claim set state = 'waiting_claimant', decision = 'ask', reasoning = v_why, message = v_msg,
           decided_by = coalesce(p_decided_by, 'sales_engineer'), decided_at = now(), updated_at = now() where id = c.id;
    perform public.fn_sales_engineer_writes('supplier_ownership_claim_question', 'supplier', c.claimant_email, c.lead_id, null, null, null,
      'One question about taking over ' || coalesce(l.company_name, 'the company'),
      v_msg || E'\n\nReply to this e-mail, or answer in your portal (Settings, Team). Nothing changes until we have it.',
      null, null, '{}'::text[], 'supplier_ownership_claim_question:' || c.id || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
  else
    update public.supplier_ownership_claim set state = 'refused', decision = 'refuse', reasoning = v_why, message = v_msg,
           decided_by = coalesce(p_decided_by, 'sales_engineer'), decided_at = now(), updated_at = now() where id = c.id;
    perform public.fn_sales_engineer_writes('supplier_ownership_claim_refused', 'supplier', c.claimant_email, c.lead_id, null, null, null,
      'Your request to take over ' || coalesce(l.company_name, 'the company') || ' on QuotesDone', v_msg,
      null, null, '{}'::text[], 'supplier_ownership_claim_refused:' || c.id);
  end if;
  -- a refusal closes the task; a transfer keeps it open until the company passes or the owner keeps it
  if p_decision = 'refuse' then
    update public.agent_actions set status = 'done' where kind = 'supplier_ownership_claim' and target_id = 'supplier_ownership_claim:' || c.id
       and status = 'pending';
  end if;
  return jsonb_build_object('ok', true, 'claim_id', c.id, 'decision', p_decision, 'effective_at', v_at);
end $fn$;
revoke execute on function public.fn_supplier_ownership_claim_decide(bigint, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_ownership_claim_decide(bigint, text, text, text, text) to service_role;

create or replace function public.fn_supplier_ownership_claim_object(p_lead bigint, p_actor text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare l record; c public.supplier_ownership_claim;
begin
  select id, claimed_by, company_name into l from public.leads where id = p_lead;
  if not found or lower(coalesce(l.claimed_by, '')) <> lower(btrim(coalesce(p_actor, ''))) then return jsonb_build_object('ok', false, 'code', 'owner_only'); end if;
  select * into c from public.supplier_ownership_claim where lead_id = p_lead and state in ('open', 'waiting_claimant', 'approved_waiting') for update;
  if not found then return jsonb_build_object('ok', true, 'nothing_waiting', true); end if;
  update public.supplier_ownership_claim set state = 'objected', objected_at = now(), updated_at = now() where id = c.id;
  update public.agent_actions set status = 'done' where kind = 'supplier_ownership_claim' and target_id = 'supplier_ownership_claim:' || c.id and status = 'pending';
  perform public.fn_sales_engineer_writes('supplier_ownership_claim_kept', 'supplier', c.claimant_email, p_lead, null, null, null,
    'The owner keeps ' || coalesce(l.company_name, 'the company'),
    'The owner of ' || coalesce(l.company_name, 'the company') || ' (' || l.claimed_by || ') has told us he is still the owner, so the company '
    || 'stays his and nothing changed. Please speak to him; he can hand it to you himself in Settings, Team.',
    null, null, '{}'::text[], 'supplier_ownership_claim_kept:' || c.id);
  return jsonb_build_object('ok', true, 'claim_id', c.id, 'state', 'objected');
end $fn$;
revoke execute on function public.fn_supplier_ownership_claim_object(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_ownership_claim_object(bigint, text) to service_role;

create or replace function public.fn_supplier_ownership_claims_complete()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare c record; v_n int := 0; v_skipped int := 0; v_from text;
begin
  for c in select x.*, l.claimed_by as owner_email, l.company_name from public.supplier_ownership_claim x join public.leads l on l.id = x.lead_id
            where x.state = 'approved_waiting' and x.effective_at <= now() order by x.id for update of x, l loop
    -- the member must still count (not removed, not held by the screen) when the day comes
    if not exists (select 1 from public.supplier_member m where m.id = c.member_id and m.status in ('active', 'screening'))
       or not public.fn_supplier_member_counts(c.member_id) then
      update public.supplier_ownership_claim set state = 'refused', reasoning = coalesce(reasoning, '') || E'\n[system] the member no longer counts on the day',
             updated_at = now() where id = c.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;
    -- REVIEW W3PEOPLE: exact facts the owner has not left, read on the day: the owner changed since the case opened (a hand-over in
    -- the three days), or the owner signed in after the decision. The case goes back to the sales engineer with the fact; nothing moves.
    if lower(coalesce(c.owner_email, '')) <> lower(coalesce(c.evidence -> 'owner' ->> 'email', c.owner_email))
       or exists (select 1 from auth.users u where lower(u.email) = lower(c.owner_email) and u.last_sign_in_at > c.decided_at) then
      update public.supplier_ownership_claim set state = 'open', decision = null, effective_at = null, updated_at = now(),
             reason = left(reason || E'\n[system] on the day: the owner changed, or signed in after the decision; nothing moved', 6000)
       where id = c.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;
    v_from := lower(c.owner_email);
    update public.supplier_member set status = 'became_owner', removed_at = now(), removed_by = 'ownership_claim' where id = c.member_id;
    -- the old owner's channels stop speaking as the owner, exactly as fn_supplier_transfer_confirm; he LEFT, so he is not kept
    update public.leads set claimed_by = c.claimant_email, owner_email_verified = true, portal_updated_at = now(),
           email = case when lower(coalesce(email, '')) = v_from then c.claimant_email else email end,
           whatsapp_opt = 'none', whatsapp_phone = null, whatsapp_verified_at = null
     where id = c.lead_id;
    update public.supplier_ownership_claim set state = 'transferred', completed_at = now(), updated_at = now() where id = c.id;
    update public.agent_actions set status = 'done' where kind = 'supplier_ownership_claim' and target_id = 'supplier_ownership_claim:' || c.id and status = 'pending';
    perform public.fn_sales_engineer_writes('supplier_ownership_claim_done', 'supplier', c.claimant_email, c.lead_id, null, null, null,
      'You are now the owner of ' || coalesce(c.company_name, 'your company') || ' on QuotesDone',
      'You are now the owner of ' || coalesce(c.company_name, 'your company') || ' on QuotesDone. You sign its quotations and manage its team '
      || 'and account. Please set the company''s WhatsApp number in Settings, and check its details and trade licence.',
      null, null, '{}'::text[], 'supplier_ownership_claim_done:' || c.id);
    perform public.fn_sales_engineer_writes('supplier_ownership_claim_done', 'supplier', v_from, c.lead_id, null, null, null,
      coalesce(c.company_name, 'The company') || ' now has a new owner on QuotesDone',
      'As we wrote three days ago, ' || coalesce(c.company_name, 'the company') || ' on QuotesDone now belongs to ' || c.claimant_email
      || ', because you have left it. If this is wrong, reply to this e-mail and our sales engineer will look into it.',
      null, null, '{}'::text[], 'supplier_ownership_claim_done_old:' || c.id);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('transferred', v_n, 'member_no_longer_counts', v_skipped);
end $fn$;
revoke execute on function public.fn_supplier_ownership_claims_complete() from public, anon, authenticated;
grant execute on function public.fn_supplier_ownership_claims_complete() to service_role;
