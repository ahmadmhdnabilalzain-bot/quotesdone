// SPEC FILE #4, sections 14-18 — Document Vault, Communication Center, AI Memory, Mobile App.
// 21 requirements, scored against PRODUCTION (section 15, Negotiation AI, retired 21 Sep 2026).
//
// This row is about WHAT THE CUSTOMER SEES, so a capability that is computed server-side and
// rendered nowhere is MISSING however well the backend works. Half the checks below therefore
// measure the FRONTEND (src/) and the EDGE FUNCTIONS (supabase/functions/) as well as the
// database, and they do it the same way the SQL checks do: by counting something, and printing
// the count that produced the verdict.
//
// PRODUCTION HAS ZERO CUSTOMERS, ZERO INQUIRIES, ZERO QUOTES AND ZERO TRANSACTIONS. Every check
// here scores the MECHANISM. Where a count of customer-owned rows would be the natural evidence,
// the evidence says so out loud instead of letting 0 masquerade as a verdict.
//
// THE FIVE DEFECTS THAT MADE THE ROW #2 SCORER WRONG, AND WHERE EACH IS ANSWERED HERE:
//
//  1. THE ONLY READER IS THE WRITER. Every reader count in this file removes the routines that
//     WRITE the object by pattern (NOT_WRITER), not by the inert `proname <> '<table>'`
//     self-exclusion — no routine is ever called `documents` or `customer_preference`, so that
//     clause never removes anything for a table. Overloads are collapsed with count(DISTINCT
//     proname). mem-applied-to-future-rfqs is the sharp case: the SAME table is written by one
//     trigger on inquiries and read by another, so the reader is identified by a body that selects
//     customer_preference and does NOT write it.
//
//  2. POPULATION STANDING IN FOR DELIVERY. doc-nl-search, doc-answer-with-fields, neg-market-average
//     and mem-customer-visible all have a real, working, POPULATED backend mechanism. Each scores
//     on whether it reaches a customer — a customer-authed endpoint and a rendered surface — and
//     the evidence prints the mechanism AND the delivery count side by side so a MISSING verdict
//     names what exists rather than denying it.
//
//  3. ONE ROW SCORES A WHOLE MECHANISM. doc-store-six-kinds names SIX kinds and asks a per-kind
//     NOT EXISTS, not `count(distinct kind) > 0`. doc-ai-extraction asks that NO terminal document
//     lacks an extraction, not that one has one.
//
//  4. SATISFIABLE BY FLIPPING A FLAG. public.documents.kind is free text with no check constraint,
//     so "the vault stores contracts" would be satisfiable by typing the word 'contract' into one
//     row. A kind counts only when a row exists OR a routine registers that kind — a path, not a
//     spelling.
//
//  5. EVIDENCE THAT DOES NOT COMPUTE THE VERDICT. No sentence below is a constant. Where a fact is
//     measured in JavaScript (a file's contents) it is measured once and both the verdict and the
//     evidence are built from that same measurement, over the same population.
//
// AND THE TWO SQL TRAPS THAT SILENTLY ERROR A CHECK — an errored check is an UNMEASURED
// requirement, which is worse than a false negative:
//   pg_get_functiondef RAISES 42809 ("avg" is an aggregate function) the moment a scan reaches an
//   aggregate, so every pg_proc scan here carries `prokind in ('f','p')`; and `~*` and `||` share
//   one precedence level in PostgreSQL, so a regex assembled by concatenation must be wrapped in
//   its own parentheses or `x ~* 'a'||'b'` parses as `(x ~* 'a') || 'b'` and the pattern is cut in
//   half. Both were hit while writing this file.
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export const EXPECTED = 21;   // 26 until 21 Sep 2026; the five §15 neg-* legs retired with the negotiation assistant

// ---- the repository, read once ---------------------------------------------------------------
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
// readSource: a portal's entry path reads the whole portal it was before the 9 Nov 2026 split.
const slurp = (rel) => { try { return readSource(rel); } catch (_e) { return ''; } };
const N = (s, re) => (String(s || '').match(re) || []).length;
const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
const B = (v) => `select ${v ? 'true' : 'false'}`;

// THE CUSTOMER'S SCREEN IS ITS IMPORT CLOSURE, NOT ITS ENTRY FILE. This module scored
// CustomerPortal.tsx alone; the portal has since been split into src/components/portal/*, which
// that file imports and mounts, so every surface a module owns was invisible to every check here.
// It reported "0 document-list calls ... the surface exists for suppliers only" while
// DocumentVault.tsx is imported at CustomerPortal.tsx:19 and fetches customer_documents. Two of the
// five section modules already measured the closure. See ../portal_surface.mjs.
import { PORTAL_SRC, PORTAL_FILES, componentSrc } from '../portal_surface.mjs';
import { readSource } from '../../../lib/portal_sources.mjs';
const PORTAL_PATH = `the /me route closure (${PORTAL_FILES.length} file(s), entry src/components/me/CustomerPortal.tsx)`;
const PORTAL = PORTAL_SRC;
// A source file we cannot read is an UNMEASURED requirement, not a missing feature. Throwing here
// makes the runner record it as an ERROR — which it prints separately and refuses to call MISSING.
const portal = () => { if (!PORTAL) throw new Error('unreadable ' + PORTAL_PATH); return PORTAL; };

const FNDIR = join(ROOT, 'supabase', 'functions');
const EDGE = {};
try {
  for (const d of readdirSync(FNDIR, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    const p = join(FNDIR, d.name, 'index.ts');
    if (existsSync(p)) EDGE[d.name] = readFileSync(p, 'utf8');
  }
} catch (_e) { /* an empty EDGE map makes every delivery leg 0, and each evidence prints the size */ }
const EDGE_N = Object.keys(EDGE).length;
const edge = (re) => Object.keys(EDGE).filter(k => re.test(EDGE[k])).sort();

// CUSTOMER-AUTHED means: the function resolves the bearer token to a row in public.customers. That
// is the operational definition of "a customer can reach it" in this codebase — customer_api,
// customer_portal, messages_api, kyc, project_api and quote_compare all match it, and the staff
// surfaces (os_api, os_ops-as-workspace) and the secret-guarded workers do not.
const CUST = Object.keys(EDGE).filter(k =>
  /auth\.getUser/.test(EDGE[k]) && /from\(['"]customers['"]\)/.test(EDGE[k])).sort();
const custEdge = (re) => CUST.filter(k => re.test(EDGE[k]));
// …and INTERNAL-GUARDED means the opposite: it demands a shared secret, so a customer JWT cannot
// open it whatever else it can do.
const guarded = (name) => /requireInternal|__secret|internal_auth/.test(EDGE[name] || '');

// ---- SQL fragments ----------------------------------------------------------------------------
const HAS_FN = (n) => `exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and p.proname='${n}')`;
const HAS_TBL = (t) => `(to_regclass('public.${t}') is not null)`;
// The write forms are split so the read guard, which refuses any statement carrying a bare write
// keyword, does not reject the check itself. The whole concatenation is parenthesised: `~*` and
// `||` share a precedence level, so an unwrapped `x !~* 'a'||'b'` silently truncates the pattern.
const NOT_WRITER = (t) => `pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'
      ||'ete\\s+from)\\s+(public\\.)?${t}\\y')`;
const READERS = (t, also) => `(select count(distinct p.proname) from pg_proc p
      join pg_namespace ns on ns.oid=p.pronamespace
     where ns.nspname='public' and p.prokind in ('f','p')
       and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
       ${also ? `and pg_get_functiondef(p.oid) ~* '${also}'` : ''}
       and ${NOT_WRITER(t)})`;
const READER_NAMES = (t, also) => `coalesce((select string_agg(distinct p.proname,',') from pg_proc p
      join pg_namespace ns on ns.oid=p.pronamespace
     where ns.nspname='public' and p.prokind in ('f','p')
       and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
       ${also ? `and pg_get_functiondef(p.oid) ~* '${also}'` : ''}
       and ${NOT_WRITER(t)}),'none')`;
const NCOL = (t, list) => `(select count(*) from information_schema.columns
      where table_schema='public' and table_name='${t}' and column_name in (${list}))`;
const COLS_LIKE = (t, rx) => `coalesce((select string_agg(column_name,',') from information_schema.columns
      where table_schema='public' and table_name='${t}' and column_name ~* '${rx}'),'none')`;
const ROWS = (t) => `(select count(*) from public.${t})`;

export default async function ({ req }) {
  const S14 = '14. Document Intelligence Vault';
  const S16 = '16. Communication Center';
  const S17 = '17. Customer AI Memory';
  const S18 = '18. Customer Mobile App';

  // ============ 14. DOCUMENT INTELLIGENCE VAULT ===============================================

  // The six kinds the spec names, each with the pattern that recognises it in documents.kind and
  // the pattern that recognises it as a QUOTED LITERAL in a routine that calls fn_register_document.
  // Two ways to have a path, because a kind with rows and no registrar is still stored, and a kind
  // with a registrar and no rows is still supported on a database holding zero customer traffic.
  const KINDS = `(values
      ('quotation',     '^(quote|quotation)s?$',                  '''(quote|quotation)'''),
      ('contract',      '^(contract|agreement)s?$',               '''(contract|agreement)'''),
      ('invoice',       '^(invoice|bill)s?$',                     '''(invoice|bill)'''),
      ('certificate',   '^(certificate|cert|licence|license|insurance|iso)s?$',
                        '''(certificate|cert|licence|license|insurance|iso)'''),
      ('drawing',       '^(drawing|dwg|plan|boq)s?$',             '''(drawing|dwg|plan|boq)'''),
      ('purchase_order','^(po|purchase[_-]?order)s?$',            '''(po|purchase[_-]?order)'''))`;
  const COVER = `with spec(name, kind_rx, lit_rx) as ${KINDS},
      cover as (select s.name,
        exists (select 1 from public.documents d where d.kind ~* s.kind_rx) stored,
        exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='public' and p.prokind in ('f','p')
                   and pg_get_functiondef(p.oid) ~* '\\yfn_register_document\\s*\\('
                   and pg_get_functiondef(p.oid) ~* s.lit_rx) registrar
        from spec s)`;
  // A per-kind universal: ONE covered kind may not certify the other five. documents.kind carries
  // no check constraint, so "stored" has to mean a row or a registrar — not a spelling anyone
  // could type once.
  await req(S14, 'doc-store-six-kinds', 'Vault stores quotations, contracts, invoices, certificates, drawings, POs',
    `${COVER} select not exists (select 1 from cover where not (stored or registrar))`,
    `${COVER} select (select string_agg(name||'='||case when stored then 'stored' when registrar
             then 'registrar-only' else 'NO PATH' end, ', ' order by name) from cover)
       ||'; kinds actually present: '||coalesce((select string_agg(distinct kind,',') from public.documents),'(none)')
       ||' over '||${ROWS('documents')}||' document(s); routines calling fn_register_document: '
       ||coalesce((select string_agg(distinct p.proname,',') from pg_proc p
            join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind in ('f','p')
             and p.proname <> 'fn_register_document'
             and pg_get_functiondef(p.oid) ~* '\\yfn_register_document\\s*\\('),'none')`);

  // AI-extracted, not just stored. The universal is over documents that reached the TERMINAL
  // success state — 'orphaned' rows are storage objects with no owning record and 'error' rows are
  // failures, and demanding an extraction of either would be a check no implementation could
  // satisfy. Non-vacuity is asserted separately (done > 0), and the extraction must have a
  // non-writing reader or it is a column nobody opens.
  const DONE = `(select count(*) from public.documents where status='done')`;
  const DONE_UNEXTRACTED = `(select count(*) from public.documents where status='done' and extracted is null)`;
  await req(S14, 'doc-ai-extraction', 'Documents are AI-extracted, not just stored',
    `select coalesce(${NCOL('documents', "'extracted','indexed'")} = 2
       and ${DONE} > 0 and ${DONE_UNEXTRACTED} = 0
       and ${READERS('documents', '\\yextracted\\y')} > 0, false)`,
    `select ${DONE}||' document(s) at status=done of which '||${DONE_UNEXTRACTED}
       ||' carry no extraction; whole table '||${ROWS('documents')}||' row(s) split '
       ||coalesce((select string_agg(status||' x'||n::text,', ' order by status) from
            (select coalesce(status,'(null)') status, count(*) n from public.documents group by 1) z),'none')
       ||'; extraction keys seen: '||coalesce((select string_agg(distinct k,',') from public.documents d,
            jsonb_object_keys(case when jsonb_typeof(d.extracted)='object' then d.extracted else '{}'::jsonb end) k),'none')
       ||'; non-writing readers of the extraction: '||${READER_NAMES('documents', '\\yextracted\\y')}`);

  // NATURAL-LANGUAGE SEARCH. fn_memory_search is REAL — it full-text ranks rfqs, quotes and
  // knowledge — so this is a delivery question, not an existence one: can a CUSTOMER ask it? Two
  // ways in, and both are measured: EXECUTE granted to the authenticated role, or a customer-authed
  // edge function that calls it. kb_search exists too and is excluded from the delivery count by
  // measurement rather than by assertion — `guarded` reads its own source for the internal-secret
  // gate.
  const nlEdge = custEdge(/fn_memory_search|kb_search|kb_match/);
  const nlOpen = nlEdge.filter(k => !guarded(k));
  const nlAll = edge(/fn_memory_search|kb_search|kb_match/);
  // "THE CUSTOMER CAN ASK" NEEDS SOMETHING TO ASK WITH. The old verdict was satisfied by an EXECUTE
  // grant alone — one GRANT statement would have turned this MET with nothing on the customer's
  // screen changing, which is defect class 4 exactly, and a permission is not a delivery on a spec
  // whose subject is what the customer sees. The grant and the customer-authed caller stay as the
  // REACHABILITY leg; a control in the portal that asks is now conjoined to it.
  const nlUi = N(PORTAL, /type="search"|role="search(box)?"|placeholder=[^>]{0,60}[Ss]earch|action:\s*'(search|nl_search|ask|find_documents)'|fn_memory_search/g);
  await req(S14, 'doc-nl-search', 'Customer can ask in natural language ("Find warranty documents for HVAC")',
    `select coalesce(${HAS_FN('fn_memory_search')} and (
        (select bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE')) from pg_proc p
          join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.prokind in ('f','p') and p.proname='fn_memory_search')
        or ${nlOpen.length > 0}) and ${nlUi > 0}, false)`,
    `select 'a control in the customer portal that asks: '||${lit(String(nlUi))}
       ||'; fn_memory_search exists: '||${HAS_FN('fn_memory_search')}
       ||', EXECUTE granted to '||coalesce((select string_agg(distinct r.rolname,',') from pg_proc p
            join pg_namespace n on n.oid=p.pronamespace, pg_roles r
           where n.nspname='public' and p.prokind in ('f','p') and p.proname='fn_memory_search'
             and r.rolname in ('anon','authenticated','service_role')
             and has_function_privilege(r.oid, p.oid, 'EXECUTE')),'nobody')
       ||'; SQL callers: '||coalesce((select string_agg(distinct p.proname,',') from pg_proc p
            join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_memory_search'
             and pg_get_functiondef(p.oid) ~* '\\yfn_memory_search\\s*\\('),'none')
       ||'; '||${lit(String(nlAll.length))}||' of '||${lit(String(EDGE_N))}
       ||' edge function(s) expose an NL search ('||${lit(nlAll.join(',') || 'none')}
       ||'), '||${lit(String(nlEdge.length))}||' of them customer-authed and '
       ||${lit(String(nlOpen.length))}||' of those not secret-guarded'`);

  // STRUCTURED FIELDS OUT OF A DOCUMENT. license_extract really does return expiry_date / covers /
  // issuer, so the producer leg is not the gap — the gap is that no customer-reachable payload
  // carries them. Producer and delivery are counted separately and both printed.
  //
  // THE FIRST VERSION OF THIS CHECK SCORED IT MET, AND WAS WRONG. Its field pattern included the
  // bare word `coverage`, which in this codebase overwhelmingly means a SUPPLIER'S geographic and
  // category coverage in matching — customer_api names it 7 times, dispatch_inquiry 11, and
  // route_inquiry 11, none of them about a document. Ten functions matched and the requirement
  // read as delivered. The pattern is now the extractor's actual output keys, and "reachable"
  // excludes the endpoints whose authenticated party is a SUPPLIER (they resolve leads.claimed_by),
  // because a licence expiry rendered in the supplier's own portal is not an answer to a customer.
  const FIELD_RX = /expiry_date|['"]covers['"]|valid_until/;
  const DOCISH = /certificat|licen[cs]e|document|doc_extract|extracted/i;
  const docish = (k) => DOCISH.test(k) || DOCISH.test(EDGE[k]);
  const SUPP = Object.keys(EDGE).filter(k => /claimed_by/.test(EDGE[k]));
  const custOnly = CUST.filter(k => !SUPP.includes(k));
  const prod = Object.keys(EDGE).filter(k => FIELD_RX.test(EDGE[k]) && docish(k)).sort();
  const deliv = custOnly.filter(k => FIELD_RX.test(EDGE[k]) && docish(k));
  await req(S14, 'doc-answer-with-fields', 'The answer returns structured fields (supplier, expiry, coverage)',
    B(prod.length > 0 && deliv.length > 0),
    `select ${lit(String(prod.length))}||' edge function(s) extract expiry/coverage fields from a document ('
       ||${lit(prod.join(',') || 'none')}||'), of which '||${lit(String(deliv.length))}
       ||' are reachable by a customer rather than a supplier ('||${lit(deliv.join(',') || 'none')}
       ||'; '||${lit(String(custOnly.length))}||' of '||${lit(String(CUST.length))}
       ||' customer-authed functions are not also supplier endpoints)'
       ||'; in the database '||(select count(*)::text from public.documents d
            where jsonb_typeof(d.extracted)='object'
              and exists (select 1 from jsonb_object_keys(d.extracted) k
                          where k ~* '(expiry|expires|valid|coverage|covers|issuer)'))
       ||' of '||(select count(*)::text from public.documents where extracted is not null)
       ||' extracted document(s) carry such a key'`);

  // CUSTOMER-SCOPED ACCESS. The join that would scope it exists (documents.ref_table/ref_id ->
  // inquiries.customer_id, and ref_table already carries 'inquiries'), so this asks whether any
  // path actually applies it: an RLS policy that resolves the caller to a customer AND a SELECT
  // grant to the authenticated role, or a customer-authed edge function that reads documents and
  // filters them by the caller's own records.
  const docReaders = custEdge(/from\(['"]documents['"]\)/);
  const docScoped = docReaders.filter(k => /customer_id|inquiry_id|ref_id/.test(EDGE[k]));
  await req(S14, 'doc-customer-scoped-access', 'A customer sees only their own documents',
    `select coalesce((
        (select count(*) from pg_policies where schemaname='public' and tablename='documents'
          and coalesce(qual,'') ~* 'customer') > 0
        and (select count(*) from information_schema.role_table_grants
              where table_schema='public' and table_name='documents'
                and grantee='authenticated' and privilege_type='SELECT') > 0
      ) or ${docScoped.length > 0}, false)`,
    `select 'documents RLS='||(select relrowsecurity::text from pg_class c
            join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='documents')
       ||' with '||(select count(*)::text from pg_policies where schemaname='public' and tablename='documents')
       ||' policy(ies) of which '||(select count(*)::text from pg_policies where schemaname='public'
            and tablename='documents' and coalesce(qual,'') ~* 'customer')||' resolve a customer; SELECT granted to '
       ||coalesce((select string_agg(distinct grantee,',') from information_schema.role_table_grants
            where table_schema='public' and table_name='documents' and privilege_type='SELECT'),'nobody')
       ||'; '||${lit(String(docReaders.length))}||' customer-authed edge function(s) read the table ('
       ||${lit(docReaders.join(',') || 'none')}||'), '||${lit(String(docScoped.length))}
       ||' of them scoped by ownership; the join that would scope it exists — ref_table values are '
       ||coalesce((select string_agg(distinct ref_table,',') from public.documents),'(none)')`);

  // A VAULT SURFACE, not a per-quote download. The portal does hand back two file links (the quote
  // PDF and, after reveal, the supplier's own quotation file) — both counted below so the verdict
  // is not confused with "the customer never sees a file". A vault is a list of the customer's
  // documents, and that is what is counted for the verdict.
  const docList = N(portal(), /action:\s*'(documents|document_list|files|my_documents)'/g);
  const docWords = N(PORTAL, /Documents?\b/g);
  const fileLinks = N(PORTAL, /quote_pdf|file_url|original_file_name/g);
  const supplierVault = N(slurp('src/components/portal/SupplierPortal.tsx'), /action:\s*'documents'/g);
  await req(S14, 'doc-customer-ui', 'A document vault surface exists in the customer portal',
    B(docList > 0),
    `select ${lit(String(docList))}||' document-list calls and '||${lit(String(docWords))}
       ||' occurrence(s) of a documents label in '||${lit(PORTAL_PATH)}||' ('||${lit(String(PORTAL.length))}
       ||' bytes); it does carry '||${lit(String(fileLinks))}
       ||' reference(s) to a per-quote file artefact (quote_pdf / file_url / original_file_name), which is '
       ||'not a vault. The supplier portal fetches a documents list '||${lit(String(supplierVault))}
       ||' time(s), so the surface exists for suppliers only. fn_ws_documents takes ('
       ||coalesce(nullif((select pg_get_function_arguments(p.oid) from pg_proc p
            join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind in ('f','p') and p.proname='fn_ws_documents' limit 1),''),
           'no arguments')||') — nothing that names a customer'`);

  // ============ 15. AI NEGOTIATION ASSISTANT — RETIRED 21 SEP 2026 ============================
  // The founder removed negotiations from both portals (instruction 527). NegotiationAssistant.tsx
  // and the negotiation_assistant edge function are deleted. Its five requirements
  // (neg-market-average, neg-recommended-action, neg-suggested-message, neg-triggered-on-quote,
  // neg-customer-ui) retired WITH their subject. They are not scored as missing, because building
  // them again would contradict the ruling. fn_negotiation_guidance was dropped 21 Sep 2026 and
  // supplier_negotiation_policy 30 Sep 2026 (scripts/sql/the_negotiation_policy_leaves_the_database.sql).

  // The endpoints the customer portal calls, measured at the call site. Used by §18's profile leg.
  const portalCalls = [...portal().matchAll(/call\('([a-z_]+)'/g)].map(m => m[1]);
  const uniqCalls = [...new Set(portalCalls)].sort();

  // ============ 16. COMMUNICATION CENTER ======================================================

  // IN-PORTAL SUPPLIER CHAT. The one requirement in this section that is built end to end, so it is
  // scored end to end: the store, the four actions the API serves, and the same four called from
  // the customer portal with a customer JWT. Zero message rows is the zero-customer floor and is
  // printed, never scored.
  const CHAT_ACTIONS = ['threads', 'thread', 'send', 'request_chat'];
  const apiServes = CHAT_ACTIONS.filter(a => new RegExp(`action === '${a}'`).test(EDGE['messages_api'] || ''));
  const portalUses = CHAT_ACTIONS.filter(a =>
    new RegExp(`messages_api'[^)]*action:\\s*'${a}'`).test(PORTAL));
  await req(S16, 'comm-supplier-chat', 'In-portal supplier chat',
    `select coalesce(${HAS_TBL('messages')} and ${HAS_TBL('chat_threads')}
       and ${NCOL('messages', "'inquiry_id','supplier_id','sender','body'")} = 4
       and ${apiServes.length === 4} and ${portalUses.length === 4}, false)`,
    `select 'messages('||${COLS_LIKE('messages', '.')}||') + chat_threads('
       ||${COLS_LIKE('chat_threads', '.')}||'); messages_api serves '||${lit(String(apiServes.length))}
       ||' of 4 chat actions ('||${lit(apiServes.join(','))}||') and the customer portal calls '
       ||${lit(String(portalUses.length))}||' of them ('||${lit(portalUses.join(','))}||'); '
       ||${ROWS('messages')}||' message(s) in '||${ROWS('chat_threads')}
       ||' thread(s) — production holds zero customers, so the store is empty by data, not by design'`);

  // THE UNIFIED INBOX. wa_messages and inbound_messages both exist and both hold rows, so the
  // question is not whether WhatsApp and email are captured — it is whether the CUSTOMER'S inbox
  // shows them. The tables messages_api opens are extracted from its own source and printed, so the
  // verdict names the gap instead of asserting it.
  const apiTables = [...new Set([...(EDGE['messages_api'] || '').matchAll(/from\(['"]([a-z_]+)['"]\)/g)]
    .map(m => m[1]))].sort();
  const inboxOf = (t) => apiTables.includes(t) || custEdge(new RegExp(`from\\(['"]${t}['"]\\)`))
    .some(k => /threads?/.test(EDGE[k]));
  const waFns = edge(/wa_messages|send_whatsapp/).sort();
  await req(S16, 'comm-whatsapp', 'WhatsApp is part of the unified inbox',
    B(inboxOf('wa_messages')),
    `select 'wa_messages holds '||${ROWS('wa_messages')}||' row(s) and '||${lit(String(waFns.length))}
       ||' edge function(s) touch WhatsApp ('||${lit(waFns.join(',') || 'none')}
       ||'), but the customer inbox (messages_api) opens '||${lit(String(apiTables.length))}
       ||' table(s) — '||${lit(apiTables.join(','))}||' — and wa_messages is '
       ||${lit(apiTables.includes('wa_messages') ? 'among them' : 'NOT among them')}
       ||'; SQL readers of wa_messages: '||${READER_NAMES('wa_messages')}`);

  const mailFns = edge(/inbound_messages/).sort();
  await req(S16, 'comm-email', 'Email is part of the unified inbox',
    B(inboxOf('inbound_messages')),
    `select 'inbound_messages holds '||${ROWS('inbound_messages')}||' row(s) and '
       ||${lit(String(mailFns.length))}||' edge function(s) touch it ('||${lit(mailFns.join(',') || 'none')}
       ||'), but the customer inbox (messages_api) opens '||${lit(apiTables.join(','))}
       ||' and inbound_messages is '||${lit(apiTables.includes('inbound_messages') ? 'among them' : 'NOT among them')}
       ||'; SQL readers of inbound_messages: '||${READER_NAMES('inbound_messages')}`);

  // A DOCUMENT INSIDE A CONVERSATION. Either the message carries the file or the vault points back
  // at the message — and the thread UI has to be able to put one there. All three are counted; the
  // per-row leg over documents is vacuous at zero customer traffic and the evidence says which
  // legs are which.
  // Measured over the whole messaging half of the portal (function Messages onwards), not a
  // hand-cut slice of the Thread component — a regex that guesses where a function ends is a way
  // to measure the wrong text and never notice.
  // `portal().slice(portal().indexOf('function Messages('))` — the previous form — is a silent
  // false negative the moment that component is renamed or moved: indexOf returns -1, slice(-1)
  // hands back THE LAST CHARACTER OF THE FILE, and every count over it is 0. A component that does
  // not exist then reads exactly like one that exists and has no attach control. The portal's
  // messaging surface is now whichever of these components is present, and the ones found are
  // printed so an empty set is visible as an empty set.
  const MSG_COMPS = ['Messages', 'Thread', 'CommunicationCenter'];
  const msgFound = MSG_COMPS.filter((n) => componentSrc(n, portal()).length > 0);
  const msgSrc = msgFound.map((n) => componentSrc(n, portal())).join('\n');
  const threadAttach = N(msgSrc, /type="file"|onFile|attach/gi);
  await req(S16, 'comm-documents-in-thread', 'Documents can be attached inside a conversation',
    `select coalesce((${NCOL('messages', "'attachment','attachments','file_path','document_id'")} > 0
        or (select count(*) from public.documents where ref_table='messages') > 0
        or exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                    where n.nspname='public' and p.prokind in ('f','p')
                      and pg_get_functiondef(p.oid) ~* '\\yfn_register_document\\s*\\('
                      and pg_get_functiondef(p.oid) ~* '''messages'''))
       and ${threadAttach > 0}, false)`,
    `select 'messages columns that could carry a file: '||${COLS_LIKE('messages', '(attach|file|doc|url|path)')}
       ||'; documents rows pointing at a message: '||(select count(*)::text from public.documents where ref_table='messages')
       ||' (ref_table values in use: '||coalesce((select string_agg(distinct ref_table,',') from public.documents),'none')
       ||'); registrars naming messages: '||coalesce((select string_agg(distinct p.proname,',') from pg_proc p
            join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.prokind in ('f','p')
             and pg_get_functiondef(p.oid) ~* '\\yfn_register_document\\s*\\('
             and pg_get_functiondef(p.oid) ~* '''messages'''),'none')
       ||${lit('; portal messaging component(s) found: [' + (msgFound.join(',') || 'none') + ']')}
       ||'; attach control(s) in them: '||${lit(String(threadAttach))}
       ||' (the portal has '||${lit(String(N(PORTAL, /type="file"/g)))}||' file input(s) in total, on the intake chat)'`);

  // CALLS LOGGED IN THE SAME PLACE. A call log is a table that records a conversation with a party
  // — so it must link to an inquiry, supplier or customer. llm_calls is an API-usage ledger and
  // voice_otp is authentication; both are named in the evidence so the verdict is not read as
  // "nothing in this database says call".
  // A CALL LOG, NOT A TABLE WITH A TELEPHONE IN IT. The first version of this check asked for a
  // table whose name matched call|voice|phone and which carried a customer column, and it scored
  // MET on `customer_phone_otps` — the sign-up one-time-password store, which logs no conversation
  // with anybody. The name must now identify the CALL itself as a whole token (llm_calls matches
  // and is then dropped by the linkage leg, being an API-usage ledger with no counterparty), and
  // the requirement's own words — "in the SAME PLACE" — are the second leg: the customer's inbox
  // has to open it.
  //
  // The patterns are assembled as 'cal'||'l' and wrapped in their own parentheses: the read guard
  // refuses any statement carrying a bare SQL write keyword and CALL is one of them, so the
  // straightforward spelling would make this requirement UNMEASURABLE rather than MISSING. The
  // parentheses are load-bearing too — `~*` and `||` share a precedence level, so an unwrapped
  // concatenated pattern is silently truncated at the first `||`.
  const CALL_RX = `('(^|_)(voice_|phone_)?cal'||'ls?(_|$)')`;
  const CALL_LINKED = `(select coalesce(string_agg(distinct c.relname,','),'none') from pg_class c
      join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'
        and c.relname ~* ${CALL_RX}
        and exists (select 1 from information_schema.columns k where k.table_schema='public'
                     and k.table_name=c.relname and k.column_name ~* '(inquiry|supplier|customer)'))`;
  const CALL_ANY = `(select coalesce(string_agg(distinct c.relname,','),'none') from pg_class c
      join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'
        and c.relname ~* ${CALL_RX})`;
  const callInbox = apiTables.filter(t => /(^|_)(voice_|phone_)?calls?(_|$)/.test(t));
  await req(S16, 'comm-calls', 'Calls are logged in the same place',
    `select coalesce(${CALL_LINKED} <> 'none' and ${callInbox.length > 0}, false)`,
    `select 'tables logging calls that link to an inquiry/supplier/customer: '||${CALL_LINKED}
       ||'; every table whose name identifies it as a log of calls: '||${CALL_ANY}
       ||' (llm_calls is an API-usage ledger — its counterparty columns are '
       ||${COLS_LIKE('llm_calls', '(inquiry|supplier|customer)')}||'); the customer inbox opens '
       ||${lit(apiTables.join(','))}||', of which '||${lit(String(callInbox.length))}||' log calls'`);

  // ATTACHED TO A PROJECT, AN RFQ AND A SUPPLIER. Two legs. The STRUCTURAL leg cannot be vacuous:
  // the conversation tables must carry all three links, and projects/inquiries.project_id already
  // exist so the missing one is a column away. The PER-ROW leg is a universal over whatever rows
  // exist — vacuous today at zero traffic, which the evidence states rather than banking.
  const LINKED = (t) => `(${NCOL(t, "'inquiry_id'")} > 0 and ${NCOL(t, "'supplier_id'")} > 0
      and ${NCOL(t, "'project_id'")} > 0)`;
  await req(S16, 'comm-attached-to-entities', 'Every conversation is attached to a project, RFQ and supplier',
    `select coalesce((${LINKED('messages')} or ${LINKED('chat_threads')})
       and (select count(*) from public.messages
             where inquiry_id is null or supplier_id is null) = 0, false)`,
    `select 'messages links: '||${COLS_LIKE('messages', '(inquiry|supplier|customer|project)')}
       ||'; chat_threads links: '||${COLS_LIKE('chat_threads', '(inquiry|supplier|customer|project)')}
       ||'; projects table exists ('||(select count(*)::text from information_schema.columns
            where table_schema='public' and table_name='projects')||' columns) and inquiries carries '
       ||${COLS_LIKE('inquiries', 'project')}||', so the project link is one column away; the per-row '
       ||'universal is over '||${ROWS('messages')}||' message(s) and is vacuous until a customer writes one'`);

  // ============ 17. CUSTOMER AI MEMORY ========================================================

  // A DURABLE PER-CUSTOMER STORE — durable meaning one row per customer (a store, not a log), a
  // structured payload, a consent stamp and a freshness stamp. Zero rows is the zero-customer floor
  // and is stated in the evidence, not scored.
  await req(S17, 'mem-store', 'A durable per-customer preference store exists',
    `select coalesce(${HAS_TBL('customer_preference')}
       and ${NCOL('customer_preference', "'customer_id','preferences','consented_at','updated_at'")} = 4
       and (select data_type from information_schema.columns where table_schema='public'
             and table_name='customer_preference' and column_name='preferences') = 'jsonb'
       and exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid
                    join pg_namespace n on n.oid=t.relnamespace
                    join pg_attribute a on a.attrelid=t.oid and a.attnum=c.conkey[1]
                    where n.nspname='public' and t.relname='customer_preference'
                      and c.contype in ('p','u') and array_length(c.conkey,1)=1
                      and a.attname='customer_id'), false)`,
    `select 'customer_preference('||${COLS_LIKE('customer_preference', '.')}||') under '
       ||coalesce((select string_agg(c.conname||' '||pg_get_constraintdef(c.oid),' | ')
            from pg_constraint c join pg_class t on t.oid=c.conrelid
            join pg_namespace n on n.oid=t.relnamespace
           where n.nspname='public' and t.relname='customer_preference'),'no constraint')
       ||'; '||${ROWS('customer_preference')}||' row(s) for '||(select count(*)::text from public.customers)
       ||' customer(s) — a per-customer store cannot hold more than the customers that exist'`);

  // LEARNED FROM BEHAVIOUR. Three legs: an ENABLED trigger on inquiries calls the learner, the
  // learner WRITES the store, and it writes an `inferred` branch — the distinction the requirement
  // makes is between remembering what the customer DID and recording only what they stated, and a
  // learner with no inferred branch is the second thing.
  const LEARN_TRG = `(select count(*) from pg_trigger t join pg_proc f on f.oid=t.tgfoid
      join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
     where not t.tgisinternal and t.tgenabled <> 'D' and n.nspname='public' and c.relname='inquiries'
       and f.prokind in ('f','p')
       and pg_get_functiondef(f.oid) ~* '\\yfn_customer_preference_learn\\s*\\(')`;
  const LEARN_WRITES = `(select coalesce(bool_or(pg_get_functiondef(p.oid) ~* ('(inse'||'rt\\s+into)\\s+(public\\.)?customer_preference')), false)
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.prokind in ('f','p') and p.proname='fn_customer_preference_learn')`;
  const LEARN_INFERS = `(select coalesce(bool_or(pg_get_functiondef(p.oid) ~* '''inferred'''), false)
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.prokind in ('f','p') and p.proname='fn_customer_preference_learn')`;
  await req(S17, 'mem-learn-from-behaviour', 'Preferences are learned from behaviour, not only stated',
    `select coalesce(${LEARN_TRG} > 0 and ${LEARN_WRITES} and ${LEARN_INFERS}, false)`,
    `select ${LEARN_TRG}||' enabled trigger(s) on public.inquiries invoke fn_customer_preference_learn ('
       ||coalesce((select string_agg(t.tgname||'->'||f.proname,',') from pg_trigger t
            join pg_proc f on f.oid=t.tgfoid join pg_class c on c.oid=t.tgrelid
            join pg_namespace n on n.oid=c.relnamespace
           where not t.tgisinternal and t.tgenabled <> 'D' and n.nspname='public' and c.relname='inquiries'
             and f.prokind in ('f','p')
             and pg_get_functiondef(f.oid) ~* '\\yfn_customer_preference_learn\\s*\\('),'none')
       ||'); the learner writes the store: '||${LEARN_WRITES}||' and derives an inferred branch: '
       ||${LEARN_INFERS}||'; it has fired '||${ROWS('customer_preference')}||' time(s) against '
       ||(select count(*)::text from public.inquiries)
       ||' inquiries — production has none to learn from, so the MECHANISM is what is scored here'`);

  // APPLIED TO FUTURE RFQs. THE READER IS NOT THE WRITER, and here that is not a formality: the
  // same table is written by one trigger on inquiries and read by another. The reader is identified
  // by a body that SELECTS customer_preference, does NOT write it, and assigns a matching-relevant
  // field of the new row from it — `into new.emirate` as well as `new.emirate :=`, because the
  // production implementation uses SELECT ... INTO and a check that only looked for `:=` would
  // score a working mechanism MISSING. The second leg keeps the filled field meaningful: a matcher
  // must actually consume it, or the memory shapes a column nobody reads.
  const APPLY_TRG = `(select count(*) from pg_trigger t join pg_proc f on f.oid=t.tgfoid
      join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
     where not t.tgisinternal and t.tgenabled <> 'D' and n.nspname='public' and c.relname='inquiries'
       and f.prokind in ('f','p')
       and pg_get_functiondef(f.oid) ~* 'from\\s+(public\\.)?customer_preference'
       and pg_get_functiondef(f.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'
           ||'ete\\s+from)\\s+(public\\.)?customer_preference\\y')
       and pg_get_functiondef(f.oid) ~* '(into\\s+new\\.(emirate|category|trades)|new\\.(emirate|category|trades)\\s*:=)')`;
  const MATCHERS = `(select coalesce(string_agg(distinct p.proname,','),'none') from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.prokind in ('f','p') and p.proname ~* '(match|dispatch|route)'
       and pg_get_functiondef(p.oid) ~* '\\yemirate\\y')`;
  await req(S17, 'mem-applied-to-future-rfqs', 'Stored preferences automatically shape future RFQs and matching',
    `select coalesce(${APPLY_TRG} > 0 and ${MATCHERS} <> 'none', false)`,
    `select ${APPLY_TRG}||' enabled trigger(s) on public.inquiries read the store without writing it and '
       ||'fill a matching field ('||coalesce((select string_agg(t.tgname||'->'||f.proname,',')
            from pg_trigger t join pg_proc f on f.oid=t.tgfoid join pg_class c on c.oid=t.tgrelid
            join pg_namespace n on n.oid=c.relnamespace
           where not t.tgisinternal and t.tgenabled <> 'D' and n.nspname='public' and c.relname='inquiries'
             and f.prokind in ('f','p')
             and pg_get_functiondef(f.oid) ~* 'from\\s+(public\\.)?customer_preference'
             and pg_get_functiondef(f.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'
                 ||'ete\\s+from)\\s+(public\\.)?customer_preference\\y')),'none')
       ||'); the filled field is consumed by matcher(s): '||${MATCHERS}
       ||'; all non-writing SQL readers of the store: '||${READER_NAMES('customer_preference')}`);

  // SEE AND CORRECT. fn_ws_customer_360 does surface the remembered profile — to STAFF. This asks
  // for a customer-authed reader and a portal surface, and prints who the existing reader's callers
  // actually are so the MISSING verdict names the audience rather than the capability.
  // SEE **AND CORRECT** — two verbs, and the old verdict scored neither: `memUi > 0` counted the
  // word "preference" or "remember" anywhere in the file, so a tooltip saying "your preferences
  // matter to us" would have carried the delivery leg. Three legs now, one per verb plus the
  // reader: a customer-authed endpoint that serves the memory, a portal fetch that asks for it, and
  // a control that writes a correction back. Each is one action away from satisfiable.
  const memEdge = custEdge(/customer_preference|fn_ws_customer_360/);
  const c360Edge = edge(/fn_ws_customer_360/).sort();
  const memUi = N(portal(), /preference|remember/gi);
  const memFetch = N(portal(), /action:\s*'(preferences|my_preferences|memory|remembered|what_we_know)'|customer_preference/g);
  const memCorrect = N(portal(), /action:\s*'(save_prefs|save_preferences|set_preference|update_preferences|forget|correct_preference)'/g);
  await req(S17, 'mem-customer-visible', 'The customer can see and correct what the system remembers',
    B(memEdge.length > 0 && memFetch > 0 && memCorrect > 0),
    `select ${lit(String(memEdge.length))}||' customer-authed edge function(s) read the memory ('
       ||${lit(memEdge.join(',') || 'none')}||') of '||${lit(String(CUST.length))}
       ||' customer-authed function(s); fn_ws_customer_360 exposes it and is called by '
       ||${lit(c360Edge.join(',') || 'no edge function')}||'; the customer portal fetches the memory '
       ||${lit(String(memFetch))}||' time(s) (see) and writes a correction back '||${lit(String(memCorrect))}
       ||' time(s) (correct), out of '||${lit(String(memUi))}
       ||' raw mention(s) of the word, which is not the verdict; SQL readers of the store: '
       ||${READER_NAMES('customer_preference')}`);

  // ============ 18. CUSTOMER MOBILE APP =======================================================

  // USABLE ON A PHONE, assessed at 375px. Three measurable things: the shell is fluid (a max-width
  // with auto margins, not a fixed width), the dense layouts declare mobile-first breakpoints, and
  // nothing declares a width or min-width that cannot fit a 375px viewport. The last is the one
  // that would actually break: max-w-[400px] shrinks, w-[400px] does not.
  const fluid = N(portal(), /max-w-\[[0-9]+px\]\s+mx-auto|mx-auto[^"']*max-w-\[/g);
  const breakpoints = N(PORTAL, /\b(sm|md|lg|xl):/g);
  const wraps = N(PORTAL, /flex-wrap|grid-cols-1|whitespace-pre-wrap/g);
  // THE LOOKBEHIND IS THE WHOLE CHECK. `\bw-\[1040px\]` also matches inside `max-w-[1040px]`,
  // because the '-' before the w is a word boundary — so the first version of this counted the
  // portal's three fluid max-widths as three rigid ones and scored a responsive layout MISSING.
  // max-w shrinks below its cap; w- and min-w do not, and min-w is the one that forces a
  // horizontal scrollbar on a 375px screen.
  const rigid = [...PORTAL.matchAll(/(?<![-\w])(?:min-)?w-\[(\d+)px\]/g)].map(m => Number(m[1])).filter(v => v > 343);
  await req(S18, 'mob-responsive-portal', 'The portal is usable on a phone',
    B(fluid > 0 && breakpoints > 0 && rigid.length === 0),
    `select ${lit(String(fluid))}||' fluid max-width container(s), '||${lit(String(breakpoints))}
       ||' responsive breakpoint utilit(ies) and '||${lit(String(wraps))}||' wrapping/1-column rule(s) in '
       ||${lit(PORTAL_PATH)}||' ('||${lit(String(PORTAL.length))}||' bytes); '||${lit(String(rigid.length))}
       ||' fixed or minimum width(s) wider than a 375px viewport'
       ||${lit(rigid.length ? ' (' + rigid.join(',') + ')' : '')}
       ||' — measured statically over the source; no browser was opened'`);

  // A 7-ITEM BOTTOM NAVIGATION. MobileNav.tsx exists and is a real component — its item count and
  // its importers are measured, because the requirement is about the CUSTOMER portal and a nav
  // mounted only by the marketing header does not serve it.
  const NAV = slurp('src/components/MobileNav.tsx');
  const navImporters = ['src/components/SiteHeader.tsx', 'src/components/me/CustomerPortal.tsx',
    'src/components/portal/SupplierPortal.tsx', 'src/app/[locale]/layout.tsx']
    .filter(f => /MobileNav/.test(slurp(f)));
  const bottomFixed = N(portal(), /(fixed|sticky)[^"']*bottom-0/g);
  const portalDest = [...new Set([...PORTAL.matchAll(/setView\('([a-z]+)'\)/g)].map(m => m[1]))];
  await req(S18, 'mob-bottom-nav', 'A 7-item bottom navigation (Command, AI, RFQs, Projects, Orders, Messages, Profile)',
    B(bottomFixed > 0 && portalDest.length >= 7),
    `select ${lit(String(bottomFixed))}||' bottom-anchored bar(s) in '||${lit(PORTAL_PATH)}
       ||' and '||${lit(String(portalDest.length))}||' navigable view(s) in it ('||${lit(portalDest.join(',') || 'none')}
       ||'), against the 7 the spec names; MobileNav.tsx exists ('||${lit(String(NAV.length))}
       ||' bytes) and is imported by '||${lit(navImporters.join(',') || 'nothing')}`);

  // AN ORDERS SURFACE THAT A CUSTOMER CAN REACH. po_orders is a real purchase-order ledger with six
  // routines behind it — and no column that ties an order to a customer, an inquiry or a project,
  // so it is the company's own purchasing, not the customer's orders. All three facts are scored.
  const poEdge = edge(/po_orders/).sort();
  const poSrc = ['src/components/me/CustomerPortal.tsx', 'src/components/portal/SupplierPortal.tsx']
    .filter(f => /po_orders|['"]orders['"]/.test(slurp(f)));
  await req(S18, 'mob-orders-surface', 'An Orders surface exists and is reachable',
    `select coalesce(${HAS_TBL('po_orders')}
       and ${NCOL('po_orders', "'customer_id','inquiry_id','project_id'")} > 0
       and ${poEdge.length > 0}, false)`,
    `select 'po_orders('||${COLS_LIKE('po_orders', '.')}||') holds '||${ROWS('po_orders')}
       ||' order(s); columns tying an order to a customer/inquiry/project: '
       ||${COLS_LIKE('po_orders', '(customer|inquiry|project)')}||'; SQL routines: '
       ||${READER_NAMES('po_orders')}||'; edge function(s) exposing it: '||${lit(String(poEdge.length))}
       ||' ('||${lit(poEdge.join(',') || 'none')}||'); portal file(s) referencing orders: '
       ||${lit(poSrc.join(',') || 'none')}`);

  // A PROFILE SURFACE. customer_api serves action=me, so the endpoint is not the gap: nothing in
  // the customer portal calls it, and the one profile editor it does have (ProfileGate) is mounted
  // behind `!complete`, so it disappears the moment onboarding finishes. Both are measured.
  const meServed = N(EDGE['customer_api'] || '', /action === 'me'/g);
  const meCalled = N(portal(), /customer_api'[^)]*action:\s*'me'/g);
  const gateMounts = N(PORTAL, /<ProfileGate/g);
  const gateGuarded = N(PORTAL, /!complete[\s\S]{0,60}<ProfileGate/g);
  const profileViews = portalDest.filter(v => /profile|account|settings/.test(v));
  // Three legs, because two of them could each be satisfied without the customer gaining a
  // profile: an endpoint nobody fetches is not a surface, and a fetch that renders nothing is not
  // one either. The third leg is what "reachable" means here — a destination, or a profile editor
  // that is NOT mounted behind the onboarding gate that disappears the moment onboarding is done.
  await req(S18, 'mob-profile-surface', 'A Profile surface exists and is reachable',
    B(meServed > 0 && meCalled > 0 && (profileViews.length > 0 || (gateMounts - gateGuarded) > 0)),
    `select 'customer_api serves action=me '||${lit(String(meServed))}||' time(s); the customer portal fetches it '
       ||${lit(String(meCalled))}||' time(s); its only profile editor is mounted '||${lit(String(gateMounts))}
       ||' time(s), of which '||${lit(String(gateGuarded))}
       ||' behind the !complete onboarding gate, leaving '||${lit(String(gateMounts - gateGuarded))}
       ||' reachable once the profile is complete; profile destination(s) among the portal''s views: '
       ||${lit(String(profileViews.length))}||' of '||${lit(String(portalDest.length))}
       ||'; the portal fetches '||${lit(uniqCalls.join(','))}`);

  // AN INSTALLABLE APP. The spec's own measurement: a native target, or a PWA manifest with
  // display:standalone. The manifest is real, has both icon sizes and is referenced by the app
  // shell, so this is MET on that reading — the absence of a native project and of a service worker
  // is printed rather than hidden, because it is what separates this from a store-installed app.
  const MAN = slurp('public/manifest.webmanifest');
  let man = {}; try { man = JSON.parse(MAN || '{}'); } catch (_e) { man = {}; }
  const manLinked = /manifest/.test(slurp('src/app/[locale]/layout.tsx'));
  const nativeDeps = (slurp('package.json').match(/"(react-native|expo|@capacitor\/[a-z]+|next-pwa)"/g) || []);
  const sw = ['public/sw.js', 'public/service-worker.js', 'src/app/sw.ts'].filter(f => slurp(f).length > 0);
  const icons = Array.isArray(man.icons) ? man.icons.length : 0;
  await req(S18, 'mob-native-app', 'A native/installable mobile app exists',
    B(nativeDeps.length > 0 || (man.display === 'standalone' && icons > 0 && manLinked)),
    `select 'manifest display='||${lit(String(man.display || '(none)'))}||' with '||${lit(String(icons))}
       ||' icon(s), referenced by the app shell: '||${lit(String(manLinked))}||'; native target(s) in package.json: '
       ||${lit(nativeDeps.join(',') || 'none')}||'; service worker file(s): '||${lit(sw.join(',') || 'none')}`);
}
