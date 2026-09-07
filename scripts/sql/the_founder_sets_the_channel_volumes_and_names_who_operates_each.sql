-- THE FOUNDER SETS THE CHANNEL VOLUMES AND NAMES WHO OPERATES EACH
--
-- Rulings, 7 September 2026, in his words:
--   "phone calls i can receive of course on my number +971509319355"
--   "whatsapp for this same number is my business number so also i can receive and reply"
--   "for the american whatsapp number we have which basically shares invitations, notifications
--    it should be operated by an agent of our team"
--   "for partnership emails, you can send 1 per day till the finish"
--   "for suppliers registration, we send 10 per day for the first month, then every month we add
--    5 per day"
--
-- WHAT CHANGED IN MY THINKING, AND HE WAS RIGHT TO PUSH. I had blocked quotesdone.com for cold
-- outreach absolutely. That rule was written against 15,800 emails a month. Against 10 a day it is
-- overcautious and it obscured the real precondition.
--
-- The 10% bounce did not come from volume. It came from sending to addresses nobody had verified:
-- 16,167 of 19,896 addresses in the estate have never been checked. Mailbox providers judge a domain
-- on invalid-address rate and complaint rate, not on whether an email is cold. So the precondition
-- for opening supplier invitations is A VERIFIED LIST, not a second domain. At 10 a day to verified
-- addresses, quotesdone.com is safe, and the automatic halt at 2% bounce is what keeps it that way.
--
-- WHO OPERATES WHAT is now recorded per channel, because the defect I created two commits ago was
-- encoding a capacity for a seat that could not perform the work.

begin;

-- His ramp is additive per month (10, then 15, then 20...), not the compounding weekly ramp the
-- table already supported. Both now exist; a channel uses whichever is populated.
alter table public.outreach_channel_policy
  add column if not exists ramp_monthly_increment numeric,
  add column if not exists ramp_ceiling_per_day   numeric,
  add column if not exists operator_kind          text,
  add column if not exists operator_identity      text,
  add column if not exists precondition           text;

do $ck$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid='public.outreach_channel_policy'::regclass
                    and conname='outreach_channel_operator_kind_ck') then
    alter table public.outreach_channel_policy
      add constraint outreach_channel_operator_kind_ck
      check (operator_kind is null or operator_kind in ('founder','agent','human_hire','none'));
  end if;
end $ck$;

comment on column public.outreach_channel_policy.operator_kind is
  'Who actually performs the work on this channel. A channel whose operator is none cannot be open, whatever its cap says.';
comment on column public.outreach_channel_policy.ramp_monthly_increment is
  'Additive daily increase per calendar month, as the founder set it: 10 a day in month 1, then plus 5 a day each month.';

commit;

-- ---------------------------------------------------------------------------------------------
-- The channels as the founder ruled them.
-- ---------------------------------------------------------------------------------------------

-- 1. SUPPLIER INVITATIONS. His volume, his ramp, on quotesdone.com, gated on a verified list.
update public.outreach_channel_policy set
  channel_label = 'Supplier invitations from quotesdone.com',
  status         = 'blocked',
  status_reason  = 'Founder set the volume at 10 a day for month one, rising 5 a day each month. That '
                || 'volume is safe. What is NOT yet safe is the list: 16,167 of 19,896 addresses have '
                || 'never been verified and the measured bounce on what was actually sent is 10%, five '
                || 'times the 2% threshold. This opens the moment the list is verified, not before, '
                || 'because bounce rate is what damages a domain and this domain also carries sign-in codes.',
  max_per_day            = 10,
  max_per_week           = 70,
  ramp_start_per_day     = 10,
  ramp_monthly_increment = 5,
  ramp_weekly_growth     = null,
  ramp_ceiling_per_day   = null,
  halt_bounce_pct        = 2.0,
  halt_complaint_pct     = 0.1,
  operator_kind          = 'agent',
  operator_identity      = 'onboarding (Supplier Onboarding Specialist, supply)',
  precondition           = 'Every address MX-verified, syntax-checked and screened against the '
                        || 'suppression list before it can be sent to. Sending stops automatically if '
                        || 'bounce reaches 2% or complaints reach 0.1% in any batch.',
  authority              = 'Founder ruling 7 Sep 2026: 10 a day month one, plus 5 a day each month',
  limit_basis            = 'founder_ruling',
  limit_uncertainty      = 'The VOLUME is his ruling and is not in doubt. What remains unmeasured is '
                        || 'the bounce rate against a verified list, because no verified batch has ever '
                        || 'been sent. The first batch measures it.',
  note                   = 'Month 1 = 10/day, month 2 = 15/day, month 3 = 20/day, and so on.',
  reviewed_at            = now()
 where channel_key = 'email_transactional_domain';

-- 2. PARTNERSHIP EMAILS. One a day until the list of counterparties is exhausted.
insert into public.outreach_channel_policy (
  channel_key, channel_label, status, status_reason,
  max_per_day, max_per_week, halt_bounce_pct, halt_complaint_pct,
  shares_transactional_reputation, requires_opt_in,
  authority, limit_basis, limit_uncertainty,
  operator_kind, operator_identity, precondition, note
) values (
  'email_partnership', 'Partnership approach emails', 'open',
  'Founder ruling: one a day until the list of counterparties is finished. This is a finite pipeline '
  || 'of named organisations, not a rate channel, and one carefully written email a day to a chamber, '
  || 'an association or a distributor carries no meaningful domain risk.',
  1, 7, 2.0, 0.1, true, false,
  'Founder ruling 7 Sep 2026: one per day till the finish', 'founder_ruling',
  'None on the volume. What is unknown is how many credible counterparties exist in the UAE; nobody '
  || 'has counted them, so the length of the pipeline is not yet a number.',
  'agent', 'partnerships_mgr (Partnerships Manager, supply) drafts and sends; the founder takes any meeting that results',
  'Each email names a real organisation and a specific reason to talk. A generic partnership email to '
  || 'a list is cold outreach wearing a different word.',
  'A finite pipeline. When the counterparty list is exhausted this channel closes rather than repeating.'
)
on conflict (channel_key) do update set
  status = excluded.status, status_reason = excluded.status_reason,
  max_per_day = excluded.max_per_day, max_per_week = excluded.max_per_week,
  operator_kind = excluded.operator_kind, operator_identity = excluded.operator_identity,
  precondition = excluded.precondition, authority = excluded.authority,
  limit_basis = excluded.limit_basis, limit_uncertainty = excluded.limit_uncertainty,
  note = excluded.note, reviewed_at = now();

-- 3. WHATSAPP, OUTBOUND, from the US number. Agent-operated, as he ruled.
update public.outreach_channel_policy set
  channel_label  = 'WhatsApp outbound from the US Twilio number',
  status         = 'blocked',
  status_reason  = 'Founder ruled this number is agent-operated for invitations and notifications, and '
                || 'that settles WHO runs it. What still blocks it is not staffing: WhatsApp Business '
                || 'policy requires an approved template AND recipient opt-in for a business-initiated '
                || 'message, and zero contacts have opted in. Sending anyway degrades the number''s '
                || 'quality rating and gets it banned. Measured: 13 messages queued, none ever sent.',
  operator_kind     = 'agent',
  operator_identity = 'channel_specialist (Lifecycle Channel Operations, customer_experience)',
  precondition      = 'An approved message template, plus a recorded opt-in per recipient captured '
                   || 'through the product. Opt-in can be collected at registration and in the '
                   || 'invitation email, which is why this channel opens after email, not before.',
  requires_opt_in   = true,
  authority         = 'Founder ruling 7 Sep 2026 on the operator; Meta and Twilio policy on the gate',
  limit_basis       = 'founder_ruling',
  reviewed_at       = now()
 where channel_key = 'whatsapp';

-- 4. THE FOUNDER'S OWN UAE NUMBER. Inbound only, and he is the operator.
insert into public.outreach_channel_policy (
  channel_key, channel_label, status, status_reason,
  max_per_day, max_per_week, shares_transactional_reputation, requires_opt_in,
  authority, limit_basis, limit_uncertainty,
  operator_kind, operator_identity, precondition, note
) values (
  'founder_direct_uae', 'Calls and WhatsApp on the founder''s UAE business number', 'open',
  'The founder receives and replies personally on +971509319355, by phone and on WhatsApp. Inbound '
  || 'from a supplier who chooses to make contact carries no platform risk and no consent question, '
  || 'because they initiated it.',
  20, 100, false, false,
  'Founder ruling 7 Sep 2026: he receives calls and WhatsApp on this number', 'founder_ruling',
  'The cap is a soft estimate of how many conversations one person absorbs in a day alongside running '
  || 'the company. It is not a limit anyone enforces on him; it exists so the arithmetic does not plan '
  || 'a hundred conversations a day into one person.',
  'founder', 'Ahmad, +971509319355',
  'This number is published as the contact route, so every outbound message must carry it.',
  'INBOUND. Outbound cold dialling is a different channel and still has no operator.'
)
on conflict (channel_key) do update set
  status = excluded.status, status_reason = excluded.status_reason,
  max_per_day = excluded.max_per_day, operator_kind = excluded.operator_kind,
  operator_identity = excluded.operator_identity, authority = excluded.authority,
  limit_basis = excluded.limit_basis, note = excluded.note, reviewed_at = now();

-- 5. OUTBOUND COLD CALLING stays closed and honest about why.
update public.outreach_channel_policy set
  channel_label = 'Outbound cold calling to suppliers',
  status        = 'blocked',
  status_reason = 'Still NO OPERATOR. The founder receives calls; he did not say he would make '
               || 'hundreds of outbound cold calls, and no seat in this company can dial a phone. '
               || 'The cap below is what one hired human would carry.',
  operator_kind = 'none',
  operator_identity = null,
  precondition  = 'A hired human, or a voice system the founder has approved. Neither exists.',
  reviewed_at   = now()
 where channel_key = 'phone_call';

-- 6. PARTNERSHIP RELATIONSHIPS, as distinct from the emails that open them.
update public.outreach_channel_policy set
  channel_label = 'Partnership relationships: meetings, chambers, associations',
  status        = 'open',
  status_reason = 'The founder is the operator. An association will not take a meeting with software, '
               || 'but it will take one with the founder of a UAE company holding a DET licence. This '
               || 'is a finite set of maybe twenty to forty organisations, approached once and properly.',
  max_per_day   = 2,
  max_per_week  = 5,
  operator_kind = 'founder',
  operator_identity = 'Ahmad',
  precondition  = 'The email channel opens the conversation; this channel is what happens after.',
  authority     = 'Founder is the only person in the company who can hold a commercial conversation',
  limit_basis   = 'estimate',
  limit_uncertainty = 'Not really a per-day quantity. The real constraint is how many credible '
                   || 'counterparties exist, which nobody has counted. Modelled as a small daily cap '
                   || 'only so the arithmetic cannot plan an unlimited number of meetings.',
  note          = 'A finite pipeline of named organisations, not a rate.',
  reviewed_at   = now()
 where channel_key = 'partnership_introduction';

-- The separate outreach domain is no longer the recommendation, because his volumes do not require it.
update public.outreach_channel_policy set
  status        = 'blocked',
  status_reason = 'Not needed at the founder''s volumes. A second domain is worth buying only if '
               || 'supplier invitations ever exceed roughly 50 a day, or if complaints appear on '
               || 'quotesdone.com. Kept in the policy so the arithmetic can price that option if the '
               || 'volume ever justifies it.',
  operator_kind = 'none',
  reviewed_at   = now()
 where channel_key = 'email_outreach_domain';

-- ---------------------------------------------------------------------------------------------
-- THE SAFE-VOLUME FUNCTION LEARNS THE FOUNDER'S RAMP
--   His ramp is additive per calendar month (10 a day, then 15, then 20), not the compounding weekly
--   ramp the function already knew. It now handles both, and a channel with no operator carries zero
--   regardless of its cap, because a capacity nobody can perform is not a capacity.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_channel_safe_volume(
  p_channel_key text,
  p_required    numeric,
  p_days        int
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  p record;
  v_safe   numeric := 0;
  v_weeks  numeric;
  v_months int;
  m        int;
  v_rate   numeric;
  v_dleft  int;
  v_take   int;
begin
  if p_channel_key is null then
    return jsonb_build_object('applies', false);
  end if;

  select * into p from public.outreach_channel_policy where channel_key = p_channel_key;
  if not found then
    return jsonb_build_object('applies', true, 'ok', false, 'safe_max', 0,
      'reason', format('Channel %s has no policy. An unknown channel carries zero until someone declares its limit.', p_channel_key));
  end if;

  -- A capacity nobody can perform is not a capacity. This is the defect that put 25 dials a day
  -- against a seat made of software.
  if coalesce(p.operator_kind, 'none') = 'none' and p.status <> 'blocked' then
    return jsonb_build_object('applies', true, 'ok', false, 'safe_max', 0, 'status', p.status,
      'reason', format('Channel %s has no operator. %s', p.channel_label,
                       coalesce(p.precondition, 'Nobody and nothing can perform this work.')));
  end if;

  if p.status = 'blocked' then
    return jsonb_build_object('applies', true, 'ok', false, 'safe_max', 0, 'status', p.status,
      'operator', p.operator_identity,
      'reason', format('Channel %s is BLOCKED. %s', p.channel_label, p.status_reason));
  end if;

  if p.ramp_monthly_increment is not null and p.ramp_start_per_day is not null then
    -- The founder's additive ramp, walked month by month over the days actually available.
    v_months := ceil(p_days / 30.0);
    v_dleft  := p_days;
    for m in 0 .. greatest(v_months - 1, 0) loop
      exit when v_dleft <= 0;
      v_rate := p.ramp_start_per_day + (m * p.ramp_monthly_increment);
      if p.ramp_ceiling_per_day is not null then
        v_rate := least(v_rate, p.ramp_ceiling_per_day);
      end if;
      v_take := least(v_dleft, 30);
      v_safe := v_safe + (v_rate * v_take);
      v_dleft := v_dleft - v_take;
    end loop;
  elsif p.status = 'warming' and p.ramp_start_per_day is not null then
    v_weeks := ceil(p_days / 7.0);
    if coalesce(p.ramp_weekly_growth, 0) > 0 then
      v_safe := p.ramp_start_per_day * 7 * ((power(1 + p.ramp_weekly_growth, v_weeks) - 1) / p.ramp_weekly_growth);
    else
      v_safe := p.ramp_start_per_day * p_days;
    end if;
    if p.max_per_day is not null then
      v_safe := least(v_safe, p.max_per_day * p_days);
    end if;
  else
    v_safe := coalesce(p.max_per_day, 0) * greatest(p_days, 0);
    if p.max_per_week is not null then
      v_safe := least(v_safe, p.max_per_week * ceil(p_days / 7.0));
    end if;
  end if;

  return jsonb_build_object(
    'applies', true,
    'ok', p_required <= v_safe,
    'status', p.status,
    'channel_label', p.channel_label,
    'operator', p.operator_identity,
    'operator_kind', p.operator_kind,
    'safe_max', round(v_safe, 0),
    'required', round(coalesce(p_required, 0), 0),
    'precondition', p.precondition,
    'shares_transactional_reputation', p.shares_transactional_reputation,
    'requires_opt_in', p.requires_opt_in,
    'reason', case
      when p_required <= v_safe then format('%s can safely carry %s over %s days, operated by %s.',
                                            p.channel_label, round(v_safe,0), p_days, coalesce(p.operator_identity,'nobody'))
      else format('%s can safely carry %s over %s days, but the plan needs %s. %s',
                  p.channel_label, round(v_safe,0), p_days, round(p_required,0),
                  case when p.shares_transactional_reputation
                       then 'This channel shares a reputation with transactional mail, so exceeding it risks sign-in codes and receipts, not just the campaign.'
                       else 'Exceeding a channel''s safe throughput risks the channel itself.' end)
    end
  );
end;
$$;

comment on function public.fn_channel_safe_volume(text, numeric, int) is
  'Safe volume for a channel over N days. Honours the founder additive monthly ramp, a compounding weekly warm-up, or a flat cap. A channel with no operator carries zero.';
