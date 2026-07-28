// sync_src_from_github — makes the git repo the single source of truth for the deployed site.
//
// WHY THIS EXISTS. quotesdone.com is built by deploy_next_preview from the qd_deploy_src table, while
// the app is developed in git. The two drifted into different applications: the repo carried a blog,
// MobileNav, lib/seo.ts and newer portals that had never shipped, while the table carried a console
// far ahead of the repo (OsxShell 272KB vs 67KB) plus Content Studio edits written straight to the
// table. Publishing either side over the other destroyed work. After a one-off reconciliation the repo
// now holds the correct union, and this function keeps the table derived FROM the repo instead of
// beside it. Run it after every push; the table stops being a place anyone edits by hand.
//
// NOT A DELETER. It only inserts and updates. Rows in qd_deploy_src that are absent from the repo are
// reported in `extra` and left alone — losing a Content Studio page to a sync would be the exact
// failure this whole exercise was about.
//
// AUTH. This publishes source that becomes the live site, so it takes deploy authority
// (__deploy_secret / app_secrets 'deploy_secret'), not the general inbound secret.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// The deploy set. Everything under these prefixes, plus these exact root files. Anything else in the
// repo (supabase/functions, docs, scripts, graphify-out, node_modules, .next) is not part of the site
// build and must never reach Vercel.
const PREFIXES = ['src/', 'messages/'];
const ROOT_FILES = ['package.json', 'next.config.mjs', 'postcss.config.mjs', 'tailwind.config.ts', 'tsconfig.json', 'next-env.d.ts'];
const EXCLUDE = new Set<string>([]);

function wanted(p: string): boolean {
  if (EXCLUDE.has(p)) return false;
  if (ROOT_FILES.includes(p)) return true;
  return PREFIXES.some((pre) => p.startsWith(pre));
}

// GitHub blobs come back base64 of the RAW BYTES. Decoding with atob alone yields latin-1 and would
// corrupt every Arabic string in messages/ar.json and the content JSONs, so the bytes are rebuilt and
// decoded as UTF-8 explicitly.
function b64utf8(b64: string): string {
  const bin = atob(String(b64).replace(/\s+/g, ''));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder('utf-8').decode(bytes);
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    const body = await req.json().catch(() => ({} as any));
    const dep = await sec('deploy_secret');
    if (!secretOk(dep) || body.__deploy_secret !== dep) return J({ error: 'forbidden' }, 403);

    const token = await sec('github_token'); if (!token) return J({ ok: false, error: 'github_token not configured' }, 200);
    const repo = (await sec('github_repo')) || 'ahmadmhdnabilalzain-bot/quotesdone';
    const branch = (await sec('github_branch')) || 'main';
    const H = { Authorization: 'Bearer ' + token, Accept: 'application/vnd.github+json', 'User-Agent': 'quotesdone-sync' };
    const api = 'https://api.github.com/repos/' + repo;

    const tr = await fetch(api + '/git/trees/' + encodeURIComponent(branch) + '?recursive=1', { headers: H });
    const tj = await tr.json();
    if (!tr.ok) return J({ ok: false, error: 'tree_failed', status: tr.status, detail: String(tj?.message || '').slice(0, 200) }, 200);
    // A truncated tree would silently sync a PARTIAL site, which is worse than not syncing at all.
    if (tj?.truncated) return J({ ok: false, error: 'tree_truncated', note: 'GitHub truncated the recursive tree; sync aborted rather than publish a partial file set' }, 200);

    const blobs = (tj.tree || []).filter((n: any) => n.type === 'blob' && wanted(String(n.path)));
    if (!blobs.length) return J({ ok: false, error: 'no_matching_files', tree_size: (tj.tree || []).length }, 200);

    const { data: existingRows } = await admin.from('qd_deploy_src').select('path,data');
    const existing = new Map<string, string>((existingRows || []).map((r: any) => [r.path as string, r.data as string]));

    const changed: string[] = []; const added: string[] = []; const failed: any[] = []; const shrank: any[] = [];
    let unchanged = 0;

    for (const n of blobs) {
      const path = String(n.path);
      try {
        const br = await fetch(api + '/git/blobs/' + n.sha, { headers: H });
        const bj = await br.json();
        if (!br.ok) { failed.push({ path, status: br.status, detail: String(bj?.message || '').slice(0, 120) }); continue; }
        const text = bj.encoding === 'base64' ? b64utf8(bj.content) : String(bj.content ?? '');
        const prev = existing.get(path);
        if (prev === text) { unchanged++; continue; }
        // SHRINK GUARD. The whole hazard of a repo->table sync is publishing a STALE branch over a
        // file the live side is ahead on. That is not hypothetical: at the time this was written the
        // repo's OsxShell.tsx was 66,920 bytes against the live console's 272,001, so one sync from an
        // unpushed branch would have destroyed the console. A file collapsing to under half its
        // current size is the signature of that mistake, never of a normal edit, so it is refused and
        // reported rather than written. Pass allow_shrink:true to override deliberately.
        if (prev !== undefined && prev.length > 2000 && text.length < prev.length * 0.5 && !body.allow_shrink) {
          shrank.push({ path, from: prev.length, to: text.length });
          continue;
        }
        if (!body.dry_run) {
          if (prev === undefined) {
            const { error } = await admin.from('qd_deploy_src').insert({ path, data: text });
            if (error) { failed.push({ path, detail: error.message }); continue; }
          } else {
            const { error } = await admin.from('qd_deploy_src').update({ data: text }).eq('path', path);
            if (error) { failed.push({ path, detail: error.message }); continue; }
          }
        }
        (prev === undefined ? added : changed).push(path);
      } catch (e) { failed.push({ path, detail: String((e as Error)?.message || e).slice(0, 120) }); }
    }

    const repoPaths = new Set(blobs.map((n: any) => String(n.path)));
    const extra = [...existing.keys()].filter((p) => !repoPaths.has(p));

    const counts = { matched: blobs.length, added: added.length, changed: changed.length, unchanged, failed: failed.length, refused_shrink: shrank.length, extra: extra.length, dry_run: !!body.dry_run };
    try {
      await admin.from('agent_runs').insert({ agent: 'sync_src_from_github', status: (failed.length || shrank.length) ? 'error' : 'ok', counts,
        note: (shrank.length ? 'REFUSED to shrink ' + shrank.length + ' file(s) by more than half - this is the signature of syncing a stale branch over a file the live side is ahead on, so those files were left untouched and the rest of the sync completed: ' + shrank.map((x: any) => x.path + ' ' + x.from + '->' + x.to).join('; ') + '. ' : '') +
              (failed.length ? 'Some files failed to sync, so qd_deploy_src is a PARTIAL mix of repo and previous state — do not publish until this is resolved. ' : '') +
              (extra.length ? 'Rows present in qd_deploy_src but absent from the repo were left untouched: ' + extra.join(', ') : ''),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never block the sync on a log write */ }

    return J({ ok: failed.length === 0 && shrank.length === 0, ...counts, added, changed, shrank, extra, failed, branch, repo }, 200);
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 500); }
});
