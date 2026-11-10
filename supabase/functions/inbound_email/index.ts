import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeUpload, SAFE_UPLOAD } from '../_shared/attachment.ts';
import { readEveryAttachment, envGatewayVision, untrustedBlock } from '../_shared/read_every_attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. These images are forwarded to a model and
// can reach a person; a refused one is counted in attachmentsRefused exactly as a bad shape is.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { defaultDeps } from '../_shared/think.ts';
import { NONE, tradeOfText } from '../_shared/reasoned_trades.ts';
import { orSafeDomain } from '../_shared/or_filter_email.ts';
// Constant-time compare (L5 / row 40 of the security pass): the one in stripe_setup, not a fourth copy.
import { sameSecret } from '../stripe_setup/webhook_plan.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, x-webhook-secret' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
const fromEmailOf = (b: Record<string, unknown>) => { const e = String(b.from || b.sender || '').toLowerCase().trim(); return e ? { email: e } : null; };

const FREE = new Set(['gmail.com','googlemail.com','yahoo.com','ymail.com','yahoo.co.uk','hotmail.com','hotmail.co.uk','outlook.com','live.com','msn.com','icloud.com','me.com','mac.com','aol.com','mail.com','gmx.com','gmx.net','protonmail.com','proton.me','yandex.com','zoho.com','rediffmail.com','hotmail.fr','outlook.sa']);

// THE SECTOR IS REASONED, NOT COUNTED (23 Sep 2026, founder_instruction 886-903). A KW map scored substrings
// ('door' in 'outdoor', 'sign' in 'design') and the highest count became leads.sector. It is gone: a new lead's
// sector is one category_specs trade reasoned from what the sender wrote, or none (decision point
// inbound_email.infer_sector, _shared/reasoned_trades.ts). It runs after the reply to the webhook is decided and
// never blocks the intake; held, the sector stays empty and fn_reason_apply_inbound_email__infer_sector fills it
// (only while still empty) the moment the hold lifts.
async function reasonSector(leadId: number, text: string): Promise<void> {
  const { data: specs } = await admin.from('category_specs').select('category,label');
  const t = await tradeOfText(defaultDeps(admin, 'inbound_email'), {
    surface: 'inbound_email.infer_sector', text, audience: 'supplier',
    options: (specs || []).map((r: { category: string; label: string | null }) => ({ slug: r.category, label: r.label || r.category })),
    dedupeKey: 'lead_sector:' + leadId, subject: { lead_id: leadId },
  });
  if (t.value && t.value !== NONE && (specs || []).some((r: { category: string }) => r.category === t.value)) {
    await admin.from('leads').update({ sector: t.value }).eq('id', leadId).is('sector', null);
  }
}
function domainOf(email: string): string { const m = String(email || '').toLowerCase().match(/@([^>\s]+)/); return m ? m[1].trim() : ''; }
const empty = (v: unknown) => v === null || v === undefined || (typeof v === 'string' && v.trim() === '');

Deno.serve(observe('inbound_email', async (req) => {
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
    // Both are compared (no short-circuit) and in constant time. This provider sends a shared secret only:
    // no signature and no timestamp header, so there is no replay window to enforce here.
    const [okWh, okIb] = await Promise.all([sameSecret(String(provided), whSecret), sameSecret(String(provided), ibSecret)]);
    if (!provided || !(okWh || okIb)) return J({ error: 'forbidden' }, 403);
    const sec = { value: ibSecret }; // internal secret for downstream calls

    const fromEmail = String(body.from || body.sender || '').toLowerCase().trim();
    const fromName = String(body.from_name || '').trim();
    const subject = String(body.subject || '');
    let text = String(body.text || body.body || '');
    const atts = Array.isArray(body.attachments) ? body.attachments : [];
    // AUDIT 9.1 (3 Aug 2026): this trusted the SENDER'S declared mime — anyone who could send mail
    // to this address could post arbitrary bytes to the model by labelling them "image/png". The
    // declared type is now only a hint: sanitizeUpload identifies the bytes, refuses anything that
    // is not a real JPEG/PNG/WebP, and strips EXIF/GPS before the image is forwarded. A refused
    // attachment is DROPPED rather than failing the whole email, because the text still needs to
    // route — but the count is reported so a sender pushing rejects is visible.
    const images: { mime: string; data: string }[] = [];
    let attachmentsRefused = 0;
    for (const a of atts as { mime?: string; content_type?: string; data?: string }[]) {
      if (!a?.data) continue;
      const sc = await sanitizeAndScan({ input: a.data, declaredMime: a.mime || a.content_type || null,
                                         allow: SAFE_UPLOAD, maxBytes: 10 * 1024 * 1024,
                                         scan: { source: 'inbound_email.image', subject: String(body.from || ''), filename: null } });
      if (!sc.ok) { attachmentsRefused++; continue; }
      const san = sc.result;
      let bin = '';
      for (let i = 0; i < san.bytes.length; i += 0x8000) {
        bin += String.fromCharCode(...san.bytes.subarray(i, i + 0x8000));
      }
      images.push({ mime: san.mime, data: btoa(bin) });
      // RULING 1177 (12 Oct 2026): every attachment is READ — code first (a PDF's text layer), then the vision model.
      // It was sanitised and counted and its words were never looked at; they now travel with the message text, so the
      // stored message and the sector reasoning see what the sender attached. Unreadable ones are named, not dropped.
      const seen = await readEveryAttachment(san.bytes, 'attachment-' + images.length, san.mime, envGatewayVision({ subject: fromEmailOf(body) }));
      text += seen.status === 'read'
        ? '\n\n' + untrustedBlock(seen.text.slice(0, 6000))
        : `\n\n[attachment ${images.length} could not be read: ${String(seen.reason || seen.status).slice(0, 80)}]`;
    }
    if (!fromEmail) return J({ error: 'missing from' }, 400);
    const dom = domainOf(fromEmail);
    const isFree = FREE.has(dom);

    let lead: Record<string, unknown> | null = null;
    const { data: exact } = await admin.from('leads').select('*').ilike('email', fromEmail);
    let candidates: number[] = [];
    if (exact && exact.length === 1) lead = exact[0];
    else if (exact && exact.length > 1) candidates = exact.map((r: { id: number }) => r.id);

    if (!lead && candidates.length === 0 && orSafeDomain(dom) && !isFree) {
      const { data: dl } = await admin.from('leads').select('*').or(`email_domain.ilike.${dom},domain.ilike.${dom}`).order('reviews', { ascending: false, nullsFirst: false }).limit(1);
      if (dl && dl.length) lead = dl[0];
    }

    if (!lead && candidates.length > 1) {
      const { data: m } = await admin.from('inbound_messages').insert({
        lead_id: null, from_email: fromEmail, to_email: String(body.to || ''), subject, body: text,
        attachments_count: atts.length, attachments_refused: attachmentsRefused, matched_existing: true, created_new_lead: false, ai_ok: false,
        needs_review: true, ai_notes: `ambiguous: ${candidates.length} companies share this email`, raw: { candidates },
      }).select('id').maybeSingle();
      return J({ ok: true, needs_review: true, reason: 'multiple companies share this email; queued for manual review', candidates, message_id: m?.id });
    }

    let createdNew = false;
    if (!lead) {
      const ins = await admin.from('leads').insert({
        company_name: fromName || (isFree ? fromEmail : dom) || fromEmail,
        email: fromEmail, email_domain: dom || null, domain: isFree ? null : (dom || null),
        sector: null, business_role: 'supplier',
        source: 'email_inbound', enrich_source: 'email_inbound',
        contacted: true, claimed: false, verified: false, permanently_closed: false,
      }).select('*').maybeSingle();
      lead = ins.data; createdNew = !!lead;
      if (!lead) return J({ error: 'could not create lead', detail: ins.error?.message }, 500);
      // Reasoned beside the intake, never in its way (EdgeRuntime.waitUntil keeps it alive past the response).
      const sectorWork = reasonSector(Number(lead.id), (subject + '\n' + text).slice(0, 4000)).catch(() => {});
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime?.waitUntil?.(sectorWork);
    }

    // profile_ai was DELETED on 8 Sep 2026 under the founder's rule: a function that belongs to
    // neither the CEO nor the customer-support agent does not exist. It enriched a supplier profile
    // from the text of an inbound email, and no agent owned that work.
    //
    // The call is removed rather than left to 404. It sat inside a try/catch with an 'ai fallback'
    // note, so it would have degraded quietly and correctly -- and that is exactly the problem: an
    // HTTP request on every inbound email, to an endpoint deliberately deleted, recording a
    // fallback that reads like a transient AI failure rather than a decision. A dead call that
    // fails gracefully is how a deletion gets un-noticed for months.
    //
    // The intake keeps everything it did without a model: the sender is matched to a lead, the
    // message and attachments are stored, and the row is available for the support agent to work.
    const profile: Record<string, unknown> = {};
    const aiOk = false;
    const aiNotes = 'profile enrichment removed 8 Sep 2026: no agent owns it. Intake is deterministic.';

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
    }
    upd.contacted = true;
    upd.portal_updated_at = new Date().toISOString();
    if (Object.keys(upd).length) await admin.from('leads').update(upd).eq('id', lead.id);

    await admin.from('inbound_messages').insert({
      lead_id: lead.id, from_email: fromEmail, to_email: String(body.to || ''), subject, body: text,
      attachments_count: atts.length, attachments_refused: attachmentsRefused, matched_existing: !createdNew, created_new_lead: createdNew,
      ai_ok: aiOk, needs_review: false, ai_notes: aiNotes || null, raw: { fields_updated: Object.keys(upd) },
    });

    return J({ ok: true, lead_id: lead.id, company: lead.company_name, matched_existing: !createdNew, created_new_lead: createdNew, ai_ok: aiOk, fields_updated: Object.keys(upd) });
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
}));