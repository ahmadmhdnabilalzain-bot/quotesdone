// A BANK STATEMENT IN THE EXPENSES MAILBOX IS TAKEN IN AS A STATEMENT (15 Sep 2026, agent: accountant).
//
// WHY THIS FILE EXISTS. #666 built the statement reader and wired it into the accountant's expense_sweep
// only. The live webhook (resend_inbound) never called it, so the founder's first forwarded Mashreq
// statement (14 Sep 2026 21:04Z, subject "statement", August 2026) was treated as a receipt: pdf_text read
// nothing, the model fallback was called (http 503) and the email was HELD for the bookkeeper, while
// bank_statement_intake stayed empty. Both paths now call takeInStatement BEFORE any receipt handling, and a
// recognised statement returns from here — it never reaches the receipt parser or the model gateway.
//
// Recognition is isBankStatement over the sender, subject, filenames AND the document's rebuilt rows
// (pdfTextByRows — the real statement names no bank anywhere but inside the PDF). Reading is readStatement.
// A statement that does not add up is ingested with NO lines and a note: fn_accountant_bank_statement_ingest
// records it 'unreadable', which fn_accountant_bank_reconcile reports as an open accountant finding.
// The closing balance is recorded (#659's fn_accountant_bank_balance_record) only for a statement whose
// every row was proved against it. The bookings (charges -> 6300, owner transfer -> 3000, interest -> 7000,
// drafts while bank_booking_on_hold = 1) are made by fn_accountant_cost_booking_tick from the lines.
import { isBankStatement, readStatement } from './bank_statement_parse.ts';
import { pdfTextByRows } from './pdf_text_positions.ts';

// deno-lint-ignore no-explicit-any
type Db = any;

export type StatementInput = {
  from: string; subject: string; filenames: string[];
  pdf: { bytes: Uint8Array; ext: string; mime: string } | null;   // the sanitised attachment, if a PDF
  csvText?: string;       // a CSV export, when one was attached
  docText?: string;       // pdf_text's guarded text layer ('' when it refused)
  sourceRef: string;      // 'resend:<email id>' — the same key from the webhook and the sweep
  archivePath: string;    // receipt-files path (without extension) for the statement PDF
  readNote?: string;
  dryRun?: boolean;
};

export type StatementOutcome = {
  lines: number; adds_up: boolean; problem: string | null;
  result: unknown; closing_balance: unknown; doc_path: string | null; error: string | null;
  defects_error?: string;   // fn_accountant_statement_reader_defects could not settle (the statement is still in)
};

/** null when the message is not a bank statement; otherwise it has been taken in (or read, on a dry run). */
export async function takeInStatement(admin: Db, i: StatementInput): Promise<StatementOutcome | null> {
  const byEnvelope = isBankStatement(i.from, i.subject, i.filenames);
  const rowText = i.pdf && i.pdf.mime === 'application/pdf' ? await pdfTextByRows(i.pdf.bytes).catch(() => '') : '';
  const csvText = i.csvText || '';
  const isStmt = byEnvelope
    || (!!rowText && isBankStatement(i.from, i.subject, i.filenames, rowText))
    || (!!i.docText && isBankStatement(i.from, i.subject, i.filenames, i.docText));
  if (!isStmt) return null;

  const st = readStatement(csvText || rowText || i.docText || '');
  const lines = st.lines;
  const out: StatementOutcome = { lines: lines.length, adds_up: !st.problem, problem: st.problem,
    result: null, closing_balance: null, doc_path: null, error: null };
  if (i.dryRun) return out;

  if (i.pdf) {
    const sp = i.archivePath + '.' + i.pdf.ext;
    const up = await admin.storage.from('receipt-files').upload(sp, i.pdf.bytes, { contentType: i.pdf.mime, upsert: true });
    if (!up.error) out.doc_path = 'receipt-files/' + sp;
  }
  const { data: ing, error: ingErr } = await admin.rpc('fn_accountant_bank_statement_ingest', {
    p_account: 'mashreq', p_source_ref: i.sourceRef,
    p_statement_month: st.period_from ? st.period_from.slice(0, 8) + '01' : null, p_lines: lines,
    p_doc_path: out.doc_path,
    p_note: st.problem ? 'The statement does not add up, so none of it was booked: ' + st.problem
                         + ' (printed opening ' + st.opening_balance_aed + ', closing ' + st.closing_balance_aed + ')'
          : lines.length ? null : 'No line could be read without guessing a sign: ' + (i.readNote || 'no CSV export and no CR/DR markers in the text layer') });
  out.result = ing ?? null;
  out.error = ingErr?.message ?? null;
  // Founder, 15 Sep 2026: an unreadable statement is a parser defect for the IT engineer, never his question.
  // Settled on every intake, so the finding opens on a failure and closes when the same statement reads.
  if (!ingErr) {
    const { error: dErr } = await admin.rpc('fn_accountant_statement_reader_defects');
    // Not out.error: the statement IS taken in, and a webhook 500 would make Resend redeliver it.
    if (dErr) out.defects_error = dErr.message;
  }
  if (!ingErr && !st.problem && st.closing_balance_aed !== null && st.period_to) {
    const { data: b, error: bErr } = await admin.rpc('fn_accountant_bank_balance_record', {
      p_source_ref: i.sourceRef, p_balance_aed: st.closing_balance_aed, p_on: st.period_to });
    out.closing_balance = bErr ? { error: bErr.message } : b;
  }
  return out;
}
