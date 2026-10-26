// SPEC FILE #5, sections 9-11 — RFQ Intelligence Center, AI Ranking, Quote Builder.
//
//    9. RFQ Intelligence Center (9) — "this is where suppliers make money": the opportunity feed
//   10. AI RFQ Ranking          (8) — ranked, not listed, and each rank carries its reasons
//   11. AI Quote Builder        (9) — the supplier does NOT manually create quotes; AI proposes one
//   12. AI Negotiation Assistant(0) — RETIRED 21 Sep 2026; founder removed negotiations from both portals
//
// ── THE TRAP THIS MODULE IS MOST EXPOSED TO ──────────────────────────────────────────────────────
// The portal already reaches `extract_quote` and `submit_quote`. Both are about quotes. NEITHER is
// §11. `extract_quote` OCRs a quote document the supplier already wrote — it reads a price off a
// PDF. §11 is the inverse: the supplier writes nothing and the AI PROPOSES a price, a market
// position, a delivery estimate, a risk level and a warranty. A scan for /quote/i cannot tell an
// OCR reader from a pricing recommender, and passing §11 on `extract_quote` would certify the
// section's entire premise ("supplier does not manually create quotes") off a feature that exists
// precisely because the supplier does.
//
// So every §11 leg subtracts the extraction vocabulary explicitly and prints both counts, the same
// discipline that caught the registration uploader in §7 and the help desk in §4.
//
// ── AND THE MONOLITH ─────────────────────────────────────────────────────────────────────────────
// SupplierPortal.tsx is 81,811 stripped characters holding the settings form, the registration
// uploader, the help desk, the catalog uploader, the RFQ inbox AND the quote submission flow.
// Round 3 established that "does this FILE contain both X and Y" is nearly vacuous against it. Legs
// that need two things together use near()/filesNear()/fnsNear(), which window WITHIN one file or
// one function — adjacency inside a single file is a real fact; adjacency across a join is not.
import {
  S, P, FILES, P_FILES, FNS, fileSrc, fnSrc, n, has, filesMatching, fnsMatching, fnsWithBoth,
  near, filesNear, fnsNear, delivered, cover, B, Q, READERS_SQL, NROWS_SQL, rpcSources,
} from '../supplier_checks.mjs';

export const EXPECTED = 26;   // 33 until 21 Sep 2026; the seven §12 neg-* legs retired with the negotiation assistant

export default async function (H) {
  const { req, one } = H;
  const S9 = 'rfq', S10 = 'rank', S11 = 'qb';

  // ── THE SERVING POPULATION FOLLOWS THE RPC HOP ────────────────────────────────────────────────
  // Already fixed in §13, §7, §15, §14 and §18; §10 and §11 were never updated, and they are the
  // two sections where it matters most. Ranking and price recommendation are QUERIES — over
  // inquiries, leads and quotes — so they belong in SQL where the planner can see the indexes, and
  // an edge function that rpc()s one is a four-line passthrough with none of the field names in it.
  // Scanning only the edge tier therefore reports "computed by [NO fn]" about logic that is
  // demonstrably running: fn_supplier_opportunities answers 200 over HTTPS on both projects.
  //
  // This loosens nothing. RPC_NAMES is derived from the `.rpc('...')` calls in the reachable edge
  // functions, so a routine the supplier's browser cannot reach is still not a server for them.
  const RPC = await rpcSources(one);
  const servedBy = (re) => [...fnsMatching(re), ...RPC.filter(([, src]) => re.test(src)).map(([nm]) => nm)];
  const servedNear = (reA, reB, win = 300) => [
    ...fnsNear(reA, reB, win),
    ...RPC.filter(([, src]) => near(src, reA, reB, win)).map(([nm]) => nm),
  ];

  // Quote-EXTRACTION vocabulary: reading a price off a document the supplier already produced.
  // Subtracted from every §11 leg.
  const EXTRACTQ = /extract_quote|extractQuote|ocr|parse[_ ]?quote|read[_ ]?the[_ ]?quote|upload[_ ]?quote/i;
  // Quote-RECOMMENDATION vocabulary: the AI proposing terms the supplier did not write.
  const RECOMMEND = /recommend|suggest|proposed?[_ ]?price|advis|ai[_ ]?price|price[_ ]?guidance/i;
  // RFQ SUBJECT MATTER. Required near any §9/§10 leg so the platform's plumbing — OAuth `scope`,
  // the OTP's `expires_at`, an HTML `title`, an HTTP `request` — cannot satisfy a requirement about
  // opportunities. See the note above the §9 field loop for what this was catching.
  const RFQCTX = /inquir|\brfq\b|opportunit|requirement|tender|bid\b|quote[_ ]?request/i;

  const extractTok = n(EXTRACTQ, P);

  // The estate's row counts. Printed beside every verdict, never used as one: production holds
  // 0 inquiries, 0 quotes and 0 inquiry_matches, so a check that counted rows would read MISSING for
  // all 33 requirements and measure nothing.
  const inqRows = await one(NROWS_SQL('inquiries'));
  const qRows = await one(NROWS_SQL('quotes'));
  const mRows = await one(NROWS_SQL('inquiry_matches'));
  const ESTATE = `inquiries ${inqRows}, quotes ${qRows}, matches ${mRows} — verdicts are mechanism, not rows`;

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §9 — RFQ INTELLIGENCE CENTER (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  // The opportunity screen itself. `inbox` is the portal's existing action; the question is whether
  // it presents OPPORTUNITIES (things to win) rather than messages.
  // NOT /requests?/ — that matched HTTP "request" in layout.tsx, which is site chrome carrying no
  // opportunity list at all. The leg needs RFQ subject matter on both sides of the window.
  const oppFiles = filesNear(/inbox|opportunit|new[_ ]?rfq/i, RFQCTX, 500);
  await req(S9, 'rfq-opportunities-screen', 'a NEW OPPORTUNITIES screen',
    B(oppFiles.length > 0),
    Q(`${oppFiles.length} file(s) put an opportunity list next to opportunity content ` +
      `[${oppFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]; ${ESTATE}`));

  //
  // ── GENERIC INFRASTRUCTURE VOCABULARY IS NOT RFQ VOCABULARY ───────────────────────────────────
  // The first version of these six legs read 4 MET, and the evidence itself gave them away:
  // rfq-requirement was "served by [kyc login_otp role_guard …]" and rfq-deadline by "[login_otp …]".
  // login_otp does not serve an RFQ deadline. The regexes were matching the platform's plumbing:
  //   · /scope/       → OAuth/JWT scope in login_otp and role_guard
  //   · /expires?_at/ → the OTP's own expiry
  //   · /\btitle\b/   → any HTML title attribute
  //   · /\bunits?\b/  → any occurrence of the word
  // This is the §7 lesson again at a different altitude: a token that names the right CONCEPT in the
  // wrong SUBJECT. The fix is the same shape — require the field to sit near RFQ subject matter
  // inside the SAME function, and print the unscoped list beside it so the gap is auditable.
  for (const [id, re, label] of [
    ['rfq-project-title', /project[_ ]?(name|title)|inquiry[_ ]?title|rfq[_ ]?title/i, 'project title'],
    ['rfq-requirement', /requirement|scope[_ ]?of[_ ]?work|what[_ ]?(they|customer)[_ ]?need/i, 'the requirement'],
    ['rfq-quantity', /\bquantity\b|\bqty\b|volume/i, 'quantity'],
    ['rfq-deadline', /deadline|due[_ ]?date|closes?[_ ]?(at|on)|days[_ ]?left/i, 'deadline'],
    ['rfq-ai-match-pct', /match[_ ]?(pct|percent|score)|ai[_ ]?match|fit[_ ]?score/i, 'AI match %'],
    ['rfq-estimated-value', /estimated[_ ]?(value|opportunity|budget)|opportunity[_ ]?value/i, 'estimated opportunity value'],
  ]) {
    const shown = delivered(re);
    // The rpc hop, same as §10 and §12: project_title, match_pct, estimated_value and the
    // requirement are produced by fn_supplier_opportunities, and the edge action that rpc()s it
    // carries none of those names.
    const served = servedNear(re, RFQCTX, 500);  // the field, near RFQ subject matter, same fn
    const unscoped = fnsMatching(re);             // what the loose version would have counted
    await req(S9, id, `the opportunity shows ${label}`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}] ` +
        `(${unscoped.length} fn(s) name it outside any RFQ context: [${unscoped.join(' ') || 'none'}]); ${ESTATE}`));
  }

  // The action that turns an opportunity into money. Requires a submit affordance on the surface
  // AND a server that accepts it.
  const submitUi = has(/submit[_ ]?quote|send[_ ]?quote|submitQuote/i, P);
  const submitFn = fnsMatching(/submit[_ ]?quote|submitQuote/i);
  await req(S9, 'rfq-submit-quote-action', 'a Submit Quote action on the opportunity',
    B(submitUi && submitFn.length > 0),
    Q(`submit affordance ${submitUi ? 'yes' : 'NO'}, accepted by [${submitFn.join(' ') || 'NO fn'}]`));

  // The feed must be COMPUTED FOR THIS SUPPLIER, not a global list the client filters. The
  // refutable form: a server-side routine that matches inquiries to a supplier.
  // Scoping-to-the-caller ALONE matched ai_gateway, which scopes everything to its caller and
  // serves no feed. Both an RFQ subject and a per-caller scope must sit in the same function.
  const feedFn = fnsNear(RFQCTX, /supplier[_ ]?id|lead_id|claims\.|jwt/i, 600);
  const matchRoutines = await one(`select count(distinct p.proname) from pg_proc p
    join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public' and p.prokind in ('f','p') and p.proname ~* 'match'`);
  await req(S9, 'rfq-feed-routine', 'the opportunity feed is computed server-side for this supplier',
    B(feedFn.length > 0),
    Q(`${feedFn.length} fn(s) scope a feed to the caller [${feedFn.join(' ') || 'none'}]; ` +
      `${matchRoutines} matching routine(s) in public; ${ESTATE}`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §10 — AI RFQ RANKING (8)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // "Instead of showing all RFQs, AI ranks them." The whole section is the difference between a
  // LIST and a RANKING, so the legs are about ordering and justification, never about the list.

  const recFiles = filesNear(/recommended|for[_ ]?you|best[_ ]?match|top[_ ]?(picks?|matches)/i, /rfq|opportunit|project|inquiry/i, 500);
  await req(S10, 'rank-recommended-list', 'a "Recommended For You" list',
    B(recFiles.length > 0),
    Q(`${recFiles.length} file(s) pair recommendation language with opportunities ` +
      `[${recFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // ORDERED BY RANK, not by date. A chronological inbox is the thing §10 rejects, so a created_at
  // sort cannot satisfy it — the ordering key must be a score.
  const scoreSort = servedNear(/order[_ ]?by|\.order\(|sort/i, /score|match|rank|similarity|relevance/i, 300);
  const dateSort = servedNear(/order[_ ]?by|\.order\(|sort/i, /created_at|updated_at|\bdate\b/i, 300);
  await req(S10, 'rank-ordered', 'ranked ordering, not chronological',
    B(scoreSort.length > 0),
    Q(`${scoreSort.length} fn(s) order by a SCORE [${scoreSort.join(' ') || 'none'}]; ` +
      `${dateSort.length} order by date [${dateSort.join(' ')}] — a chronological inbox is what §10 rejects`));

  const rankPctShown = delivered(/match[_ ]?(pct|percent|score)|ai[_ ]?match|fit[_ ]?score/i);
  const rankPctServed = fnsMatching(/match[_ ]?(pct|percent|score)|fit[_ ]?score/i);
  await req(S10, 'rank-match-pct', 'each ranked RFQ carries a match percentage',
    B(rankPctShown && rankPctServed.length > 0),
    Q(`rendered ${rankPctShown ? 'yes' : 'NO'}, served by [${rankPctServed.join(' ') || 'NO fn'}]`));

  // The "Why" block, and then its three enumerated reasons — defect class #3, one requirement each.
  const whyFiles = filesNear(/\bwhy\b|reasons?|because|match[_ ]?reason/i, /match|rank|recommend/i, 400);
  await req(S10, 'rank-why-reasons', 'a "Why" explanation list is rendered',
    B(whyFiles.length > 0),
    Q(`${whyFiles.length} file(s) pair explanation language with ranking ` +
      `[${whyFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  for (const [id, re, label] of [
    ['rank-reason-capacity', /capacity[_ ]?fits?|your[_ ]?capacity|capacity[_ ]?match/i, 'your capacity fits'],
    ['rank-reason-similar-history', /similar[_ ]?(project|job|work)|previous[_ ]?(project|similar)|worked[_ ]?on/i, 'previous similar project'],
    ['rank-reason-location', /nearby|near[_ ]?you|proximity|same[_ ]?emirate|distance/i, 'nearby location'],
  ]) {
    const onSurface = has(re, P);
    const served = servedBy(re);
    await req(S10, id, `the ranking explains "${label}"`,
      B(onSurface && served.length > 0),
      Q(`"${label}": surface ${onSurface ? 'yes' : 'NO'}, computed by [${served.join(' ') || 'NO fn'}]`));
  }

  // The ranking must be a ROUTINE, not a client-side sort — a browser sorting an array it already
  // holds is not "AI ranks them".
  // /score/ near /limit/ matched ai_gateway, which ranks nothing — a scoring word beside a SQL
  // keyword is not a ranking. Ranking is ranking OF something, so RFQ subject matter is required.
  const rankFn = servedNear(/rank|relevance|match[_ ]?score/i, RFQCTX, 400);
  await req(S10, 'rank-routine', 'ranking is computed by a routine, not a client-side sort',
    B(rankFn.length > 0),
    Q(`${rankFn.length} server fn(s) rank [${rankFn.join(' ') || 'none'}]; ` +
      `${n(/\.sort\(/g, P)} client-side .sort( call(s) on the portal — a browser sort is not AI ranking`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §11 — AI QUOTE BUILDER (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // Every leg here subtracts EXTRACTQ. See the module header: `extract_quote` reads a price off a
  // document the supplier already wrote, which is the opposite of §11's premise.

  const builderFiles = filesNear(RECOMMEND, /quote|price|pricing/i, 400);
  await req(S11, 'qb-builder-surface', 'a quote-builder surface where AI proposes terms',
    B(builderFiles.length > 0),
    Q(`${builderFiles.length} file(s) pair recommendation language with quoting ` +
      `[${builderFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]; ` +
      `${extractTok} quote-EXTRACTION token(s) excluded — OCR of a quote the supplier wrote is not AI proposing one`));

  // NOT /ask/, and NOT over the wide file list. Both mistakes at once let ChatWidget.tsx — the
  // marketing chat bubble — answer for the portal a third time in this row. The intent must be
  // about QUOTING THIS PROJECT, and it must be found in the portal's own files.
  const nlIntent = filesNear(/i (want|would like) to quote|quote[_ ]?this[_ ]?(project|rfq)|help[_ ]?me[_ ]?quote|build[_ ]?(me[_ ]?)?a[_ ]?quote/i, /quote/i, 300, P_FILES);
  await req(S11, 'qb-nl-intent', 'a natural-language "I want to quote this project" entry',
    B(nlIntent.length > 0),
    Q(`${nlIntent.length} portal file(s) carry a natural-language quoting intent ` +
      `[${nlIntent.map(f => f.split('/').pop()).join(' ') || 'none'}] — the marketing chat bubble is excluded`));

  // The five things the AI proposes. Each needs a RECOMMENDATION context — a price INPUT the
  // supplier types is the thing §11 replaces, so `delivered()` alone would score the existing form.
  for (const [id, re, label] of [
    ['qb-recommend-price', /price/i, 'a recommended price'],
    ['qb-market-position', /market[_ ]?position|competitive|vs[_ ]?market|market[_ ]?rate/i, 'market position'],
    ['qb-delivery-estimate', /delivery[_ ]?(days|time|estimate|lead)|lead[_ ]?time/i, 'a delivery estimate'],
    ['qb-risk-level', /risk[_ ]?(level|score|rating)/i, 'a risk level'],
    ['qb-warranty-suggestion', /warrant(y|ies)/i, 'a suggested warranty'],
  ]) {
    // ── AND NEGOTIATION IS SUBTRACTED TOO, FOR THE SAME REASON EXTRACTION IS ────────────────────
    // On 8 Aug 2026 the §12 assistant was built and FOUR §11 legs flipped to MET off it —
    // qb-recommend-price, qb-delivery-estimate, qb-warranty-suggestion and qb-routine — because
    // `recommended_response` (a drafted REPLY) sits within 300 characters of the words price,
    // lead_time and warranty. Every one was false. That assistant explicitly REFUSES to recommend
    // a price, and the lead time and warranty it shows are the ones already ON the supplier's
    // quote, echoed back.
    //
    // §11's premise is that the supplier writes nothing and the AI proposes the terms. §12 reads a
    // quote the supplier has ALREADY written. Both live near the words "recommend" and "price", so
    // the negotiation vocabulary is excluded by name exactly as the extraction vocabulary is, and
    // both counts print so the exclusion stays auditable.
    const NEGOT = /negotiat|counter[_ ]?offer|discount|recommended[_ ]?response|price[_ ]?pressure|possible[_ ]?reduction/i;
    const recommended = filesNear(re, RECOMMEND, 300).filter((f) => !NEGOT.test(fileSrc(f)));
    const negFiltered = filesNear(re, RECOMMEND, 300).length - recommended.length;
    const typed = has(re, P);
    // ── THE RPC HOP, WHICH THIS FILE'S OWN HEADER WARNS ABOUT AND THIS LEG DID NOT APPLY ─────────
    // These five legs used raw fnsNear() — the edge tier only — while §10's legs twenty lines up
    // already used the rpc-aware servedNear(). §11's recommendation is a SQL routine reached by
    // rpc, and supplier_portal's quote_recommend action is a four-line passthrough carrying none of
    // the field names, so the scan reported "computed by [NO fn]" about a routine answering 200 on
    // production with a real median. Measured before this line was changed, not after.
    //
    // This loosens nothing, for the reason the header gives: RPC_NAMES comes from the .rpc('…')
    // calls in reachable edge functions. It also TIGHTENS the negotiation exclusion, which
    // previously could not reach an rpc routine at all — a routine full of negotiation vocabulary
    // was invisible rather than excluded, and is now read and excluded on the same rule as a file.
    const bodyOf = (nm) => { const hit = RPC.find(([n]) => n === nm); return hit ? hit[1] : fnSrc(nm); };
    const served = servedNear(re, RECOMMEND, 400).filter((f) => !NEGOT.test(bodyOf(f)));
    await req(S11, id, `the builder proposes ${label}`,
      B(recommended.length > 0 && served.length > 0),
      Q(`${label}: recommended on ${recommended.length} file(s), computed by [${served.join(' ') || 'NO fn'}]; ` +
        `${negFiltered} negotiation surface(s) excluded — reading back a quote the supplier already wrote ` +
        `is not proposing one; field present on the portal ${typed ? 'yes' : 'no'} — a field the supplier TYPES is what §11 replaces`));
  }

  // "quote near recommend" passed on messages_api — the messaging endpoint — because the two words
  // happen within 500 characters of each other there. A routine that PRODUCES a quote
  // recommendation has to produce the things §11 says it produces, so the leg requires the proposal
  // vocabulary itself (a price, a delivery estimate, a warranty) rather than the word "recommend".
  const PROPOSAL = /price|delivery[_ ]?(days|time|estimate)|warrant(y|ies)|market[_ ]?position/i;
  // Same exclusion as the five field legs above: the negotiation assistant pairs PROPOSAL words
  // with RECOMMEND words all day and proposes no quote at all.
  const QB_NEGOT = /negotiat|counter[_ ]?offer|discount|recommended[_ ]?response|price[_ ]?pressure|possible[_ ]?reduction/i;
  // Same rpc hop as the five field legs above, same reasoning, same preserved exclusions.
  const qbBody = (nm) => { const hit = RPC.find(([n]) => n === nm); return hit ? hit[1] : fnSrc(nm); };
  const qbFn = servedNear(PROPOSAL, RECOMMEND, 400).filter((f) => !QB_NEGOT.test(qbBody(f)));
  const looseQb = fnsNear(/quote/i, RECOMMEND, 500);
  await req(S11, 'qb-routine', 'a server routine produces the quote recommendation',
    B(qbFn.length > 0),
    Q(`${qbFn.length} fn(s) pair a PROPOSAL field with recommendation [${qbFn.join(' ') || 'none'}]; ` +
      `${looseQb.length} merely put "quote" near "recommend" [${looseQb.join(' ')}]; ` +
      `${fnsMatching(EXTRACTQ).length} perform quote EXTRACTION [${fnsMatching(EXTRACTQ).join(' ')}] — a different mechanism`));

  // Accepting the recommendation must create a REAL quote, not a draft in local state.
  const writesQuote = fnsNear(/quotes?\b/i, /insert|upsert|\.from\(\s*['"]quotes/i, 400);
  await req(S11, 'qb-writes-quote', 'accepting the recommendation creates a real quote',
    B(writesQuote.length > 0),
    Q(`${writesQuote.length} fn(s) write a quote row [${writesQuote.join(' ') || 'none'}]; ${ESTATE}`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §12 — AI NEGOTIATION ASSISTANT — RETIRED 21 SEP 2026
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // The founder removed negotiations from both portals (instruction 527). SupplierNegotiation.tsx
  // and the supplier_portal 'negotiation' action are deleted. Its seven requirements
  // (neg-assistant-surface, neg-detects-price-pressure, neg-current-margin, neg-possible-reduction,
  // neg-recommended-response, neg-response-actionable, neg-routine) retired WITH their subject. They
  // are not scored as missing, because building them again would contradict the ruling.
  // fn_supplier_negotiation still exists in the database; no surface calls it. The NEGOT / QB_NEGOT
  // exclusions in §11 above are kept: they guard the quote-builder legs against that routine's
  // vocabulary for as long as it remains in the estate.
}
