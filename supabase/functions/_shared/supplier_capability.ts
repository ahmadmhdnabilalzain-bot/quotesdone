// WHAT A SUPPLIER CAN QUOTE FOR, AS THE SUPPLIER CONFIRMED IT — `state` and `confirm`, no model.
//
// fn_match_capability's candidate CTE opens with `where sc.confirmed_at is not null`, so this is the
// gate every match passes through. Until 14 Sep 2026 supplier_api proxied both actions to the
// capability_agent edge function. That function was deleted from the repository AND from production
// by the 137-function sweep (commit 182308b, 7 Sep 2026); on 14 Sep get_edge_function returned
// "Function not found" and list_edge_functions listed 62 functions without it. From 7 Sep, then,
// every "Confirm my scope" press returned the gateway's 404, and no supplier could clear the gate.
//
// Neither action ever needed a model. Both are ported here verbatim in behaviour from
// capability_agent@2 (182308b^:supabase/functions/capability_agent/index.ts): same vocabulary read,
// same validation against taxonomy_trade / taxonomy_role, same versioned ledger row in
// supplier_capability_confirmation, same response shapes, so the portal needed no contract change.
// The third action, `analyze`, sent the supplier's documents to a model through ai_gateway. It is
// deliberately NOT ported: the OpenRouter hold stands until the whole build is done, and registration
// must work with no model in the loop. The supplier corrects what we hold and confirms it instead.
//
// This lives in _shared rather than as a new edge function because the only caller is supplier_api,
// which resolves the supplier id from the caller's own JWT. A separately deployed function taking
// supplier_id from its body is exactly the enumeration surface the old proxy existed to hide.

// deno-lint-ignore no-explicit-any
type Admin = any;
import { answeredForLedger } from './supplier_service_questions.ts';

const VERSION = 'supplier_api.capability@1';
const clip = (v: unknown, n: number) => String(v == null ? '' : v).slice(0, n);
const strArr = (v: unknown, n: number, len = 120): string[] =>
  Array.isArray(v) ? v.map((x) => clip(x, len)).filter(Boolean).slice(0, n) : [];
const obj = (v: unknown) => (v && typeof v === 'object' ? v : {});

export async function capabilityVocabulary(admin: Admin) {
  // label_ar arrives with a_suppliers_documents_propose_trades_and_a_new_trade_is_reviewed_not_dropped.sql.
  // Read without it if that column is not there yet, so a deploy that lands first never empties the list.
  // umbrella_code arrives with the_missing_trades_join_the_taxonomy_under_twelve_groups.sql; same fallback.
  let { data: tr, error } = await admin.from('taxonomy_trade').select('code,label,label_ar,authority_required,umbrella_code').eq('active', true).order('sort');
  if (error) ({ data: tr, error } = await admin.from('taxonomy_trade').select('code,label,label_ar,authority_required').eq('active', true).order('sort'));
  if (error) ({ data: tr } = await admin.from('taxonomy_trade').select('code,label,authority_required').eq('active', true).order('sort'));
  const { data: ro } = await admin.from('taxonomy_role').select('code,label,supplies,executes,whole_scope').eq('active', true).order('sort');
  return { trades: tr || [], roles: ro || [] };
}

/** This supplier's own new-trade proposals (taxonomy_trade_proposal), newest first; [] before that table exists. */
async function tradeProposals(admin: Admin, supplierId: number) {
  const { data, error } = await admin.from('taxonomy_trade_proposal')
    .select('code,label_en,label_ar,status,mapped_to,created_at').eq('supplier_id', supplierId).order('created_at', { ascending: false }).limit(25);
  return error ? [] : (data || []);
}

export async function capabilityState(admin: Admin, supplierId: number) {
  const { data: cap } = await admin.from('supplier_capabilities').select('*').eq('supplier_id', supplierId).maybeSingle();
  const { data: hist } = await admin.from('supplier_capability_confirmation')
    .select('version,confirmed_at,confirmed_via').eq('supplier_id', supplierId).order('version', { ascending: false }).limit(5);
  const vocabulary = await capabilityVocabulary(admin);
  return { ok: true, capability: cap || null, confirmed: !!cap?.confirmed_at, history: hist || [], vocabulary,
           trade_proposals: await tradeProposals(admin, supplierId) };
}

/** A trade name as a code: lower case, every run of non-letters/digits becomes '_'. The TS twin of
 *  public.fn_trade_code (every_intake_trade_resolves_to_the_capability_vocabulary.sql) — the two
 *  must agree, because a request's category resolves through that one and a supplier's typed trade
 *  through this one, and they meet on string equality in fn_match_capability. */
export const tradeCode = (name: unknown): string =>
  String(name ?? '').trim().toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '_').replace(/^_+|_+$/g, '');

/** fn_match_capability's p_limit when a request is matched: every gated candidate, never a top N. Any number of
 *  suppliers may quote (founder, 24 Sep 2026); this only bounds the SQL row count, far above any trade's list. */
export const MATCH_ALL = 100000;

/** Does decision_policy's match_relevance_floor gate this match? Only when the request named
 *  products: fn_match_capability's product term is 0 without them, so the floor would measure
 *  nothing and refuse every exact-trade supplier without a track record (measured 15 Sep 2026: 5.0
 *  against a floor of 35). The exact trade is then the whole relevance test. */
export const relevanceFloorApplies = (products: unknown): boolean =>
  Array.isArray(products) && products.some((p) => String(p ?? '').trim() !== '');

/** A supplier the gate holds ONLY because its services were unconfirmed (founder ledger 1469) is decided as soon as it confirms. An rpc
 *  answers {error}, it does not throw, so the error is read. The supplier is waiting on the page, so the call is
 *  fn_sales_engineer_verifies_supplier_now: the gate under a 3 s lock_timeout that answers {decision:'queued'} instead of hanging
 *  (10 Nov 2026: two 8 s statement timeouts back to back, then a 40.4 s confirm, all waiting on another transaction's founding-rank
 *  lock). 'queued' is decided by fn_sales_engineer_reruns_held_verifications within the minute. A timeout is NOT retried (a retry
 *  doubled the wait to 16 s and the tick re-runs it anyway); any other error is retried once, then LOGGED and put on the sales
 *  engineer's queue (agent_actions) and returned as gate:'failed', so a supplier cannot stay Pending in silence.
 *  The confirm itself stands whatever this does. Returns 'not_held' | the gate's decision | 'queued' | 'failed'. */
export async function rerunGateAfterConfirm(admin: Admin, supplierId: number): Promise<string> {
  try {
    const { data: held } = await admin.from('leads').select('licence_gate_reason').eq('id', supplierId).maybeSingle();
    if (held?.licence_gate_reason !== 'services_unconfirmed') return 'not_held';
    let last = '';
    for (let attempt = 0; attempt < 2; attempt++) {
      const { data, error } = await admin.rpc('fn_sales_engineer_verifies_supplier_now', { p_lead_id: supplierId, p_source: 'services_confirmed' });
      if (!error && data?.ok) return String(data.decision || 'unchanged');
      last = error?.message || JSON.stringify(data || {});
      if (/timeout|canceling statement/i.test(last)) break;
    }
    console.error('capabilityConfirm: the gate failed after the confirm', supplierId, last);
    await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'supplier_verification', status: 'failed', risk: 'medium',
      title: 'Services confirmed but the verification did not re-run — supplier #' + supplierId,
      detail: { supplier_id: supplierId, source: 'services_confirmed', error: last.slice(0, 500), rerun_by: 'fn_sales_engineer_reruns_held_verifications' },
      target_table: 'leads', target_id: String(supplierId) });
    return /timeout|canceling statement/i.test(last) ? 'queued' : 'failed';
  } catch (e) {
    console.error('capabilityConfirm: the gate was not re-run after the confirm', supplierId, String((e as Error)?.message || e));
    return 'failed';
  }
}

// Returns [httpStatus, body]. What the supplier agrees to is what we store.
//
// THE TRADE LIST IS OPEN (founder, 14 Sep 2026: "our categories are not finalized. if a supplier
// comes tomorrow and register for packaging services he is welcomed"). Until then a trade outside
// taxonomy_trade was silently dropped here, so a supplier of a trade nobody had listed could never be
// matched. Now any trade the supplier names is stored as given, normalised by tradeCode, and matches
// a request whose category is that same trade — exactly, never a neighbour. Roles stay a closed
// vocabulary: they drive the supplies/executes/whole_scope logic, not the trade gate.
export async function capabilityConfirm(admin: Admin, supplierId: number, body: Record<string, unknown>): Promise<[number, Record<string, unknown>]> {
  const vocab = await capabilityVocabulary(admin);
  const okTrade = new Set(vocab.trades.map((t: { code: string }) => t.code));
  const okRole = new Set(vocab.roles.map((r: { code: string }) => r.code));
  const rawTrades = strArr(body.trades, 25, 60);
  const trades = [...new Set(rawTrades.map(tradeCode).filter(Boolean))];
  const roles = strArr(body.roles, 8, 40).filter((c) => okRole.has(c));
  if (!trades.length || !roles.length) {
    return [400, { error: 'need_at_least_one_trade_and_role', code: 'capability_need_trade_role', valid_trades: [...okTrade], valid_roles: [...okRole] }];
  }
  const products = strArr(body.products, 40);
  const exclusions = strArr(body.exclusions, 25);
  const brands = strArr(body.brands, 40, 60);
  const projectTypes = strArr(body.project_types, 12, 60);
  const services = strArr(body.services, 120);
  // NOTHING TICKED IS NOT A CONFIRMATION (founder_instructions 857 and 862, 23 Sep 2026). The first visit
  // now starts unticked, so a supplier who presses Confirm without ticking anything would otherwise be
  // stored as confirmed — matchable, with an empty portfolio shown as complete — and under 857 he would
  // then reach no inquiry that names a service, without ever having been told why. So a confirm that
  // states no service at all (no ticked key and no words of his own) is refused whenever the trades he
  // confirms HAVE services to tick. A trade the taxonomy lists no service for has nothing to tick, and
  // is confirmed as before. Decided here, in the one writer of confirmed_at, so the Services tab's
  // services_save_rewrite and the older capability_confirm route (and any mobile client of either)
  // obey the same rule.
  if (!services.length) {
    const { data: tickable } = await admin.from('taxonomy_trade_service')
      .select('trade_code').eq('active', true).in('trade_code', trades).limit(1);
    if ((tickable || []).length) {
      return [400, { error: 'no_service_ticked', code: 'services_none_ticked', trades }];
    }
  }
  // Supplier-declared only. These feed a HARD gate in fn_match_capability (a job outside the range
  // removes the supplier from the candidate set), so null stays null and stays permissive.
  const nv = (v: unknown) => (v === null || v === undefined || v === '') ? null : (Number.isFinite(Number(v)) ? Number(v) : null);
  const minVal = nv(body.min_project_value);
  const maxVal = nv(body.max_project_value);
  if ((minVal !== null && minVal < 0) || (maxVal !== null && maxVal < 0) || (minVal !== null && maxVal !== null && minVal > maxVal)) {
    return [400, { error: 'invalid_project_value_range', code: 'capability_bad_range', min_project_value: minVal, max_project_value: maxVal }];
  }
  const { data: prev } = await admin.from('supplier_capability_confirmation')
    .select('version').eq('supplier_id', supplierId).order('version', { ascending: false }).limit(1).maybeSingle();
  // What we held BEFORE this confirm, read server-side: the ledger is the dispute record, so what the
  // documents said comes from our own stored reading, never from the browser's copy of it.
  const { data: before } = await admin.from('supplier_capabilities')
    .select('trades,proposed_trades,source_docs,services_removed').eq('supplier_id', supplierId).maybeSingle();
  // THROUGH A PARTNER (12 Nov 2026, ruling 1647; report 3.4, slice 4): the confirmed services he delivers through someone else.
  // ALWAYS A SUBSET OF `services`, enforced here, the one writer: a partner key he did not also confirm is dropped. A caller that
  // sends none (the older capability_confirm route) keeps what is stored, cut to the services now confirmed. Read on its own so
  // a deploy that lands before a_supplier_is_asked_what_his_documents_could_not_say.sql (the column) writes as before.
  const partnerRead = await admin.from('supplier_capabilities').select('services_partner').eq('supplier_id', supplierId).maybeSingle();
  const partnerColumn = !partnerRead.error;
  const sentPartner = body.services_partner === undefined
    ? (Array.isArray(partnerRead.data?.services_partner) ? partnerRead.data.services_partner as string[] : [])
    : strArr(body.services_partner, 120);
  const servicesPartner = [...new Set(sentPartner)].filter((k) => services.includes(k));
  const onFile: string[] = Array.isArray(before?.trades) ? before.trades : [];
  const fromDocs: string[] = Array.isArray(before?.proposed_trades) ? before.proposed_trades : [];
  const version = Number(prev?.version || 0) + 1;
  const now = new Date().toISOString();
  const capRow: Record<string, unknown> = {
    supplier_id: supplierId, trades, roles, products_norm: products, brands, project_types: projectTypes, exclusions,
    // 120, not 25 (15 Sep 2026): the Services checklist stores one '<trade>.<code>' per ticked service,
    // five per trade, plus up to 25 of the supplier's own words; 25 would have cut a five-trade company.
    services, coverage_emirates: strArr(body.coverage_emirates, 8, 40),
    missing_fields: [], review_status: 'confirmed', confirmed_at: now, confirmed_version: version, updated_at: now,
  };
  // Conditional: PostgREST's merge-duplicates only SETs columns present in the payload, so omitting a
  // key keeps a stored range instead of nulling it on a confirm from a screen that does not collect it.
  if (minVal !== null) capRow.min_project_value = minVal;
  if (maxVal !== null) capRow.max_project_value = maxVal;
  if (partnerColumn) capRow.services_partner = servicesPartner;
  const { error: upErr } = await admin.from('supplier_capabilities').upsert(capRow, { onConflict: 'supplier_id' });
  if (upErr) return [500, { error: 'capability_write_failed', code: 'capability_write_failed', detail: upErr.message }];
  // The ledger row is the dispute record: what this supplier agreed to receive, and when. Since slice 4 it also holds what he
  // delivers through a partner, what he removed, and every question he answered (read from the table, never from the browser).
  const answers = await answeredForLedger(admin, supplierId);
  await admin.from('supplier_capability_confirmation').insert({
    supplier_id: supplierId, version,
    proposed: { on_file_trades: onFile, document_trades: fromDocs },
    confirmed: { trades, roles, services, products, brands, project_types: projectTypes, min_project_value: minVal, max_project_value: maxVal,
                 services_partner: servicesPartner, services_removed: Array.isArray(before?.services_removed) ? before.services_removed : [], answers },
    supplier_added: { trades: trades.filter((c) => !onFile.includes(c) && !fromDocs.includes(c)) },
    exclusions, source_docs: obj(before?.source_docs),
    confirmed_at: now, confirmed_via: 'portal', agent_version: VERSION,
  });
  // A TRADE WE DO NOT LIST IS A PROPOSAL FOR THE SALES ENGINEER, NOT A SILENT STRING. It is still
  // stored and matched exactly as typed (above); this row is how the seat learns it exists and decides
  // to add it, offer an existing trade, or decline (fn_trade_proposal_decide).
  const newCodes = trades.filter((c) => !okTrade.has(c));
  if (newCodes.length) {
    await admin.from('taxonomy_trade_proposal').upsert(newCodes.map((code) => {
      const raw = rawTrades.find((r) => tradeCode(r) === code) || code;
      const ar = /[؀-ۿ]/.test(raw);
      return { supplier_id: supplierId, code, label_en: ar ? null : raw, label_ar: ar ? raw : null };
    }), { onConflict: 'supplier_id,code', ignoreDuplicates: true });
  }
  // An existing trade the seat offered in place of the supplier's own is applied only when the
  // supplier ticked it (and dropped their own): the supplier's agreement is the confirm itself.
  const { data: offers } = await admin.from('taxonomy_trade_proposal')
    .select('id,code,mapped_to').eq('supplier_id', supplierId).eq('status', 'map_offered');
  for (const o of offers || []) {
    if (trades.includes(o.mapped_to) && !trades.includes(o.code)) {
      await admin.from('taxonomy_trade_proposal').update({ status: 'mapped', decided_at: now }).eq('id', o.id);
    }
  }
  // A supplier the gate holds ONLY because its services were unconfirmed (founder ledger 1469) is decided now. Any other hold, and any
  // supplier already approved, is left to the gate's own triggers and clocks. The confirm stands whatever this call does.
  const gate = await rerunGateAfterConfirm(admin, supplierId);
  return [200, { ok: true, confirmed: true, version, trades, roles, gate, services_partner: servicesPartner, products_count: products.length, exclusions_count: exclusions.length,
                 new_trades_under_review: newCodes }];
}
