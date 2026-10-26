-- FIFTY-SEVEN SUPPLIERS WERE INVITED TO CLICK A BUTTON THAT WAS NOT THERE.
--
-- The brief asked why 57 real UAE suppliers never started registration and told me to walk the path:
-- invite link -> portal -> profile -> submit -> licence -> approval queue. The walk stops at step
-- one. There is no invite link.
--
-- MEASURED ON PRODUCTION, ALL 62 INVITATIONS EVER SENT:
--
--   invitations sent                          62
--   with an empty `html` column               62
--   with no http:// anywhere in `body`        62
--   whose copy says "the button below"        62
--   leads.claimed                              0
--   leads.portal_updated_at                    0
--   leads.registration_submitted_at            0
--
-- The body reads: 'To join, use the "Go to the Supplier Portal" button below and complete a short
-- company profile.' There is nothing below it. `notifications.html` is never written by the
-- composer, so the HTML email that would have rendered that button does not exist, and the
-- plain-text template it falls back to has no URL in it. Every recipient was asked to click
-- something that was never in the message.
--
-- IT IS NOT AN UNSUBSTITUTED PLACEHOLDER. app_secrets.invite_body is 1,476 characters and contains
-- exactly one placeholder, `{{company}}`. A link was never written into the template, and
-- enqueue_supplier_invites performs exactly one replace() to match. Nothing was lost in
-- substitution; nothing was ever there.
--
-- AND THE CONTRACT WAS WRITTEN DOWN THREE WEEKS AGO. claim_lookup/index.ts, 19 Jul 2026, in its own
-- header: "OUTREACH MUST NOW LINK WITH THE TOKEN, e.g. https://quotesdone.com/claim?t=<claim_token>.
-- Never put leads.id in a supplier invitation." Two things then happened: the invitation never
-- carried a token, and the /claim route was never built. Measured just now against the live site:
--
--   https://quotesdone.com/portal        -> 200   (canonical /en/portal)
--   https://quotesdone.com/claim?t=x     -> 404
--
-- So the documented URL would have 404'd even if the template had used it. The live entry point is
-- /en/portal, which is a work-email sign-up: the supplier creates an account, then registers the
-- company, uploads the trade licence and submits for approval. That path works and nobody could
-- reach it.
--
-- THIS DOES NOT SEND ANYTHING. The founder's standing decision is that supplier invitations are LAST
-- and stay disabled until one real registration completes end to end and bounce is under the
-- platform's 0.08 brake. org_tasks 1360/1361 were moved to 'proposed' for the same reason. This
-- repairs the mechanism so that the next invitation, whenever it is authorised, has a way in.
--
-- THE 62 ALREADY SENT ARE NOT RE-SENT AND NOT REWRITTEN. Their notifications rows stay exactly as
-- they went out; back-dating a link into a delivered email would be a lie about what those people
-- received. Whether to write to those 57 again is a commercial decision, not this migration's.
--
-- The token rides in the URL as ?t=<claim_token> even though the portal ignores unknown query
-- params today. That costs nothing, it is the identifier claim_lookup already accepts, and it means
-- attribution is a front-end change rather than another round of emails. leads.id is never used —
-- the enumeration fix of 19 Jul stands.

-- ── 1. the template says what is actually in the message ────────────────────────────────────────
-- Targeted replace of the one false sentence, so the rest of the founder's copy is untouched
-- byte-for-byte. The DO block RAISES if the anchor is missing rather than silently doing nothing:
-- a no-op here would leave the invitation broken while the migration reported success, which is the
-- exact failure shape this whole file is about.
do $$
declare v_old text; v_new text; v_body text;
begin
  v_old := 'To join, use the "Go to the Supplier Portal" button below and complete a short company profile.';
  v_new := E'To join, open your supplier portal here:\n\n{{link}}\n\nand complete a short company profile.';
  select value into v_body from public.app_secrets where key = 'invite_body';
  if v_body is null then raise exception 'app_secrets.invite_body is missing'; end if;
  if position(v_old in v_body) = 0 and position('{{link}}' in v_body) = 0 then
    raise exception 'invite_body does not contain the phantom-button sentence and has no {{link}} either - refusing to guess';
  end if;
  if position(v_old in v_body) > 0 then
    update public.app_secrets set value = replace(v_body, v_old, v_new) where key = 'invite_body';
  end if;
end $$;

-- ── 2. the composer substitutes it ──────────────────────────────────────────────────────────────
-- Transformed from the LIVE definition, not retyped: claim_token is threaded through cand -> prio ->
-- elig, v_site is read from app_secrets.public_site_url, and the single replace() becomes a nested
-- pair. Nothing else in this 6,500-character function is touched.
CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_site text;
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_subj text; v_body text; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_target int; v_cap int;
  v_pause boolean := false; v_why text;
begin
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then return 0; end if;

  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  insert into invite_schedule(day, planned, status) values (v_today, v_cap, 'approved')
    on conflict (day) do update set planned = excluded.planned, status = 'approved';
  v_planned := least(coalesce(p_cap, v_cap), v_cap);
  if v_planned <= 0 then return 0; end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  if not v_pause and v_bounced_recent >= 5 then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  select coalesce(nullif(btrim(value),''), 'https://quotesdone.com') into v_site
    from app_secrets where key='public_site_url';
  select value into v_subj from app_secrets where key='invite_subject';
  select value into v_body from app_secrets where key='invite_body';
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today;
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  -- How many REGISTERED suppliers we want per category before that category stops being prioritised.
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing. Both CTEs are referenced exactly once, from
  -- inside the correlated subquery in `prio`. Without this keyword Postgres inlines them there and
  -- re-runs the whole leads x lead_subcategory aggregate once per candidate - 19,632 times, twice
  -- over, ~220 s against a 120 s timeout. Neither depends on the outer row, so computing them once
  -- is semantically identical and 54x faster. Do not remove.
  with activated as materialized (
    -- suppliers who actually came on board, counted per canonical domain
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
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified
    from leads l
    where l.email is not null and l.email <> '' and l.invite_status is null
      and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
      and (public.fn_email_sendable(l.email)->>'ok')::boolean
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain,
      -- the lead's own most under-served category; emptiest category first so coverage evens out
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank
    from cand c
  ),
  elig as (
    select id, email, company_name, claim_token from (
      select id, email, company_name, claim_token, pdomain, unverified_rank,
        case when pdomain='~none' then 1 else 0 end as is_none,
        -- rk cycles: taking rk=1 from every category before any rk=2 is what spreads a run
        row_number() over (partition by pdomain order by unverified_rank, id) as rk,
        row_number() over (partition by coalesce(email_domain, split_part(email,'@',2)) order by unverified_rank, id) as domain_rk
      from prio
    ) r
    where domain_rk <= 5
    -- unclassified leads ('~none') come last: never spend the cap on a lead whose trade we do not know
    order by is_none, rk, unverified_rank, pdomain
    limit v_remaining
  ),
  ins as (
    insert into notifications(type,to_email,to_role,lead_id,subject,body,status,created_at)
    select 'supplier_invite', email, 'supplier', id, v_subj,
           replace(
             replace(v_body, '{{company}}', coalesce(nullif(btrim(company_name),''), 'there')),
             '{{link}}', v_site || '/en/portal?t=' || claim_token::text), 'queued', now()
    from elig returning to_email
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and lower(email) in (select lower(to_email) from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  return v_count;
end; $function$
;

-- ── 3. invite_status stops lying about what happened ────────────────────────────────────────────
-- The brief: "invite_status never advances past 'queued' on success — close that too." Measured:
-- 57 rows sit at 'queued' and 5 at 'bounced', and all 62 notifications read status='sent'. Only the
-- FAILURE path ever wrote back, so the supplier ledger could say a supplier had been contacted or
-- had bounced, but never that the message actually went out. A field that moves only on failure
-- reads as a queue that never drains.
--
-- AFTER UPDATE, and only on the queued -> sent edge, so a re-send or a later status change cannot
-- walk the lead backwards. Matched on lead_id, which the composer already writes.
create or replace function public.fn_invite_status_on_send()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.type = 'supplier_invite' and new.status = 'sent'
     and coalesce(old.status,'') is distinct from 'sent' and new.lead_id is not null then
    update public.leads
       set invite_status = 'sent'
     where id = new.lead_id and coalesce(invite_status,'') = 'queued';
  end if;
  return new;
end
$function$;

drop trigger if exists trg_invite_status_on_send on public.notifications;
create trigger trg_invite_status_on_send
  after update of status on public.notifications
  for each row execute function public.fn_invite_status_on_send();

-- New SECURITY DEFINER function: EXECUTE was granted to PUBLIC on creation. Revoke from PUBLIC
-- (revoking from anon alone is a silent no-op while the grant is held through PUBLIC). A trigger
-- function needs no role grant to fire - the trigger executes it regardless.
revoke execute on function public.fn_invite_status_on_send() from public;

-- The 62 already sent: their notifications are 'sent' and their leads still read 'queued', which is
-- the state the missing write-back left behind. This is not back-dating - the messages demonstrably
-- went out, the ledger simply never recorded it, and the trigger above only fixes it going forward.
update public.leads l
   set invite_status = 'sent'
 where coalesce(l.invite_status,'') = 'queued'
   and exists (select 1 from public.notifications n
                where n.lead_id = l.id and n.type = 'supplier_invite' and n.status = 'sent');
