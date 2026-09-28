-- THE CALENDAR RE-SEND WAITS ON REAL EDITS, NOT ON A HELD POST'S DRY RUN (marketing, 28 Sep 2026)
--
-- fn_marketing_calendar_due owes the founder a new calendar email once the content hash differs from what he
-- was sent and approved AND nothing has been edited for 30 minutes. "Edited" was read from updated_at on
-- marketing_post. But marketing_channels records every held post's dry run with patch(), which writes
-- updated_at too. So while a due post was held (approval_void after an edit) each beat's dry-run write
-- restarted the 30 minutes, and the email that would lift the hold never went out by itself. Measured on
-- production 28 Sep: post 91 updated_at 13:30:31.122 = its dry_run.at 13:30:31.122Z, while the last real edit
-- (all posts and variants) was 12:46:46. The 14:02 UTC beat should have sent the calendar and logged nothing.
--
-- The fix:
--   marketing_post.content_edited_at   set by a trigger only when a column the calendar hash reads changes
--                                      (or the post is inserted, or cancelled / un-cancelled). dry_run,
--                                      postiz_result, attempts, error and every other bookkeeping write leave it.
--   fn_marketing_calendar_due          waits on content_edited_at (posts), updated_at (variants: only content
--                                      is ever written there) and the campaign's updated_at, as before.
--   marketing_calendar_resend_decision one row each time the decision for a live campaign changes: 'due',
--                                      'quiet_period' (with the time it will be due), 'already_sent',
--                                      'already_approved', 'finished'. The function is called every beat; a row
--                                      is written only when (decision, hash) differs from the campaign's last row,
--                                      so the log is the decisions, not the beats.
-- Signature unchanged (returns table(campaign_key, current_hash)), so the edge function is not redeployed.
-- Prevented by: scripts/checks/the_calendar_resend_does_not_wait_on_a_bookkeeping_write.test.mjs

-- ── 1. the content-edit clock ──────────────────────────────────────────────────────────────────────
alter table public.marketing_post add column if not exists content_edited_at timestamptz;
comment on column public.marketing_post.content_edited_at is
  'When a field the calendar hash reads last changed (trigger z95_marketing_post_content_edited_at). Not moved by dry runs or publish bookkeeping; fn_marketing_calendar_due waits 30 minutes after it.';

-- Backfill: a row whose last write WAS its dry run (updated_at within 5 s of dry_run.at) was last edited no
-- later than its newest variant or its creation; every other row keeps updated_at (conservative: it may wait).
update public.marketing_post p
   set content_edited_at = case
         when p.dry_run ? 'at' and p.updated_at <= (p.dry_run->>'at')::timestamptz + interval '5 seconds'
           then greatest(p.created_at, (select max(v.updated_at) from public.marketing_post_variant v where v.post_id = p.id))
         else p.updated_at end
 where p.content_edited_at is null;
alter table public.marketing_post alter column content_edited_at set default now();

create or replace function public.fn_marketing_post_content_edited_at()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if tg_op = 'INSERT'
     or (old.ingest_key, old.scheduled_at, old.channels, old.video_path, old.video_sha256, old.cover_path, old.cover_sha256,
         old.media_paths, old.cta_url, old.is_demo, old.campaign_id, old.status = 'cancelled')
        is distinct from
        (new.ingest_key, new.scheduled_at, new.channels, new.video_path, new.video_sha256, new.cover_path, new.cover_sha256,
         new.media_paths, new.cta_url, new.is_demo, new.campaign_id, new.status = 'cancelled') then
    new.content_edited_at := now();
  else
    new.content_edited_at := old.content_edited_at;   -- a bookkeeping write never moves the clock, nor may it set it
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_marketing_post_content_edited_at() from public, anon, authenticated;

drop trigger if exists z95_marketing_post_content_edited_at on public.marketing_post;
create trigger z95_marketing_post_content_edited_at before insert or update on public.marketing_post
  for each row execute function public.fn_marketing_post_content_edited_at();

-- ── 2. the decision log ────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_calendar_resend_decision (
  id            bigint generated always as identity primary key,
  campaign_id   bigint not null references public.marketing_campaign(id) on delete cascade,
  decided_at    timestamptz not null default now(),
  decision      text not null check (decision in ('due', 'quiet_period', 'already_sent', 'already_approved', 'finished')),
  current_hash  text,
  last_edit_at  timestamptz,
  due_at        timestamptz
);
create index if not exists marketing_calendar_resend_decision_campaign on public.marketing_calendar_resend_decision (campaign_id, id desc);
comment on table public.marketing_calendar_resend_decision is
  'Every change in the automatic calendar re-send decision per campaign, written by fn_marketing_calendar_due (one row per change of decision or content hash, not per beat). last_edit_at is the latest real content edit; due_at is when the quiet period ends.';
alter table public.marketing_calendar_resend_decision enable row level security;
drop policy if exists marketing_calendar_resend_decision_service_role_only on public.marketing_calendar_resend_decision;
create policy marketing_calendar_resend_decision_service_role_only on public.marketing_calendar_resend_decision
  as permissive for all to public using (false) with check (false);
revoke all on public.marketing_calendar_resend_decision from anon, authenticated;

-- ── 3. the re-send ─────────────────────────────────────────────────────────────────────────────────
-- One campaign's decision, logged when it changes. Separate from the loop so a ZZ DEMO campaign can be probed
-- (fn_marketing_calendar_due never looks at a demo campaign, and a demo campaign is never mailed).
create or replace function public.fn_marketing_calendar_resend_decide(p_campaign_id bigint)
returns text
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.marketing_campaign; v_hash text; v_last_post timestamptz; v_edit timestamptz; v_dec text;
        v_prev public.marketing_calendar_resend_decision;
begin
  select * into c from public.marketing_campaign where id = p_campaign_id;
  if not found then return null; end if;
  v_hash := public.fn_marketing_campaign_hash(c.id);
  select max(p.scheduled_at) into v_last_post from public.marketing_post p where p.campaign_id = c.id and p.status <> 'cancelled';
  v_edit := greatest(c.updated_at,
                     (select max(p.content_edited_at) from public.marketing_post p where p.campaign_id = c.id),
                     (select max(v.updated_at) from public.marketing_post_variant v join public.marketing_post p on p.id = v.post_id
                       where p.campaign_id = c.id));
  v_dec := case when v_last_post is null or now() >= v_last_post then 'finished'
                when v_hash is not distinct from c.approved_hash then 'already_approved'
                when v_hash is not distinct from c.calendar_hash then 'already_sent'
                when v_edit >= now() - interval '30 minutes' then 'quiet_period'
                else 'due' end;
  select * into v_prev from public.marketing_calendar_resend_decision d where d.campaign_id = c.id order by d.id desc limit 1;
  -- a campaign that was over before this log existed is not written; every other change is
  if (v_prev.id is null and v_dec <> 'finished')
     or (v_prev.id is not null and (v_prev.decision, v_prev.current_hash) is distinct from (v_dec, v_hash)) then
    insert into public.marketing_calendar_resend_decision (campaign_id, decision, current_hash, last_edit_at, due_at)
    values (c.id, v_dec, v_hash, v_edit, v_edit + interval '30 minutes');
  end if;
  return v_dec;
end $fn$;
revoke execute on function public.fn_marketing_calendar_resend_decide(bigint) from public, anon, authenticated;

create or replace function public.fn_marketing_calendar_due()
returns table(campaign_key text, current_hash text)
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record;
begin
  for r in select c.id, c.campaign_key ck from public.marketing_campaign c where not c.is_demo order by c.id loop
    if public.fn_marketing_calendar_resend_decide(r.id) = 'due' then
      campaign_key := r.ck; current_hash := public.fn_marketing_campaign_hash(r.id); return next;
    end if;
  end loop;
end $fn$;
