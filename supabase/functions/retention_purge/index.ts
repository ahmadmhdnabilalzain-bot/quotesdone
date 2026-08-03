// retention_purge — data-minimisation job. Deletes transient customer drawing files
// (originals + redacted copies) for inquiries that concluded more than N months ago,
// then nulls their DB paths. Keeps supplier quote files (needed post-reveal) and KYC
// docs (handled by pdpl_erase). Internal only: __secret gated. Meant to run weekly.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'retention_purge', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const expectedSecret = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'retention_purge');
    if (!__auth.ok) {
      await logRun('error', { forbidden: 1, secret_configured: expectedSecret ? 1 : 0 }, expectedSecret ? 'Retention purge rejected a caller with a wrong __secret; no PDPL data-minimisation purge ran on this invocation. If this is the weekly cron, its secret is stale and expired drawing files are being retained indefinitely.' : 'Retention purge could not read inbound_secret from app_secrets, so every call including the weekly cron is rejected with 403. No customer drawing files are being purged and records past their retention window remain stored.');
      return J({ error: 'forbidden' }, 403);
    }
    const months = Math.max(1, Math.min(60, Number(body.months) || 6));
    const cutoff = new Date(Date.now() - months * 30 * 864e5).toISOString();
    const { data: inqs, error: inqsErr } = await admin.from('inquiries')
      .select('id,drawing_file_path,drawing_redacted_paths,status,completed_at,created_at')
      .in('status', ['completed', 'closed', 'cancelled'])
      .lt('created_at', cutoff)
      .limit(500);
    if (inqsErr) {
      await logRun('error', { months, inquiries_scanned: 0 }, 'Retention purge could not read the inquiries table, so nothing was scanned or deleted. Customer drawing files past the ' + months + '-month retention window remain stored. DB error: ' + String(inqsErr.message || inqsErr));
    }
    let filesRemoved = 0, rowsCleared = 0;
    const paths: string[] = []; const ids: string[] = [];
    for (const i of inqs || []) {
      const has = i.drawing_file_path || (Array.isArray(i.drawing_redacted_paths) && i.drawing_redacted_paths.length);
      if (!has) continue;
      if (i.completed_at && new Date(i.completed_at).toISOString() >= cutoff) continue;
      if (i.drawing_file_path) paths.push(String(i.drawing_file_path));
      if (Array.isArray(i.drawing_redacted_paths)) for (const p of i.drawing_redacted_paths) if (p) paths.push(String(p));
      ids.push(String(i.id));
    }
    let storageNote = '';
    if (paths.length) { const uniq = [...new Set(paths)]; try { const { error } = await admin.storage.from('drawing-files').remove(uniq); if (!error) filesRemoved = uniq.length; else storageNote = 'Storage delete failed for ' + uniq.length + ' drawing files in bucket drawing-files, so those customer files still exist in storage even though the job reported success: ' + String(error.message || error) + '. '; } catch (_e) { storageNote = 'Storage delete threw for ' + uniq.length + ' drawing files in bucket drawing-files, so those customer files still exist in storage even though the job reported success: ' + String((_e as Error)?.message || _e) + '. '; } }
    let updateNote = '';
    if (ids.length) { const { error } = await admin.from('inquiries').update({ drawing_file_path: null, drawing_redacted_paths: null }).in('id', ids); if (!error) rowsCleared = ids.length; else updateNote = 'Clearing drawing_file_path/drawing_redacted_paths failed for ' + ids.length + ' inquiries, so the database still points at purged files and the same rows will be re-processed every week: ' + String(error.message || error) + '. '; }
    const counts = { months, inquiries_scanned: (inqs || []).length, files_targeted: [...new Set(paths)].length, files_removed: filesRemoved, rows_targeted: ids.length, rows_cleared: rowsCleared };
    if (storageNote || updateNote) await logRun('error', counts, storageNote + updateNote);
    else if (!inqsErr) await logRun('ok', counts, '');
    return J({ ok: true, months, cutoff, inquiries_scanned: (inqs || []).length, files_removed: filesRemoved, rows_cleared: rowsCleared });
  } catch (e) { await logRun('error', {}, 'Retention purge crashed before completing, so the PDPL data-minimisation sweep did not run and expired customer drawing files remain stored: ' + String((e as Error)?.message || e)); return J({ ok: false, error: String((e as Error)?.message || e) }, 500); }
});
