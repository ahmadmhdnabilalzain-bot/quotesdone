// sales_engineer — the Sales Engineer seat's runtime. The company's third agent, and the first one
// that has a health route.
//
// WHY IT EXISTS. The founder, 9 September 2026: "Sales Engineer and Customer Support report directly
// to the actual new CEO." This seat owns customer intake, document interpretation, technical scope,
// quote readiness, supplier identity and capability verification, supplier-safe RFQ construction,
// matching and dispatch — and keeps ownership until the outcome is VERIFIED.
//
// NO MODEL CALL, ANYWHERE IN HERE, and every action below was chosen so that is not a limitation.
// Measured 9 Sep 2026: all 8 routes in llm_route_health carry open_until = 2126-08-15 under the
// founder's own hold, and fn_kernel_paid_provider_gate denies GLOBALLY while any route is held. So a
// model-dependent runtime would be a dead one today.
//
// That constraint turned out to be clarifying rather than costly. The build prompt is explicit:
// "Use deterministic code for arithmetic, units, schema validation, permissions, budget
// reservations, state transitions and mandatory exclusions." An intake obligation set is exactly
// that — which of a sector's questions remain unresolved is a set difference over a field catalogue,
// not a judgement. The model's judgement belongs in interpreting a drawing and weighing conflicting
// evidence, which is the half that waits for the hold to lift. What is here does not.
//
// WHAT IS DELIBERATELY ABSENT, so nobody mistakes silence for capability: this function does not
// dispatch, does not email, does not write a supplier's verification state, and does not match. Each
// of those needs a capability the estate does not currently have (see `capability` below, which
// reports the honest per-format status the build prompt demands rather than a list of intentions).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}

// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. Same rule as ceo_agent, and written this way from
// the first line rather than retrofitted: ceo_agent shipped on 8 Sep reading `body.as` and believing
// it, which let any holder of an in-scope credential present as the CEO. An unrecognised context is
// refused rather than defaulted.
const SEAT_BY_CREDENTIAL: Record<string, 'sales_engineer'> = {
  'fn.sales_engineer': 'sales_engineer',
};

async function whoami(req: Request, body: Record<string, unknown>): Promise<'sales_engineer' | 'founder' | null> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'sales_engineer');
    if (r.ok) return SEAT_BY_CREDENTIAL[r.context] ?? null;
  }
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt).catch(() => ({ data: { user: null } } as never));
  const email = String((data as { user?: { email?: string } })?.user?.email || '').toLowerCase();
  if (!email) return null;
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  return allow.includes(email) ? 'founder' : null;
}

// EVERY CALL LEAVES A ROW. fn_agents_board LEFT JOINs agent_runs on agent = agent_key, so a seat
// that never writes one renders with runs24 = 0 — indistinguishable from a seat that is down.
// Neither existing agent does this; measured 9 Sep, agent_runs holds rows for send_outbox and
// login_otp only. Best-effort: attribution must never fail the call it is attributing.
async function run(action: string, status: string, counts: Record<string, unknown>, note?: string) {
  try {
    await admin.from('agent_runs').insert({
      agent: 'sales_engineer',
      status,
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
      counts: { action, ...counts },
      note: note ?? null,
    });
  } catch { /* an unwritten log must not turn a good answer into a 500 */ }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const who = await whoami(req, body);
    if (!who) return J({ error: 'unauthorized' }, 401);

    const action = String(body.action || '').trim();

    // ── HEALTH ─────────────────────────────────────────────────────────────────────────────────
    // Readiness measured, not asserted. The audit of 9 Sep found the only honest liveness signal for
    // the CEO seat was an authenticated round-trip returning 200; edge_health_probe exists with 0
    // rows and nothing writes it. This route answers the question directly: is the seat established,
    // what may it do, and what is it waiting on.
    if (action === 'health') {
      const [agent, grants, know, routes] = await Promise.all([
        admin.from('org_agents').select('agent_key,active,available').eq('agent_key', 'sales_engineer').maybeSingle(),
        admin.from('ceo_standing_grant').select('grant_key,action_class,active').eq('grantee_role_id', 'sales_engineer'),
        admin.from('sales_knowledge').select('record_id', { count: 'exact', head: true }),
        admin.from('llm_route_health').select('model_id,open_until'),
      ]);

      const held = (routes.data || []).filter((r: { open_until: string | null }) =>
        r.open_until && new Date(r.open_until) > new Date());

      // A knowledge table that does not exist yet is a stage of the build, not an error. Say which.
      const knowledgeCount = know.error ? null : (know.count ?? 0);

      await run('health', 'ok', { grants: (grants.data || []).length, knowledge: knowledgeCount });
      return J({
        ok: true,
        seat: 'sales_engineer',
        caller: who,
        seated: agent.data?.active === true && agent.data?.available === true,
        grants: (grants.data || []).map((g: { grant_key: string; action_class: string; active: boolean }) =>
          ({ grant: g.grant_key, class: g.action_class, active: g.active })),
        knowledge_records: knowledgeCount,
        knowledge_state: know.error ? 'not_ingested' : (knowledgeCount ? 'ingested' : 'empty'),
        // The single most useful thing this route can report, because it is what gates the half of
        // this seat that needs judgement.
        model_calls_available: held.length === 0,
        model_hold: held.length
          ? { routes_held: held.length, until: held[0].open_until,
              note: 'fn_kernel_paid_provider_gate denies globally while any route is held; the founder set this and only he can clear it' }
          : null,
      });
    }

    // ── GRANTS ─────────────────────────────────────────────────────────────────────────────────
    // What may this seat do right now, answered by the database at call time — expiry and active
    // state are evaluated inside fn_agent_may_act, so a revoked grant cannot be used from a cached
    // answer. An uncovered class routes to the CEO and says so; it never routes to the founder.
    if (action === 'grants') {
      const cls = String(body.action_class || '').trim();
      if (cls) {
        const { data, error } = await admin.rpc('fn_agent_may_act', {
          p_grantee_role_id: 'sales_engineer', p_action_class: cls,
          p_amount_aed: body.amount_aed ?? null,
        });
        if (error) return J({ ok: false, refused: error.message }, 400);
        await run('grants', 'ok', { action_class: cls });
        return J({ ok: true, action_class: cls, ...(data as Record<string, unknown>) });
      }
      const { data } = await admin.from('ceo_standing_grant')
        .select('grant_key,action_class,scope_note,limit_note,max_amount_aed,active,expires_at')
        .eq('grantee_role_id', 'sales_engineer').order('grant_key');
      await run('grants', 'ok', { listed: (data || []).length });
      return J({ ok: true, grants: data || [] });
    }

    // ── OBLIGATIONS ────────────────────────────────────────────────────────────────────────────
    // The intake obligation set for one sector: which questions still resolve a material
    // uncertainty, given what is already known.
    //
    // This is the build prompt's section 6 made deterministic: "Build an inquiry-specific obligation
    // set instead of asking every field in a static category checklist. Each question must resolve a
    // material uncertainty... do not dump an enormous form, repeatedly ask answered questions or
    // require irrelevant information."
    //
    // `answered` is the set of field_keys already resolved by earlier answers or by a document. The
    // difference is the obligation set. No model is consulted to compute a set difference, and one
    // consulted here would make the same question non-reproducible between two identical inquiries.
    if (action === 'obligations') {
      const sector = String(body.sector_id || '').trim();
      if (!sector) return J({ error: 'sector_id_required' }, 400);
      const answered = new Set((Array.isArray(body.answered) ? body.answered : []).map(String));

      const { data, error } = await admin.from('sales_qualification_field')
        .select('field_key,question,answer_type,ask_only_if,criticality,unknown_handling')
        .eq('sector_id', sector).order('field_key');

      if (error) return J({ ok: false, error: 'knowledge_not_ingested', detail: error.message }, 503);
      if (!data?.length) return J({ ok: false, error: 'unknown_sector', sector_id: sector }, 404);

      const open = data.filter((f: { field_key: string }) => !answered.has(f.field_key));
      await run('obligations', 'ok', { sector, total: data.length, open: open.length });
      return J({
        ok: true,
        sector_id: sector,
        total_fields: data.length,
        answered: data.length - open.length,
        obligations: open,
        // Stated rather than implied: this is the sector's catalogue, not a judgement that these are
        // the only things that matter for this particular inquiry.
        basis: 'seed catalogue for this sector; a document or an answer may retire a field, and an unusual scope may add one that is not listed here',
      });
    }

    // ── SECTORS ────────────────────────────────────────────────────────────────────────────────
    if (action === 'sectors') {
      const q = String(body.q || '').trim();
      let query = admin.from('sales_sector').select('sector_id,group_key,title,scope');
      if (q) query = query.or(`title.ilike.%${q}%,scope.ilike.%${q}%,sector_id.ilike.%${q}%`);
      const { data, error } = await query.order('sector_id').limit(Number(body.limit ?? 50));
      if (error) return J({ ok: false, error: 'knowledge_not_ingested', detail: error.message }, 503);
      await run('sectors', 'ok', { q, found: (data || []).length });
      return J({ ok: true, sectors: data || [], count: (data || []).length });
    }

    // ── CAPABILITY ─────────────────────────────────────────────────────────────────────────────
    // The per-format capability status the build prompt requires, section 8: "Implement real
    // parsers/adapters and expose per-format capability status... Never claim full extraction when
    // only a thumbnail or subset worked... Do not advertise unsupported DWG handling as completed."
    //
    // Every entry is MEASURED at call time against the deployed function list, not declared. A format
    // whose handler is not deployed reports unavailable with the reason, so a caller can tell "we
    // cannot read this" from "we read it and found nothing" — which are the same empty result and
    // very different facts.
    if (action === 'capability') {
      const { data: owned } = await admin.from('function_owner').select('function_slug');
      const present = new Set((owned || []).map((r: { function_slug: string }) => r.function_slug));

      // The handler each format needs, and what it can honestly do when it is present. Written from
      // the 9 Sep audit of every deployed document function, not from their names.
      const FORMATS = [
        { format: 'pdf_text_layer', handler: 'extract_text', gives: 'one flat text blob; no pages, no layout, no coordinates' },
        { format: 'pdf_scanned', handler: 'doc_extract', gives: 'OCR fallback — the only one in the estate' },
        { format: 'pdf_licence', handler: 'license_extract', gives: 'model-asserted licence fields; enum-whitelisted' },
        { format: 'pdf_quotation', handler: 'quote_extract', gives: 'quotation line items' },
        { format: 'drawing_to_boq', handler: 'drawing_boq', gives: 'model-read line items from page images; never geometry or scale' },
        { format: 'drawing_redaction', handler: 'drawing_redact', gives: 'pixel overlay on a raster; NOT layers, block attributes, xrefs or embedded thumbnails' },
        { format: 'dwg_dxf', handler: 'cad_convert', gives: 'raster preview only (200 dpi PNG via CloudConvert); no entities, layers or dimensions, ever' },
        { format: 'xlsx', handler: 'supplier_catalog_ingest', gives: 'first sheet only, cached values, hidden rows included, merges ignored' },
      ];

      const matrix = FORMATS.map((f) => ({
        ...f,
        available: present.has(f.handler),
        reason: present.has(f.handler) ? null : `${f.handler} is not deployed`,
      }));

      await run('capability', 'ok', { available: matrix.filter((m) => m.available).length, total: matrix.length });
      return J({
        ok: true,
        formats: matrix,
        available: matrix.filter((m) => m.available).length,
        total: matrix.length,
        // The sentence that must never be softened.
        native_dwg: 'NOT SUPPORTED. CloudConvert is configured and paid for, but it is a rasteriser — entity-level DWG needs a licensed SDK the estate does not have. Any DWG handling is raster preview only.',
      });
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) {
    await run('error', 'error', {}, String((e as Error).message || e));
    return J({ error: String((e as Error).message || e) }, 500);
  }
});
