// SPEC FILE #5, sections 18-24 — Collaboration, Network Map, Gamification, Mobile, UI, Tech, Structure.
//
//   18. Supplier Collaboration Workspace (8)  — a workspace per customer relationship
//   19. Supplier Network Map             (0)  — RETIRED 21 Sep 2026; founder: "its useless remove it"
//   20. Supplier Gamification            (8)  — tiers that confer REAL benefits, not badges
//   21. Supplier Mobile App              (9)  — six bottom-nav destinations, same intelligence
//   22. Maximum UI Design Language      (12)  — twelve named style and interaction commitments (ui-3d-maps retired 21 Sep 2026)
//   23. Technology Behind This UI        (9)  — nine named technologies (six 3D legs retired 21 Sep 2026)
//   24. Final Supplier Portal Structure (18)  — eighteen modules, each reachable from navigation (struct-negotiation-ai retired 21 Sep 2026)
//
// ── §23 IS THE SECTION WHERE "INSTALLED" AND "USED" DIVERGE, AND THAT IS THE POINT ───────────────
// Measured before writing: package.json carries motion ^12.42.2, cmdk 1.1.1 and recharts 2.15.4.
// The supplier surface imports NONE of them — framer 0, d3 0, cmdk 0, drag-and-drop 0.
//
// A dependency in package.json is a purchase, not a feature. Scoring §23 off the manifest would
// certify a holographic workspace that renders as a plain form, and it would keep certifying it
// forever because nobody uninstalls a package. Every §23 leg therefore measures USE on the supplier
// surface (or, for the backend items, reachability from it) and prints the installed version beside
// it, so the evidence says exactly which kind of absence this is: never bought, or bought and unused.
//
// ── THE 3D CLAIMS ARE GONE ───────────────────────────────────────────────────────────────────────
// §5 env-3d-scene, §19 map-globe, §22 ui-3d-maps and §23 tech-threejs were four claims about 3D
// that had to be kept from sharing one <Canvas> (ROW5_REQUIREMENTS.md overlap risk #1). On
// 21 Sep 2026 the founder removed the 3D environment and the network map ("its useless remove
// it"), so all four retired with their subject and the overlap no longer exists.
import { readFileSync } from 'node:fs';
import {
  S, P, FILES, P_FILES, FNS, fileSrc, fnSrc, n, has, filesMatching, fnsMatching, fnsWithBoth,
  near, filesNear, fnsNear, delivered, cover, B, Q, READERS_SQL, NROWS_SQL, rpcSources,
} from '../supplier_checks.mjs';

export const EXPECTED = 64;   // 79 until 21 Sep 2026; §19 map-* (7), ui-3d-maps, six §23 tech-* 3D legs and struct-negotiation-ai retired

export default async function (H) {
  const { req, one } = H;
  const S18 = 'collab', S20 = 'game', S21 = 'mob', S22 = 'ui', S23 = 'tech', S24 = 'struct';

  // The serving population follows the rpc hop — the same false MISSING already fixed in §13, §7,
  // §15 and §14. §18's project identity, message count and timeline are all served through
  // rpc('fn_supplier_workspaces'), where the field names live.
  const RPC = await rpcSources(one);
  const servedBy = (re) => [...fnsMatching(re), ...RPC.filter(([, src]) => re.test(src)).map(([nm]) => nm)];

  const DEPS = (() => {
    try {
      const p = JSON.parse(readFileSync(new URL('../../../../package.json', import.meta.url), 'utf8'));
      return { ...(p.dependencies || {}), ...(p.devDependencies || {}) };
    } catch { return {}; }
  })();
  const CSS = (() => {
    try { return readFileSync(new URL('../../../../src/app/globals.css', import.meta.url), 'utf8'); } catch { return ''; }
  })();

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §18 — SUPPLIER COLLABORATION WORKSPACE (8)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // "EVERY customer relationship gets a workspace." The portal has a message thread (`threads`,
  // `thread`, `send`). Messaging is the TRANSPORT; a workspace is a per-project container holding
  // files, messages and a timeline together. Every leg requires the container, and the raw messaging
  // count is printed so the difference is visible rather than assumed.
  const msgTok = n(/threads?|messages?|\bsend\b/i, P);
  const WORKSPACE = /workspace|project[_ ]?room|collaboration|relationship/i;

  const wsFiles = filesNear(WORKSPACE, /project|customer|files?|timeline/i, 400, P_FILES);
  await req(S18, 'collab-workspace-per-relationship', 'every customer relationship gets a workspace',
    B(wsFiles.length > 0),
    Q(`${wsFiles.length} portal file(s) pair a workspace with relationship content ` +
      `[${wsFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]; ` +
      `${msgTok} raw messaging token(s) — a thread is the transport, not a workspace`));

  // `[_. ?]*`, not `[_ ]?` — a component reads its payload as `{w.project?.title}` and
  // `{w.timeline?.pct}`, and the optional-chaining punctuation between the noun and the field made
  // both legs read "rendered NO" while the values were on screen. Same shape as §13's column-name
  // problem: demanding one particular spelling of an access path would only be satisfiable by a
  // component that flattened its payload first, which no well-written one does.
  // ── AND THE SERVED LEG MUST SEE A NESTED KEY ─────────────────────────────────────────────────
  // Same blind spot as §4's quality tile: the routine does not emit a flat `project_title`, it
  // emits `'project', jsonb_build_object('title', ...)` — the identity is a SUB-OBJECT, which is
  // the better payload design and the one a source-grep for a flat identifier cannot see. The
  // served leg therefore also accepts the container key bound to an expression. A key bound to a
  // string constant still fails, so a label cannot pass as a payload.
  for (const [id, re, label, servedRe] of [
    ['collab-project-identity', /project[_. ?]*(name|title|id)\b/i, 'the project it belongs to',
      /project[_. ?]*(name|title|id)\b|'project'\s*,\s*[a-z(]/i],
    ['collab-message-count', /message[_. ?]*count|messages?\.length|unread[_. ?]*count/i, 'a message count', null],
    ['collab-timeline-pct', /timeline[_. ?]*(pct|percent|progress)|progress[_. ?]*(pct|percent)|completion/i, 'a timeline percentage',
      /timeline[_. ?]*(pct|percent|progress)|progress[_. ?]*(pct|percent)|completion|'timeline'\s*,\s*[a-z(]/i],
  ]) {
    const shown = delivered(re, P);
    const served = servedBy(servedRe || re);
    await req(S18, id, `the workspace shows ${label}`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}]`));
  }

  const wsFilesLeg = filesNear(/files?\b|documents?\b|attachments?/i, WORKSPACE, 400, P_FILES);
  await req(S18, 'collab-files', 'files live in the workspace',
    B(wsFilesLeg.length > 0),
    Q(`${wsFilesLeg.length} portal file(s) put files inside a workspace ` +
      `[${wsFilesLeg.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // Defect class #3 — the spec enumerates THREE categories, so the verdict is a coverage count.
  const cats = cover([
    ['drawings', /drawings?/i],
    ['specifications', /specifications?\b|\bspecs?\b/i],
    ['contracts', /contracts?/i],
  ], P);
  await req(S18, 'collab-file-categories', 'files are categorised as drawings / specifications / contracts',
    B(cats.hit === cats.total),
    Q(`${cats.hit}/${cats.total} categories present; missing [${cats.missing.join(' ') || 'none'}]`));

  const wsMsg = filesNear(WORKSPACE, /send|compose|reply|<textarea/i, 400, P_FILES);
  await req(S18, 'collab-messaging', 'messages are readable and sendable in the workspace',
    B(wsMsg.length > 0),
    Q(`${wsMsg.length} portal file(s) put a composer inside a workspace ` +
      `[${wsMsg.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  await req(S18, 'collab-supplier-visible', 'the workspace renders on the supplier surface',
    B(wsFiles.length > 0 && wsFilesLeg.length > 0),
    Q(`workspace container on ${wsFiles.length} file(s), files inside it on ${wsFilesLeg.length} — both required`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §19 — SUPPLIER NETWORK MAP — RETIRED 21 SEP 2026
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // The founder removed the supplier network map (the 3D globe, SupplierNetworkMap.tsx) from the
  // supplier portal (instruction 526: "its useless remove it"). Its seven requirements (map-globe,
  // map-geo-markers, map-layer-suppliers, map-layer-demand, map-layer-projects, map-layer-shipments,
  // map-data-reader) retired WITH their subject. They are not scored as missing, because building
  // them again would contradict the ruling. fn_supplier_network_map still exists in the database;
  // no surface calls it.

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §20 — SUPPLIER GAMIFICATION (8)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // The three BENEFIT legs are the interesting ones. A tier that changes only a badge is a sticker;
  // the spec says tiers confer more RFQs, preferred status and higher visibility. Each benefit
  // therefore has to reach the MATCHING/RANKING mechanism, not just the profile screen.
  // ── A TIER IS NOT ANY TIER ────────────────────────────────────────────────────────────────────
  // This was /platinum|gold|silver|bronze|tier/i, and the bare word did all the damage. The estate
  // is full of tiers that have nothing to do with suppliers: ai_cost_log.tier and model_policy.tier
  // are MODEL tiers (haiku / sonnet / opus), action_execution.risk_tier and customer_health.risk_tier
  // are risk bands, org_authority.max_tier is an approval level. Measured on production 8 Aug 2026,
  // NO routine in the estate mentions platinum, gold, silver or bronze at all — there is no supplier
  // tier anywhere — yet §20 read 3/8, and `game-benefit-visibility` was MET on ai_gateway, whose
  // "tier" chooses a language model.
  //
  // That is the §9 lesson at a different altitude: a token naming the right CONCEPT in the wrong
  // SUBJECT. A supplier tier is a NAMED tier, or the word used in supplier subject matter. Nothing
  // else counts, and this deliberately LOWERS the section's score.
  const TIER_NAMED = /platinum|\bgold\b|\bsilver\b|\bbronze\b/i;
  const TIER_WORD = /\btiers?\b/i;
  const SUPPLIER_CTX = /supplier|lead_id|vendor/i;
  const TIERS = TIER_NAMED;
  const supplierTierFns = FNS.filter((f) => {
    const src = fnSrc(f);
    return TIER_NAMED.test(src) || (TIER_WORD.test(src) && near(src, TIER_WORD, SUPPLIER_CTX, 200));
  });

  const rankSurface = filesNear(TIERS, /ranking|leaderboard|supplier/i, 400, P_FILES);
  await req(S20, 'game-ranking-surface', 'a QuotesDone Supplier Ranking surface',
    B(rankSurface.length > 0),
    Q(`${rankSurface.length} portal file(s) pair tiers with ranking ` +
      `[${rankSurface.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const tierCov = cover([['platinum', /platinum/i], ['gold', /\bgold\b/i], ['silver', /\bsilver\b/i]], P);
  await req(S20, 'game-tiers', 'Platinum / Gold / Silver tiers',
    B(tierCov.hit === tierCov.total),
    Q(`${tierCov.hit}/${tierCov.total} tier name(s) on the portal; missing [${tierCov.missing.join(' ') || 'none'}]`));

  // The `|| tierSql > 0` clause was the whole verdict, and it counted any routine whose NAME matched
  // `tier|rank` or whose body contained the bare word — 39 of them, none about suppliers. A
  // supplier tier computed from a supplier score has to name a tier a supplier would recognise.
  const tierFn = fnsNear(TIERS, /score|rank|compute|assign/i, 400);
  const tierSql = await one(`select count(distinct p.proname)::text from pg_proc p
    join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public' and p.prokind in ('f','p')
      and pg_get_functiondef(p.oid) ~* '(platinum|\\mgold\\M|\\msilver\\M|\\mbronze\\M)'`);
  await req(S20, 'game-tier-assignment-routine', 'the tier is computed from score by a routine',
    B(tierFn.length > 0 || Number(tierSql) > 0),
    Q(`${tierFn.length} reachable fn(s) compute a NAMED supplier tier [${tierFn.join(' ') || 'none'}]; ` +
      `${tierSql} SQL routine(s) name one — model-routing, risk and authority tiers are excluded`));

  const board = filesNear(/leaderboard|ranking/i, /\.map\(|rank\s*[:=]|position/i, 400, P_FILES);
  await req(S20, 'game-leaderboard', 'a ranked list of suppliers',
    B(board.length > 0),
    Q(`${board.length} portal file(s) render a ranked list ` +
      `[${board.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  for (const [id, re, label] of [
    ['game-benefit-more-rfqs', /match|inquiry|rfq|opportunit/i, 'tier affects RFQ distribution'],
    ['game-benefit-preferred-status', /preferred/i, 'preferred-supplier status is conferred'],
    ['game-benefit-visibility', /visibility|rank|order[_ ]?by|priority|boost/i, 'tier affects visibility'],
  ]) {
    // The benefit must reach the SERVER mechanism, in the same function as a SUPPLIER tier. Scored
    // over supplierTierFns rather than "any function containing the word tier": ai_gateway ties a
    // tier to `rank|order_by|priority` all day long, and that tier picks a language model.
    const inMechanism = supplierTierFns.filter((f) => near(fnSrc(f), TIERS, re, 500));
    const sqlSide = await one(`select count(distinct p.proname)::text from pg_proc p
      join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p')
        and pg_get_functiondef(p.oid) ~* '(platinum|\\mgold\\M|\\msilver\\M|\\mbronze\\M)'`);
    await req(S20, id, label,
      B(inMechanism.length > 0),
      Q(`${label}: ${inMechanism.length} reachable fn(s) tie a tier to it [${inMechanism.join(' ') || 'none'}]; ` +
        `${sqlSide} SQL routine(s) mention tiers — a tier that changes only a badge confers nothing`));
  }

  await req(S20, 'game-supplier-visible', 'the ranking renders on the supplier surface',
    B(rankSurface.length > 0 && tierCov.hit > 0),
    Q(`ranking surface on ${rankSurface.length} file(s), ${tierCov.hit}/3 tier name(s) present — both required`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §21 — SUPPLIER MOBILE APP (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // Measured before writing: the portal navigates with setTab(), and its only destinations are
  // `profile` and `documents`. So the six-destination bottom nav is answerable precisely.
  const navFiles = filesNear(/bottom[_ ]?nav|<nav\b|setTab\(|NAV\b|TABS\b/i, /fixed|bottom-0|flex/i, 400, P_FILES);
  await req(S21, 'mob-bottom-nav', 'a bottom navigation bar',
    B(navFiles.length > 0),
    Q(`${navFiles.length} portal file(s) pair navigation with bottom-anchored layout ` +
      `[${navFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // The six destinations, one requirement each — and each must be a NAVIGABLE DESTINATION, which is
  // what setTab('x') expresses, not merely a word rendered somewhere.
  //
  // ── A DESTINATION LIST IS USUALLY AN ARRAY, NOT A CALL SITE — AND MISSING THAT IS A FALSE MISSING ──
  // The first version read only `setTab('literal')` and found TWO destinations. The portal actually
  // declares `const TABS = ['overview','rfqs','documents','profile','projects','messages','billing']`
  // and renders `TABS.map(k => <button onClick={() => setTab(k)}>)`. SEVEN destinations, and the
  // scan saw two of them, because the literal never appears at a call site.
  //
  // That under-counted §21's six nav legs and §24's nineteen module legs at once — a false MISSING
  // is as much a defect as a false MET, and this one made the product look worse than it is. The
  // refutation rule cuts both ways: attack MET and MISSING with equal scepticism.
  const dests = [...new Set([
    ...[...P.matchAll(/set(?:Tab|View|Section|Page)\(\s*['"]([a-z_]+)['"]/gi)].map((m) => m[1]),
    // Declared destination arrays: const TABS = ['a','b',...] / NAV / MENU / SECTIONS / VIEWS.
    ...[...P.matchAll(/\b(?:TABS|NAV|MENU|SECTIONS|VIEWS|ROUTES)\b\s*=\s*\[([^\]]{0,400})\]/g)]
      .flatMap((m) => [...m[1].matchAll(/['"]([a-z_]+)['"]/gi)].map((x) => x[1])),
  ].map((d) => d.toLowerCase()))];
  for (const [id, re, label] of [
    ['mob-nav-command', /^(command|home|dashboard|overview)$/i, 'Command'],
    ['mob-nav-rfqs', /^(rfqs?|opportunit\w*|inbox|requests?)$/i, 'RFQs'],
    ['mob-nav-products', /^(products?|catalog\w*)$/i, 'Products'],
    ['mob-nav-messages', /^(messages?|threads?|chat)$/i, 'Messages'],
    ['mob-nav-ai', /^(ai|assistant|agent)$/i, 'AI'],
    ['mob-nav-company', /^(company|profile|account)$/i, 'Company'],
  ]) {
    const hit = dests.filter((d) => re.test(d));
    await req(S21, id, `a ${label} destination in the navigation`,
      B(hit.length > 0),
      Q(`${label}: ${hit.length ? 'destination [' + hit.join(' ') + ']' : 'NOT a destination'}; ` +
        `portal destinations are [${dests.join(' ') || 'none'}]`));
  }

  // Usable at phone width. Threshold checked against "could a correct implementation reach this?":
  // a responsive portal may still set a fixed width on a small badge, so the bar is that NO element
  // declares a fixed width wider than a phone viewport (343px content on a 375px screen).
  const wide = [...P.matchAll(/(?:min-w|width)[-:]\s*\[?(\d{3,})px/gi)].map((m) => Number(m[1])).filter((w) => w > 343);
  await req(S21, 'mob-responsive', 'the supplier surface is usable at phone width',
    B(wide.length === 0),
    Q(`${wide.length} fixed width(s) wider than a 343px phone content box${wide.length ? ': ' + wide.slice(0, 6).join(', ') : ''}`));

  // "Same intelligence" — mobile is not a cut-down set. Refutable form: no mobile-only branch hides
  // modules from small screens.
  const hiddenOnMobile = n(/hidden\s+(sm|md|lg):|(sm|md|lg):(block|flex)\s/g, P);
  await req(S21, 'mob-same-intelligence', 'mobile carries the same modules, not a cut-down set',
    B(dests.length >= 6),
    Q(`${dests.length} navigable destination(s) [${dests.join(' ') || 'none'}] against §21's six; ` +
      `${hiddenOnMobile} breakpoint-gated visibility rule(s) on the portal`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §22 — MAXIMUM UI DESIGN LANGUAGE (13)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  const darkCtl = /dark:|data-theme|prefers-color-scheme|\.dark\b/;
  await req(S22, 'ui-dark-theme', 'a dark professional theme',
    B(darkCtl.test(P) || darkCtl.test(CSS)),
    Q(`dark-mode token(s): ${n(darkCtl, P)} on the portal, ${(CSS.match(/dark|prefers-color-scheme/gi) || []).length} in globals.css`));

  await req(S22, 'ui-glass-panels', 'glass panels',
    B(n(/backdrop-blur|backdrop-filter|glass/i, P) > 0),
    Q(`${n(/backdrop-blur|backdrop-filter|glass/i, P)} glass token(s) on the portal`));

  await req(S22, 'ui-holographic-layers', 'holographic data layers',
    B(n(/holograph|hologram|\bglow\b|neon|iridescen/i, P) > 0),
    Q(`${n(/holograph|hologram|\bglow\b|neon|iridescen/i, P)} holographic token(s) on the portal`));

  // ui-3d-maps retired 21 Sep 2026 with the 3D environment (§5) and the network map (§19) — the two
  // surfaces that made 3D a recurring design element. Founder: "its useless remove it".

  const chartLib = /recharts|from ['"]d3|d3-|<svg[\s\S]{0,200}<path|sparkline/i;
  await req(S22, 'ui-animated-charts', 'animated charts',
    B(P_FILES.some((f) => near(fileSrc(f), chartLib, /transition|animate|motion\.|@keyframes|duration/i, 400))),
    Q(`${filesMatching(chartLib, P_FILES).length} portal file(s) carry chart machinery, ` +
      `${n(/transition|animate|motion\./i, P)} animation token(s) — both required in one file`));

  await req(S22, 'ui-realtime-updates', 'real-time updates',
    B(n(/supabase[\s\S]{0,40}channel\(|realtime|subscribe\(|EventSource|WebSocket|setInterval/i, P) > 0),
    Q(`${n(/channel\(|realtime|subscribe\(|EventSource|WebSocket|setInterval/i, P)} live-update token(s) on the portal`));

  // The spec's explicit negative. Threshold sanity: an AI workspace may contain a table or a form —
  // it may not be BUILT of them. Panels must dominate.
  const tables = n(/<table\b|<Table\b/i, P);
  const forms = n(/<form\b|<[Ii]nput\b|<[Ss]elect\b/g, P);
  const panels = n(/<Card\b|rounded-|backdrop-blur|glass|<Dialog|<Sheet/i, P);
  await req(S22, 'ui-not-sidebar-tables-forms', 'not a sidebar / tables / forms interface',
    B(panels > (tables + forms) * 2),
    Q(`${panels} panel token(s) vs ${tables} table + ${forms} form token(s) — a workspace may hold a form, it may not be built of them`));

  await req(S22, 'ui-ai-workspace', 'an AI Workspace interface model',
    B(filesNear(/workspace/i, /assistant|ai\b|agent/i, 400, P_FILES).length > 0),
    Q(`${filesNear(/workspace/i, /assistant|ai\b|agent/i, 400, P_FILES).length} portal file(s) pair a workspace with AI`));

  await req(S22, 'ui-floating-windows', 'floating windows',
    B(n(/<Dialog|<Modal|<Sheet|<Popover|position:\s*absolute|floating|draggable/i, P) > 0),
    Q(`${n(/<Dialog|<Modal|<Sheet|<Popover|floating|draggable/i, P)} floating-surface token(s) on the portal`));

  await req(S22, 'ui-drag-and-drop', 'drag and drop',
    B(n(/onDrag|onDrop|draggable|dnd-kit|react-dnd|useSortable/i, P) > 0),
    Q(`${n(/onDrag|onDrop|draggable|dnd-kit|react-dnd|useSortable/i, P)} drag-and-drop token(s); ` +
      `dnd-kit ${DEPS['@dnd-kit/core'] ? 'installed ' + DEPS['@dnd-kit/core'] : 'not installed'}`));

  await req(S22, 'ui-command-palette', 'a command palette',
    B(n(/cmdk|CommandDialog|command[_ ]?palette|⌘K|cmd\+k/i, P) > 0),
    Q(`${n(/cmdk|CommandDialog|command[_ ]?palette|⌘K/i, P)} command-palette token(s) on the portal; ` +
      `cmdk ${DEPS['cmdk'] ? 'INSTALLED ' + DEPS['cmdk'] + ' but unused here' : 'not installed'}`));

  await req(S22, 'ui-context-menus', 'context menus',
    B(n(/onContextMenu|ContextMenu|right[_ ]?click/i, P) > 0),
    Q(`${n(/onContextMenu|ContextMenu|right[_ ]?click/i, P)} context-menu token(s) on the portal`));

  await req(S22, 'ui-interactive-graphs', 'interactive graphs',
    B(P_FILES.some((f) => near(fileSrc(f), /<svg|recharts|d3-|force[_ ]?graph|react-flow/i, /onClick|onHover|onMouse|tooltip/i, 400))),
    Q(`${filesMatching(/<svg|recharts|d3-|force[_ ]?graph|react-flow/i, P_FILES).length} portal file(s) carry graph machinery; ` +
      `interactivity must be in the same file`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §23 — TECHNOLOGY BEHIND THIS UI (15)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // USE, not purchase. See the header note. Every leg prints the installed version so the evidence
  // distinguishes "never bought" from "bought and unused" — motion and cmdk are both the second
  // kind, which no manifest-based check could ever tell you.
  // The six 3D technology legs (tech-threejs, tech-r3f, tech-webgl, tech-3d-model-assets, tech-gltf,
  // tech-webgpu) retired 21 Sep 2026 with the 3D environment and the network map — the only
  // surfaces that used them. Founder: "its useless remove it".
  for (const [id, re, dep, label] of [
    ['tech-nextjs', /next\/|from ['"]next['"]|use client/i, 'next', 'Next.js'],
    ['tech-react', /from ['"]react['"]|useState|useEffect/i, 'react', 'React'],
    ['tech-framer-motion', /framer-motion|from ['"]motion|motion\.\w+/i, 'motion', 'Framer Motion'],
    ['tech-d3', /from ['"]d3|d3-(scale|shape|array|selection)/i, 'd3', 'D3.js'],
  ]) {
    const used = n(re, P);
    const installed = dep && DEPS[dep] ? `INSTALLED ${DEPS[dep]}` : (dep ? 'not installed' : 'n/a');
    await req(S23, id, `${label} is used on the supplier surface`,
      B(used > 0),
      Q(`${label}: ${used} usage(s) on the supplier surface; dependency ${installed} ` +
        `— a package.json entry is a purchase, not a feature`));
  }

  // The five backend technologies. "On the supplier surface" means REACHABLE FROM it — these run
  // server-side by nature, so requiring an import in a .tsx would be unsatisfiable by any correct
  // implementation. Scored per function over the reachable set, plus the database estate.
  const orFns = fnsMatching(/openrouter/i);
  await req(S23, 'tech-openrouter', 'OpenRouter is reachable from the supplier surface',
    B(orFns.length > 0),
    Q(`${orFns.length} reachable edge fn(s) use OpenRouter [${orFns.join(' ') || 'none'}]`));

  const vecFns = fnsMatching(/embedding|vector|pgvector/i);
  const pgvector = await one(`select count(*)::text from pg_extension where extname='vector'`);
  const vecCols = await one(`select count(*)::text from information_schema.columns
    where table_schema='public' and udt_name='vector'`);
  await req(S23, 'tech-vector-db', 'a vector database is reachable from the supplier surface',
    B(vecFns.length > 0 && Number(pgvector) > 0),
    Q(`pgvector extension ${pgvector}, ${vecCols} vector column(s), ` +
      `${vecFns.length} reachable fn(s) use embeddings [${vecFns.join(' ') || 'none'}]`));

  const agentFns = fnsNear(/prompt|system[_ ]?message|tool[_ ]?call|function[_ ]?call/i, /model|completion|messages\s*:/i, 500);
  await req(S23, 'tech-agent-framework', 'an agent framework backs the supplier surface',
    B(agentFns.length > 0),
    Q(`${agentFns.length} reachable fn(s) run an LLM agent loop [${agentFns.join(' ') || 'none'}]`));

  const docAiFns = fnsNear(/document|pdf|licen[cs]e|image/i, /vision|ocr|extract|prompt/i, 500);
  await req(S23, 'tech-document-ai', 'Document AI is reachable from the supplier surface',
    B(docAiFns.length > 0),
    Q(`${docAiFns.length} reachable fn(s) do document understanding [${docAiFns.join(' ') || 'none'}]`));

  // graph_nodes is the estate's knowledge graph. The brief records it as BUILT_BUT_UNREAD, so this
  // leg requires a SUPPLIER-REACHABLE reader — a nightly cron rebuilding a graph nobody reads is
  // not a knowledge graph behind this UI.
  const graphRows = await one(NROWS_SQL('graph_nodes'));
  const graphFns = fnsMatching(/graph_nodes|graph_edges|knowledge[_ ]?graph/i);
  const graphReaders = await one(READERS_SQL('graph_nodes'));
  await req(S23, 'tech-knowledge-graph', 'a knowledge graph is reachable from the supplier surface',
    B(graphFns.length > 0),
    Q(`graph_nodes ${graphRows} row(s), ${graphReaders} non-writer SQL routine(s), ` +
      `${graphFns.length} SUPPLIER-REACHABLE fn(s) [${graphFns.join(' ') || 'none'}] — a graph nobody reads is not behind this UI`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §24 — FINAL SUPPLIER PORTAL STRUCTURE (19)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // Defect class #3 in its strict form: nineteen modules scored as a per-item coverage count over
  // ONE navigation surface, not nineteen independent greps over the portal. A module is present when
  // it is a NAVIGABLE DESTINATION — setTab('x') — or a rendered section heading. A word appearing in
  // a translation string is neither, which is the §7 caption lesson.
  const headings = [...P.matchAll(/(?:<h[1-3][^>]*>|title\s*:\s*['"]|label\s*:\s*['"])([^<'"]{2,40})/gi)].map((m) => m[1].toLowerCase().trim());
  const navSurface = [...dests, ...headings];
  for (const [id, re, label] of [
    ['struct-ai-command-center', /command|home|dashboard|overview/i, 'AI Command Center'],
    ['struct-digital-twin', /twin|digital[_ ]?twin/i, 'Supplier Digital Twin'],
    ['struct-company-profile', /company|profile/i, 'Company Profile'],
    ['struct-product-intelligence', /product/i, 'Product Intelligence'],
    ['struct-catalog-ai', /catalog/i, 'Catalog AI'],
    ['struct-rfq-marketplace', /rfq|marketplace|opportunit|inbox|request/i, 'RFQ Marketplace'],
    ['struct-quote-builder', /quote/i, 'Quote Builder'],
    // struct-negotiation-ai retired 21 Sep 2026: the founder removed negotiations from both portals (instruction 527).
    ['struct-customer-projects', /project/i, 'Customer Projects'],
    ['struct-documents', /document/i, 'Documents'],
    ['struct-certifications', /certificat/i, 'Certifications'],
    ['struct-inventory', /inventory|stock/i, 'Inventory'],
    ['struct-analytics', /analytic|insight|report/i, 'Analytics'],
    ['struct-market-intelligence', /market/i, 'Market Intelligence'],
    ['struct-supplier-score', /score|rating|health/i, 'Supplier Score'],
    ['struct-ai-assistant', /assistant|\bai\b|agent/i, 'AI Assistant'],
    ['struct-messages', /message|thread|chat|inbox/i, 'Messages'],
    ['struct-finance', /finance|payment|invoice|billing|payout/i, 'Finance'],
    ['struct-settings', /setting|preference/i, 'Settings'],
  ]) {
    const asDest = dests.filter((d) => re.test(d));
    const asHeading = headings.filter((h) => re.test(h));
    await req(S24, id, `${label} is reachable from the supplier navigation`,
      B(asDest.length > 0 || asHeading.length > 0),
      Q(`${label}: destination [${asDest.join(' ') || 'no'}], heading/label [${asHeading.slice(0, 3).join(' | ') || 'no'}]; ` +
        `portal has ${dests.length} destination(s) and ${headings.length} heading(s) total`));
  }
}
