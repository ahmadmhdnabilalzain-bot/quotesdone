// RECORD ONE GLOCKAPPS INBOX-PLACEMENT RESULT (it_engineer, 27 Oct 2026).
//
// The GlockApps API key lives only in the session's GlockApps connector (ledger 1344); no Supabase secret holds it and
// the founder is not asked for it. So a session reads the result through the connector and records it here:
//
//   1. GlockApps connector: get_results({ projectId, testId, detail: 'providers' })  -> save the JSON answer to a file
//      (the scratchpad, never the repository).
//   2. node scripts/record_inbox_placement_verdict.mjs --file <answer.json> [--from supplier@quotesdone.com] [--by it_engineer]
//      Add --dry-run to see exactly what would be stored, in one rolled-back transaction, without storing it.
//
// It calls public.fn_record_inbox_placement_verdict, which keeps the per-provider COUNTS GlockApps measured and computes
// every rate from them (scripts/sql/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql). The
// invitation gate (fn_invite_placement_gate) reads the latest record for supplier@. Recording sends no mail, spends no
// GlockApps credit and switches nothing on: invite_enabled stays the founder's own switch.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const ID = /^[0-9A-Za-z:_-]{6,64}$/;
const NUM = ['total', 'inbox', 'spam', 'other', 'notDelivered'];

/** The get_results answer, unwrapped from an MCP envelope if it carries one, and checked the way the routine checks it. */
export function parseResult(input) {
  let r = typeof input === 'string' ? JSON.parse(input) : input;
  // an MCP tool result: { content: [{ type: 'text', text: '{...}' }] }
  if (r && Array.isArray(r.content)) {
    const text = r.content.find((c) => c && c.type === 'text' && typeof c.text === 'string');
    if (!text) throw new Error('the MCP result has no text part');
    r = JSON.parse(text.text);
  }
  if (r && typeof r.result === 'object' && r.result && !r.testId) r = r.result;
  const problems = [];
  if (!ID.test(String(r?.testId ?? ''))) problems.push(`testId ${JSON.stringify(r?.testId)} is not a GlockApps test id`);
  if (Number.isNaN(Date.parse(r?.created ?? ''))) problems.push('created (when the test ran) is missing or unreadable');
  if (!Array.isArray(r?.providerRollup) || r.providerRollup.length === 0) {
    problems.push("providerRollup is missing: call get_results with detail 'providers'");
  } else {
    for (const p of r.providerRollup) {
      const bad = NUM.find((k) => !Number.isInteger(p?.[k]) || p[k] < 0);
      if (!String(p?.providerGroupName ?? '').trim() || bad) problems.push(`provider ${JSON.stringify(p?.providerGroupName)}: ${bad ?? 'name'} is not a count`);
      else if (p.total !== p.inbox + p.spam + p.other + p.notDelivered) problems.push(`provider ${p.providerGroupName}: total ${p.total} is not inbox + spam + other + notDelivered`);
    }
  }
  if (problems.length) throw new Error('not a recordable GlockApps result:\n  - ' + problems.join('\n  - '));
  const sum = (k) => r.providerRollup.reduce((s, p) => s + p[k], 0);
  return { result: r, rollupSeeds: sum('total'), rollupInbox: sum('inbox') };
}

/** Dollar-quote a text with a tag the text does not contain. */
export function dollar(text) {
  let tag = 'gr';
  while (text.includes(`$${tag}$`)) tag += 'x';
  return `$${tag}$${text}$${tag}$`;
}

export function recordSql(result, from, by) {
  return `select public.fn_record_inbox_placement_verdict(${dollar(JSON.stringify(result))}::jsonb, ${dollar(from)}, ${dollar(by)}) as recorded`;
}

function args(argv) {
  const o = { from: 'supplier@quotesdone.com', by: 'it_engineer', dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--file') o.file = argv[++i];
    else if (a === '--from') o.from = argv[++i];
    else if (a === '--by') o.by = argv[++i];
    else if (a === '--dry-run') o.dryRun = true;
    else throw new Error(`unknown argument ${a}`);
  }
  if (!o.file) throw new Error('usage: node scripts/record_inbox_placement_verdict.mjs --file <get_results.json> [--from <mailbox>] [--by <seat>] [--dry-run]');
  return o;
}

async function main() {
  const o = args(process.argv.slice(2));
  const { result, rollupSeeds } = parseResult(readFileSync(o.file, 'utf8'));
  console.log(`test ${result.testId}, created ${result.created}, ${result.providerRollup.length} provider groups, ${rollupSeeds} seeds in the rollup`
    + (Number.isInteger(result.trackedSeeds) ? ` (GlockApps tracks ${result.trackedSeeds})` : '') + `; from ${o.from}; recorded by ${o.by}`);
  const q = recordSql(result, o.from, o.by);
  let rows;
  if (o.dryRun) {
    const { replaySql } = await import('./lib/safe_replay.mjs');
    rows = await replaySql(q, { label: 'record_inbox_placement_verdict --dry-run', rows: true, retry: false });
    console.log('DRY RUN: rolled back, nothing stored.');
  } else {
    const { sql } = await import('./lib/db.mjs');
    rows = await sql(q, { retry: false });
  }
  const r = rows?.[0]?.recorded;
  if (!r?.recorded) throw new Error('the routine did not record: ' + JSON.stringify(rows).slice(0, 500));
  for (const c of ['microsoft', 'google', 'yahoo_aol', 'other', 'overall']) {
    const x = r.class_rates[c];
    console.log(`  ${c.padEnd(9)} seeds ${String(x.seeds).padStart(3)}  inbox ${x.inbox_pct ?? '-'}%  tabs ${x.tabs_pct ?? '-'}%  spam ${x.spam_pct ?? '-'}%  missing ${x.missing_pct ?? '-'}%`
      + (c === 'overall' && x.unclassified ? `  (${x.unclassified} seeds not in GlockApps' provider rows)` : ''));
  }
  console.log('against the bar:', JSON.stringify(r.against_the_bar));
  console.log('gate now:', JSON.stringify(r.gate_now));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main().catch((e) => { console.error(String(e.message || e)); process.exit(1); });
}
