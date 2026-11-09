// Pull a single named file out of the private kb-import-assets bucket into the repo.
//
// Generalises pull_kb_import_assets.js: that script has a hard-coded list for the corpus import,
// this one takes a name and a destination so later phases do not each need their own puller.
//
// Usage: node scripts/archive/pull_asset.js <kb_import_token> <assetName> <repoRelativeDestination>
const fs = require('fs');
const path = require('path');

const [TOKEN, NAME, DEST] = process.argv.slice(2);
const URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_corpus_import';

if (!TOKEN || !NAME || !DEST) {
  console.error('usage: node scripts/archive/pull_asset.js <kb_import_token> <assetName> <repoRelativeDest>');
  process.exit(1);
}

(async () => {
  const res = await fetch(URL, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __token: TOKEN, action: 'get_asset', name: NAME }),
  });
  const j = await res.json();
  if (!j.ok) { console.error('failed:', JSON.stringify(j).slice(0, 300)); process.exit(1); }
  const out = path.join(__dirname, '..', '..', DEST);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, j.content, 'utf8');
  console.log(`wrote ${DEST} (${j.content.length} bytes)`);
})();
