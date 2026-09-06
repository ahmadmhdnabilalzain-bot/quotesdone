-- A REGULATION AWAITING PUBLICATION IS HELD WITH ITS ROLE, NOT THE FOUNDER (6 Sep 2026).
--
-- The knowledge_approval agent_action said the regulation "is awaiting your approval before it
-- publishes". It is held with fn_action_holder('knowledge_approval','knowledge_curator'); the
-- founder's only decision is a refund. The recommendation names the holder.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_knowledge_curator_regulation_is_held_with_its_role.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_knowledge_curator()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_health numeric; n_task int; n_appr int:=0; rec record; rc record; v_gaps jsonb;
begin
  select * into k from knowledge_kpis;
  select * into rc from reg_coverage;
  v_health := round(coalesce(k.coverage_pct,0)*0.30 + coalesce(k.accuracy_pct,0)*0.25 + coalesce(k.freshness_pct,0)*0.25 + coalesce(k.usage_reach_pct,0)*0.20,1);
  insert into knowledge_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k) || jsonb_build_object('health',v_health,'reg_coverage',to_jsonb(rc)))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  perform kn_task('playbook_gap', (k.categories_total - k.cat_with_playbook) > 0, 'medium', 'Qualification playbook gaps',
    (k.categories_total - k.cat_with_playbook)||' of '||k.categories_total||' categories lack a qualification playbook. Generating them sharpens RFQ qualification quality.',
    jsonb_build_array(
      'A playbook''s EXISTENCE is being counted, not its quality. A generated playbook nobody has read counts the same as one refined against real RFQs.',
      'All '||k.categories_total||' categories deserve one. Categories with no demand and no supplier do not need a playbook before they have either.',
      'The intake asks its questions from category_specs, not from these playbooks, so a missing playbook degrades qualification rather than stopping it.'),
    'Each playbook sharpens the questions asked of a buyer in that trade, which is what decides whether a supplier can price the job without a site visit. It is upstream of every quote in the category.',
    'Model spend, once per category, plus review time. Generating all of them unread is the wasteful case the first assumption names.');

  perform kn_task('stale_compliance', (k.compliance_active - k.compliance_fresh) > 0, 'low', 'Stale compliance sources',
    (k.compliance_active - k.compliance_fresh)||' compliance sources have not been re-checked in 45 days.',
    jsonb_build_array(
      'Age is a proxy for risk, and a poor one: a source unchanged for two years may be perfectly current, while one re-checked yesterday can already be superseded.',
      'Re-checking means fetching the page. The authority not having MOVED the document is assumed, and authorities move documents without redirecting.'),
    'A compliance reference is what suppliers and BoQ checklists are held to. Confirming '||(k.compliance_active - k.compliance_fresh)||' stale source(s) keeps quotes defensible; the alternative is discovering a rule changed when a job fails inspection.',
    'No spend. An automated fetch per source, plus review time when one has genuinely changed.');

  perform kn_task('low_accuracy', coalesce(k.flagged_revisions,0) > 0, 'medium', 'Knowledge flagged by validation',
    k.flagged_revisions||' knowledge revisions failed or were flagged by AI validation. Review before they can mislead the agents.',
    jsonb_build_array(
      'The validator is right. It is itself a model, so a flag is a second opinion and not a verdict; correct knowledge is sometimes flagged and wrong knowledge sometimes passes.',
      'Flagged knowledge is not yet in use. If an agent retrieved it before the flag, the damage is already downstream of this task.'),
    'Reviewing '||coalesce(k.flagged_revisions,0)||' revision(s) stops the agents quoting something the validator already doubted. Wrong knowledge does not fail loudly — it produces a confident answer that is wrong.',
    'No spend. Reading time. The expensive direction is dismissing a flag in bulk to clear the queue.');

  perform kn_task('reg_coverage', rc.missing > 0, 'high', 'UAE codes not yet indexed as full documents',
    'Regulatory library is '||rc.coverage_pct||'% complete ('||rc.indexed||'/'||rc.free_codes||' free-published codes fully indexed; '||rc.critical_indexed||'/'||rc.critical_total||' critical). Still missing (critical first): '
    ||coalesce((select string_agg(authority||' — '||code_name, '; ') from (select authority,code_name from reg_catalog where copyright='free' and status<>'indexed' order by priority, authority limit 10) g),'none')
    ||'. Many are portal/viewer-gated or scanned — supply official full PDFs (or a licensed copy) to index them.',
    jsonb_build_array(
      'status=''indexed'' records that a document was INGESTED. It does not establish that an agent can retrieve it, that retrieval returns the right clause, or that the text survived extraction — so this coverage percentage measures ingestion and will be read as knowledge.',
      'reg_catalog is the right denominator: it is a hand-maintained list, so a code nobody has catalogued is not missing here, it is invisible here.',
      'The codes marked critical are the ones that actually decide a quote. That ordering is a judgement recorded in reg_catalog.priority, not a regulatory ranking.',
      'copyright=''free'' means lawfully indexable. Publishing a paid code would be a licensing breach, which is why the recommendation asks for a licensed copy rather than a scrape.'),
    'Indexing the missing '||rc.missing||' code(s) is what lets an agent answer a compliance question from the code itself instead of from a summary. '||rc.critical_indexed||' of '||rc.critical_total||' critical codes are in — the critical remainder is where a wrong answer costs a customer an inspection failure.',
    'The free codes cost nothing but fetching and indexing. Paid or portal-gated codes cost a licence, which is a founder decision — this rule asks for the document rather than assuming a budget.');

  -- NEW: per-agent knowledge staleness → one auto-closing task per lagging agent.
  v_gaps := fn_dispatch_agent_knowledge_gaps();

  for rec in select id::text as rid, title, authority from regulations where approved_at is null loop
    if not exists (select 1 from agent_actions where kind='knowledge_approval' and detail->>'ref'=rec.rid and detail->>'kind'='regulation' and status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
      values ('knowledge_curator','knowledge_approval','pending','high',
        'Approve regulation: '||coalesce(rec.title,'#'||rec.rid),
        'A new/updated high-stakes regulation ('||coalesce(rec.authority,'')||') is held with '||public.fn_action_holder('knowledge_approval','knowledge_curator')||' for approval before it publishes to the knowledge base.',
        jsonb_build_object('kind','regulation','ref',rec.rid,'authority',rec.authority),'regulations', rec.rid,
        jsonb_build_array(
          'The text was captured faithfully from '||coalesce(rec.authority,'the authority')||'. Nothing between capture and here has verified it against the authority''s own wording.',
          'Approval is a publishing decision, not a legal reading: it puts this text where agents will quote it to suppliers and customers.',
          'It stays unpublished until approved — approved_at null is the gate, so delay is safe and only approval is irreversible in effect.'),
        'Approving publishes this regulation to the knowledge base, where agents will quote it in briefs and compliance checklists. Until then it exists and reaches nobody.',
        'No spend. Founder reading time. The cost of approving something unverified is every quote issued against it afterwards.');
      n_appr := n_appr + 1;
    end if;
  end loop;

  select count(*) into n_task from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'reg_coverage',to_jsonb(rc),'open_items',n_task,'new_approvals',n_appr,'agent_gaps',v_gaps->'summary');
end $function$;
