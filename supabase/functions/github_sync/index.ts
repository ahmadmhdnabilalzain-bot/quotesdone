// github_sync — nightly organization-as-code mirror.
// Exports the org (fn_org_export) and commits changed files to GitHub under
// ai-organization/org-as-code/ using the git data API. Skips the commit entirely
// when nothing changed (identical tree sha). Auth: __secret (cron) only.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!body.__secret || body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const token = await sec('github_token');
    if (!token) return J({ error: 'github_token not configured in app_secrets' }, 500);
    const repo = (await sec('github_repo')) || 'ahmadmhdnabilalzain-bot/quotesdone';
    const branch = (await sec('github_branch')) || 'main';
    const api = 'https://api.github.com/repos/' + repo;
    const H = { 'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json' };

    const { data: exp, error } = await admin.rpc('fn_org_export');
    if (error || !exp) return J({ error: 'export failed: ' + (error?.message || 'empty') }, 500);
    const base = 'ai-organization/org-as-code/';
    const tree: any[] = [];
    for (const [key, val] of Object.entries(exp as Record<string, unknown>)) {
      if (key === 'exported_at') continue;
      tree.push({ path: base + key + '.json', mode: '100644', type: 'blob', content: JSON.stringify(val, null, 1) });
    }
    tree.push({ path: 'ai-organization/EXPORTED_AT.txt', mode: '100644', type: 'blob', content: String((exp as any).exported_at || new Date().toISOString()) });

    // Full DB schema mirror — keeps GitHub in sync with the live Supabase schema
    // (tables, functions, views, triggers, indexes, RLS, policies, cron; secret VALUES
    // and row data excluded). Best-effort: if it fails, still sync the org-as-code files.
    try {
      const { data: schema } = await admin.rpc('fn_schema_export');
      if (schema && typeof schema === 'string' && schema.length > 100) {
        tree.push({ path: 'supabase/schema/full_schema.sql', mode: '100644', type: 'blob', content: schema });
      }
    } catch (_e) { /* schema export is best-effort */ }

    const ref = await fetch(api + '/git/ref/heads/' + branch, { headers: H }).then(r => r.json());
    const headSha = ref?.object?.sha; if (!headSha) return J({ error: 'ref lookup failed: ' + JSON.stringify(ref).slice(0, 200) }, 500);
    const headCommit = await fetch(api + '/git/commits/' + headSha, { headers: H }).then(r => r.json());
    const baseTree = headCommit?.tree?.sha;

    const newTree = await fetch(api + '/git/trees', { method: 'POST', headers: H, body: JSON.stringify({ base_tree: baseTree, tree }) }).then(r => r.json());
    if (!newTree?.sha) return J({ error: 'tree failed: ' + JSON.stringify(newTree).slice(0, 200) }, 500);
    if (newTree.sha === baseTree) return J({ ok: true, changed: false, note: 'no changes since last sync' });

    const commit = await fetch(api + '/git/commits', { method: 'POST', headers: H, body: JSON.stringify({
      message: 'org-as-code + schema: nightly sync ' + new Date().toISOString().slice(0, 10),
      tree: newTree.sha, parents: [headSha] }) }).then(r => r.json());
    if (!commit?.sha) return J({ error: 'commit failed: ' + JSON.stringify(commit).slice(0, 200) }, 500);
    const upd = await fetch(api + '/git/refs/heads/' + branch, { method: 'PATCH', headers: H, body: JSON.stringify({ sha: commit.sha }) }).then(r => r.json());
    if (!upd?.object?.sha) return J({ error: 'ref update failed: ' + JSON.stringify(upd).slice(0, 200) }, 500);
    return J({ ok: true, changed: true, commit: commit.sha, files: tree.length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
