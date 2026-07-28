// push_src_to_github — publishes named files from qd_deploy_src to the GitHub branch Vercel builds.
//
// WHY THIS EXISTS. quotesdone.com is NOT deployed from qd_deploy_src alone. The Vercel project is
// git-linked to ahmadmhdnabilalzain-bot/quotesdone@main, so every push to main triggers a production
// deployment. github_sync runs nightly and commits org-as-code + schema to main, which means every
// night at 04:10 Vercel rebuilds the site FROM GITHUB and silently discards anything published through
// deploy_next_preview / the OS console. That is not theoretical: an XSS fix deployed to production on
// 27 Jul 2026 was reverted by the 28 Jul nightly sync, because GitHub's src/ was still the old code.
// This function closes the loop by pushing the table's contents back into git, so a publish survives.
//
// DELIBERATELY NOT A BULK SYNC. `paths` is required. The repo and the table have genuinely diverged in
// both directions (the repo carries blog/SEO work never published; the table carried a console far
// ahead of the repo), so a blanket push would destroy whichever side happened to be behind. Name the
// files you mean.
//
// AUTH: deploy authority (__deploy_secret), because anything this writes becomes the live site.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// base64 of the UTF-8 BYTES. btoa() alone throws on any character above U+00FF, which every Arabic
// string in messages/ar.json and the content JSONs would hit.
function b64(s: string): string {
  const bytes = new TextEncoder().encode(s);
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    const body = await req.json().catch(() => ({} as any));
    const dep = await sec('deploy_secret');
    if (!secretOk(dep) || body.__deploy_secret !== dep) return J({ error: 'forbidden' }, 403);

    const paths: string[] = Array.isArray(body.paths) ? body.paths.filter((p: unknown) => typeof p === 'string' && p) : [];
    if (!paths.length) return J({ ok: false, error: 'paths_required', note: 'Name the files to publish. A blanket push would overwrite whichever of repo/table is behind on a given file, and they have diverged in both directions.' }, 200);

    const token = await sec('github_token'); if (!token) return J({ ok: false, error: 'github_token not configured' }, 200);
    const repo = (await sec('github_repo')) || 'ahmadmhdnabilalzain-bot/quotesdone';
    const branch = (await sec('github_branch')) || 'main';
    const api = 'https://api.github.com/repos/' + repo;
    const H = { Authorization: 'Bearer ' + token, Accept: 'application/vnd.github+json', 'User-Agent': 'quotesdone-push', 'Content-Type': 'application/json' };

    const { data: rows } = await admin.from('qd_deploy_src').select('path,data').in('path', paths);
    const found = new Map<string, string>((rows || []).map((r: any) => [r.path as string, r.data as string]));
    const missing = paths.filter((p) => !found.has(p));
    if (missing.length) return J({ ok: false, error: 'paths_not_in_qd_deploy_src', missing }, 200);

    // 1) current head
    const refR = await fetch(api + '/git/ref/heads/' + encodeURIComponent(branch), { headers: H });
    const refJ = await refR.json();
    if (!refR.ok) return J({ ok: false, error: 'ref_failed', detail: String(refJ?.message || '').slice(0, 200) }, 200);
    const headSha = refJ?.object?.sha as string;

    const comR = await fetch(api + '/git/commits/' + headSha, { headers: H });
    const comJ = await comR.json();
    if (!comR.ok) return J({ ok: false, error: 'commit_read_failed', detail: String(comJ?.message || '').slice(0, 200) }, 200);
    const baseTree = comJ?.tree?.sha as string;

    // 2) one blob per file
    const tree: any[] = [];
    for (const p of paths) {
      const br = await fetch(api + '/git/blobs', { method: 'POST', headers: H, body: JSON.stringify({ content: b64(found.get(p)!), encoding: 'base64' }) });
      const bj = await br.json();
      if (!br.ok) return J({ ok: false, error: 'blob_failed', path: p, detail: String(bj?.message || '').slice(0, 200) }, 200);
      tree.push({ path: p, mode: '100644', type: 'blob', sha: bj.sha });
    }

    // 3) tree on top of the current one, so nothing else in the repo is touched
    const trR = await fetch(api + '/git/trees', { method: 'POST', headers: H, body: JSON.stringify({ base_tree: baseTree, tree }) });
    const trJ = await trR.json();
    if (!trR.ok) return J({ ok: false, error: 'tree_failed', detail: String(trJ?.message || '').slice(0, 200) }, 200);

    // Identical tree means the files already match the branch - do not create an empty commit, because
    // every commit to main triggers a Vercel production rebuild.
    if (trJ.sha === baseTree) return J({ ok: true, unchanged: true, note: 'files already identical on ' + branch + '; no commit created and no deploy triggered', paths }, 200);

    const cmR = await fetch(api + '/git/commits', { method: 'POST', headers: H, body: JSON.stringify({
      message: String(body.message || 'publish from qd_deploy_src').slice(0, 200), tree: trJ.sha, parents: [headSha] }) });
    const cmJ = await cmR.json();
    if (!cmR.ok) return J({ ok: false, error: 'commit_failed', detail: String(cmJ?.message || '').slice(0, 200) }, 200);

    const upR = await fetch(api + '/git/refs/heads/' + encodeURIComponent(branch), { method: 'PATCH', headers: H, body: JSON.stringify({ sha: cmJ.sha }) });
    const upJ = await upR.json();
    if (!upR.ok) return J({ ok: false, error: 'ref_update_failed', detail: String(upJ?.message || '').slice(0, 200) }, 200);

    const counts = { files: paths.length, commit: String(cmJ.sha || '').slice(0, 12), branch };
    try {
      await admin.from('agent_runs').insert({ agent: 'push_src_to_github', status: 'ok', counts,
        note: 'Published ' + paths.join(', ') + ' to ' + repo + '@' + branch + '. Vercel is git-linked to this branch, so this commit triggers a production deployment.',
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never block the publish on a log write */ }

    return J({ ok: true, ...counts, paths, note: 'Vercel builds this branch, so a production deploy is now in progress.' }, 200);
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 500); }
});
