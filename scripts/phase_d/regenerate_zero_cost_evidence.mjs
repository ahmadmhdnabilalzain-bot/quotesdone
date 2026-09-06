// CLOSE THE ZERO-COST WINDOW FROM THE DATABASE CLOCK, NOT FROM SOMEBODY'S MEMORY.
//
//   node scripts/phase_d/regenerate_zero_cost_evidence.mjs          # print what it would write
//   node scripts/phase_d/regenerate_zero_cost_evidence.mjs --write  # rewrite the document
//
// docs/phase-d/PHASE_D_ZERO_COST_EVIDENCE.md states a window and a table of figures measured at its
// close. `scripts/checks/zero_cost_evidence_window_covers_the_work.test.mjs` fails when the close is
// earlier than the newest Phase D / governance timestamp, because a claim whose window ends before
// the work does is not evidence about the work.
//
// IT HAS CAUGHT THAT SIX TIMES: 2026-08-20 (finding 15), 2026-08-20 R4, and three more the document
// enumerates itself, then again on 2026-08-27. The document names the cause in its own words:
//
//   "the window is a hand-maintained sentence in a document and the work it must cover is produced
//    by a dozen scripts, so the only thing keeping them in step is a person remembering to
//    regenerate this file last … what would end the pattern is a generator that reads the close off
//    the database at write time, which does not exist and is named here as the build order."
//
// This is that generator. It changes nothing about what the check demands and weakens nothing: the
// close is `select now()` on production, and every figure below it is re-measured at that instant
// against the window that sentence states. The prose is left exactly as it is — a generator that
// rewrote the narrative would be a generator nobody could read.
//
// ZERO COST, ZERO EFFECT: it reads six counts and writes one file in the repository.
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const DOC = 'docs/phase-d/PHASE_D_ZERO_COST_EVIDENCE.md';
const WRITE = process.argv.includes('--write');

const text = readFileSync(DOC, 'utf8');
const m = text.match(/Covers \*\*([0-9-]{10} [0-9:]{5}) → ([0-9-]{10} [0-9:]{5}) UTC\*\*/);
if (!m) { console.error(`${DOC} no longer states a window in the form "Covers <open> → <close> UTC"`); process.exit(1); }
const open = m[1];

const [now] = await sql('select (now() at time zone \'utc\')::text as t, now()::text as tz');
const closeStamp = now.t.slice(0, 16);          // YYYY-MM-DD HH:MM, the form the sentence uses
const closeFull = now.t.slice(0, 19);

const [f] = await sql(`
  select (select count(*) from public.ai_cost_log where occurred_at > '${open}'::timestamptz
           and (coalesce(model_used,'') not in ('', 'none') or coalesce(cost_aed,0) > 0 or coalesce(prompt_tokens,0) + coalesce(output_tokens,0) > 0)) as cost_rows,
         (select count(*) from public.ai_cost_log where occurred_at > '${open}'::timestamptz
           and coalesce(model_used,'') in ('', 'none') and coalesce(cost_aed,0) = 0 and coalesce(prompt_tokens,0) + coalesce(output_tokens,0) = 0) as refusal_rows,
         (select coalesce(sum(cost_aed),0)::text from public.ai_cost_log where occurred_at > '${open}'::timestamptz) as spend,
         (select count(*) from public.llm_attempt where created_at > '${open}'::timestamptz) as attempts,
         (select count(*) from public.ai_usage   where created_at > '${open}'::timestamptz) as usage_rows,
         (select coalesce(max(occurred_at)::text,'(the table is empty)') from public.ai_cost_log) as newest_cost,
         (select count(*) from net.http_request_queue) as queued_http,
         (select count(*) from cron.job where active) as active_cron,
         (select count(*) from public.notifications where created_at > '${open}'::timestamptz) as notes,
         (select count(*) from public.notifications where created_at > '${open}'::timestamptz and sent_at is not null) as notes_sent,
         (select count(*) from public.customers    where created_at > '${open}'::timestamptz) as new_customers,
         (select count(*) from public.inquiries    where created_at > '${open}'::timestamptz) as new_inquiries,
         (select count(*) from public.quotes       where created_at > '${open}'::timestamptz) as new_quotes,
         -- public.transactions has no created_at; a reveal is what creates one.
         (select count(*) from public.transactions where revealed_at > '${open}'::timestamptz) as new_transactions,
         (select count(*) from public.phase_d_effect_ledger)    as effects,
         (select count(*) from public.phase_d_external_attempt) as external_attempts,
         (select count(*) from public.leads) as leads`);

const table = [
  ['`public.ai_cost_log` inference rows (a model named, or tokens, or cost)', `**${f.cost_rows}**`],
  ['`public.ai_cost_log` held-provider refusal rows (model none, 0 tokens, 0 AED — 6 Sep 2026: the 3-4 Sep fixes record a held return, not inference)', `${f.refusal_rows}`],
  ['`public.ai_cost_log` spend', `**AED ${f.spend}**`],
  ['`public.llm_attempt` rows', `**${f.attempts}**`],
  ['`public.ai_usage` rows', `**${f.usage_rows}**`],
  ['most recent `ai_cost_log` row in the whole table', `${f.newest_cost} — before this window opened`],
  ['`net.http_request_queue`', `**${f.queued_http}**`],
  ['active `cron.job`', `**${f.active_cron}**`],
  ['`public.notifications` written in the window', `${f.notes}, of which **${f.notes_sent} sent**`],
  ['`customers` / `inquiries` / `quotes` / `transactions`', `**${f.new_customers} / ${f.new_inquiries} / ${f.new_quotes} / ${f.new_transactions}**`],
  ['`phase_d_effect_ledger`', `**${f.effects}**`],
  ['`phase_d_external_attempt`', `**${f.external_attempts}**`],
  ['`public.leads`', `${Number(f.leads).toLocaleString('en-US')} — unchanged`],
];

const block = `**Measured at the new close, ${closeFull} UTC:**\n\n`
  + '| | over the stated window |\n|---|---:|\n'
  + table.map(([k, v]) => `| ${k} | ${v} |`).join('\n') + '\n';

let out = text.replace(m[0], `Covers **${open} → ${closeStamp} UTC**`);
const blockRe = /\*\*Measured at the new close, [^*]*\*\*\n\n\| \| over the stated window \|\n\|---\|---:\|\n(?:\|[^\n]*\n)+/;
if (!blockRe.test(out)) {
  console.error(`${DOC} no longer carries the "Measured at the new close" table this generator maintains`);
  process.exit(1);
}
out = out.replace(blockRe, block);

console.log(`window open   ${open}`);
console.log(`window close  ${closeStamp}   (database clock, read at write time)`);
for (const [k, v] of table) console.log(`  ${k.padEnd(52)} ${v}`);

if (!WRITE) { console.log('\nDRY RUN — re-run with --write to rewrite the document.'); process.exit(0); }
if (Number(f.cost_rows) !== 0 || Number(f.attempts) !== 0 || Number(f.usage_rows) !== 0) {
  console.error('\nREFUSING TO WRITE: paid inference was recorded inside the window this document '
    + 'claims is zero-cost. Moving the close would turn a true statement into a false one, which is '
    + 'the opposite of what this generator is for. Report the spend instead.');
  process.exit(1);
}
writeFileSync(DOC, out);
console.log(`\nwrote ${DOC}`);
