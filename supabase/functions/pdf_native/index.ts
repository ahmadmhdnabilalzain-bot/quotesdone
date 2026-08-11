// pdf_native v14 - serverless PDF (pdf-lib). Premium dark header band (site theme) + clean light body.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { PDFDocument, StandardFonts, rgb } from 'https://esm.sh/pdf-lib@1.17.1';
// The published fontkit.d.ts has no default export (TS1192) even though the CJS module esm.sh
// serves does. Import the namespace and take .default when it is there, so the runtime value is
// exactly what it was before and the types stop lying about it.
import * as fontkitMod from 'https://esm.sh/@pdf-lib/fontkit@1.1.1';
// deno-lint-ignore no-explicit-any
const fontkit = ((fontkitMod as any).default ?? fontkitMod) as any;
import bidiFactory from 'https://esm.sh/bidi-js@1.0.3';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const ASSET = Deno.env.get('SUPABASE_URL')! + '/storage/v1/object/public/brand';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const CO = { name:'QuotesDone Technologies', licence:'DET E-Trader Licence No. 1633275', city:'Dubai, United Arab Emirates', email:'management@quotesdone.com', phone:'+971 50 931 9355', web:'quotesdone.com', signer:'Ahmad Alzain', title:'Founder & Managing Director' };
const CO_AR = { city:'دبي، الإمارات العربية المتحدة', signer:'أحمد الزين', title:'المؤسس والمدير الإداري' };
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any){ if (body?.__secret && (await requireInternal(admin, body.__secret, 'pdf_native')).ok) return true; const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,''); const { data:{ user } } = await admin.auth.getUser(jwt); const allow=(await sec('admin_emails')||'').split(',').map((s)=>s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }
const NAVY=rgb(0.047,0.137,0.188), TEAL=rgb(0.078,0.722,0.651), GOLD=rgb(0.906,0.71,0.235), INK=rgb(0.08,0.094,0.11), MUT=rgb(0.4,0.44,0.52), LINE=rgb(0.9,0.91,0.93), WHITE=rgb(1,1,1), BANDTXT=rgb(0.82,0.87,0.9);
async function fetchBytes(path: string){ try { const r = await fetch(`${ASSET}/${path}`); if(!r.ok) return null; return new Uint8Array(await r.arrayBuffer()); } catch { return null; } }
function isArCode(c:number){ return (c>=0x600&&c<=0x6FF)||(c>=0x750&&c<=0x77F)||(c>=0x8A0&&c<=0x8FF)||(c>=0xFB50&&c<=0xFDFF)||(c>=0xFE70&&c<=0xFEFF); }
function hasAr(s:any){ const t=String(s==null?'':s); for(const ch of t){ if(isArCode(ch.codePointAt(0)||0)) return true; } return false; }
const bidi:any = bidiFactory();
const MIRROR:Record<string,string>={'(' :')',')':'(','[':']',']':'[','{':'}','}':'{','<':'>','>':'<'};
function bidiRuns(s:string){ const str=String(s==null?'':s); if(!str) return [] as {t:string;rtl:boolean}[]; let levels:any; try{ levels = bidi.getEmbeddingLevels(str,'rtl').levels; }catch(_e){ return [{t:str,rtl:true}]; } const segs:{t:string;lv:number}[]=[]; let st=0; for(let i=1;i<=str.length;i++){ if(i===str.length||levels[i]!==levels[st]){ segs.push({t:str.slice(st,i),lv:levels[st]}); st=i; } } if(!segs.length) return [{t:str,rtl:true}]; let maxL=0; for(const sg of segs) if(sg.lv>maxL)maxL=sg.lv; let order=segs.map((_,i)=>i); for(let L2=maxL;L2>=1;L2--){ let i=0; while(i<order.length){ if(segs[order[i]].lv>=L2){ let j=i; while(j<order.length && segs[order[j]].lv>=L2) j++; const sl=order.slice(i,j).reverse(); for(let k=i;k<j;k++) order[k]=sl[k-i]; i=j; } else i++; } } return order.map(i=>{ const rtl=segs[i].lv%2===1; let t=segs[i].t; if(rtl){ let o=''; for(const ch of t) o+=(MIRROR[ch]||ch); t=o; } return { t, rtl }; }); }
function decodeEnt(s:string){ return String(s||'').replace(/<br\s*\/?>/gi,' ').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;|&rsquo;|&lsquo;/g,"'").replace(/&mdash;/g,'—').replace(/&ndash;/g,'–'); }
function stripTags(s:string){ return decodeEnt(String(s||'').replace(/<[^>]+>/g,' ')).replace(/\s+/g,' ').trim(); }
function parseHtml(frag:string){ const blocks:any[]=[]; const re=/<(h2|h3|p|ul|ol|table)\b[^>]*>([\s\S]*?)<\/\1>/gi; let m:any; while((m=re.exec(frag))){ const tag=m[1].toLowerCase(); const inner=m[2]; if(tag==='h2') blocks.push({t:'h2',text:stripTags(inner)}); else if(tag==='h3') blocks.push({t:'h3',text:stripTags(inner)}); else if(tag==='p'){ const tx=stripTags(inner); if(tx) blocks.push({t:'p',text:tx}); } else if(tag==='ul'||tag==='ol'){ const lis=inner.match(/<li\b[^>]*>([\s\S]*?)<\/li>/gi)||[]; lis.forEach((li:string)=>{ const tx=stripTags(li.replace(/<\/?li[^>]*>/gi,'')); if(tx) blocks.push({t:'li',text:tx}); }); } else if(tag==='table'){ const trs=inner.match(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)||[]; let head:string[]=[]; const rows:string[][]=[]; trs.forEach((tr:string,ri:number)=>{ const cells=(tr.match(/<(th|td)\b[^>]*>([\s\S]*?)<\/(?:th|td)>/gi)||[]).map((c:string)=>stripTags(c.replace(/<\/?(th|td)[^>]*>/gi,''))); if(ri===0 && /<th\b/i.test(tr)) head=cells; else rows.push(cells); }); if(!head.length&&rows.length) head=rows.shift() as string[]; if(head.length||rows.length) blocks.push({t:'table',head,rows,widths:head.map(()=>1/Math.max(1,head.length))}); } } return blocks; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    let body = await req.json().catch(()=>({} as any));
    if (!(await authed(req, body))) return J({ error:'forbidden' }, 403);
    const lang = ['en','ar','bi'].includes(String(body.lang)) ? String(body.lang) : 'en';
    let L = lang==='bi' ? 'en' : lang;
    const pdf = await PDFDocument.create(); pdf.registerFontkit(fontkit);
    let font = await pdf.embedFont(StandardFonts.Helvetica);
    let bold = await pdf.embedFont(StandardFonts.HelveticaBold);
    const ital = await pdf.embedFont(StandardFonts.HelveticaOblique);
    let latinFull = false, arFull = false;
    try { const sr = await fetchBytes('qd_sora_regular.ttf'); const sb = await fetchBytes('qd_sora_bold.ttf'); if (sr) { font = await pdf.embedFont(sr, { subset: true }); latinFull = true; } if (sb) bold = await pdf.embedFont(sb, { subset: true }); } catch (_e) { }
    const PW=595.28, PH=841.89, M=48; const CW=PW-2*M; const BAND=92, BANDSLIM=42;
    const opt = body.options||{};
    const letterhead = !!opt.letterhead, doSign = !!opt.sign, doStamp = !!opt.stamp;
    const isQuote = !!body.quote;
    const probe = JSON.stringify(body.quote||'') + JSON.stringify(body.quote_ar||'') + String(body.body_html||'') + JSON.stringify(body.blocks||'') + String(body.title||'');
    const needAr = lang!=='en' || hasAr(probe);
    let arReg=font, arBold=bold;
    if (needAr){ const rb=await fetchBytes('qd_ar_regular.ttf'); const bb=await fetchBytes('qd_ar_bold.ttf'); if(rb){ arReg=await pdf.embedFont(rb,{subset:true}); arFull=true; } if(bb) arBold=await pdf.embedFont(bb,{subset:true}); }

    // 5 Aug 2026. The fonts above are embedded from the brand bucket; when a fetch returns nothing
    // we silently keep StandardFonts.Helvetica, which is WinAnsi-encoded and can represent NOTHING
    // above U+00FF. pdf-lib does not skip such a character, it THROWS - so one glyph fails the
    // entire document. Staging's brand bucket was empty, so every PDF ran on that fallback, and the
    // moment quote_compare started returning real output a single "≠" in the model's prose turned
    // the customer's quotation comparison into a 502. This text is model-written prose about money
    // and specifications: typographic characters are routine here, not exotic. Normalise them to
    // ASCII always (it costs nothing when the real fonts ARE loaded and it reads better), and drop
    // only what the font actually in force cannot encode.
    const NORM: Record<string,string> = { '≠':'!=','≈':'~','≥':'>=','≤':'<=','±':'+/-','—':'-','–':'-','−':'-','‑':'-','→':'->','←':'<-','×':'x','÷':'/','·':'-','•':'-','…':'...','“':'"','”':'"','„':'"','‘':"'",'’':"'",'′':"'",'″':'"','‚':',','€':'EUR','£':'GBP','™':'(TM)','®':'(R)','©':'(C)','½':'1/2','¼':'1/4','¾':'3/4',' ':' ','​':'','‎':'','‏':'','‪':'','‫':'','‬':'' };
    function safeText(s: string): string {
      let out = '';
      for (const ch of String(s == null ? '' : s)) {
        const rep = NORM[ch];
        if (rep !== undefined) { out += rep; continue; }
        const cp = ch.codePointAt(0) || 0;
        if (cp > 0xff) {
          // Arabic needs the Arabic TTF; everything else above Latin-1 needs Sora.
          if (isArCode(cp)) { if (arFull) out += ch; continue; }
          if (latinFull) out += ch;
          continue;
        }
        out += ch;
      }
      return out;
    }
    // deno-lint-ignore no-explicit-any
    function safeDeep(v: any): any {
      if (typeof v === 'string') return safeText(v);
      if (Array.isArray(v)) return v.map(safeDeep);
      // deno-lint-ignore no-explicit-any
      if (v && typeof v === 'object') { const o: any = {}; for (const k of Object.keys(v)) o[k] = safeDeep(v[k]); return o; }
      return v;
    }
    body = safeDeep(body);

    // safeDeep only cleans the CALLER's text. The letterhead, footer and Arabic signer block are
    // our own constants and never pass through it, so on the fallback font they could still throw
    // and lose the whole PDF. Losing one glyph is acceptable; losing the customer's document is not.
    // deno-lint-ignore no-explicit-any
    function armPage(p: any){ const orig = p.drawText.bind(p);
      // deno-lint-ignore no-explicit-any
      p.drawText = (t: any, o: any) => { try { orig(String(t), o); } catch (_e) { try { orig(safeText(String(t)), o); } catch (_e2) { /* skip the glyph, keep the document */ } } };
      return p; }

    const title = String(body.title||'Document');
    const refText = body.ref? String(body.ref):'';
    const dateEn = body.date ? String(body.date) : new Date().toLocaleDateString('en-GB',{day:'2-digit',month:'long',year:'numeric'});
    const dateAr = body.date_ar ? String(body.date_ar) : new Date().toLocaleDateString('ar-AE',{day:'2-digit',month:'long',year:'numeric'});
    function dateFor(){ return L==='ar'?dateAr:dateEn; }
    const logoImg = await (async()=>{ const b=await fetchBytes('qd_lockup_dark.png'); return b?await pdf.embedPng(b):null; })();
    const logoLightImg = await (async()=>{ const b=await fetchBytes('qd_lockup_light.png'); return b?await pdf.embedPng(b):null; })();
    const sig = doSign ? await (async()=>{ const b=await fetchBytes('qd_signature.png'); return b?await pdf.embedPng(b):null; })() : null;
    const stamp = doStamp ? await (async()=>{ const b=await fetchBytes('qd_stamp.png'); return b?await pdf.embedPng(b):null; })() : null;

    let page = armPage(pdf.addPage([PW, PH])); let y = PH - M; let pageNo = 1;
    function fontFor(s:any, b:boolean){ return hasAr(s) ? (b?arBold:arReg) : (b?bold:font); }
    function W(text:string,f:any,s:number){ try{ return f.widthOfTextAtSize(text,s); }catch(_e){ return text.length*s*0.5; } }
    function measRTL(s:string,f:any,size:number){ let w=0; for(const r of bidiRuns(s)) w+=W(r.t,f,size); return w; }
    function drawRTL(s:string,size:number,f:any,color:any,yy:number,xRight:number){ const runs=bidiRuns(s); let tot=0; const ws=runs.map(r=>{const w=W(r.t,f,size);tot+=w;return w;}); let x=xRight-tot; for(let i=0;i<runs.length;i++){ if(runs[i].t.trim()!=='') page.drawText(runs[i].t,{x,y:yy,size,font:f,color}); x+=ws[i]; } }
    function putLine(text:string, size:number, b:boolean, color:any, align:'l'|'r', yy:number, x0=M, w=CW){ const f=fontFor(text,b); if(align==='r' && hasAr(text)){ drawRTL(text,size,f,color,yy,x0+w); return measRTL(text,f,size); } const ww=W(text,f,size); const x = align==='r' ? (x0+w-ww) : x0; page.drawText(text,{x,y:yy,size,font:f,color}); return ww; }
    const footerEn = letterhead ? `${CO.name} · ${CO.licence} · ${CO.city}` : 'QuotesDone · quotesdone.com';
    const footerEn2 = letterhead ? `${CO.email} · ${CO.phone} · ${CO.web}` : '';
    function drawFooter(){ page.drawLine({ start:{x:M,y:54}, end:{x:PW-M,y:54}, thickness:0.5, color:LINE }); page.drawLine({ start:{x:M,y:54}, end:{x:M+34,y:54}, thickness:1.6, color:GOLD }); page.drawText(footerEn, { x:M, y:42, size:7.5, font, color:MUT }); if(footerEn2) page.drawText(footerEn2, { x:M, y:32, size:7.5, font, color:MUT }); page.drawText('Page '+pageNo, { x:PW-M-40, y:42, size:7.5, font, color:MUT }); }
    function headerBand(slim:boolean){ const h = slim?BANDSLIM:BAND; page.drawRectangle({ x:0, y:PH-h, width:PW, height:h, color:NAVY }); page.drawRectangle({ x:0, y:PH-h, width:PW, height:2.6, color:GOLD }); page.drawRectangle({ x:0, y:PH-h+2.6, width:PW, height:1, color:TEAL }); const lg = logoLightImg || logoImg; if (lg){ const w = slim?92:128; const hh=lg.height*(w/lg.width); page.drawImage(lg, { x:M, y:PH-(h/2)-(hh/2)+(slim?0:2), width:w, height:hh }); } if (!slim && letterhead){ const lines=[CO.name, CO.licence, CO.email+' · '+CO.phone]; let ly=PH-26; lines.forEach((ln,i)=>{ const f=i===0?bold:font; const s=i===0?11:8.5; page.drawText(ln,{ x:PW-M-(f.widthOfTextAtSize(ln,s)), y:ly-s, size:s, font:f, color:i===0?WHITE:BANDTXT }); ly-=(i===0?15:11.5); }); } return PH-h; }
    function quoteHeader(){ const by=headerBand(false); y=by-22; if(L==='ar'){ putLine('عرض أسعار', 22, true, NAVY, 'r', y-16, M, CW); if(refText) putLine('الرقم المرجعي: '+refText, 10, false, MUT, 'r', y-32, M, CW); putLine('التاريخ: '+dateFor(), 10, false, MUT, 'r', y-46, M, CW); } else { page.drawText('QUOTATION',{x:M,y:y-16,size:22,font:bold,color:NAVY}); if(refText) page.drawText('Ref: '+refText,{x:M,y:y-32,size:10,font,color:MUT}); page.drawText('Date: '+dateFor(),{x:M,y:y-46,size:10,font,color:MUT}); } y=y-64; drawFooter(); }
    function docHeader(){ const by=headerBand(false); y=by-24; const tAr=hasAr(title); putLine(title, 20, true, NAVY, tAr?'r':'l', y-18); y-=24; const meta = (L==='ar'? CO_AR.city : CO.city)+' · '+dateFor(); putLine(meta, 10, false, MUT, hasAr(meta)?'r':'l', y-10); y-=22; drawFooter(); }
    function newSection(){ page = armPage(pdf.addPage([PW,PH])); pageNo++; y=PH-M; }
    function ensure(h:number){ if (y - h < 70){ page = armPage(pdf.addPage([PW,PH])); pageNo++; const by=headerBand(true); drawFooter(); y=by-18; } }
    function wrap(t:string, f:any, s:number, w:number){ const isAr=hasAr(t); const meas=(str:string)=> isAr?measRTL(str,f,s):W(str,f,s); const words=String(t==null?'':t).split(/\s+/); const lines:string[]=[]; let cur=''; for(const wd0 of words){ const test=cur?cur+' '+wd0:wd0; if(meas(test)>w && cur){ lines.push(cur); cur=wd0; } else cur=test; } if(cur)lines.push(cur); return lines.length?lines:['']; }
    function para(t:string, s=11, b=false, color=INK, lh=1.45, x0=M, w=CW){ const isAr=hasAr(t); const f=fontFor(t,b); for(const ln of wrap(t,f,s,w)){ ensure(s*lh); if(isAr) drawRTL(ln,s,f,color,y-s,x0+w); else page.drawText(ln,{x:x0,y:y-s,size:s,font:f,color}); y-=s*lh; } }
    function bullet(t:string, s=11){ const isAr=hasAr(t); if(isAr){ para(t+' •',s,false,INK,1.4,M,CW-4); } else { para('•  '+t,s,false,INK,1.4,M+10,CW-12); } }
    function headingBi(en:string, ar:string){ ensure(28); y-=8; if(L==='ar'){ putLine(ar||en,11,true,TEAL,'r',y-11); } else { page.drawText(String(en).toUpperCase(),{x:M,y:y-11,size:11,font:bold,color:TEAL}); } y-=13; page.drawLine({start:{x:M,y},end:{x:PW-M,y},thickness:0.6,color:LINE}); page.drawLine({start:{x:M,y},end:{x:M+34,y},thickness:1.6,color:GOLD}); y-=10; }
    function headingAuto(t:string){ const isAr=hasAr(t); ensure(28); y-=8; putLine(t,11,true,TEAL,isAr?'r':'l',y-11); y-=13; page.drawLine({start:{x:M,y},end:{x:PW-M,y},thickness:0.6,color:LINE}); page.drawLine({start:{x:M,y},end:{x:M+34,y},thickness:1.6,color:GOLD}); y-=10; }
    function h3(t:string){ ensure(20); putLine(t,13,true,NAVY,hasAr(t)?'r':'l',y-12); y-=20; }
    function space(h=8){ ensure(h); y-=h; }
    function blockTable(head:string[], rows:string[][], widths:number[], rtl=false){ let H=head.slice(), R=rows.map(r=>r.slice()), Wd=widths.slice(); if(rtl){ H.reverse(); R=R.map(r=>r.slice().reverse()); Wd=Wd.slice().reverse(); } const colW=Wd.map(w=>w*CW); ensure(22); page.drawRectangle({x:M,y:y-20,width:CW,height:20,color:NAVY}); let cx=M; H.forEach((h,i)=>{ const isAr=hasAr(h); const f=isAr?arBold:bold; if(isAr) drawRTL(String(h),9,f,WHITE,y-14,cx+colW[i]-8); else page.drawText(String(h),{x:cx+8,y:y-14,size:9,font:f,color:WHITE}); cx+=colW[i]; }); y-=20; page.drawLine({start:{x:M,y},end:{x:M+CW,y},thickness:1.4,color:GOLD}); R.forEach((r)=>{ const cl=r.map((c,i)=>{ const isAr=hasAr(c); const f=isAr?arReg:font; return { isAr, f, lines: wrap(String(c==null?'':c), f, 10, colW[i]-14) }; }); const rh=Math.max(1,...cl.map(c=>c.lines.length))*13+8; ensure(rh); cx=M; r.forEach((c,i)=>{ const cell=cl[i]; let ly=y-14; for(const ln of cell.lines){ if(cell.isAr) drawRTL(ln,10,cell.f,INK,ly,cx+colW[i]-8); else page.drawText(ln,{x:cx+8,y:ly,size:10,font:cell.f,color:INK}); ly-=13; } cx+=colW[i]; }); y-=rh; page.drawLine({start:{x:M,y},end:{x:PW-M,y},thickness:0.5,color:LINE}); }); y-=2; }
    function blockKV(pairs:[string,string][]){ const colW=CW/2; const rows=Math.ceil(pairs.length/2); for(let r=0;r<rows;r++){ let maxLines=1; for(let c=0;c<2;c++){ const idx=r*2+c; if(idx>=pairs.length)continue; const vv=String(pairs[idx][1]); const vfm=hasAr(vv)?arBold:bold; const n=wrap(vv,vfm,11,colW-12).length; if(n>maxLines) maxLines=n; } const rowH=29+maxLines*13; ensure(rowH); for(let c=0;c<2;c++){ const idx=r*2+c; if(idx>=pairs.length)continue; const x=M+c*colW; const [k,v]=pairs[idx]; const kAr=hasAr(k); putLine(String(k), 8, false, MUT, kAr?'r':'l', y-12, x+4, colW-8); const vAr=hasAr(v); const vf=vAr?arBold:bold; const vlines=wrap(String(v),vf,11,colW-12); let vy=y-26; for(const ln of vlines){ if(vAr) drawRTL(ln,11,vf,NAVY,vy,x+colW-8); else page.drawText(ln,{x:x+4,y:vy,size:11,font:vf,color:NAVY}); vy-=13; } } y-=rowH; } }
    function blockTotal(value:string){ ensure(64); const bw=270, bx=PW-M-bw; const qt = L==='ar'?'القيمة المعروضة':'Quoted total'; const lab = L==='ar'?'الإجمالي':'TOTAL'; page.drawRectangle({x:bx,y:y-58,width:bw,height:58,borderColor:TEAL,borderWidth:2}); page.drawRectangle({x:bx,y:y-4,width:bw,height:4,color:GOLD}); const qf=hasAr(qt)?arReg:font; if(hasAr(qt)) drawRTL(qt,11,qf,INK,y-22,bx+bw-14); else page.drawText(qt,{x:bx+14,y:y-22,size:11,font:qf,color:INK}); page.drawText(value,{x: hasAr(qt)?(bx+14):(bx+bw-14-font.widthOfTextAtSize(value,11)),y:y-22,size:11,font,color:INK}); page.drawRectangle({x:bx,y:y-58,width:bw,height:30,color:NAVY}); const lf=hasAr(lab)?arBold:bold; if(hasAr(lab)) drawRTL(lab,13,lf,WHITE,y-49,bx+bw-14); else page.drawText(lab,{x:bx+14,y:y-49,size:13,font:lf,color:WHITE}); page.drawText(value,{x: hasAr(lab)?(bx+14):(bx+bw-14-bold.widthOfTextAtSize(value,15)),y:y-50,size:15,font:bold,color:WHITE}); y-=66; }
    function blockBadge(en:string, ar:string, subEn:string, subAr:string){ ensure(46); const lab = L==='ar'? ('الجهة مقدّمة العرض'):'QUOTING PARTY'; putLine(lab,8,false,MUT,L==='ar'?'r':'l',y-10); const txt = L==='ar'? ar : en; const tAr=hasAr(txt); const f=tAr?arBold:bold; const bw=(tAr?measRTL(txt,f,12):W(txt,f,12))+24; const bx = L==='ar' ? (PW-M-bw) : M; page.drawRectangle({x:bx,y:y-34,width:bw,height:22,color:NAVY}); if(tAr) drawRTL(txt,12,f,WHITE,y-29,bx+bw-12); else page.drawText(txt,{x:bx+12,y:y-29,size:12,font:f,color:WHITE}); const sub = L==='ar'? subAr : subEn; if(sub){ putLine(sub,9,false,MUT, L==='ar'?'r':'l', y-28, L==='ar'?M:(bx+bw+14), L==='ar'?(PW-2*M-bw-14):(CW-bw-14)); } y-=46; }
    function renderBlocks(blocks:any[]){ for(const b of blocks){ const t=b.t||b.type; if(t==='h2'||t==='heading') headingAuto(b.text||''); else if(t==='h3') h3(b.text||''); else if(t==='p'||t==='para') para(b.text||'', b.size||11, !!b.bold); else if(t==='li') bullet(b.text||''); else if(t==='kv') blockKV(b.pairs||[]); else if(t==='table'){ const rtl = hasAr((b.head||[]).join(' ')+' '+(b.rows||[]).flat().join(' ')); blockTable(b.head||[], b.rows||[], b.widths||(b.head||[]).map(()=>1/Math.max(1,(b.head||[]).length)), rtl); } else if(t==='total') blockTotal(b.value||''); else if(t==='note') para(b.text||'',9,false,MUT); else if(t==='space') space(b.h||10); } }
    const disEn="This quotation is presented in QuotesDone's standardized format from the supplier's submitted quote. Figures and scope are as quoted by the supplier; verify final details before ordering. QuotesDone charges the customer a 3% facilitation fee on the quoted value at the point of contact reveal.";
    const disAr='هذا العرض مقدّم بصيغة QuotesDone الموحّدة استناداً إلى عرض المورّد. القيم والنطاق كما وردت من المورّد؛ يُرجى التحقق من التفاصيل النهائية قبل الطلب. تتقاضى QuotesDone رسوم تيسير بنسبة 3% من قيمة العرض عند كشف بيانات التواصل.';
    function renderQuote(q:any){ const rtlT = L==='ar';
      blockBadge('Supplier '+(q.supplier_label||'1'), 'المورّد رقم '+(q.supplier_label||'1'), 'Identity revealed only after the customer pays the reveal fee.', 'تُكشف هوية المورّد فقط بعد سداد العميل رسوم الكشف.');
      headingBi('Job','بيان العمل'); para((q.job_category? q.job_category+' — ':'')+(q.job_summary||'')+(q.emirate?(' · '+q.emirate):''));
      space(2); headingBi('Scope of supply','نطاق التوريد');
      const items=Array.isArray(q.items)?q.items:[];
      if(items.length){ const head = L==='ar'?['#','الوصف','الكمية','الوحدة'] : ['#','Description','Qty','Unit']; blockTable(head, items.map((it:any,i:number)=>[String(i+1),String(it.desc||''),String(it.qty||''),String(it.unit||'')]), [0.07,0.71,0.11,0.11], rtlT); }
      else if(q.scope) para(String(q.scope));
      if(items.length && q.scope){ space(3); para(String(q.scope),10,false,rgb(0.2,0.25,0.33)); }
      headingBi('Commercial terms','الشروط التجارية');
      const TL=(en:string,ar:string)=> L==='ar'?ar:en;
      blockKV([[TL('Lead time','مدة التنفيذ'),q.lead_time||'—'],[TL('Quote validity','صلاحية العرض'),q.validity||'—'],[TL('Warranty','الضمان'),q.warranty||'—'],[TL('Payment terms','شروط الدفع'),q.payment_terms||'—']]);
      if(q.conditions){ headingBi('Conditions','الشروط'); para(String(q.conditions)); }
      if(q.exclusions){ headingBi('Exclusions','الاستثناءات'); para(String(q.exclusions)); }
      if(q.notes){ headingBi('Notes','ملاحظات'); para(String(q.notes)); }
      space(6); blockTotal('AED '+Number(q.total||0).toLocaleString('en-AE',{minimumFractionDigits:2,maximumFractionDigits:2}));
      space(8); para(L==='ar'?disAr:disEn,9,false,MUT);
    }

    if (isQuote){
      if (lang==='bi'){ const qEn=body.quote; const qAr=body.quote_ar||body.quote; L='en'; quoteHeader(); renderQuote(qEn); newSection(); L='ar'; quoteHeader(); renderQuote(qAr); }
      else { L=lang; quoteHeader(); renderQuote(body.quote); }
    } else {
      L = lang==='bi'?'en':lang; docHeader();
      if (body.body_html) renderBlocks(parseHtml(String(body.body_html)));
      else if (Array.isArray(body.blocks)) renderBlocks(body.blocks);
      if (doSign || doStamp){ ensure(120); y-=20; const baseY=y-58; if (sig){ const w=150, h=sig.height*(w/sig.width); page.drawImage(sig,{x:M+90,y:baseY+4,width:w,height:h}); } const sLabel= lang==='ar'?'الموقّع المعتمد':'AUTHORISED SIGNATORY'; putLine(sLabel,8,false,MUT,'l',baseY+50); page.drawLine({start:{x:M,y:baseY},end:{x:M+230,y:baseY},thickness:0.8,color:rgb(0.2,0.25,0.33)}); const nm= lang==='ar'?CO_AR.signer:CO.signer; const tt= lang==='ar'?CO_AR.title:CO.title; putLine(nm,11,true,NAVY,'l',baseY-14); putLine(tt,9.5,false,MUT,'l',baseY-27); putLine(CO.name,9.5,false,MUT,'l',baseY-39); if (stamp){ const w=110, h=stamp.height*(w/stamp.width); page.drawImage(stamp,{x:PW-M-140,y:baseY-26,width:w,height:h,opacity:0.9,rotate:{type:'degrees',angle:-8} as any}); } y=baseY-50; }
    }

    const bytes = await pdf.save();
    // ...CORS LAST WAS OVERWRITING THE CONTENT TYPE. CORS carries 'Content-Type': 'application/json',
    // so this spread replaced application/pdf on every raw response and the PDF went out labelled
    // JSON. TS2783/TS2785 said exactly that ("this spread always overwrites this property") and the
    // edge-function typecheck is deliberately non-blocking, so nobody saw it. CORS goes first now.
    if (body.raw){ return new Response(bytes as unknown as BodyInit, { status:200, headers:{ ...CORS, 'Content-Type':'application/pdf' } }); }
    const bucket=String(body.bucket||'agent-docs');
    const safe=String(body.name||title||'document').replace(/[^\w.\-]+/g,'_').slice(0,60)||'document';
    const path=(body.folder?String(body.folder).replace(/[^\w\-\/]/g,'')+'/':(new Date().toISOString().slice(0,10)+'/'))+Date.now()+'_'+safe+'.pdf';
    const up=await admin.storage.from(bucket).upload(path, bytes, { contentType:'application/pdf', upsert:true });
    if (up.error) return J({ error:'store_failed', detail: up.error.message }, 500);
    const { data: signed } = await admin.storage.from(bucket).createSignedUrl(path, 7*24*3600);
    return J({ ok:true, bucket, path, url: signed?.signedUrl||null, bytes: bytes.length });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
