// Bring migrations that were applied through the Supabase management API back into the repository.
//
// Why this exists: every drift incident on this project has the same root - SQL applied from a tool
// rather than from a checkout, so production knows something the repo does not. `supabase functions
// download` already closes that gap for edge functions; this closes it for migrations.
//
// Usage:  node scripts/archive/sync_migrations_from_prod.js <kb_import_token> [sinceVersion]
// The token is passed on the command line deliberately: it is a single-purpose, disposable
// credential for kb_corpus_import, never the service-role key, and it is not stored in this file.
const fs = require('fs');
const path = require('path');

const TOKEN = process.argv[2];
const SINCE = process.argv[3] || '20260802000000';
const URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_corpus_import';
const OUT = path.join(__dirname, '..', '..', 'supabase', 'migrations');

if (!TOKEN) {
  console.error('usage: node scripts/archive/sync_migrations_from_prod.js <kb_import_token> [sinceVersion]');
  process.exit(1);
}

(async () => {
  const res = await fetch(URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __token: TOKEN, action: 'dump_migrations', since: SINCE }),
  });
  const j = await res.json();
  if (!j.ok) { console.error('failed:', JSON.stringify(j).slice(0, 500)); process.exit(1); }

  let written = 0, skipped = 0;
  for (const m of j.migrations) {
    const file = path.join(OUT, `${m.version}_${m.name}.sql`);
    if (fs.existsSync(file) && fs.readFileSync(file, 'utf8').trim() === String(m.sql).trim()) { skipped++; continue; }
    fs.writeFileSync(file, m.sql.endsWith('\n') ? m.sql : m.sql + '\n', 'utf8');
    console.log('wrote', path.basename(file));
    written++;
  }
  console.log(`\n${j.migrations.length} migrations since ${SINCE}: ${written} written, ${skipped} already current`);
})();
