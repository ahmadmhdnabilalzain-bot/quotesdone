// _shared/case_dropbox.ts — each case summary is a text file in the person's own Dropbox folder (customer_support,
// 11 Nov 2026; founder rulings 1635 and 1634).
//
// Ruling 1635: "The case summaries are backed up in the customer's or supplier's Dropbox folder with their profile." #1938
// built the seam as a PDF and switched it off, because the PDF function has no case_summary renderer. Text does not need one:
// a Markdown file is readable in Dropbox, searchable, and written by code from the case row in milliseconds.
//
// The path is <person folder>/cases/<case number>.md. fn_support_case_summary_backup_enqueue
// (scripts/sql/a_case_summary_is_a_text_file_in_the_persons_dropbox_folder.sql) queues ONE doc_backups row per case,
// re-queued on every summary version; the admit trigger files it in the person's first named folder (the one their
// Customer Details / Company Details file opened). dropbox_backup's renderGenerated calls caseSummaryFile here, which
// renders the case AS IT IS NOW (so a late run never writes an older version over a newer one), stores it in the private
// 'backups' bucket at generated/cases/<case number>.md, and the uploader sends it with mode 'overwrite' and verifies it
// (size and content_hash). Every earlier version stays in public.support_case_summary_version.
// prevented by: dropbox_backup/case_summary.test.ts (the request Dropbox receives, through backupRow, on a stubbed fetch)
// deno-lint-ignore no-explicit-any
type Admin = any;

export interface CaseRow {
  case_ref: string; title: string | null; subject: string | null; summary_text: string | null; summary_version: number;
  summary_updated_at: string | null; status_plain: string | null; opened_at: string | null; last_activity_at: string | null;
  channels: string[] | null; party_kind: string | null; customer_profile_id: number | null;
}
export interface PromiseRow { what: string; due_at: string; due_basis: string; owner_seat: string; status: string; closed_how: string | null }

const STATUS: Record<string, string> = { waiting_on_us: 'waiting on us', waiting_on_them: 'waiting on them', closed: 'closed' };
const SEAT: Record<string, string> = { customer_support: 'Customer Support', sales_engineer: 'Sales Engineer' };
/** A Dubai wall-clock stamp (UTC+4, no daylight saving): what the person and the founder read. */
export const dubaiStamp = (iso: string | null | undefined) => {
  if (!iso) return '-';
  const t = Date.parse(iso); if (!Number.isFinite(t)) return '-';
  return new Date(t + 4 * 3600_000).toISOString().slice(0, 16).replace('T', ' ') + ' Dubai';
};
const cell = (s: unknown) => String(s ?? '').replace(/\|/g, '/').replace(/\s+/g, ' ').trim();

/** The case as a Markdown file: plain text a person can read and Dropbox can search. */
export function caseMarkdown(c: CaseRow, promises: readonly PromiseRow[], who: string | null): string {
  const title = (c.title || c.subject || 'Support case').replace(/\s+/g, ' ').trim();
  const lines = [
    `# Case ${c.case_ref}: ${title}`, '',
    `- With: ${who || (c.party_kind === 'supplier' ? 'a supplier' : 'a customer')}`,
    `- Status: ${STATUS[c.status_plain ?? ''] ?? c.status_plain ?? '-'}`,
    `- Opened: ${dubaiStamp(c.opened_at)}`,
    `- Last activity: ${dubaiStamp(c.last_activity_at)}`,
    `- Channels: ${(c.channels ?? []).join(', ') || '-'}`,
    `- Summary version: ${c.summary_version} (written ${dubaiStamp(c.summary_updated_at)})`,
    '', '## Summary', '', (c.summary_text || '(no summary yet)').trim(), '',
  ];
  if (promises.length) {
    lines.push('## Promises', '', '| What we promised | Due | Owner | Status |', '| --- | --- | --- | --- |');
    for (const p of promises) {
      const due = dubaiStamp(p.due_at) + (p.due_basis === 'assumed' ? ' (no date was given)' : '');
      const status = p.status.replace('_', ' ') + (p.closed_how ? ': ' + p.closed_how : '');
      lines.push(`| ${cell(p.what)} | ${cell(due)} | ${cell(SEAT[p.owner_seat] ?? p.owner_seat)} | ${cell(status)} |`);
    }
    lines.push('');
  }
  lines.push('---', `QuotesDone case record, written automatically after each exchange. Every earlier version is kept by QuotesDone.`);
  return lines.join('\n') + '\n';
}

/** The storage object dropbox_backup uploads for a case_summary row: the case as it is now, one object per case. */
export async function caseSummaryFile(admin: Admin, caseRef: string): Promise<{ bucket: string; path: string }> {
  const { data: c, error } = await admin.from('support_case')
    .select('case_ref,title,subject,summary_text,summary_version,summary_updated_at,status_plain,opened_at,last_activity_at,channels,party_kind,customer_profile_id')
    .eq('case_ref', caseRef).maybeSingle();
  if (error) throw new Error('case_read ' + error.message);
  if (!c) throw new Error('case_missing');
  if (!c.summary_text) throw new Error('case_has_no_summary');
  const [{ data: ps }, { data: pf }] = await Promise.all([
    admin.from('support_case_promise').select('what,due_at,due_basis,owner_seat,status,closed_how').eq('case_ref', caseRef).order('id', { ascending: true }),
    c.customer_profile_id ? admin.from('support_customer_profile').select('display_name').eq('id', c.customer_profile_id).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  const md = caseMarkdown(c as CaseRow, (ps ?? []) as PromiseRow[], pf?.display_name ?? null);
  const path = 'generated/cases/' + caseRef.replace(/[^A-Za-z0-9-]/g, '_') + '.md';
  const up = await admin.storage.from('backups').upload(path, new TextEncoder().encode(md), { upsert: true, contentType: 'text/markdown; charset=utf-8' });
  if (up?.error) throw new Error('case_store ' + up.error.message);
  return { bucket: 'backups', path };
}
