-- THE CEO DECISION REGISTER, ITS AUTHORITY, AND ONE CALL THAT SAYS WHERE THE SEAT STANDS
--
-- The position document describes ten domains and the decisions each one owns. A document cannot be
-- queried, cannot be checked, and cannot refuse anything, so the register lives here instead.
--
-- BUILT FOR THE COMPANY THAT EXISTS. Two seats, no departments, no tasks, no workflows. Nothing
-- below opens a task, cascades to a department or travels a manager chain -- all three were removed
-- on the founder's ruling of 7 September 2026. The CEO decides, records the decision with the
-- evidence it rested on, and reports.

create table if not exists public.ceo_decision (
  decision_key      text primary key,
  domain            text not null,
  decision          text not null,      -- what this seat actually decides, in one sentence
  trigger_condition text not null,      -- what makes the decision due; never "quarterly review"
  measure           text not null,      -- the reading that says whether it was decided well
  measure_sql       text,               -- null where no instrument exists yet, and that is stated
  authority         text not null,      -- 'ceo_alone' or 'founder_reserved'
  evidence_required text not null,      -- what must be recorded WITH the decision
  cadence           text not null,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  constraint ceo_decision_authority_ck check (authority in ('ceo_alone','founder_reserved'))
);

comment on table public.ceo_decision is
  'The decisions the CEO seat owns. A row here is a standing accountability, not a task: nothing creates work from it. authority says whether the seat may decide alone or must reach the founder.';

-- Every decision the seat holds. The measure column is the honest part: where no instrument exists,
-- measure_sql is null and the measure says so in words rather than pointing at a number that would
-- have to be invented.
insert into public.ceo_decision (decision_key, domain, decision, trigger_condition, measure, measure_sql, authority, evidence_required, cadence) values

 ('target_is_reachable', 'Strategic planning',
  'Whether the AED 1,000,000 target is still reachable on the evidence, and what must change if it is not.',
  'Any weekly feasibility run whose verdict is not REACHABLE, or any week the required run rate rises above twice the highest ever measured.',
  'The verdict on the live contract, and how many of its driver rates are measured rather than assumed.',
  $q$select verdict || ' (' || measured_rate_count || ' measured / ' || assumed_rate_count || ' assumed rates)'
       from public.target_verdict v join public.target_contract c on c.id = v.contract_id
      where c.status = 'active' order by v.run_at desc limit 1$q$,
  'ceo_alone',
  'The feasibility verdict it rested on, the binding stage, and the specific change proposed.', 'weekly'),

 ('binding_constraint', 'Problem solving',
  'Which single stage of the funnel is the binding constraint, and therefore what the company works on next.',
  'Any week the binding stage named by the feasibility run differs from the one currently being worked.',
  'The binding stage on the latest verdict.',
  $q$select coalesce(binding_stage, '(none computed yet)') from public.target_verdict order by run_at desc limit 1$q$,
  'ceo_alone',
  'The verdict naming the stage, and what was worked on instead if the answer is to override it.', 'weekly'),

 ('spend_against_constraint', 'Resource allocation',
  'Whether money is aimed at the binding constraint, and to move it if it is not.',
  'Any month in which spend went somewhere other than the binding stage.',
  'Spend in the last 30 days aimed at the binding stage, in AED. No instrument attributes spend to a funnel stage yet.',
  null,
  'ceo_alone',
  'The amount, the stage it was aimed at, and the binding stage at the time.', 'monthly'),

 ('channel_volume', 'Operational alignment',
  'The volume each outreach channel may carry, inside the ceilings the founder set.',
  'Any proposal to send more than the standing volume, or any bounce rate above 5 per cent.',
  'The standing ceiling on each channel.',
  $q$select coalesce(string_agg(channel_key || ' ' || coalesce(daily_cap::text,'(no cap)'), '; ' order by channel_key),
                     '(no channel policy rows)') from public.outreach_channel_policy$q$,
  'ceo_alone',
  'The channel, the ceiling, the volume sent, and the bounce rate that justified any change.', 'daily'),

 ('supplier_admission', 'Operational alignment',
  'Whether a supplier is admitted, on the founder''s six mandatory fields and nothing else.',
  'A registration arrives with all six present.',
  'Suppliers who have completed registration.',
  $q$select count(*)::text from public.leads where claimed$q$,
  'ceo_alone',
  'The six fields, the OTP result on the email, and the UAE mobile that confirmed.', 'per event'),

 ('refund', 'Risk management',
  'Nothing. Every refund is the founder''s decision alone and this seat may only prepare it.',
  'A buyer asks for a refund, or a reveal is disputed.',
  'Refunds recorded against a transaction. Each one must carry the founder''s answer.',
  $q$select count(*)::text from public.transactions
      where coalesce(refund_status,'') <> ''$q$,
  'founder_reserved',
  'The transaction, the buyer''s reason, the reveal it relates to, and the recommendation -- handed to the founder, never acted on.', 'per event'),

 ('paid_inference', 'Resource allocation',
  'Nothing while the hold stands. OpenRouter is held by founder order and this seat may not lift it.',
  'Any request that needs a paid model while the hold is on.',
  'Paid inference charged in the last 30 days. While the hold stands this must read zero.',
  $q$select coalesce(sum(cost_aed), 0)::text from public.ai_cost_log where created_at > now() - interval '30 days'$q$,
  'founder_reserved',
  'The request that wanted it, the deterministic answer given instead, and the cost that would have been incurred.', 'per event'),

 ('risk_owner', 'Risk management',
  'Who owns each live risk and by when its mitigation is tested.',
  'A risk is raised, or a mitigation passes its review date untested.',
  'Live risks with no owner or no tested mitigation. No instrument records when a mitigation was last actually tested.',
  null,
  'ceo_alone',
  'The risk, the owner, the mitigation, and the date it was last actually tested rather than described.', 'monthly'),

 ('structure', 'Vision',
  'Nothing. The organisation''s shape is the founder''s, and he is rebuilding it one piece at a time.',
  'Any work that does not fit either existing seat.',
  'Seats that exist. Two is correct until he says otherwise.',
  $q$select count(*)::text from public.org_role$q$,
  'founder_reserved',
  'What the work was, why neither seat fits it, and what was done instead of inventing a seat.', 'per event'),

 ('report_to_founder', 'PR and access',
  'What reaches the founder, and what is decided without troubling him.',
  'Every reporting cadence, and immediately on anything in a founder_reserved row.',
  'Decisions recorded in the last 7 days.',
  $q$select count(*)::text from public.ceo_decision_log where decided_at > now() - interval '7 days'$q$,
  'ceo_alone',
  'The decision, its evidence, and whether it was escalated or taken alone.', 'weekly')

on conflict (decision_key) do nothing;

-- WHERE A DECISION ACTUALLY LANDS. A decision that leaves no row is a decision nobody can audit, and
-- this estate has already proved what that costs: 113 of 134 KPI tasks were closed having recorded
-- the facts and decided nothing, and every underlying number stayed missed.
create table if not exists public.ceo_decision_log (
  id                   bigserial primary key,
  decision_key         text not null references public.ceo_decision(decision_key),
  decided_at           timestamptz not null default now(),
  the_decision         text not null,
  evidence             jsonb not null,
  reading_before       text,
  reading_after        text,
  escalated_to_founder boolean not null default false,
  founder_answer       text,
  constraint ceo_decision_log_evidence_ck
    check (jsonb_typeof(evidence) = 'object' and evidence <> '{}'::jsonb)
);

comment on table public.ceo_decision_log is
  'One row per decision actually taken. The evidence CHECK refuses an empty object on purpose: a decision recorded with no evidence is the close-that-carries-no-act defect wearing a new name.';

-- ---------------------------------------------------------------------------------------------
-- WHERE THE SEAT STANDS, IN ONE CALL, READ LIVE
-- ---------------------------------------------------------------------------------------------
-- Every domain, its decision, and the reading right now. Where an instrument exists the number is
-- read; where none exists the row says NOT INSTRUMENTED rather than returning a zero that would be
-- mistaken for a measurement. A zero meaning "nothing was measured" and a zero meaning "measured,
-- and it is zero" are different answers, and confusing them is how a gap reads as health.
create or replace function public.fn_ceo_standing()
returns table(domain text, decision_key text, authority text, reading text, reading_kind text)
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record;
  v text;
begin
  for r in select d.domain, d.decision_key, d.authority, d.measure, d.measure_sql
             from public.ceo_decision d
            where d.active
            order by d.domain, d.decision_key
  loop
    domain := r.domain; decision_key := r.decision_key; authority := r.authority;
    if r.measure_sql is null then
      reading := 'NOT INSTRUMENTED -- ' || r.measure;
      reading_kind := 'not_instrumented';
    else
      begin
        execute r.measure_sql into v;
        reading := coalesce(v, '(null)');
        reading_kind := 'measured';
      exception when others then
        -- An instrument that throws is not a zero either. It is a broken instrument, and it says so.
        reading := 'INSTRUMENT FAILED -- ' || sqlerrm;
        reading_kind := 'instrument_failed';
      end;
    end if;
    return next;
  end loop;
end $function$;

comment on function public.fn_ceo_standing() is
  'Every decision this seat owns and its reading right now. A domain with no instrument reports NOT INSTRUMENTED rather than zero, and an instrument that throws reports INSTRUMENT FAILED rather than zero.';
