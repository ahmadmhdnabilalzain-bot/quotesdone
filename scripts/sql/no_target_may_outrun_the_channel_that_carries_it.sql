-- NO TARGET MAY OUTRUN THE CHANNEL THAT CARRIES IT
--
-- The founder, 7 Sep 2026, on the engine's own output of 16,129 invitations in 30 days:
-- "that amount of invitation will get our email banned". He is right, and the engine was wrong to
-- return AT_RISK for it. A plan that destroys the sending domain is not a risky plan, it is an
-- impossible one, and the arithmetic must refuse it rather than flag it.
--
-- THE PRINCIPLE THIS ENCODES. A channel has a physical safe throughput that is a property of the
-- channel and the provider, not of how badly we want the target. Budget and internal capacity are
-- negotiable. Sender reputation is not: once a domain is blacklisted the loss is not the campaign,
-- it is every login code, receipt and refund notice that shares the domain. So the channel limit sits
-- ABOVE every target, and when a target and a limit conflict, the limit wins and the target is
-- renegotiated with the founder.
--
-- WHY THIS IS NOT A REMINDER OR A COMMENT. The estate already had this rule written in prose, in the
-- safety envelope section of the plan. It was written down, and the engine still returned a number
-- that would have burned the domain. A rule that lives only in a document is not a rule.
--
-- MEASURED STATE THIS IS BUILT AGAINST, 7 Sep 2026:
--   quotesdone.com carries BOTH cold outreach and transactional mail (sign-in codes, receipts).
--   The provider's own log: 110 invitations, 98 delivered, 11 bounced, 1 suppressed = 10% bounce,
--   five times the 2% industry danger threshold, on the domain that carries authentication.
--   19,896 of 22,265 leads hold an address; 3,266 are verified and 16,167 are unverified.
-- On that evidence the safe outreach volume on quotesdone.com today is ZERO, and the policy says so.

begin;

create table if not exists public.outreach_channel_policy (
  channel_key         text        primary key,
  channel_label       text        not null,

  -- The gate. A channel that is not 'open' cannot carry ANY volume, whatever a target wants.
  status              text        not null default 'blocked'
                        check (status in ('open','warming','blocked')),
  status_reason       text        not null,

  -- Safe throughput. NULL max_per_day on an open channel is a contradiction and is refused below,
  -- because "open with no stated limit" is exactly the unbounded assumption this file exists to kill.
  max_per_day         numeric,
  max_per_week        numeric,
  ramp_start_per_day  numeric,
  ramp_weekly_growth  numeric,      -- 0.5 means volume may rise by at most 50% a week

  -- The automatic halt. These are thresholds, not targets to approach.
  halt_bounce_pct     numeric,
  halt_complaint_pct  numeric,

  -- Whether this channel shares a reputation with transactional mail. TRUE is the dangerous case.
  shares_transactional_reputation boolean not null default false,

  -- Consent. A compiled or scraped list is not an opted-in audience and most providers forbid it.
  requires_opt_in     boolean     not null default false,

  authority           text        not null,   -- who or what sets this limit
  -- HOW SOLID IS THE NUMBER. The founder asked "did you set that?" and the answer was yes for all
  -- five, with only two resting on anything solid. A cap that is an estimate must be visibly an
  -- estimate in the data, not just in whoever remembers writing it.
  limit_basis         text        not null default 'estimate',
  limit_uncertainty   text,
  reviewed_at         timestamptz not null default now(),
  note                text,

  constraint outreach_channel_open_needs_a_limit
    check (status <> 'open' or max_per_day is not null)
);

-- The table was created by an earlier run of this file without these two columns, and
-- CREATE TABLE IF NOT EXISTS will not add them. Alter explicitly so a re-apply converges.
alter table public.outreach_channel_policy
  add column if not exists limit_basis       text not null default 'estimate',
  add column if not exists limit_uncertainty text;

do $add_ck$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.outreach_channel_policy'::regclass
       and conname  = 'outreach_channel_limit_basis_ck'
  ) then
    alter table public.outreach_channel_policy
      add constraint outreach_channel_limit_basis_ck
      check (limit_basis in ('founder_ruling','provider_published','measured_here',
                             'practitioner_norm','estimate'));
  end if;
end $add_ck$;

comment on table public.outreach_channel_policy is
  'The safe throughput of each outbound channel. Sits ABOVE every target: when a target and a limit conflict, the limit wins.';

comment on column public.outreach_channel_policy.limit_basis is
  'How solid the number is. An estimate that is not labelled an estimate becomes a fact the moment someone who was not there reads it.';

comment on column public.outreach_channel_policy.status is
  'blocked means no volume at all, whatever the target requires. An open channel must state a max_per_day.';

-- ---------------------------------------------------------------------------------------------
-- The policy as the evidence supports it today.
--
-- HONESTY ABOUT WHERE THESE NUMBERS COME FROM. The founder asked "what is the max safe cap, did you
-- set that?" The answer is that I set all five, and only two rest on anything solid:
--
--   founder_ruling      the two zeros. quotesdone.com is blocked because he ruled outreach must not
--                       risk the authentication channel and the 10% bounce is measured from the
--                       provider's own log. WhatsApp is blocked because zero contacts have opted in.
--   practitioner_norm   the 50-a-day outreach cap. A conservative industry convention, NOT a
--                       published provider limit and NOT measured here.
--   estimate            the 25 dials a day and the 5 introductions a day. Both are mine, neither has
--                       ever been measured, because no supplier call has ever been made.
--
-- Every row carries limit_basis and limit_uncertainty so this is visible in the data rather than
-- resting on whoever remembers writing it. An estimate that is not labelled an estimate becomes a
-- fact the moment it is read by someone who was not there.
-- ---------------------------------------------------------------------------------------------

insert into public.outreach_channel_policy (
  channel_key, channel_label, status, status_reason,
  max_per_day, max_per_week, ramp_start_per_day, ramp_weekly_growth,
  halt_bounce_pct, halt_complaint_pct, shares_transactional_reputation, requires_opt_in,
  authority, limit_basis, limit_uncertainty, note
) values
(
  'email_transactional_domain', 'Cold outreach from quotesdone.com',
  'blocked',
  'This domain carries sign-in codes, receipts and refund notices. Its measured bounce rate on the '
  || '110 invitations the provider actually sent is 10%, five times the 2% danger threshold. Cold '
  || 'outreach here risks the authentication channel, so the safe volume is zero and stays zero.',
  0, 0, null, null, 2.0, 0.1, true, false,
  'Founder ruling 7 Sep 2026 plus the provider''s own delivery log', 'founder_ruling',
  'None. Zero is not an estimate: the founder ruled that outreach must not risk the authentication channel, and the 10% bounce is measured from the provider''s own log.',
  'Never re-open. Cold outreach moves to a separate domain permanently.'
),
(
  'email_outreach_domain', 'Cold outreach from a separate warmed domain',
  'blocked',
  'No separate outreach domain exists yet. Until one is registered, authenticated with SPF, DKIM and '
  || 'DMARC, and warmed, its safe volume is zero rather than unknown. The limits below are what it '
  || 'would be permitted to reach ONCE warm, so the arithmetic can already say what such a domain '
  || 'could and could not carry. status=blocked is what holds it at zero today.',
  50, 250, 20, 0.5, 2.0, 0.1, false, false,
  'Standard deliverability practice', 'practitioner_norm',
  'THE WEAKEST NUMBER HERE. 50 a day is the conservative practitioner norm for cold outreach from a single warmed domain; it is NOT a published Resend limit and NOT measured by us. Resend''s own acceptable-use position on cold outreach has not been checked and may forbid it outright, which would make this cap irrelevant. Scaling means more warmed domains, each ramped separately, never more volume from one.',
  'Warm from roughly 20 a day, rising by no more than 50% a week, and only while the previous week '
  || 'held bounce under 2% and complaints under 0.1%. Every address MX-verified before use.'
),
(
  'whatsapp', 'WhatsApp via Twilio',
  'blocked',
  'Zero contacts have opted in. An unsolicited business message risks the number being banned, and '
  || 'the ban takes the transactional channel with it. Measured: 13 messages queued, none ever sent.',
  0, 0, null, null, null, null, true, true,
  'Platform policy plus founder ruling', 'founder_ruling',
  'None. Zero opted-in contacts exist, so any volume is unsolicited by definition.',
  'Only opted-in recipients, only approved templates.'
),
(
  'phone_call', 'Direct calls by the seat that owns onboarding',
  'blocked',
  'NO OPERATOR EXISTS. Measured 7 Sep 2026: all 54 active seats are software (7 of kind agent, 47 of '
  || 'kind brain), no seat brief mentions calling or dialling, and the estate has no voice capability. '
  || 'This channel was marked open on the assumption that a seat could dial a phone. It cannot. The cap '
  || 'below is what ONE HUMAN could carry; it stays blocked until such a person exists.',
  25, 125, null, null, null, null, false, false,
  'Capacity of ONE HUMAN at roughly 25 dials a day - and no human exists', 'estimate',
  'MY ESTIMATE. Nobody has ever made a supplier call, so no dial rate has been measured here. 25 a day is a plausible figure for one seat doing qualified B2B outreach with notes; it should be replaced by measurement in the first week of calling.',
  'The highest-converting channel available today and the only one currently open at volume.'
),
(
  'partnership_introduction', 'Introductions through associations, chambers and distributors',
  'blocked',
  'NO OPERATOR EXISTS, for the same reason as calls. A partnership approach is a relationship built by '
  || 'a person; no seat in this company can attend a chamber meeting or hold a commercial conversation. '
  || 'Volume is bounded by counterparties, not by a sending limit, but the binding constraint today is '
  || 'that nobody can make the approach.',
  5, 25, null, null, null, null, false, false,
  'Relationship capacity', 'estimate',
  'MY ESTIMATE, and the softest number in the table. Partnership outreach is not really a per-day quantity at all; the real constraint is how many credible counterparties exist, which nobody has counted.',
  'Low volume, far higher conversion, and it carries an implied endorsement cold email cannot buy.'
)
-- The LIMITS are canonical and come from this file, so a re-apply corrects them. The STATUS is not
-- overwritten, because opening or blocking a channel is an operating decision that may have been
-- taken since, and this migration must not silently re-open something someone shut.
on conflict (channel_key) do update set
  max_per_day        = excluded.max_per_day,
  max_per_week       = excluded.max_per_week,
  ramp_start_per_day = excluded.ramp_start_per_day,
  ramp_weekly_growth = excluded.ramp_weekly_growth,
  halt_bounce_pct    = excluded.halt_bounce_pct,
  halt_complaint_pct = excluded.halt_complaint_pct,
  shares_transactional_reputation = excluded.shares_transactional_reputation,
  requires_opt_in    = excluded.requires_opt_in,
  channel_label      = excluded.channel_label,
  authority          = excluded.authority,
  limit_basis        = excluded.limit_basis,
  limit_uncertainty  = excluded.limit_uncertainty,
  note               = excluded.note,
  reviewed_at        = now();

-- Driver stages can now name the channel that carries them.
alter table public.target_driver
  add column if not exists channel_key text references public.outreach_channel_policy(channel_key);

comment on column public.target_driver.channel_key is
  'The outbound channel this stage''s volume travels on. When set, the channel policy caps the stage regardless of budget or internal capacity.';

commit;

-- ---------------------------------------------------------------------------------------------
-- THE CHECK ITSELF
--   Given a stage's required volume and the days available, is that volume safe on its channel?
--   Returns the verdict, the safe maximum, and the plain reason. Deterministic; no model.
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
  v_safe numeric;
  v_weeks numeric;
begin
  if p_channel_key is null then
    return jsonb_build_object('applies', false);
  end if;

  select * into p from public.outreach_channel_policy where channel_key = p_channel_key;
  if not found then
    -- An unknown channel is not an unlimited one.
    return jsonb_build_object(
      'applies', true, 'ok', false, 'safe_max', 0,
      'reason', format('Channel %s has no policy. An unknown channel carries zero until someone declares its limit.', p_channel_key));
  end if;

  if p.status = 'blocked' then
    return jsonb_build_object(
      'applies', true, 'ok', false, 'safe_max', 0, 'status', p.status,
      'reason', format('Channel %s is BLOCKED. %s', p.channel_label, p.status_reason));
  end if;

  -- A warming channel does not get max_per_day times days. It gets the ramp, which compounds weekly
  -- from a small start. Treating a warming channel as if it were at full throughput on day one is
  -- how a domain gets burned in week one.
  if p.status = 'warming' and p.ramp_start_per_day is not null then
    v_weeks := ceil(p_days / 7.0);
    -- sum of a geometric ramp: start*7 * ((1+g)^weeks - 1) / g
    if coalesce(p.ramp_weekly_growth, 0) > 0 then
      v_safe := p.ramp_start_per_day * 7 *
                ((power(1 + p.ramp_weekly_growth, v_weeks) - 1) / p.ramp_weekly_growth);
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
    'safe_max', round(v_safe, 0),
    'required', round(coalesce(p_required, 0), 0),
    'shares_transactional_reputation', p.shares_transactional_reputation,
    'requires_opt_in', p.requires_opt_in,
    'reason', case
      when p_required <= v_safe then format('%s can safely carry %s over %s days.', p.channel_label, round(v_safe,0), p_days)
      else format('%s can safely carry %s over %s days, but the plan needs %s. %s',
                  p.channel_label, round(v_safe,0), p_days, round(p_required,0),
                  case when p.shares_transactional_reputation
                       then 'This channel shares a reputation with transactional mail, so exceeding it risks sign-in codes and receipts, not just the campaign.'
                       else 'Exceeding a channel''s safe throughput risks the channel itself.' end)
    end
  );
end;
$$;

revoke execute on function public.fn_channel_safe_volume(text, numeric, int) from public;

comment on function public.fn_channel_safe_volume(text, numeric, int) is
  'Is a required volume safe on its channel over the days available? An unknown or blocked channel carries zero.';
