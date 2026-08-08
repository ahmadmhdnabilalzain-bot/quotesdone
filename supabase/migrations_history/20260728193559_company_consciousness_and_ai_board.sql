-- Layer 10: every night the company asks itself nine questions. Nobody starts it.
create table if not exists public.company_reflection (
  id           bigserial primary key,
  reflected_on date not null unique,
  answers      jsonb not null,
  concerns     int not null default 0,
  actions      int not null default 0,
  created_at   timestamptz not null default now()
);
alter table public.company_reflection enable row level security;

create or replace function public.fn_company_reflect()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare a jsonb := '{}'::jsonb; n_concern int := 0; n_act int := 0;
  v_learned int; v_errors int; v_wrong int; v_dept text; v_improved text;
  v_stale int; v_missed int; v_comp int; v_worst text;
begin
  select count(*) into v_learned from institutional_memory where created_at > now()-interval '24 hours';
  select count(*) into v_errors  from agent_runs where status='error' and started_at > now()-interval '24 hours';
  select count(*) into v_wrong   from outcome_record where verdict='worse' and closed_at > now()-interval '24 hours';
  select dept_key into v_dept from org_tasks where status<>'done' group by dept_key order by count(*) desc limit 1;
  select string_agg(agent_key,', ') into v_improved from (
    select agent_key from outcome_record where verdict='improved' and closed_at > now()-interval '7 days' limit 3) x;
  select count(*) into v_stale from agent_knowledge where validation_status in ('stale','quarantined');
  select count(*) into v_missed from v_supply_gap where status='READY - not yet invited';
  select count(*) into v_comp from competitor;
  select name into v_worst from v_supply_gap where status like 'NO POOL%' limit 1;

  a := jsonb_build_object(
    'what_did_i_learn', v_learned||' lesson(s) entered institutional memory in the last 24 hours.',
    'what_mistakes_did_i_make', v_errors||' agent run(s) errored.',
    'which_decisions_were_wrong', v_wrong||' graded improvement(s) made things worse and were flagged for reversal.',
    'which_departments_are_struggling', coalesce('Heaviest open backlog: '||v_dept,'No department is carrying an unusual backlog.'),
    'which_employees_improved', coalesce('Improvements that worked came from: '||v_improved,'No graded improvement closed successfully yet.'),
    'which_knowledge_became_outdated', v_stale||' knowledge item(s) are stale or quarantined.',
    'which_opportunities_did_i_miss', v_missed||' category/categories have a viable supplier pool and no invitations sent.',
    'which_competitor_became_stronger', v_comp||' competitor(s) tracked; 0 market signals captured, so this cannot be answered honestly yet.',
    'how_can_i_be_better_tomorrow', coalesce('Close the supply gap starting with '||v_worst,'Close the open KPI gaps before adding new work.'));

  if v_errors > 10 then n_concern := n_concern + 1; end if;
  if v_wrong  > 0  then n_concern := n_concern + 1; end if;
  if v_stale  > 50 then n_concern := n_concern + 1; end if;

  -- the honest answer becomes work, not just a diary entry
  if v_missed > 0 then
    insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)
    select 'procurement','Nightly reflection: '||v_missed||' category(ies) ready but uninvited',
           'The company noticed overnight that '||v_missed||' category(ies) hold a viable supplier pool with no invitations sent. Queue them or record why not.',
           'proposed','advisory',false,'invite'
    where not exists (select 1 from org_tasks where title like 'Nightly reflection: % ready but uninvited' and status<>'done');
    if found then n_act := n_act + 1; end if;
  end if;

  insert into company_reflection (reflected_on, answers, concerns, actions)
  values (current_date, a, n_concern, n_act)
  on conflict (reflected_on) do update set answers=excluded.answers, concerns=excluded.concerns, actions=excluded.actions;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_reflect',now(),now(),'ok',jsonb_build_object('concerns',n_concern,'actions',n_act),
    'Nightly self-reflection: '||n_concern||' concern(s), '||n_act||' action(s) opened. Nobody asked for this.');
  return jsonb_build_object('concerns',n_concern,'actions',n_act,'answers',a);
end $fn$;
revoke execute on function public.fn_company_reflect() from public, anon, authenticated;

-- Feature 24: an AI board that gives independent recommendations before a major decision.
create table if not exists public.board_advisor (
  advisor_key text primary key,
  name        text not null,
  lens        text not null,
  asks        text not null,
  weight      numeric not null default 1.0,
  active      boolean not null default true
);
alter table public.board_advisor enable row level security;

insert into board_advisor (advisor_key,name,lens,asks) values
 ('risk','Risk Advisor','downside','What is the worst realistic outcome, how likely is it, and is it reversible?'),
 ('economist','Economist','unit economics','Does this improve contribution per RFQ, or only top-line?'),
 ('growth','Growth Advisor','compounding','Does this compound, or is it a one-off lift that decays?'),
 ('customer','Customer Advocate','buyer','Would a buyer paying a reveal fee think this was fair?'),
 ('supplier','Marketplace Advisor','supply side','Does this make suppliers more or less likely to quote?'),
 ('ethics','Ethics Advisor','integrity','Would we be comfortable if this were published?'),
 ('technology','Technology Advisor','feasibility','Can the platform carry this without new fragility or cost?')
on conflict do nothing;

create table if not exists public.board_opinion (
  id            bigserial primary key,
  subject       text not null,
  subject_ref   text,
  advisor_key   text not null references board_advisor(advisor_key),
  recommendation text not null check (recommendation in ('proceed','proceed_with_conditions','do_not_proceed','abstain')),
  rationale     text not null,
  confidence    numeric,
  created_at    timestamptz not null default now()
);
alter table public.board_opinion enable row level security;

create or replace function public.fn_board_review(p_subject text, p_subject_ref text default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare adv record; ch jsonb; v_rec text; v_conf numeric; v_supply int; v_rev numeric;
  n_pro int:=0; n_cond int:=0; n_against int:=0; v_out jsonb := '[]'::jsonb;
begin
  ch := fn_challenge(p_subject,'board','board');
  select count(*) into v_supply from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at>now()-interval '30 days';

  for adv in select * from board_advisor where active order by advisor_key loop
    -- each advisor reasons through its own lens against the same facts
    if adv.advisor_key='risk' and (ch->>'stance')='recommend_against' then
      v_rec:='do_not_proceed'; v_conf:=0.85;
    elsif adv.advisor_key='economist' and v_rev=0 then
      v_rec:='proceed_with_conditions'; v_conf:=0.7;
    elsif adv.advisor_key in ('customer','supplier') and v_supply=0 then
      v_rec:='abstain'; v_conf:=0.5;
    elsif (ch->>'stance')='recommend_against' then
      v_rec:='do_not_proceed'; v_conf:=0.75;
    elsif (ch->>'stance')='concern' then
      v_rec:='proceed_with_conditions'; v_conf:=0.65;
    else
      v_rec:='proceed'; v_conf:=0.6;
    end if;

    insert into board_opinion (subject,subject_ref,advisor_key,recommendation,rationale,confidence)
    values (p_subject,p_subject_ref,adv.advisor_key,v_rec,
      adv.name||' ('||adv.lens||') asks: '||adv.asks||' — '||
      case v_rec
        when 'do_not_proceed' then 'On the evidence available this fails that test.'
        when 'proceed_with_conditions' then 'Proceed only with a named metric, a captured baseline and a reversal path.'
        when 'abstain' then 'There is no data on this side of the marketplace yet; an opinion would be invention.'
        else 'Nothing in this lens argues against it.' end, v_conf);

    if v_rec='proceed' then n_pro:=n_pro+1;
    elsif v_rec='proceed_with_conditions' then n_cond:=n_cond+1;
    elsif v_rec='do_not_proceed' then n_against:=n_against+1; end if;

    v_out := v_out || jsonb_build_array(jsonb_build_object('advisor',adv.name,'lens',adv.lens,'recommendation',v_rec,'confidence',v_conf));
  end loop;

  return jsonb_build_object('subject',p_subject,'proceed',n_pro,'with_conditions',n_cond,
    'against',n_against,'abstained',(select count(*) from board_advisor where active)-n_pro-n_cond-n_against,
    'board_verdict', case when n_against>0 then 'DO NOT PROCEED' when n_cond>0 then 'PROCEED WITH CONDITIONS' else 'PROCEED' end,
    'challenge_stance', ch->>'stance', 'opinions', v_out);
end $fn$;
revoke execute on function public.fn_board_review(text,text) from public, anon, authenticated;