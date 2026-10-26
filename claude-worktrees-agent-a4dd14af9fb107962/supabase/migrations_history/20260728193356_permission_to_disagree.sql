-- The most important line in the vision doc, and the only behaviour gap rather than a UI gap.
-- Today the company can hold an action for review. It cannot say "I recommend against this,
-- here is why, here are three alternatives." That is the difference between a command
-- executor and an executive team.

create table if not exists public.challenge_record (
  id              bigserial primary key,
  proposal        text not null,
  proposed_by     text not null default 'founder',
  challenged_by   text not null,
  stance          text not null check (stance in ('support','concern','recommend_against')),
  confidence      numeric,
  reasoning       text not null,
  violates_rank   int,
  violates_principle text,
  evidence        jsonb default '[]'::jsonb,
  alternatives    jsonb default '[]'::jsonb,
  founder_response text check (founder_response in ('accepted','overruled','modified',null)),
  responded_at    timestamptz,
  created_at      timestamptz not null default now()
);
alter table public.challenge_record enable row level security;
comment on table public.challenge_record is
  'Every time the company disagrees with a proposal, on the record: the stance, the reasoning, which company principle it conflicts with, the evidence, the alternatives, and whether the founder accepted or overruled it. Overrules are as auditable as the advice.';

-- Keywords that signal a proposal touches a governed domain, kept as data so the
-- company can widen its own judgement without a code change.
create table if not exists public.challenge_heuristic (
  id            bigserial primary key,
  pattern       text not null,
  rank_touched  int not null,
  principle     text not null,
  concern       text not null,
  alternative   text,
  active        boolean not null default true
);
alter table public.challenge_heuristic enable row level security;

insert into challenge_heuristic (pattern, rank_touched, principle, concern, alternative) values
 ('(increase|raise|add).*(fee|price|commission|subscription)', 2,'Protect customer trust',
  'A unilateral price rise on a two-sided marketplace with no onboarded supply risks churn that outweighs the revenue gain, and there is no elasticity evidence to price against.',
  'Test on one category first and measure churn before applying broadly; or hold price and raise value; or stage the increase over two quarters with a grandfathered cohort.'),
 ('(skip|bypass|disable|turn off).*(review|approval|gate|check)', 1,'Protect legal and regulatory compliance',
  'Removing a gate removes the evidence trail that makes a decision defensible afterwards. Compliance outranks speed in the constitution.',
  'Keep the gate and lower its threshold; or auto-approve the low-risk class only, with sampling.'),
 ('(delete|purge|remove).*(data|record|supplier|customer|log)', 2,'Protect customer trust and data security',
  'Deletion is irreversible and may conflict with PDPL retention obligations.',
  'Soft-delete with a retention window; or archive then purge on the policy schedule.'),
 ('(launch|start|send).*(campaign|invite|blast|marketing)', 3,'Deliver high-quality outcomes',
  'Sending into an unvalidated list risks the sending domain reputation, which is slow and expensive to recover.',
  'Validate the list first; or start at a low cap with a bounce breaker and ramp on health.'),
 ('(cut|reduce|lower).*(budget|spend|cost).*(security|compliance|backup|test)', 1,'Protect legal and regulatory compliance',
  'Cutting spend on controls trades a certain small saving for an uncertain large loss.',
  'Cut discretionary spend elsewhere; or reduce scope while keeping the control in place.'),
 ('(hire|add|create).*(department|team|employee|agent)', 5,'Improve efficiency and reduce costs',
  'Adding structure before the existing structure is saturated adds coordination cost without adding output.',
  'Measure current utilisation first; add capacity only where backlog per head is above target.')
on conflict do nothing;

create or replace function public.fn_challenge(
  p_proposal text,
  p_proposed_by text default 'founder',
  p_challenger text default 'brief'
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  h record; v_id bigint; v_stance text := 'support'; v_conf numeric := 0.5;
  v_reason text := ''; v_alts jsonb := '[]'::jsonb; v_evidence jsonb := '[]'::jsonb;
  v_rank int; v_principle text; v_hits int := 0;
  v_prior record; v_supply int; v_rev numeric;
begin
  -- 1. does the proposal collide with a ranked company principle?
  for h in select * from challenge_heuristic where active and p_proposal ~* pattern order by rank_touched limit 3
  loop
    v_hits := v_hits + 1;
    if v_rank is null or h.rank_touched < v_rank then
      v_rank := h.rank_touched; v_principle := h.principle;
    end if;
    v_reason := v_reason || case when v_reason = '' then '' else ' ' end || h.concern;
    if h.alternative is not null then
      v_alts := v_alts || jsonb_build_array(h.alternative);
    end if;
  end loop;

  -- 2. has the company tried something like this before, and what happened?
  for v_prior in
    select headline, detail, outcome from institutional_memory
     where outcome in ('worse','improved')
       and p_proposal ~* coalesce(substring(headline from '\w+'),'zzzz')
     order by created_at desc limit 3
  loop
    v_evidence := v_evidence || jsonb_build_array(
      jsonb_build_object('type','prior_outcome','verdict',v_prior.outcome,'lesson',left(v_prior.detail,240)));
    if v_prior.outcome = 'worse' then v_hits := v_hits + 2; end if;
  end loop;

  -- 3. current state that bears on almost any commercial proposal
  select count(*) into v_supply from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev
    from transactions where revealed_at > now()-interval '30 days';
  v_evidence := v_evidence || jsonb_build_array(jsonb_build_object(
    'type','current_state','onboarded_suppliers',v_supply,'revenue_30d_aed',v_rev,
    'note', case when v_supply = 0
      then 'The marketplace has no onboarded supply, so any demand-side or pricing change cannot be validated against real behaviour yet.'
      else 'Supply exists; effects are measurable.' end));

  if v_supply = 0 and p_proposal ~* '(fee|price|commission|campaign|customer|demand)' then
    v_hits := v_hits + 1;
    v_reason := v_reason || ' There is also no onboarded supply to measure the effect against, so the change would be unfalsifiable at the moment it is made.';
  end if;

  -- 4. stance
  if v_hits >= 3 then v_stance := 'recommend_against'; v_conf := 0.85;
  elsif v_hits >= 1 then v_stance := 'concern'; v_conf := 0.65;
  else
    v_stance := 'support'; v_conf := 0.6;
    v_reason := 'No conflict found with the priority hierarchy, no contrary prior outcome on record, and current state does not argue against it.';
  end if;

  if v_alts = '[]'::jsonb and v_stance <> 'support' then
    v_alts := jsonb_build_array('Run it as a bounded test with a named metric and a captured baseline, so it can be graded and reversed.');
  end if;

  insert into challenge_record (proposal, proposed_by, challenged_by, stance, confidence,
                                reasoning, violates_rank, violates_principle, evidence, alternatives)
  values (p_proposal, p_proposed_by, p_challenger, v_stance, v_conf,
          v_reason, v_rank, v_principle, v_evidence, v_alts)
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id, 'stance', v_stance, 'confidence', v_conf,
    'conflicts_with', case when v_principle is null then null
                           else 'Rank '||v_rank||' — '||v_principle end,
    'reasoning', v_reason, 'evidence', v_evidence, 'alternatives', v_alts);
end $fn$;

revoke execute on function public.fn_challenge(text,text,text) from public, anon, authenticated;

comment on function public.fn_challenge(text,text,text) is
  'Reasons a proposal against the priority hierarchy, prior graded outcomes and current company state, then returns support / concern / recommend_against with evidence and alternatives. Advice, not a veto - the founder can overrule, and the overrule is recorded.';