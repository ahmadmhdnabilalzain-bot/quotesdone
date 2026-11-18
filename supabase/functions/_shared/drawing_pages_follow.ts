// drawing_pages_follow — A REQUEST SENT WHILE ITS DRAWING'S SHEETS ARE STILL BEING CHECKED GETS THE PAGES WHEN THEY ARE
// (17 Nov 2026 evening, sales_engineer; paid proof 6244a525, founder ledger 580: "a customer's drawing ALWAYS reaches the
// matched suppliers, redacted and verified, never unverified").
//
// MEASURED: rfq 166742 went out "7 lines, 0 pages, status sent": the sheets were not verified inside analyze_drawing, the
// customer sent the request at once, and nothing ever attached the pages later or told a supplier a drawing existed
// (./drawing_pages_queued.ts header, "What this does NOT do", before today). Now:
//   * create_inquiry is handed the queued job (drawing.pages_job_id) and, when the job is the customer's own, open and for
//     the same stored drawing, the request says "redacted drawing pages follow" (attachedLine) and is NOT recorded as sent
//     without its drawing; a job already finished with every sheet verified attaches its pages there and then;
//   * the supplier's inbox says the pages follow (supplier_api inbox drawing_pages_follow, EN/AR in the portal);
//   * when the CAD read routine publishes the verified set (scripts/cad_read_worker.ts), pagesReachTheirRequestsSql attaches
//     the pages to every open request of that customer that carries the same stored drawing and has none yet, and asks
//     customer_support to tell each matched supplier (one 'rfq_addendum', English, anonymous: suppliers read English only)
//     and the customer (in the language he registered in) through the ONE delivery door, public.fn_customer_support_takes_
//     delivery, which applies the suppression, consent and sanctions rules every send meets. A dedupe key per request and
//     recipient means a re-run never mails twice.
// WHAT THIS DOES NOT DO: a request whose drawing was refused for identity gets no pages, ever, from here; that hold is the
// sales_engineer's finding (customer_api drawing_hold.ts).

/** The line on the request every matched supplier reads (inquiry description and the new-inquiry e-mail). English only. */
export const PAGES_FOLLOW_LINE = ' Redacted drawing pages follow: they are being checked and will be added to this request.';

/** The customer's answer when his request went out with the pages still being checked (create_inquiry). */
export const PAGES_FOLLOW_MESSAGE = {
  en: 'Your request has gone to the suppliers. The drawing pages still being checked will be added to it, and every supplier told, as soon as every sheet is checked.',
  ar: 'أُرسل طلبكم إلى المورّدين. ستُضاف لوحات المخطّط التي ما زالت قيد الفحص إلى الطلب، ويُبلَّغ كل مورّد، بمجرّد فحص كل اللوحات.',
} as const;

/** The supplier's e-mail when the pages are attached. Says nothing of who the customer is: the trade, the emirate, the job.
 *  pagesReachTheirRequestsSql builds the same text in SQL from the same parts (the test compares them). */
const ARRIVED_HEAD = 'The redacted drawing for the ';
const arrivedTail = (pages: number) => ' you were invited to quote is now attached: ' + pages + ' page' + (pages === 1 ? '' : 's')
  + ', with the customer\'s details removed. Log in to your QuotesDone supplier portal to see the drawing and quote.';
export function pagesArrivedMail(inq: { category?: string | null; emirate?: string | null }, pages: number) {
  const job = String(inq.category || 'request').replace(/[_-]+/g, ' ') + (inq.emirate ? ' job in ' + inq.emirate : ' job');
  return { type: 'rfq_addendum', subject: 'Drawing pages were added to a request you were invited to quote', body: ARRIVED_HEAD + job + arrivedTail(pages) };
}

/** The customer's e-mail when the pages are attached to his request, in the language he registered in. */
export function pagesAttachedForCustomer(locale: string | null | undefined, pages: number) {
  if (locale === 'ar') return { lang: 'ar' as const, subject: 'أُضيفت لوحات مخطّطكم إلى طلبكم',
    body: 'تم فحص كل لوحات مخطّطكم (' + pages + ') وحُجبت منها بياناتكم، وأُضيفت إلى طلبكم، وأُبلغ المورّدون الذين دُعوا إلى تسعيره.' };
  return { lang: 'en' as const, subject: 'Your drawing pages were added to your request',
    body: 'Every sheet of your drawing is now checked (' + pages + ' page' + (pages === 1 ? '' : 's') + ', your details removed). The pages were added to your request, and the suppliers invited to quote it were told.' };
}

/** A dollar-quoted literal whose tag cannot occur in the value (the worker's own `lit`). */
const lit = (s: string) => { let tag = 'qd'; while (s.includes(`$${tag}$`)) tag += 'x'; return `$${tag}$${s}$${tag}$`; };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** ONLY A DRAWING'S REQUEST GETS DRAWING PAGES (18 Nov 2026; review of 578f49003, item 1). A request built from a quotation
 *  (brief_source 'quotation') or a priced document (pricedRoute's 'boq') carries the stored original as drawing_file_path for
 *  its own doors; attaching by path alone would picture another supplier's offer, or the customer's rates, for every matched
 *  supplier. A request with no brief_source is a drawing's (inquiry_create sets one whenever a drawing is attached). */
export const DRAWING_BRIEF = (alias: string) => `coalesce(${alias}.brief_source, 'drawing') = 'drawing'`;
/** Requests that are over: no pages are attached to them and nobody is told (supplier_api lib/fields.ts CONCLUDED). */
export const CONCLUDED = ['completed', 'closed', 'cancelled'] as const;

/**
 * ONE statement: attach the verified pages to every open request of the job's customer carrying the same stored drawing and
 * no pages yet, then hand every e-mail to the delivery door. Returns `attached` (request ids) and `delivered` (the door's
 * answer). The paths are the worker's own recorded runs for this customer (drawing_redaction_runs), so supplier_api signs
 * them as it signs any other. null when the job cannot be tied to a customer's drawing (nothing is attached then).
 */
export function pagesReachTheirRequestsSql(job: { id: string; customer_id: string | null; source_path: string }, paths: string[]): string | null {
  if (!job.customer_id || !UUID.test(job.customer_id) || !UUID.test(job.id) || !job.source_path || !paths.length) return null;
  const n = paths.length;
  const arr = 'array[' + paths.map((p) => lit(String(p))).join(', ') + ']::text[]';
  const probe = pagesArrivedMail({}, n);
  const bodyFor = (cat: string, em: string) => `${lit(ARRIVED_HEAD)} || regexp_replace(coalesce(nullif(${cat}, ''), 'request'), '[_-]+', ' ', 'g') || case when coalesce(${em}, '') <> '' then ${lit(' job in ')} || ${em} else ${lit(' job')} end || ${lit(arrivedTail(n))}`;
  const en = pagesAttachedForCustomer('en', n), ar = pagesAttachedForCustomer('ar', n);
  const key = 'drawing_pages_follow:' + job.id;
  return `with att as (
  update public.inquiries i set drawing_redacted_paths = ${arr}
   where i.customer_id = ${lit(job.customer_id)}::uuid and i.drawing_file_path = ${lit(job.source_path)}
     and ${DRAWING_BRIEF('i')}
     and coalesce(cardinality(i.drawing_redacted_paths), 0) = 0
     and coalesce(i.status, 'open') not in (${CONCLUDED.map((s) => lit(s)).join(', ')})
  returning i.id, i.category, i.emirate
), sup as (
  select distinct on (a.id, l.id) a.id as inquiry_id, a.category, a.emirate, l.id as lead_id,
         lower(coalesce(nullif(btrim(l.claimed_by), ''), btrim(l.email))) as to_email
    from att a
    join public.inquiry_matches m on m.inquiry_id = a.id and m.declined_at is null
    join public.leads l on l.id = m.supplier_id and coalesce(l.banned, false) = false
   where lower(coalesce(nullif(btrim(l.claimed_by), ''), btrim(l.email))) ~ '^[^@[:space:]]+@[^@[:space:]]+$'
), cust as (
  select c.email, c.locale, (select a.id from att a order by a.id limit 1) as inquiry_id
    from public.customers c where c.id = ${lit(job.customer_id)}::uuid and exists (select 1 from att)
     and coalesce(btrim(c.email), '') <> ''
), rows as (
  select jsonb_build_object('type', ${lit(probe.type)}, 'channel', 'email', 'to_email', s.to_email, 'to_role', 'supplier', 'lead_id', s.lead_id,
           'inquiry_id', s.inquiry_id, 'subject', ${lit(probe.subject)}, 'body', ${bodyFor('s.category', 's.emirate')}, 'lang', 'en',
           'requested_by', 'sales_engineer', 'dedupe_key', ${lit(key)} || ':' || s.inquiry_id || ':' || s.lead_id) as r
    from sup s
  union all
  select jsonb_build_object('type', 'drawing_pages_attached', 'kind', 'customer_support_drawing_pages_attached', 'channel', 'email',
           'to_email', c.email, 'to_role', 'customer', 'inquiry_id', c.inquiry_id,
           'subject', case when c.locale = 'ar' then ${lit(ar.subject)} else ${lit(en.subject)} end,
           'body', case when c.locale = 'ar' then ${lit(ar.body)} else ${lit(en.body)} end,
           'lang', case when c.locale = 'ar' then 'ar' else 'en' end,
           'requested_by', 'customer_support', 'dedupe_key', ${lit(key)} || ':customer') as r
    from cust c
)
select (select coalesce(jsonb_agg(a.id), '[]'::jsonb) from att a) as attached,
       case when exists (select 1 from rows) then public.fn_customer_support_takes_delivery((select jsonb_agg(r) from rows)) else '[]'::jsonb end as delivered`;
}

/**
 * The requests on a supplier's inbox page whose drawing's sheets are still being checked (supplier_api inbox
 * drawing_pages_follow): an open 'pages_need_time' job of the request's own customer for the request's own stored drawing.
 * Only the FACT leaves this function. A failed read is "nothing follows" (the inbox then says withheld, as before).
 */
// deno-lint-ignore no-explicit-any
export async function pagesFollowFor(db: { from: (t: string) => any }, rows: { id: unknown; customer_id?: unknown; drawing_file_path?: unknown }[]): Promise<Set<string>> {
  const out = new Set<string>();
  const want = rows.filter((r) => r.drawing_file_path && r.customer_id);
  if (!want.length) return out;
  try {
    const { data, error } = await db.from('cad_read_jobs').select('customer_id,source_path').eq('why', 'pages_need_time')
      .in('status', ['queued', 'running']).in('source_path', [...new Set(want.map((r) => String(r.drawing_file_path)))]);
    if (error || !Array.isArray(data)) return out;
    const open = new Set(data.map((j: { customer_id: unknown; source_path: unknown }) => String(j.customer_id) + '|' + String(j.source_path)));
    for (const r of want) if (open.has(String(r.customer_id) + '|' + String(r.drawing_file_path))) out.add(String(r.id));
  } catch (_e) { /* nothing follows */ }
  return out;
}

// ── EVERY RUN, THE PAGES FINISHED IN THE LAST DAY REACH ANY REQUEST THAT MISSED THEM (review 17 Nov 2026, item 3) ───────────
// The race: create_inquiry reads the job OPEN (customer_api lib/drawings.ts pagesStillBeingChecked), the worker finishes and
// attaches to the requests that exist, and only then is the new request inserted: it says "pages follow" and nothing would
// ever attach them. So every worker run re-runs the same idempotent statement for each pages job finished with every sheet
// verified in the last FOLLOW_UP_HOURS (a request saved after the job finished gets its pages and its rfq_addendum; one that
// already has pages, and every mail already sent, is untouched by the statement's own guards and dedupe keys), and a request
// that still has no pages STILL_FOLLOWING_HOURS after its job finished (held, failed, or an attach that keeps failing) is the
// sales_engineer's finding, never silence.
export const FOLLOW_UP_HOURS = 24;
export const STILL_FOLLOWING_HOURS = 2;
/** A request counts as one that was told "pages follow" when it was saved while its job was open, or within this grace after
 *  the job finished (the race above). */
export const RACE_GRACE_MINUTES = 10;

/** The pages jobs finished with every sheet verified in the last FOLLOW_UP_HOURS, with their published pages. */
export const FINISHED_PAGES_JOBS_SQL = `select id, customer_id, source_path, result->'drawing_redacted_paths' as paths
  from public.cad_read_jobs
 where why = 'pages_need_time' and status = 'done' and result->>'redaction_complete' = 'true'
   and finished_at > now() - interval '${FOLLOW_UP_HOURS} hours'
 order by finished_at limit 200`;

/** Requests saved while their pages job was open (or just after it finished) that still have no pages STILL_FOLLOWING_HOURS
 *  after the job finished, one row per job. Read only. */
export const STILL_FOLLOWING_SQL = `select j.id as job_id, j.status, coalesce(j.result->>'held_reason', j.error, '') as why,
       jsonb_agg(i.id order by i.created_at) as inquiries
  from public.cad_read_jobs j
  join public.inquiries i on i.customer_id = j.customer_id and i.drawing_file_path = j.source_path
 where j.why = 'pages_need_time' and j.status in ('done', 'failed')
   and j.finished_at between now() - interval '${FOLLOW_UP_HOURS} hours' and now() - interval '${STILL_FOLLOWING_HOURS} hours'
   and i.created_at >= j.created_at and i.created_at < j.finished_at + interval '${RACE_GRACE_MINUTES} minutes'
   and ${DRAWING_BRIEF('i')}
   and coalesce(cardinality(i.drawing_redacted_paths), 0) = 0
   and coalesce(i.status, 'open') not in (${CONCLUDED.map((c) => `'${c}'`).join(', ')})
 group by j.id, j.status, j.result, j.error
 limit 50`;

/** The sweep. `sql` runs one statement and returns its rows; `raise` files one finding (the worker's fn_it_engineer_finding_upsert).
 *  A failure in one job's attach is counted and does not stop the others or the finding read. */
export async function followUpFinishedPages(deps: { sql: (q: string) => Promise<Record<string, unknown>[]>; raise: (key: string, title: string, evidence: Record<string, unknown>) => Promise<void> }): Promise<{ jobs: number; attached: number; failed: number; still: number }> {
  let jobs = 0, attached = 0, failed = 0;
  for (const j of await deps.sql(FINISHED_PAGES_JOBS_SQL)) {
    const paths = Array.isArray(j.paths) ? j.paths.map(String) : [];
    const stmt = pagesReachTheirRequestsSql({ id: String(j.id), customer_id: j.customer_id ? String(j.customer_id) : null, source_path: String(j.source_path || '') }, paths);
    if (!stmt) continue;
    jobs++;
    try { const r = await deps.sql(stmt); attached += Array.isArray(r[0]?.attached) ? (r[0].attached as unknown[]).length : 0; } catch (_e) { failed++; }
  }
  const still = await deps.sql(STILL_FOLLOWING_SQL);
  for (const s of still) {
    await deps.raise('cad_read_worker:pages_never_followed:' + String(s.job_id),
      `A request told "drawing pages follow" still has no pages ${STILL_FOLLOWING_HOURS} h after its sheets' job finished`,
      { job_id: s.job_id, job_status: s.status, why: String(s.why || '').slice(0, 200), inquiries: s.inquiries });
  }
  return { jobs, attached, failed, still: still.length };
}
