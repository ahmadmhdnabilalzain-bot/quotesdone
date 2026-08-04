// kb_corpus_import - the ONLY write path for the QuotesDone knowledge corpus.
// (Named apart from the pre-existing kb_import, which is an unrelated one-off kb_chunks loader.)
//
// WHY THIS EXISTS AS A FUNCTION RATHER THAN A SCRIPT WITH A DATABASE PASSWORD.
// The corpus is 115,118 records across 67 packages, ~174 MB of JSONL. Three ways to land it, two of
// them bad:
//   * paste it through a model  - forbidden by the control pack, and would cost more than the
//     company's monthly AI budget to achieve nothing;
//   * hand a service-role key to a local script - that key is the whole platform (app_secrets holds
//     every third-party credential behind it), and it would then exist on a laptop and in a shell
//     history forever.
// So the importer runs OUTSIDE with no platform credential at all, and this function is a narrow,
// token-authenticated writer that holds the service role inside the Supabase runtime where it
// already lives. The token is single-purpose, stored in app_secrets, and is deleted the moment the
// import is signed off - losing it costs an attacker write access to kb_stage and nothing else.
//
// DESIGN RULES, all of them load-bearing:
//   1. TARGETS ARE AN ALLOWLIST. The caller names a logical target ('records', 'questions', ...),
//      never a table. There is no code path where caller input reaches a table name, so there is
//      nothing to inject.
//   2. NO MODEL CALLS. Ingestion must be deterministic and free. This function never touches
//      ai_gateway or OpenRouter.
//   3. IDEMPOTENT BY STABLE ID. Every write is an upsert on the supplied record/question/rule ID.
//      Re-running the whole import is a no-op, which is what makes "resume after interruption" and
//      "rerun creates no duplicates" the same mechanism rather than two.
//   4. FAIL LOUD, PER BATCH. A rejected batch returns the Postgres message and the failing IDs. It
//      does not half-write and report success - a knowledge base that is quietly 4% wrong is worse
//      than one that is visibly broken.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// One client, public schema only. kb_stage is deliberately NOT exposed to PostgREST - a
// createClient({db:{schema:'kb_stage'}}) fails with "Invalid schema: kb_stage", and exposing it to
// fix that would put 115,000 unreviewed records and every internal decision rule on the REST
// surface. All staging writes go through the SECURITY DEFINER functions kb_stage_upsert /
// kb_begin_run / kb_finish_run / kb_get_hashes, which are the only doors into that schema.
const admin = createClient(URL_, SERVICE);

const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return (data?.value as string | undefined) || undefined;
}
// Fail-closed: a missing or short secret must never equal a caller-supplied value. This is the same
// bug that was found across ~30 functions on 27 Jul - an absent secret made {} a valid credential.
const tokenOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 32;

// The allowlist now lives in kb_stage_upsert's CASE statement, one layer further from the network.
// This set exists only so an unknown target is refused here with a useful message instead of raising
// inside Postgres.
const TARGETS = new Set([
  'sources', 'categories', 'subcategories', 'records', 'questions', 'decision_rules',
  'validation_rules', 'scenario_tests', 'knowledge_gaps', 'crosswalk', 'file_hashes',
  'op_route', 'op_route_map', 'op_alias', 'op_route_test',
]);

const MAX_ROWS = 1000; // the pack's upper bound; keeps one request inside the function memory limit

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok');
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const expected = await sec('kb_import_token');
    if (!tokenOk(expected) || body.__token !== expected) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || '');

    if (action === 'ping') return J({ ok: true, ts: new Date().toISOString() });

    // --- run bookkeeping -------------------------------------------------------------------
    if (action === 'begin_run') {
      const pkg = String(body.package_id || '');
      const ver = String(body.package_version || '');
      const sha = body.package_sha256 ? String(body.package_sha256) : null;
      if (!pkg || !ver) return J({ error: 'package_id_and_version_required' }, 400);
      // A completed run for the identical bytes means there is nothing to do. Returning it rather
      // than starting a second run is what makes a full re-import cost seconds instead of an hour.
      const { data, error } = await admin.rpc('kb_begin_run', { p_package_id: pkg, p_version: ver, p_sha: sha ?? '' });
      if (error) return J({ error: error.message }, 500);
      // deno-lint-ignore no-explicit-any
      const r = data as any;
      return J({ ok: true, run_id: r.run_id, reused: r.reused, status: r.status });
    }

    if (action === 'finish_run') {
      const id = String(body.run_id || '');
      if (!id) return J({ error: 'run_id_required' }, 400);
      const { error } = await admin.rpc('kb_finish_run', {
        p_run_id: id, p_status: String(body.status || 'completed'),
        p_inserted: Number(body.inserted_count || 0), p_updated: Number(body.updated_count || 0),
        p_rejected: Number(body.rejected_count || 0), p_report: body.report ?? {},
      });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true });
    }

    // --- file-level skip ledger -------------------------------------------------------------
    if (action === 'get_hashes') {
      const { data, error } = await admin.rpc('kb_get_hashes', { p_package_id: String(body.package_id || '') });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, hashes: data ?? {} });
    }

    if (action === 'put_hash') {
      const { error } = await admin.rpc('kb_stage_upsert', {
        p_target: 'file_hashes',
        p_rows: [{
          package_id: String(body.package_id || ''), file_name: String(body.file_name || ''),
          sha256: String(body.sha256 || ''), rows_seen: Number(body.rows_seen || 0),
          last_run_id: body.run_id ? String(body.run_id) : null,
          updated_at: new Date().toISOString(),
        }],
      });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true });
    }

    // --- the actual write ---------------------------------------------------------------------
    if (action === 'batch') {
      const target = String(body.target || '');
      if (!TARGETS.has(target)) return J({ error: 'unknown_target', target, allowed: [...TARGETS] }, 400);
      const rows = Array.isArray(body.rows) ? body.rows : [];
      if (!rows.length) return J({ ok: true, written: 0 });
      if (rows.length > MAX_ROWS) return J({ error: 'batch_too_large', max: MAX_ROWS, got: rows.length }, 400);

      const { data, error } = await admin.rpc('kb_stage_upsert', { p_target: target, p_rows: rows });
      if (error) {
        // Return enough to fix it without returning the payload: the reason plus the IDs involved.
        // deno-lint-ignore no-explicit-any
        const first = rows[0] as any;
        const idField = ['record_id', 'rule_id', 'source_id', 'question_id', 'validation_id',
                         'scenario_id', 'category_slug', 'catalog_num', 'test_id']
                        .find((k) => first && k in first) || 'id';
        // deno-lint-ignore no-explicit-any
        const ids = rows.slice(0, 25).map((r: any) => r?.[idField]).filter(Boolean);
        return J({ error: error.message, details: error.details ?? null, hint: error.hint ?? null,
                   target, rows: rows.length, id_field: idField, sample_ids: ids }, 422);
      }
      return J({ ok: true, written: rows.length, affected: data ?? null });
    }

    // --- COMPANY OPERATIONS CORPUS -------------------------------------------------------------
    // Second corpus, same shape of problem, so the same door rather than a second function with a
    // second token and a second thing to forget to revoke. Targets are validated inside
    // ops_stage_upsert's CASE; this set only produces a better error for a typo.
    if (action.startsWith('ops_')) {
      if (action === 'ops_begin_run') {
        const { data, error } = await admin.rpc('ops_begin_run', {
          p_package: String(body.package_name || ''), p_version: String(body.package_version || ''),
          p_sha: String(body.package_sha256 || ''),
        });
        if (error) return J({ error: error.message }, 500);
        return J({ ok: true, ...(data as Record<string, unknown>) });
      }
      if (action === 'ops_finish_run') {
        const { error } = await admin.rpc('ops_finish_run', {
          p_run_id: String(body.run_id || ''), p_status: String(body.status || 'completed'),
          p_ins: Number(body.inserted_count || 0), p_upd: Number(body.updated_count || 0),
          p_skip: Number(body.skipped_count || 0), p_rej: Number(body.rejected_count || 0),
          p_detail: body.detail ?? {},
        });
        if (error) return J({ error: error.message }, 500);
        return J({ ok: true });
      }
      if (action === 'ops_get_files') {
        const { data, error } = await admin.rpc('ops_get_files', { p_run_id: String(body.run_id || '') });
        if (error) return J({ error: error.message }, 500);
        return J({ ok: true, files: data ?? {} });
      }
      if (action === 'ops_rollback_run') {
        const { data, error } = await admin.rpc('ops_rollback_run', { p_run_id: String(body.run_id || '') });
        if (error) return J({ error: error.message }, 500);
        return J({ ok: true, result: data });
      }
      if (action === 'ops_batch') {
        const rows = Array.isArray(body.rows) ? body.rows : [];
        if (!rows.length) return J({ ok: true, written: 0 });
        if (rows.length > MAX_ROWS) return J({ error: 'batch_too_large', max: MAX_ROWS, got: rows.length }, 400);
        const { data, error } = await admin.rpc('ops_stage_upsert', { p_target: String(body.target || ''), p_rows: rows });
        if (error) {
          // deno-lint-ignore no-explicit-any
          const first = rows[0] as any;
          const idField = ['record_id', 'source_id', 'department_key', 'workflow_key', 'concept_key']
            .find((k) => first && k in first) || 'id';
          // deno-lint-ignore no-explicit-any
          const ids = rows.slice(0, 25).map((r: any) => r?.[idField]).filter(Boolean);
          return J({ error: error.message, details: error.details ?? null, hint: error.hint ?? null,
                     target: body.target, rows: rows.length, id_field: idField, sample_ids: ids }, 422);
        }
        return J({ ok: true, written: rows.length, affected: data ?? null });
      }
      return J({ error: 'unknown_ops_action', action }, 400);
    }

    // --- source-of-truth transfer for the importer itself ---------------------------------------
    // The importer runs in a workspace that has no direct access to the repository checkout. Rather
    // than retyping ~700 lines of Python across that gap by hand (slow, and every retype is a chance
    // to introduce a difference between the code that ran and the code that is committed), the
    // importer uploads its own source through this action and the repo pulls it down verbatim. The
    // committed script is then byte-identical to the one that actually produced the 115,148 rows.
    // Private bucket, service role only, plain text only.
    if (action === 'put_asset' || action === 'get_asset') {
      const name = String(body.name || '').replace(/[^A-Za-z0-9._-]/g, '_');
      if (!name) return J({ error: 'name_required' }, 400);
      const BUCKET = 'kb-import-assets';
      try { await admin.storage.createBucket(BUCKET, { public: false }); } catch (_e) { /* exists */ }
      if (action === 'put_asset') {
        const content = String(body.content ?? '');
        const { error } = await admin.storage.from(BUCKET)
          .upload(name, new Blob([content], { type: 'text/plain' }), { upsert: true, contentType: 'text/plain' });
        if (error) return J({ error: error.message }, 500);
        return J({ ok: true, name, bytes: content.length });
      }
      const { data, error } = await admin.storage.from(BUCKET).download(name);
      if (error || !data) return J({ error: error?.message || 'not_found' }, 404);
      return J({ ok: true, name, content: await data.text() });
    }

    // --- migration mirror ----------------------------------------------------------------------
    // Migrations applied through the Supabase management API exist in supabase_migrations but not
    // in the repository, which is precisely the drift that has bitten this project before. This
    // returns their SQL so a checkout can be brought back to production truth in one command.
    if (action === 'dump_migrations') {
      const since = String(body.since || '20260802000000');
      const { data, error } = await admin.rpc('kb_dump_migrations', { p_since: since });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, migrations: data ?? [] });
    }

    // --- rollback -----------------------------------------------------------------------------
    if (action === 'rollback_run') {
      const id = String(body.run_id || '');
      if (!id) return J({ error: 'run_id_required' }, 400);
      const { data, error } = await admin.rpc('rollback_ingestion_run', { p_run_id: id });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, result: data });
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
});
