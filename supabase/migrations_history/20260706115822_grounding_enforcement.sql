-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706115822   name: grounding_enforcement
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ RETRIEVE-BEFORE-ANSWER GROUNDING ============
-- guardrail helper: is an answer grounded (has sources or explicit citations)?
create or replace function public.fn_require_grounding(p_answer text, p_sources jsonb default '[]')
returns jsonb language plpgsql immutable set search_path=public,pg_temp as $$
declare grounded boolean:=false; reason text;
begin
  if p_sources is not null and jsonb_typeof(p_sources)='array' and jsonb_array_length(p_sources)>0 then
     grounded:=true; reason:='sources provided';
  elsif coalesce(p_answer,'') ~* '(per |according to|source:|standard |code |regulation|SIRA|DCD|ADCD|DEWA|Estidama|Al Sa|ESMA|ISO |IEC |BS |EN |NFPA|knowledge base|checklist)' then
     grounded:=true; reason:='inline citation detected';
  else reason:='no sources or citation — retrieve from knowledge base and cite before answering'; end if;
  return jsonb_build_object('grounded',grounded,'reason',reason);
end $$;

-- hard rule injected globally
delete from public.agent_knowledge where agent_key='_global' and topic='Retrieve before answering';
insert into public.agent_knowledge(agent_key,topic,content,priority) values
 ('_global','Retrieve before answering',
  'Before answering any technical, regulatory, pricing, material or procurement question, FIRST retrieve from the internal knowledge platform (call kb_query / kb_retrieve, and consult the category checklist, regulation library, materials and standards). Base the answer on what you retrieve and cite the source (e.g. the regulation code, standard, or checklist item). If retrieval returns nothing relevant, say so and ask a clarifying question or escalate — never fill the gap with an unsourced guess.',
  980);

-- extend the eval snapshot to track decision grounding rate
create or replace function public.fn_eval_snapshot(p_days int default 30)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  intake_total int; intake_complete int; q_total int; q_scored int; q_pass numeric; q_avg numeric;
  inq_matched int; inq_all int; inq_done int; inq_open int; esc_pending int; esc_total int; lat_avg numeric;
  dec_total int; dec_grounded int; k jsonb;
begin
  select count(*) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and coalesce(rfq_ready,false))
    into intake_total, intake_complete from inquiries;
  select count(*) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and quality is not null),
         avg(nullif(quality->>'score','')::numeric) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and nullif(quality->>'score','')::numeric >= 60)
    into q_total, q_scored, q_avg, q_pass from quotes;
  select count(*) filter (where i.created_at > now()-(p_days||' days')::interval),
         count(*) filter (where i.created_at > now()-(p_days||' days')::interval and exists(select 1 from inquiry_matches m where m.inquiry_id=i.id))
    into inq_all, inq_matched from inquiries i;
  select count(*) filter (where created_at > now()-(p_days||' days')::interval and (status in ('completed','accepted','closed') or completed_at is not null)),
         count(*) filter (where created_at > now()-(p_days||' days')::interval) into inq_done, inq_open from inquiries;
  begin select count(*) filter (where created_at > now()-(p_days||' days')::interval and status='pending'), count(*) filter (where created_at > now()-(p_days||' days')::interval) into esc_pending, esc_total from agent_actions; exception when others then esc_pending:=0; esc_total:=0; end;
  begin select round(avg(extract(epoch from (finished_at-started_at)))::numeric,1) into lat_avg from agent_runs where started_at > now()-(p_days||' days')::interval and finished_at is not null; exception when others then lat_avg:=null; end;
  begin select count(*), count(*) filter (where jsonb_array_length(coalesce(sources,'[]'))>0) into dec_total, dec_grounded from decision_log where created_at > now()-(p_days||' days')::interval; exception when others then dec_total:=0; dec_grounded:=0; end;

  k := jsonb_build_object(
    'window_days', p_days,
    'rfq_completeness_pct', case when intake_total=0 then null else round(intake_complete::numeric/intake_total*100,1) end,
    'quote_gate_pass_pct',  case when q_scored=0 then null else round(q_pass::numeric/q_scored*100,1) end,
    'quote_quality_avg',    round(coalesce(q_avg,0),1),
    'match_coverage_pct',   case when inq_all=0 then null else round(inq_matched::numeric/inq_all*100,1) end,
    'resolution_pct',       case when inq_open=0 then null else round(inq_done::numeric/inq_open*100,1) end,
    'escalation_rate_pct',  case when esc_total=0 then null else round(esc_pending::numeric/esc_total*100,1) end,
    'agent_latency_sec_avg',lat_avg,
    'decision_grounding_pct', case when dec_total=0 then null else round(dec_grounded::numeric/dec_total*100,1) end,
    'clarification_efficiency', null, 'hallucination_rate_pct', null, 'customer_satisfaction', null,
    'samples', jsonb_build_object('inquiries',intake_total,'quotes',q_total,'agent_actions',esc_total,'decisions',dec_total));
  return k;
end $$;

select public.fn_require_grounding('The camera must meet EN 62676 per SIRA.', '[]'::jsonb) as grounded_by_citation,
       public.fn_require_grounding('It should be fine.', '[]'::jsonb) as ungrounded;
