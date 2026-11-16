// sync_staging_assets.mjs — copy the RENDERING assets production depends on into staging.
//
// Phase 1 verified "15 / 15 storage buckets" and that measurement was true and useless: it counted
// buckets, not objects. Staging's `brand` bucket held ZERO objects against production's 26, and
// `brand` is where pdf_native fetches its fonts, logo, signature and stamp from. When a font fetch
// returns nothing pdf_native silently keeps StandardFonts.Helvetica, which is WinAnsi-encoded and
// throws on any character above U+00FF — so on 5 Aug the first quotation comparison that actually
// produced output died on a single "≠" with pdf_failed/502. Every PDF staging had ever rendered was
// running on that fallback: no logo, no signature, no stamp, Latin-1 only.
//
// ONLY `brand` is copied, and that is a deliberate limit, not an oversight. Every other bucket with
// content holds real customer, supplier or finance data — signed terms, compliance documents,
// receipts, backups. Copying those into staging would import production personal data into a system
// built to be written to freely. Brand assets are already served publicly by production, so this
// moves nothing that was not public.
//
//   node scripts/archive/staging/sync_staging_assets.mjs [--dry]
import { supabaseAccessToken } from '../../lib/supabase_token.mjs';
import { resolveStagingRef, PROD_REF, mgmtRead } from '../../lib/qd_guard.mjs';
import { readFileSync } from 'node:fs';
import { pickApiKey } from '../../lib/supabase_keys.mjs';   // new keys first; legacy only as a temporary fallback (27 Oct 2026)

// 15 AUG 2026: this tool's whole job is standing a SECOND project up from this one, and there is
// no second project — pglpqrhvozwepymcuunn was deleted. It is kept rather than retired because it
// works unchanged the day a new staging project exists; it now REFUSES instead of defaulting to a
// ref that 404s, because a sync reporting success against nothing is the worst outcome available.
const REF = resolveStagingRef(process.env.QD_STAGING_REF);
const DRY = process.argv.includes('--dry');
const BUCKET = 'brand';

const mgmt = supabaseAccessToken();

const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`,
  { headers: { Authorization: 'Bearer ' + mgmt } })).json();
const SERVICE = pickApiKey(keys, 'secret');
if (!SERVICE) { console.error('FAIL: could not read the staging service key'); process.exit(1); }

const want = await mgmtRead(PROD_REF,
  `select name, coalesce(metadata->>'mimetype','application/octet-stream') mime,
          (metadata->>'size')::bigint sz
     from storage.objects where bucket_id='${BUCKET}' order by name`);
const have = new Set((await mgmtRead(REF,
  `select name from storage.objects where bucket_id='${BUCKET}'`)).map(r => r.name));

console.log(`${BUCKET}: production has ${want.length} object(s), staging has ${have.size}`);

let copied = 0, skipped = 0, failed = 0;
for (const o of want) {
  if (have.has(o.name)) { skipped++; continue; }
  if (DRY) { console.log(`  would copy ${o.name} (${o.sz} bytes)`); copied++; continue; }
  // Production is read through its PUBLIC url — this script never authenticates to production.
  const src = await fetch(`https://${PROD_REF}.supabase.co/storage/v1/object/public/${BUCKET}/${o.name}`);
  if (!src.ok) { console.log(`  FAIL read ${o.name}: HTTP ${src.status}`); failed++; continue; }
  const bytes = new Uint8Array(await src.arrayBuffer());
  const up = await fetch(`https://${REF}.supabase.co/storage/v1/object/${BUCKET}/${o.name}`, {
    method: 'POST',
    headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': o.mime, 'x-upsert': 'true' },
    body: bytes,
  });
  if (!up.ok) { console.log(`  FAIL write ${o.name}: HTTP ${up.status} ${(await up.text()).slice(0, 120)}`); failed++; continue; }
  console.log(`  copied ${o.name} (${bytes.length} bytes)`);
  copied++;
}

// The fonts are the reason this script exists: without them every PDF is Latin-1 only.
const FONTS = ['qd_sora_regular.ttf', 'qd_sora_bold.ttf', 'qd_ar_regular.ttf', 'qd_ar_bold.ttf'];
const now = new Set((await mgmtRead(REF, `select name from storage.objects where bucket_id='${BUCKET}'`)).map(r => r.name));
const missingFonts = DRY ? [] : FONTS.filter(f => !now.has(f));

console.log(`\nASSETS copied ${copied}, already present ${skipped}, failed ${failed}` +
            ` — staging ${BUCKET} now holds ${DRY ? have.size : now.size} / ${want.length}`);
if (missingFonts.length) {
  console.log(`FAIL: fonts still missing (${missingFonts.join(' ')}) — pdf_native will fall back to ` +
              `WinAnsi Helvetica and cannot render Arabic or typographic characters.`);
  process.exit(1);
}
if (failed) process.exit(1);
