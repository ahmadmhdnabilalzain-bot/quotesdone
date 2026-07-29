// doc_reminder - consolidated supplier document reminder. Checks trade licence, insurance, establishment
// card, VAT/TRN, ISO certification and manufacturer authorisation for each active supplier; if anything is
// EXPIRING (within N days), EXPIRED, or MISSING (where relevant), sends ONE branded email asking them to reply
// with the documents. Type 'doc_request' => send_outbox sets reply-to = docs@mail.quotesdone.com and bypasses the
// supplier marketing gate (transactional); the reply is auto-extracted/applied to the supplier profile.
// v2: adds ISO + manufacturer authorisation (expiry always; missing only where category/brands make it relevant).
// v3 (29 Jul 2026): TARGETING. Previously this picked targets with a plain leads query filtered on
// approval_status='approved' AND claimed=true, with NO ordering and a hard .limit(500) - so once the
// supplier base passes 500 approved+claimed accounts, Postgres' arbitrary row order decides who ever
// gets chased, and the suppliers who have shared the least documentation are as likely to be dropped
// as anyone else. It now draws the target list from public.v_supplier_doc_score ordered by
// documentation score ASCENDING, so the emptiest supplier profiles are always chased first. Falls back
// to the old query if the view is unavailable, so reminders never stop going out.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseDate(v: unknown): Date | null { if(!v) return null; const d=new Date(String(v)); return isNaN(d.getTime())?null:d; }
function filled(v: unknown): boolean { if (v === null || v === undefined) return false; if (Array.isArray(v)) return v.length > 0; const s = String(v).trim(); return s.length > 0 && s !== '[]' && s !== '{}' && s.toLowerCase() !== 'null' && s.toLowerCase() !== 'none'; }
const ISO_RELEVANT = /secur|cctv|fire|mep|electric|hvac|\bac\b|duct|elevator|\blift|medical|water|pool|solar|smart[-_ ]?home|access[-_ ]?control/i;
const LEAD_COLS = 'id,company_name,email,claimed_by,banned,license_expiry,license_doc_path,insurance_expiry,insurance_doc_path,egr_doc_path,trn,iso_certifications,iso_expiry,iso_doc_path,manufacturer_authorizations,manufacturer_auth_expiry,manufacturer_auth_doc_path,brands_carried,sector,categories';
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);
    const windowDays = Math.max(1, Math.min(90, Number(body.days) || 14));
    const reDays = Math.max(3, Math.min(30, Number(body.resend_after_days) || 10));
    const max = Math.max(1, Math.min(500, Number(body.limit) || 500));
    const now = Date.now();

    // --- target selection: lowest documentation score first ---
    const scoreById = new Map<number, number>();
    const ids: number[] = [];
    const { data: board } = await admin.from('v_supplier_doc_score')
      .select('lead_id,score')
      .eq('approval_status','approved').eq('claimed',true).eq('banned',false)
      .order('score', { ascending: true }).order('lead_id', { ascending: true }).limit(max);
    for (const b of (board || [])) { const id = Number((b as any).lead_id); ids.push(id); scoreById.set(id, Number((b as any).score)); }

    let leads: any[] = [];
    let prioritised = false;
    if (ids.length) {
      const { data } = await admin.from('leads').select(LEAD_COLS).in('id', ids);
      leads = (data || []).slice().sort((a: any, b: any) =>
        ((scoreById.get(Number(a.id)) ?? 999) - (scoreById.get(Number(b.id)) ?? 999)) || (Number(a.id) - Number(b.id)));
      prioritised = true;
    } else {
      // view unavailable or no scored rows -> previous behaviour, so reminders still go out
      const { data } = await admin.from('leads').select(LEAD_COLS)
        .eq('approval_status','approved').eq('claimed',true).limit(max);
      leads = data || [];
    }

    let queued = 0, skipped = 0, no_issues = 0; const sample: string[] = [];
    for (const l of leads) {
      if (l.banned === true) { skipped++; continue; }
      const to = String(l.claimed_by || l.email || '').trim();
      if (!to || to.indexOf('@') < 0) { skipped++; continue; }
      const issues: string[] = [];
      const expLine = (label: string, d: Date) => { const days = Math.round((d.getTime()-now)/864e5); if (days < 0) return label+' EXPIRED on '+d.toISOString().slice(0,10); if (days===0) return label+' expires TODAY'; return label+' expires on '+d.toISOString().slice(0,10)+' (in '+days+' day'+(days===1?'':'s')+')'; };
      const chk = (exp: unknown, docPath: unknown, present: boolean, label: string, missingLabel: string | null) => {
        const dx = parseDate(exp);
        if (dx) { const days = Math.round((dx.getTime()-now)/864e5); if (days <= windowDays) issues.push(expLine(label, dx)); }
        else if (missingLabel && !present && !filled(docPath)) issues.push(missingLabel);
      };
      // trade licence
      chk(l.license_expiry, l.license_doc_path, false, 'Trade licence', 'Trade licence not on file');
      // insurance
      chk(l.insurance_expiry, l.insurance_doc_path, false, 'Insurance certificate', 'Insurance certificate not on file');
      // establishment card
      if (!filled(l.egr_doc_path)) issues.push('Establishment card not on file');
      // VAT / TRN
      if (!filled(l.trn)) issues.push('VAT / TRN number not provided');
      // ISO: expiry always; missing only for ISO-relevant categories
      const catText = [l.sector, Array.isArray(l.categories) ? l.categories.join(' ') : l.categories].filter(Boolean).join(' ');
      const isoRelevant = ISO_RELEVANT.test(catText);
      chk(l.iso_expiry, l.iso_doc_path, filled(l.iso_certifications), 'ISO certification', isoRelevant ? 'ISO certification recommended for your category (upload if you hold one)' : null);
      // manufacturer authorisation: expiry always; missing only if they carry brands
      const carriesBrands = filled(l.brands_carried);
      chk(l.manufacturer_auth_expiry, l.manufacturer_auth_doc_path, filled(l.manufacturer_authorizations), 'Manufacturer authorisation', carriesBrands ? 'Manufacturer authorisation for the brands you carry not on file' : null);
      if (!issues.length) { no_issues++; continue; }
      // de-dupe
      const { data: recent } = await admin.from('notifications').select('id').eq('type','doc_request').eq('lead_id', l.id).gte('created_at', new Date(now - reDays*864e5).toISOString()).limit(1);
      if (recent && recent.length) { skipped++; continue; }
      const co = String(l.company_name || 'there');
      const listTxt = issues.map(x=>'• '+x).join('\n');
      const subject = 'Action needed: keep your QuotesDone documents up to date — ' + co;
      const bodyTxt = 'Dear ' + co + ',\n\nTo keep your QuotesDone supplier profile active and continue receiving customer job requests, the following document(s) need your attention:\n\n' + listTxt + '\n\nHow to fix this: simply REPLY to this email with the document(s) attached (PDF or a clear photo). Our system will read them and update your account automatically — you do not need to do anything else.\n\nIf you have already provided these, please reply with the latest copies so our records stay current. Thank you for being part of QuotesDone.';
      const { error } = await admin.from('notifications').insert({ type:'doc_request', to_email: to, to_role:'supplier', lead_id: l.id, channel:'email', subject, body: bodyTxt, status:'queued' });
      if (!error) { queued++; if (sample.length < 10) { const sc = scoreById.get(Number(l.id)); sample.push(co + ' [doc score ' + (sc === undefined ? 'n/a' : sc) + ']: ' + issues.length + ' issue(s)'); } } else skipped++;
    }
    return J({ ok: true, suppliers: leads.length, queued, no_issues, skipped, window_days: windowDays, prioritised_by_doc_score: prioritised, sample });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
