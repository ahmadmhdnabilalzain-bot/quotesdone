// SPEC FILE #5, sections 1-3 — Entry Experience, AI Onboarding, Supplier Digital Twin.
//
//   1. Supplier Entry Experience  (9)  — the landing screen, its two CTAs, its animated background
//   2. AI Supplier Onboarding    (11)  — a conversation that extracts six fields and writes a profile
//   3. Supplier Digital Twin      (9)  — the AI representation: strength, capabilities, risk
//
// ── WHAT THESE 29 REQUIREMENTS ARE ABOUT, AND WHICH POPULATION ANSWERS EACH ──────────────────────
// Almost none is a question about Postgres. "The landing screen shows a world map" is a fact about
// src/. So this file joins two populations: the DATABASE (does the mechanism exist, is there a
// routine behind the number) and the SUPPLIER SURFACE (does something the supplier opens put it on
// screen). A capability computed server-side and rendered nowhere is MISSING here however well the
// backend works — §3's twin is the worked example, since supplier_score carries `reliability` on
// all 20,464 rows and the supplier surface names it zero times.
//
// ── THE SURFACE IS SUPPLIER.SRC, AND THIS FILE CANNOT NAME SupplierPortal.tsx ─────────────────────
// Imported from portal_surface.mjs, which computes the import closure of
// src/app/[locale]/supplier/page.tsx with the SAME importClosure the customer's /me surface uses.
// Row #4 shipped two definitions of "the user sees it" in one run and reported 104/147 against a
// truth of 124. SUPPLIER deliberately exposes no entry-file handle, so that bug is unwritable here
// rather than merely discouraged.
//
// ── THE FIVE DEFECT CLASSES, AS THEY APPLY TO THESE 29 ───────────────────────────────────────────
//  1. THE ONLY READER IS THE WRITER. Reader counts collapse pg_proc overloads with
//     count(distinct proname) and exclude the writer by name — fn_agent_context has two rows on
//     production and inflated every row #2 count that forgot.
//  2. POPULATION STANDING IN FOR DELIVERY. Every "the supplier sees X" requirement needs a RENDER
//     leg over SUPPLIER.SRC. An endpoint returning a field is not a supplier seeing it, so §3's
//     eight twin fields each need the field FETCHED and INTERPOLATED, not merely present in a
//     payload somewhere.
//  3. ONE ROW SCORING A WHOLE MECHANISM. §2 enumerates six extracted fields; the verdict is a
//     per-field coverage count, not "extraction exists".
//  4. SATISFIABLE BY FLIPPING A FLAG. No check reads a boolean column. Counts are over code.
//  5. EVIDENCE THAT DOES NOT COMPUTE THE VERDICT. Every number printed is the number the boolean
//     used, over the same population.
//
// ── AND THE INVERSE FAILURE, WHICH IS JUST AS BAD ────────────────────────────────────────────────
// Row #4 shipped `assistant-floating-persistent` clamped to 0-or-1 and compared against
// views.length — the only way to pass was to DELETE a view, so every view the product gained made
// it harder. Every threshold below is checked against "could a correct implementation reach this?".
// Where a count could legitimately grow, the comparison is >=, never ==.
//
// ── ONE TRAP THIS FILE IS WRITTEN AROUND ─────────────────────────────────────────────────────────
// A COMMENT QUOTING THE MARKUP IT REMOVED IS THAT MARKUP TO A STATIC SCAN. Row #4 lost two
// requirements to a comment reading `WAS A <table min-w-[380px]>`. Counts that must not be fooled
// by prose strip block and line comments from the surface first — see SRC_NC below.
import { SUPPLIER, srcOf, EDGE } from '../portal_surface.mjs';

export const EXPECTED = 29;

export default async function (H) {
  const { req, one } = H;

  // ── literal helpers ────────────────────────────────────────────────────────────────────────────
  // Q defuses the bare write keywords qd_guard's read guard refuses. Not cosmetic: an evidence
  // string quoting source easily contains `call` or `create`, the statement is then refused as a
  // write, and the check ERRORs — and an errored check is an UNMEASURED requirement, strictly worse
  // than either verdict.
  //
  // BOTH EMIT A COMPLETE STATEMENT. req() hands its 4th and 5th arguments straight to one(), which
  // sends them to the management API as the whole query — so a bare `true` is a 42601 syntax error,
  // and the runner books that as an ERRORED check, which is an UNMEASURED requirement rather than a
  // verdict. Nine checks were lost to exactly that before this line said `select`.
  const GUARD = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|vacuum|reindex|call|do)\b/gi;
  const LIT = (s) => `'` + String(s == null ? '' : s).replace(/'/g, "''").replace(GUARD, (m) => m.slice(0, 2) + "'||'" + m.slice(2)) + `'`;
  const Q = (s) => 'select ' + (H.EV ? H.EV(s) : LIT(s));
  const B = (v) => 'select ' + (H.B ? H.B(v) : (v ? 'true' : 'false'));

  const S = SUPPLIER.SRC;                 // the supplier's screen, whole import closure
  const FN = SUPPLIER.FN_SRC;             // every edge function that screen can cause to run
  const FILES = SUPPLIER.FILES;
  const strip = (t) => t.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/^\s*\/\/.*$/gm, ' ');
  // Comment-stripped surface, for any count a comment could fake. See the trap note above.
  const SRC_NC = strip(S);

  // ── THE CHROME IS ON THE SUPPLIER'S PAGE, BUT IT IS NOT THE SUPPLIER PORTAL ────────────────────
  // ChatWidget.tsx is the MARKETING chat bubble and it is in the closure, so a naive scan for a
  // conversation shape finds role:'user' five times and certifies an "AI onboarding conversation"
  // that does not exist. Measured: role:'user'|'assistant' appears 5x in ChatWidget.tsx and 0x
  // anywhere else on the surface. Row #4's spatial module drew this exact line — a cookie banner
  // that fades in is not "the portal animates", and a marketing chat bubble is not the portal's AI
  // assistant module.
  //
  // The line is drawn ONLY where it belongs. §1's background legitimately uses the wide surface:
  // NodeField.tsx IS the animated landing background the supplier genuinely sees. §2's conversation
  // and assistant legs use ASSIST_NC, which is the surface with the marketing widget removed.
  const CHROME = ['src/components/ChatWidget.tsx'];
  const ASSIST_NC = strip(FILES.filter((f) => !CHROME.includes(f)).map((f) => srcOf(f)).join('\n/*FILE*/\n'));

  // THE `g` FLAG IS FORCED, AND THIS IS NOT TIDINESS. String.match with a NON-global regex returns
  // the first match plus its capture groups, so `n()` returned 1 (or 1+groups) for every pattern
  // present, never a count. It made entry-not-form-wall read "3 form controls" and PASS its `< 20`
  // bar while the surface carries 29 — a false MET, the most dangerous verdict a scorer can emit —
  // and it put a wrong number in every evidence string, which is defect class #5 exactly.
  const n = (re, t = SRC_NC) =>
    (t.match(re.flags.includes('g') ? re : new RegExp(re.source, re.flags + 'g')) || []).length;
  const has = (re, t = SRC_NC) => re.test(t);
  // Coverage over an enumerated list — defect class #3. Returns [hits, total, missingNames].
  const cover = (items, t = SRC_NC) => {
    const miss = items.filter(([, re]) => !re.test(t)).map(([nm]) => nm);
    return [items.length - miss.length, items.length, miss];
  };
  // A field is DELIVERED only if the surface both fetches it and interpolates it — defect class #2.
  // Fetching in one component and rendering in another cannot pass by coincidence, because both
  // legs are required to appear and the render leg must be a JSX interpolation, not a string.
  const delivered = (re) => has(re) && new RegExp('\\{[^{}]*' + re.source + '[^{}]*\\}').test(SRC_NC);

  const SEC1 = 'entry', SEC2 = 'onb', SEC3 = 'twin';

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §1 — SUPPLIER ENTRY EXPERIENCE (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  // The route must exist AND be reachable without a session. A supplier landing screen behind a
  // login is not a landing screen. Reachability is evidenced by the page file being a client entry
  // that renders something before any auth gate resolves.
  const hasRoute = FILES.includes('src/app/[locale]/supplier/page.tsx');
  await req(SEC1, 'entry-landing-route', 'a supplier landing screen exists and is reachable unauthenticated',
    B(hasRoute && SUPPLIER.FILES.length > 1),
    Q(`route ${hasRoute ? 'present' : 'ABSENT'}; closure ${FILES.length} file(s), ${SUPPLIER.FNS.length} edge fn(s)`));

  const headline = n(/Supplier\s+Network/i);
  await req(SEC1, 'entry-headline-network', 'a "QuotesDone Supplier Network" welcome headline',
    B(headline > 0), Q(`${headline} occurrence(s) of /Supplier Network/i on the supplier surface`));

  const valprop = n(/AI[- ]powered procurement|Grow your business/i);
  await req(SEC1, 'entry-value-proposition', 'the "grow your business with AI-powered procurement" value line',
    B(valprop > 0), Q(`${valprop} occurrence(s) of the value proposition`));

  const ctaVerified = n(/Become a Verified|Verified Supplier[^"']*<\/|register|registration/i);
  const ctaVerifiedStrict = n(/Become a Verified/i);
  await req(SEC1, 'entry-cta-become-verified', 'a primary CTA "Become a Verified Supplier" leading to registration',
    B(ctaVerifiedStrict > 0),
    Q(`${ctaVerifiedStrict} exact CTA, ${ctaVerified} registration-ish token(s) — the spec names the CTA`));

  const ctaHow = n(/How It Works|watch.{0,12}(video|demo)/i);
  await req(SEC1, 'entry-cta-how-it-works', 'a secondary CTA "Watch How It Works"',
    B(ctaHow > 0), Q(`${ctaHow} occurrence(s) of a how-it-works CTA`));

  // The background is three separate claims in the spec and they are scored separately: an
  // animation, edges that move between two node kinds, and a map. NodeField.tsx is in the closure,
  // so the animation leg can legitimately pass on chrome the supplier genuinely sees.
  const anim = n(/NodeField|animate|@keyframes|requestAnimationFrame|motion\./i);
  await req(SEC1, 'entry-bg-animated-network', 'an animated supply-network background',
    B(anim > 0), Q(`${anim} animation token(s) on the supplier surface`));

  // MOVING connections is two claims, and one token satisfied neither. The first version passed on
  // a single match of a loose regex; the spec asks for connections that MOVE, so the animation leg
  // is required alongside. Both legs are reported so a MISSING names the one that failed.
  const conn = n(/(edge|link|connection|line)s?\b[^;]{0,40}(supplier|project|node)/i);
  await req(SEC1, 'entry-bg-moving-connections', 'moving connections between suppliers and projects',
    B(conn > 0 && anim > 0),
    Q(`${conn} connection token(s) x ${anim} animation token(s) — the spec says MOVING, so both are required`));

  const worldmap = n(/world ?map|<Globe|globe|geoJson|latitude|longitude|mapbox|leaflet/i);
  await req(SEC1, 'entry-bg-world-map', 'a world map visualization',
    B(worldmap > 0), Q(`${worldmap} map/geo token(s) on the supplier surface`));

  // "Register -> fill 20 forms" is what the spec rejects. The threshold is satisfiable by a correct
  // implementation: a conversational onboarding still needs a few inputs (an email, an OTP), so the
  // bar is fewer than 20 raw input elements on the surface, not zero.
  const inputs = n(/<[Ii]nput\b/) + n(/<[Tt]extarea\b/) + n(/<[Ss]elect\b/);
  await req(SEC1, 'entry-not-form-wall', 'entry is not "register then fill 20 forms"',
    B(inputs < 20), Q(`${inputs} form control(s) on the supplier surface; the spec rejects a 20-form wall`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §2 — AI SUPPLIER ONBOARDING (11)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  // A conversational ONBOARDING surface is a turn-taking message list inside the portal itself.
  // Scored over ASSIST_NC so the marketing chat bubble cannot certify it — see the CHROME note.
  const convoWide = n(/role:\s*['"](user|assistant)['"]/i);
  const convoReal = n(/role:\s*['"](user|assistant)['"]/i, ASSIST_NC) + n(/messages?\s*\.map/i, ASSIST_NC);
  await req(SEC2, 'onb-ai-conversation', 'a conversational onboarding surface exists instead of a form',
    B(convoReal > 0),
    Q(`${convoReal} turn-taking token(s) in the portal; ${convoWide} on the whole surface ` +
      `(the difference is ChatWidget.tsx, the marketing bubble); ${inputs} form control(s) alongside`));

  const askCompany = n(/tell me about your (company|business)|about your company/i);
  await req(SEC2, 'onb-prompt-tell-me', 'the agent opens by asking the supplier about their company',
    B(askCompany > 0), Q(`${askCompany} occurrence(s) of an opening company question`));

  const freetext = has(/<[Tt]extarea\b/) || has(/contentEditable/);
  await req(SEC2, 'onb-freetext-input', 'the supplier answers in free text, not fields',
    B(freetext), Q(`free-text composer ${freetext ? 'present' : 'ABSENT'} on the supplier surface`));

  // Defect class #3 — the spec enumerates SIX extracted fields, so each is its own requirement and
  // the extraction leg is measured over the edge functions the surface can actually reach.
  const EXTRACT = [
    ['company_name', /company[_ ]?name|companyName/i],
    ['category', /\bcategory\b|categories/i],
    ['company_type', /company[_ ]?type|manufacturer|supplier[_ ]?type/i],
    ['location', /\blocation\b|\bcity\b|emirate/i],
    ['capability', /capabilit(y|ies)/i],
    ['markets', /\bmarkets?\b|service[_ ]?emirates|countries/i],
  ];
  //
  // ── WHY THE OBVIOUS TWO-LEG TEST IS WRONG HERE, AND WHAT REPLACED IT ──────────────────────────
  // The first version asked "does the endpoint mention this field AND does the surface mention it".
  // All six passed. Attribution showed every match came from SupplierPortal.tsx's CRUD FORM —
  // /\bcategory\b/ matches a <label>, /\blocation\b|\bcity\b/ matched 26 times in address fields.
  // Six false METs, and the spec's actual claim ("the AI creates the supplier profile
  // automatically" FROM A SENTENCE) was never tested at all. A field appearing on a form the
  // supplier types into by hand is the precise OPPOSITE of what §2 asks for.
  //
  // The gate is therefore the mechanism, not the vocabulary: there must be a free-text -> structure
  // path — a prompt naming the field, or an AI endpoint returning it — before any per-field leg can
  // count. Without one, no amount of field vocabulary can pass, which is the correct behaviour.
  //
  // AND THE PROXIMITY SCAN MUST BE PER-FUNCTION, NOT OVER THE CONCATENATION. The second version
  // searched `field ... within 400 chars ... (prompt|json|schema)` across FN_SRC — which is all
  // fourteen reachable edge functions joined end to end. A field name in supplier_api could pair
  // with the word `json` in wa_optin_set and score a MET. All six passed again for that reason.
  // Windowing across a concatenation is the same error as scoring a route by one file: the join is
  // an artefact of the scan, not a fact about the product. Each function is scored on its own text.
  const AI_FNS = ['profile_ai', 'ai_gateway', 'license_extract'].filter((f) => SUPPLIER.FNS.includes(f));
  const aiSrc = AI_FNS.map((f) => [f, strip(EDGE.get(f) || '')]);
  const promptish = /prompt|system[_ ]?message|completion|response_format|json[_ ]?schema/i;
  for (const [field, re] of EXTRACT) {
    // A field is EXTRACTED only if ONE AI function both names it and carries a prompt/schema
    // construct. The form leg is reported separately so a MISSING says which leg is absent.
    const hits = aiSrc.filter(([, src]) => re.test(src) && promptish.test(src)).map(([f]) => f);
    const inPrompt = hits.length > 0;
    const onForm = re.test(SRC_NC);
    await req(SEC2, `onb-extract-${field.replace(/_/g, '-')}`, `AI extraction yields ${field}`,
      B(inPrompt),
      Q(`${field}: extracted by [${hits.join(' ') || 'NO fn'}], form field ${onForm ? 'yes' : 'no'} ` +
        `(a form field is NOT extraction); ${AI_FNS.length} AI endpoint(s) reachable, scored per-fn`));
  }

  // The profile must be WRITTEN, not merely displayed. Scored over the reachable edge functions,
  // since the write happens there.
  const writesProfile = has(/save_profile|create_company|upsert|\.from\(\s*['"]leads['"]\s*\)[^;]{0,80}(update|insert)/i, FN);
  await req(SEC2, 'onb-creates-profile', 'extraction writes the supplier profile automatically',
    B(writesProfile), Q(`profile write path in reachable edge fns: ${writesProfile ? 'present' : 'ABSENT'}`));

  // Is there a server-side routine or endpoint doing the extraction — as opposed to the browser
  // shipping raw text into a column?
  const extractFns = ['profile_ai', 'license_extract', 'quote_extract', 'ai_gateway'].filter((f) => SUPPLIER.FNS.includes(f));
  await req(SEC2, 'onb-extraction-routine', 'a server-side routine or endpoint performs the extraction',
    B(extractFns.length > 0),
    Q(`${extractFns.length} extraction endpoint(s) reachable from the supplier page: ${extractFns.join(' ') || 'none'}`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §3 — SUPPLIER DIGITAL TWIN (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // This is the section the estate's shape makes most interesting. supplier_score holds 20,464 rows
  // with `reliability` non-null on ALL of them — the inputs to the twin exist for every company on
  // production. So a MISSING verdict here is never "no data"; it is "computed and never shown".

  const twinReaders = await one(`select count(distinct p.proname) from pg_proc p
    join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public' and p.prokind in ('f','p')
      and p.proname !~* '^(fn_)?(set|upd|ins|write|refresh|rebuild)_'
      and pg_get_functiondef(p.oid) ~* '\\ysupplier_score\\y'`);
  const scoreRows = await one(`select count(*)::text from public.supplier_score`);
  await req(SEC3, 'twin-object', 'a supplier digital-twin object or routine exists',
    B(Number(twinReaders) > 0),
    Q(`${twinReaders} non-writer routine(s) read supplier_score; ${scoreRows} row(s) on target`));

  // The eight twin fields the spec draws. Each needs the DELIVERY leg (defect class #2): present on
  // the supplier's own surface, not merely computable. Row counts print beside every verdict so a
  // MISSING is never mistaken for an empty-estate artefact.
  const TWIN = [
    ['company-strength', /company[_ ]?strength|strength[_ ]?score|reliability/i, 'Company Strength %'],
    ['capabilities-list', /capabilit(y|ies)/i, 'capability checklist'],
    ['product-count', /product[_ ]?count|products?\s*[:=]\s*\{|\bproducts\b/i, 'product count'],
    ['certifications', /certification|iso_?9001|iso_?certifications/i, 'certifications'],
    ['production-capacity', /production[_ ]?capacity|units?[_ ]?per[_ ]?year|capacity/i, 'production capacity'],
    ['best-opportunities', /best[_ ]?opportunit|recommended[_ ]?project|opportunit/i, 'best opportunities'],
    ['risk-level', /risk[_ ]?level|\brisk\b/i, 'risk level'],
  ];
  //
  // THE RENDER LEG IS AN INTERPOLATION, NOT AN OCCURRENCE. The first version asked only whether the
  // field name appeared on the surface, and three passed on SupplierPortal.tsx's CRUD form —
  // /\bproducts\b/ matched a form label seven times. A field the supplier TYPES is not a twin
  // DISPLAYING what the AI computed about them; it is the opposite claim. `delivered()` requires
  // the name inside a JSX interpolation, so an <Input name="products"> cannot satisfy it while
  // {twin.products} can. This is defect class #2 — population standing in for delivery.
  //
  // THE SERVER LEG IS THE TWIN'S OWN ENDPOINT, NOT "ANY OF FOURTEEN". `re.test(FN)` searched all
  // fourteen reachable functions joined together, so `capability` matching in rfq_flag certified a
  // twin field. The twin is what the supplier's own profile endpoint returns about them, so the
  // leg is scored per-function over the endpoints that actually serve it, and the evidence NAMES
  // the function — an unnamed "endpoint yes" is evidence that does not compute the verdict.
  const TWIN_FNS = ['supplier_portal', 'supplier_api', 'profile_ai'].filter((f) => SUPPLIER.FNS.includes(f));
  const twinSrc = TWIN_FNS.map((f) => [f, strip(EDGE.get(f) || '')]);
  for (const [id, re, label] of TWIN) {
    const shown = delivered(re);       // rendered as a value, not offered as a form field
    const occurs = re.test(SRC_NC);    // reported so a MISSING says which leg failed
    const served = twinSrc.filter(([, src]) => re.test(src)).map(([f]) => f);
    await req(SEC3, `twin-${id}`, `the twin shows ${label}`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'} (mentioned ${occurs ? 'yes' : 'no'}), served by ` +
        `[${served.join(' ') || 'NO fn'}]; ${scoreRows} supplier_score row(s) exist so a MISSING is not an empty estate`));
  }

  // The whole-section delivery leg: is the twin actually on the supplier's screen as a unit?
  const twinSurfaced = n(/digital[_ ]?twin|supplier[_ ]?profile[_ ]?ai|twin/i);
  await req(SEC3, 'twin-supplier-visible', 'the twin renders on the supplier own surface',
    B(twinSurfaced > 0),
    Q(`${twinSurfaced} twin token(s) across ${FILES.length} file(s) of the supplier surface`));
}
