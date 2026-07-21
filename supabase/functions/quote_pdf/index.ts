// quote_pdf - renders a branded QuotesDone-format quotation (HTML, print-to-PDF) for one quote.
// Admin-only: Authorization Bearer (email must be in admin_emails) OR { __secret }. Returns text/html.
// The supplier is shown anonymized as 'Supplier N' (our standard quotation format); a small admin band
// shows the real supplier identity for internal monitoring only.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const URL_ = Deno.env.get('SUPABASE_URL')!;
const ASSET = URL_ + '/storage/v1/object/public/brand';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function esc(s: unknown){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function money(n: unknown){ const v=Number(n); return isFinite(v)&&v>0 ? 'AED '+v.toLocaleString('en-AE',{minimumFractionDigits:2,maximumFractionDigits:2}) : '—'; }
function fmtDate(d: unknown){ try { return new Date(String(d)).toLocaleDateString('en-GB',{day:'2-digit',month:'short',year:'numeric'}); } catch { return ''; } }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    // auth: admin JWT or shared secret
    let authed = false;
    if (body.__secret && body.__secret === (await sec('inbound_secret'))) authed = true;
    if (!authed) {
      const jwt = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
      const { data: { user } } = await admin.auth.getUser(jwt);
      const allow = (await sec('admin_emails')||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean);
      if (user?.email && allow.includes(user.email.toLowerCase())) authed = true;
    }
    if (!authed) return new Response('Forbidden', { status: 403, headers: CORS });

    const quote_id = String(body.quote_id||'');
    const { data: q } = await admin.from('quotes').select('*').eq('id', quote_id).maybeSingle();
    if (!q) return new Response('Quote not found', { status: 404, headers: CORS });
    const { data: inq } = await admin.from('inquiries').select('id,summary,category,emirate,budget,raw_input,spec,scope_type,created_at,boq').eq('id', q.inquiry_id).maybeSingle();
    const { data: sup } = await admin.from('leads').select('id,company_name,emirate,phone,email').eq('id', q.supplier_id).maybeSingle();
    // Facilitation (reveal) fee % sourced live from pricing_config — single source of truth (OPEN_ISSUES #4).
    const { data: pc } = await admin.from('pricing_config').select('standard_reveal_rate').eq('id', 1).maybeSingle();
    const feePct = Math.round((Number((pc as any)?.standard_reveal_rate ?? 0.03)) * 100);
    // Supplier N = position of this quote among the inquiry's quotes (by created_at asc)
    const { data: sibs } = await admin.from('quotes').select('id,created_at').eq('inquiry_id', q.inquiry_id).order('created_at',{ascending:true});
    const idx = (sibs||[]).findIndex(s=>s.id===q.id); const supN = idx>=0 ? idx+1 : 1;
    const ref = 'QD-' + String(q.inquiry_id||'').slice(0,8).toUpperCase() + '-S' + supN;

    // Line items: prefer structured boq/line_items on the quote, else the inquiry BOQ, else the scope text.
    let items: { desc: string; qty: string; unit: string }[] = [];
    const qbo = (q as any).boq || (q as any).line_items;
    if (Array.isArray(qbo)) items = qbo.map((b:any)=>({ desc:String(b.description||b.desc||''), qty: b.qty==null?'':String(b.qty), unit:String(b.unit||'') })).filter(x=>x.desc);
    if (!items.length && inq?.boq && Array.isArray((inq.boq as any).boq)) items = (inq.boq as any).boq.map((b:any)=>({ desc:String(b.description||''), qty:b.qty==null?'':String(b.qty), unit:String(b.unit||'') })).filter((x:any)=>x.desc).slice(0,40);
    const itemRows = items.length ? items.map((it,i)=>`<tr><td class=c>${i+1}</td><td>${esc(it.desc)}</td><td class=c>${esc(it.qty)}</td><td class=c>${esc(it.unit)}</td></tr>`).join('') : `<tr><td class=c>1</td><td>${esc(q.scope||inq?.summary||'As per scope below')}</td><td class=c></td><td class=c></td></tr>`;

    const cond = String(q.conditions||''); const excl = String(q.exclusions||''); const notes = String(q.notes||''); const scope = String(q.scope||'');
    const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(ref)} — QuotesDone Quotation</title>
<style>
:root{--teal:#14B8A6;--gold:#E3C065;--navy:#0C2330;--ink:#0A0A0A;--mut:#667085;--line:#E5E7EB}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:var(--ink);background:#f1f5f9}
.sheet{max-width:820px;margin:18px auto;background:#fff;padding:40px 44px;box-shadow:0 6px 30px rgba(0,0,0,.08);border-radius:6px}
.top{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:3px solid var(--teal);padding-bottom:16px}
.top img{height:40px}.qt{text-align:right}.qt h1{margin:0;font-size:26px;letter-spacing:3px;color:var(--navy)}.qt .ref{color:var(--mut);font-size:13px;margin-top:4px}
.meta{display:flex;justify-content:space-between;gap:24px;margin:22px 0 6px}
.meta .box{flex:1}.meta .lbl{font-size:11px;letter-spacing:1px;text-transform:uppercase;color:var(--mut);margin-bottom:3px}
.meta .val{font-size:14px;font-weight:600;color:var(--navy)}.meta .sub{font-size:12px;color:#475467}
.supbadge{display:inline-block;background:var(--navy);color:#fff;font-weight:700;font-size:13px;padding:4px 12px;border-radius:5px;letter-spacing:.5px}
h2.sec{font-size:12px;letter-spacing:1.5px;text-transform:uppercase;color:var(--teal);margin:24px 0 8px;border-bottom:1px solid var(--line);padding-bottom:5px}
table.items{width:100%;border-collapse:collapse;font-size:13px}table.items th{background:var(--navy);color:#fff;text-align:left;padding:8px 10px;font-size:11px;letter-spacing:.5px}
table.items td{padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}table.items td.c{text-align:center;width:50px;color:var(--mut)}
.scopebox{font-size:13px;line-height:1.55;color:#344054;white-space:pre-wrap}
.commer{display:grid;grid-template-columns:1fr 1fr;gap:0;border:1px solid var(--line);border-radius:6px;overflow:hidden;margin-top:6px}
.commer .cell{padding:10px 12px;border-bottom:1px solid var(--line)}.commer .cell:nth-child(odd){border-right:1px solid var(--line);background:#fafafa}
.commer .k{font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:var(--mut)}.commer .v{font-size:14px;font-weight:600;color:var(--navy);margin-top:2px}
.total{margin-top:18px;display:flex;justify-content:flex-end}.total .tbox{min-width:280px;border:2px solid var(--teal);border-radius:8px;overflow:hidden}
.total .row{display:flex;justify-content:space-between;padding:10px 16px;font-size:14px}.total .grand{background:var(--navy);color:#fff;font-weight:700;font-size:18px}
.small{font-size:11.5px;color:var(--mut);line-height:1.5}
.foot{margin-top:30px;border-top:1px solid var(--line);padding-top:14px;display:flex;justify-content:space-between;align-items:center}
.foot .brand{font-weight:700;color:var(--navy)}.foot .brand span{color:var(--teal)}
.adminband{margin:0 auto 0;max-width:820px;background:#fff7ed;border:1px solid #fed7aa;color:#9a3412;font-size:12px;padding:8px 14px;border-radius:6px;max-width:820px}
.bar{position:sticky;top:0;background:var(--navy);color:#fff;padding:10px 16px;display:flex;justify-content:space-between;align-items:center;font-size:13px}
.bar button{background:var(--teal);color:#04201c;border:0;font-weight:700;padding:8px 16px;border-radius:6px;cursor:pointer;font-size:13px}
@media print{.bar,.adminband{display:none}body{background:#fff}.sheet{box-shadow:none;margin:0;max-width:none;border-radius:0;padding:24px 28px}}
</style></head><body>
<div class="bar"><div>QuotesDone — internal quotation view · ${esc(ref)}</div><button onclick="window.print()">⤓ Save as PDF / Print</button></div>
<div class="adminband"><b>Admin only:</b> Actual supplier — ${esc(sup?.company_name||('Lead #'+q.supplier_id))} (lead #${esc(q.supplier_id)})${sup?.emirate?(' · '+esc(sup.emirate)):''} · quote id ${esc(q.id)}. This identity is never shown to the customer; the customer sees only "Supplier ${supN}".</div>
<div class="sheet">
  <div class="top"><img src="${ASSET}/qd_lockup_dark.png" alt="QuotesDone"/><div class="qt"><h1>QUOTATION</h1><div class="ref">Ref: ${esc(ref)}</div><div class="ref">Date: ${fmtDate(q.created_at||new Date().toISOString())}</div></div></div>
  <div class="meta">
    <div class="box"><div class="lbl">Quoting party</div><div class="val"><span class="supbadge">Supplier ${supN}</span></div><div class="sub" style="margin-top:6px">Identity revealed after the customer accepts &amp; pays the reveal fee.</div></div>
    <div class="box"><div class="lbl">Job</div><div class="val">${esc(inq?.category||'—')}</div><div class="sub">${esc(inq?.summary||'')}${inq?.emirate?(' · '+esc(inq.emirate)):''}</div></div>
  </div>
  <h2 class="sec">Scope of supply</h2>
  <table class="items"><tr><th>#</th><th>Description</th><th style="width:70px">Qty</th><th style="width:70px">Unit</th></tr>${itemRows}</table>
  ${scope && items.length ? `<div class="scopebox" style="margin-top:10px">${esc(scope)}</div>`:''}
  <h2 class="sec">Commercial terms</h2>
  <div class="commer">
    <div class="cell"><div class="k">Lead time</div><div class="v">${esc(q.lead_time||'—')}</div></div>
    <div class="cell"><div class="k">Quote validity</div><div class="v">${esc(q.validity||'—')}</div></div>
    <div class="cell"><div class="k">Warranty</div><div class="v">${esc(q.warranty||'—')}</div></div>
    <div class="cell"><div class="k">Payment terms</div><div class="v">${esc(q.payment_terms||'—')}</div></div>
  </div>
  ${cond?`<h2 class="sec">Conditions</h2><div class="scopebox">${esc(cond)}</div>`:''}
  ${excl?`<h2 class="sec">Exclusions</h2><div class="scopebox">${esc(excl)}</div>`:''}
  ${notes?`<h2 class="sec">Notes</h2><div class="scopebox">${esc(notes)}</div>`:''}
  <div class="total"><div class="tbox"><div class="row"><span>Quoted total</span><span>${money(q.quote_amount)}</span></div><div class="row grand"><span>Total (incl. supplier pricing)</span><span>${money(q.quote_amount)}</span></div></div></div>
  <div class="small" style="margin-top:10px">This quotation is presented in QuotesDone's standardized format from the supplier's submitted quote. Figures and scope are as quoted by the supplier; verify final details before ordering. QuotesDone charges the customer a ${feePct}% facilitation fee on the quoted value at the point of contact reveal.</div>
  <div class="foot"><div class="brand">Quotes<span>Done</span></div><div class="small">Generated ${fmtDate(new Date().toISOString())} · quotesdone.com</div></div>
</div>
</body></html>`;
    return new Response(html, { status: 200, headers: { 'Content-Type': 'text/html; charset=utf-8', ...CORS } });
  } catch (e) { return new Response('Error: '+String((e as Error)?.message||e), { status: 500, headers: CORS }); }
});
