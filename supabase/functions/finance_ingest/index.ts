// finance_ingest — records finance entries (one-off expenses, income, subscriptions) from the Secretary/console
// or the expenses@ email pipeline; forecasts upcoming recurring payments; and runs the 3-day subscription reminder.
// Auth: __secret == inbound_secret (server + cron) OR admin-email JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function whoami(req: Request, body: any): Promise<boolean> {
  if ((await requireInternal(admin, body?.__secret, 'finance_ingest')).ok) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || '').split(/[,;\s]+/).map((s) => s.trim().toLowerCase()).filter(Boolean);
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}
async function founderEmail(): Promise<string> {
  for (const k of ['founder_email', 'email_founder', 'founder_notify_email']) { const v = await sec(k); if (v && /@/.test(v)) return v; }
  const list = (await sec('admin_emails') || '').split(/[,;\s]+/).map((s) => s.trim()).filter((s) => /@/.test(s));
  return list[0] || 'management@quotesdone.com';
}
function addCycle(d: Date, cadence: string): Date { const c = String(cadence || 'monthly').toLowerCase(); const n = new Date(d); if (c.startsWith('ann') || c.startsWith('year')) n.setFullYear(n.getFullYear() + 1); else if (c.startsWith('quart')) n.setMonth(n.getMonth() + 3); else if (c.startsWith('week')) n.setDate(n.getDate() + 7); else n.setMonth(n.getMonth() + 1); return n; }
const ymd = (d: Date) => d.toISOString().slice(0, 10);

async function doLog(entry: any) {
  const kind = String(entry?.kind || 'expense').toLowerCase();
  const amount = Math.round((Number(entry?.amount) || 0) * 100) / 100;
  if (!amount) return { error: 'amount_required' };
  const vendor = String(entry?.vendor || entry?.description || 'Unknown').slice(0, 160);
  const currency = String(entry?.currency || 'AED').slice(0, 8).toUpperCase();
  const category = String(entry?.category || (kind === 'income' ? 'Income' : 'General')).slice(0, 80);
  const note = String(entry?.description || entry?.note || '').slice(0, 800);
  const source = String(entry?.source || 'secretary').slice(0, 40);
  if (kind === 'subscription') {
    let nd: string;
    if (entry?.next_due && /^\d{4}-\d{2}-\d{2}/.test(String(entry.next_due))) nd = String(entry.next_due).slice(0, 10);
    else nd = ymd(addCycle(new Date(), entry?.cycle || 'monthly'));
    // H8 (OS audit): don't create a duplicate active subscription for the same vendor+amount+cadence on a re-ingest.
    const cad = String(entry?.cycle || 'monthly').toLowerCase();
    const { data: dupSub } = await admin.from('expenses').select('id').eq('active', true).eq('vendor', vendor).eq('amount', amount).eq('cadence', cad).limit(1).maybeSingle();
    if (dupSub?.id) return { ok: true, deduped: true, logged: 'subscription', id: dupSub.id, next_due: nd, amount, currency, vendor };
    const { data, error } = await admin.from('expenses').insert({ vendor, category, description: note || vendor, amount, currency, cadence: cad, expense_date: ymd(new Date()), next_due: nd, active: true, source, note }).select('id').maybeSingle();
    if (error) return { error: error.message };
    return { ok: true, logged: 'subscription', id: data?.id, next_due: nd, amount, currency, vendor };
  }
  const signed = kind === 'income' ? -Math.abs(amount) : Math.abs(amount);
  // H8 (OS audit): a re-uploaded invoice (same doc_path) must not create a duplicate expense/income row.
  const dPath = entry?.doc_path || null;
  if (dPath) { const { data: dup } = await admin.from('expense_entries').select('id').eq('doc_path', dPath).limit(1).maybeSingle(); if (dup?.id) return { ok: true, deduped: true, logged: kind, id: dup.id, amount, currency, vendor }; }
  const { data, error } = await admin.from('expense_entries').insert({ vendor, category, amount: signed, currency, charged_on: ymd(new Date()), note: (kind === 'income' ? '[INCOME] ' : '') + note, source, doc_path: dPath, doc_name: entry?.doc_name || null, doc_content_type: entry?.doc_content_type || null }).select('id').maybeSingle();
  if (error) return { error: error.message };
  return { ok: true, logged: kind, id: data?.id, amount, currency, vendor };
}

async function doForecast(days: number) {
  const horizon = ymd(new Date(Date.now() + days * 864e5));
  const { data: subs } = await admin.from('expenses').select('id,vendor,category,amount,currency,cadence,next_due').eq('active', true).not('next_due', 'is', null).lte('next_due', horizon).order('next_due');
  const { data: allSubs } = await admin.from('expenses').select('amount,cadence').eq('active', true);
  let monthly = 0; for (const s of (allSubs || [])) { const c = String(s.cadence || 'monthly').toLowerCase(); const a = Number(s.amount) || 0; monthly += c.startsWith('ann') || c.startsWith('year') ? a / 12 : c.startsWith('quart') ? a / 3 : c.startsWith('week') ? a * 4.33 : a; }
  const { data: recent } = await admin.from('expense_entries').select('amount').gte('charged_on', ymd(new Date(Date.now() - 30 * 864e5)));
  const spend30 = (recent || []).reduce((t, e) => t + Math.max(0, Number(e.amount) || 0), 0);
  return { upcoming: subs || [], monthly_recurring_aed: Math.round(monthly), oneoff_spend_30d_aed: Math.round(spend30), horizon_days: days };
}

async function doRemind(reminderDays: number) {
  const today = new Date(); const todayStr = ymd(today);
  // 1) roll any past-due subscriptions forward so they recur
  const { data: past } = await admin.from('expenses').select('id,next_due,cadence').eq('active', true).not('next_due', 'is', null).lt('next_due', todayStr);
  for (const s of (past || [])) { let nd = new Date(String(s.next_due)); let guard = 0; while (ymd(nd) < todayStr && guard < 60) { nd = addCycle(nd, s.cadence); guard++; } await admin.from('expenses').update({ next_due: ymd(nd) }).eq('id', s.id); }
  // 2) find subscriptions due within the reminder window, not yet reminded this cycle
  const windowEnd = ymd(new Date(Date.now() + reminderDays * 864e5));
  const { data: due } = await admin.from('expenses').select('id,vendor,amount,currency,next_due,cadence,last_reminded_at').eq('active', true).not('next_due', 'is', null).lte('next_due', windowEnd).gte('next_due', todayStr);
  const toRemind = (due || []).filter((s) => !s.last_reminded_at || (Date.now() - new Date(s.last_reminded_at).getTime()) > 6 * 864e5);
  if (!toRemind.length) return { ok: true, reminded: 0, rolled: (past || []).length };
  const lines = toRemind.map((s) => { const days = Math.max(0, Math.round((new Date(String(s.next_due)).getTime() - Date.now()) / 864e5)); return `- ${s.vendor}: ${s.currency} ${Number(s.amount).toLocaleString()} due ${s.next_due} (${days === 0 ? 'today' : 'in ' + days + ' day' + (days === 1 ? '' : 's')})`; }).join('\n');
  const total = toRemind.reduce((t, s) => t + (Number(s.amount) || 0), 0);
  const body = 'UPCOMING PAYMENTS\nThe following subscription/recurring payments are due within the next ' + reminderDays + ' days:\n\n' + lines + '\n\nTotal due soon: AED ' + Math.round(total).toLocaleString() + '.\nMake sure funds are available. Reply or open the OS Finance tab to manage these.';
  const to = await founderEmail();
  await admin.from('notifications').insert({ type: 'finance_reminder', to_email: to, to_role: 'founder', channel: 'email', subject: 'Upcoming payments — ' + toRemind.length + ' due within ' + reminderDays + ' days', body, status: 'queued' });
  await admin.from('expenses').update({ last_reminded_at: new Date().toISOString() }).in('id', toRemind.map((s) => s.id));
  return { ok: true, reminded: toRemind.length, rolled: (past || []).length, total_aed: Math.round(total) };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await whoami(req, body))) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || 'log');
    if (action === 'log') return J(await doLog(body.entry || body));
    if (action === 'forecast') return J(await doForecast(Math.min(120, Math.max(1, Number(body.days) || 30))));
    if (action === 'remind') return J(await doRemind(Math.min(30, Math.max(1, Number(body.reminder_days) || 3))));
    return J({ error: 'unknown_action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
