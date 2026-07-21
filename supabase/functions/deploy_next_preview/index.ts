import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
async function sha1hex(bytes: Uint8Array){ const h = await crypto.subtle.digest('SHA-1', bytes); return [...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,'0')).join(''); }
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const token = await sec('vercel_token'); const team = await sec('vercel_team_id');
    if (!token || !team) return J({ ok:false, error:'vercel_not_configured' }, 200);
    const H = { Authorization: 'Bearer ' + token };
    const target = (body.target === 'preview') ? 'preview' : 'production';
    const project = 'quotesdone-next';
    // 1) turn off deployment protection so the site is publicly viewable
    try { await fetch('https://api.vercel.com/v9/projects/' + project + '?teamId=' + team, { method:'PATCH', headers:{ ...H, 'Content-Type':'application/json' }, body: JSON.stringify({ ssoProtection: null, passwordProtection: null }) }); } catch(_e){}
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
    // 3) create the deployment (production by default)
    const dep = await fetch('https://api.vercel.com/v13/deployments?teamId=' + team + '&forceNew=1', { method:'POST', headers:{ ...H, 'Content-Type':'application/json' }, body: JSON.stringify({ name: project, files, target, projectSettings:{ framework:'nextjs' } }) });
    const dj = await dep.json();
    if (!dep.ok) return J({ ok:false, error:'deploy_failed', status:dep.status, detail: JSON.stringify(dj?.error||dj).slice(0,500) }, 200);
    return J({ ok:true, id: dj.id, url: dj.url, target, readyState: dj.readyState, files: files.length, alias: (dj.alias||[]) }, 200);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});