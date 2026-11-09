// Pull the knowledge-corpus importer and its run reports out of the private kb-import-assets
// bucket and into knowledge-import/ in this repository.
//
// The importer runs in a workspace with no checkout of this repo. It uploads its own source through
// kb_corpus_import's put_asset action; this pulls it down verbatim, so the committed script is
// byte-identical to the one that actually produced the 115,148 imported rows rather than a retyped
// approximation of it.
//
// Usage: node scripts/archive/pull_kb_import_assets.js <kb_import_token>
const fs = require('fs');
const path = require('path');

const TOKEN = process.argv[2];
const URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_corpus_import';
const FILES = [
  'import_corpus.py', 'import_routes.py', 'ar_aliases.json', 'live_catalog.json',
  'dry_run_report.json', 'import_report.json', 'routes_report.json', 'idempotency_report.json',
];
const OUT = path.join(__dirname, '..', '..', 'knowledge-import');

if (!TOKEN) { console.error('usage: node scripts/archive/pull_kb_import_assets.js <kb_import_token>'); process.exit(1); }

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  for (const name of FILES) {
    const res = await fetch(URL, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __token: TOKEN, action: 'get_asset', name }),
    });
    const j = await res.json();
    if (!j.ok) { console.error(name, '->', JSON.stringify(j).slice(0, 200)); continue; }
    fs.writeFileSync(path.join(OUT, name), j.content, 'utf8');
    console.log('wrote knowledge-import/' + name, `(${j.content.length} bytes)`);
  }
})();
