// assets_ingest v2 — makes agents ASSET-AWARE (compact, deduped).
// Reads Dropbox "/QuotesDone Backup/Assets", folds text assets into agent_knowledge,
// and writes a COMPACT folder-grouped index of binary assets so it fits the brain budget.
// Auth: __secret == inbound_secret.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

const ASSETS_PATH = '/QuotesDone Backup/Assets';
const TEXT_EXT = new Set(['md', 'txt', 'csv', 'json', 'html']);
const human = (n: number) => n == null ? '?' : (n > 1048576 ? (n / 1048576).toFixed(1) + ' MB' : (n > 1024 ? (n / 1024).toFixed(0) + ' KB' : n + ' B'));

async function dbxToken(): Promise<string> {
  const [key, secret, refresh] = await Promise.all([sec('dropbox_app_key'), sec('dropbox_app_secret'), sec('dropbox_refresh_token')]);
  const body = new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refresh || '', client_id: key || '', client_secret: secret || '' });
  const r = await fetch('https://api.dropboxapi.com/oauth2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
  const j = await r.json(); if (!j.access_token) throw new Error('dropbox_auth_failed: ' + JSON.stringify(j).slice(0, 200));
  return j.access_token as string;
}
async function dbxRpc(token: string, path: string, arg: unknown) {
  const r = await fetch('https://api.dropboxapi.com/2/' + path, { method: 'POST', headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify(arg) });
  const txt = await r.text(); let j: any = {}; try { j = JSON.parse(txt); } catch (_e) { j = { _raw: txt }; }
  return { ok: r.ok, status: r.status, j };
}
async function dbxDownload(token: string, path: string): Promise<string> {
  const r = await fetch('https://content.dropboxapi.com/2/files/download', { method: 'POST', headers: { 'Authorization': 'Bearer ' + token, 'Dropbox-API-Arg': JSON.stringify({ path }) } });
  if (!r.ok) return ''; return (await r.text()).slice(0, 12000);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  const body = await req.json().catch(() => ({} as any));
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'assets_ingest');
  if (!__auth.ok) return J({ error: 'forbidden' }, 403);
  const started = new Date().toISOString();
  try {
    const token = await dbxToken();
    await dbxRpc(token, 'files/create_folder_v2', { path: ASSETS_PATH, autorename: false });

    // list recursively
    const files: any[] = [];
    const res = await dbxRpc(token, 'files/list_folder', { path: ASSETS_PATH, recursive: true, limit: 2000 });
    if (!res.ok) return J({ error: 'list_failed', detail: res.j }, 200);
    const collect = (entries: any[]) => { for (const e of entries) { if (e['.tag'] === 'file') files.push(e); } };
    collect(res.j.entries || []);
    let cursor = res.j.cursor, hasMore = res.j.has_more, guard = 0;
    while (hasMore && guard++ < 20) { const c = await dbxRpc(token, 'files/list_folder/continue', { cursor }); if (!c.ok) break; collect(c.j.entries || []); cursor = c.j.cursor; hasMore = c.j.has_more; }

    // group by the first folder segment under ASSETS_PATH; ingest text files in full
    const groups: Record<string, { count: number; bytes: number; examples: string[] }> = {};
    const textEntries: { topic: string; content: string }[] = [];
    const prefixLen = ASSETS_PATH.length + 1;
    for (const f of files) {
      const name = f.name as string; const path = f.path_display || f.path_lower;
      const rel = String(path).slice(prefixLen);
      const seg = rel.includes('/') ? rel.split('/')[0] : '(root)';
      const g = groups[seg] || (groups[seg] = { count: 0, bytes: 0, examples: [] });
      g.count++; g.bytes += Number(f.size) || 0;
      const ext = (name.split('.').pop() || '').toLowerCase();
      const notable = /logo|lockup|cover|avatar|icon_|mark|banner|kit|guide|palette|font/i.test(name);
      if (g.examples.length < 6 && (notable || g.examples.length < 3)) g.examples.push(name);
      if (TEXT_EXT.has(ext) && (f.size || 0) < 200000) {
        const content = await dbxDownload(token, path);
        if (content && content.trim()) textEntries.push({ topic: ('Asset text: ' + name).slice(0, 120), content: ('From company asset "' + name + '" (Dropbox: ' + path + ')\n\n' + content).slice(0, 8000) });
      }
    }

    // wipe previous asset knowledge (two clean deletes — no malformed or() filters)
    await admin.from('agent_knowledge').delete().eq('agent_key', '_global').eq('topic', 'Company assets (auto-synced from Dropbox)');
    await admin.from('agent_knowledge').delete().eq('agent_key', '_global').like('topic', 'Asset text: %');

    // compact manifest (folder summary, capped)
    let manifest: string;
    if (files.length) {
      const lines = Object.entries(groups).sort((a, b) => b[1].count - a[1].count).map(([g, v]) => '- ' + g + ' — ' + v.count + ' file(s), ' + human(v.bytes) + (v.examples.length ? (' · e.g. ' + v.examples.join(', ')) : ''));
      manifest = 'COMPANY ASSETS (synced from Dropbox "' + ASSETS_PATH + '", ' + files.length + ' files). These are real files the company owns; reference them and give the founder the Dropbox path when useful. Folders:\n' + lines.join('\n') + '\n\nText docs (brand voice, colours, letterhead, where-to-use) are read into your knowledge in full. For a specific image/logo/cover, tell the founder the folder above and offer to fetch the exact filename.';
    } else {
      manifest = 'COMPANY ASSETS: the Dropbox folder "' + ASSETS_PATH + '" is currently empty. Drop the PRO brand kit and social kit there to make agents asset-aware.';
    }
    await admin.from('agent_knowledge').insert({ agent_key: '_global', topic: 'Company assets (auto-synced from Dropbox)', content: manifest.slice(0, 3500), priority: 60 });
    if (textEntries.length) await admin.from('agent_knowledge').insert(textEntries.map((t) => ({ agent_key: '_global', topic: t.topic, content: t.content, priority: 45 })));

    const counts = { files: files.length, folders: Object.keys(groups).length, text_ingested: textEntries.length };
    await admin.from('agent_runs').insert({ agent: 'assets_ingest', started_at: started, finished_at: new Date().toISOString(), status: 'ok', counts });
    return J({ ok: true, path: ASSETS_PATH, ...counts, folders: Object.fromEntries(Object.entries(groups).map(([k, v]) => [k, v.count])) });
  } catch (e) {
    await admin.from('agent_runs').insert({ agent: 'assets_ingest', started_at: started, finished_at: new Date().toISOString(), status: 'error', note: String(e).slice(0, 200) });
    return J({ error: String((e as Error)?.message || e) }, 200);
  }
});
