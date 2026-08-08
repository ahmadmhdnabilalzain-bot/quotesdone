// SPEC FILE #5, sections 7-8 — Product Intelligence System, AI Product Cards.
//
//   7. Product Intelligence (14) — seven upload formats, AI conversion, three counts, searchable
//   8. AI Product Cards      (9)  — every product becomes an intelligent, matchable object
//
// ── THIS IS THE SECTION THE BRIEF CALLED THE ROW'S HEADLINE DEFECT ───────────────────────────────
// Measured on production, and re-measured here rather than quoted: supplier_product,
// supplier_product_variant and supplier_catalog hold 0 rows AND have 0 readers — 0 by the \y regex
// scan and 0 by ilike, against a control where `leads` reads 137 by the same scan. A schema with no
// reader, no writer and no surface. §7's "245 products, 12,500 attributes, searchable" and all of
// §8 are NET-NEW BUILD, and no amount of onboarding changes that: a real supplier still has zero
// products until the extractor exists.
//
// The row counts are therefore printed beside every verdict but are NEVER the verdict. An empty
// table with a reader and a surface is a product waiting for data; an empty table with neither is
// an unbuilt feature. Only the second is a MISSING here, and the evidence has to make clear which
// one it saw so a future run against a populated estate reads the same verdict.
//
// ── THE INTRA-FILE VOCABULARY LEAK THIS MODULE IS MOST EXPOSED TO ────────────────────────────────
// Round 2 found the chrome fence is FILE-level and does not help when the wrong thing lives in the
// right file. §7 is the worst case for it: the supplier portal ALREADY uploads documents — trade
// licence, IBAN, EGR, Emirates ID, company profile, and columns literally named `catalogue_pdfs`
// and `catalog_doc_paths`. Those are REGISTRATION documents. A registration uploader is not a
// product-catalog ingestion pipeline, and `/catalog/i` cannot tell them apart.
//
// So every §7 upload leg subtracts the registration vocabulary explicitly and PRINTS BOTH COUNTS.
// A scan that quietly passed on the licence uploader would certify a product intelligence system
// that does not exist, which is the single most valuable false MET available in this spec.
import {
  S, P, FILES, FNS, fileSrc, fnSrc, n, has, filesMatching, fnsMatching, fnsWithBoth,
  near, delivered, cover, B, Q, READERS_SQL, NROWS_SQL, rpcSources,
} from '../supplier_checks.mjs';

export const EXPECTED = 23;

export default async function (H) {
  const { req, one } = H;
  const SEC7 = 'prod', SEC8 = 'card';

  // The registration document vocabulary — everything the portal uploads that is NOT a product
  // catalog. Subtracted from every §7 upload leg.
  const REGDOC = /trade[_ ]?licen[cs]e|licen[cs]e_doc|iban_doc|egr_doc|emirates[_ ]?id|company_profile_doc|signed_terms|vat_doc|insurance_doc|iso_doc|manufacturer_auth_doc/i;
  // A PRODUCT ingestion path names products, not compliance documents.
  const PRODUCTCTX = /product|catalog(ue)?[_ ]?(item|line|sku|import|ingest)|price[_ ]?list|sku\b/i;

  const regTok = n(REGDOC, P);
  const prodTok = n(PRODUCTCTX, P);

  // The serving population follows the rpc hop — see the long note in supplier_checks.mjs. §7's
  // three counts read "served by [NO fn]" while supplier_portal was serving them through
  // rpc('fn_supplier_products'), where the field names actually live. Same false MISSING §13 had.
  const RPC = await rpcSources(one);
  const servedBy = (re) => [...fnsMatching(re), ...RPC.filter(([, src]) => re.test(src)).map(([nm]) => nm)];

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §7 — PRODUCT INTELLIGENCE SYSTEM (14)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  // Defect class #3 — the spec enumerates SEVEN accepted formats, so each is its own requirement.
  // A format counts only where a PRODUCT context accompanies it in the same file: an <input
  // accept=".pdf"> on the trade-licence uploader is not "the supplier uploads product catalogs".
  const FORMATS = [
    ['catalog', /catalog(ue)?/i, 'catalogs'],
    ['pdf', /\.pdf\b|application\/pdf/i, 'PDFs'],
    ['excel', /\.xlsx?\b|spreadsheetml|application\/vnd\.ms-excel/i, 'Excel files'],
    ['bim', /\.ifc\b|\.rvt\b|\bBIM\b/i, 'BIM files'],
    ['cad', /\.dwg\b|\.dxf\b|\bCAD\b/i, 'CAD files'],
    ['images', /image\/\*|\.jpe?g\b|\.png\b|accept=["'][^"']*image/i, 'images'],
    ['pricelist', /price[_ ]?list|pricelist/i, 'price lists'],
  ];
  for (const [id, re, label] of FORMATS) {
    // The format named in a file that is ALSO about products — per-file, so the pairing is real and
    // not an artefact of concatenating the whole surface.
    const prodFiles = FILES.filter((f) => re.test(fileSrc(f)) && PRODUCTCTX.test(fileSrc(f)));
    const anyFiles = filesMatching(re);
    const regOnly = anyFiles.filter((f) => !prodFiles.includes(f) && REGDOC.test(fileSrc(f)));
    await req(SEC7, `prod-upload-${id}`, `the supplier can upload ${label} for product extraction`,
      B(prodFiles.length > 0),
      Q(`${label}: ${prodFiles.length} file(s) pair the format with a PRODUCT context ` +
        `[${prodFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]; ${anyFiles.length} mention it at all, ` +
        `${regOnly.length} only alongside registration documents — a licence uploader is not catalog ingestion`));
  }

  // The conversion itself. Requires an endpoint that both ingests a file AND produces product
  // structure, scored per function so a file-reader in one function cannot pair with a product
  // word in another.
  //
  // ── "INGESTS A FILE AND MENTIONS PRODUCTS" IS NOT AN EXTRACTOR ────────────────────────────────
  // That version passed 7 functions and every one was false. license_extract does read "COMPANY
  // PROFILE and/or PRODUCT CATALOG", but it returns `products:[string]` — a comma-separated list of
  // NAMES for the leads.products free-text column. supplier_api's `products` is that same leads
  // column being SELECTed. Neither creates a product record, and §7 asks for 245 products in 18
  // categories with 12,500 attributes, which is a structured store and not a text field.
  //
  // The refutable difference is the DESTINATION. An extractor writes structured product records;
  // a profile enricher writes a sentence. So the leg requires a reachable function that touches the
  // structured product store, and the free-text path is printed beside it so the evidence shows
  // exactly what exists instead — which is the honest answer to "is this built".
  //
  // ── READING THE PRODUCT STORE IS NOT CONVERTING A CATALOGUE INTO IT ──────────────────────────
  // Once fn_supplier_products shipped, this leg read MET on "supplier_portal touches the structured
  // product store" — and supplier_portal only READS it. §7's requirement is a CONVERSION: a
  // catalogue goes in, product records come out. A reader satisfying an extraction requirement is
  // a false MET of the most self-flattering kind, because the same commit that built the reader
  // would appear to have built the extractor.
  //
  // The gate is therefore a WRITE into the product store, paired with file ingestion in the same
  // function or routine. The reader is printed beside it so the evidence distinguishes "nothing
  // exists" from "the read path exists and the extractor does not" — which is the true state.
  const WRITE = /insert\s+into[^;]{0,80}supplier_(product|catalog)|\.from\(\s*['"]supplier_(product|catalog)[^)]*\)\s*\.\s*(insert|upsert)/i;
  const INGEST = /storage|file_b64|arrayBuffer|base64|ai_gateway|extract/i;
  const extractorFns = [
    ...FNS.filter((f) => WRITE.test(fnSrc(f)) && INGEST.test(fnSrc(f))),
    ...RPC.filter(([, src]) => WRITE.test(src)).map(([nm]) => nm),
  ];
  const readerFns = fnsMatching(/supplier_product|supplier_catalog|product_variant/i);
  await req(SEC7, 'prod-ai-extraction', 'a routine converts uploads into products',
    B(extractorFns.length > 0),
    Q(`${extractorFns.length} fn(s)/routine(s) WRITE the product store from an ingested file ` +
      `[${extractorFns.join(' ') || 'none'}]; ${readerFns.length} merely read it [${readerFns.join(' ')}] ` +
      `— a reader is not an extractor, and ${prodTok} product token(s) on the portal are not either`));

  // The three numbers §7's "After" panel draws. Empty tables, so the verdict is delivery and the
  // row count is printed beside it — never instead of it.
  const prodRows = await one(NROWS_SQL('supplier_product'));
  const varRows = await one(NROWS_SQL('supplier_product_variant'));
  for (const [id, re, label] of [
    ['prod-count-products', /product[_ ]?count|products[_ ]?total|\d+\s*products/i, 'product count'],
    ['prod-count-categories', /categor(y|ies)[_ ]?count|categories[_ ]?total/i, 'category count'],
    ['prod-count-attributes', /attribute[_ ]?count|specification[_ ]?count|attributes[_ ]?total|spec[_ ]?count/i, 'attribute count'],
  ]) {
    const shown = delivered(re);
    const served = servedBy(re);
    await req(SEC7, id, `the ${label} is surfaced to the supplier`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}]; ` +
        `supplier_product ${prodRows} row(s), variants ${varRows} — the verdict is the mechanism, not the rows`));
  }

  // "Searchable: YES" is a claim about a query path, not a checkbox. Needs a search affordance on
  // the supplier surface AND a product search on the server, per function.
  const searchUi = filesMatching(/search/i).filter((f) => PRODUCTCTX.test(fileSrc(f)));
  const searchFn = fnsWithBoth(/search|ilike|websearch|ts_query|tsvector|embedding/i, PRODUCTCTX);
  await req(SEC7, 'prod-searchable', 'products are searchable',
    B(searchUi.length > 0 && searchFn.length > 0),
    Q(`search UI in ${searchUi.length} product file(s) [${searchUi.map(f => f.split('/').pop()).join(' ') || 'none'}], ` +
      `product search in [${searchFn.join(' ') || 'NO fn'}]`));

  // Defect class #1, and the brief's named defect measured rather than repeated. A relation with a
  // schema and no reader is not a feature. Overloads collapsed, writers excluded by name pattern.
  const spReaders = await one(READERS_SQL('supplier_product'));
  const scReaders = await one(READERS_SQL('supplier_catalog'));
  const spFnReaders = fnsMatching(/supplier_product|supplier_catalog/i);
  await req(SEC7, 'prod-table-reader', 'supplier_product has a reader that is not its writer',
    B(Number(spReaders) > 0 || spFnReaders.length > 0),
    Q(`supplier_product: ${spReaders} non-writer SQL routine(s), ${spFnReaders.length} reachable edge fn(s) ` +
      `[${spFnReaders.join(' ') || 'none'}]; supplier_catalog: ${scReaders} routine(s); ${prodRows} row(s)`));

  // The delivery leg for the whole section: is product intelligence on the supplier's screen at all?
  //
  // A UI LABEL IS NOT A FEATURE. The first version matched `/product[_ ]?catalog/i` and its ONE hit
  // was the English string `catalogs_ph:'Product catalogs (up to 5):'` — an upload field's caption
  // inside a translations object. A caption naming a thing is the weakest possible evidence that
  // the thing is rendered, and it is exactly defect class #2: the label is the population standing
  // in for the delivery. The leg now requires CODE — the structured store named as an identifier,
  // or a product collection actually mapped into the DOM — and prints the label count separately.
  const prodCode = filesMatching(/supplier_product\b|products\s*\.map\(|productIntelligence|<ProductCard/);
  const prodLabels = n(/Product catalogs|catalogs_ph|catalogues/i, P);
  await req(SEC7, 'prod-supplier-visible', 'product intelligence renders on the supplier surface',
    B(prodCode.length > 0),
    Q(`${prodCode.length} of ${FILES.length} supplier file(s) carry product-intelligence CODE ` +
      `[${prodCode.map(f => f.split('/').pop()).join(' ') || 'none'}]; ${prodLabels} upload-caption token(s) — a caption is not a render`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §8 — AI PRODUCT CARDS (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // "Every product becomes intelligent." The card is ONE component, so defect class #3 applies in
  // its strict form: the eight fields are counted OVER THAT COMPONENT, not over the surface. A
  // category name rendered in a dropdown elsewhere is not a product card showing a category.

  const cardFiles = FILES.filter((f) => /product[_ ]?card|<ProductCard|function ProductCard/i.test(fileSrc(f)));
  await req(SEC8, 'card-component', 'a product card component exists',
    B(cardFiles.length > 0),
    Q(`${cardFiles.length} file(s) declare a product card [${cardFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // The card's own source. Empty string when the component is absent — and that is deliberate:
  // every field leg below then reads 0 legitimately, rather than matching something elsewhere on
  // the surface and certifying a card that does not exist. This is the componentSrc() lesson from
  // row #4, where slice(indexOf(...)) on an absent component returned the file's LAST CHARACTER and
  // made a missing component indistinguishable from a present one with no matches.
  const CARD = cardFiles.map(fileSrc).join('\n/*FILE*/\n');

  const CARD_FIELDS = [
    ['card-name', /name|title|model/i, 'product name'],
    ['card-category', /categor(y|ies)/i, 'category'],
    ['card-spec-attributes', /capacity|efficiency|spec|attribute|cfm\b|rating/i, 'spec attributes'],
    ['card-certifications', /certification|certified|iso/i, 'certifications'],
    ['card-availability', /available|in[_ ]?stock|qty|units?\b/i, 'availability'],
    ['card-compatible-projects', /compatible|suitable[_ ]?for|project[_ ]?type|applications?/i, 'compatible projects'],
    ['card-ai-match-pct', /match[_ ]?(pct|percent|score)|ai[_ ]?match/i, 'AI match %'],
  ];
  for (const [id, re, label] of CARD_FIELDS) {
    const onCard = CARD ? re.test(CARD) : false;
    const elsewhere = re.test(P);
    await req(SEC8, id, `the product card shows ${label}`,
      B(onCard),
      Q(`${label}: on the card ${onCard ? 'yes' : 'NO'} (card component ${cardFiles.length ? 'exists' : 'ABSENT, so every field leg is 0'}); ` +
        `mentioned elsewhere on the portal ${elsewhere ? 'yes' : 'no'} — elsewhere is not on the card`));
  }

  // The match percentage must be COMPUTED, not a literal. Defect class #4 in spirit: a number
  // hardcoded in JSX satisfies no requirement. Scored per function over the server.
  //
  // §8's match is a PRODUCT match — "AHU Model X500 … AI Match 96%" — and the estate's matching is
  // capability-level: fn_match_capability scores a SUPPLIER against an inquiry. Passing this on
  // those routines would count an existing, unrelated mechanism as evidence for an unbuilt one, and
  // would keep reading MET no matter how long §8 stayed missing. The leg therefore requires the
  // match to involve products, and prints the capability-matching estate beside it so the evidence
  // shows what does exist. Satisfiable: a correct §8 implementation has exactly this routine.
  // fnsWithBoth is TOO LOOSE for a function the size supplier_portal has grown to: it now serves
  // nine actions, so an inquiry-level match in one action pairs with the word product in another
  // and certifies a PRODUCT matcher that does not exist. Windowed within the function instead, and
  // the rpc'd routines are searched too so a matcher living in SQL still counts.
  //
  // AND READING A STORED MATCH IS NOT COMPUTING ONE. The previous version passed on
  // fn_supplier_products because that routine SELECTS `attributes ->> 'ai_match'` — a passthrough
  // of whatever an extractor might one day have written. Proven at the same time: 0 of 4 products
  // carry an ai_match and there are 0 inquiries to match against. A read of an always-null key
  // cannot be the mechanism §8 asks for.
  //
  // A computation leaves a trace a passthrough cannot: vector distance, a similarity call, or
  // arithmetic producing the score. That is what is required, alongside a product subject.
  const MATCHRE = /match[_ ]?(pct|percent|score)|ai[_ ]?match/i;
  const COMPUTES = /similarity\s*\(|<=>|<->|cosine|embedding|\bscore\s*[:=][^;]{0,40}[*+\/]|round\s*\([^)]{0,60}[*+]/i;
  const productMatchFn = [
    ...FNS.filter((f) => near(fnSrc(f), MATCHRE, PRODUCTCTX, 200) && COMPUTES.test(fnSrc(f))),
    ...RPC.filter(([, src]) => near(src, MATCHRE, /product|sku|catalog/i, 200) && COMPUTES.test(src)).map(([nm]) => nm),
  ];
  const anyMatchFn = fnsMatching(/match[_ ]?(pct|percent|score)|fn_match|similarity|embedding/i);
  const matchSql = await one(`select count(distinct p.proname) from pg_proc p
    join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public' and p.prokind in ('f','p')
      and p.proname ~* 'match|similar'`);
  await req(SEC8, 'card-match-routine', 'the product match percentage is computed server-side',
    B(productMatchFn.length > 0),
    Q(`${productMatchFn.length} reachable fn(s) match on PRODUCTS [${productMatchFn.join(' ') || 'none'}]; ` +
      `${anyMatchFn.length} match on anything [${anyMatchFn.join(' ')}], ${matchSql} matching routine(s) in public ` +
      `— capability-level supplier matching is a different mechanism and is scored elsewhere`));
}
