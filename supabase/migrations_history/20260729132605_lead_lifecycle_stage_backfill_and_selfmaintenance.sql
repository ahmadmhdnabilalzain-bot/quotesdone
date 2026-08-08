-- WHY: Founder spec says "Agents track status: contacted / no response / responded & registered".
-- leads.lifecycle_stage existed but was NULL on all 20,464 rows, so that status was never actually
-- tracked. This migration (a) derives the stage from evidence that already exists on the row,
-- (b) backfills every row, and (c) makes it self-maintaining via a BEFORE trigger on the source
-- columns plus a nightly reconcile job for the one transition that is time-based (no_response),
-- so it cannot silently go stale again.
--
-- STAGES (small, documented set; evaluated in this precedence order):
--   registered     responded AND registered: claimed / signed / registration submitted /
--                  claimed_by set / has a registration_status or approval_status decision
--   responded      came back and engaged but has not completed registration:
--                  portal_updated_at, accepted_terms_at, or owner_email_verified
--   undeliverable  outreach could not be delivered (invite_status bounced/failed/invalid) —
--                  tracked separately from "no response" because it is a data problem, not a decision
--   no_response    outreach left the building >14 days ago and nothing came back
--   contacted      outreach sent within the last 14 days, still inside the response window
--   not_contacted  no outreach attempted yet (today: the overwhelming majority)

create or replace function public.fn_lead_lifecycle_stage(l public.leads)
returns text
language sql
stable
as $$
  select case
    when l.claimed is true
      or l.signed is true
      or l.registration_submitted_at is not null
      or nullif(btrim(coalesce(l.claimed_by, '')), '') is not null
      or nullif(btrim(coalesce(l.approval_status, '')), '') is not null
      or nullif(btrim(coalesce(l.registration_status, '')), '') is not null
      then 'registered'
    when l.portal_updated_at is not null
      or l.accepted_terms_at is not null
      or l.owner_email_verified is true
      then 'responded'
    when lower(btrim(coalesce(l.invite_status, ''))) in ('bounced', 'failed', 'undeliverable', 'invalid', 'rejected')
      then 'undeliverable'
    when (l.invited_at is not null and l.invited_at < now() - interval '14 days')
      or (l.invited_at is null and l.contacted is true and coalesce(l.created_at, now()) < now() - interval '14 days')
      then 'no_response'
    when l.invited_at is not null
      or l.contacted is true
      or nullif(btrim(coalesce(l.invite_status, '')), '') is not null
      then 'contacted'
    else 'not_contacted'
  end
$$;

comment on function public.fn_lead_lifecycle_stage(public.leads) is
  'Single source of truth for leads.lifecycle_stage. Derives contacted / no_response / responded / registered (plus undeliverable and not_contacted) from the evidence columns already on the row. Used by both the trigger and the nightly reconcile job so the two can never disagree.';

-- (b) keep it current whenever any source column changes
create or replace function public.trg_leads_lifecycle_stage()
returns trigger
language plpgsql
as $$
begin
  new.lifecycle_stage := public.fn_lead_lifecycle_stage(new);
  return new;
end;
$$;

drop trigger if exists trg_leads_lifecycle_stage on public.leads;
create trigger trg_leads_lifecycle_stage
  before insert or update of
    claimed, signed, registration_submitted_at, claimed_by, approval_status, registration_status,
    portal_updated_at, accepted_terms_at, owner_email_verified,
    invite_status, invited_at, contacted, created_at, lifecycle_stage
  on public.leads
  for each row
  execute function public.trg_leads_lifecycle_stage();

-- (c) the contacted -> no_response transition is driven by the clock, not by a write, so a trigger
-- alone would let it go stale. This reconcile pass is idempotent and only touches rows that drifted.
create or replace function public.fn_refresh_lead_lifecycle()
returns integer
language plpgsql
as $$
declare n integer;
begin
  update public.leads l
     set lifecycle_stage = public.fn_lead_lifecycle_stage(l)
   where l.lifecycle_stage is distinct from public.fn_lead_lifecycle_stage(l);
  get diagnostics n = row_count;
  return n;
end;
$$;

create index if not exists leads_lifecycle_stage_idx on public.leads (lifecycle_stage);

-- backfill now
select public.fn_refresh_lead_lifecycle();
