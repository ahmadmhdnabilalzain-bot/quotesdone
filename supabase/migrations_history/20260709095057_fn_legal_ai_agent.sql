-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709095057   name: fn_legal_ai_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.leg_flag(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='legal_flag' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('legal_ai','legal_flag','pending',p_risk,p_title,
      p_reco||E'\n\n⚠️ Not legal advice — this is a flag for you to review with a licensed UAE lawyer.',
      jsonb_build_object('signal',p_sig),'legal',p_sig);
  end if;
end $$;
revoke all on function public.leg_flag(text,boolean,text,text,text) from anon, authenticated, public;

create or replace function public.fn_legal_ai()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare k record; v_health numeric; v_terms numeric; v_fresh numeric; n int; v_missing text; v_regchg int;
begin
  select * into k from legal_kpis;
  -- refresh checklist presence
  update legal_checklist lc set present = exists(select 1 from legal_documents d where d.slug = lc.match_slug);

  v_terms := round((coalesce(k.customer_terms_acceptance_pct,0)+coalesce(k.supplier_terms_acceptance_pct,0))/2,1);
  v_fresh := case when k.policies_published=0 then 0 else round(100.0*(k.policies_published-k.policies_stale)/k.policies_published,1) end;
  v_health := round(coalesce(k.coverage_pct,0)*0.35 + v_terms*0.30 + v_fresh*0.20 + greatest(0,100-coalesce(k.open_legal_flags,0)*10)*0.15,1);

  insert into legal_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('legal_health',v_health,'terms_acceptance_avg',v_terms))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  select string_agg(requirement,'; ') into v_missing from legal_checklist where not present and priority=1;
  select count(*) into v_regchg from compliance_sources where last_changed_at >= now()-interval '30 days';

  -- ESCALATIONS (founder-visible legal_flag; never legal advice)
  perform leg_flag('missing_core_docs', coalesce(k.critical_missing,0)>0, 'high', 'Core legal documents missing',
    'The platform is operating without these core documents: '||coalesce(v_missing,'')||'. They govern your contractual relationship with customers and suppliers (liability, governing law, dispute resolution). Have a licensed UAE lawyer prepare and approve them, then publish as versioned legal documents.');
  perform leg_flag('supplier_terms_acceptance', coalesce(k.suppliers_approved,0)>0 and coalesce(k.supplier_terms_acceptance_pct,0) < 90, 'high', 'Suppliers have not accepted current terms',
    'Only '||coalesce(k.supplier_terms_acceptance_pct,0)||'% of approved suppliers have accepted the current terms. Enforce terms acceptance (click-wrap / signed) at onboarding so agreements are enforceable.');
  perform leg_flag('customer_terms_acceptance', coalesce(k.customer_terms_acceptance_pct,0) < 90, 'medium', 'Customers have not accepted current terms',
    'Only '||coalesce(k.customer_terms_acceptance_pct,0)||'% of customers have accepted the current terms. Gate key actions (posting an inquiry / paying to reveal) behind explicit terms acceptance.');
  perform leg_flag('stale_policies', coalesce(k.policies_stale,0)>0, 'low', 'Policies due for annual review',
    k.policies_stale||' published policy(ies) have not been reviewed in over a year. Schedule an annual legal review.');
  perform leg_flag('reg_change_review', v_regchg>0, 'medium', 'Regulatory change may affect your terms/policies',
    v_regchg||' monitored authority source(s) changed in the last 30 days. Review whether your terms, privacy or compliance policies need updating with a lawyer.');

  select count(*) into n from agent_actions where agent='legal_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'legal_health',v_health,'kpis',to_jsonb(k),'open_flags',n);
end $fn$;
revoke all on function public.fn_legal_ai() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('legal_ai','Legal AI','⚖️',true,
  'Guards the platform''s legal posture. Maintains the register of contracts, terms and policies (customer T&C, supplier agreement, NDA, privacy, refund, KYC/AML, anti-bribery, and more); tracks a completeness checklist, terms-acceptance coverage, policy freshness and a legal risk score; reviews agreements/NDAs for missing or risky clauses; and monitors regulatory change for legal impact. It ALWAYS ESCALATES anything requiring licensed legal advice to the founder and a qualified UAE lawyer, and NEVER gives definitive legal advice, signs, or publishes a legal document on its own. Every output is a flag for human legal review, not advice.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('legal_ai_daily','15 5 * * *', $$select public.fn_legal_ai();$$);
