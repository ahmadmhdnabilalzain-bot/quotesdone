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

// A PORTAL CALLER IS A THIRD KIND OF CALLER, and it is the one the founder's 9 Sep ruling adds:
// "if its on the home page then the support replies. but if its on the customer or supplier portal
// then its the sales engineer". PortalShell already sends the customer's own session token; this
// resolves it to a customer row and NOTHING WIDER. `customer` may read its own report and ask its
// own questions; it may not name another party. Note customers.id is NOT auth.users.id (measured 9
// Sep: the one real customer's id does not exist in auth.users) — the verified JWT email is the
// join, which is the same identity rule the estate already uses: a phone may confirm, never select.
type Caller =
  | { kind: 'sales_engineer' | 'founder' }
  | { kind: 'customer'; customerId: string; email: string }
  | null;

async function whoami(req: Request, body: Record<string, unknown>): Promise<Caller> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'sales_engineer');
    if (r.ok && SEAT_BY_CREDENTIAL[r.context]) return { kind: 'sales_engineer' };
  }
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt).catch(() => ({ data: { user: null } } as never));
  const email = String((data as { user?: { email?: string } })?.user?.email || '').toLowerCase();
  if (!email) return null;
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  if (allow.includes(email)) return { kind: 'founder' };
  const { data: cust } = await admin.from('customers').select('id').ilike('email', email).maybeSingle();
  return cust?.id ? { kind: 'customer', customerId: String(cust.id), email } : null;
}

// EMBEDDING IS FREE AND IS NOT OpenRouter. ai_gateway serves {action:'embed'} at its line 204,
// BEFORE routing and before fn_kernel_paid_provider_gate, from Supabase.ai.Session('gte-small') —
// an in-region 384-dim model with no bill and no route. Those are the same six lines, run here
// rather than across a network hop that would also need a second scoped credential for a local
// model. Verified 9 Sep 2026 by reading ai_gateway/index.ts:54-63.
// deno-lint-ignore no-explicit-any
let _emb: any = null;
async function embed(text: string): Promise<string | null> {
  try {
    // deno-lint-ignore no-explicit-any
    if (_emb === null) _emb = new (globalThis as any).Supabase.ai.Session('gte-small');
    const v = await _emb.run(String(text).slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
    return '[' + v.join(',') + ']';
  } catch (_e) { return null; }
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
    const caller = await whoami(req, body);
    if (!caller) return J({ error: 'unauthorized' }, 401);

    const action = String(body.action || '').trim();

    // ── ASSIST ─────────────────────────────────────────────────────────────────────────────────
    // The portal assistant. PortalShell.tsx called site_assistant — Support's function, and correct
    // on the public homepage but wrong inside the customer portal by the founder's ruling of 9 Sep.
    //
    // NO MODEL, so the answer is RETRIEVED OR ESCALATED. fn_sales_assist reads SEVEN corpora, not
    // one: sales_knowledge (1,136), ops_knowledge (9,139), kb_chunks (2,686,026), agent_knowledge
    // (2,556, of which 1,627 are the live 'cat:' technical body), support_knowledge (408),
    // category_specs (56) and category_quote_specs (141). The first build of this handler searched
    // sales_knowledge alone — 0.042% of what the seat is entitled to — and the founder rejected the
    // refusal that produced on 9 Sep: "there is no reason for him not to know whatsoever."
    //
    // THE FLOORS DID NOT MOVE, because a nearest neighbour is ALWAYS found and an unfiltered vector
    // search answers nonsense as confidently as it answers a real question. A row that HAS an
    // embedding must clear cosine 0.86 (fn_faq_answer's number) AND match the tsvector. A row that
    // has NO embedding — 93.8% of kb_chunks, all of support_knowledge, all 1,627 'cat:' rows —
    // cannot be put to the vector floor at all, so it must clear a stricter lexical-only bar
    // instead. The lexical index is the only instrument in this estate that returns nothing for
    // nothing, which is why it gates both routes.
    //
    // WHEN NOTHING CLEARS, SOMETHING STILL HAPPENS. The refusal string is gone. The routine records
    // the question in sales_knowledge_gap (deduplicated, counted — the acquisition backlog) and
    // opens an org_tasks row owned by sales_engineer, and the asker is given the task number and
    // the owner. Which records were retrieved, how close each was and which were cited are written
    // to sales_decision_log from INSIDE the retrieval routine, so this handler cannot forget to.
    if (action === 'assist') {
      const message = String(body.message || '').trim();
      if (!message) return J({ error: 'message_required' }, 400);

      const vec = await embed(message);
      const { data, error } = await admin.rpc('fn_sales_assist', {
        p_text: message, p_embedding: vec,
        p_min_similarity: Number(body.min_similarity ?? 0.86),
        p_min_rank: Number(body.min_rank ?? 0.05),
        p_k: Number(body.k ?? 5),
        p_actor: 'sales_engineer',
      });
      if (error) return J({ ok: false, error: 'retrieval_failed', detail: error.message }, 503);

      const r = data as Record<string, unknown>;
      const recs = (r.records || []) as Array<Record<string, unknown>>;
      // Plain text: the widget renders a string, not markdown. Deterministic assembly of the cited
      // records — no generation step, nothing to hallucinate with. Each passage now names the body
      // it came from, because a cross-corpus answer that does not say whether it is quoting the
      // company's own policy or a trade standard is a worse answer than one that does.
      const reply = r.answered
        ? recs.map((x) =>
            String(x.title || '(untitled)') + '\n' +
            '[' + String(x.corpus) + (x.provenance ? ' · ' + String(x.provenance) : '') + ']\n' +
            String(x.content)).join('\n\n')
        : String(r.handoff || 'I do not have that yet.');

      await run('assist', 'ok', {
        answered: r.answered === true,
        cited: Array.isArray(r.cited) ? r.cited.length : 0,
        refusal: r.refusal ?? null,
        task_id: r.task_id ?? null,
      });

      return J({
        ok: true,
        seat: 'sales_engineer',
        answered: r.answered === true,
        reply,
        cited: r.cited,
        corpora: r.corpora,
        floor: r.floor,
        refusal: r.refusal ?? null,
        // The fallback is an action now, not a sentence. Surfaced so a caller can show the task.
        task_id: r.task_id ?? null,
        gap_recorded: r.gap_recorded === true,
        // Never claimed, always stated: this seat has no model today.
        basis: 'retrieved across sales_knowledge, ops_knowledge, kb_chunks, agent_knowledge, support_knowledge, category_specs and category_quote_specs under a similarity floor with lexical corroboration (embedded rows) or a stricter lexical-only bar (rows with no embedding); no model was called, so passages are quoted, never fused or restated',
        scope: caller.kind === 'customer' ? { customer_id: caller.customerId } : { caller: caller.kind },
      });
    }

    // ── REPORT ─────────────────────────────────────────────────────────────────────────────────
    // "he does the comparison reports, he basically fill the reports for suppliers and customers
    // about jobs won / supplier ratings / customer total spend literally everything related to
    // both portals." Every figure carries its basis — true_zero / measured / unknown /
    // derived_not_earned — because three different facts print as the character 0 on this
    // database today and collapsing them would be the misinformation, not the zero.
    //
    // A CUSTOMER CALLER MAY ONLY READ ITSELF. The party is taken from the resolved session, not
    // from the body, so a portal caller cannot widen what it can see by renaming the subject.
    if (action === 'report') {
      let kind = String(body.party_kind || '').trim().toLowerCase();
      let id = String(body.party_id ?? '').trim();
      if (caller.kind === 'customer') { kind = 'customer'; id = caller.customerId; }
      if (!kind || !id) return J({ error: 'party_kind_and_party_id_required' }, 400);

      const { data, error } = await admin.rpc('fn_sales_portal_report', { p_party_kind: kind, p_party_id: id });
      if (error) return J({ ok: false, error: 'report_failed', detail: error.message }, 503);
      await run('report', 'ok', { party_kind: kind });
      return J(data);
    }

    // Everything below `assist` and `report` is INTERNAL: seat readiness, the grant ledger, the
    // sector catalogue and the format matrix. A portal customer is authenticated but is not staff,
    // and an authenticated caller reaching an operator route is how privilege quietly widens.
    if (caller.kind === 'customer') return J({ error: 'forbidden', action }, 403);

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
        caller: caller.kind,
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
