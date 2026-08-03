// dropbox_sync v3 - the Document Controller's server-side Dropbox integration. Uses the platform's stored Dropbox
// refresh token to index specific QuotesDone folders into public.dropbox_files. Read/index only — never deletes
// anything in Dropbox. Scoped to the QuotesDone folders (dropbox_roots secret) so the huge jewelry/media tree on the
// same account is ignored and the sync always completes. On a complete sync it prunes local index rows that no longer
// exist so the catalog matches Dropbox.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'dropbox_sync', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const { data } = await admin.from('agent_runs').select('id').eq('agent', 'dropbox_sync')
      .gte('started_at', since).eq('counts->>signal', signal).limit(1);
    if (data && data.length) return;
  } catch (_e) { /* if the check fails, fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function accessToken(): Promise<string|null> {
  const rt = await sec('dropbox_refresh_token'); const ak = await sec('dropbox_app_key'); const as = await sec('dropbox_app_secret');
  if (!rt || !ak || !as) return null;
  const body = new URLSearchParams({ grant_type: 'refresh_token', refresh_token: rt, client_id: ak, client_secret: as });
  const r = await fetch('https://api.dropboxapi.com/oauth2/token', { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body });
  const j = await r.json(); return j?.access_token || null;
}
async function listRoot(token: string, path: string){
  const entries: any[] = []; let complete = true; let truncated = false;
  let r = await fetch('https://api.dropboxapi.com/2/files/list_folder', { method:'POST', headers:{'Authorization':'Bearer '+token,'Content-Type':'application/json'}, body: JSON.stringify({ path, recursive: true, limit: 2000 }) });
  let j = await r.json();
  if (j?.error) { // a missing folder is not fatal for the whole sync
    return { entries, complete: false, error: j.error_summary || j.error };
  }
  entries.push(...(j.entries||[]));
  let guard = 0;
  while (j.has_more) { if (guard++ >= 200) { truncated = true; break; }
    r = await fetch('https://api.dropboxapi.com/2/files/list_folder/continue', { method:'POST', headers:{'Authorization':'Bearer '+token,'Content-Type':'application/json'}, body: JSON.stringify({ cursor: j.cursor }) });
    j = await r.json(); if (j?.error) { complete=false; break; } entries.push(...(j.entries||[]));
  }
  if (truncated) complete = false;
  return { entries, complete, truncated };
}
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'dropbox_sync');
    if (!__auth.ok) { await logThrottled('forbidden', 60, 'error', { stage:'auth' }, 'dropbox_sync rejected a caller presenting a bad or missing inbound secret. If this is the scheduled caller, the Dropbox document catalog is no longer being refreshed at all.'); return J({ error: 'forbidden' }, 403); }
    const runStart = new Date().toISOString();
    const token = await accessToken();
    if (!token) { await logThrottled('no_dropbox_auth', 60, 'error', { stage:'token' }, 'dropbox_sync could not obtain a Dropbox access token (refresh token expired/revoked or app key/secret missing). The dropbox_files catalog is frozen and the Document Controller is showing stale contents until the OAuth credentials are restored.'); return J({ ok:false, error:'no_dropbox_auth' }); }
    let roots: string[] = [];
    if (Array.isArray(body.paths)) roots = body.paths.map((p:any)=>String(p));
    else { try { roots = JSON.parse((await sec('dropbox_roots')) || '[]'); } catch { roots = []; await logThrottled('bad_dropbox_roots', 60, 'error', { stage:'config' }, 'The dropbox_roots secret is not valid JSON, so dropbox_sync silently fell back to the built-in default folder list; any custom backup folders configured there are not being indexed.'); } }
    if (!roots.length) roots = ['/QuotesDone Backup', '/quotes done'];

    let files=0, folders=0, up=0; let complete = true; const perRoot: any[] = [];
    let upsertFailed = 0; const rootErrors: string[] = []; let truncatedRoots = 0;
    for (const root of roots) {
      const res = await listRoot(token, root);
      if (!res.complete) complete = false;
      if ((res as any).error) rootErrors.push(root + ': ' + String((res as any).error).slice(0,120));
      if ((res as any).truncated) truncatedRoots++;
      perRoot.push({ root, entries: res.entries.length, complete: res.complete, error: (res as any).error||null });
      for (const e of res.entries) {
        const isFolder = e['.tag']==='folder';
        if (isFolder) folders++; else files++;
        const rec = { dropbox_id: e.id || e.path_lower, path: e.path_display || e.path_lower, name: e.name, is_folder: isFolder,
          size: isFolder ? 0 : (Number(e.size)||0), content_hash: e.content_hash || null,
          server_modified: e.server_modified || null, synced_at: new Date().toISOString() };
        const { error } = await admin.from('dropbox_files').upsert(rec, { onConflict: 'dropbox_id' });
        if (!error) up++; else upsertFailed++;
      }
    }
    // prune stale rows only on a fully complete sync of all roots
    let pruned = 0;
    if (complete) { const { count, error: pruneErr } = await admin.from('dropbox_files').delete({ count:'exact' }).lt('synced_at', runStart); pruned = count || 0; if (pruneErr) { await logRun('error', { stage:'prune', files, folders }, 'dropbox_sync could not prune stale rows from dropbox_files; the Document Controller will keep listing documents that no longer exist in Dropbox. ' + String(pruneErr?.message||pruneErr).slice(0,160)); } }

    const seen = files + folders;
    const counts = { roots: roots.length, files, folders, upserted: up, upsert_failed: upsertFailed, pruned, complete, root_errors: rootErrors.length, truncated_roots: truncatedRoots };
    if (seen > 0 || rootErrors.length > 0 || upsertFailed > 0) {
      if (rootErrors.length > 0) {
        await logThrottled('root_error', 60, 'error', counts, 'dropbox_sync could not list ' + rootErrors.length + ' configured Dropbox root(s), so those folders are missing from the document catalog and pruning was skipped (stale rows remain). ' + rootErrors.slice(0,3).join(' | '));
      } else if (upsertFailed > 0) {
        await logRun('error', counts, 'dropbox_sync failed to index ' + upsertFailed + ' of ' + seen + ' Dropbox entries; those documents exist in Dropbox but are invisible in the Document Controller.');
      } else if (truncatedRoots > 0) {
        await logThrottled('truncated', 60, 'error', counts, 'dropbox_sync hit the 200-page listing guard on ' + truncatedRoots + ' root(s), so the sync was incomplete, the catalog is only partially refreshed and stale-row pruning was skipped.');
      } else if (seen === 0) {
        await logThrottled('empty_result', 60, 'error', counts, 'dropbox_sync completed but found zero files or folders under the configured roots; the document catalog has just been pruned to empty, which usually means the roots are misconfigured or the Dropbox folders were moved.');
      } else {
        await logRun('ok', counts, 'dropbox_sync indexed ' + files + ' file(s) and ' + folders + ' folder(s), pruned ' + pruned + ' stale row(s).');
      }
    }
    return J({ ok:true, roots, per_root: perRoot, files, folders, upserted: up, pruned, complete });
  } catch (e) { await logRun('error', { stage:'fatal' }, 'dropbox_sync crashed before completing; the Dropbox document catalog was not refreshed on this run and may be stale or partially pruned. ' + String((e as Error)?.message || e).slice(0,200)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
