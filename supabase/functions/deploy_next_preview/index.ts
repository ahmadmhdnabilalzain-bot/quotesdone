import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
async function sha1hex(bytes: Uint8Array){ const h = await crypto.subtle.digest('SHA-1', bytes); return [...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,'0')).join(''); }
// SECURITY FIX 27 Jul 2026 -----------------------------------------------------------------------
// WHAT WAS WRONG: this function publishes whatever currently sits in qd_deploy_src to Vercel, and it
// was gated on inbound_secret - the single shared secret that 134 of the 187 edge functions accept.
// Paired with put_src (which writes any path/content into that table on the same secret), one leaked
// inbound_secret was a full takeover of quotesdone.com, not an API key with some reach.
// WHY THIS FIX: deploy authority now needs its OWN key - app_secrets key 'deploy_secret', sent as
// body.__deploy_secret. Until that row exists we still honour inbound_secret so os_pages 'publish'
// does not break before the founder creates it, but every fallback authorisation is written to
// agent_runs with status 'error' so the gap is loud, not silent. Drop the fallback once it is set.
async function deployAuth(b: any, fn: string){
  const dep = await sec('deploy_secret');
  if (dep) return b.__deploy_secret === dep;
  // FALLBACK DROPPED 3 Aug 2026 (audit 9.5). app_secrets.deploy_secret exists, so the line above
  // has returned for every real call since 27 Jul and this fallback has been dead code that merely
  // kept deploy authority coupled to the omnipotent shared secret. Deploy authority is now
  // deploy_secret and nothing else; a caller presenting the shared secret is refused.
  const ok: boolean = false;
  if (ok) { const t = new Date().toISOString(); try { await admin.from('agent_runs').insert({ agent:'deploy_authority', started_at:t, finished_at:t, status:'error', counts:{ fallback_auth:1, fn }, note:'DEPLOY SECRET NOT SET YET: '+fn+' authorised a deploy-capable call using inbound_secret because app_secrets has no deploy_secret row. inbound_secret is accepted by 134 of 187 functions, so until deploy_secret exists anything holding it can publish arbitrary source to quotesdone.com. Create app_secrets key deploy_secret and have callers send __deploy_secret.' }); } catch(_e){ /* never block the deploy path on a log write */ } }
  return ok;
}
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (!(await deployAuth(body, 'deploy_next_preview'))) return J({ error: 'forbidden' }, 403);
    const token = await sec('vercel_token'); const team = await sec('vercel_team_id');
    if (!token || !team) return J({ ok:false, error:'vercel_not_configured' }, 200);
    const H = { Authorization: 'Bearer ' + token };
    // FIX 27 Jul 2026: WHAT WAS WRONG - this read `(body.target === 'preview') ? 'preview' : 'production'`,
    // so a caller that simply omitted `target` got a PRODUCTION deploy out of a function called
    // deploy_next_preview. Every wrong guess landed on the live site. Now inverted: preview is the
    // default and production must be asked for by name. os_pages 'publish' and any deliberate release
    // already send target:'production' explicitly, so nothing that meant production loses production.
    const target = (body.target === 'production') ? 'production' : 'preview';
    const project = 'quotesdone-next';
    // 1) turn off deployment protection so the LIVE site is publicly viewable.
    // FIX 27 Jul 2026: WHAT WAS WRONG - this PATCH ran on every single call, so any deploy, including a
    // throwaway preview, stripped ssoProtection and passwordProtection off the whole Vercel project and
    // left them off. Project-wide protection is not a preview's business: only a production publish
    // needs the public site reachable, and previews must never widen access as a side effect.
    if (target === 'production') { try { await fetch('https://api.vercel.com/v9/projects/' + project + '?teamId=' + team, { method:'PATCH', headers:{ ...H, 'Content-Type':'application/json' }, body: JSON.stringify({ ssoProtection: null, passwordProtection: null }) }); } catch(_e){} }
    // 2) upload source files
    const { data: rows } = await admin.from('qd_deploy_src').select('path,data');
    if (!rows || !rows.length) return J({ ok:false, error:'no_source_files' }, 200);
    const files: { file: string; sha: string; size: number }[] = [];
    for (const r of rows) {
      const bytes = new TextEncoder().encode(r.data as string);
      const sha = await sha1hex(bytes);
      const up = await fetch('https://api.vercel.com/v2/files?teamId=' + team, { method:'POST', headers:{ ...H, 'Content-Type':'application/octet-stream', 'x-vercel-digest':sha }, body: bytes });
      if (!up.ok) return J({ ok:false, error:'upload_failed', path:r.path, status:up.status, detail:(await up.text()).slice(0,200) }, 200);
      files.push({ file: r.path as string, sha, size: bytes.length });
    }
    // 3) create the deployment (preview by default since 27 Jul 2026; production needs target:'production')
    // FIX 27 Jul 2026: WHAT WAS WRONG - the previous change made 'preview' the default and then sent it
    // verbatim as the API's `target`. Vercel's v13 deployments endpoint does not accept 'preview' there:
    // it answers 400 `target should be 'production', 'staging', or a custom environment identifier`.
    // A preview is expressed by OMITTING target entirely. So every call that did not ask for production
    // - i.e. the whole default path of a function named deploy_next_preview - was a hard 400 that
    // uploaded all 70 source files first and then threw the deployment away. Target is now only sent
    // when it is 'production'; the local `target` variable still gates the protection PATCH above and
    // is still reported back to the caller, so nothing else changes.
    const depBody: Record<string, unknown> = { name: project, files, projectSettings:{ framework:'nextjs' } };
    if (target === 'production') depBody.target = 'production';
    const dep = await fetch('https://api.vercel.com/v13/deployments?teamId=' + team + '&forceNew=1', { method:'POST', headers:{ ...H, 'Content-Type':'application/json' }, body: JSON.stringify(depBody) });
    const dj = await dep.json();
    if (!dep.ok) return J({ ok:false, error:'deploy_failed', status:dep.status, detail: JSON.stringify(dj?.error||dj).slice(0,500) }, 200);
    return J({ ok:true, id: dj.id, url: dj.url, target, readyState: dj.readyState, files: files.length, alias: (dj.alias||[]) }, 200);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});