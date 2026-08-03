import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, x-webhook-secret' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;

const FREE = new Set(['gmail.com','googlemail.com','yahoo.com','ymail.com','yahoo.co.uk','hotmail.com','hotmail.co.uk','outlook.com','live.com','msn.com','icloud.com','me.com','mac.com','aol.com','mail.com','gmx.com','gmx.net','protonmail.com','proton.me','yandex.com','zoho.com','rediffmail.com','hotmail.fr','outlook.sa']);

const KW: Record<string, string[]> = {
  flooring: ['floor', 'flooring', 'spc', 'vinyl', 'lvt', 'parquet', 'laminate', 'epoxy', 'tile', 'marble', 'granite', 'carpet'],
  glass: ['glass', 'glazing', 'mirror', 'shower enclosure', 'partition', 'facade', 'curtain wall', 'window'],
  aluminium: ['aluminium', 'aluminum', 'pergola', 'cladding', 'composite panel'],
  steel: ['steel', 'metal', 'fabrication', 'welding', 'staircase', 'railing', 'gate'],
  acrylic: ['acrylic', 'plexiglass', 'perspex', 'display stand'],
  carpentry: ['carpentry', 'wood', 'joinery', 'wardrobe', 'cabinet', 'kitchen', 'furniture', 'door'],
  gypsum: ['gypsum', 'false ceiling', 'drywall', 'partition wall', 'ceiling'],
  signage: ['sign', 'signage', '3d letters', 'lightbox', 'led sign', 'billboard', 'sticker'],
  wallpaper: ['wallpaper', 'wall covering'],
  upholstery: ['upholstery', 'sofa', 'curtain', 'blinds', 'cushion'],
  fitout: ['fitout', 'fit-out', 'fit out', 'interior', 'renovation', 'refurbish', 'turnkey', 'joinery works'],
  painting: ['paint', 'painting', 'varnish', 'coating'],
  landscaping: ['landscaping', 'garden', 'grass', 'artificial grass', 'irrigation', 'swimming pool'],
  scaffolding: ['scaffolding', 'scaffold', 'formwork'],
  security: ['cctv', 'camera', 'access control', 'intercom', 'alarm', 'security system'],
  safety: ['safety', 'ppe', 'fire extinguisher', 'fire alarm', 'first aid', 'helmet'],
};
function inferSector(text: string): string | null {
  const t = ' ' + text.toLowerCase() + ' ';
  let best: string | null = null, n = 0;
  for (const [c, ks] of Object.entries(KW)) { let m = 0; for (const k of ks) if (t.includes(k)) m++; if (m > n) { n = m; best = c; } }
  return best;
}
function domainOf(email: string): string { const m = String(email || '').toLowerCase().match(/@([^>\s]+)/); return m ? m[1].trim() : ''; }
const empty = (v: unknown) => v === null || v === undefined || (typeof v === 'string' && v.trim() === '');

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return J({ error: 'POST only' }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    // Auth: external inbound webhook uses its own dedicated secret (inbound_webhook_secret).
    // The internal RPC secret (inbound_secret) is also accepted for backward compatibility and
    // is what we forward to internal functions (profile_ai).
    const { data: secRows } = await admin.from('app_secrets').select('key,value').in('key', ['inbound_webhook_secret', 'cred_fn_inbound_email']);
    const whSecret = (secRows || []).find((r: { key: string; value: string }) => r.key === 'inbound_webhook_secret')?.value || '';
    const ibSecret = (secRows || []).find((r: { key: string; value: string }) => r.key === 'cred_fn_inbound_email')?.value || '';
    const provided = req.headers.get('x-webhook-secret') || body.__secret || '';
    if (!provided || (provided !== whSecret && provided !== ibSecret)) return J({ error: 'forbidden' }, 403);
    const sec = { value: ibSecret }; // internal secret for downstream calls

    const fromEmail = String(body.from || body.sender || '').toLowerCase().trim();
    const fromName = String(body.from_name || '').trim();
    const subject = String(body.subject || '');
    const text = String(body.text || body.body || '');
    const atts = Array.isArray(body.attachments) ? body.attachments : [];
    const images = atts.filter((a: { mime?: string; content_type?: string; data?: string }) => {
      const m = String(a?.mime || a?.content_type || '');
      return a?.data && /^image\//i.test(m);
    }).map((a: { mime?: string; content_type?: string; data: string }) => ({ mime: a.mime || a.content_type, data: a.data }));
    if (!fromEmail) return J({ error: 'missing from' }, 400);
    const dom = domainOf(fromEmail);
    const isFree = FREE.has(dom);

    let lead: Record<string, unknown> | null = null;
    const { data: exact } = await admin.from('leads').select('*').ilike('email', fromEmail);
    let candidates: number[] = [];
    if (exact && exact.length === 1) lead = exact[0];
    else if (exact && exact.length > 1) candidates = exact.map((r: { id: number }) => r.id);

    if (!lead && candidates.length === 0 && dom && !isFree) {
      const { data: dl } = await admin.from('leads').select('*').or(`email_domain.ilike.${dom},domain.ilike.${dom}`).order('reviews', { ascending: false, nullsFirst: false }).limit(1);
      if (dl && dl.length) lead = dl[0];
    }

    if (!lead && candidates.length > 1) {
      const { data: m } = await admin.from('inbound_messages').insert({
        lead_id: null, from_email: fromEmail, to_email: String(body.to || ''), subject, body: text.slice(0, 20000),
        attachments_count: atts.length, matched_existing: true, created_new_lead: false, ai_ok: false,
        needs_review: true, ai_notes: `ambiguous: ${candidates.length} companies share this email`, raw: { candidates },
      }).select('id').maybeSingle();
      return J({ ok: true, needs_review: true, reason: 'multiple companies share this email; queued for manual review', candidates, message_id: m?.id });
    }

    let createdNew = false;
    if (!lead) {
      const guessSector = inferSector(subject + ' ' + text);
      const ins = await admin.from('leads').insert({
        company_name: fromName || (isFree ? fromEmail : dom) || fromEmail,
        email: fromEmail, email_domain: dom || null, domain: isFree ? null : (dom || null),
        sector: guessSector, business_role: 'supplier',
        source: 'email_inbound', enrich_source: 'email_inbound',
        contacted: true, claimed: false, verified: false, permanently_closed: false,
      }).select('*').maybeSingle();
      lead = ins.data; createdNew = !!lead;
      if (!lead) return J({ error: 'could not create lead', detail: ins.error?.message }, 500);
    }

    let profile: Record<string, unknown> = {}; let aiOk = false; let aiNotes = '';
    try {
      const rr = await fetch(`${SUPA_URL}/functions/v1/profile_ai`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: sec.value, company_name: lead.company_name, sector: lead.sector, emirate: lead.emirate, text: (subject ? subject + '\n\n' : '') + text, images }),
      });
      const jd = await rr.json();
      if (jd?.ok && jd.profile) { profile = jd.profile; aiOk = true; } else aiNotes = jd?.error || 'ai fallback';
    } catch (e) { aiNotes = String((e as Error)?.message || e); }

    const upd: Record<string, unknown> = {};
    const setField = (col: string, val: unknown) => {
      if (empty(val)) return;
      const cur = (lead as Record<string, unknown>)[col];
      if (lead!.verified && !empty(cur)) return;
      upd[col] = val;
    };
    if (aiOk) {
      setField('description', profile.description);
      setField('services', profile.services);
      setField('products', profile.products);
      setField('certifications', profile.certifications);
      setField('founded_year', profile.founded_year);
      setField('company_size', profile.company_size);
      setField('company_type', profile.company_type);
      setField('contact_name', profile.contact_name);
      setField('trade_license_no', profile.trade_license_no);
      setField('capability_summary', profile.capability_summary);
      if (Array.isArray(profile.service_emirates) && profile.service_emirates.length) {
        if (!(lead.verified && Array.isArray(lead.service_emirates) && lead.service_emirates.length)) upd.service_emirates = profile.service_emirates;
      }
      if (empty(lead.sector)) { const gs = inferSector([profile.services, profile.products, profile.description, subject, text].join(' ')); if (gs) upd.sector = gs; }
    }
    upd.contacted = true;
    upd.portal_updated_at = new Date().toISOString();
    if (Object.keys(upd).length) await admin.from('leads').update(upd).eq('id', lead.id);

    await admin.from('inbound_messages').insert({
      lead_id: lead.id, from_email: fromEmail, to_email: String(body.to || ''), subject, body: text.slice(0, 20000),
      attachments_count: atts.length, matched_existing: !createdNew, created_new_lead: createdNew,
      ai_ok: aiOk, needs_review: false, ai_notes: aiNotes || null, raw: { fields_updated: Object.keys(upd) },
    });

    return J({ ok: true, lead_id: lead.id, company: lead.company_name, matched_existing: !createdNew, created_new_lead: createdNew, ai_ok: aiOk, fields_updated: Object.keys(upd) });
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
});