-- THE SUPPLIER INVITATION CARRIES NO LINK, AND A REPLY WITH TRADES REACHES THE SALES ENGINEER.
-- Seat: marketing (copy, the reply hand-off) for the sales_engineer (the company page). 27 Oct 2026.
--
-- The founder approved a new supplier invitation (founder_instruction 1298-1301): "the wording sounds fine to me";
-- "think of our company as something really big, like Amazon, Apple, Google ... we gotta follow the same method";
-- "safer to not send links"; "It's just QuotesDone Technologies, Dubai, UAE" (no Al Furjan, no permit, no licence no.).
-- The Microsoft 365 lane builds the sent email in code (supabase/functions/send_outbox/m365_lane.ts,
-- m365InvitationText), whatever a row stored. This file makes the STORED copy say the same and stops the routines
-- that build it from refusing it:
--
--   1. app_secrets.invite_body becomes the approved text with {{company}} and no {{link}}; invite_subject becomes the
--      lane's neutral subject. The neutral trade line ("onboarding suppliers") stands in for the trade the lane fills.
--   2. fn_supplier_invite_candidates RAISED on a body without {{link}} ("an invitation with no way in is refused"):
--      with the approved body every daily batch would have errored. It now refuses only an EMPTY body; a body that
--      still carries {{link}} is filled as before. It no longer substitutes marketing's per-trade variant body or
--      subject: the founder approved one text, so every queued row stores it. The plan RANKING still orders the queue.
--      With no company name the greeting is "Hello," (the lane's neutral variant), never "Hi there team,".
--   3. fn_marketing_gap_recruitment_plans RAISED the same way; it now writes the approved body to each plan row, and
--      marketing_gap_recruitment_plan's CHECK changes from "must carry {{link}}" to "must carry no link" (and still
--      no Arabic). Existing plan rows are rewritten first so the new CHECK validates.
--   4. A REPLY TO THE INVITATION BECOMES A SALES ENGINEER HANDOFF. The new email says "reply with the trades you
--      cover and our team will set up your company page for you". Traced 27 Oct 2026: a reply to
--      supplier@quotesdone.com is read by _shared/m365_reply_inbox.ts and handed to resend_inbound, which stores it in
--      inbound_messages with lead_id; email_triage answers it as customer_support. Nothing put it in front of the
--      sales engineer (no agent_actions row, no handoff). Now an AFTER INSERT trigger on inbound_messages calls
--      fn_marketing_files_invite_reply: a reply to the invitation mailbox (invite_m365_mailbox or the old Reply-To,
--      email_reply_supplier) from an invited, unclaimed lead, that is not a "stop" and not an auto-reply, is filed
--      through fn_seat_handoff as 'invite.reply' marketing -> sales_engineer, carrying the lead id and the reply
--      text (the quoted original cut off). The handler fn_sales_engineer_takes_invite_reply leaves it waiting with
--      the sales engineer: set up the company page from the trades in the reply. A "stop" reply is unchanged: it is
--      an unsubscribe (resend_inbound, _shared/suppression_policy.ts) and files no handoff.
--      Ruling 1199 holds: fn_seat_handoff files nothing for a demo lead.
--
-- Prevented by: supabase/functions/send_outbox/m365_lane.test.ts (the approved text word for word, no link, the stop
-- line, the token only on the seed) and scripts/checks/the_supplier_invitation_carries_no_link.test.mjs (this file:
-- no {{link}} raise, the CHECK, the handoff kind and its trigger).
-- Probe: probe_the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql.

-- 1. the stored copy
update public.app_secrets set value = $body$Hi {{company}} team,

I'm Ahmad, founder of QuotesDone. QuotesDone connects companies in the UAE with qualified suppliers: buyers post a request for quotation, and each request reaches only the suppliers registered for that exact trade.

We are now onboarding suppliers ahead of our buyer launch.

What you get:
– Requests that match your trade, delivered directly to you.
– You choose which ones to quote on.
– No commission on work you win.
– Free registration for our first 1,000 suppliers.

To join, register at quotesdone.com, or simply reply with the trades you cover and our team will set up your company page for you.

Best regards,
Ahmad Alzain
Founder, QuotesDone
QuotesDone Technologies · Dubai, UAE

If this isn't relevant, reply "stop" and we won't contact you again.$body$, updated_at = now()
 where key = 'invite_body';
update public.app_secrets set value = 'Quote requests in the UAE', updated_at = now() where key = 'invite_subject';

-- 2. the daily list accepts a body with no link
create or replace function public.fn_supplier_invite_candidates(p_limit integer)
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text; v_target int;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  -- 27 Oct 2026: the founder's invitation carries no link ("safer to not send links"); a supplier registers at
  -- quotesdone.com or replies. Only an EMPTY template is refused now. A template that still has {{link}} is filled.
  if btrim(coalesce(v_body, '')) = '' then
    raise exception 'app_secrets.invite_body is empty: no invitation is built from nothing';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  -- ONE COMPANY, ONE INVITATION (24 Sep 2026, marketing). A company is its email domain, unless the domain is
  -- a shared mailbox provider (gmail, emirates.net.ae ...: measured as a domain carrying 3+ different company
  -- names), where it is the address itself; and, independently, its normalised company name.
  shared as materialized (
    select split_part(lower(btrim(l.email)), '@', 2) as dom from leads l where coalesce(btrim(l.email), '') <> ''
    group by 1 having count(distinct lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g'))) >= 3
  ),
  keyed as materialized (
    select l.id,
           case when s.dom is null then split_part(lower(btrim(l.email)), '@', 2) else lower(btrim(l.email)) end as dkey,
           nullif(lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g')), '') as nkey,
           (l.invite_status is not null or l.invited_at is not null or coalesce(l.claimed, false)) as touched
    from leads l left join shared s on s.dom = split_part(lower(btrim(l.email)), '@', 2)
    where coalesce(btrim(l.email), '') <> ''
  ),
  touched_d as materialized (select distinct dkey from keyed where touched),
  touched_n as materialized (select distinct nkey from keyed where touched and nkey is not null),
  -- instr 1013: marketing's ranking of the trades below ten suppliers (the ranking orders the queue; since 27 Oct 2026
  -- every row stores the one approved text, not a per-trade variant)
  plans as materialized (select p.trade, p.emirate, p.rank from public.marketing_gap_recruitment_plan p),
  -- 29 Sep 2026 (ledger 1018): the trades and areas of the open, real stalled-request rescues (public.stalled_inquiry_rescue).
  -- A fixture rescue never moves the real queue.
  rescue as materialized (select x.trades, x.emirate from public.stalled_inquiry_rescue x where x.cleared_at is null and not x.fixture and cardinality(x.trades) > 0),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey,
           -- ALWAYS ENGLISH (24 Sep 2026, ledger 993 item 4; #1065): suppliers are always written in English.
           'en'::text as lang
    from leads l join keyed k on k.id = l.id
    where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))   -- the set, read once (see header)
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 29 Sep 2026 (ledger 1018): ahead of every tier below, a lead in the trade and area of a stalled request a customer waits on.
      -- 23 Sep 2026: a lead in a trade the sales engineer marked for recruitment (supply_gap 'recruit') goes first;
      -- 29 Sep 2026 (instr 1013): then a lead in any trade marketing planned, by the plan's rank.
      case when exists (select 1 from rescue x where x.trades && coalesce(c.invite_trades, '{}'::text[])
                          and (x.emirate is null or x.emirate = 'UAE' or x.emirate = c.emirate)) then -1
           when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0
           when pl.rank is not null then 1 else 2 end as target_rank,
      coalesce(pl.rank, 2147483647) as plan_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
    left join lateral (select p.rank from plans p
                        where p.trade = any(coalesce(c.invite_trades, '{}'::text[])) and (p.emirate = 'UAE' or p.emirate = c.emirate)
                        order by p.rank limit 1) pl on true
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.unverified_rank, p.role_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.unverified_rank, p.role_rank, p.id) as domain_rk,
        -- the best contact per company: a verified, named mailbox before info@/sales@ (a role address goes only
        -- when it is the company's only one). ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.unverified_rank, p.role_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.unverified_rank, p.role_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.plan_rank, r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang, v_subj,
         -- an Arabic-script company name is not written into an English letter (the 29 Sep probe found 11 of 200);
         -- with no usable name the greeting is the neutral "Hello," the Microsoft 365 lane also sends
         -- (a template that still carries {{link}} is filled as before; the approved one has none)
         replace(replace(case when n.nm = '' then replace(v_body, 'Hi {{company}} team,', 'Hello,') else v_body end,
                         '{{company}}', case when n.nm = '' then 'there' else n.nm end),
                 '{{link}}', public.fn_supplier_invite_link(v_site, e.claim_token, e.id))
  from elig e
  cross join lateral (select coalesce(nullif(btrim(case when e.company_name ~ '[؀-ۿ]' then '' else e.company_name end), ''), '') as nm) n;
end
$function$;

-- 3. marketing's plans carry the approved text, and a plan row may carry no link
create or replace function public.fn_marketing_gap_recruitment_plans()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_body text := (select value from public.app_secrets where key = 'invite_body');
  v_rows int; v_dropped int;
begin
  -- 27 Oct 2026: the founder approved ONE invitation with no link; each plan row stores it (the trade is filled at
  -- send time by the Microsoft 365 lane). Only an empty template is refused.
  if btrim(coalesce(v_body, '')) = '' then
    raise exception 'app_secrets.invite_body is empty: no plan is built from nothing';
  end if;

  delete from public.marketing_gap_recruitment_plan p
   where not exists (select 1 from public.supply_gap g where g.trade = p.trade and g.emirate = p.emirate
                       and g.closed_at is null and g.status <> 'closed' and g.matchable < g.target);
  get diagnostics v_dropped = row_count;

  with gaps as (
    select g.*, coalesce(t.label, g.trade) as label, t.group_code,
           row_number() over (order by (g.target - g.matchable) desc, g.demand_90d desc, g.uninvited_pool desc, g.trade, g.emirate) as rk
      from public.supply_gap g left join public.taxonomy_trade t on t.code = g.trade
     where g.closed_at is null and g.status <> 'closed' and g.matchable < g.target
  )
  insert into public.marketing_gap_recruitment_plan as p
    (trade, emirate, rank, matchable, target, gap, demand_90d, uninvited_pool, gap_status, sources, invite_subject, invite_body, built_at)
  select x.trade, x.emirate, x.rk, x.matchable, x.target, x.target - x.matchable, x.demand_90d, x.uninvited_pool, x.status,
         coalesce((select jsonb_agg(jsonb_build_object('kind', s.kind, 'name', s.name, 'url', s.url, 'scope', s.scope,
                                                       'http_status', s.http_status, 'verified', s.verified, 'checked_at', s.checked_at)
                                    order by (s.scope = x.trade) desc, (s.scope = x.group_code) desc, s.verified desc, s.kind, s.name)
                     from public.marketing_recruitment_source s
                    where s.scope in ('all', x.trade, coalesce(x.group_code, '-'))), '[]'::jsonb),
         initcap(x.label) || ' quote requests',
         v_body,
         now()
    from gaps x
  on conflict (trade, emirate) do update set rank = excluded.rank, matchable = excluded.matchable, target = excluded.target,
    gap = excluded.gap, demand_90d = excluded.demand_90d, uninvited_pool = excluded.uninvited_pool, gap_status = excluded.gap_status,
    sources = excluded.sources, invite_subject = excluded.invite_subject, invite_body = excluded.invite_body, built_at = excluded.built_at;
  get diagnostics v_rows = row_count;

  -- a planned trade with no checked source is marketing's own finding (where to look is the gap, not the invitation)
  perform public.fn_it_engineer_finding_upsert('recruitment:no_source:' || p.trade,
      'No checked recruitment source is recorded for ' || p.trade, 'public.marketing_recruitment_source', 'monitor', 1,
      jsonb_build_object('trade', p.trade, 'owner_seat', 'marketing'), '{}'::text[],
      array['a directory, association, chamber, LinkedIn group or trade fair where this trade gathers'], 'marketing')
    from (select distinct trade from public.marketing_gap_recruitment_plan
           where not exists (select 1 from jsonb_array_elements(sources) e where (e->>'verified')::boolean)) p;
  update public.it_engineer_finding f set closed_at = now(), close_note = 'a checked source is recorded'
   where f.issue_key like 'recruitment:no_source:%' and f.closed_at is null
     and not exists (select 1 from public.marketing_gap_recruitment_plan p where 'recruitment:no_source:' || p.trade = f.issue_key
                       and not exists (select 1 from jsonb_array_elements(p.sources) e where (e->>'verified')::boolean));

  return public.fn_marketing_gap_recruitment_report() || jsonb_build_object('plans_written', v_rows, 'plans_dropped', v_dropped);
end $fn$;

alter table public.marketing_gap_recruitment_plan drop constraint if exists marketing_gap_recruitment_plan_check;
update public.marketing_gap_recruitment_plan
   set invite_body = (select value from public.app_secrets where key = 'invite_body'),
       invite_subject = coalesce((select initcap(coalesce(t.label, marketing_gap_recruitment_plan.trade)) from public.taxonomy_trade t
                                   where t.code = marketing_gap_recruitment_plan.trade), initcap(trade)) || ' quote requests';
alter table public.marketing_gap_recruitment_plan add constraint marketing_gap_recruitment_plan_check
  check (invite_body !~* '(https?://|www\.|\{\{link\}\})' and invite_body !~ '[؀-ۿ]' and invite_subject !~ '[؀-ۿ]');

-- 4. a reply to the invitation reaches the sales engineer
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('invite.reply', 'marketing', 'sales_engineer', 'an invited supplier replied to the invitation, usually with the trades it covers: set up its company page from the reply', 'fn_sales_engineer_takes_invite_reply',
   interval '24 hours', false, 'scripts/sql/the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql')
on conflict do nothing;

create or replace function public.fn_sales_engineer_takes_invite_reply(p_id bigint)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  -- The sales engineer owns the company page. The handoff stays in its queue, waiting on that work, with the lead
  -- and the supplier's own words in front of it.
  return jsonb_build_object(
    'waiting', 'sales_engineer: set up the company page for lead #' || coalesce(a.detail->>'lead_id', '?') || ' from the trades in the reply',
    'lead_id', a.detail->'lead_id', 'inbound_message_id', a.detail->'inbound_message_id', 'reply_text', a.detail->'reply_text');
end $fn$;
revoke execute on function public.fn_sales_engineer_takes_invite_reply(bigint) from public, anon, authenticated;

create or replace function public.fn_marketing_files_invite_reply(p_inbound_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages; l public.leads;
  v_from text; v_boxes text[]; v_first text; v_reply text; v_id bigint;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then return jsonb_build_object('due', false, 'reason', 'no such inbound message'); end if;
  v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
  select array_agg(lower(btrim(value))) into v_boxes from public.app_secrets
   where key in ('invite_m365_mailbox', 'email_reply_supplier') and btrim(coalesce(value, '')) <> '';
  if v_boxes is null or not exists (select 1 from unnest(v_boxes) b where position(b in lower(coalesce(m.to_email, ''))) > 0) then
    return jsonb_build_object('due', false, 'reason', 'not addressed to the invitation mailbox');
  end if;
  select * into l from public.leads x
   where (m.lead_id is not null and x.id = m.lead_id) or (m.lead_id is null and lower(btrim(x.email)) = v_from)
   order by x.id limit 1;
  if l.id is null then return jsonb_build_object('due', false, 'reason', 'the sender is no lead'); end if;
  if l.invited_at is null and l.invite_status is null then return jsonb_build_object('due', false, 'reason', 'the lead was never invited'); end if;
  if coalesce(l.claimed, false) then return jsonb_build_object('due', false, 'reason', 'the lead already has its company page'); end if;
  if lower(coalesce(m.raw->>'auto_submitted', 'no')) <> 'no' then return jsonb_build_object('due', false, 'reason', 'an automatic reply'); end if;
  -- the supplier's own words: everything above the quoted original
  v_reply := btrim(regexp_replace(coalesce(m.body, ''), E'(\\n|^)\\s*(>|On [^\\n]{0,200}wrote:|-{2,}\\s*Original Message|From:\\s).*$', ''));
  v_first := lower(btrim(regexp_replace(split_part(v_reply, E'\n', 1), '[[:punct:][:space:]]+', ' ', 'g')));
  -- "stop" is an unsubscribe (resend_inbound), never a request for a page
  if v_first in ('stop', 'unsubscribe', 'stopall', 'end', 'cancel', 'opt out', 'optout', 'remove', 'remove me', 'please remove', 'not interested') then
    return jsonb_build_object('due', false, 'reason', 'a stop reply (handled as an unsubscribe)');
  end if;
  if v_reply = '' then return jsonb_build_object('due', false, 'reason', 'an empty reply'); end if;

  v_id := public.fn_seat_handoff('marketing', 'sales_engineer', 'invite.reply', 'leads', l.id::text,
    jsonb_build_object('lead_id', l.id, 'company_name', l.company_name, 'from_email', v_from,
                       'inbound_message_id', m.id, 'reply_text', left(v_reply, 4000),
                       'ask', 'Set up the company page for this supplier from the trades it listed in its reply.'));
  -- null = a demo lead (ruling 1199: a demo row files no handoff)
  return jsonb_build_object('due', true, 'reason', 'an invited supplier replied', 'lead_id', l.id, 'reply_text', left(v_reply, 4000), 'handoff_id', v_id);
end $fn$;
revoke execute on function public.fn_marketing_files_invite_reply(bigint) from public, anon, authenticated;

create or replace function public.trg_invite_reply_reaches_sales_engineer()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- never costs the mail it rides on: a failure is a warning, the inbound row is kept
  begin
    perform public.fn_marketing_files_invite_reply(new.id);
  exception when others then
    raise warning 'trg_invite_reply_reaches_sales_engineer: inbound_messages % not handed to the sales engineer: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
revoke execute on function public.trg_invite_reply_reaches_sales_engineer() from public, anon, authenticated;

drop trigger if exists z52_invite_reply_reaches_sales_engineer on public.inbound_messages;
create trigger z52_invite_reply_reaches_sales_engineer after insert on public.inbound_messages
  for each row execute function public.trg_invite_reply_reaches_sales_engineer();

-- verdict (no DDL is rolled back by it)
select case
  when (select value from public.app_secrets where key = 'invite_body') ~* '(https?://|www\.|\{\{link\}\}|al furjan|NOL-)'
    then 'PROBE FAILED: the stored invitation still carries a link, Al Furjan or the permit'
  when not exists (select 1 from public.seat_handoff_kind where type = 'invite.reply' and from_seat = 'marketing' and to_seat = 'sales_engineer')
    then 'PROBE FAILED: the invite.reply handoff kind is not registered'
  when not exists (select 1 from pg_trigger where tgname = 'z52_invite_reply_reaches_sales_engineer')
    then 'PROBE FAILED: the reply trigger is missing'
  else 'PROBE OK' end as verdict;
