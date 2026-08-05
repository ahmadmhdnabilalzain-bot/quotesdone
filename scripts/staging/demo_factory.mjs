// demo_factory.mjs — the demo-data factory for staging.
//
// THE RULE (session 9): anything that needs data to be tested gets demo data built for it,
// asserted against, and deleted afterwards. Production has 0 customers, 0 inquiries and 0 quotes,
// so demo data is the only way to prove anything.
//
// This module exists because journey_test.mjs was the only end-to-end demo-data creator in the
// repo and every helper inside it was a private top-level const. standUpSupplier() returned
// {ok, detail} and threw away the supplier's id, email and JWT, so a caller could make a supplier
// but never ACT AS it. The 18-column supplier_capabilities INSERT was written out twice, verbatim.
//
// Three things this fixes, all of them measured failures:
//
//   1. TEARDOWN BY TAG, NOT BY GUESSWORK. journey_test deleted auth users, 'Journey Test %' leads
//      and a HAND-LISTED set of storage paths. Everything else survived: 65 customers rows (every
//      single one an orphan whose auth user was already gone), 41 inquiries, 24 dangling documents,
//      118 signed-terms PDFs. Here every row a run creates carries the run tag, and teardown
//      derives the storage paths FROM THE DATABASE rather than from a list someone maintained.
//
//   2. try/finally. journey_test is a bare linear file, so a mid-run throw leaks everything. The
//      15 orphaned auth users in staging are the proof it already happened. withRun() below
//      tears down on the way out of a throw.
//
//   3. VARIETY. Twelve identically-scored suppliers make every later supplier structurally
//      invisible to matching. TRADES below carries all 25 taxonomy_trade codes and the corpus
//      builder spreads products_norm across them on a deterministic ladder, because products_norm
//      overlap - not leads.rating - is the score dial that actually works (see §2.4 of the brief:
//      supplier_perf prefers app_rating, and quote_rate overrides perf_score the moment
//      matched > 0, so a rating-spread corpus collapses on its second run).
//
// Usage as a module:
//     import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote } from './demo_factory.mjs';
//     await withRun(async (run) => {
//       const cust = await makeCustomer(run);          // { id, email, jwt, customerId }
//       const sup  = await makeSupplier(run, { trade: 'aluminium' });
//       ...assert...
//     });                                              // teardown runs even if the body throws
//
// Usage as a CLI:
//     node scripts/staging/demo_factory.mjs --selftest    create, assert, tear down, prove the
//                                                         database returned to its exact baseline
//     node scripts/staging/demo_factory.mjs --purge       delete the accumulated litter
//     node scripts/staging/demo_factory.mjs --purge --dry-run
//     node scripts/staging/demo_factory.mjs --corpus 100  build a matching corpus (add --keep)
import { assertNotProduction, mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { readFileSync } from 'node:fs';
import { randomBytes, createHmac } from 'node:crypto';

export const REF = assertNotProduction(
  process.env.QD_STAGING_REF || 'pglpqrhvozwepymcuunn', 'demo factory');
export const BASE = `https://${REF}.supabase.co`;

// ---- SQL literals ----------------------------------------------------------------------------
// Every value that reaches the database goes through one of these. A demo fixture that carries an
// apostrophe (an Arabic transliteration, a company name like "Al Reem Ali's") must not be able to
// end a string literal.
export const q = (v) => (v === null || v === undefined) ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
export const num = (v) => (v === null || v === undefined || v === '') ? 'null' : String(Number(v));
export const arr = (a) => (Array.isArray(a) && a.length) ? `ARRAY[${a.map(q).join(',')}]::text[]` : `'{}'::text[]`;
export const jb = (o) => (o === null || o === undefined) ? 'null' : `${q(JSON.stringify(o))}::jsonb`;
export const bool = (v) => (v === null || v === undefined) ? 'null' : (v ? 'true' : 'false');

// ---- staging api keys ------------------------------------------------------------------------
let _keys = null;
export async function keys() {
  if (_keys) return _keys;
  const mgmt = (process.env.SUPABASE_ACCESS_TOKEN
    || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`,
    { headers: { Authorization: 'Bearer ' + mgmt } });
  const k = await r.json();
  const ANON = k.find((x) => x.name === 'anon')?.api_key;
  const SERVICE = k.find((x) => x.name === 'service_role')?.api_key;
  if (!ANON || !SERVICE) throw new Error('could not read staging api keys');
  _keys = { ANON, SERVICE };
  return _keys;
}

export async function call(slug, jwt, body, timeoutMs = 90000) {
  const { ANON } = await keys();
  try {
    const r = await fetch(`${BASE}/functions/v1/${slug}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: 'Bearer ' + (jwt || ANON), 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* a non-JSON body is itself the finding */ }
    return { status: r.status, json, text: text.slice(0, 200).replace(/\s+/g, ' ') };
  } catch (e) {
    return { status: 0, json: null, text: String(e.message).slice(0, 200) };
  }
}

// ---- the trade vocabulary --------------------------------------------------------------------
// These 25 codes are public.taxonomy_trade.code, which is what fn_match_capability's `cand` CTE
// gates on (sc.trades && p_trades) and what its req_auth CTE reads authority_required from. They
// are NOT catalog_supplier_categories.slug (86 rows, a different vocabulary) - conflating the two
// is why a capability fixture can pass every visible check and still match nothing.
//
// Three trades carry a mandatory authority: a capability row without that key in
// authority_approvals is dropped by the `not exists (... where not (sc.authority_approvals ? a))`
// gate, silently and before scoring.
export const AUTHORITY = {
  electrical: 'electrical_utility',
  fire_fighting: 'civil_defence',
  security_systems: 'sira',
};

export const TRADES = {
  aluminium: { name: 'Aluminium & Cladding', products: ['aluminium windows', 'aluminium doors', 'curtain walling', 'cladding', 'louvres', 'powder coated profiles', 'thermal break profiles', 'sliding systems'], brands: ['Technal', 'Schueco', 'Alumil'] },
  av_it: { name: 'AV & IT Systems', products: ['structured cabling', 'av distribution', 'projectors', 'led video wall', 'conference room av', 'pa system', 'network switches', 'cctv cabling'], brands: ['Crestron', 'Extron', 'Bosch'] },
  civil_works: { name: 'Civil Works', products: ['concrete works', 'blockwork', 'plastering', 'excavation', 'shoring', 'screed', 'rebar fixing', 'formwork'], brands: ['Doka', 'Peri'] },
  cleaning: { name: 'Cleaning Services', products: ['deep cleaning', 'facade cleaning', 'post construction cleaning', 'disinfection', 'housekeeping', 'carpet cleaning', 'pest control', 'waste removal'], brands: ['Karcher', 'Diversey'] },
  doors: { name: 'Doors & Windows', products: ['wooden doors', 'fire rated doors', 'automatic sliding doors', 'upvc windows', 'aluminium windows', 'glass doors', 'door hardware', 'roller shutters'], brands: ['Assa Abloy', 'Dorma', 'Hormann'] },
  electrical: { name: 'Electrical', products: ['db panels', 'cable trays', 'lv panels', 'light fittings', 'wiring accessories', 'earthing system', 'diesel generator', 'busbar trunking'], brands: ['Schneider', 'ABB', 'Legrand'] },
  elevators: { name: 'Elevators & Escalators', products: ['passenger lift', 'service lift', 'escalator', 'dumbwaiter', 'platform lift', 'lift modernisation', 'lift amc', 'travelator'], brands: ['Otis', 'Kone', 'Schindler'] },
  fire_fighting: { name: 'Fire Fighting', products: ['fire alarm panel', 'sprinkler system', 'fm200 system', 'fire extinguisher', 'smoke detector', 'hose reel', 'fire pump', 'emergency lighting'], brands: ['Notifier', 'Tyco', 'Honeywell'] },
  flooring: { name: 'Flooring', products: ['porcelain tiles', 'vinyl flooring', 'epoxy flooring', 'marble flooring', 'parquet', 'carpet tiles', 'raised access floor', 'skirting'], brands: ['Tarkett', 'RAK Ceramics', 'Interface'] },
  glazing: { name: 'Glass & Glazing', products: ['double glazed units', 'tempered glass', 'laminated glass', 'glass partitions', 'shower screens', 'mirrors', 'frameless glass', 'spider glazing'], brands: ['Guardian', 'Saint-Gobain', 'Emirates Glass'] },
  gypsum: { name: 'Gypsum & Ceilings', products: ['gypsum board partitions', 'false ceiling', 'acoustic ceiling', 'drywall', 'bulkheads', 'gypsum cornice', 'metal stud framing', 'access panels'], brands: ['Knauf', 'Gyproc', 'Armstrong'] },
  hvac: { name: 'HVAC', products: ['fan coil unit', 'air handling unit', 'ducting', 'vrf system', 'split ac', 'chiller', 'ventilation fans', 'duct insulation'], brands: ['Daikin', 'Carrier', 'Trane'] },
  interior_fitout: { name: 'Interior Fit-Out', products: ['fit out works', 'joinery fitout', 'partitions', 'ceiling works', 'painting works', 'flooring works', 'mep fitout', 'turnkey fitout'], brands: ['Vitra', 'Herman Miller'] },
  joinery: { name: 'Joinery & Carpentry', products: ['kitchen cabinets', 'wardrobes', 'reception desk', 'wall panelling', 'joinery doors', 'veneer works', 'solid surface counters', 'custom furniture'], brands: ['Blum', 'Hettich', 'Egger'] },
  landscaping: { name: 'Landscaping & Pools', products: ['soft landscaping', 'hard landscaping', 'irrigation system', 'swimming pool', 'water features', 'pergola', 'artificial grass', 'outdoor lighting'], brands: ['Hunter', 'Rain Bird', 'Pentair'] },
  mep_general: { name: 'MEP (combined)', products: ['mep works', 'plumbing works', 'electrical works', 'hvac works', 'fire fighting works', 'drainage', 'bms', 'elv systems'], brands: ['Schneider', 'Siemens'] },
  painting: { name: 'Painting & Finishes', products: ['interior painting', 'exterior painting', 'decorative finishes', 'epoxy paint', 'texture coating', 'waterproof paint', 'spray painting', 'wood coating'], brands: ['Jotun', 'Dulux', 'National Paints'] },
  plumbing: { name: 'Plumbing & Sanitary', products: ['sanitary ware', 'ppr pipes', 'drainage pipes', 'water heater', 'booster pumps', 'water tank', 'upvc pipes', 'valves and fittings'], brands: ['Grohe', 'Geberit', 'Duravit'] },
  scaffolding: { name: 'Scaffolding & Access', products: ['scaffolding rental', 'cuplock scaffolding', 'mobile tower', 'shoring props', 'safety nets', 'ladder access', 'formwork panels', 'edge protection'], brands: ['Layher', 'Doka'] },
  security_systems: { name: 'Security Systems', products: ['cctv cameras', 'access control', 'video intercom', 'road barriers', 'turnstiles', 'intruder alarm', 'nvr recorder', 'sira compliant cctv'], brands: ['Hikvision', 'Axis', 'Dahua'] },
  signage: { name: 'Signage & Printing', products: ['acrylic signage', 'led signage', '3d letters', 'vinyl printing', 'banners', 'wayfinding signage', 'digital printing', 'pylon sign'], brands: ['3M', 'Avery Dennison'] },
  steel: { name: 'Steel Fabrication', products: ['structural steel', 'steel fabrication', 'handrails', 'steel staircase', 'gates', 'mezzanine floor', 'ms fabrication', 'ss railing'], brands: ['Emirates Steel', 'Conares'] },
  upholstery: { name: 'Upholstery & Soft Furnishing', products: ['sofa upholstery', 'curtains', 'blinds', 'cushions', 'headboards', 'fabric supply', 'majlis seating', 'loose furniture'], brands: ['Kvadrat', 'Silent Gliss'] },
  wallpaper: { name: 'Wall Finishes', products: ['wallpaper supply', 'wall panels', '3d wall panels', 'wall murals', 'fabric wall covering', 'acoustic wall panels', 'wall cladding', 'decorative film'], brands: ['Vescom', 'Omexco'] },
  waterproofing: { name: 'Waterproofing & Insulation', products: ['bituminous membrane', 'liquid waterproofing', 'pu coating', 'basement tanking', 'roof waterproofing', 'wet area waterproofing', 'thermal insulation', 'vapour barrier'], brands: ['Sika', 'Fosroc', 'BASF'] },
};
export const TRADE_CODES = Object.keys(TRADES);

export const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain'];
export const PROJECT_TYPES = [['villa', 'residential'], ['commercial', 'office'], ['hotel', 'hospitality'],
  ['industrial', 'warehouse'], ['retail', 'mall']];

// roles are CODES from public.taxonomy_role, not needs. fn_match_capability requires a
// taxonomy_role row whose code appears in sc.roles AND whose column for p_need is true:
// executes -> contractor | installer | maintenance | turnkey_fitout
// supplies -> contractor | distributor | manufacturer | supplier | turnkey_fitout
// whole_scope -> turnkey_fitout only
export const ROLE_SETS = {
  both: ['contractor', 'installer', 'supplier'],
  executes_only: ['installer', 'maintenance'],
  supplies_only: ['supplier', 'distributor', 'manufacturer'],
  turnkey: ['turnkey_fitout'],
};

// ---- run -------------------------------------------------------------------------------------
// Every row a run creates carries the tag. customers and leads carry it in columns that survive
// independently of each other, because the reason 62 customers rows outlived their suppliers is
// that customers.full_name was 'Journey Test Customer' for journey rows and NULL for smoke rows,
// so no single predicate could find them all.
//
//   auth.users / customers / inquiry_intake / email_verifications -> email `qd-<tag>-...@example.com`
//   leads                                                          -> tags @> {qd_demo, qd_run:<tag>}
//   inquiries                                                      -> provenance->>'qd_run'
//   quotes / supplier_capabilities / documents / storage objects    -> reached through their parents
export function newRun(opts = {}) {
  const tag = (opts.tag || randomBytes(4).toString('hex')).toLowerCase();
  if (!/^[a-z0-9]{4,16}$/.test(tag)) throw new Error(`bad run tag ${JSON.stringify(tag)}`);
  return {
    tag,
    ref: REF,
    base: BASE,
    keep: !!opts.keep,
    quiet: !!opts.quiet,
    seq: 0,
    authUsers: [],          // ids we created through the auth admin API
    log: (...a) => { if (!opts.quiet) console.log(...a); },
  };
}

export const runEmail = (run, kind) => `qd-${run.tag}-${kind}${run.seq++}@example.com`;
export const RUN_TAG_COL = (tag) => `'qd_run:${tag}'`;

/**
 * Run `fn` against a fresh tagged run and ALWAYS tear it down, including on a throw.
 * This is the whole reason the module exists: the 15 orphaned auth users in staging came from a
 * mid-run throw in a script that had no finally.
 */
export async function withRun(fn, opts = {}) {
  const run = newRun(opts);
  run.log(`demo run ${run.tag} on ${REF}`);
  try {
    return await fn(run);
  } finally {
    if (run.keep) run.log(`run ${run.tag} KEPT (teardown skipped) - tear down later with --purge`);
    else {
      const t = await teardown(run);
      run.log(`run ${run.tag} torn down: ${t.summary}`);
    }
  }
}

// ---- auth ------------------------------------------------------------------------------------
export async function mkAuthUser(run, email) {
  const { ANON, SERVICE } = await keys();
  const password = 'Demo-' + randomBytes(8).toString('hex') + 'A1!';
  const c = await fetch(`${BASE}/auth/v1/admin/users`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  const cu = await c.json();
  if (!cu.id) throw new Error(`auth create failed for ${email}: ${JSON.stringify(cu).slice(0, 200)}`);
  run.authUsers.push(cu.id);
  const t = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const tok = await t.json();
  return { id: cu.id, email, password, jwt: tok.access_token ?? null };
}

async function deleteAuthUsersByTag(tag) {
  const { SERVICE } = await keys();
  const rows = await mgmtRead(REF,
    `select id from auth.users where email like 'qd-${tag}-%@example.com'`);
  let n = 0;
  for (const r of rows) {
    const d = await fetch(`${BASE}/auth/v1/admin/users/${r.id}`, {
      method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
    });
    if (d.ok) n++;
  }
  return n;
}

// ---- customers -------------------------------------------------------------------------------
/**
 * makeCustomer(run, opts) -> { id, email, jwt, customerId, locale }
 *
 * mode 'sql'  (default): auth-admin identity + a direct customers INSERT. Zero model calls, zero
 *                        Edge Function calls. This is the bulk path.
 * mode 'api'            : the real journey - kyc save_customer, the OTP round trip through
 *                        login_otp, and kyc accept_terms (which writes a signed-terms PDF).
 *                        Still zero MODEL calls; kyc does not use the gateway.
 */
export async function makeCustomer(run, opts = {}) {
  const mode = opts.mode || 'sql';
  const email = opts.email || runEmail(run, 'cust');
  const locale = opts.locale || 'en';
  const fullName = opts.full_name || (locale === 'ar' ? 'عميل تجريبي' : 'Demo Customer');
  const phone = opts.phone || '+9715' + String(10000000 + Math.floor(Math.random() * 8999999));
  const u = await mkAuthUser(run, email);

  if (mode === 'api') {
    await call('kyc', u.jwt, { action: 'save_customer', user_kind: 'customer', email, full_name: fullName, phone });
    if (opts.verified !== false) await verifyEmailByOtp(email, 'customer');
    if (opts.terms !== false) await call('kyc', u.jwt, { action: 'accept_terms', user_kind: 'customer', email });
    if (locale !== 'en') {
      await mgmtWrite(REF, `update public.customers set locale=${q(locale)} where id=${q(u.id)}`, 'customer locale');
    }
  } else {
    // tos_version is read from app_secrets by kyc so the acceptance records WHICH document was
    // signed; the SQL path records the same version rather than inventing one.
    await mgmtWrite(REF,
      `insert into public.customers (id, email, full_name, phone, email_verified, locale
         ${opts.terms === false ? '' : ', tos_accepted_at, tos_version'})
       values (${q(u.id)}, ${q(email)}, ${q(fullName)}, ${q(phone)},
               ${bool(opts.verified !== false)}, ${q(locale)}
         ${opts.terms === false ? '' : `, now(), (select value from public.app_secrets where key='customer_terms_version')`})
       on conflict (id) do update set email=excluded.email, full_name=excluded.full_name`,
      'demo customer');
  }
  const row = (await mgmtRead(REF, `select id from public.customers where id=${q(u.id)}`))[0];
  if (!row) throw new Error(`customers row not created for ${email}`);
  return { id: u.id, customerId: u.id, email, jwt: u.jwt, password: u.password, locale, full_name: fullName };
}

/**
 * The OTP hop, exactly as journey_test does it: login_otp stores an HMAC of the code and never the
 * code, and staging cannot receive mail (email_enabled is forced off), so we write the row with a
 * code we chose, hashed the way login_otp hashes it, then verify through the REAL endpoint. Hash
 * comparison, expiry, purpose, single-use and the customers.email_verified write are all genuinely
 * exercised; only the delivery hop is skipped.
 */
export async function verifyEmailByOtp(email, userKind = 'customer', code = '424242') {
  const key = (await mgmtRead(REF, "select value from public.app_secrets where key='otp_hmac_key'"))[0]?.value;
  if (!key) throw new Error('otp_hmac_key missing from staging app_secrets');
  const hash = createHmac('sha256', key).update(code).digest('hex');
  await mgmtWrite(REF,
    `insert into public.email_verifications (email, token_hash, purpose, user_kind, expires_at)
     values (${q(email)}, ${q(hash)}, 'login', ${q(userKind)}, now() + interval '10 minutes')`, 'seed otp');
  return call('login_otp', null, { action: 'verify', identifier: email, code, user_kind: userKind });
}

// ---- suppliers -------------------------------------------------------------------------------
/**
 * The capability profile for one supplier, parameterised by trade and by a variant index.
 *
 * The variant ladder is the point. fn_match_capability scores
 *     w_prod * product_hits/|p_products|  (40)
 *   + w_brand * brand_hit                 (20)
 *   + w_ptype * ptype_hit                 (15)
 *   + w_track * track                     (15)
 *   + w_size  * (size_known ? 1 : 0.5)    (10)
 * so with brands and project_type left out of the query, and track 0 on a fresh corpus, score is a
 * pure function of how many of the query's products the supplier declares. Variant 0 declares all
 * of them, the last variant declares NONE of them and leaves min/max_project_value null, which is
 * the 5-point floor case the relevance floor is supposed to discard.
 */
export function capabilityProfile(trade, variant = 0, variants = 1, opts = {}) {
  const t = TRADES[trade];
  if (!t) throw new Error(`unknown trade ${trade} (expected one of taxonomy_trade.code)`);
  const decoyTrade = TRADE_CODES[(TRADE_CODES.indexOf(trade) + 7) % TRADE_CODES.length];
  // `flat` gives every supplier the full product list, so they all clear match_relevance_floor.
  // That is what a fan-out test needs: the ladder deliberately puts only 2 of 4 above the floor,
  // which can never exercise a cap of 5.
  const isDecoy = !opts.flat && variants >= 3 && variant === variants - 1;

  // Two products dropped per rung, and the last rung of a 3+ ladder is a zero-overlap decoy. With
  // the default 8 products and 4 variants that is 8, 6, 4 and 0 matching products, so a query using
  // all 8 scores 50, 40, 30 and 5 - two clearly above the match_relevance_floor of 35, one clearly
  // below it, and one on the w_size*0.5 floor. No rung lands ON 35, so a floor test never depends
  // on whether the comparison is > or >=.
  const keep = opts.flat ? t.products.length : Math.max(1, t.products.length - variant * 2);
  const products = isDecoy ? TRADES[decoyTrade].products.slice(0, 4) : t.products.slice(0, keep);
  const auth = AUTHORITY[trade];
  return {
    trades: [trade],
    // Roles are a GATE, not a score term, so they are uniform unless a caller asks otherwise.
    // Varying them "for realism" silently changes eligibility: the first cut of this file gave
    // every 4th supplier supplies_only roles, which is exactly the decoy slot, so the decoy was
    // dropped by the role gate and never reached the relevance floor it was built to test. Vary
    // the score dial (products_norm); hold the gates still.
    roles: ROLE_SETS[opts.roleSet] || ROLE_SETS.both,
    products_norm: products,
    project_types: PROJECT_TYPES[variant % PROJECT_TYPES.length],
    brands: t.brands.slice(0, 1 + (variant % t.brands.length)),
    coverage_emirates: EMIRATES.slice(0, 1 + (variant % 3)),
    // A mandatory authority missing from authority_approvals drops the row before scoring, so the
    // fixture holds it for regulated trades. The decoy deliberately still holds it: its low score
    // must come from products, not from being silently gated out for a different reason.
    authority_approvals: auth ? { [auth]: { ref: `DEMO-${auth.toUpperCase()}-${variant}`, valid_until: '2027-12-31' } } : {},
    min_project_value: isDecoy ? null : [1000, 25000, 100000, 250000][variant % 4],
    max_project_value: isDecoy ? null : [500000, 2000000, 5000000, 20000000][variant % 4],
    completeness: isDecoy ? 55 : 95 - variant * 5,
  };
}

const capabilityInsert = (leadId, p) => `insert into public.supplier_capabilities
   (supplier_id, trades, roles, products_norm, project_types, brands, exclusions,
    authority_approvals, source_docs, confidence, missing_fields, excluded_trades,
    completeness, review_status, confirmed_at, extracted_at,
    min_project_value, max_project_value, coverage_emirates)
 values (${num(leadId)}, ${arr(p.trades)}, ${arr(p.roles)}, ${arr(p.products_norm)},
   ${arr(p.project_types)}, ${arr(p.brands)}, '{}'::text[],
   ${jb(p.authority_approvals)}, '{}'::jsonb, '{"overall":0.9}'::jsonb,
   '{}'::text[], '{}'::text[],
   ${num(p.completeness)}, 'confirmed', now(), now(),
   ${num(p.min_project_value)}, ${num(p.max_project_value)}, ${arr(p.coverage_emirates)})
 on conflict (supplier_id) do update
   set trades=excluded.trades, roles=excluded.roles, products_norm=excluded.products_norm,
       project_types=excluded.project_types, brands=excluded.brands,
       authority_approvals=excluded.authority_approvals,
       min_project_value=excluded.min_project_value, max_project_value=excluded.max_project_value,
       coverage_emirates=excluded.coverage_emirates,
       completeness=excluded.completeness, review_status='confirmed', confirmed_at=now()`;

/**
 * makeSupplier(run, opts) -> { leadId, id, email, jwt, companyName, trade, profile }
 *
 * Returns the WHOLE identity, which standUpSupplier() did not: a caller can now make a supplier and
 * then act as it (inbox, submit_quote, extract_quote) instead of only asserting that it exists.
 *
 * mode 'sql' (default): auth-admin identity + one leads INSERT + one supplier_capabilities INSERT.
 *                       Zero model calls.
 * mode 'api'          : create_company -> save_profile -> accept_terms -> approve -> enrich_capability.
 *                       Costs 2 billable model calls (profile_ai on save_profile, enrich_capability);
 *                       supplier_review resolves to use_llm:false and is a free no-op.
 *
 * license_doc_path is left NULL on the SQL path ON PURPOSE. trg_leads_a_licence_gate fires BEFORE
 * INSERT, and a row inserted as approved/verified carrying a license_doc_path with a null
 * trade_license_no is rewritten to approval_status='action_required', which fails fn_is_matchable,
 * which drops the supplier out of fn_match_capability's cand CTE. A bulk corpus built that way is
 * invisible and looks like a matching bug. Use makeLicenceGatedSupplier() when you WANT that state.
 */
export async function makeSupplier(run, opts = {}) {
  const trade = opts.trade || 'aluminium';
  const t = TRADES[trade];
  if (!t) throw new Error(`unknown trade ${trade}`);
  const mode = opts.mode || 'sql';
  const variant = opts.variant ?? 0;
  const profile = opts.profile || capabilityProfile(trade, variant, opts.variants ?? 1);
  const email = opts.email || runEmail(run, 'sup');
  const companyName = opts.company_name || `QD Demo ${t.name} ${run.tag.slice(0, 4)}-${run.seq}`;
  const emirate = opts.emirate || profile.coverage_emirates[0] || 'Dubai';
  const withAuth = opts.withAuth !== false;

  const u = withAuth ? await mkAuthUser(run, email) : { id: null, email, jwt: null, password: null };

  let leadId = null;
  if (mode === 'api') {
    const c = await call('supplier_api', u.jwt, {
      action: 'create_company', company_name: companyName, emirate, role: 'supplier',
    });
    leadId = c.json?.id ?? null;
    if (!leadId) throw new Error(`create_company failed: HTTP ${c.status} ${c.text}`);
    await call('supplier_api', u.jwt, {
      action: 'save_profile',
      products: profile.products_norm.join(', '),
      services: `Supply and installation of ${t.name.toLowerCase()}.`,
      description: `${t.name} specialist serving ${profile.coverage_emirates.join(', ')}.`,
      company_type: 'LLC', contact_name: 'Demo Contact', phone: '+971505550000',
      service_emirates: profile.coverage_emirates,
    });
    await call('kyc', u.jwt, { action: 'accept_terms', user_kind: 'supplier', email });
    // The approval UPDATE deliberately excludes license_doc_path / trade_license_no /
    // license_expiry: trg_leads_a_licence_gate is UPDATE OF those three columns, so an UPDATE that
    // does not name them short-circuits the gate. Match case-insensitively - the API lowercases
    // claimed_by before storing it.
    await mgmtWrite(REF,
      `update public.leads
          set approval_status='approved', verified=true,
              tags = (select array(select distinct unnest(coalesce(tags,'{}'::text[])
                       || ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[])))
        where lower(claimed_by)=lower(${q(email)})`, 'approve demo supplier');
    if (opts.enrich !== false) {
      const cred = await internalCred();
      if (cred) await call('enrich_capability', null, { __secret: cred, lead_id: leadId });
    }
  } else {
    const ins = await mgmtWrite(REF,
      `insert into public.leads
         (company_name, emirate, city, claimed, claimed_by, email, contact_name, phone,
          company_type, products, services, description, service_emirates, source,
          verified, approval_status, owner_email_verified, accepted_terms_at, locale, tags)
       values (${q(companyName)}, ${q(emirate)}, ${q(emirate)}, ${bool(withAuth)},
               ${withAuth ? q(email) : 'null'}, ${q(email)}, 'Demo Contact',
               ${q('+9714' + String(1000000 + Math.floor(Math.random() * 8999999)))},
               'LLC', ${q(profile.products_norm.join(', '))},
               ${q(`Supply and installation of ${t.name.toLowerCase()}.`)},
               ${q(`${t.name} specialist serving ${profile.coverage_emirates.join(', ')}.`)},
               ${arr(profile.coverage_emirates)}, 'demo_factory',
               true, 'approved', true, now(), ${q(opts.locale || 'en')},
               ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[])
       returning id`, 'demo supplier');
    leadId = ins?.[0]?.id ?? null;
    if (!leadId) throw new Error(`leads insert returned no id for ${companyName}`);
  }

  if (opts.capability === 'agent') await confirmCapability(leadId, profile);
  else if (opts.capability !== false) await mgmtWrite(REF, capabilityInsert(leadId, profile), 'demo capability');
  // The API path stamps the tag in its approval UPDATE; the SQL path stamps it in the INSERT.
  // Belt and braces for the api path where create_company may have raced the update.
  await mgmtWrite(REF,
    `update public.leads set tags = (select array(select distinct unnest(coalesce(tags,'{}'::text[])
       || ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[]))) where id=${num(leadId)}`, 'tag demo supplier');

  return {
    leadId, id: leadId, email, jwt: u.jwt, password: u.password, authUserId: u.id,
    companyName, trade, profile, emirate,
  };
}

/**
 * A supplier that the licence gate REFUSES: evidence exists (license_doc_path) but the licence
 * number is missing, so fn_supplier_licence_gate fails and fn_leads_licence_gate_rerun rewrites
 * approval_status to 'action_required' on the way in. This is the exception-window fixture, and it
 * works with pricing_config still empty because the gate runs in the trigger, not in supplier_api.
 */
export async function makeLicenceGatedSupplier(run, opts = {}) {
  const s = await makeSupplier(run, { ...opts, capability: opts.capability !== false });
  await mgmtWrite(REF,
    `update public.leads
        set license_doc_path = ${q(opts.license_doc_path || `supplier-docs/demo/${run.tag}/licence.pdf`)},
            trade_license_no = ${q(opts.trade_license_no ?? null)},
            license_expiry   = ${opts.license_expiry ? q(opts.license_expiry) : 'null'}
      where id = ${num(s.leadId)}`, 'open licence gate');
  const row = (await mgmtRead(REF,
    `select approval_status, licence_gate_reason from public.leads where id=${num(s.leadId)}`))[0];
  return { ...s, approval_status: row?.approval_status, licence_gate_reason: row?.licence_gate_reason };
}

/**
 * Confirm a capability through the PRODUCT, not through a raw INSERT.
 *
 * capability_agent's `confirm` action makes no model call at all - the single model call in that
 * function sits on the `analyze` path - so this costs nothing, and unlike the 18-column INSERT that
 * journey_test writes out twice it also validates trades and roles against the controlled
 * vocabulary and records a supplier_capability_confirmation ledger row with a version. That ledger
 * is the thing that matters the day a supplier disputes a match.
 *
 * It needs `capability_agent` in a credential scope; seed_staging_secrets.mjs adds it to
 * db.internal. Until session 9 no credential in EITHER project scoped it, which is why the half of
 * the capability flow that is NOT blocked by fn_ai_route's supplier_matching tier=none policy had
 * still never run.
 *
 * NOTE it does not write min_project_value / max_project_value: fn_match_capability's size term
 * therefore scores w_size*0.5 rather than w_size for a supplier confirmed this way.
 */
export async function confirmCapability(leadId, profile, opts = {}) {
  const cred = await internalCred();
  if (!cred) throw new Error('cred_db_internal missing from staging app_secrets');
  const r = await call('capability_agent', null, {
    __secret: cred, action: 'confirm', supplier_id: Number(leadId),
    trades: profile.trades, roles: profile.roles, products: profile.products_norm,
    brands: profile.brands, project_types: profile.project_types,
    coverage_emirates: profile.coverage_emirates, exclusions: profile.exclusions || [],
    confirmed_via: opts.confirmed_via || 'demo_factory',
  });
  if (r.status !== 200 || r.json?.ok !== true) {
    throw new Error(`capability_agent confirm failed: HTTP ${r.status} ${r.text}`);
  }
  return r.json;
}

let _cred = null;
export async function internalCred() {
  if (_cred !== null) return _cred;
  _cred = (await mgmtRead(REF, "select value from public.app_secrets where key='cred_db_internal'"))[0]?.value || null;
  return _cred;
}

// ---- inquiries -------------------------------------------------------------------------------
/**
 * makeInquiry(run, opts) -> { id, customerId, category, trades, status }
 *
 * mode 'sql' (default): one INSERT. Fires enrich_inquiry, rfq_complete, scrub_inquiry_contacts,
 *                       fn_emit_event('inquiry','rfq.created') and trg_inquiry_received, so it
 *                       leaves a company_event row and a queued notifications row behind - both of
 *                       which teardown removes.
 * mode 'api'          : the real multi-turn inquiry_intake loop plus customer_api create_inquiry.
 *                       That is roughly 8 model calls; reserve it for the deep cases.
 */
export async function makeInquiry(run, opts = {}) {
  const cust = opts.customer;
  if (!cust) throw new Error('makeInquiry needs { customer }');
  const trade = opts.trade || 'aluminium';
  const t = TRADES[trade] || TRADES.aluminium;
  const emirate = opts.emirate || 'Dubai';
  const status = opts.status || 'sent';
  const locale = opts.locale || cust.locale || 'en';
  const summary = opts.summary || (locale === 'ar'
    ? `توريد وتركيب ${t.name} لفيلا في ${emirate}`
    : `Supply and install ${t.name.toLowerCase()} for a villa in ${emirate}`);
  const rawInput = opts.raw_input || (locale === 'ar'
    ? `نحتاج ${t.name} لفيلا خاصة في ${emirate}. الرجاء تقديم عرض سعر شامل التوريد والتركيب.`
    : `We need ${t.name.toLowerCase()} supplied and installed for a private villa in ${emirate}.`);

  if (opts.mode === 'api') {
    const answers = opts.answers || DEFAULT_INTAKE_ANSWERS(t, emirate);
    const intake = await runIntake(cust, answers);
    const r = await call('customer_api', cust.jwt, {
      action: 'create_inquiry', intake_id: intake.intakeId, text: rawInput,
    });
    const id = r.json?.id ?? r.json?.inquiry_id ?? null;
    if (!id) throw new Error(`create_inquiry failed: HTTP ${r.status} ${r.text}`);
    await tagInquiry(run, id);
    return { id, customerId: cust.customerId, category: trade, trades: [trade], status, intake };
  }

  const ins = await mgmtWrite(REF,
    `insert into public.inquiries
       (customer_id, category, emirate, role_needed, raw_input, summary, keywords, trades,
        status, budget, scope_type, brief_source, urgency, drawing_file_path, drawing_file_name,
        provenance, spec)
     values (${q(cust.customerId)}, ${q(trade)}, ${q(emirate)}, ${q(opts.role_needed || 'executes')},
             ${q(rawInput)}, ${q(summary)}, ${arr(t.products.slice(0, 4))}, ${arr([trade])},
             ${q(status)}, ${num(opts.budget ?? null)}, ${q(opts.scope_type || 'single')},
             ${q(opts.brief_source || 'chat')}, ${q(opts.urgency || 'normal')},
             ${q(opts.drawing_file_path ?? null)}, ${q(opts.drawing_file_name ?? null)},
             ${jb({ qd_run: run.tag, source: 'demo_factory' })},
             ${rfqReadySpec(trade, opts)})
     returning id`, 'demo inquiry');
  const id = ins?.[0]?.id;
  if (!id) throw new Error('inquiries insert returned no id');

  // An inquiry that is not rfq_ready cannot be dispatched, and dispatch_inquiry says so with
  // {"ok":true,"skip":"not_rfq_ready"} - a 200 that did nothing. Fail loudly here instead.
  if (opts.rfqReady !== false) {
    const row = (await mgmtRead(REF,
      `select rfq_ready, completeness->>'score' score,
              completeness->'category_check'->>'missing' cat_missing
         from public.inquiries where id=${q(id)}`))[0] || {};
    if (row.rfq_ready !== true) {
      throw new Error(`demo inquiry ${id} is not rfq_ready (score ${row.score}, ` +
        `category_specs still missing ${row.cat_missing}) - dispatch would answer ` +
        '{"ok":true,"skip":"not_rfq_ready"} and contact nobody');
    }
  }
  return { id, customerId: cust.customerId, category: trade, trades: [trade], status };
}

/**
 * The structured capability requirement `route_inquiry` gates on. Without a row here
 * `capabilityRetrieve` calls `inquiry_parse` to build one - a model call - and returns null if it
 * still cannot, dropping routing back to the loose legacy path. Writing it directly keeps a
 * matching test deterministic and free.
 *
 * Note `route_inquiry` calls fn_match_capability with a hardcoded `p_limit: 12` and applies
 * `match_relevance_floor` AFTER that limit, so the limit binds before the floor does.
 */
export async function makeRequirement(run, opts = {}) {
  const { inquiry } = opts;
  if (!inquiry) throw new Error('makeRequirement needs { inquiry }');
  const trade = opts.trade || inquiry.category || 'aluminium';
  const t = TRADES[trade] || TRADES.aluminium;
  await mgmtWrite(REF,
    `insert into public.inquiry_requirement
       (inquiry_id, trades_required, role_required, emirate, authority_required, products_norm,
        brands_specified, project_type, value_band, scope_type, confidence, missing_fields,
        parsed_at, parser_version)
     values (${q(inquiry.id)}, ${arr(opts.trades || [trade])}, ${q(opts.role || 'executes')},
             ${q(opts.emirate ?? null)}, ${arr(opts.authority || [])},
             ${arr(opts.products || t.products)}, ${arr(opts.brands || [])},
             ${q(opts.project_type ?? null)}, ${num(opts.value_band ?? 150000)},
             ${q(opts.scope_type || 'single')}, '{"overall":0.9}'::jsonb, '{}'::text[],
             now(), 'demo_factory')
     on conflict (inquiry_id) do update
       set trades_required=excluded.trades_required, role_required=excluded.role_required,
           products_norm=excluded.products_norm, value_band=excluded.value_band,
           emirate=excluded.emirate, project_type=excluded.project_type`, 'demo requirement');
  return { inquiry_id: inquiry.id, trades: opts.trades || [trade] };
}

/**
 * A spec that satisfies the category's OWN checklist.
 *
 * `trg_rfq_complete` runs `fn_rfq_score` on every insert and update, so `rfq_ready` cannot be set
 * by hand - it is computed. It needs 70 generic points AND `fn_rfq_required_check` to find an
 * answer for every field `category_specs` marks required. A hand-written spec satisfies the first
 * and fails the second, and the only symptom is dispatch_inquiry returning
 * {"ok":true,"skip":"not_rfq_ready"}: an ok:true that contacted nobody.
 *
 * So the required keys are read out of category_specs IN SQL rather than hard-coded. A field with
 * `options` gets its first option (which is also what the option-token fallback scans the blob
 * for); everything else gets its own question echoed back, which is enough for `_rfq_answered` -
 * that only rejects null, empty, '[]', '{}', '-', '?', 'null', 'not sure', 'unknown', 'tbd',
 * 'n/a' and 'na'. Reading the checklist instead of copying it means a new required field starts
 * being answered the day it is added.
 */
function rfqReadySpec(trade, opts) {
  const base = opts.spec || { products: (TRADES[trade] || TRADES.aluminium).products.slice(0, 4),
                              quantity: opts.quantity ?? 40 };
  if (opts.rfqReady === false) return jb(base);
  return `(coalesce((
      select jsonb_object_agg(lower(f->>'key'),
               coalesce((select o from jsonb_array_elements_text(f->'options') o limit 1),
                        'Demo answer: ' || coalesce(f->>'question', f->>'key')))
        from public.category_specs cs, jsonb_array_elements(cs.fields) f
       where lower(cs.category) = lower(${q(trade)})
         and coalesce((f->>'required')::boolean, false)
         and nullif(btrim(lower(coalesce(f->>'key',''))), '') is not null
    ), '{}'::jsonb) || ${jb(base)})`;
}

const tagInquiry = (run, id) => mgmtWrite(REF,
  `update public.inquiries
      set provenance = coalesce(provenance,'{}'::jsonb) || ${jb({ qd_run: run.tag, source: 'demo_factory' })}
    where id = ${q(id)}`, 'tag demo inquiry');

export const DEFAULT_INTAKE_ANSWERS = (t, emirate) => [
  `${t.name}: supply and installation. 40 units for a private villa in ${emirate}.`,
  'Sizes: 40 units at 1200 mm W x 1500 mm H each, approximately 72 square metres in total.',
  'Scope: supply and install, including removing the existing units and disposing of them.',
  `Property: private villa in ${emirate}, ground and first floor, direct vehicle access, no crane needed.`,
  `Specification: ${t.products.slice(0, 3).join(', ')}, standard commercial grade.`,
  'Timeline: installation within eight weeks of order. Budget is open; include supply and install.',
];

/** The adaptive intake loop. Each turn answers whatever the server still says is missing. */
export async function runIntake(cust, answers, maxTurns = 10) {
  let intakeId = null, status = null, readiness = 0, missing = [], turns = 0;
  for (let i = 0; i < maxTurns; i++) {
    const answer = i < answers.length ? answers[i]
      : `Details: ${missing.slice(0, 6).map((m) => `${m}: standard specification, please assume typical values`).join('; ') || 'please proceed with typical values'}.`;
    const r = await call('inquiry_intake', cust.jwt,
      intakeId ? { intake_id: intakeId, text: answer, email: cust.email }
               : { text: answer, email: cust.email });
    turns++;
    if (r.status !== 200) { status = `HTTP ${r.status} ${r.text}`; break; }
    intakeId = r.json?.intake_id ?? r.json?.id ?? intakeId;
    status = r.json?.status ?? null;
    readiness = Number(r.json?.readiness ?? 0);
    missing = Array.isArray(r.json?.missing) ? r.json.missing.map(String) : [];
    if (status === 'ready') break;
  }
  return { intakeId, status, readiness, missing, turns };
}

// ---- quotes ----------------------------------------------------------------------------------
/**
 * A quote is only ACCEPTED (status submitted, not draft) when the form is complete: source 'form',
 * at least one priced item, and validity, warranty and lead_time all present. Amount plus notes
 * alone leaves a draft with submittable=false while the API still answers status 'submitted', and
 * comparison then reports "needs at least two complete quotes" for an RFQ that has two.
 */
export const quotePayload = (inquiryId, amount, note, extra = {}) => ({
  action: 'submit_quote', inquiry_id: inquiryId, amount, currency: 'AED', source: 'form',
  items: [{ description: extra.item || 'Supply and installation as specified', qty: 40, unit_price: Math.round(amount / 40) }],
  lead_time: '8 weeks', validity: '30 days', warranty: '12 months',
  payment_terms: '50% advance, 50% on completion',
  scope: extra.scope || 'Supply, delivery and installation including removal of existing units.',
  conditions: 'Access to site during working hours.',
  exclusions: 'Civil works, painting, scaffolding.',
  notes: note,
  ...extra.overrides,
});

export async function makeQuote(run, opts = {}) {
  const { inquiry, supplier } = opts;
  if (!inquiry || !supplier) throw new Error('makeQuote needs { inquiry, supplier }');
  const amount = opts.amount ?? 125000;
  const note = opts.notes || 'Demo quotation for the stated scope.';

  if (opts.mode === 'api') {
    const r = await call('supplier_api', supplier.jwt, quotePayload(inquiry.id, amount, note, opts));
    if (r.status !== 200) throw new Error(`submit_quote failed: HTTP ${r.status} ${r.text}`);
    const row = (await mgmtRead(REF,
      `select id, status, submittable from public.quotes
        where inquiry_id=${q(inquiry.id)} and supplier_id=${num(supplier.leadId)}`))[0] || {};
    return { id: row.id, status: row.status, submittable: row.submittable, amount };
  }

  const ins = await mgmtWrite(REF,
    `insert into public.quotes
       (inquiry_id, supplier_id, quote_amount, notes, status, source, lead_time, validity,
        warranty, payment_terms, scope, conditions, exclusions, anonymized)
     values (${q(inquiry.id)}, ${num(supplier.leadId)}, ${num(amount)}, ${q(note)},
             ${q(opts.status || 'submitted')}, ${q(opts.source || 'form')},
             ${q(opts.lead_time || '8 weeks')}, ${q(opts.validity || '30 days')},
             ${q(opts.warranty || '12 months')}, ${q(opts.payment_terms || '50% advance, 50% on completion')},
             ${q(opts.scope || 'Supply, delivery and installation as specified.')},
             ${q(opts.conditions || 'Access to site during working hours.')},
             ${q(opts.exclusions || 'Civil works, painting, scaffolding.')},
             ${bool(opts.anonymized ?? true)})
     on conflict (inquiry_id, supplier_id) do update
       set quote_amount=excluded.quote_amount, status=excluded.status, notes=excluded.notes
     returning id, status, quote_amount`, 'demo quote');
  const row = ins?.[0] || {};
  return { id: row.id, status: row.status, amount: Number(row.quote_amount) };
}

// ---- bulk corpus -----------------------------------------------------------------------------
/**
 * makeBulkCorpus(run, opts) -> { suppliers: [...], customers: [...], trades: [...] }
 *
 * The acceptance-scale corpus, built with ZERO model calls. Standing one supplier up through the
 * API costs 2 billable model calls, so 100 suppliers that way is ~200 inference calls and no extra
 * confidence: reserve the API path for the 2-3 deep cases actually being asserted end to end.
 *
 * Suppliers default to withAuth:false - a matching corpus never logs in, and skipping 100 auth
 * round trips is most of the runtime. Pass withAuth:true if you need to act as them.
 */
export async function makeBulkCorpus(run, opts = {}) {
  const trades = opts.trades || TRADE_CODES;
  const perTrade = opts.perTrade ?? 4;
  const nCustomers = opts.customers ?? 0;
  const withAuth = opts.withAuth === true;

  // One multi-row INSERT for all suppliers, one for all capabilities: 2 management-API round trips
  // instead of 200. leads.id is GENERATED ALWAYS AS IDENTITY, so the ids come back from RETURNING.
  const specs = [];
  for (const trade of trades) {
    for (let v = 0; v < perTrade; v++) {
      const profile = capabilityProfile(trade, v, perTrade, { flat: opts.flat, roleSet: opts.roleSet });
      const t = TRADES[trade];
      specs.push({
        trade, variant: v, profile,
        // run.seq, not specs.length: leads carries a unique index on lower(email), and a second
        // makeBulkCorpus call in the same run would restart the numbering and collide on corp0.
        email: `qd-${run.tag}-corp${run.seq++}@example.com`,
        companyName: `QD Demo ${t.name} ${String(v + 1).padStart(2, '0')} ${run.tag.slice(0, 4)}`,
        emirate: profile.coverage_emirates[0] || 'Dubai',
      });
    }
  }
  if (!specs.length) return { suppliers: [], customers: [], trades };

  const values = specs.map((s) => `(${q(s.companyName)}, ${q(s.emirate)}, ${q(s.emirate)},
      false, null, ${q(s.email)}, 'Demo Contact', '+97140000000',
      'LLC', ${q(s.profile.products_norm.join(', '))},
      ${q(`Supply and installation of ${TRADES[s.trade].name.toLowerCase()}.`)},
      ${q(`${TRADES[s.trade].name} specialist serving ${s.profile.coverage_emirates.join(', ')}.`)},
      ${arr(s.profile.coverage_emirates)}, 'demo_factory', true, 'approved', true, now(), 'en',
      ARRAY['qd_demo', ${RUN_TAG_COL(run.tag)}]::text[])`).join(',\n');

  // license_doc_path is absent from the column list ON PURPOSE - see makeSupplier's note.
  const ins = await mgmtWrite(REF,
    `insert into public.leads
       (company_name, emirate, city, claimed, claimed_by, email, contact_name, phone,
        company_type, products, services, description, service_emirates, source,
        verified, approval_status, owner_email_verified, accepted_terms_at, locale, tags)
     values ${values}
     returning id, email`, 'demo corpus suppliers');

  const byEmail = new Map((ins || []).map((r) => [String(r.email).toLowerCase(), r.id]));
  const suppliers = specs.map((s) => ({
    ...s, leadId: byEmail.get(s.email.toLowerCase()) ?? null, jwt: null,
  })).filter((s) => s.leadId != null);
  if (suppliers.length !== specs.length) {
    throw new Error(`corpus insert returned ${suppliers.length} ids for ${specs.length} rows`);
  }

  const capValues = suppliers.map((s) => {
    const p = s.profile;
    return `(${num(s.leadId)}, ${arr(p.trades)}, ${arr(p.roles)}, ${arr(p.products_norm)},
      ${arr(p.project_types)}, ${arr(p.brands)}, '{}'::text[], ${jb(p.authority_approvals)},
      '{}'::jsonb, '{"overall":0.9}'::jsonb, '{}'::text[], '{}'::text[],
      ${num(p.completeness)}, 'confirmed', now(), now(),
      ${num(p.min_project_value)}, ${num(p.max_project_value)}, ${arr(p.coverage_emirates)})`;
  }).join(',\n');
  await mgmtWrite(REF,
    `insert into public.supplier_capabilities
       (supplier_id, trades, roles, products_norm, project_types, brands, exclusions,
        authority_approvals, source_docs, confidence, missing_fields, excluded_trades,
        completeness, review_status, confirmed_at, extracted_at,
        min_project_value, max_project_value, coverage_emirates)
     values ${capValues}
     on conflict (supplier_id) do nothing`, 'demo corpus capabilities');

  if (withAuth) for (const s of suppliers) {
    const u = await mkAuthUser(run, s.email);
    s.jwt = u.jwt; s.authUserId = u.id;
    await mgmtWrite(REF,
      `update public.leads set claimed=true, claimed_by=${q(s.email)} where id=${num(s.leadId)}`,
      'claim corpus supplier');
  }

  const customers = [];
  for (let i = 0; i < nCustomers; i++) {
    customers.push(await makeCustomer(run, {
      mode: 'sql', locale: i % 10 === 0 ? 'ar' : 'en',
      full_name: i % 10 === 0 ? `عميل ${i}` : `Demo Customer ${i}`,
    }));
  }

  run.log(`corpus: ${suppliers.length} supplier(s) across ${trades.length} trade(s)` +
          `${nCustomers ? `, ${customers.length} customer(s)` : ''}`);
  return { suppliers, customers, trades };
}

// ---- teardown --------------------------------------------------------------------------------
// Storage paths are DERIVED FROM THE DATABASE, never from a hand-maintained list. The hand-listed
// version in journey_test is why 118 signed-terms objects and 19 comparison PDFs are still sitting
// in staging: nobody added those two buckets to the list.
// A scope is a set of WHERE fragments, one per table, all derived from the run tag. Everything
// downstream (storage discovery, the delete order) is built from these rather than from string
// surgery on a subquery, which is how the first cut of this file produced
// `select id::text from (select id from ...)` and would have silently deleted nothing.
function scopeForRun(tag) {
  const cust = `email like 'qd-${tag}-%@example.com'`;
  const lead = `'qd_run:${tag}' = any(coalesce(tags,'{}'::text[]))`;
  const inq = `(customer_id in (select id from public.customers where ${cust})` +
              ` or provenance->>'qd_run' = '${tag}')`;
  const quote = `(inquiry_id in (select id from public.inquiries where ${inq})` +
                ` or supplier_id in (select id from public.leads where ${lead}))`;
  return { cust, lead, inq, quote, redaction: `(customer_id in (select id from public.customers where ${cust}) or owner_email like 'qd-${tag}-%@example.com')` };
}

const scopeSql = (s) => ({
  CUST: `(select id from public.customers where ${s.cust})`,
  LEAD: `(select id from public.leads where ${s.lead})`,
  INQ: `(select id from public.inquiries where ${s.inq})`,
  QUO: `(select id from public.quotes where ${s.quote})`,
  INQ_T: `(select id::text from public.inquiries where ${s.inq})`,
  QUO_T: `(select id::text from public.quotes where ${s.quote})`,
  LEAD_T: `(select id::text from public.leads where ${s.lead})`,
});

const BUCKET_SOURCES = (s) => [
  {
    bucket: 'drawing-files', sql:
      `select drawing_file_path p from public.inquiries where ${s.inq} and drawing_file_path is not null
       union select unnest(drawing_redacted_paths) from public.inquiries where ${s.inq}
       union select source_path from public.drawing_redaction_runs where ${s.redaction} and source_path is not null
       union select unnest(output_paths) from public.drawing_redaction_runs where ${s.redaction}`,
  },
  {
    bucket: 'quote-files', sql:
      `select original_file_path p from public.quotes where ${s.quote} and original_file_path is not null`,
  },
  {
    bucket: 'signed-terms', sql:
      `select signed_terms_path p from public.customers where ${s.cust} and signed_terms_path is not null
       union select signed_terms_path from public.leads where ${s.lead} and signed_terms_path is not null`,
  },
  {
    // The comparison PDF is the one output whose path NOTHING records: comparison_run_v2 has no
    // path column and the signed URL is only ever returned to the caller. It is derivable from the
    // filename convention instead - QD-<first 8 of the inquiry id, uppercased>-CMP.pdf - which is
    // how 20 of them accumulated in agent-docs without appearing on anybody's cleanup list.
    bucket: 'agent-docs', sql:
      `select o.name p from storage.objects o
        where o.bucket_id = 'agent-docs'
          and exists (select 1 from public.inquiries i
                       where ${s.inq}
                         and o.name like '%QD-' || upper(left(i.id::text, 8)) || '-CMP%')`,
  },
];

/**
 * Put a real object in a real bucket. Teardown finds it again through whichever row names it
 * (`inquiries.drawing_file_path`, `documents.path`, …), so callers must attach the returned path to
 * something - an orphan object is exactly the litter this module exists to stop.
 */
export async function uploadObject(bucket, path, bytes, mime = 'application/octet-stream') {
  const { SERVICE } = await keys();
  const r = await fetch(`${BASE}/storage/v1/object/${bucket}/${path}`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': mime, 'x-upsert': 'true' },
    body: bytes,
  });
  if (!r.ok) throw new Error(`upload to ${bucket}/${path} failed: HTTP ${r.status} ${(await r.text()).slice(0, 200)}`);
  return path;
}

async function deleteObjects(bucket, paths) {
  const clean = [...new Set(paths.filter(Boolean))];
  if (!clean.length) return 0;
  const { SERVICE } = await keys();
  let n = 0;
  for (let i = 0; i < clean.length; i += 100) {
    const chunk = clean.slice(i, i + 100);
    const r = await fetch(`${BASE}/storage/v1/object/${bucket}`, {
      method: 'DELETE',
      headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefixes: chunk }),
    });
    if (r.ok) n += chunk.length;
  }
  return n;
}

const delCount = async (label, sql) => {
  const rows = await mgmtWrite(REF, `with d as (${sql} returning 1) select count(*)::int n from d`, label);
  return Number(rows?.[0]?.n ?? 0);
};

/**
 * Delete everything this run created, in foreign-key order, including the storage objects and the
 * auth users. Safe to call twice.
 */
export async function teardown(run) {
  const tag = run.tag;
  const s = scopeForRun(tag);
  const { CUST, LEAD, INQ, QUO, INQ_T, QUO_T, LEAD_T } = scopeSql(s);
  const DOCS_W = `((ref_table='inquiries' and ref_id in ${INQ_T})` +
                 ` or (ref_table='quotes' and ref_id in ${QUO_T})` +
                 ` or (ref_table='leads' and ref_id in ${LEAD_T}))`;

  // 1. storage first, while the rows that name the objects still exist
  const objs = {};
  for (const src of BUCKET_SOURCES(s)) {
    const rows = await mgmtRead(REF, src.sql);
    objs[src.bucket] = await deleteObjects(src.bucket, rows.map((r) => r.p));
  }
  // documents rows name their own bucket, so they are their own source of truth
  const docRows = await mgmtRead(REF, `select bucket, path from public.documents where ${DOCS_W}`);
  for (const b of new Set(docRows.map((r) => r.bucket))) {
    objs[b] = (objs[b] || 0) + await deleteObjects(b, docRows.filter((r) => r.bucket === b).map((r) => r.path));
  }

  // 2. rows, children before parents. Everything below is one statement per table so a failure
  //    names the table it failed on instead of collapsing into one opaque constraint error.
  const counts = {};
  const steps = [
    ['transactions', `delete from public.transactions where quote_id in ${QUO} or inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD}`],
    // notifications names all three parents (inquiry_id, lead_id, quote_id) and has no children of
    // its own, so it goes first - after the quote is deleted the quote_id clause matches nothing.
    ['notifications', `delete from public.notifications where inquiry_id in ${INQ} or lead_id in ${LEAD} or quote_id in ${QUO} or to_email like 'qd-${tag}-%@example.com'`],
    ['comparison_candidate_v2', `delete from public.comparison_candidate_v2 where quote_id in ${QUO}`],
    ['comparison_run_v2', `delete from public.comparison_run_v2 where inquiry_id in ${INQ}`],
    // doc_versions, documents and company_event key off the quote/inquiry id as TEXT, so they must
    // go before the row they name: once the quote is deleted the subquery finds nothing and the
    // log row survives as litter. That ordering mistake is exactly what left 452 doc_versions and
    // 186 company_event rows in staging.
    ['doc_versions', `delete from public.doc_versions where entity_type='quote' and entity_id in ${QUO_T}`],
    ['documents', `delete from public.documents where ${DOCS_W}`],
    ['company_event (quote)', `delete from public.company_event where entity_type='quote' and entity_id in ${QUO_T}`],
    ['quotes', `delete from public.quotes where id in ${QUO}`],
    ['supplier_opportunity_score', `delete from public.supplier_opportunity_score where inquiry_id in ${INQ} or supplier_id in ${LEAD}`],
    ['reviews', `delete from public.reviews where inquiry_id in ${INQ} or customer_id in ${CUST} or supplier_id in ${LEAD}`],
    ['inquiry_matches', `delete from public.inquiry_matches where inquiry_id in ${INQ} or supplier_id in ${LEAD}`],
    ['company_event (lead)', `delete from public.company_event where entity_type='lead' and entity_id in ${LEAD_T}`],
    ['company_event (inquiry)', `delete from public.company_event where entity_type='inquiry' and entity_id in ${INQ_T}`],
    ['inquiry_supplier_brief', `delete from public.inquiry_supplier_brief where inquiry_id in ${INQ}`],
    ['inquiries_unhire', `update public.inquiries set hired_supplier_id=null where hired_supplier_id in ${LEAD}`],
    ['inquiries', `delete from public.inquiries where id in ${INQ}`],
    ['doc_reviews', `delete from public.doc_reviews where lead_id in ${LEAD}`],
    ['inbound_messages', `delete from public.inbound_messages where lead_id in ${LEAD}`],
    ['supplier_catalog', `delete from public.supplier_catalog where supplier_id in ${LEAD}`],
    ['supplier_negotiation_policy', `delete from public.supplier_negotiation_policy where supplier_id in ${LEAD}`],
    ['supplier_product', `delete from public.supplier_product where supplier_id in ${LEAD}`],
    ['supplier_capability_confirmation', `delete from public.supplier_capability_confirmation where supplier_id in ${LEAD}`],
    // fn_supplier_exception_sweep records its auto-rejections here as telemetry, keyed by
    // target_table/target_id text rather than a foreign key - so nothing cascades and nothing
    // complained when a run left one behind pointing at a lead that no longer existed.
    ['agent_actions', `delete from public.agent_actions where (target_table='leads' and target_id in ${LEAD_T}) or (target_table='inquiries' and target_id in ${INQ_T}) or (target_table='quotes' and target_id in ${QUO_T})`],
    ['leads', `delete from public.leads where id in ${LEAD}`],
    ['drawing_redaction_runs', `delete from public.drawing_redaction_runs where customer_id in ${CUST} or owner_email like 'qd-${tag}-%@example.com'`],
    ['customer_preference', `delete from public.customer_preference where customer_id in ${CUST}`],
    ['customer_organization', `delete from public.customer_organization where owner_customer_id in ${CUST}`],
    ['customers', `delete from public.customers where id in ${CUST}`],
    ['inquiry_intake', `delete from public.inquiry_intake where email like 'qd-${tag}-%@example.com'`],
    ['email_verifications', `delete from public.email_verifications where email like 'qd-${tag}-%@example.com'`],
  ];
  for (const [label, sql] of steps) {
    const n = await delCount(`teardown ${label}`, sql);
    if (n) counts[label] = n;
  }

  // 3. auth users last: the email pattern is the only handle on them once the rows are gone
  const users = await deleteAuthUsersByTag(tag);
  if (users) counts.auth_users = users;
  const objTotal = Object.values(objs).reduce((a, b) => a + b, 0);
  if (objTotal) counts.storage_objects = objTotal;

  const summary = Object.keys(counts).length
    ? Object.entries(counts).map(([k, v]) => `${k} ${v}`).join(', ')
    : 'nothing to remove';
  return { counts, objects: objs, summary };
}

// ---- purge -----------------------------------------------------------------------------------
// Teardown handles a run this process created. Purge handles DRIFT: what previous runs left behind
// before the tag existed, and what a mid-run throw leaks. The rules are deliberately about
// synthetic markers and orphanhood, not "delete everything in staging".
//
// The bucket allowlist is explicit and MUST NOT contain 'brand'. brand holds the fonts
// sync_staging_assets copies from production, and Phase 1's "15/15 storage buckets" was true and
// useless precisely because it counted buckets and not objects: an empty brand bucket made
// pdf_native fall back to WinAnsi Helvetica, which throws on any character above U+00FF, and one
// '≠' from a model 502'd a customer's comparison PDF.
export const PURGE_BUCKETS = ['drawing-files', 'quote-files', 'signed-terms', 'agent-docs'];
export const PROTECTED_BUCKETS = ['brand', 'site', 'demo-assets', 'social-media', 'kb-import-assets', 'backups'];

const P_CUST = `(select id from public.customers where email like 'qd-%@example.com' or email is null or id not in (select id from auth.users))`;
const P_LEAD = `(select id from public.leads where 'qd_demo' = any(coalesce(tags,'{}'::text[])) or company_name like 'Journey Test %' or company_name like 'QD Demo %' or source='demo_factory' or claimed_by like 'qd-%@example.com')`;
const P_INQ = `(select id from public.inquiries where customer_id in ${P_CUST} or customer_id is null or provenance->>'qd_run' is not null)`;
const P_QUO = `(select id from public.quotes where inquiry_id in ${P_INQ} or supplier_id in ${P_LEAD})`;

export async function purge(opts = {}) {
  const dry = !!opts.dryRun;
  const log = opts.quiet ? () => {} : console.log;
  for (const b of PURGE_BUCKETS) {
    if (PROTECTED_BUCKETS.includes(b)) throw new Error(`refusing to purge protected bucket ${b}`);
  }

  const brandBefore = Number((await mgmtRead(REF,
    "select count(*)::int n from storage.objects where bucket_id='brand'"))[0].n);

  const steps = [
    // children -> parents, then the orphan sweeps that only make sense once the parents are gone
    ['transactions', `delete from public.transactions where quote_id in ${P_QUO} or inquiry_id in ${P_INQ} or customer_id in ${P_CUST} or supplier_id in ${P_LEAD}`],
    ['comparison_candidate_v2', `delete from public.comparison_candidate_v2 where quote_id in ${P_QUO}`],
    ['comparison_run_v2', `delete from public.comparison_run_v2 where inquiry_id in ${P_INQ}`],
    ['doc_versions (quote)', `delete from public.doc_versions where entity_type='quote' and entity_id not in (select id::text from public.quotes)`],
    ['quotes', `delete from public.quotes where id in ${P_QUO}`],
    ['supplier_opportunity_score', `delete from public.supplier_opportunity_score where inquiry_id in ${P_INQ} or supplier_id in ${P_LEAD}`],
    ['reviews', `delete from public.reviews where inquiry_id in ${P_INQ} or customer_id in ${P_CUST} or supplier_id in ${P_LEAD}`],
    ['inquiry_matches', `delete from public.inquiry_matches where inquiry_id in ${P_INQ} or supplier_id in ${P_LEAD}`],
    ['inquiries (unhire)', `update public.inquiries set hired_supplier_id=null where hired_supplier_id in ${P_LEAD}`],
    ['inquiries', `delete from public.inquiries where id in ${P_INQ}`],
    ['doc_reviews', `delete from public.doc_reviews where lead_id in ${P_LEAD}`],
    ['inbound_messages', `delete from public.inbound_messages where lead_id in ${P_LEAD}`],
    ['supplier_catalog', `delete from public.supplier_catalog where supplier_id in ${P_LEAD}`],
    ['supplier_negotiation_policy', `delete from public.supplier_negotiation_policy where supplier_id in ${P_LEAD}`],
    ['supplier_product', `delete from public.supplier_product where supplier_id in ${P_LEAD}`],
    ['supplier_capability_confirmation', `delete from public.supplier_capability_confirmation where supplier_id in ${P_LEAD} or supplier_id not in (select id from public.leads)`],
    ['leads', `delete from public.leads where id in ${P_LEAD}`],
    ['drawing_redaction_runs', `delete from public.drawing_redaction_runs where customer_id is null or customer_id not in (select id from public.customers) or owner_email like 'qd-%@example.com'`],
    ['customer_preference', `delete from public.customer_preference where customer_id in ${P_CUST}`],
    ['customer_organization', `delete from public.customer_organization where owner_customer_id in ${P_CUST}`],
    ['customers', `delete from public.customers where id in ${P_CUST}`],
    ['inquiry_intake', `delete from public.inquiry_intake where email like 'qd-%@example.com' or customer_id is null or customer_id not in (select id from public.customers)`],
    ['email_verifications', `delete from public.email_verifications where email like 'qd-%@example.com'`],
    // orphan sweeps: run last, when "dangling" finally means what it says
    ['documents (dangling)', `delete from public.documents where (ref_table='inquiries' and ref_id not in (select id::text from public.inquiries)) or (ref_table='quotes' and ref_id not in (select id::text from public.quotes)) or (ref_table='leads' and ref_id not in (select id::text from public.leads))`],
    // notifications is a QUEUE, not a log. 66 'supplier_registered' rows addressed to
    // management@quotesdone.com survived the first purge because they carry a lead_id and no
    // inquiry_id - every one of them for a supplier that no longer exists. email_enabled is false
    // on staging today, so they sat there harmlessly; the moment it is turned on behind a
    // recipient allowlist to prove notification, they would all fire at once.
    ['notifications (dangling)', `delete from public.notifications where to_email like 'qd-%@example.com' or (inquiry_id is not null and inquiry_id not in (select id from public.inquiries)) or (lead_id is not null and lead_id not in (select id from public.leads)) or (quote_id is not null and quote_id not in (select id from public.quotes))`],
    ['company_event (dangling)', `delete from public.company_event where (entity_type in ('inquiry','quote') and entity_id not in (select id::text from public.inquiries union all select id::text from public.quotes)) or (entity_type='lead' and entity_id not in (select id::text from public.leads))`],
    ['inquiry_supplier_brief (dangling)', `delete from public.inquiry_supplier_brief where inquiry_id not in (select id from public.inquiries)`],
    ['agent_actions (dangling)', `delete from public.agent_actions where (target_table='leads' and target_id not in (select id::text from public.leads)) or (target_table='inquiries' and target_id not in (select id::text from public.inquiries)) or (target_table='quotes' and target_id not in (select id::text from public.quotes))`],
  ];

  const counts = {};
  if (dry) {
    // A dry run counts each rule against the CURRENT state, but the orphan sweeps at the end only
    // become true once their parents are gone - the real run deleted 26 dangling documents where
    // the dry run predicted 13, and 415 notifications where it predicted 382. The dry run is a
    // lower bound on what will go, never an upper one.
    for (const [label, sql] of steps) {
      const probe = sql.startsWith('update')
        ? sql.replace(/^update public\.(\w+) set .*? where /, 'select count(*)::int n from public.$1 where ')
        : sql.replace(/^delete from /, 'select count(*)::int n from ');
      const rows = await mgmtRead(REF, probe);
      const n = Number(rows?.[0]?.n ?? 0);
      if (n) counts[label] = n;
    }
  } else {
    for (const [label, sql] of steps) {
      const n = await delCount(`purge ${label}`, sql);
      if (n) counts[label] = n;
    }
  }

  // storage: every object in the four demo buckets. Staging holds no real uploads - the 118
  // signed-terms PDFs and 19 comparison PDFs are all previous runs' litter.
  const objs = {};
  for (const bucket of PURGE_BUCKETS) {
    const rows = await mgmtRead(REF,
      `select name from storage.objects where bucket_id=${q(bucket)} order by name`);
    objs[bucket] = dry ? rows.length : await deleteObjects(bucket, rows.map((r) => r.name));
  }

  let users = 0;
  const orphanRows = await mgmtRead(REF, `select id from auth.users where email like 'qd-%@example.com'`);
  if (dry) users = orphanRows.length;
  else {
    const { SERVICE } = await keys();
    for (const r of orphanRows) {
      const d = await fetch(`${BASE}/auth/v1/admin/users/${r.id}`, {
        method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE },
      });
      if (d.ok) users++;
    }
  }

  const brandAfter = Number((await mgmtRead(REF,
    "select count(*)::int n from storage.objects where bucket_id='brand'"))[0].n);
  if (brandAfter !== brandBefore) {
    throw new Error(`purge touched the brand bucket: ${brandBefore} -> ${brandAfter}. ` +
      'brand holds the fonts pdf_native needs; restore with sync_staging_assets.mjs.');
  }

  log(`\n${dry ? 'PURGE (dry run) would remove AT LEAST' : 'PURGED'}:`);
  for (const [k, v] of Object.entries(counts)) log(`  ${String(v).padStart(6)}  ${k}`);
  for (const [k, v] of Object.entries(objs)) if (v) log(`  ${String(v).padStart(6)}  storage/${k}`);
  if (users) log(`  ${String(users).padStart(6)}  auth users (qd-%@example.com)`);
  log(`  brand bucket preserved at ${brandAfter} object(s)`);
  return { counts, objects: objs, authUsers: users, dry };
}

// ---- baseline diff ---------------------------------------------------------------------------
/**
 * Count every non-empty public table plus the storage buckets. The selftest takes this before and
 * after a run and asserts they match: it is the only check that catches a table a trigger wrote
 * that nobody remembered to tear down. company_event, doc_versions and notifications were all
 * found this way.
 */
export const EXACT_TABLES = ['customers', 'leads', 'inquiries', 'quotes', 'supplier_capabilities',
  'supplier_capability_confirmation',
  'inquiry_matches', 'inquiry_intake', 'inquiry_requirement', 'inquiry_supplier_brief',
  'email_verifications', 'drawing_redaction_runs', 'documents', 'transactions', 'notifications',
  'company_event', 'doc_versions', 'comparison_run_v2', 'comparison_candidate_v2',
  // Added after an exception-window run left a dangling row here: the baseline check can only catch
  // what it counts, and this table was not on the list.
  'agent_actions'];

export async function snapshot() {
  const exact = await mgmtRead(REF, EXACT_TABLES.map((t) =>
    `select ${q(t)} as t, count(*)::bigint n from public.${t}`).join(' union all '));
  const rest = await mgmtRead(REF,
    `select 'storage:'||bucket_id as t, count(*)::bigint n from storage.objects group by bucket_id
     union all select 'auth.users', count(*)::bigint from auth.users`);
  const m = {};
  for (const r of [...exact, ...rest]) m[r.t] = Number(r.n);
  return m;
}

export function diffSnapshots(before, after) {
  const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])].sort();
  return keys.map((k) => ({ t: k, before: before[k] ?? 0, after: after[k] ?? 0 }))
             .filter((r) => r.before !== r.after);
}

// ---- CLI -------------------------------------------------------------------------------------
const isMain = !!process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('/demo_factory.mjs');

if (isMain) {
  const argv = process.argv.slice(2);
  const has = (f) => argv.includes(f);
  const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

  if (has('--purge')) {
    await purge({ dryRun: has('--dry-run') });
  } else if (has('--corpus')) {
    const n = Number(val('--corpus', '100'));
    const perTrade = Math.max(1, Math.round(n / TRADE_CODES.length));
    await withRun(async (run) => {
      const c = await makeBulkCorpus(run, { perTrade, customers: Number(val('--customers', '0')) });
      console.log(`corpus tag=${run.tag} suppliers=${c.suppliers.length}`);
    }, { keep: has('--keep') });
  } else {
    // --selftest (default): the factory proving itself against the rule it exists to enforce.
    await selftest();
  }
}

export async function selftest() {
  const checks = [];
  const ok = (name, pass, detail) => {
    checks.push({ name, pass, detail });
    console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(46)} ${detail}`);
  };

  const before = await snapshot();
  let out = null;
  try {
    out = await withRun(async (run) => {
      const cust = await makeCustomer(run, { mode: 'sql', locale: 'ar', full_name: 'عميل تجريبي' });
      ok('makeCustomer returns a usable identity', !!cust.id && !!cust.jwt && !!cust.email,
        `id=${cust.id ? 'yes' : 'NO'} jwt=${cust.jwt ? 'yes' : 'NO'} ${cust.email}`);

      const me = await call('customer_api', cust.jwt, { action: 'me' });
      ok('the made customer can act as itself', me.status === 200 && me.json?.customer?.id === cust.id,
        `HTTP ${me.status} me.id matches=${me.json?.customer?.id === cust.id}`);

      const supA = await makeSupplier(run, { trade: 'aluminium', variant: 0, variants: 4 });
      const supB = await makeSupplier(run, { trade: 'aluminium', variant: 3, variants: 4 });
      ok('makeSupplier returns id, email and JWT', !!supA.leadId && !!supA.email && !!supA.jwt,
        `lead=${supA.leadId} jwt=${supA.jwt ? 'yes' : 'NO'} ${supA.companyName}`);

      const supMe = await call('supplier_api', supA.jwt, { action: 'me' });
      ok('the made supplier can act as itself',
        supMe.status === 200 && Number(supMe.json?.supplier?.id) === Number(supA.leadId),
        `HTTP ${supMe.status} approval=${supMe.json?.supplier?.approval_status ?? '-'}`);

      // The variety claim, measured through the real function rather than asserted in a comment.
      // p_value is supplied on purpose: w_size scores 10 when the supplier states a range that
      // contains the job and 5 when it does not, so omitting p_value makes size_known false for
      // EVERY candidate and quietly shifts the whole ladder down by 5.
      const products = TRADES.aluminium.products;
      const scores = await mgmtRead(REF,
        `select supplier_id, score, product_hits from public.fn_match_capability(
           ARRAY['aluminium']::text[], 'executes', ${arr(products)}, '{}'::text[], null, 150000, null, 50)
         where supplier_id in (${supA.leadId}, ${supB.leadId}) order by score desc`);
      const sA = scores.find((r) => Number(r.supplier_id) === Number(supA.leadId));
      const sB = scores.find((r) => Number(r.supplier_id) === Number(supB.leadId));
      ok('capability variants score differently (not a tie)',
        !!sA && !!sB && Number(sA.score) > Number(sB.score),
        `variant0=${sA?.score ?? 'absent'} (${sA?.product_hits ?? '-'}/${products.length} products), ` +
        `decoy=${sB?.score ?? 'absent'} (${sB?.product_hits ?? '-'}/${products.length})`);
      ok('the zero-overlap decoy sits on the 5-point floor',
        !!sB && Number(sB.score) === 5 && Number(sB.product_hits) === 0,
        `score=${sB?.score ?? 'absent'} hits=${sB?.product_hits ?? '-'} (w_size*0.5 with min/max null)`);

      const inq = await makeInquiry(run, { customer: cust, trade: 'aluminium', status: 'sent' });
      ok('makeInquiry writes a tagged inquiry', !!inq.id, `id=${inq.id}`);
      const tagged = (await mgmtRead(REF,
        `select provenance->>'qd_run' t from public.inquiries where id=${q(inq.id)}`))[0]?.t;
      ok('every row carries the run tag', tagged === run.tag, `provenance.qd_run=${tagged}`);

      // rfq_ready is computed by trg_rfq_complete and cannot be set by hand. An inquiry that is not
      // ready cannot be dispatched, and dispatch_inquiry reports that as {"ok":true,
      // "skip":"not_rfq_ready"} - a 200 that contacted nobody.
      const ready = (await mgmtRead(REF,
        `select rfq_ready, completeness->>'score' score,
                completeness->'category_check'->>'required_total' req
           from public.inquiries where id=${q(inq.id)}`))[0] || {};
      ok('the inquiry satisfies the category checklist and is dispatchable',
        ready.rfq_ready === true,
        `rfq_ready=${ready.rfq_ready} score=${ready.score}/70 ` +
        `category_specs required fields answered=${ready.req}`);

      const qa = await makeQuote(run, { inquiry: inq, supplier: supA, amount: 125000 });
      const qb = await makeQuote(run, { inquiry: inq, supplier: supB, amount: 131750 });
      ok('makeQuote writes comparable quotes', !!qa.id && !!qb.id && qa.amount !== qb.amount,
        `${qa.amount} vs ${qb.amount}, status=${qa.status}`);

      const corpus = await makeBulkCorpus(run, { trades: ['hvac', 'glazing'], perTrade: 4 });
      ok('makeBulkCorpus builds a trade-spread corpus with zero model calls',
        corpus.suppliers.length === 8,
        `${corpus.suppliers.length} supplier(s) across ${corpus.trades.length} trade(s), 2 round trips`);

      // The capability flow through the PRODUCT rather than a raw INSERT. Zero model calls: the
      // only model call in capability_agent is on the `analyze` path, which is separately blocked
      // by fn_ai_route routing supplier_matching to tier=none.
      const supAgent = await makeSupplier(run, { trade: 'hvac', capability: 'agent' });
      const confirmed = (await mgmtRead(REF, `
        select c.review_status, c.confirmed_version, c.trades, c.roles,
               (select count(*)::int from public.supplier_capability_confirmation f
                 where f.supplier_id = c.supplier_id) as ledger
          from public.supplier_capabilities c where c.supplier_id = ${supAgent.leadId}`))[0] || {};
      ok('capability_agent confirm writes the real record',
        confirmed.review_status === 'confirmed' && Number(confirmed.ledger) === 1
          && Array.isArray(confirmed.trades) && confirmed.trades.includes('hvac'),
        `review_status=${confirmed.review_status} version=${confirmed.confirmed_version} ` +
        `ledger_rows=${confirmed.ledger} trades=${(confirmed.trades || []).join('+')}`);

      // The vocabulary gate is the reason to prefer the endpoint over an INSERT: a raw INSERT will
      // happily store a trade code that fn_match_capability can never match.
      const junk = await call('capability_agent', null, {
        __secret: await internalCred(), action: 'confirm', supplier_id: Number(supAgent.leadId),
        trades: ['not_a_real_trade'], roles: ['contractor'], products: ['x'],
      });
      ok('confirm refuses codes outside the controlled vocabulary',
        junk.status === 400 && junk.json?.error === 'need_at_least_one_trade_and_role',
        `HTTP ${junk.status} ${junk.json?.error ?? junk.text}`);

      const gated = await makeLicenceGatedSupplier(run, { trade: 'steel' });
      ok('the licence gate fixture actually opens the gate',
        gated.approval_status === 'action_required' && !!gated.licence_gate_reason,
        `approval_status=${gated.approval_status} reason=${gated.licence_gate_reason ?? 'none'}`);

      return { tag: run.tag };
    });
  } catch (e) {
    ok('factory body completed', false, String(e.message).slice(0, 160));
  }

  // This check compares absolute counts, so it assumes nothing else is writing to staging while it
  // runs. Running it alongside journey_test.mjs will fail it on the journey's rows, not on a
  // teardown defect - read the named counters before believing the failure.
  const after = await snapshot();
  const drift = diffSnapshots(before, after);
  ok('teardown returned the database to its baseline', drift.length === 0,
    drift.length
      ? drift.map((d) => `${d.t} ${d.before}->${d.after}`).join(', ') + '  (another writer running?)'
      : `no drift in ${Object.keys(after).length} counters`);

  const pass = checks.filter((c) => c.pass).length;
  console.log(`\nDEMO FACTORY SELFTEST ${pass}/${checks.length} on ${REF}`);
  process.exitCode = pass === checks.length ? 0 : 1;
  return { pass, total: checks.length };
}
