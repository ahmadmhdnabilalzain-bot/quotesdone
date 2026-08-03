// make_xlsx - reusable native .xlsx generator (SheetJS). Input rows or multi-sheet; stores xlsx, returns signed URL. Admin/secret only.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import * as XLSX from 'https://esm.sh/xlsx@0.18.5';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any){ if (body?.__secret && (await requireInternal(admin, body.__secret, 'make_xlsx')).ok) return true; const jwt = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,''); const { data:{ user } } = await admin.auth.getUser(jwt); const allow = (await sec('admin_emails')||'').split(',').map((s)=>s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    if (!(await authed(req, body))) return J({ error:'forbidden' }, 403);
    let sheets = Array.isArray(body.sheets) ? body.sheets : null;
    if (!sheets && Array.isArray(body.rows)) sheets = [{ name: body.sheet_name || 'Sheet1', rows: body.rows }];
    if (!sheets || !sheets.length) return J({ error:'sheets_or_rows_required' }, 400);
    const wb = XLSX.utils.book_new();
    for (let i=0;i<sheets.length;i++){ const sh = sheets[i]; const rows = Array.isArray(sh?.rows) ? sh.rows : []; const ws = XLSX.utils.aoa_to_sheet(rows); const widths: any[] = []; for (const r of rows) { (r||[]).forEach((c:any,ci:number)=>{ const len = String(c==null?'':c).length; widths[ci] = Math.min(60, Math.max(widths[ci]||10, len+2)); }); } ws['!cols'] = widths.map((w)=>({ wch: w })); const nm = String(sh?.name||('Sheet'+(i+1))).replace(/[\\\/?*\[\]:]/g,'').slice(0,31) || ('Sheet'+(i+1)); XLSX.utils.book_append_sheet(wb, ws, nm); }
    const out = XLSX.write(wb, { type:'array', bookType:'xlsx' });
    const bytes = new Uint8Array(out);
    const bucket = String(body.bucket||'agent-docs');
    const safe = String(body.name||'workbook').replace(/[^\w.\-]+/g,'_').slice(0,50) || 'workbook';
    const path = (body.folder? String(body.folder).replace(/[^\w\-\/]/g,'')+'/' : (new Date().toISOString().slice(0,10)+'/')) + Date.now() + '_' + safe + '.xlsx';
    const up = await admin.storage.from(bucket).upload(path, bytes, { contentType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', upsert:true });
    if (up.error) return J({ error:'store_failed', detail: up.error.message }, 500);
    const { data: signed } = await admin.storage.from(bucket).createSignedUrl(path, 7*24*3600);
    return J({ ok:true, bucket, path, url: signed?.signedUrl||null, bytes: bytes.length, sheets: sheets.length });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
