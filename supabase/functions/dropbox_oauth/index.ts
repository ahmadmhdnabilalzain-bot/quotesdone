// dropbox_oauth — self-service connect page + diagnostics for the QuotesDone Dropbox.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const H = (html: string, s = 200) => new Response(html, { status: s, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
const JS = (o: unknown, s = 200) => new Response(JSON.stringify(o, null, 2), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
const esc = (s: string) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' } as any)[c]);
const SHELL = (inner: string) => `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Connect QuotesDone Dropbox</title><body style="font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:560px;margin:44px auto;padding:0 20px;color:#16181d;line-height:1.5"><div style="height:6px;background:linear-gradient(90deg,#0c2330,#14b8a6);border-radius:6px;margin-bottom:22px"></div>${inner}</body>`;

async function dbxAccessToken(): Promise<string> {
  const rt = await sec('dropbox_refresh_token'); const key = await sec('dropbox_app_key'); const secret = await sec('dropbox_app_secret');
  const p = new URLSearchParams({ grant_type: 'refresh_token', refresh_token: rt, client_id: key, client_secret: secret });
  const r = await fetch('https://api.dropboxapi.com/oauth2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: p });
  const j = await r.json().catch(() => ({})); return j.access_token || '';
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const gate = await sec('dropbox_oauth_key');
    const appKey = await sec('dropbox_app_key');
    const appSecret = await sec('dropbox_app_secret');
    if (!gate) return H(SHELL('<h3>Setup not initialised.</h3>'), 403);

    // ---- diagnostics: which account + scope does the STORED token see? ----
    if (req.method === 'GET' && url.searchParams.get('diag') === gate) {
      const at = await dbxAccessToken();
      if (!at) return JS({ error: 'could_not_refresh_stored_token' }, 400);
      let account: any = {}; try { const r = await fetch('https://api.dropboxapi.com/2/users/get_current_account', { method: 'POST', headers: { 'Authorization': 'Bearer ' + at } }); account = await r.json(); } catch (e) { account = { error: String(e) }; }
      let root: string[] = []; let rootErr: any = null;
      try { const r = await fetch('https://api.dropboxapi.com/2/files/list_folder', { method: 'POST', headers: { 'Authorization': 'Bearer ' + at, 'Content-Type': 'application/json' }, body: JSON.stringify({ path: '', recursive: false, limit: 200 }) }); const j = await r.json(); if (j.entries) root = j.entries.map((e: any) => (e['.tag'] === 'folder' ? '[dir] ' : '') + e.name); else rootErr = j; } catch (e) { rootErr = String(e); }
      let qdBackup: any = 'not_checked';
      try { const r = await fetch('https://api.dropboxapi.com/2/files/get_metadata', { method: 'POST', headers: { 'Authorization': 'Bearer ' + at, 'Content-Type': 'application/json' }, body: JSON.stringify({ path: '/QuotesDone Backup' }) }); const j = await r.json(); qdBackup = j.error ? ('NOT VISIBLE: ' + (j.error_summary || JSON.stringify(j.error))) : ('VISIBLE: ' + j.path_display); } catch (e) { qdBackup = String(e); }
      return JS({ token_account: { account_id: account.account_id, email: account.email, name: account?.name?.display_name, root_info: account.root_info }, root_folders: root, root_error: rootErr, quotesdone_backup: qdBackup });
    }

    if (req.method === 'GET') {
      const k = url.searchParams.get('k') || '';
      if (k !== gate) return H(SHELL('<h2>Not authorized</h2><p>This connect link is invalid or expired.</p>'), 403);
      const authUrl = `https://www.dropbox.com/oauth2/authorize?client_id=${encodeURIComponent(appKey)}&response_type=code&token_access_type=offline&force_reapprove=true`;
      return H(SHELL(`
        <h2>Connect the QuotesDone Dropbox</h2>
        <p>This links the platform (daily document sync + backups) to your Dropbox account.</p>
        <ol style="line-height:2">
          <li><a href="${authUrl}" target="_blank" rel="noopener" style="display:inline-block;padding:11px 20px;background:#0c2330;color:#fff;text-decoration:none;border-radius:8px">Authorize on Dropbox ↗</a></li>
          <li>Approve access. Dropbox will show you a short <b>access code</b> — copy it.</li>
          <li>Paste that code below and press <b>Connect</b>.</li>
        </ol>
        <form method="POST" style="margin-top:18px">
          <input type="hidden" name="k" value="${esc(k)}">
          <input name="code" autocomplete="off" placeholder="Paste the Dropbox access code" style="width:100%;box-sizing:border-box;padding:13px;font-size:15px;border:1px solid #cbd2da;border-radius:8px">
          <button type="submit" style="margin-top:12px;padding:12px 24px;background:#14b8a6;color:#04241f;font-weight:700;border:0;border-radius:8px;font-size:15px;cursor:pointer">Connect</button>
        </form>`));
    }

    if (req.method === 'POST') {
      const form = await req.formData();
      const k = String(form.get('k') || '');
      const code = String(form.get('code') || '').trim();
      if (k !== gate) return H(SHELL('<h2>Not authorized</h2>'), 403);
      if (!code) return H(SHELL('<h2>No code provided</h2><p><a href="?k=' + esc(k) + '">Go back</a></p>'), 400);
      const params = new URLSearchParams({ code, grant_type: 'authorization_code', client_id: appKey, client_secret: appSecret });
      const tr = await fetch('https://api.dropboxapi.com/oauth2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: params });
      const tj = await tr.json().catch(() => ({}));
      if (!tj.refresh_token) return H(SHELL('<h2>Could not connect</h2><p>The code may have expired — <a href="?k=' + esc(k) + '">start again</a>.</p><pre style="white-space:pre-wrap;color:#a00;font-size:12px">' + esc(JSON.stringify(tj)) + '</pre>'), 400);
      let email = ''; let name = '';
      try { const ar = await fetch('https://api.dropboxapi.com/2/users/get_current_account', { method: 'POST', headers: { 'Authorization': 'Bearer ' + tj.access_token } }); const aj = await ar.json(); email = aj?.email || ''; name = aj?.name?.display_name || ''; } catch (_e) { /* ignore */ }
      await admin.from('app_secrets').update({ value: tj.refresh_token }).eq('key', 'dropbox_refresh_token');
      let sync = 'started'; let cron = 'unknown';
      try { await fetch(`${BASE}/dropbox_sync`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret') }) }); } catch (_e) { sync = 'queued'; }
      try { const { data } = await admin.rpc('fn_enable_dropbox_sync'); cron = String(data || 'unknown'); } catch (_e) { /* ignore */ }
      return H(SHELL(`<h2>✓ Dropbox connected</h2><p>Linked to <b>${esc(name || email || 'the authorized account')}</b>${email ? ' (' + esc(email) + ')' : ''}.</p><p>Sync ${sync}; daily sync <b>${esc(cron === 'enabled' ? 'on' : cron)}</b>.</p>`));
    }
    return H(SHELL('<h3>Unsupported</h3>'), 405);
  } catch (e) { return H(SHELL('<h2>Error</h2><pre style="white-space:pre-wrap">' + String((e as Error)?.message || e) + '</pre>'), 500); }
});
