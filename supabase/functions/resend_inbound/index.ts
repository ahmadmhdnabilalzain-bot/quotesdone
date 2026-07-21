// resend_inbound v14 - inbound emails. Webhook metadata-only; body via GET /emails/inbound/{id}; attachments via
// /attachments/{id} -> download_url. Receipts -> finance. Supplier docs -> store + AI classify + AUTO-EXTRACT
// (trade licence -> licence no/authority/emirate/expiry/TRN; profile/catalogue -> capability) applied to the matched lead.
// v12: agent_runs instrumentation for silently-lost inbound documents.
// v13: Svix signature verification (see PROVENANCE below).
// v14: DUPLICATE-EXPENSE FIX (see DEDUP below).
//
// v13 SECURITY FIX 19 Jul 2026 -----------------------------------------------------------------
// v12 authenticated ONLY on a shared token in the QUERY STRING (?s=...). The full URL including
// that token is stored in the Resend dashboard, lands in browser history and referrer headers, and
// is written to any proxy or access log that records request lines. Anyone holding it could forge
// inbound email events and, because this function BOOKS EXPENSES and WRITES SUPPLIER RECORDS,
// could inject fabricated expense_entries rows, overwrite a supplier's trade licence number, TRN
// and capability summary, and upload arbitrary files into the supplier-docs bucket.
// v13 verifies the SVIX SIGNATURE Resend signs each delivery with (svix-id, svix-timestamp,
// svix-signature) against app_secrets.resend_inbound_signing_secret. The ?s= token is KEPT as a
// second factor - both must now pass. The body is read ONCE as raw text because the signature is
// over the exact bytes; it is parsed only after verification succeeds.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const MODEL = 'anthropic/claude-sonnet-5';
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }

// Observability -------------------------------------------------------------
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'resend_inbound', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging drop an inbound email */ }
}

// Webhook authenticity ------------------------------------------------------
function timingSafeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
// Svix/Standard-Webhooks: base64(HMAC-SHA256(secret, "<id>.<timestamp>.<rawBody>")).
async function verifySvix(secret: string, rawBody: string, h: Headers): Promise<{ ok: boolean; reason: string }> {
  const id = h.get('svix-id') || h.get('webhook-id');
  const ts = h.get('svix-timestamp') || h.get('webhook-timestamp');
  const sigHeader = h.get('svix-signature') || h.get('webhook-signature');
  if (!id || !ts || !sigHeader) return { ok: false, reason: 'missing svix-id / svix-timestamp / svix-signature headers - not a genuine Resend delivery' };
  const skew = Math.abs(Date.now() / 1000 - Number(ts));
  if (!Number.isFinite(skew)) return { ok: false, reason: 'unparseable svix-timestamp' };
  if (skew > 300) return { ok: false, reason: 'timestamp is ' + Math.round(skew) + 's from now, outside the 5 minute replay window' };
  try {
    const b64 = secret.startsWith('whsec_') ? secret.slice(6) : secret;
    const keyBytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const ck = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const mac = new Uint8Array(await crypto.subtle.sign('HMAC', ck, new TextEncoder().encode(id + '.' + ts + '.' + rawBody)));
    const expected = btoa(String.fromCharCode(...mac));
    for (const part of sigHeader.split(' ')) {
      const candidate = part.includes(',') ? part.split(',')[1] : part;
      if (candidate && timingSafeEq(candidate, expected)) return { ok: true, reason: 'ok' };
    }
    return { ok: false, reason: 'signature mismatch - payload was not signed with our endpoint secret' };
  } catch (e) { return { ok: false, reason: 'verification error: ' + String((e as Error)?.message || e).slice(0, 120) }; }
}

function addr(v: unknown){ if(!v) return ''; if(Array.isArray(v)) v=v[0]; const s=String((v as any)?.email||(v as any)?.address||v); const m=s.match(/<([^>]+)>/); return (m?m[1]:s).trim().toLowerCase(); }
function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return {}; } }
function stripHtml(s:string){ return String(s||'').replace(/<style[\s\S]*?<\/style>/gi,' ').replace(/<script[\s\S]*?<\/script>/gi,' ').replace(/<[^>]+>/g,' ').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&#36;/g,'$').replace(/\s+/g,' ').trim(); }
function pickBody(d:any){ const t = d?.text || d?.plain || d?.['body-plain'] || d?.['stripped-text'] || d?.email?.text || d?.parsed?.text || ''; const h = d?.html || d?.['body-html'] || d?.email?.html || d?.parsed?.html || ''; let body = String(t||''); if (!body && h) body = stripHtml(String(h)); return body; }
function b64ToBytes(b64:string){ const bin=atob(b64.replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
function bytesToB64(u8:Uint8Array){ let bin=''; const c=0x8000; for(let i=0;i<u8.length;i+=c){ bin+=String.fromCharCode.apply(null, Array.from(u8.subarray(i,i+c))); } return btoa(bin); }
async function fetchInboundEmail(emailId:string, rkey:string){ try{ const r=await fetch(`https://api.resend.com/emails/inbound/${emailId}`,{headers:{Authorization:`Bearer ${rkey}`}}); if(!r.ok) return null; return await r.json(); }catch{ return null; } }
async function fetchInboundAttachmentBytes(emailId:string, attId:string, rkey:string){ try{ const r=await fetch(`https://api.resend.com/emails/inbound/${emailId}/attachments/${attId}`,{headers:{Authorization:`Bearer ${rkey}`}}); if(!r.ok) return null; const j=await r.json(); const o=j.data||j; const u=o.download_url||o.url; if(!u) return null; const f=await fetch(u); if(!f.ok) return null; return new Uint8Array(await f.arrayBuffer()); }catch{ return null; } }
async function attachmentBytes(a:any, emailId:string, rkey:string|undefined){ if (a.content) return b64ToBytes(String(a.content)); if (a.url || a.download_url) { try { const rr = await fetch(a.url||a.download_url); return new Uint8Array(await rr.arrayBuffer()); } catch {} } if (a.id && emailId && rkey) return await fetchInboundAttachmentBytes(emailId, String(a.id), rkey); return null; }
async function extractDoc(mode:string, bytes:Uint8Array, mime:string, fname:string, inbSecret:string){ try{ const isImg=/^image\//.test(mime); const payload:any = isImg ? { __secret:inbSecret, mode, images:[{ b64: bytesToB64(bytes), mime }] } : { __secret:inbSecret, mode, file_b64: bytesToB64(bytes), mime, filename: fname }; const r=await fetch(`${SUPA_URL}/functions/v1/license_extract`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}); const j=await r.json(); return (j&&j.ok)?j:null; }catch{ return null; } }
const SYS = `You classify a document a supplier emailed to QuotesDone, a UAE building & fit-out marketplace. Decide if it relates to the supplier's company profile and what it is. Return STRICT JSON only: {\"relevant\":boolean,\"category\":\"trade_license\"|\"company_profile\"|\"catalogue\"|\"certificate\"|\"vat_trn\"|\"bank_letter\"|\"insurance\"|\"other\",\"summary\":string,\"suggested_field\":string|null,\"confidence\":\"low\"|\"medium\"|\"high\"}. suggested_field = the profile detail it informs or null.`;
const RECEIPT_SYS = `You extract a business expense from a vendor receipt/invoice/subscription email for QuotesDone bookkeeping. The email is usually a FORWARD; identify the ORIGINAL vendor (Supabase, Vercel, Resend, GoDaddy, Apify, OpenRouter, CloudConvert, Anthropic, OpenAI, Microsoft, Google, Google Play, Dropbox, Adobe, Twilio, Rork, Netflix, Tasjeel, DubaiPay, etc.), NOT the person who forwarded it. If a payment is for a product sold THROUGH a platform (e.g. \"subscription from Dropbox on Google Play\"), the vendor is the actual product (Dropbox). Return STRICT JSON only: {\"is_receipt\":boolean,\"vendor\":string,\"amount\":number,\"currency\":string,\"date\":\"YYYY-MM-DD\",\"recurring\":boolean,\"period\":\"monthly\"|\"annual\"|\"one_off\",\"note\":string}. amount = TOTAL actually charged (incl tax). currency = 3-letter code. IMPORTANT: report the amount in the currency the vendor actually billed, and do not convert between currencies. recurring=true for any subscription/plan/renewal that repeats; period=monthly or annual accordingly; one-off purchases use period=one_off. If there is genuinely no charged amount, set is_receipt=false.`;
function isReceiptish(toLocal:string, subject:string, from:string){
  const boxes=['receipts','receipt','billing','expenses','expense','finance','accounts','accounting','fin','subscriptions','subscription','bills','bill'];
  if (boxes.includes(toLocal)) return true;
  if (/(receipt|invoice|payment (was )?(received|successful|confirmation)|tax invoice|your .*receipt|order receipt|thank you for your order|subscription (renewed|payment|confirmation)|renewal|your plan|billing|funded)/i.test(subject)) return true;
  if (/(billing|invoice|receipts?|no-?reply.*(pay|billing)|stripe)/i.test(from)) return true;
  return false;
}
Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const s = url.searchParams.get('s');
    const ibs = await sec('inbound_secret'); const rit = await sec('resend_inbound_token');
    if (!s || (s !== ibs && s !== rit)) { await logRun('error', { authorised: 0, stage: 'query_token' }, 'resend_inbound rejected a caller with a bad or missing ?s token. No inbound email was processed - if this was genuine Resend traffic, a supplier document or forwarded receipt has been dropped.'); return J({ error: 'forbidden' }, 403); }

    // Read the body ONCE as raw text - the Svix signature covers the exact bytes.
    const raw = await req.text();
    const signingSecret = await sec('resend_inbound_signing_secret');
    if (!signingSecret) { await logRun('error', { authorised: 0, stage: 'no_signing_secret' }, 'resend_inbound could not read resend_inbound_signing_secret from app_secrets, so it cannot confirm this email really came from Resend. The delivery was REJECTED rather than trusted on the query token alone. Inbound receipts and supplier documents are paused until the secret is restored.'); return J({ error: 'signing secret unavailable' }, 503); }
    const v = await verifySvix(signingSecret, raw, req.headers);
    if (!v.ok) { await logRun('error', { authorised: 0, stage: 'signature', reason: v.reason }, 'resend_inbound REJECTED a delivery that failed Svix signature verification (' + v.reason + '). Until 19 Jul 2026 a leaked ?s token alone was enough to book fake expenses and overwrite supplier licence data. If this fires on genuine Resend traffic, check the signing secret in app_secrets matches the endpoint in the Resend dashboard.'); return J({ error: 'invalid signature' }, 401); }

    let p: any = {}; try { p = JSON.parse(raw); } catch (_e) { p = {}; }
    const isResend = p?.type === 'email.received' && p?.data;
    let d = isResend ? p.data : (p.data || p);
    const emailId = String(d.email_id || d.id || '');
    const rkey = await sec('resend_api_key'); const key = await sec('openrouter_api_key'); const inbSecret = ibs;
    let text = pickBody(d);
    let atts: any[] = Array.isArray(d.attachments) ? d.attachments : [];
    if ((!text || text.length < 20 || !atts.length) && emailId && rkey) {
      const full = await fetchInboundEmail(emailId, rkey);
      if (full) { const fd = full.data || full; const fb = pickBody(fd); if (fb && fb.length > text.length) text = fb; if (Array.isArray(fd.attachments) && fd.attachments.length) atts = fd.attachments; if (!d.subject && fd.subject) d = { ...d, subject: fd.subject }; if (!d.from && fd.from) d = { ...d, from: fd.from }; if (!d.to && fd.to) d = { ...d, to: fd.to }; }
      else if (emailId) await logRun('error', { email_id: emailId }, 'could not fetch full inbound email from Resend - body and attachments may be incomplete');
    }
    text = String(text||'').slice(0,8000);
    const from = addr(d.from); const to = addr(d.to); const subject = String(d.subject||'').slice(0,300);
    const toLocal = to.split('@')[0] || '';
    const adminList = String(await sec('admin_emails')||'management@quotesdone.com').toLowerCase().split(',').map((x)=>x.trim()).filter(Boolean);
    const fwdList = String(await sec('expense_forwarders')||'').toLowerCase().split(',').map((x)=>x.trim()).filter(Boolean);
    const expenseSenderOk = [...adminList, ...fwdList].includes(from);
    const owner = adminList[0] || 'management@quotesdone.com';

    // ---- Forwarded receipt / subscription -> finance ----
    if (key && isReceiptish(toLocal, subject, from)) {
      try {
        const r = await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({model:MODEL,max_tokens:400,temperature:0,messages:[{role:'system',content:RECEIPT_SYS},{role:'user',content:`From: ${from}\nSubject: ${subject}\nBody:\n${text}`}]})});
        const jd = await r.json(); const ex:any = r.ok ? parseJson(jd?.choices?.[0]?.message?.content||'{}') : {};
        if (!r.ok) await logRun('error', { from, subject }, 'receipt extraction LLM call failed (http ' + r.status + ') - this email looked like a receipt but no expense was booked');
        if (ex && ex.is_receipt === true && ex.vendor && Number(ex.amount) > 0) {
          const amount = Number(ex.amount);
          const currency = String(ex.currency||'USD').toUpperCase().replace(/[^A-Z]/g,'').slice(0,3) || 'USD';
          const charged = /^\d{4}-\d{2}-\d{2}$/.test(String(ex.date)) ? String(ex.date) : new Date().toISOString().slice(0,10);
          const vendor = String(ex.vendor).slice(0,120);
          const cad = String(ex.period)==='annual' ? 'annual' : (String(ex.period)==='one_off' ? 'one_off' : 'monthly');
          const recurring = ex.recurring === true || cad === 'monthly' || cad === 'annual';
          if (!expenseSenderOk) {
            await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: `[receipt received but NOT booked — sender not allowlisted] ${vendor} ${amount} ${currency}`, attachments_count: 0, matched_existing: false, needs_review: true });
            try{ await admin.from('notifications').insert({ type:'expense_review', to_email: owner, to_role:'admin', channel:'email', subject:'A forwarded receipt needs review', body:`A receipt from ${from} for ${vendor} (${amount} ${currency}) arrived at ${to} but was NOT auto-booked because the sender is not on your allowlist.` }); }catch(_e){}
            await logRun('ok', { receipt: true, booked: false, vendor, amount, currency }, 'receipt not booked: sender ' + from + ' is not on the expense allowlist');
            return J({ ok:true, receipt:true, booked:false, reason:'sender_not_allowlisted' });
          }

          // DEDUP FIX 19 Jul 2026 -------------------------------------------------------------
          // This used to match vendor + charged_on + AMOUNT. Resend RETRIES a delivery that timed
          // out or errored, and the extractor does not always read an identical amount from the
          // same email twice (one pass read a Resend renewal as 20 USD, a re-delivery of the very
          // same receipt read it as 76.39 AED). Because the amounts differed, the old guard let a
          // SECOND expense through and the same real cost was counted twice.
          // Now ANY existing entry for the same vendor on the same date blocks the booking. If the
          // amount differs it is flagged for review rather than silently booked - a genuine second
          // same-day charge from one vendor is possible, but rare enough to deserve a human look,
          // and under-booking with an alert is far safer than silently double-counting costs.
          const { data: sameDay } = await admin.from('expense_entries').select('id,amount,currency').eq('vendor', vendor).eq('charged_on', charged).limit(5);
          if (sameDay && sameDay.length) {
            const exact = sameDay.some((x:any) => Number(x.amount) === amount && String(x.currency||'').toUpperCase() === currency);
            if (!exact) {
              try{ await admin.from('notifications').insert({ type:'expense_review', to_email: owner, to_role:'admin', channel:'email', subject:'Possible duplicate expense was NOT booked', body:`A receipt for ${vendor} dated ${charged} showing ${amount} ${currency} was not booked, because an expense from that vendor already exists on that date (${sameDay.map((x:any)=>x.amount+' '+x.currency).join(', ')}).\n\nThis is usually the same receipt arriving twice and being read slightly differently. If it is genuinely a SECOND charge on the same day, add it manually.` }); }catch(_e){}
            }
            await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: `[receipt dup] ${vendor} ${amount} ${currency} ${charged}${exact?'':' (amount differs from existing entry - flagged)'}`, attachments_count: 0, matched_existing: false, needs_review: !exact });
            await logRun('ok', { receipt: true, deduped: true, vendor, amount, currency, exact_match: exact }, exact ? 'duplicate receipt ignored - an identical expense was already booked for this vendor and date.' : ('receipt NOT booked: an expense from ' + vendor + ' already exists on ' + charged + ' with a DIFFERENT amount (' + sameDay.map((x:any)=>x.amount+' '+x.currency).join(', ') + ' vs ' + amount + ' ' + currency + '). Flagged for review - most likely a redelivery read differently by the extractor, but could be a real second charge.'));
            return J({ ok:true, receipt:true, deduped:true, vendor, amount, currency });
          }

          let docBytes: Uint8Array | null = null; let docName = 'receipt.html'; let docType = 'text/html';
          for (const a of atts.slice(0,8)) { const fn=String(a.filename||a.name||''); const mm=String(a.content_type||a.contentType||''); if (!(/pdf/i.test(mm) || /\.pdf$/i.test(fn))) continue; const by = await attachmentBytes(a, emailId, rkey); if (by && by.length) { docBytes = by; docName = (fn||'receipt.pdf'); docType = 'application/pdf'; break; } }
          if (!docBytes) { const html = String((d.html)|| text || subject); docBytes = new TextEncoder().encode('<meta charset=\"utf-8\"><pre style=\"font:14px/1.5 monospace;white-space:pre-wrap\">'+html.replace(/</g,'&lt;')+'</pre>'); docName = 'receipt.html'; docType = 'text/html'; }
          const ext = docType === 'application/pdf' ? 'pdf' : 'html';
          const rp = `receipts/${charged}/${Date.now()}_${vendor.replace(/[^A-Za-z0-9._-]/g,'_')}.${ext}`;
          let docPath: string | null = null; let upErr = ''; try { const up = await admin.storage.from('receipt-files').upload(rp, docBytes, { contentType: docType, upsert: true }); if (!up.error) docPath = rp; else upErr = String(up.error.message||'').slice(0,150); } catch (e) { upErr = String((e as Error)?.message||e).slice(0,150); }
          await admin.from('expense_entries').insert({ vendor, category: recurring ? 'Subscription' : 'Usage', amount, currency, charged_on: charged, note: ('auto from forwarded ' + (recurring?'subscription':'receipt') + ': ' + String(ex.note||subject)).slice(0,300), source: 'receipt', doc_path: docPath, doc_name: docName.slice(0,180), doc_content_type: docType });
          let bookedSub = false;
          if (recurring) {
            const erow = { vendor, category: 'Subscription', description: String(ex.note||subject).slice(0,300), amount, currency, cadence: cad, expense_date: charged, active: true, source: 'email_forward', confidence: 'medium', note: ('auto from forwarded subscription receipt' + (docPath?' (document archived)':'')) };
            const { data: ex0 } = await admin.from('expenses').select('id').ilike('vendor', vendor).eq('active', true).limit(1);
            if (ex0 && ex0.length) await admin.from('expenses').update(erow).eq('id', ex0[0].id);
            else await admin.from('expenses').insert(erow);
            bookedSub = true;
          }
          await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: `[expense ${recurring?'subscription':'one-off'}] ${vendor} ${amount} ${currency} on ${charged}${docPath?' +'+ext:''}`, attachments_count: docPath?1:0, matched_existing: false, needs_review: false });
          try{ await admin.from('notifications').insert({ type:'expense_logged', to_email: owner, to_role:'admin', channel:'email', subject:`Expense logged: ${vendor} ${amount} ${currency}`, body:`Logged from your forwarded email.\n\nVendor: ${vendor}\nAmount: ${amount} ${currency}\nDate: ${charged}\nType: ${recurring?(cad+' subscription'):'one-off'}` }); }catch(_e){}
          await logRun(upErr ? 'error' : 'ok', { receipt: true, booked: true, vendor, amount, currency, recurring, cadence: cad, doc_archived: !!docPath }, upErr ? ('expense booked but the receipt document failed to archive: ' + upErr) : '');
          return J({ ok: true, receipt: true, vendor, amount, currency, charged_on: charged, recurring, cadence: cad, booked_subscription: bookedSub, doc: docPath });
        }
      } catch (e) { await logRun('error', { from, subject }, 'receipt handling threw, fell through to document handling: ' + String((e as Error)?.message||e).slice(0,200)); }
    }

    // ---- Supplier document handling (store + classify + AUTO-EXTRACT + apply) ----
    let lead: any = null;
    if (from) { const { data } = await admin.from('leads').select('id,company_name,claimed_by,emirate,trn,services,products,capability_summary,service_emirates,catalog_doc_paths,verified').or(`email.eq.${from},claimed_by.eq.${from}`).limit(1).maybeSingle(); lead = data; }
    let stored = 0; const reviews: number[] = []; const appliedSummary: string[] = [];
    let lostAttachments = 0; let uploadFailures = 0; let classifyFailures = 0;
    for (const a of atts.slice(0,6)) {
      const fname = String(a.filename || a.name || 'document').slice(0,180);
      const mime = String(a.content_type || a.contentType || 'application/octet-stream');
      const bytes = await attachmentBytes(a, emailId, rkey);
      // previously a silent 'continue' - a supplier's trade licence could vanish with no record
      if (!bytes) { lostAttachments++; continue; }
      const path = `inbound/${lead?.id||'unknown'}/${Date.now()}_${fname.replace(/[^A-Za-z0-9._-]/g,'_')}`;
      const up = await admin.storage.from('supplier-docs').upload(path, bytes, { contentType: mime, upsert: true });
      // the upload result was never checked: a failed upload still counted as stored
      if (up && (up as any).error) { uploadFailures++; continue; }
      stored++;
      let ai:any = { relevant:null, category:'other', summary:'', suggested_field:null, confidence:'low' };
      if (key) {
        const content:any[] = [{ type:'text', text:`Email from supplier ${lead?.company_name||from}. Subject: ${subject}. Body: ${text}. Attached file: ${fname} (${mime}). Classify this document.` }];
        if (/^image\//.test(mime)) { try { content.push({ type:'image_url', image_url:{ url:`data:${mime};base64,${bytesToB64(bytes)}` } }); } catch {} }
        try {
          const r = await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({model:MODEL,max_tokens:500,temperature:0.1,messages:[{role:'system',content:SYS},{role:'user',content}]})});
          const jd = await r.json(); if (r.ok) ai = { ...ai, ...parseJson(jd?.choices?.[0]?.message?.content||'{}') }; else classifyFailures++;
        } catch { classifyFailures++; }
      }
      const cat = String(ai.category||'other');
      let extracted:any = null; const fields:string[] = [];
      if (lead && inbSecret) {
        if (cat === 'trade_license') {
          const ex = await extractDoc('license', bytes, mime, fname, inbSecret);
          if (ex && ex.doc) { extracted = ex.doc; const dc = ex.doc; const u:any = { license_doc_path: path, license_doc_name: fname, doc_extracted_at: new Date().toISOString() };
            if (dc.confidence !== 'low') {
              if (dc.license_number) { u.trade_license_no = dc.license_number; fields.push('licence no '+dc.license_number); }
              if (dc.license_authority) { u.license_authority = dc.license_authority; fields.push('authority'); }
              if (dc.expiry_date) { u.license_expiry = dc.expiry_date; fields.push('expiry '+dc.expiry_date); }
              if (dc.city) u.license_city = dc.city;
              if (dc.emirate && !lead.emirate) u.emirate = dc.emirate;
              if (dc.trn && !lead.trn) { u.trn = dc.trn; fields.push('TRN'); }
            }
            await admin.from('leads').update(u).eq('id', lead.id);
          }
        } else if (cat === 'company_profile' || cat === 'catalogue') {
          const ex = await extractDoc('profile', bytes, mime, fname, inbSecret);
          const u:any = { doc_extracted_at: new Date().toISOString() };
          if (cat === 'company_profile') u.company_profile_doc_path = path;
          if (cat === 'catalogue') { const cur = Array.isArray(lead.catalog_doc_paths)?lead.catalog_doc_paths:[]; u.catalog_doc_paths = [...cur, path]; }
          if (ex && ex.profile) { extracted = ex.profile; const pr = ex.profile;
            if (pr.confidence !== 'low') {
              if (pr.summary && !lead.capability_summary) { u.capability_summary = pr.summary; fields.push('capability'); }
              if (Array.isArray(pr.services) && pr.services.length && !lead.services) u.services = pr.services;
              if (Array.isArray(pr.products) && pr.products.length && !lead.products) u.products = pr.products;
              if (Array.isArray(pr.emirates) && pr.emirates.length && !(Array.isArray(lead.service_emirates)&&lead.service_emirates.length)) u.service_emirates = pr.emirates;
            }
          }
          await admin.from('leads').update(u).eq('id', lead.id);
        }
        if (fields.length) appliedSummary.push(fname + ' → ' + fields.join(', '));
      }
      const { data: rev } = await admin.from('doc_reviews').insert({ lead_id: lead?.id||null, from_email: from, subject, file_name: fname, file_path: path, mime, ai_relevant: ai.relevant, ai_category: ai.category, ai_summary: String(ai.summary||'').slice(0,1000), ai_suggested_field: ai.suggested_field, ai_confidence: ai.confidence, status: 'pending', auto_applied: fields.length>0, extracted: extracted }).select('id').maybeSingle();
      if (rev?.id) reviews.push(rev.id);
    }
    await admin.from('inbound_messages').insert({ lead_id: lead?.id||null, from_email: from, to_email: to, subject, body: (text||'').slice(0,20000), attachments_count: stored, matched_existing: !!lead, needs_review: stored>0 && appliedSummary.length===0 });
    if (lead && appliedSummary.length) {
      try{ await admin.from('notifications').insert({ type:'supplier_doc_applied', to_email: owner, to_role:'admin', lead_id: lead.id, channel:'email', subject:`Supplier record auto-updated: ${lead.company_name||('Lead #'+lead.id)}`, body:`A document from ${from} was read and applied to ${lead.company_name||('Lead #'+lead.id)}:\n\n${appliedSummary.join('\n')}\n\nReview it in the CRM if needed.` }); }catch(_e){}
    }
    if (from && from !== 'onboarding@resend.dev' && stored>0 && lead) await admin.from('notifications').insert({ type:'doc_received', to_email: from, to_role:'supplier', lead_id: lead?.id||null, subject:'We received your document', body:`Thank you${lead?.company_name?' '+lead.company_name:''} — we received ${stored} document(s) and updated your records.`, status:'queued' });
    const counts = { from, matched_lead: lead?.id||null, attachments: atts.length, stored, lost_attachments: lostAttachments, upload_failures: uploadFailures, classify_failures: classifyFailures, applied: appliedSummary.length, signature_verified: 1 };
    if (lostAttachments || uploadFailures) await logRun('error', counts, 'INBOUND DOCUMENTS LOST - ' + lostAttachments + ' attachment(s) could not be downloaded from Resend and ' + uploadFailures + ' failed to upload to storage. Sender: ' + from + ', subject: ' + subject.slice(0, 120));
    else if (atts.length || stored) await logRun('ok', counts, appliedSummary.length ? ('applied: ' + appliedSummary.join('; ').slice(0, 300)) : (lead ? '' : 'no matching lead for sender'));
    return J({ ok: true, matched_lead: lead?.id||null, stored, reviews, applied: appliedSummary });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception (inbound email dropped): ' + m); return J({ error: m }, 500); }
});
