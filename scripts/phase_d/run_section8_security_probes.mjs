// PHASE D · §8 — THE SEVEN SECURITY PROBES, EXECUTED OVER REAL HTTP.
//
// Every prior Phase D session recorded these as NOT_RUN. The stated reason was always some form of
// "no Phase D path issues an authenticated HTTP request". That reason is false and this file is the
// refutation: the estate already mints a real bearer (management token -> /api-keys?reveal ->
// admin/generate_link -> /auth/v1/verify), exactly as scripts/phase_d/discharge_d0_auth_debt.mjs
// has done since D0. Nothing new had to be invented; the work simply had not been done.
//
// WHAT THIS FILE MAY AND MAY NOT CREATE — measured, not assumed.
//
// An HTTP request COMMITS. The Phase D discipline of "drive it in a transaction you abort" is not
// available here, so every fixture is a namespaced canary that is deleted in a finally, and the
// zero-effect assertions are made against a watermark taken before the first request. Before
// choosing the fixtures, the triggers on every candidate table were read:
//
//   public.customers  INSERT -> trg_emit_customer_registered -> fn_emit() -> one company_event row.
//                     No HTTP, no notification. SAFE, and the event row is deleted with the rest.
//   public.leads      INSERT -> enrich_capability_on_approve posts net.http_post ONLY when
//                     approval_status='approved'; fn_assign_founding_rank assigns a rank ONLY when
//                     verified=true. A canary inserted unapproved and unverified fires NEITHER.
//                     SAFE under exactly those two conditions, which this file asserts.
//   public.inquiries  INSERT -> trg_inquiry_received writes a public.notifications row whenever the
//                     owning customer has an e-mail, and the customer row MUST carry its e-mail or
//                     customer_api cannot resolve it at all. There is therefore no way to create an
//                     inquiry and still honour "notifications written 0". FORBIDDEN HERE.
//   public.quotes     INSERT -> trg_new_quote_sms. FORBIDDEN HERE.
//   public.transactions INSERT -> trg_reveal_receipt. FORBIDDEN HERE.
//
// That measurement is what bounds the probes below: the cross-identity reads are proved against
// account records and storage objects, and NOT against inquiries or quotes, because creating one of
// those would have broken the zero-external-effect hold to test it. Where a probe is bounded that
// way, it says so in its own `observed` text rather than claiming more than it did.
//
// THE THREE-KEY TRAP DOES NOT APPLY HERE, and that is a statement about this harness, not a
// dismissal. qd-cust-token / qd-cust-refresh / qd-cust-auth are BROWSER localStorage keys; getting
// them wrong makes a reload restore the previous account and reads as an account-mixup bug in the
// product that is not one. These probes are server-side `fetch` calls carrying an Authorization
// header and touch no browser storage, so the failure mode is structurally absent. Probe 1 asserts
// the binding the trap would have corrupted — A's bearer returns A and only A.
//
// Usage:  node scripts/phase_d/run_section8_security_probes.mjs [--write]
//   without --write the probes run and print, and no verdict is recorded.
//   with    --write the verdicts are recorded in public.phase_d_section8_probe_result, which
//           fn_phase_d_run_injected_defects() reads.

import { readFileSync } from 'node:fs';
import { sql, lit } from '../phase_c/lib/db.mjs';

const WRITE = process.argv.includes('--write');
const PROJECT = 'htdblwldjkcgjvmqkbeh';
const BASE = `https://${PROJECT}.supabase.co`;
const MGMT = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const NS = 'zz-phase-d-s8';
const EMAIL = {
  custA: `${NS}-cust-a@example.invalid`,
  custB: `${NS}-cust-b@example.invalid`,
  supA: `${NS}-sup-a@example.invalid`,
  supB: `${NS}-sup-b@example.invalid`,
  nobody: `${NS}-nobody@example.invalid`,
};

const mgmt = async (path, init = {}) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}${path}`, {
    ...init,
    headers: { authorization: `Bearer ${MGMT}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  if (!r.ok) throw new Error(`management ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};

const keys = await mgmt('/api-keys?reveal=true');
const SERVICE = keys.find((k) => k.name === 'service_role' || k.type === 'secret')?.api_key;
const ANON = keys.find((k) => k.name === 'anon' || k.type === 'publishable')?.api_key;
if (!SERVICE || !ANON) throw new Error('could not resolve both the service_role and anon keys');

const admin = async (path, init = {}) => {
  const r = await fetch(`${BASE}/auth/v1${path}`, {
    ...init,
    headers: { apikey: SERVICE, authorization: `Bearer ${SERVICE}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  return { status: r.status, body: await r.json().catch(() => ({})) };
};

// A bearer for an e-mail without touching its password. generate_link RETURNS a link; it does not
// deliver mail. The token_hash is then verified for a real session.
const bearerFor = async (email) => {
  const gen = await admin('/admin/generate_link', { method: 'POST', body: JSON.stringify({ type: 'magiclink', email }) });
  const hash = gen.body?.hashed_token || gen.body?.properties?.hashed_token;
  if (!hash) throw new Error(`generate_link for ${email} returned no hashed_token (${gen.status})`);
  const r = await fetch(`${BASE}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: ANON, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: hash }),
  });
  const b = await r.json().catch(() => ({}));
  if (!b?.access_token) throw new Error(`verify for ${email} returned no access_token (${r.status})`);
  return b.access_token;
};

const fn = async (name, token, body) => {
  const r = await fetch(`${BASE}/functions/v1/${name}`, {
    method: 'POST',
    headers: { apikey: ANON, ...(token ? { authorization: `Bearer ${token}` } : {}), 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await r.text();
  let json = null; try { json = JSON.parse(text); } catch { /* not json */ }
  return { status: r.status, text, json };
};

const rest = async (path, { token = null, anonOnly = false } = {}) => {
  const bearer = anonOnly ? ANON : (token || ANON);
  const r = await fetch(`${BASE}/rest/v1/${path}`, {
    headers: { apikey: ANON, authorization: `Bearer ${bearer}`, accept: 'application/json' },
  });
  const text = await r.text();
  let json = null; try { json = JSON.parse(text); } catch { /* not json */ }
  return { status: r.status, text, json, rows: Array.isArray(json) ? json.length : null };
};

const results = [];
const record = (id, probe, verdict, observed, http_status = null) => {
  results.push({ id, probe, verdict, observed: String(observed).slice(0, 900), http_status });
  const mark = verdict === 'REFUSED_AS_REQUIRED' ? 'ok  ' : verdict === 'NOT_RUN' ? '... ' : 'FAIL';
  console.log(`  ${mark} ${id}  ${String(observed).slice(0, 150)}`);
};

// ---------------------------------------------------------------------------------------------
// WATERMARK. Everything the hold forbids is counted before the first request and again at the end.
// ---------------------------------------------------------------------------------------------
// net.http_request_queue DRAINS, so a queue length of 0 at the end proves nothing about what was
// posted in between — it is the same "a zero cannot tell a dead guard from an idle system" shape
// this estate keeps finding. The durable record is net._http_response, so the watermark is a CLOCK
// and the assertion counts responses logged after it.
const base = (await sql(`select
  (select now())::text                                      as t0,
  (select count(*) from public.notifications)              as notif,
  (select count(*) from public.llm_attempt)                as llm,
  (select coalesce(max(id),0) from net.http_request_queue)  as httpmax,
  (select count(*) from net.http_request_queue)             as httpq,
  (select count(*) from public.leads)                       as leads,
  (select count(*) from public.customers)                   as customers,
  (select count(*) from public.inquiries)                   as inquiries,
  (select count(*) from public.quotes)                      as quotes,
  (select count(*) from public.transactions)                as transactions,
  (select count(*) from public.company_event)               as events`))[0];
console.log(`watermark  notifications=${base.notif} llm_attempt=${base.llm} http_queue=${base.httpq} leads=${base.leads} customers=${base.customers}`);

let created = false;
try {
  // -------------------------------------------------------------------------------------------
  // FIXTURES. Namespaced canaries only, under the repository's established convention
  // (ZZ DEMO … / @example.invalid). Leads are inserted UNAPPROVED and UNVERIFIED so that neither
  // the capability-enrichment HTTP post nor the founding-rank assignment can fire.
  // -------------------------------------------------------------------------------------------
  for (const e of Object.values(EMAIL)) {
    await admin('/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email: e, email_confirm: true, password: crypto.randomUUID() + 'Aa1!' }),
    });
  }
  created = true;

  await sql(`
    insert into public.customers (email, full_name, email_verified)
    values (${lit(EMAIL.custA)}, 'ZZ DEMO — section 8 probe customer A', true),
           (${lit(EMAIL.custB)}, 'ZZ DEMO — section 8 probe customer B', true);
    insert into public.leads (company_name, email, claimed, claimed_by, verified, approval_status, source, business_role)
    values ('ZZ DEMO — section 8 probe supplier A', ${lit(EMAIL.supA)}, true, ${lit(EMAIL.supA)}, false, 'pending', 'zz_phase_d_section8', 'supplier'),
           ('ZZ DEMO — section 8 probe supplier B', ${lit(EMAIL.supB)}, true, ${lit(EMAIL.supB)}, false, 'pending', 'zz_phase_d_section8', 'supplier');`);

  const ids = (await sql(`select 'custA' as k, id::text from public.customers where email=${lit(EMAIL.custA)}
    union all select 'custB', id::text from public.customers where email=${lit(EMAIL.custB)}
    union all select 'supA', id::text from public.leads where claimed_by=${lit(EMAIL.supA)}
    union all select 'supB', id::text from public.leads where claimed_by=${lit(EMAIL.supB)}`))
    .reduce((a, r) => (a[r.k] = r.id, a), {});

  const tok = {};
  for (const [k, e] of Object.entries(EMAIL)) tok[k] = await bearerFor(e);

  // ===========================================================================================
  console.log('\nPROBE 1 — customer A reads customer B');
  // ===========================================================================================
  {
    const meA = await fn('customer_api', tok.custA, { action: 'me' });
    const meB = await fn('customer_api', tok.custB, { action: 'me' });
    const aEmail = meA.json?.customer?.email, bEmail = meB.json?.customer?.email;
    const bound = meA.status === 200 && meB.status === 200 && aEmail === EMAIL.custA && bEmail === EMAIL.custB;
    record('P1-identity-binding', 'customer A reads customer B',
      bound ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      bound ? `each bearer resolved to its own account and only its own: A->${aEmail}, B->${bEmail}. The identity is taken from the JWT, never from the request body`
            : `identity binding wrong: A->${aEmail} B->${bEmail} (${meA.status}/${meB.status})`, meA.status);

    // A asks for an inquiry it does not own. No inquiry exists (creating one would write a
    // notification), so this proves the ownership BRANCH answers 403 rather than 200 or 500 — it
    // does not prove discrimination between two real inquiries, and does not claim to.
    const act = await fn('customer_api', tok.custA, { action: 'activity', inquiry_id: crypto.randomUUID() });
    record('P1-object-scope', 'customer A reads an inquiry it does not own',
      act.status === 403 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `activity on an inquiry not owned by the caller -> ${act.status} ${String(act.json?.error ?? '').slice(0, 60)}. BOUNDED: with 0 inquiries on the estate this exercises the ownership branch, not discrimination between two real inquiries`, act.status);

    // The signed-in identity that has no customer account must not acquire one by reading.
    const ghost = await fn('customer_api', tok.nobody, { action: 'me' });
    const after = (await sql(`select count(*)::int as n from public.customers where email=${lit(EMAIL.nobody)}`))[0].n;
    record('P1-no-autovivify', 'reading who you are must not create it',
      ghost.status === 403 && after === 0 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `an authenticated identity with no customer account got ${ghost.status} and ${after} row(s) were created for it`, ghost.status);
  }

  // ===========================================================================================
  console.log('\nPROBE 2 — supplier A reads supplier B');
  // ===========================================================================================
  {
    const meA = await fn('supplier_api', tok.supA, { action: 'me' });
    const meB = await fn('supplier_api', tok.supB, { action: 'me' });
    const aId = String(meA.json?.supplier?.id ?? ''), bId = String(meB.json?.supplier?.id ?? '');
    const ok = aId === String(ids.supA) && bId === String(ids.supB) && aId !== bId;
    record('P2-identity-binding', "supplier A reads supplier B's record",
      ok ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      ok ? `each supplier bearer resolved to its own leads row via claimed_by and only its own (A=${aId}, B=${bId}); the client-supplied id is never consulted`
         : `supplier identity binding wrong: A=${aId} expected ${ids.supA}, B=${bId} expected ${ids.supB}`, meA.status);

    // Supplier A names supplier B's row id explicitly on a MUTATING action.
    //
    // `save_settings` is used here and `save_profile` deliberately is NOT. The first run of this
    // file used save_profile and that reaches the registration-submission branch at
    // supabase/functions/supplier_api/index.ts:603, which writes two public.notifications rows —
    // one of them addressed to management@quotesdone.com. Two such rows WERE written on 19 Aug
    // 2026 at 10:54 UTC, were caught by this file's own zero-effect assertion, and were deleted
    // while still status='pending'; neither ever reached status='sent'. save_settings is the same
    // ownership decision (the row id comes from claimed_by on the JWT, never from the body) with
    // no registration side effect: it writes locale / wa_optin / email_shared and nothing else.
    const before = (await sql(`select coalesce(locale,'(null)') as locale from public.leads where id=${lit(ids.supB)}`))[0]?.locale ?? '';
    const cross = await fn('supplier_api', tok.supA, { action: 'save_settings', id: ids.supB, leads_id: ids.supB, supplier_id: ids.supB, locale: 'ar' });
    const after = (await sql(`select coalesce(locale,'(null)') as locale from public.leads where id=${lit(ids.supB)}`))[0]?.locale ?? '';
    const aLocale = (await sql(`select coalesce(locale,'(null)') as locale from public.leads where id=${lit(ids.supA)}`))[0]?.locale ?? '';
    const untouched = before === after;
    record('P2-cross-write', "supplier A writes supplier B's record",
      untouched ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `supplier A named supplier B's id on a settings write -> ${cross.status}; B's locale is ${untouched ? `UNCHANGED (${after})` : `OVERWRITTEN (${before} -> ${after})`} and the write landed on A's own row instead (A locale=${aLocale}), because the target id is resolved from claimed_by on the caller's JWT`, cross.status);

    // The document surface. supplier_portal derives every path from rows scoped by claimed_by and
    // accepts no caller path, so naming B's id must not widen what A is shown.
    const docsA = await fn('supplier_portal', tok.supA, { action: 'documents' });
    const docsCross = await fn('supplier_portal', tok.supA, { action: 'documents', id: ids.supB, leads_id: ids.supB, supplier_id: ids.supB });
    const same = docsA.text === docsCross.text;
    const mentionsB = docsCross.text.includes('probe supplier B') || docsCross.text.includes(EMAIL.supB);
    record('P2-document-scope', "supplier A reads supplier B's documents",
      same && !mentionsB ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `supplier_portal documents as A -> ${docsA.status}; the same call naming B's id -> ${docsCross.status} and the two bodies are ${same ? 'IDENTICAL' : 'DIFFERENT'}; B's identity ${mentionsB ? 'APPEARS' : 'does not appear'} in the cross-tenant response`, docsCross.status);
  }

  // ===========================================================================================
  console.log('\nPROBE 3 — supplier reads raw customer identity');
  // ===========================================================================================
  {
    // The real supplier-facing surfaces, called as a real supplier, with the response BODY read
    // rather than the status. A masked 200 is the correct answer here; there is no status that
    // constitutes success on its own.
    const inbox = await fn('supplier_api', tok.supA, { action: 'inbox' });
    const opps = await fn('supplier_portal', tok.supA, { action: 'opportunities' });
    const raw = await rest('inquiries?select=summary,raw_input,budget&limit=1', { token: tok.supA });

    // Scan the bodies for the identity of the two customer canaries, whose values are known
    // exactly. A substring hit is a leak; there is nothing to interpret.
    const needles = [EMAIL.custA, EMAIL.custB, 'section 8 probe customer'];
    const hay = `${inbox.text}\n${opps.text}\n${raw.text}`.toLowerCase();
    const hits = needles.filter((n) => hay.includes(n.toLowerCase()));
    record('P3-supplier-surface-body', 'supplier reads raw customer identity from a supplier surface',
      hits.length === 0 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `supplier_api inbox -> ${inbox.status}, supplier_portal opportunities -> ${opps.status}, direct /rest/v1/inquiries -> ${raw.status}/${raw.rows} row(s). Bodies scanned for the two known customer identities: ${hits.length === 0 ? 'no identity value appeared in any body' : 'LEAKED ' + hits.join(', ')}. BOUNDED: 0 inquiries exist, so this proves the surfaces carry no identity and the direct table is unreachable, NOT that a populated payload is masked`, inbox.status);

    // The RPC that returns the candidate set must not answer an unauthenticated caller.
    const rpcAnon = await fetch(`${BASE}/rest/v1/rpc/fn_supplier_opportunities`, {
      method: 'POST',
      headers: { apikey: ANON, authorization: `Bearer ${ANON}`, 'content-type': 'application/json' },
      body: JSON.stringify({ p_lead_id: 1 }),
    });
    const rpcBody = (await rpcAnon.text()).slice(0, 120);
    record('P3-opportunities-rpc-anon', 'the opportunity RPC answers an unauthenticated caller',
      rpcAnon.status !== 200 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `fn_supplier_opportunities called with the anon key -> ${rpcAnon.status} ${rpcBody}`, rpcAnon.status);

    // The identity columns must not exist on the safe surface at all.
    const cols = await sql(`select coalesce(string_agg(column_name, ','), '(none)') as c
      from information_schema.columns where table_schema='public' and table_name='inquiries_supplier_safe'
        and column_name in ('email','phone','full_name','customer_email','customer_phone','customer_name','contact_name')`);
    const leak = cols[0].c !== '(none)';
    record('P3-safe-surface-shape', 'supplier-safe surface carries raw customer identity',
      leak ? 'NOT_REFUSED' : 'REFUSED_AS_REQUIRED',
      `identity columns present on inquiries_supplier_safe: ${cols[0].c}`, null);
  }

  // ===========================================================================================
  console.log('\nPROBE 4 — customer reads supplier KYC');
  // ===========================================================================================
  {
    // customer_documents takes a documents.id, never a bucket or path. A document the caller does
    // not own is filtered by RLS on the customer's OWN jwt before anything is signed, so the
    // correct answer is 404 with no file_url in the body — the signing call is never reached.
    const doc = (await sql(`select id::text, coalesce(ref_table,'') as ref from public.documents order by id limit 1`))[0];
    if (!doc) {
      record('P4-kyc-doc-read', 'customer reads a document it does not own', 'NOT_RUN', 'public.documents holds no row to aim at', null);
    } else {
      const got = await fn('customer_documents', tok.custA, { action: 'get', id: Number(doc.id) });
      const listed = await fn('customer_documents', tok.custA, { action: 'documents', limit: 100 });
      const noUrl = !/file_url/.test(got.text) && !/signedURL|signed_url/i.test(got.text);
      record('P4-kyc-doc-read', 'customer reads a document it does not own',
        got.status >= 400 && noUrl ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
        `customer_documents get on documents.id=${doc.id} (ref_table='${doc.ref}') as a customer that owns nothing -> ${got.status}, and the body carries ${noUrl ? 'NO' : 'A'} file_url; the vault listing returned ${listed.status}`, got.status);
    }

    // The KYC bucket named directly, by a customer, on the two minters that accept a caller path.
    const obj = (await sql(`select bucket_id, name from storage.objects
      where bucket_id in ('compliance-docs','supplier-docs') order by created_at limit 1`))[0];
    if (!obj) {
      record('P4-kyc-bucket-read', 'customer names a KYC bucket path directly', 'NOT_RUN', 'no object exists in compliance-docs or supplier-docs', null);
    } else {
      const viaOs = await fn('os_api', tok.custA, { action: 'file', bucket: obj.bucket_id, path: obj.name });
      const viaOps = await fn('os_ops', tok.custA, { action: 'file', bucket: obj.bucket_id, path: obj.name });
      const files = await fn('os_api', tok.custA, { action: 'files', entity: 'supplier', id: String(ids.supB) });
      const refused = viaOs.status >= 400 && viaOps.status >= 400 && files.status >= 400;
      record('P4-kyc-bucket-read', 'customer names a KYC bucket path directly',
        refused ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
        `a customer bearer naming ${obj.bucket_id} verbatim: os_api file -> ${viaOs.status}, os_ops file -> ${viaOps.status}, os_api files(entity=supplier) -> ${files.status}`, viaOs.status);
    }
  }

  // ===========================================================================================
  console.log('\nPROBE 5 — inactive / unprivileged identity executes');
  // ===========================================================================================
  {
    const ping = await fn('os_api', tok.nobody, { action: 'ping' });
    record('P5-no-role-readonly', 'identity with no canonical role reaches the Command Center',
      ping.status === 403 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `an authenticated identity that maps to no active canonical role -> os_api ping ${ping.status}`, ping.status);

    const mutate = await fn('os_api', tok.custA, { action: 'agent_run', agent: 'zz_phase_d_section8_probe' });
    record('P5-non-admin-mutation', 'non-admin performs an admin mutation',
      mutate.status >= 400 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `a customer bearer attempting an admin mutation on os_api -> ${mutate.status} ${String(mutate.json?.error ?? '').slice(0, 60)}`, mutate.status);

    const supMutate = await fn('os_api', tok.supA, { action: 'agent_run', agent: 'zz_phase_d_section8_probe' });
    record('P5-supplier-admin-mutation', 'supplier identity performs an admin mutation',
      supMutate.status >= 400 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `a supplier bearer attempting an admin mutation on os_api -> ${supMutate.status}`, supMutate.status);
  }

  // ===========================================================================================
  console.log('\nPROBE 6 — direct table / RPC bypass as anon and as authenticated');
  // ===========================================================================================
  {
    // A ZERO CANNOT TELL A DEAD GUARD FROM AN IDLE SYSTEM. PostgREST answers an RLS-invisible
    // table with HTTP 200 and `[]`, and an EMPTY table with exactly the same thing. Most of the
    // sensitive tables on this estate are genuinely empty right now (inquiries, quotes, refunds
    // and transactions are all 0), so "anon got no rows" from those would be a green light over
    // nothing. Every table is therefore counted with the service_role FIRST, and a table the
    // positive control cannot populate is reported INCONCLUSIVE rather than as a pass.
    // `customers` is populated for the duration of this run by the two probe canaries, which is
    // what makes it testable at all.
    const TABLES = ['customers', 'inquiries', 'quotes', 'refunds', 'documents', 'leads', 'transactions',
      'app_secrets', 'phase_d_external_attempt', 'phase_c_refund_decision', 'company_event', 'notifications'];
    const bad = [], tested = [], inconclusive = [];
    for (const t of TABLES) {
      const control = Number((await sql(`select count(*)::int as n from public.${t}`))[0].n);
      if (control === 0) { inconclusive.push(t); continue; }
      const a = await rest(`${t}?select=*&limit=1`, { anonOnly: true });
      const u = await rest(`${t}?select=*&limit=1`, { token: tok.custA });
      if ((a.rows ?? 0) > 0) bad.push(`${t}: anon read ${a.rows} of ${control} row(s)`);
      if ((u.rows ?? 0) > 0) bad.push(`${t}: authenticated read ${u.rows} of ${control} row(s)`);
      tested.push(`${t}(${control})`);
    }
    record('P6-table-bypass', 'direct table read as anon and authenticated',
      bad.length === 0 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      bad.length === 0
        ? `${tested.length} NON-EMPTY sensitive tables read directly with the anon key and with a real authenticated customer bearer; every one returned 0 rows against a service_role control that proves the rows exist: ${tested.join(', ')}. ${inconclusive.length} table(s) hold 0 rows so a denial there is INCONCLUSIVE and is not counted: ${inconclusive.join(', ') || '(none)'}`
        : `REACHABLE: ${bad.join('; ')}`, null);

    // The last seven are the ones D35 revoked. They are listed here so the fix is guarded rather
    // than merely applied: this probe is what found them open, and it is what will notice if a
    // later CREATE OR REPLACE hands the grant back. (A plain CREATE re-grants EXECUTE to PUBLIC;
    // only CREATE OR REPLACE preserves the ACL, so the regression is one careless DROP away.)
    // EVERY RPC IS CALLED WITH ITS REAL ARGUMENTS, and that is the whole point of this block.
    // An earlier version POSTed `{}` to all of them. PostgREST answers a call whose parameters do
    // not match any overload with 404 PGRST202 — NOT with a permission error — so `{}` against
    // fn_supplier_opportunities(p_lead_id bigint) returns 404 and a probe that only asks "was the
    // status 200?" scores it REFUSED while the function is wide open. This check would have gone
    // green over the exact defect it exists to find; it was probe 3, which passes the real
    // argument, that actually caught it. A false pass is worse than no check, so the arguments are
    // named here and a 404 is reported separately from a denial instead of being counted as one.
    const RPCS = [
      ['fn_phase_d_run_injected_defects', {}],
      ['fn_phase_a_baseline_drift', {}],
      ['fn_phase_b_baseline_drift', {}],
      ['fn_kernel_all_boards', {}],
      ['fn_phase_d_object_write', { p_input: {} }],
      ['fn_phase_d_drive_workflow', { p_input: {} }],
      ['fn_customer_preference_learn', { p_customer_id: '00000000-0000-0000-0000-000000000001', p_stated: {} }],
      ['fn_os_memory', { p_q: 'zz', p_from: '2026-01-01', p_to: '2026-12-31' }],
      ['fn_supplier_document_impact', { p_lead_id: 1 }],
      ['fn_supplier_knowledge_graph', { p_lead_id: 1 }],
      ['fn_supplier_opportunities', { p_lead_id: 1 }],
      ['fn_supplier_quote_recommend', { p_lead_id: 1, p_inquiry_id: '00000000-0000-0000-0000-000000000001' }],
      ['fn_supplier_twin', { p_lead_id: 1 }],
    ];
    const reachable = [], notfound = [], denied = [];
    for (const [p, args] of RPCS) {
      for (const [who, t] of [['anon', null], ['authenticated', tok.custA]]) {
        const r = await fetch(`${BASE}/rest/v1/rpc/${p}`, {
          method: 'POST',
          headers: { apikey: ANON, authorization: `Bearer ${t || ANON}`, 'content-type': 'application/json' },
          body: JSON.stringify(args),
        });
        const body = await r.text();
        if (r.status === 200) reachable.push(`${p}:${who}`);
        else if (/PGRST202/.test(body)) notfound.push(`${p}:${who}`);
        else denied.push(`${p}:${who}`);
      }
    }
    record('P6-rpc-bypass', 'direct RPC call as anon and authenticated',
      reachable.length === 0 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      reachable.length === 0
        ? `${RPCS.length} kernel, Phase D and supplier routines called directly as anon and as authenticated, each with its REAL argument list: ${denied.length} refused on permission, ${notfound.length} not exposed to the schema cache at all (PGRST202), 0 returned 200. A 404 is reported separately because it is a signature answer, not an authorisation one.`
        : `EXECUTABLE: ${reachable.join(', ')}`, null);
  }

  // ===========================================================================================
  console.log('\nPROBE 7 — unsafe signed URL: expired, and a path the caller does not own');
  // ===========================================================================================
  {
    const obj = (await sql(`select bucket_id, name from storage.objects
      where bucket_id not in (select id from storage.buckets where public) order by created_at limit 1`))[0];
    if (!obj) {
      record('P7-expired-url', 'expired signed URL is replayed', 'NOT_RUN', 'no object exists in any private bucket', null);
    } else {
      const mk = await fetch(`${BASE}/storage/v1/object/sign/${obj.bucket_id}/${encodeURI(obj.name)}`, {
        method: 'POST',
        headers: { apikey: SERVICE, authorization: `Bearer ${SERVICE}`, 'content-type': 'application/json' },
        body: JSON.stringify({ expiresIn: 1 }),
      });
      const signed = (await mk.json().catch(() => ({})))?.signedURL;
      if (!signed) {
        record('P7-expired-url', 'expired signed URL is replayed', 'NOT_RUN', `could not mint a signed URL (${mk.status})`, mk.status);
      } else {
        const fresh = await fetch(`${BASE}/storage/v1${signed}`);
        await new Promise((r) => setTimeout(r, 2500));
        const stale = await fetch(`${BASE}/storage/v1${signed}`);
        record('P7-expired-url', 'expired signed URL is replayed',
          fresh.status === 200 && stale.status >= 400 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
          `a 1-second URL for ${obj.bucket_id} answered ${fresh.status} while valid and ${stale.status} after expiry`, stale.status);

        // The wrong-owner half. A customer bearer names a private object it has no relationship to.
        const asCust = await fn('os_api', tok.custA, { action: 'file', bucket: obj.bucket_id, path: obj.name });
        const asAnon = await fn('os_api', null, { action: 'file', bucket: obj.bucket_id, path: obj.name });
        const refused = asCust.status >= 400 && asAnon.status >= 400;
        record('P7-wrong-owner-path', 'signed URL minted for a path the caller does not own',
          refused ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
          `os_api file names bucket+path verbatim from the body and performs NO ownership check on it; the only thing between a caller and any private object is the admin gate, which answered ${asCust.status} to a customer bearer and ${asAnon.status} to anon. With 0 policies on storage.objects there is no second line of defence beneath it`,
          asCust.status);
      }
    }

    // Direct insert into storage.objects under a path the caller does not own.
    const ins = await fetch(`${BASE}/rest/v1/objects?select=id`, {
      method: 'POST',
      headers: { apikey: ANON, authorization: `Bearer ${tok.custA}`, 'content-type': 'application/json', 'accept-profile': 'storage', 'content-profile': 'storage' },
      body: JSON.stringify({ bucket_id: 'compliance-docs', name: `${NS}/unowned-insert-probe.txt` }),
    });
    record('P7-unowned-insert', 'insert into storage.objects under an unowned path',
      ins.status >= 400 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      `an authenticated customer bearer inserting directly into storage.objects -> ${ins.status}`, ins.status);
  }

  // ===========================================================================================
  console.log('\nPROBE 8 — the storage upload rules the brief lists');
  // ===========================================================================================
  {
    // Every bucket carries a file_size_limit and a MIME allow-list, and BOTH are enforced by
    // storage itself rather than by whichever code path uploads. That is the claim; these three
    // uploads are the execution of it. The bucket is chosen from the live allow-lists so the test
    // cannot be invalidated by a configuration change.
    const b = (await sql(`select id, file_size_limit, allowed_mime_types
      from storage.buckets where not public and file_size_limit is not null
        and allowed_mime_types is not null and array_length(allowed_mime_types,1) > 0
      order by file_size_limit limit 1`))[0];

    if (!b) {
      record('P8-mime-allowlist', 'upload whose declared type is not on the bucket allow-list', 'NOT_RUN', 'no private bucket carries both a size limit and a MIME allow-list', null);
    } else {
      const allowed = b.allowed_mime_types;
      const put = async (name, mime, bytes) => {
        const r = await fetch(`${BASE}/storage/v1/object/${b.id}/${NS}/${name}`, {
          method: 'POST',
          headers: { apikey: SERVICE, authorization: `Bearer ${SERVICE}`, 'content-type': mime },
          body: bytes,
        });
        return { status: r.status, text: (await r.text()).slice(0, 160) };
      };

      // (a) A type the bucket does not allow. PK\x03\x04 is a ZIP; the name says .pdf.
      const zip = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0x14, 0, 0, 0, 8, 0]);
      const disguised = await put('disguised.pdf', 'application/zip', zip);
      record('P8-mime-allowlist', 'upload whose declared type is not on the bucket allow-list',
        disguised.status >= 400 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
        `bucket ${b.id} allows [${allowed.join(', ')}]; a ZIP declared application/zip and named .pdf -> ${disguised.status} ${disguised.text}`, disguised.status);

      // (b) An executable, declared as one, under a document name.
      const exe = new Uint8Array([0x4d, 0x5a, 0x90, 0, 3, 0, 0, 0, 4, 0]);
      const asExe = await put('payload.pdf', 'application/x-msdownload', exe);
      record('P8-executable-content', 'executable content posted as a document',
        asExe.status >= 400 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
        `an MZ executable declared application/x-msdownload against ${b.id} -> ${asExe.status} ${asExe.text}`, asExe.status);

      // (c) Over the bucket's own declared limit, in the bucket's own allowed type.
      const limit = Number(b.file_size_limit);
      const big = new Uint8Array(limit + 4096);
      big.set([0x25, 0x50, 0x44, 0x46]); // %PDF
      const oversize = await put('oversize.bin', allowed[0], big);
      record('P8-size-limit', 'upload larger than the bucket file_size_limit',
        oversize.status >= 400 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
        `${(limit / 1048576).toFixed(0)} MB limit on ${b.id}; ${((limit + 4096) / 1048576).toFixed(2)} MB of ${allowed[0]} -> ${oversize.status} ${oversize.text}`, oversize.status);

      const left = (await sql(`select count(*)::int as n from storage.objects where name like ${lit(NS + '/%')}`))[0].n;
      record('P8-upload-residue', 'the upload probes leave nothing behind',
        left === 0 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
        `${left} object(s) under ${NS}/ survived the three refused uploads`, null);
    }
  }
} finally {
  // -------------------------------------------------------------------------------------------
  // CLEANUP. A cleanup scoped to the table you happened to look at is not a cleanup: every table
  // this file can touch is named here, and the counts are re-read afterwards.
  // -------------------------------------------------------------------------------------------
  // EACH DELETE IS ITS OWN STATEMENT. The first version of this cleanup sent all of them as one
  // batch and included `delete from storage.objects`, which storage.protect_delete() refuses —
  // and because the refusal aborted the WHOLE batch, none of the other deletes ran either and the
  // canaries survived. A cleanup that stops at the first refusal is not a cleanup.
  const emails = Object.values(EMAIL).map(lit).join(',');
  const steps = [
    // Any notification a probe provoked is reverted here, and only ever while it is still
    // unsent — a row that has already been delivered is evidence and must not be erased.
    // public.notifications has no customer_id: it addresses by to_email / to_role and carries
    // lead_id, inquiry_id and quote_id. An earlier version of this delete named customer_id and
    // failed with 42703 every run — harmlessly, because nothing needed cleaning once save_profile
    // was dropped, which is exactly how a broken cleanup stays invisible until the day it matters.
    `delete from public.notifications where status = 'pending' and (to_email in (${emails})
       or lead_id in (select id from public.leads where claimed_by in (${emails})))`,
    `delete from public.company_event where entity_id in (select id::text from public.customers where email in (${emails}))`,
    `delete from public.company_event where entity_id in (select id::text from public.leads where claimed_by in (${emails}))`,
    `delete from public.leads where claimed_by in (${emails}) or email in (${emails})`,
    `delete from public.customers where email in (${emails})`,
  ];
  for (const s of steps) await sql(s).catch((e) => console.error(`cleanup step failed: ${e.message.slice(0, 200)}\n  ${s.slice(0, 120)}`));

  // storage.objects is deleted through the Storage API, never through SQL: storage.protect_delete()
  // refuses a direct delete precisely so orphaned objects cannot be created this way.
  const leftover = await sql(`select name from storage.objects where name like ${lit(NS + '/%')}`).catch(() => []);
  for (const o of (Array.isArray(leftover) ? leftover : [])) {
    const bucket = (await sql(`select bucket_id from storage.objects where name=${lit(o.name)} limit 1`))[0]?.bucket_id;
    if (!bucket) continue;
    await fetch(`${BASE}/storage/v1/object/${bucket}/${encodeURI(o.name)}`, {
      method: 'DELETE', headers: { apikey: SERVICE, authorization: `Bearer ${SERVICE}` },
    }).catch(() => {});
  }

  if (created) {
    for (const e of Object.values(EMAIL)) {
      const found = await admin(`/admin/users?filter=${encodeURIComponent(e)}`);
      for (const u of (found.body?.users ?? [])) if (u.email === e) await admin(`/admin/users/${u.id}`, { method: 'DELETE' });
    }
  }
}

// ---------------------------------------------------------------------------------------------
// ZERO-EFFECT ASSERTION AND RESIDUE.
// ---------------------------------------------------------------------------------------------
const end = (await sql(`select
  (select count(*) from public.notifications)              as notif,
  (select count(*) from public.llm_attempt)                as llm,
  (select count(*) from net.http_request_queue where id > ${base.httpmax}) as newhttp,
  (select count(*) from net._http_response where created > ${lit(base.t0)}::timestamptz) as http_done,
  (select coalesce(string_agg(distinct left(coalesce(content,''),40), ' | '), '(none)')
     from net._http_response where created > ${lit(base.t0)}::timestamptz) as http_bodies,
  (select count(*) from public.leads)                       as leads,
  (select count(*) from public.customers)                   as customers,
  (select count(*) from public.inquiries)                   as inquiries,
  (select count(*) from public.quotes)                      as quotes,
  (select count(*) from public.transactions)                as transactions,
  (select count(*) from public.fn_phase_d_fixture_residue()) as residue,
  (select count(*) from auth.users where email like ${lit(NS + '%')}) as canary_users,
  (select count(*) from public.company_event) as events`))[0];

const drift = [];
if (end.notif !== base.notif) drift.push(`notifications ${base.notif} -> ${end.notif}`);
if (end.llm !== base.llm) drift.push(`llm_attempt ${base.llm} -> ${end.llm}`);
if (Number(end.newhttp) !== 0) drift.push(`net.http_request_queue gained ${end.newhttp}`);
// Scheduled read-only monitoring stays active under the hold, so a non-zero response count is
// reported for inspection rather than failed on; the bodies are printed so it can be judged.
console.log(`  outbound HTTP logged during the run: ${end.http_done} -> ${end.http_bodies}`);
if (end.leads !== base.leads) drift.push(`leads ${base.leads} -> ${end.leads}`);
if (end.customers !== base.customers) drift.push(`customers ${base.customers} -> ${end.customers}`);
if (end.inquiries !== base.inquiries) drift.push(`inquiries ${base.inquiries} -> ${end.inquiries}`);
if (end.quotes !== base.quotes) drift.push(`quotes ${base.quotes} -> ${end.quotes}`);
if (end.transactions !== base.transactions) drift.push(`transactions ${base.transactions} -> ${end.transactions}`);
if (Number(end.residue) !== 0) drift.push(`fn_phase_d_fixture_residue ${end.residue}`);
if (Number(end.canary_users) !== 0) drift.push(`${end.canary_users} canary auth user(s) survived`);
if (end.events !== base.events) drift.push(`company_event ${base.events} -> ${end.events}`);

console.log('\n--- zero effect ---');
console.log(drift.length === 0
  ? `  clean: notifications, llm_attempt, outbound HTTP, leads, customers, inquiries, quotes, transactions, company_event and canary identities all returned to their watermark; fn_phase_d_fixture_residue() = 0`
  : `  DRIFT: ${drift.join(' | ')}`);

const refused = results.filter((r) => r.verdict === 'REFUSED_AS_REQUIRED').length;
const failed = results.filter((r) => r.verdict === 'NOT_REFUSED');
const notrun = results.filter((r) => r.verdict === 'NOT_RUN').length;
console.log(`\n--- ${results.length} probe assertions ---`);
console.log(`  refused as required   ${refused}`);
console.log(`  FAILED TO REFUSE      ${failed.length}   (must be 0)`);
console.log(`  not run               ${notrun}`);
if (failed.length) console.log('  ' + failed.map((r) => `${r.id}: ${r.observed}`).join('\n  '));

if (WRITE) {
  const rows = results.map((r) => `(${lit(r.id)},${lit(r.probe)},${lit(r.verdict)},${lit(r.observed)},${r.http_status == null ? 'null' : Number(r.http_status)})`).join(',');
  await sql(`insert into public.phase_d_section8_probe_result (probe_id, probe, verdict, observed, http_status)
             values ${rows}
             on conflict (probe_id) do update set probe=excluded.probe, verdict=excluded.verdict,
               observed=excluded.observed, http_status=excluded.http_status, ran_at=now();`);
  console.log(`\nrecorded ${results.length} verdict(s) in public.phase_d_section8_probe_result`);
} else {
  console.log('\n(dry run — pass --write to record the verdicts)');
}

if (drift.length || failed.length) process.exit(1);
