// Backfill forwarded receipts that resend_inbound could not book while the paid hold was on (6 Sep 2026).
//
// Runs the SAME deterministic parser the edge function runs (supabase/functions/_shared/receipt_parse.ts)
// over the stored inbound_messages bodies, and books what it reads: expense_entries (source 'receipt'),
// the subscription register (expenses) for a recurring vendor, doc_reviews -> 'auto_applied', and the
// inbound row -> replied with the reason. A receipt the parser cannot read is handed to the bookkeeper
// (fn_receipt_hand_to_bookkeeper) — never left in front of the founder. Nothing here types an amount.
//
//   deno run -A scripts/backfill_unbooked_receipts.ts --ids=67,73,74,75 --probe   # aborted transaction, prints counts
//   deno run -A scripts/backfill_unbooked_receipts.ts --ids=67,73,74,75           # commits
//
// Token: %USERPROFILE%\.supabase\access-token or SUPABASE_ACCESS_TOKEN (Supabase management API).
import { parseReceipt } from '../supabase/functions/_shared/receipt_parse.ts';

const REF = 'htdblwldjkcgjvmqkbeh';
const BY = 'receipt_backfill_2026_09_06';
const args = Deno.args;
const ids = (args.find((a) => a.startsWith('--ids=')) || '').slice(6).split(',').map((s) => Number(s)).filter((n) => n > 0);
const probe = args.includes('--probe');
if (!ids.length) { console.error('usage: --ids=67,73 [--probe]'); Deno.exit(2); }

function token(): string {
  const env = Deno.env.get('SUPABASE_ACCESS_TOKEN'); if (env) return env.trim();
  const home = Deno.env.get('USERPROFILE') || Deno.env.get('HOME') || '';
  try { return Deno.readTextFileSync(`${home}/.supabase/access-token`).trim(); } catch { console.error('No Supabase access token.'); Deno.exit(2); }
}
async function sql(query: string): Promise<any> {
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 600)}`);
  return JSON.parse(text);
}
const L = (v: unknown) => v === null || v === undefined ? 'null' : `'${String(v).replace(/'/g, "''")}'`;

const rows = await sql(`
  select m.id, m.from_email, m.subject, m.body, m.needs_review, m.owner_role,
         (select json_agg(json_build_object('id', r.id, 'file_path', r.file_path, 'file_name', r.file_name, 'mime', r.mime) order by r.id)
            from public.doc_reviews r where r.from_email = m.from_email and r.subject = m.subject and r.status in ('pending', 'skipped')) as reviews,
         (select count(*) from public.expense_entries e where e.note like '%[inbound_message:' || m.id || ']%') as already
    from public.inbound_messages m where m.id in (${ids.join(',')}) order by m.id`);

const cadences = await sql(`select lower(vendor) v, cadence from public.expenses where active`);
const cadenceOf = (vendor: string) => cadences.find((c: any) => c.v === vendor.toLowerCase())?.cadence ?? null;

for (const m of rows) {
  const reviews: any[] = m.reviews || [];
  const reviewIds = reviews.map((r) => r.id);
  if (m.already > 0) { console.log(m.id, 'already booked, skipped'); continue; }
  const first = parseReceipt({ from: m.from_email, subject: m.subject, body: m.body });
  // second pass only adds the subscription register's cadence for the vendor the first pass named
  const det = first && parseReceipt({ from: m.from_email, subject: m.subject, body: m.body, knownCadence: cadenceOf(first.vendor) });
  const reason = `Backfill ${BY}: resend_inbound could not book this while paid inference was held`;
  let body: string;
  if (!det) {
    body = `select public.fn_receipt_hand_to_bookkeeper(${m.id}, array[${reviewIds.join(',') || 'null::bigint'}]::bigint[], ${L(reason + '; the deterministic parser read no amount from the text either.')}) as task;`;
  } else {
    // prefer the vendor's receipt over its invoice as the evidence document; both stay in supplier-docs
    const doc = reviews.find((r) => /receipt/i.test(r.file_name)) || reviews[0] || null;
    const note = `auto from forwarded ${det.recurring ? 'subscription' : 'receipt'}: ${m.subject} [inbound_message:${m.id}] [${BY}: ${det.basis}]${doc ? ' (document in supplier-docs bucket)' : ''}`;
    body = `
      insert into public.expense_entries (vendor, category, amount, currency, charged_on, note, source, doc_path, doc_name, doc_content_type)
      select ${L(det.vendor)}, ${det.recurring ? "'Subscription'" : "'Usage'"}, ${det.amount}, ${L(det.currency)}, ${L(det.date)}::date, ${L(note.slice(0, 300))}, 'receipt',
             ${L(doc?.file_path ?? null)}, ${L(doc?.file_name ?? null)}, ${L(doc?.mime ?? null)}
       where not exists (select 1 from public.expense_entries e where e.vendor = ${L(det.vendor)} and e.charged_on = ${L(det.date)}::date);
      ${det.recurring ? `
      update public.expenses set amount = ${det.amount}, currency = ${L(det.currency)}, cadence = ${L(det.period)}, expense_date = ${L(det.date)}::date,
             active = true, source = 'email_forward', confidence = 'medium', note = ${L('auto from forwarded subscription receipt (' + BY + ')')}
       where lower(vendor) = ${L(det.vendor.toLowerCase())} and active;
      insert into public.expenses (vendor, category, description, amount, currency, cadence, expense_date, active, source, confidence, note)
      select ${L(det.vendor)}, 'Subscription', ${L(m.subject.slice(0, 300))}, ${det.amount}, ${L(det.currency)}, ${L(det.period)}, ${L(det.date)}::date, true, 'email_forward', 'medium', ${L('auto from forwarded subscription receipt (' + BY + ')')}
       where not exists (select 1 from public.expenses where lower(vendor) = ${L(det.vendor.toLowerCase())} and active);` : ''}
      update public.doc_reviews set status = 'auto_applied', decided_by = ${L(BY)}, decided_at = now(),
             ai_summary = ${L(`Booked as expense_entries (${det.vendor} ${det.amount} ${det.currency} on ${det.date}) by ${BY} via the deterministic receipt parser; ${det.basis}`)}
       where id = any(array[${reviewIds.join(',') || 'null::bigint'}]::bigint[]) and status in ('pending', 'skipped');
      update public.inbound_messages set needs_review = false, replied_at = now(), replied_by = ${L(BY)},
             ai_notes = ${L(`${reason}. Booked deterministically: ${det.vendor} ${det.amount} ${det.currency} on ${det.date} (${det.period}); ${det.basis}`)}
       where id = ${m.id};`;
  }
  const effect = `select json_build_object('inbound', ${m.id}, 'parsed', ${L(det ? JSON.stringify(det) : null)}::json,
      'expense_rows', (select json_agg(json_build_object('id', id, 'vendor', vendor, 'amount', amount, 'currency', currency, 'charged_on', charged_on, 'doc', doc_name)) from public.expense_entries where note like '%[inbound_message:${m.id}]%'),
      'reviews', (select json_agg(json_build_object('id', id, 'status', status, 'owner', owner_role)) from public.doc_reviews where id = any(array[${reviewIds.join(',') || 'null::bigint'}]::bigint[])),
      'inbound', (select json_build_object('needs_review', needs_review, 'replied_by', replied_by, 'owner', owner_role) from public.inbound_messages where id = ${m.id}),
      'task', (select json_agg(json_build_object('id', id, 'dept', dept_key, 'assigned', assigned_agent, 'status', status)) from public.org_tasks where detail like '[inbound_message:${m.id}]%'))::text as j`;
  const q = probe
    ? `begin; ${body} do $p$ declare j text; begin ${effect} into j; raise exception 'PROBE(rolled back) %', j; end $p$;`
    : `begin; ${body} ${effect}; commit;`;
  try { const r = await sql(q); console.log(m.id, probe ? r : JSON.stringify(r?.[0]?.j ? JSON.parse(r[0].j) : r)); }
  catch (e) { const s = String((e as Error).message); if (probe && s.includes('PROBE(rolled back)')) console.log(m.id, s.slice(s.indexOf('PROBE'))); else { console.error(m.id, s); Deno.exit(1); } }
}
