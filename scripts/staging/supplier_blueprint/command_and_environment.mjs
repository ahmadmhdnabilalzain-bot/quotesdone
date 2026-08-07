// SPEC FILE #5, sections 4-6 — Command Center, 3D Supplier Environment, Supplier Profile Page.
//
//   4. Supplier Command Center UI (10) — the home screen, and the spec insists it is NOT a dashboard
//   5. 3D Supplier Environment    (12) — a factory scene whose objects open real inventory
//   6. Supplier Profile Page       (9) — a LIVING intelligence page, not a static company record
//
// ── EVERY LEG IS PER-FILE OR PER-FUNCTION, AND THE EVIDENCE NAMES WHAT SATISFIED IT ──────────────
// Row #5's refutation round 1 removed seven false METs from module 1 and three of the five defects
// were one error: a scan whose population was an artefact of the scan (fourteen edge functions
// joined end to end; a window straddling that join; the marketing chat bubble inside the route's
// closure). Helpers come from ../supplier_checks.mjs so that error is not available to write here.
// An unnamed "endpoint yes" cannot be refuted; a named one can, so every evidence string prints the
// file or function that carried the verdict.
//
// ── THE OVERLAP THIS MODULE MUST NOT CAUSE ───────────────────────────────────────────────────────
// docs/sessions/ROW5_REQUIREMENTS.md logs four pairs that risk one implementation scoring twice.
// Two are this module's responsibility:
//   · env-3d-scene (§5) vs map-globe (§19) vs ui-3d-maps (§22) vs tech-threejs (§23). ONE <Canvas>
//     must not satisfy all four. §5 is specifically a COMPANY ENVIRONMENT — a factory with a
//     production line, inventory, orders and customers — so the scene leg requires 3D machinery AND
//     a company-environment subject. A globe alone cannot pass it, and neither can a bare import.
//   · cc-perf-response / cc-perf-quality (§4) vs the §13 health panel. §4 draws two SUMMARY TILES on
//     the command center; §13 draws five bars in a health panel. Scored on different components, and
//     the §4 legs require the value on the command-center screen rather than anywhere on the surface.
//
// ── THE EMPTY-ESTATE RULE ────────────────────────────────────────────────────────────────────────
// §5's inventory legs sit on inv_items / inv_stock_moves, which hold 0 rows on production. A row
// count is therefore NEVER the verdict — the verdict is whether a reader and a supplier-facing
// surface exist. The row count is printed beside it so a MISSING can never be mistaken for an
// artefact of the empty estate, and so a future run with real stock reads the same verdict.
import {
  S, P, FILES, FNS, fileSrc, fnSrc, n, has, filesMatching, fnsMatching, fnsWithBoth,
  delivered, cover, B, Q, READERS_SQL, NROWS_SQL, rpcSources,
} from '../supplier_checks.mjs';

export const EXPECTED = 31;

export default async function (H) {
  const { req, one } = H;
  const SEC4 = 'cc', SEC5 = 'env', SEC6 = 'prof';

  // The serving population follows the rpc hop — the same false MISSING found in §13, §7 and §15.
  const RPC = await rpcSources(one);
  const servedBy = (re) => [...fnsMatching(re), ...RPC.filter(([, src]) => re.test(src)).map(([nm]) => nm)];

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §4 — SUPPLIER COMMAND CENTER UI (10)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  // The command center is the supplier's HOME screen. Legs are scored over P (the portal without the
  // marketing chrome), because a company name in a cookie banner is not a command-center header.
  const hdr = filesMatching(/company[_ ]?name|companyName/i);
  await req(SEC4, 'cc-company-header', 'the supplier company name heads the screen',
    B(delivered(/company[_ ]?name|companyName/i)),
    Q(`rendered ${delivered(/company[_ ]?name|companyName/i) ? 'yes' : 'NO'}; named in [${hdr.map(f => f.split('/').pop()).join(' ') || 'no file'}]`));

  // NOT /verified/i. That read MET on 13 matches and every one of them was the phone-verification
  // flow in a settings form — `mobile_verified`, `phone_verified`, "Required to get verified".
  // A supplier having confirmed their mobile number is not the platform certifying them as a
  // Verified Supplier; they are different claims about different subjects. The account-verification
  // vocabulary is excluded by name and both counts are printed, so the exclusion is auditable.
  const VERIF_BADGE = /verified[_ ]?supplier|supplier[_ ]?verified|approval_status|\bapproved\b/i;
  const ACCOUNT_VERIF = /(mobile|phone|email|owner|sms)[_ ]?verified|verify[_ ]?my/i;
  const badgeShown = delivered(VERIF_BADGE);
  await req(SEC4, 'cc-verified-badge', 'a "Verified Supplier" badge',
    B(badgeShown),
    Q(`supplier-badge token(s) ${n(VERIF_BADGE)}, rendered ${badgeShown ? 'yes' : 'NO'}; ` +
      `${n(ACCOUNT_VERIF)} account-verification token(s) excluded — a confirmed mobile is not a Verified Supplier`));

  // A star RATING, not the word rating: the spec draws five stars. Either a star glyph/icon or an
  // explicit rating value rendered as stars.
  const stars = n(/★|⭐|StarIcon|<Star\b|rating[_ ]?stars|renderStars/i);
  await req(SEC4, 'cc-star-rating', 'a star rating',
    B(stars > 0), Q(`${stars} star-rendering token(s) on the supplier portal`));

  // §4's headline number. supplier_score holds it for all 20,464 companies — so a MISSING here is
  // "computed and never shown", never "no data". The row count is printed to make that unambiguous.
  const scoreRows = await one(NROWS_SQL('supplier_score'));
  const scoreShown = delivered(/intelligence[_ ]?score|supplier[_ ]?score|overall[_ ]?score/i);
  const scoreServed = servedBy(/supplier_score|intelligence[_ ]?score/i);
  await req(SEC4, 'cc-intelligence-score', 'a Supplier Intelligence Score on the command center',
    B(scoreShown && scoreServed.length > 0),
    Q(`rendered ${scoreShown ? 'yes' : 'NO'}, served by [${scoreServed.join(' ') || 'NO fn'}]; ` +
      `${scoreRows} supplier_score row(s) exist, so a MISSING is not an empty estate`));

  const oppShown = delivered(/new[_ ]?rfq|open[_ ]?rfq|opportunit|inbox[_ ]?count/i);
  const oppServed = fnsMatching(/inbox|opportunit|rfq/i, ['supplier_api', 'supplier_portal']);
  await req(SEC4, 'cc-opportunities-count', 'a new-RFQ opportunity count tile',
    B(oppShown && oppServed.length > 0),
    Q(`rendered ${oppShown ? 'yes' : 'NO'}, served by [${oppServed.join(' ') || 'NO fn'}]`));

  // §4's two performance TILES. Kept apart from §13's health panel by requiring the value to be
  // rendered on the portal AND served by the supplier's own overview endpoint — §13 will score the
  // five-bar panel as a distinct component, so neither can satisfy the other by coincidence.
  //
  // A TILE IS A VALUE, NOT A SENTENCE. `/\bquality\b/i` scored a render leg on the prose "it has
  // not reached the quality mark" — which would have flipped to a false MET the moment an endpoint
  // existed, so it is a latent defect even while the check reads MISSING. The metric legs now
  // require an identifier-shaped name (`response_rate`, `quality_score`), never a bare English word,
  // and the endpoint leg searches ALL reachable functions so the evidence names the real server
  // instead of reporting NO fn because the guess-list was too short.
  for (const [id, re, label] of [
    ['cc-perf-response', /response[_ ]?(rate|pct|percent|score)|responsiveness/i, 'Response %'],
    ['cc-perf-quality', /quality[_ ]?(rate|pct|percent|score|mark)|score[_ ]?quality/i, 'Quality %'],
  ]) {
    const shown = delivered(re);
    const served = servedBy(re);
    await req(SEC4, id, `a ${label} tile on the command center`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}] ` +
        `(identifier-shaped only — prose mentioning the word is not a tile)`));
  }

  // The assistant panel, scored over P so the MARKETING chat bubble cannot certify it. Module 1 lost
  // onb-ai-conversation to exactly that: ChatWidget.tsx supplies 5 role:'user' tokens and the portal
  // supplies 0. Both numbers are printed so the difference is visible in the evidence.
  //
  // ── THE CHROME FENCE IS FILE-LEVEL AND THIS LEAK IS INTRA-FILE ────────────────────────────────
  // Excluding ChatWidget.tsx was not enough. All six matches here were the SUPPORT CHAT living
  // inside SupplierPortal.tsx itself — "Our assistant handles most questions instantly",
  // "Ask / request a chat", `assistant_pre: 'Assistant: '`. A box the supplier types a question
  // into is a help desk. §4's assistant is the opposite direction of travel: it tells the supplier,
  // unprompted, what to fix. So the support-chat vocabulary is subtracted from the count, and the
  // leg requires PROACTIVE guidance rather than a Q&A affordance.
  const SUPPORT_CHAT = /ask[_ ]?(a )?question|ask[_ ]?placeholder|ask[_ ]?request|request[_ ]?(a )?chat|assistant_pre|answers instantly|handles most questions/i;
  const PROACTIVE = /(your|this) (profile|company|account)[^.;]{0,60}(can|could|would|missing|needs)|upload[^.;]{0,40}(to|and) (qualify|unlock|reach)|you (are|re) missing|improve your/i;
  const supportTok = n(SUPPORT_CHAT, P);
  const proactiveTok = n(PROACTIVE, P);
  await req(SEC4, 'cc-assistant-panel', 'an AI Assistant panel on the command center',
    B(proactiveTok > 0),
    Q(`${proactiveTok} proactive-guidance token(s); ${supportTok} support-chat token(s) excluded ` +
      `— a box the supplier asks questions into is a help desk, not §4's assistant`));

  // The spec's example advice names a concrete gap AND quantifies the upside ("qualify for 32 more
  // projects if you upload 3 missing certificates"). Advice that says "improve your profile" is not
  // this requirement, so both legs are required: something missing, and a number attached to fixing it.
  const gap = has(/missing|incomplete|not[_ ]?uploaded|expired/i, P);
  const upside = has(/\bmore\b[^.;]{0,30}(project|rfq|opportunit)|qualify[_ ]?for|unlock/i, P);
  await req(SEC4, 'cc-assistant-actionable', 'the advice names a concrete gap and a quantified upside',
    B(gap && upside),
    Q(`gap leg ${gap ? 'yes' : 'NO'}, quantified-upside leg ${upside ? 'yes' : 'NO'} — the spec's example needs both`));

  // "Not a dashboard. A command center." The refutable form of that is: the home screen is not built
  // out of data tables. THRESHOLD SANITY — this is checked against "could a correct implementation
  // reach it?": a command center may legitimately contain a table somewhere (a line-items grid), so
  // the bar is that tables do not DOMINATE, not that they are absent. Row #4 shipped a check whose
  // only passing move was to delete a view; this one passes for any table-light layout.
  const tables = n(/<table\b|<Table\b/i, P);
  const panels = n(/<Card\b|rounded-|backdrop-blur|glass/i, P);
  await req(SEC4, 'cc-workspace-not-dashboard', 'a command-center layout, not a table dashboard',
    B(panels > tables * 3),
    Q(`${panels} panel token(s) vs ${tables} table token(s) — a command center may hold a table, it may not be built of them`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §5 — 3D SUPPLIER ENVIRONMENT (12)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  // THE SCENE LEG IS DELIBERATELY NARROWER THAN "IS THERE 3D". §19's globe, §22's design-language
  // commitment to 3D maps and §23's Three.js dependency are three other requirements; if a bare
  // <Canvas> satisfied all four the score would count one implementation four times. §5 is a COMPANY
  // ENVIRONMENT, so it needs 3D machinery AND a factory/warehouse subject in the same file.
  const threeD = /@react-three|three\b|<Canvas\b|useFrame|WebGLRenderer|webgl/i;
  const factorySubject = /factory|warehouse|production[_ ]?line|shop[_ ]?floor|plant\b/i;
  const sceneFiles = FILES.filter((f) => threeD.test(fileSrc(f)) && factorySubject.test(fileSrc(f)));
  const anyThreeD = filesMatching(threeD);
  await req(SEC5, 'env-3d-scene', 'a 3D company environment on the supplier surface',
    B(sceneFiles.length > 0),
    Q(`${sceneFiles.length} file(s) carry BOTH 3D and a factory subject [${sceneFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]; ` +
      `${anyThreeD.length} file(s) carry 3D at all — §19/§22/§23 score those separately`));

  // Defect class #3 — the spec enumerates FIVE objects in the scene, so each is its own requirement
  // rather than one "the scene has nodes" verdict. Each names the file that carried it.
  for (const [id, re, label] of [
    ['env-node-factory', /\bfactory\b/i, 'Factory'],
    ['env-node-production-line', /production[_ ]?line/i, 'Production Line'],
    ['env-node-inventory', /\binventory\b/i, 'Inventory'],
    ['env-node-orders', /\borders?\b/i, 'Orders'],
    ['env-node-customers', /\bcustomers?\b/i, 'Customers'],
  ]) {
    const inScene = sceneFiles.filter((f) => re.test(fileSrc(f)));
    const onPortal = filesMatching(re);
    await req(SEC5, id, `the environment has a ${label} node`,
      B(inScene.length > 0),
      Q(`${label}: in a 3D scene file ${inScene.length ? '[' + inScene.map(f => f.split('/').pop()).join(' ') + ']' : 'NO'}; ` +
        `mentioned in ${onPortal.length} portal file(s) — a mention outside the scene is not a scene node`));
  }

  const clickable = sceneFiles.filter((f) => /onClick|onPointer(Down|Up|Over)|raycast|useCursor/i.test(fileSrc(f)));
  await req(SEC5, 'env-clickable-objects', 'clicking an object opens its information',
    B(clickable.length > 0),
    Q(`${clickable.length} scene file(s) with pointer handlers [${clickable.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const whPanel = filesMatching(/warehouse/i).filter((f) => /inventory|stock|available|reserved/i.test(fileSrc(f)));
  await req(SEC5, 'env-warehouse-panel', 'the warehouse click opens an inventory panel',
    B(whPanel.length > 0),
    Q(`${whPanel.length} file(s) pair a warehouse with inventory content [${whPanel.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // ── THESE CHECKS WERE POINTED AT THE WRONG RELATION ───────────────────────────────────────────
  // The first version read inv_items / inv_stock_moves, on the assumption that they held supplier
  // stock. They do not. Measured: inv_items has NO supplier_id at all — its columns are
  // sku, name, uom, category, inventory_account, cogs_account, reorder_point. Those GL account
  // columns give it away: it is QuotesDone's OWN accounting inventory ledger, not a per-supplier
  // stock table. A supplier's warehouse could never appear in it.
  //
  // The supplier's actual stock lives in supplier_product_variant.attributes.available_units, which
  // is where §8's "Available: 120 units" was proven coming from. Scoring §5's warehouse panel
  // against the company's own COGS ledger would have been unsatisfiable by any correct
  // implementation — row #4's unsatisfiable-check defect, arriving through a wrong table rather
  // than a wrong threshold. Both populations are printed so the distinction stays visible.
  const invRows = await one(NROWS_SQL('supplier_product_variant'));
  const moveRows = await one(NROWS_SQL('inv_items'));
  for (const [id, re, label] of [
    ['env-inv-available', /\bavailable\b|qty[_ ]?available|on[_ ]?hand/i, 'Available'],
    ['env-inv-reserved', /\breserved\b|qty[_ ]?reserved|allocated/i, 'Reserved'],
    ['env-inv-production', /in[_ ]?production|qty[_ ]?production|being[_ ]?made|wip\b/i, 'In production'],
  ]) {
    const shown = delivered(re);
    const served = servedBy(re);
    await req(SEC5, id, `the warehouse panel shows ${label}`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}]; ` +
        `supplier_product_variant ${invRows} row(s) (the supplier stock); inv_items ${moveRows} (the company COGS ledger, a different thing) — the verdict is delivery, not rows`));
  }

  // Defect class #1 — a reader that is not the writer. The brief names inv_items/inv_stock_moves as
  // built-but-unread; this measures it rather than repeating it, and requires a SUPPLIER-FACING
  // reader specifically, because a staff-side routine reading stock is not the supplier seeing it.
  // The SUPPLIER's stock, not the company's ledger. See the note above the quantity legs.
  const invReaders = await one(READERS_SQL('supplier_product_variant'));
  const invFnReaders = [
    ...fnsMatching(/supplier_product_variant|available_units/i),
    ...RPC.filter(([, src]) => /supplier_product_variant|available_units/i.test(src)).map(([nm]) => nm),
  ];
  await req(SEC5, 'env-inventory-reader', 'the panel reads real inventory rows',
    B(invFnReaders.length > 0),
    Q(`${invFnReaders.length} supplier-reachable edge fn(s) read inventory [${invFnReaders.join(' ') || 'none'}]; ` +
      `${invReaders} non-writer SQL routine(s) read supplier_product_variant`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §6 — SUPPLIER PROFILE PAGE (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // "Not a static company page. A LIVING intelligence page." Six of these nine are stored facts the
  // profile shows; the last three are what makes it living rather than a record.

  for (const [id, re, label] of [
    ['prof-identity-name', /company[_ ]?name|companyName|legal[_ ]?name/i, 'company identity name'],
    ['prof-verified-mark', /verified|verification[_ ]?status/i, 'verified mark'],
    ['prof-established-year', /founded[_ ]?year|established|year[_ ]?founded|incorporat/i, 'established year'],
    ['prof-employees', /employee[_ ]?count|employees|team[_ ]?size|headcount/i, 'employee count'],
    ['prof-countries', /countries|service[_ ]?emirates|markets[_ ]?served|\bemirate/i, 'countries served'],
  ]) {
    const shown = delivered(re);
    const served = servedBy(re);
    await req(SEC6, id, `the profile shows ${label}`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}]`));
  }

  // AI CONFIDENCE is not a stored form field — it is the page asserting how well it understands the
  // company. Requires a confidence value, not merely the word AI.
  const confShown = delivered(/ai[_ ]?confidence|confidence[_ ]?(score|pct|percent)|understanding[_ ]?pct/i);
  const confServed = servedBy(/confidence/i);
  await req(SEC6, 'prof-ai-confidence', 'an AI Confidence percentage',
    B(confShown && confServed.length > 0),
    Q(`rendered ${confShown ? 'yes' : 'NO'}, served by [${confServed.join(' ') || 'NO fn'}]`));

  // The spec draws a GRAPH, not a list: a root category with capability children. A bulleted list of
  // capabilities is §3's checklist and already scored there, so this needs graph machinery.
  const graphish = /<svg|d3-|force[_ ]?graph|react-flow|<line\b|<edge|nodes?\s*=|edges?\s*=/i;
  const mapFiles = FILES.filter((f) => graphish.test(fileSrc(f)) && /capabilit/i.test(fileSrc(f)));
  await req(SEC6, 'prof-capability-map', 'the capability map renders as a visual graph',
    B(mapFiles.length > 0),
    Q(`${mapFiles.length} file(s) pair graph machinery with capabilities [${mapFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const edgeFiles = mapFiles.filter((f) => /(edges?|links?|children|parent)\s*[:=]/i.test(fileSrc(f)));
  await req(SEC6, 'prof-capability-map-edges', 'the map draws root category to capability children',
    B(edgeFiles.length > 0),
    Q(`${edgeFiles.length} of ${mapFiles.length} capability-graph file(s) declare edges/children`));

  // LIVING vs STATIC, and this is the section's actual claim. A static page renders only columns the
  // supplier typed. A living one renders something DERIVED — a score, a confidence, a computed
  // opportunity. Coverage over the derived signals, so one lucky match cannot certify it.
  const derived = cover([
    ['score', /supplier[_ ]?score|intelligence[_ ]?score|capability[_ ]?score/i],
    ['confidence', /ai[_ ]?confidence|confidence[_ ]?(score|pct)/i],
    ['opportunity', /best[_ ]?opportunit|recommended|match[_ ]?(pct|score)/i],
    ['risk', /risk[_ ]?level|risk[_ ]?score/i],
  ], P);
  await req(SEC6, 'prof-living-not-static', 'the page reads computed fields, not only stored form fields',
    B(derived.hit >= 2),
    Q(`${derived.hit}/${derived.total} derived signal(s) on the profile; missing [${derived.missing.join(' ') || 'none'}] ` +
      `— a page showing only typed columns is a record, not a living page`));
}
