// SPEC FILE #6, sections 3-10 — the eight knowledge domains every category agent must implement.
//
//   §3 Industry Knowledge        (9)   §7  Quotation Knowledge     ⭐   (8)
//   §4 Products & Services      (13)   §8  Documents Knowledge         (16)
//   §5 Technical Knowledge      (10)   §9  UAE Regulations & Authorities (16)
//   §6 Supplier Knowledge        (9)   §10 Inquiry Qualification ⭐⭐⭐  (9)
//
// ── THE COLUMN, WHICH IS THIS ROW'S VERSION OF ROW #5's RPC HOP ──────────────────────────────────
// The opening brief states: "agent_knowledge.layer today holds company/profession/state/experience.
// NONE of the eight domains is a layer. So 'does agent X cover Technical Knowledge?' is currently
// unanswerable from the schema." The first sentence is true. The conclusion is false, and it is
// false in exactly the way row #5's seven false MISSINGs were false — the scan's population
// excluded the column where the fact lived.
//
// The eight domains are `agent_knowledge.topic` values, spelled EXACTLY as the spec spells them:
//
//   Industry Knowledge · Products & Services · Technical Knowledge · Supplier Knowledge
//   Quotation Knowledge · Documents Knowledge · UAE Regulations & Authorities
//   Inquiry Qualification Logic
//
// measured on production 2026-08-09 at 87 rows each across the corpus and 84/84 across the mapped
// categories. A scorer that read `layer` would have reported all eight MISSING on all 84 agents and
// issued a build order to regenerate 672 rows that already exist and are individually unique. That
// build order would have overwritten real knowledge with generated text — the single worst outcome
// the brief names. So this module reads `topic`, says so in every evidence string, and prints the
// layer distribution once at the top so the two columns can never be confused again.
//
// ── AND THE AVERAGE, WHICH IS THE OTHER HALF OF THE SAME MISTAKE ─────────────────────────────────
// "1,584 rows across 132 agents is 12 each, and 12 rows cannot cover 8 domains." The arithmetic is
// right and the conclusion does not follow, because the 132 is not one population. It is 87 agents
// on the 15-module standard, 31 on a legacy 7-8 topic scheme, and 14 stubs holding 1-3 rows. The
// mean of those three is a number describing none of them. Every check here scores the 84 MAPPED
// agents — the spec's own list — and reports a per-agent count, never a mean.
//
// ── THE TWO BARS ─────────────────────────────────────────────────────────────────────────────────
// BAR A, the eight `*-coverage` checks: 84 of 84. "Every AI Agent Needs These Knowledge Domains" is
//   a universal claim and gets a universal check. One agent short is MISSING.
// BAR B, every sub-bullet: 21 of 84. The spec introduces every sub-list with the word "Example:" —
//   these illustrate a domain, they do not mandate it. A BOQ is irrelevant to a translation agency;
//   requiring `doc-boq` on all 84 would manufacture a false MISSING and then a build order to
//   fabricate BOQ knowledge for translators. The exact agent count prints either way.
//
// ── EACH SUB-BULLET IS SCORED INSIDE ITS OWN DOMAIN'S CONTENT ────────────────────────────────────
// Not across the corpus. `tech-materials` (§5) and `prod-materials` (§4) are the same word in two
// domains, and `quo-mandatory-info` (§7) and `iql-mandatory-info` (§10) are the same phrase in two
// more. Scoring either across the whole corpus would let one paragraph satisfy both — the exact
// double-count row #5's overlap-risk list was written to prevent. The content is fetched per topic
// and a bullet only ever sees the rows of the domain it belongs to.

export const EXPECTED = 90;

// [spec topic string, section label, id prefix, [[id-suffix, regex, human label], ...]]
const DOMAINS = [
  ['Industry Knowledge', '§3 industry', 'ind', [
    ['overview', /overview|landscape|sector\b|market structure|the industry/i, 'industry overview'],
    ['scope-of-work', /scope\b|\bsow\b|remit|covers?\b|deliverab/i, 'scope of work'],
    ['terminology', /terminolog|jargon|known as|called|referred to as|\bterm(s|ed)?\b/i, 'common terminology'],
    ['market-segments', /segment|residential|commercial|industrial|hospitality|retail|tier/i, 'market segments'],
    ['uae-practices', /\buae\b|dubai|abu dhabi|sharjah|emirat|gcc\b/i, 'local UAE practices'],
    ['supplier-ecosystem', /supplier|vendor|subcontractor|trader|distribut|manufactur/i, 'supplier ecosystem'],
    ['customer-types', /customer|client|contractor|consultant|developer|owner|end.?user/i, 'customer types'],
    ['workflows', /workflow|process|sequence|stage|typical|lead time|from .{0,25} to /i, 'typical workflows'],
  ]],
  ['Products & Services', '§4 products', 'prod', [
    ['categories', /categor|range|famil|types? of|classes?\b/i, 'product categories'],
    ['hierarchy', /hierarch|sub.?categor|breaks? down|grouped|tier|sub.?type/i, 'product hierarchy'],
    ['materials', /material|steel|alumini|glass|timber|\bpvc\b|concrete|fabric|grade/i, 'materials'],
    ['models', /model|series|part number|\bsku\b|range\b/i, 'models'],
    ['variants', /variant|option|configur|version|finish/i, 'variants'],
    ['sizes', /\bsizes?\b|\bmm\b|diameter|dimension|width|thickness|\bkw\b|\bton|capacity/i, 'sizes'],
    ['specifications', /spec(ification)?|rating|performance|standard/i, 'specifications'],
    ['accessories', /accessor|fitting|fixing|ancillar|consumable|spare/i, 'accessories'],
    ['services-offered', /service/i, 'services offered'],
    ['installation', /install|erect|fit.?out|commission/i, 'installation services'],
    ['maintenance', /maintenance|servicing|\bamc\b|preventive|repair/i, 'maintenance services'],
    ['warranties', /warrant|guarantee|defect.{0,20}liab|\bdlp\b/i, 'warranties'],
  ]],
  ['Technical Knowledge', '§5 technical', 'tech', [
    ['materials', /material|grade|alloy|composition|substrate/i, 'materials'],
    ['components', /component|\bparts?\b|assembl|element|module|unit/i, 'components'],
    ['performance', /performance|efficien|output|rating|capacity|\bcop\b|\beer\b|\bu.?value\b/i, 'performance'],
    ['standards', /standard|\biso\b|\bbs\b|\ben\s?\d|astm|nfpa|\biec\b|ashrae|\bul\b|\bcode\b/i, 'standards'],
    ['compatibility', /compatib|interfac|suit(able|ed)|works? with|integrat|match/i, 'compatibility'],
    ['installation-methods', /install|fixing|mount|method|erect|laying|jointing/i, 'installation methods'],
    ['design-considerations', /design|consider|allowance|calculat|sizing|selection|specify/i, 'design considerations'],
    ['limitations', /limit|constraint|cannot|not suitable|maximum|minimum|restrict/i, 'limitations'],
    ['common-problems', /problem|fail(ure)?|defect|issue|fault|crack|leak|corros|mistake/i, 'common problems'],
  ]],
  ['Supplier Knowledge', '§6 supplier', 'sup', [
    ['types', /types?\b|categor|kinds? of|fall into|split/i, 'supplier types'],
    ['manufacturers', /manufactur|factory|producer|\bmill\b|fabricat/i, 'manufacturers'],
    ['distributors', /distribut|dealer|stockist|wholesal|reseller/i, 'distributors'],
    ['importers', /import|trader|sourcing|\bagent\b/i, 'importers'],
    ['contractors', /contractor/i, 'contractors'],
    ['installers', /install|applicator|fitter/i, 'installers'],
    ['maintenance-companies', /maintenance|\bamc\b|servicing|after.?sales/i, 'maintenance companies'],
    ['service-providers', /service provider|consultan|specialist|provider|firm/i, 'service providers'],
  ]],
  ['Quotation Knowledge', '§7 quotation', 'quo', [
    ['mandatory-info', /mandator|must|required|essential|always ask|need to know/i, 'mandatory information'],
    ['optional-info', /optional|nice to have|skippable|if available|helpful|useful but/i, 'optional information'],
    ['affects-price', /price|cost|rate|\baed\b|budget|premium/i, 'what affects price'],
    ['affects-delivery', /deliver|lead time|schedul|timeline|turnaround|\beta\b/i, 'what affects delivery'],
    ['affects-installation', /install|site|access|fixing|erection|mobilis|mobiliz/i, 'what affects installation'],
    ['rejection-causes', /reject|decline|refus|will not quote|no.?quote|walk away|pass on|drop out/i, 'what causes suppliers to reject quotations'],
    ['required-documents', /document|drawing|\bboq\b|licen[cs]e|datasheet|submittal|attach|\brfq\b/i, 'what documents are required'],
  ]],
  ['Documents Knowledge', '§8 documents', 'doc', [
    ['boq', /\bboq\b|bill of quantit/i, 'BOQ'],
    ['shop-drawings', /shop drawing/i, 'Shop Drawings'],
    ['ifc-drawings', /\bifc\b|issued for construction/i, 'IFC Drawings'],
    ['as-built', /as.?built/i, 'As Built Drawings'],
    ['datasheets', /datasheet|data sheet|technical data/i, 'Datasheets'],
    ['material-submittals', /submittal|material approval|\bmar\b|material submission/i, 'Material Submittals'],
    ['rfq', /\brfq\b|request for quot/i, 'RFQs'],
    ['rfi', /\brfi\b|request for information/i, 'RFIs'],
    ['method-statements', /method statement|\bmos\b|\brams\b/i, 'Method Statements'],
    ['technical-specs', /technical spec|specification/i, 'Technical Specifications'],
    ['photos', /photo|picture|image/i, 'Photos'],
    ['site-videos', /video/i, 'Site Videos'],
    ['purchase-orders', /purchase order|\blpo\b|\bpo\b/i, 'Purchase Orders'],
    ['contracts', /contract|agreement|\bsla\b|subcontract/i, 'Contracts'],
    // Not a fifteenth document — the spec's own sentence after the list: "The AI should know WHEN
    // each document is needed." A list of names without a stage is a glossary, not knowledge.
    ['when-needed', /\bwhen\b|before|prior to|during|after|at (tender|award|submittal|handover)|stage/i,
      'knows WHEN each document is needed, not only its name'],
  ]],
  ['UAE Regulations & Authorities', '§9 uae', 'uae', [
    ['municipality', /municipalit/i, 'Municipality requirements'],
    ['civil-defense', /civil defen[cs]e|\bdcd\b|\badcd\b/i, 'Civil Defense'],
    ['dewa', /\bdewa\b/i, 'DEWA'],
    ['addc', /\baddc\b/i, 'ADDC'],
    ['etihad-we', /etihad water|\bewec?\b|\bfewa\b|etihad we/i, 'Etihad Water & Electricity'],
    ['trakhees', /trakhees/i, 'Trakhees'],
    ['dda', /\bdda\b|dubai development author/i, 'DDA'],
    ['rta', /\brta\b|roads and transport/i, 'RTA'],
    ['dm', /\bdm\b|dubai municipalit/i, 'DM'],
    ['dubai-municipality', /dubai municipalit/i, 'Dubai Municipality'],
    ['abudhabi-municipality', /abu dhabi municipalit|\badm\b|\bdmt\b/i, 'Abu Dhabi Municipality'],
    ['local-standards', /standard|\bgso\b|emirates standard|\buae\.?s\b|\bes\s?\d/i, 'local standards'],
    ['regulations', /regulat|\blaw\b|decree|\bcode\b|circular|bylaw/i, 'UAE regulations'],
    ['local-approvals', /approval|permit|\bnoc\b|licen[cs]e|authoris|authoriz|inspection/i, 'local approvals'],
    ['local-terminology', /known as|locally|called|referred|\bterm\b|in the uae/i, 'local terminology'],
  ]],
  ['Inquiry Qualification Logic', '§10 inquiry-qual', 'iql', [
    ['question-order', /ask in order|\bfirst\b|then\b|\b1\b|step|sequence|start (with|by)/i, 'which questions to ask first'],
    ['dependent-questions', /\bif\b|depend|only if|conditional|branch|when .{0,25}then/i, 'which questions depend on previous answers'],
    ['mandatory-info', /mandator|must\b|required/i, 'which information is mandatory'],
    ['skippable-info', /skip|optional|omit|not essential|nice to have|can be left/i, 'which information can be skipped'],
    ['enough-collected', /enough|sufficient|complete|ready to (fan|quote|route|send)|proceed when|once you have/i, 'when enough information has been collected'],
    ['confidence-score', /confidence|score|certaint/i, 'confidence score'],
    ['missing-info', /missing|absent|not provided|not given|\bgap\b|unknown|unclear/i, 'missing information'],
    ['validation-rules', /valid|\brules?\b|check|must be|reject if|verify|flag/i, 'validation rules'],
  ]],
];

export default async function (H) {
  const { req, many, one, B, Q, MAPPED, MAPPED_N, BAR_B } = H;

  // Printed once, not scored: the two columns that the brief's diagnosis confused. Anyone reading a
  // verdict below can see at a glance that `layer` is an orthogonal axis and `topic` is the domain.
  const layers = await many(`select layer, count(*)::text as rows from public.agent_knowledge
    where ${MAPPED} group by layer order by count(*) desc`);
  const topicN = await one(`select count(distinct topic)::text from public.agent_knowledge where ${MAPPED}`);
  console.log(`         COLUMN NOTE: over the ${MAPPED_N} mapped agents, agent_knowledge.layer holds ` +
    `[${layers.map(l => `${l.layer}:${l.rows}`).join(' ')}] and carries NO domain; ` +
    `agent_knowledge.topic holds ${topicN} distinct values and IS the domain axis. ` +
    `Every verdict below reads topic + content.`);

  for (const [topic, section, prefix, bullets] of DOMAINS) {
    // One fetch per domain. Every bullet in this domain is scored against these rows and no others,
    // so `tech-materials` cannot be satisfied by a Products & Services paragraph.
    const rows = await many(`select agent_key, content from public.agent_knowledge
      where ${MAPPED} and topic = '${topic.replace(/'/g, "''")}'`);
    const agents = new Set(rows.map(r => r.agent_key));
    const lens = rows.map(r => (r.content || '').length);
    const distinct = new Set(rows.map(r => r.content)).size;

    // ── BAR A ────────────────────────────────────────────────────────────────────────────────────
    // The universal check. Also prints distinct-content, because 84 agents all carrying an
    // identically-worded module would be a template, not eighty-four agents' knowledge — and that
    // is a MET this scorer should be able to refute.
    await req(section, `${prefix}-coverage`, `all ${MAPPED_N} mapped agents carry a ${topic} module`,
      B(agents.size >= MAPPED_N),
      Q(`agent_knowledge.topic='${topic}': ${agents.size} of ${MAPPED_N} mapped agents, ` +
        `${rows.length} row(s), content length min/avg/max ` +
        `${Math.min(...lens, 0)}/${Math.round(lens.reduce((a, b) => a + b, 0) / (lens.length || 1))}/${Math.max(...lens, 0)}, ` +
        `${distinct} distinct body/bodies` +
        (distinct < agents.size ? ` — !! ${agents.size - distinct} agent(s) share a body, that is a template` : ' — every body unique')));

    // ── BAR B ────────────────────────────────────────────────────────────────────────────────────
    for (const [suffix, re, label] of bullets) {
      const hits = new Set(rows.filter(r => re.test(r.content || '')).map(r => r.agent_key));
      await req(section, `${prefix}-${suffix}`, label,
        B(hits.size >= BAR_B),
        Q(`"${label}" in topic='${topic}'.content on ${hits.size} of ${MAPPED_N} agents ` +
          `(bar B is ${BAR_B}); ${hits.size >= MAPPED_N ? 'universal' : hits.size >= BAR_B ? 'pattern' : 'CORPUS GAP'}`));
    }
  }
}
