// SPEC FILE #6, section 11 — the Optional Knowledge Modules.
//
//   Pricing (3) · Brand (4) · Standards (9) · Drawing (7) · Attachment Analysis (7) · FAQ (5)
//
// ── WHY THESE ARE SCORED ACROSS THE CORPUS, NOT INSIDE ONE TOPIC ─────────────────────────────────
// The eight mandatory domains each have a `topic` row of their own, so §3-§10 score each bullet
// inside its own domain and no other. The optional modules have no topic of their own — the spec
// never asked for one ("Some agents will also need these") — and the estate answers them from
// wherever the knowledge naturally sits: standards bodies appear in Technical Knowledge, brands in
// "Brands & Manufacturers", cost drivers in "Commercial & Pricing". Constraining these to a topic
// that the spec did not name would produce MISSINGs about a filing decision rather than about
// knowledge, so the population here is every row of the 84 mapped agents.
//
// This is a LOOSER population than §3-§10 use, and saying so is the point: the overlap-risk list in
// ROW6_REQUIREMENTS.md names `tech-standards` (§5, scored inside Technical Knowledge) against
// `opt-std-*` (§11, scored across the corpus) precisely so the two are not read as one fact
// measured twice. They are different claims: "this agent's technical module mentions standards" and
// "the corpus knows what ASHRAE is".
//
// ── BAR B THROUGHOUT, AND HERE IT IS NOT A CONCESSION ────────────────────────────────────────────
// The spec calls this whole section optional. A 21-of-84 bar on `opt-std-nfpa` is not a weakened
// check — NFPA is a fire-protection standard and the spec would be WRONG if a translation agency's
// agent cited it. The count prints, so a bullet that is genuinely universal (PDFs) and one that is
// correctly narrow (NFPA) are distinguishable at a glance rather than flattened into a verdict.

export const EXPECTED = 35;

// [id-suffix, SQL regex (POSIX, case-insensitive via ~*), human label]
const GROUPS = [
  ['Pricing Knowledge', 'opt-pricing', [
    ['factors', 'pricing factor|what drives (the )?price|price (is )?driven|affects? price|cost driver', 'pricing factors'],
    ['market-ranges', 'market rate|market range|benchmark|typical(ly)? (costs?|priced?)|aed ?[0-9]', 'market ranges'],
    ['cost-drivers', 'cost driver|labour cost|material cost|overhead|margin|mark.?up', 'cost drivers'],
  ]],
  ['Brand Knowledge', 'opt-brand', [
    ['major-manufacturers', 'manufacturer|\\bbrands?\\b|\\bmake\\b|\\boem\\b', 'major manufacturers'],
    ['local', 'local (brand|manufactur|suppl)|uae.?(made|based)|made in (the )?uae|regional brand', 'local brands'],
    ['international', 'international|european|german|italian|japanese|chinese|imported|\\bglobal\\b', 'international brands'],
    ['alternatives', 'alternative|equivalent|substitut|or equal|comparable', 'alternatives'],
  ]],
  ['Standards Knowledge', 'opt-std', [
    ['nfpa', '\\ynfpa\\y', 'NFPA'],
    ['iec', '\\yiec\\y', 'IEC'],
    ['ashrae', '\\yashrae\\y', 'ASHRAE'],
    ['astm', '\\yastm\\y', 'ASTM'],
    ['bs', '\\ybs ?(en ?)?[0-9]|\\ybritish standard', 'BS'],
    ['iso', '\\yiso ?[0-9]|\\yiso\\y', 'ISO'],
    ['en', '\\yen ?[0-9]', 'EN'],
    ['ul', '\\yul ?[0-9]|\\yul listed|underwriters lab', 'UL'],
    ['civil-defense', 'civil defen[cs]e|\\ydcd\\y|\\yadcd\\y', 'Civil Defense requirements'],
  ]],
  ['Drawing Knowledge', 'opt-draw', [
    ['cad', '\\ycad\\y|autocad|\\ydwg\\y|\\ydxf\\y', 'CAD Drawings'],
    ['bim', '\\ybim\\y|revit|\\yifc\\y|\\ylod ?[0-9]', 'BIM'],
    ['pdf', '\\ypdfs?\\y', 'PDFs'],
    ['plans', '\\yplans?\\y|layout|floor plan|site plan', 'Plans'],
    ['elevations', 'elevation', 'Elevations'],
    ['sections', '\\ysections?\\y|cross.?section|detail drawing', 'Sections'],
    ['mep', '\\ymep\\y|\\yhvac\\y|electrical drawing|plumbing drawing|services drawing', 'MEP drawings'],
  ]],
  ['Attachment Analysis', 'opt-att', [
    ['drawings', 'drawing', 'recognises drawings'],
    ['photos', 'photo|picture|image', 'recognises photos'],
    ['videos', 'video', 'recognises videos'],
    ['boq', '\\yboq\\y|bill of quantit', 'recognises BOQs'],
    ['pdf', '\\ypdfs?\\y', 'recognises PDFs'],
    ['excel', 'excel|spreadsheet|\\yxlsx?\\y|\\ycsv\\y', 'recognises Excel files'],
    // The spec's own sentence after that list: "and understand what information they contain".
    // Recognising a file type is a MIME check; knowing what it tells you is the requirement.
    ['understands-content', 'from the (drawing|boq|photo)|drawing shows|boq (gives|lists|shows)|extract|read (off|from) the|tells you|confirm from', 'understands what an attachment CONTAINS, not only its type'],
  ]],
  ['FAQ Knowledge', 'opt-faq', [
    ['difference', 'difference between|\\yvs\\y|versus|compared (to|with)|rather than', "\"What's the difference?\""],
    ['which-choose', 'which (one|type|option)|choose|selection|recommend(ed)? (for|when)|best (for|suited)', '"Which one should I choose?"'],
    ['how-long', 'how long|lead time|duration|takes? [0-9]|\\ydays?\\y|\\yweeks?\\y', '"How long does it take?"'],
    ['whats-included', 'included|excludes?|exclusion|scope covers|what you get|inclusive of', '"What\'s included?"'],
    ['maintenance', 'maintenance|servicing|\\yamc\\y|upkeep|clean(ing|ed) (every|annually)', '"Does it require maintenance?"'],
  ]],
];

export default async function (H) {
  const { req, one, B, Q, MAPPED, MAPPED_N, BAR_B } = H;

  for (const [group, prefix, bullets] of GROUPS) {
    for (const [suffix, rx, label] of bullets) {
      // The count is the verdict's own query rather than a pre-fetched literal: the whole-corpus
      // population is ~1.1 MB of content and pulling it through the management API to regex it in
      // JS would trade a small query for a large transfer 35 times over. The patterns here are
      // literal enough for POSIX — they are standards bodies and file extensions — so there is no
      // expressiveness lost by letting Postgres do the matching.
      const n = `(select count(distinct agent_key) from public.agent_knowledge
                  where ${MAPPED} and content ~* '${rx}')`;
      await req(`§11 optional`, `${prefix}-${suffix}`, `${group}: ${label}`,
        `select ${n} >= ${BAR_B}`,
        `select '${group.replace(/'/g, "''")} — ' || ${n}::text || ' of ${MAPPED_N} mapped agents ` +
        `mention it anywhere in agent_knowledge.content (bar B is ${BAR_B}); ' || ` +
        `case when ${n} >= ${MAPPED_N} then 'universal' when ${n} >= ${BAR_B} then 'pattern' else 'CORPUS GAP' end`);
    }
  }
}
