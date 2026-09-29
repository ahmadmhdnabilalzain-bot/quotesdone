// marketing_outreach -- THE MARKETING SEAT'S BUSINESS DEVELOPMENT (marketing, 22 Sep 2026).
//
// Founder, instruction 722: the seat writes articles about QuotesDone and, every day, prepares two or three
// LinkedIn messages; "no one should feel he is an agent". LinkedIn allows no automated messaging (User
// Agreement 8.2) and its API gives an app no member messaging, so this function never calls LinkedIn: it
// drafts, the founder sends from his own account, and taps a link to record what happened.
//
// Internal actions (credential fn.marketing_outreach -> app_secrets.cred_fn_marketing_outreach), used by
// resilience_ping step marketingOutreach and scripts/marketing/business_development.mjs:
//   duties            once a Dubai morning: compose the list (marketing_outreach.ts) and hand it to
//                     fn_marketing_outreach_record / _deliver, which email it ONLY while marketing_golive is
//                     true; release an approved article on the weekly cadence; mark a released article live
//                     when its page answers 200 (which schedules its LinkedIn post in #834's store)
//   ingest_prospects  {prospects:[{full_name, role_title, company, segment, language, source_urls[], ...}]}
// ingest_article and approve_article were REMOVED on 29 Sep 2026 (founder 1058, 1059; #1114): a blog is a market
// topic the marketing seat drafts and the CEO seat reviews (supabase/functions/marketing/duties.ts blog_article and
// scripts/sql/a_blog_article_is_a_market_topic_the_ceo_reviews_until_it_is_useful.sql). A hand-written article, or
// an approval by anyone else, could never be released, so neither door is kept.
//
// The one-tap page, no credential: GET ?m=<mark_token> shows the message and the buttons; only a POST
// records (link scanners and prefetchers issue GETs; see supabase/functions/unsubscribe for why).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { composeFirst, composeFollowUp, founderList, SITE, type ListItem, type Prospect } from '../_shared/marketing_outreach.ts';
import { defaultDeps } from '../_shared/think.ts';
import { replyClass } from '../_shared/reasoned_outreach.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SELF = Deno.env.get('SUPABASE_URL')! + '/functions/v1/marketing_outreach';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const dubaiDay = () => new Date(Date.now() + 4 * 3600_000).toISOString().slice(0, 10);

async function logRun(status: 'ok' | 'error', counts: Record<string, unknown>, note: string, started: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'marketing_outreach', status, counts, note: note.slice(0, 500), started_at: started, finished_at: new Date().toISOString() });
  } catch (_e) { /* the log never breaks the duty */ }
}

  const { data: release, error } = await admin.rpc('fn_marketing_article_release_due');
  if (error) return { ok: false, error: error.message };
  const { data: waiting } = await admin.from('marketing_article').select('slug').eq('status', 'released').limit(5);
  const live: string[] = [];
  for (const { slug } of waiting || []) {
    // The page exists only after the bake is committed and deployed; until then the post waits.
    const r = await fetch(`${SITE}/blog/${slug}`, { method: 'HEAD', redirect: 'follow', signal: AbortSignal.timeout(8000) }).catch(() => null);
    if (r?.status === 200) { await admin.rpc('fn_marketing_article_mark_live', { p_slug: slug }); live.push(slug); }
  }
  return { ok: true, release, live };
}

// ── the morning list ─────────────────────────────────────────────────────────────────────────────
type DueProspect = Prospect & { role_title: string; linkedin_url: string | null };
function compose(p: DueProspect) {
  let c = composeFirst(p);
  // A researcher's opening line is the one text the templates do not control; if it carries a tell, the
  // message goes without it rather than with it.
  if (c.lint.length && p.opening_line) c = composeFirst({ ...p, opening_line: null });
  return c;
}

async function outreachDuty() {
  const { data: due, error } = await admin.rpc('fn_marketing_outreach_due', { p_include_demo: false });
  if (error) return { ok: false, error: error.message };
  const people = (due?.prospects || []) as DueProspect[];
  if (!due?.due || !people.length) return { ok: true, due: !!due?.due, listed: 0, live: due?.live ?? null };
  const composed = people.map((p) => ({ p, c: compose(p) })).filter((x) => x.c.lint.length === 0);
  const { data: rec, error: rErr } = await admin.rpc('fn_marketing_outreach_record', {
    p_day: due.day, p_items: composed.map(({ p, c }) => ({ prospect_id: p.id, language: p.language, body: c.message, note: c.note, lint: [] })),
  });
  if (rErr) return { ok: false, error: rErr.message };
  const byPerson = new Map(composed.map((x) => [x.p.id, x]));
  const items: ListItem[] = []; const ids: number[] = [];
  for (const it of (rec?.items || []) as Array<{ id: number; prospect_id: number; token: string }>) {
    const x = byPerson.get(it.prospect_id); if (!x) continue;
    ids.push(it.id);
    items.push({ full_name: x.p.full_name, role_title: x.p.role_title, company: x.p.company, language: x.p.language,
                 linkedin_url: x.p.linkedin_url, message: x.c.message, note: x.c.note, link: `${SELF}?m=${it.token}` });
  }
  const mail = founderList(due.day, items);
  const { data: delivery, error: dErr } = await admin.rpc('fn_marketing_outreach_deliver', { p_day: due.day, p_ids: ids, p_subject: mail.subject, p_body: mail.body });
  if (dErr) return { ok: false, error: dErr.message };
  return { ok: true, due: true, live: rec?.live, listed: ids.length, skipped_by_lint: people.length - composed.length, delivery: delivery?.mode };
}

// ── the one-tap page ─────────────────────────────────────────────────────────────────────────────
const esc = (s: unknown) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const L = {
  sent: 'I sent it · أرسلتُها', converted: 'Converted · تحوّل إلى عميل', declined: 'Not interested · غير مهتم',
  reply: 'Paste the reply and draft the follow-up · الصق الرد لإعداد المتابعة', message: 'Message · الرسالة',
  note: 'Connection note · ملاحظة طلب التواصل', follow: 'Follow-up to send · رسالة المتابعة', unknown: 'This link is not valid. · هذا الرابط غير صالح.',
  recorded: 'Recorded. · سُجّل.',
  recordedHeld: 'Recorded. The follow-up is drafted as soon as the reply has been read. · سُجّل الرد، وتُكتب رسالة المتابعة فور قراءته.',
};
function page(inner: string, status = 200) {
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>QuotesDone · LinkedIn</title></head><body style="margin:0;background:#f6f7f9;font-family:Arial,Helvetica,sans-serif;color:#1f2937"><div style="max-width:620px;margin:32px auto;padding:16px">${inner}</div></body></html>`;
  return new Response(html, { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
}
const box = (title: string, text: string, rtl: boolean) =>
  `<div style="background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:16px;margin:12px 0"><div style="font-size:12px;color:#6b7280;margin-bottom:8px">${esc(title)}</div><div dir="${rtl ? 'rtl' : 'ltr'}" style="white-space:pre-wrap;font-size:15px;line-height:1.6;user-select:all">${esc(text)}</div></div>`;
const btn = (m: string, a: string, label: string, colour: string) =>
  `<form method="post" action="?m=${esc(m)}" style="display:inline-block;margin:6px 6px 0 0"><input type="hidden" name="a" value="${a}"><button type="submit" style="background:${colour};color:#fff;border:0;border-radius:10px;padding:10px 16px;font-size:14px;font-weight:700;cursor:pointer">${esc(label)}</button></form>`;

// deno-lint-ignore no-explicit-any
function render(m: string, d: any, flash = '') {
  const rtl = d.language === 'ar';
  const p = d.prospect || {};
  const head = `<div style="font-weight:800;font-size:18px">${esc(p.full_name)}</div><div style="color:#6b7280">${esc(p.role_title)}, ${esc(p.company)} · ${esc(p.status)}</div>` +
    (p.linkedin_url ? `<div style="margin-top:6px"><a href="${esc(p.linkedin_url)}" rel="noopener">${esc(p.linkedin_url)}</a></div>` : '');
  const follows = (d.follow_ups || []).map((f: { body: string; token: string }) => box(L.follow, f.body, rtl) + `<div style="font-size:12px"><a href="?m=${esc(f.token)}">${esc(f.token.slice(0, 8))}</a></div>`).join('');
  return page((flash ? `<div style="background:#ecfdf5;border:1px solid #a7f3d0;border-radius:10px;padding:10px;margin-bottom:12px">${esc(flash)}</div>` : '') + head +
    box(L.message, d.body, rtl) + (d.note ? box(L.note, d.note, rtl) : '') + (d.reply_text ? box('Reply · الرد', d.reply_text, rtl) : '') + follows +
    btn(m, 'sent', L.sent, '#0d9488') + btn(m, 'converted', L.converted, '#1d4ed8') + btn(m, 'declined', L.declined, '#6b7280') +
    `<form method="post" action="?m=${esc(m)}" style="margin-top:16px"><input type="hidden" name="a" value="replied"><label style="font-size:13px;color:#374151">${esc(L.reply)}</label><textarea name="reply" rows="5" dir="auto" style="width:100%;box-sizing:border-box;margin-top:6px;border:1px solid #d1d5db;border-radius:10px;padding:10px;font-size:14px"></textarea><button type="submit" style="margin-top:8px;background:#111827;color:#fff;border:0;border-radius:10px;padding:10px 16px;font-size:14px;font-weight:700;cursor:pointer">${esc(L.reply)}</button></form>`);
}

async function onePage(req: Request, m: string) {
  if (!/^[0-9a-f-]{36}$/i.test(m)) return page(L.unknown, 404);
  const load = async () => (await admin.rpc('fn_marketing_outreach_page', { p_token: m })).data;
  const d = await load();
  if (!d) return page(L.unknown, 404);
  if (req.method !== 'POST') return render(m, d);
  const form = await req.formData().catch(() => null);
  const a = String(form?.get('a') || '');
  if (a === 'replied') {
    const reply = String(form?.get('reply') || '').slice(0, 4000);
    // WHAT THE REPLY MEANS is reasoned (think(), founder_instruction 886-903), never read off a word list. Held:
    // the reply is recorded as replied, nobody is closed and no follow-up is drafted on a guess; the marketing
    // seat's queue reasons it when the hold lifts and fn_marketing_outreach_reply_reasoned drafts it then.
    const cls = reply.trim() ? (await replyClass(defaultDeps(admin, 'marketing_outreach'), { reply, sent: String(d.body || ''), token: m, language: d.language === 'ar' ? 'ar' : 'en' })).value : null;
    const f = cls ? composeFollowUp({ full_name: d.prospect.full_name, language: d.language }, cls) : null;
    const { data: res } = await admin.rpc('fn_marketing_outreach_mark', {
      p_token: m, p_status: 'replied', p_reply: reply, p_reply_class: cls, p_follow_up: f && !f.lint.length ? f.message : null,
    });
    return render(m, await load(), res?.ok ? (cls ? L.recorded : L.recordedHeld) : String(res?.error || 'error'));
  }
  if (!['sent', 'converted', 'declined'].includes(a)) return render(m, d);
  const { data: res } = await admin.rpc('fn_marketing_outreach_mark', { p_token: m, p_status: a });
  return render(m, await load(), res?.ok ? L.recorded : String(res?.error || 'error'));
}

Deno.serve(async (req) => {
  if (req.method === 'GET' && req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  const m = new URL(req.url).searchParams.get('m');
  if (m !== null) return onePage(req, m);

  const started = new Date().toISOString();
  // deno-lint-ignore no-explicit-any
  const body = await req.json().catch(() => ({} as any));
  const auth = await requireInternal(admin, body?.__secret, 'marketing_outreach');
  if (!auth.ok) return J({ error: auth.error, message: auth.message }, auth.status);
  const action = String(body.action || 'duties');
  try {
    if (action === 'ingest_prospects') {
      const out = [];
      for (const p of Array.isArray(body.prospects) ? body.prospects : []) {
        const { data, error } = await admin.rpc('fn_marketing_prospect_upsert', { p });
        out.push(error ? { ok: false, error: error.message, full_name: p?.full_name } : { ...data, full_name: p?.full_name });
      }
      return J({ ok: out.every((x) => x.ok), results: out });
    }
    if (action !== 'duties') return J({ error: 'unknown_action' }, 400);

    const outreach = await outreachDuty();
    const articles = await articleDuty();
    const bad = [outreach, articles].filter((x) => x.ok === false);
    // deno-lint-ignore no-explicit-any
    const ran = ((outreach as any).listed ?? 0) > 0 || (articles as any).release?.released || ((articles as any).live || []).length;
    if (ran || bad.length) await logRun(bad.length ? 'error' : 'ok', { outreach, articles }, bad.length ? 'marketing_outreach duty failed: ' + JSON.stringify(bad).slice(0, 400) : 'marketing_outreach duties ran', started);
    return J({ ok: bad.length === 0, outreach, articles });
  } catch (err) {
    await logRun('error', { action }, 'marketing_outreach crashed: ' + String((err as Error)?.message || err), started);
    return J({ ok: false, error: String((err as Error)?.message || err) }, 500);
  }
});
