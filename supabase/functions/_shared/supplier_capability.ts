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
const VERSION = 'supplier_api.capability@1';
const clip = (v: unknown, n: number) => String(v == null ? '' : v).slice(0, n);
const strArr = (v: unknown, n: number, len = 120): string[] =>
  Array.isArray(v) ? v.map((x) => clip(x, len)).filter(Boolean).slice(0, n) : [];
const obj = (v: unknown) => (v && typeof v === 'object' ? v : {});

export async function capabilityVocabulary(admin: Admin) {
  const { data: tr } = await admin.from('taxonomy_trade').select('code,label,authority_required').eq('active', true).order('sort');
  const { data: ro } = await admin.from('taxonomy_role').select('code,label,supplies,executes,whole_scope').eq('active', true).order('sort');
  return { trades: tr || [], roles: ro || [] };
}

export async function capabilityState(admin: Admin, supplierId: number) {
  const { data: cap } = await admin.from('supplier_capabilities').select('*').eq('supplier_id', supplierId).maybeSingle();
  const { data: hist } = await admin.from('supplier_capability_confirmation')
    .select('version,confirmed_at,confirmed_via').eq('supplier_id', supplierId).order('version', { ascending: false }).limit(5);
  const vocabulary = await capabilityVocabulary(admin);
  return { ok: true, capability: cap || null, confirmed: !!cap?.confirmed_at, history: hist || [], vocabulary };
}

// Returns [httpStatus, body]. What the supplier agrees to is what we store, validated against the
// controlled vocabulary so a bad client cannot inject codes that would silently never match.
export async function capabilityConfirm(admin: Admin, supplierId: number, body: Record<string, unknown>): Promise<[number, Record<string, unknown>]> {
  const vocab = await capabilityVocabulary(admin);
  const okTrade = new Set(vocab.trades.map((t: { code: string }) => t.code));
  const okRole = new Set(vocab.roles.map((r: { code: string }) => r.code));
  const trades = strArr(body.trades, 25, 40).filter((c) => okTrade.has(c));
  const roles = strArr(body.roles, 8, 40).filter((c) => okRole.has(c));
  if (!trades.length || !roles.length) {
    return [400, { error: 'need_at_least_one_trade_and_role', code: 'capability_need_trade_role', valid_trades: [...okTrade], valid_roles: [...okRole] }];
  }
  const products = strArr(body.products, 40);
  const exclusions = strArr(body.exclusions, 25);
  const brands = strArr(body.brands, 40, 60);
  const projectTypes = strArr(body.project_types, 12, 60);
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
  const version = Number(prev?.version || 0) + 1;
  const now = new Date().toISOString();
  const capRow: Record<string, unknown> = {
    supplier_id: supplierId, trades, roles, products_norm: products, brands, project_types: projectTypes, exclusions,
    services: strArr(body.services, 25), coverage_emirates: strArr(body.coverage_emirates, 8, 40),
    missing_fields: [], review_status: 'confirmed', confirmed_at: now, confirmed_version: version, updated_at: now,
  };
  // Conditional: PostgREST's merge-duplicates only SETs columns present in the payload, so omitting a
  // key keeps a stored range instead of nulling it on a confirm from a screen that does not collect it.
  if (minVal !== null) capRow.min_project_value = minVal;
  if (maxVal !== null) capRow.max_project_value = maxVal;
  const { error: upErr } = await admin.from('supplier_capabilities').upsert(capRow, { onConflict: 'supplier_id' });
  if (upErr) return [500, { error: 'capability_write_failed', code: 'capability_write_failed', detail: upErr.message }];
  // The ledger row is the dispute record: what this supplier agreed to receive, and when.
  await admin.from('supplier_capability_confirmation').insert({
    supplier_id: supplierId, version, proposed: obj(body.proposed),
    confirmed: { trades, roles, products, brands, project_types: projectTypes, min_project_value: minVal, max_project_value: maxVal },
    supplier_added: obj(body.supplier_added), exclusions, source_docs: obj(body.source_docs),
    confirmed_at: now, confirmed_via: 'portal', agent_version: VERSION,
  });
  return [200, { ok: true, confirmed: true, version, trades, roles, products_count: products.length, exclusions_count: exclusions.length }];
}
