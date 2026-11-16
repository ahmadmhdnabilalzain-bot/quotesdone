// SPEC FILE #6, section 12 — the agent mechanism.
//
// The spec's closing line is "Each agent should implement the same modules". That is a claim about
// a SYSTEM, not about a corpus: knowledge nobody can reach is not knowledge the platform has. These
// eight checks are the mechanism the sentence implies.
//
// ── WHAT A CATEGORY AGENT *IS*, DECIDED HERE AND NOT LEFT AMBIGUOUS ──────────────────────────────
// The opening brief asks the question and says both halves of the codebase assume different answers.
// Measured on production 2026-08-09, they do not — one half is 16 routines and the other is 1:
//
//   category_agents            132 rows (110 active), slug/name/persona/emoji/agent_class.
//                              84 of them are exactly the spec's realistic categories. THE REGISTRY.
//   agent_knowledge 'cat:…'    132 namespaces, 1,584 rows. THE KNOWLEDGE.
//   org_agents                  67 rows, 0 prefixed 'cat:'. Departments (it, sales, finance, hr…),
//                              manager_key chains, seniority, max_open_tasks, hired_at.
//                              THE INTERNAL COMPANY ORG CHART. A different object entirely.
//
//   16 routines resolve a category agent through 'cat:' + agent_knowledge / category_agents:
//     fn_resolve_cat_agent, fn_category_knowledge, fn_category_expert_ref, fn_category_sales,
//     fn_category_knowledge_promote, fn_knowledge_gaps, fn_decide, fn_ws_agents, fn_ws_knowledge,
//     fn_ws_governance, fn_kb_reconcile, fn_regulation_propagate, fn_agent_institutional_memory,
//     fn_execution_run, fn_enqueue_doc_backups, kb_match
//   1 routine assumes org_agents: fn_graph_rebuild — and it is the one producing zero rows.
//
// THE ANSWER: a category agent is a row in `category_agents` plus a namespace in `agent_knowledge`.
// It is NOT an org_agents row. org_agents is a 67-person org chart with manager chains and
// goal-accountability edges; inserting 84 category agents into it would put 84 synthetic employees
// into every department rollup, every manager chain and every employee->goal edge in the graph, to
// satisfy one join. The 84:84 join that already works is category_agent_map.agent_slug ->
// category_agents.slug, and it works because BOTH sides are bare.
//
// ── WHICH MAKES THE BRIEF'S NAMED DEFECT A MISDIAGNOSIS, AND THE PROPOSED FIX A REGRESSION ───────
// The brief says "category_agent_map.agent_slug is missing the 'cat:' prefix, so all 84 rows resolve
// to nothing". Measured:
//
//   category_agent_map rows                                84
//   … joining org_agents.agent_key on the bare slug         0
//   … joining org_agents.agent_key on 'cat:'||slug          0    <- prefixing fixes NOTHING here
//   … joining category_agents.slug on the bare slug        84    <- already resolves, all of them
//   … matching agent_knowledge on 'cat:'||slug             84    <- already resolves, all of them
//
// The column is CORRECT. Writing 'cat:' into it would break the 84/84 join to category_agents and
// still not satisfy fn_graph_rebuild, because that edge's problem is the TABLE it looks in, not the
// string it looks for. The defect is one `exists` clause in fn_graph_rebuild pointed at org_agents.
// `mech-graph-edge` below is the check that holds it, and it is scored on the edge's OUTPUT — rows
// in graph_edges — never on the function's text, so a repointed clause that still produces nothing
// cannot pass it.

export const EXPECTED = 8;

export default async function (H) {
  const { req, one, B, Q, MAPPED, MAPPED_N } = H;

  // 1 — every one of the spec's realistic categories has an agent behind it.
  const withAgent = await one(`select count(*)::text from public.category_agent_map m
    where exists (select 1 from public.agent_knowledge k where k.agent_key='cat:'||m.agent_slug)`);
  const catalogued = await one(`select count(*)::text from public.catalog_supplier_categories`);
  const unmapped = await one(`select coalesce(string_agg(c.slug, ' '), 'none') from public.catalog_supplier_categories c
    where not exists (select 1 from public.category_agent_map m where m.catalog_slug=c.slug)`);
  await req('§12 mechanism', 'mech-agent-per-category', `every one of the ${MAPPED_N} realistic categories has an agent`,
    B(Number(withAgent) >= MAPPED_N),
    Q(`${withAgent} of ${MAPPED_N} mapped categories reach agent_knowledge via 'cat:'||agent_slug; ` +
      `catalogue holds ${catalogued} categories, the ${Number(catalogued) - MAPPED_N} beyond the spec's list ` +
      `carry no agent [${unmapped}]`));

  // 2 — the agent is a REGISTERED OBJECT, not a bare string that happens to key some rows. A
  //     knowledge namespace with no registry row is undiscoverable: nothing can enumerate it.
  const regRows = await one(`select count(*)::text from public.category_agents`);
  const regJoin = await one(`select count(*)::text from public.category_agent_map m
    join public.category_agents a on a.slug=m.agent_slug`);
  const orgJoin = await one(`select count(*)::text from public.category_agent_map m
    join public.org_agents a on a.agent_key=m.agent_slug`);
  await req('§12 mechanism', 'mech-agent-registry-row', 'the agent is a registered object, not only a bare knowledge key',
    B(Number(regJoin) >= MAPPED_N),
    Q(`category_agents holds ${regRows} row(s); ${regJoin} of ${MAPPED_N} map rows join it on the BARE slug ` +
      `(org_agents joins ${orgJoin}) — the registry is category_agents, org_agents is the internal org chart`));

  // 3 — a routine turns a catalogue slug into its agent. Scored by EXECUTION, not by existence:
  //     row #5's lesson is that a function that exists and returns null has not been measured.
  const fnResolve = await one(`select exists (select 1 from pg_proc p join pg_namespace ns
    on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='fn_resolve_cat_agent')::text`);
  const resolved = fnResolve === 'true'
    ? await one(`select count(*)::text from public.category_agent_map m
        where public.fn_resolve_cat_agent(m.catalog_slug) is not null`)
    : '0';
  await req('§12 mechanism', 'mech-resolve-by-slug', 'a routine resolves a catalogue slug to its agent',
    B(fnResolve === 'true' && Number(resolved) >= MAPPED_N),
    Q(`fn_resolve_cat_agent present ${fnResolve}; EXECUTED over all ${MAPPED_N} mapped slugs -> ` +
      `${resolved} resolved, ${MAPPED_N - Number(resolved)} returned null`));

  // 4 — and it accepts the vocabulary the LIVE INTAKE actually speaks. The catalogue slugs are not
  //     what arrives at runtime: category_specs keys 56 legacy trade slugs (hvac, tiling, plumbing)
  //     whose overlap with the 86 catalogue slugs is exactly zero. An agent reachable only by a
  //     vocabulary nothing sends is an agent nothing reaches.
  const legacyResolved = await one(`select count(*)::text from public.category_specs s
    where public.fn_resolve_cat_agent(s.category) is not null`);
  const legacyTotal = await one(`select count(*)::text from public.category_specs`);
  const overlap = await one(`select count(*)::text from public.category_specs s
    join public.catalog_supplier_categories c on c.slug=s.category`);
  await req('§12 mechanism', 'mech-resolve-legacy-vocab', 'resolution accepts the live intake vocabulary, not only catalogue slugs',
    B(Number(legacyResolved) > Number(legacyTotal) * 0.8),
    Q(`${legacyResolved} of ${legacyTotal} category_specs trade slugs resolve to an agent; ` +
      `those slugs overlap the ${MAPPED_N}-category catalogue on ${overlap} row(s) — ` +
      `two vocabularies, so resolution must bridge them`));

  // 5 — ONE call returns an agent's knowledge. Not "the rows exist and a caller can assemble them".
  const fnKnow = await one(`select exists (select 1 from pg_proc p join pg_namespace ns
    on ns.oid=p.pronamespace where ns.nspname='public' and p.proname='fn_category_knowledge')::text`);
  const answered = fnKnow === 'true'
    ? await one(`select count(*)::text from public.category_agent_map m
        where (select count(*) from public.fn_category_knowledge(m.catalog_slug)) > 0`)
    : '0';
  await req('§12 mechanism', 'mech-knowledge-one-call', "one routine returns an agent's modules",
    B(fnKnow === 'true' && Number(answered) >= MAPPED_N),
    Q(`fn_category_knowledge present ${fnKnow}; EXECUTED over all ${MAPPED_N} mapped slugs -> ` +
      `${answered} returned at least one module`));

  // 6 — and that ONE call returns ALL EIGHT mandatory modules together. Eight separate reachable
  //     rows are not the same claim as one payload an agent can be handed.
  const EIGHT = ['Industry Knowledge', 'Products & Services', 'Technical Knowledge', 'Supplier Knowledge',
    'Quotation Knowledge', 'Documents Knowledge', 'UAE Regulations & Authorities', 'Inquiry Qualification Logic'];
  const allEight = await one(`select count(*)::text from public.category_agent_map m
    where (select count(distinct topic) from public.fn_category_knowledge(m.catalog_slug)
            where topic in (${EIGHT.map(t => `'${t.replace(/'/g, "''")}'`).join(',')})) = 8`);
  await req('§12 mechanism', 'mech-modules-together', 'that call returns all eight mandatory modules in one payload',
    B(Number(allEight) >= MAPPED_N),
    Q(`fn_category_knowledge returns all 8 spec topics for ${allEight} of ${MAPPED_N} mapped categories ` +
      `(topics matched by name: ${EIGHT.join(' | ')})`));

  // 7 — the knowledge is PER CATEGORY. A template with the category name swapped in would satisfy
  //     every check above and be worth nothing: the spec's whole premise is that "this knowledge is
  //     different for every supplier category". Refutable form: distinct content bodies per topic.
  const dupTopics = await one(`select coalesce(string_agg(topic || ' ' || dup::text, ', '), 'none') from (
      select topic, count(*) - count(distinct content) as dup
        from public.agent_knowledge where ${MAPPED}
         and topic in (${EIGHT.map(t => `'${t.replace(/'/g, "''")}'`).join(',')})
       group by topic having count(*) - count(distinct content) > 0) t`);
  const totalDomainRows = await one(`select count(*)::text from public.agent_knowledge where ${MAPPED}
    and topic in (${EIGHT.map(t => `'${t.replace(/'/g, "''")}'`).join(',')})`);
  const distinctDomainRows = await one(`select count(distinct content)::text from public.agent_knowledge where ${MAPPED}
    and topic in (${EIGHT.map(t => `'${t.replace(/'/g, "''")}'`).join(',')})`);
  await req('§12 mechanism', 'mech-per-category-not-generic', 'the content differs per category — not one template with the name swapped',
    B(Number(totalDomainRows) > 0 && totalDomainRows === distinctDomainRows),
    Q(`${totalDomainRows} domain row(s) across the ${MAPPED_N} mapped agents, ${distinctDomainRows} distinct ` +
      `content bod(ies); topics with a repeated body: ${dupTopics}`));

  // 8 — the relationship is IN THE GRAPH. Scored on the edge's OUTPUT, never on fn_graph_rebuild's
  //     text: an edge whose SQL is repointed but still selects nothing has not been fixed, and a
  //     check that read the function body could not tell the two apart.
  const edges = await one(`select count(*)::text from public.graph_edges
    where src_kind='category' and rel='served_by'`);
  const catEdgesAny = await one(`select coalesce(string_agg(rel || '->' || dst_kind || ' ' || n::text, ', '), 'none') from (
      select rel, dst_kind, count(*) as n from public.graph_edges where src_kind='category'
       group by rel, dst_kind) t`);
  await req('§12 mechanism', 'mech-graph-edge', 'the category -> agent relationship is present in the knowledge graph',
    B(Number(edges) >= MAPPED_N),
    Q(`graph_edges src_kind='category' rel='served_by': ${edges} row(s), need ${MAPPED_N}; ` +
      `all category edges present: [${catEdgesAny}]`));
}
