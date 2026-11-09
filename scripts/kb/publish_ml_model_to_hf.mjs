// PUBLISH THE EMBEDDING MODEL TO A PUBLIC HUGGING FACE REPO, THEN POINT THE EDGE AT IT (it_engineer, 9 Nov 2026).
//
// Why: every cold edge worker downloads the 47.6 MB trimmed multilingual-e5-small from this project's public
// Storage bucket `ml-models`, and Supabase bills that as cached egress. Measured on production on 2 Nov 2026:
// 2,565 downloads at the CDN edge, about 122 GB, in one day; the 1 TB days of 19 and 27 Oct match ~21,000-25,000.
// Hugging Face serves public model files without egress charges. The founder chose this route on 9 Nov 2026.
//
// What it does, in order, and stops at the first failure:
//   1. reads the five model files from the Storage bucket (one download, 47.6 MB, the last one we pay for);
//   2. creates the PUBLIC model repo <owner>/multilingual-e5-small-ar-en if it does not exist, and uploads the files
//      in one commit (@huggingface/hub handles the 45 MB ONNX through Git LFS);
//   3. reads every file back from https://huggingface.co/<repo>/resolve/main/<file> and compares sha256 with the
//      Storage copy: byte-identical or it stops;
//   4. with --set-secret, sets the edge secret ML_MODEL_HF_REPO=<repo> through the management API. Every function that
//      embeds then loads the model from Hugging Face on its next cold start (supabase/functions/_shared/ml_embed.ts).
//      To undo: delete the secret; the functions fall back to Storage.
//
//   HF_TOKEN=<write token> node scripts/kb/publish_ml_model_to_hf.mjs --owner=Quotesdone            # 1-3
//   HF_TOKEN=<write token> node scripts/kb/publish_ml_model_to_hf.mjs --owner=Quotesdone --set-secret
// In a claude.ai cloud session the token is a network secret for huggingface.co: pass a placeholder in its
// shape, HF_TOKEN=hf_proxyinjected (@huggingface/hub refuses a value not starting hf_; the proxy replaces the header).
import { createHash } from 'node:crypto';
import { ML_MODEL } from './ml_embed_recipe.mjs';
import { supabaseAccessToken } from '../lib/supabase_token.mjs';

const REF = process.env.SUPABASE_PROJECT_REF || 'htdblwldjkcgjvmqkbeh';
const arg = (n) => process.argv.find((a) => a.startsWith(`--${n}=`))?.split('=').slice(1).join('=');
const OWNER = arg('owner');
const SET_SECRET = process.argv.includes('--set-secret');
const TOKEN = process.env.HF_TOKEN;
if (!OWNER || !/^[A-Za-z0-9][\w.-]*$/.test(OWNER)) { console.error('--owner=<hugging face user or org> is required'); process.exit(2); }
if (!TOKEN) { console.error('HF_TOKEN is not set (a Hugging Face WRITE token; proxy-injected in a cloud session)'); process.exit(2); }
const REPO = `${OWNER}/${ML_MODEL}`;
const FILES = ['config.json', 'special_tokens_map.json', 'tokenizer.json', 'tokenizer_config.json', 'onnx/model_quantized.onnx'];
const sha = (b) => createHash('sha256').update(b).digest('hex');

async function get(url, headers = {}) {
  const r = await fetch(url, { headers, signal: AbortSignal.timeout(120_000) });
  if (!r.ok) throw new Error(`${r.status} ${url}`);
  return Buffer.from(await r.arrayBuffer());
}

const { createRepo, uploadFiles } = await import('@huggingface/hub').catch(() => {
  console.error('needs @huggingface/hub: run `npx -y -p @huggingface/hub node scripts/kb/publish_ml_model_to_hf.mjs ...`');
  process.exit(2);
});

// 1. the Storage copy
const local = {};
for (const f of FILES) {
  local[f] = await get(`https://${REF}.supabase.co/storage/v1/object/public/ml-models/${ML_MODEL}/${f}`);
  console.log(`storage  ${f.padEnd(28)} ${String(local[f].length).padStart(10)} B  ${sha(local[f]).slice(0, 16)}`);
}

// 2. the public repo and one commit
const credentials = { accessToken: TOKEN };
try { await createRepo({ repo: { type: 'model', name: REPO }, credentials, private: false }); console.log(`created  ${REPO} (public)`); }
catch (e) { if (!/already|409|exists/i.test(String(e?.message || e))) throw e; console.log(`exists   ${REPO}`); }
await uploadFiles({
  repo: { type: 'model', name: REPO }, credentials,
  files: FILES.map((f) => ({ path: f, content: new Blob([local[f]]) })),
  commitTitle: 'QuotesDone embedding model (trimmed multilingual-e5-small, Arabic + English), served from Hugging Face',
});
console.log('uploaded one commit');

// 3. read back, anonymously, exactly as an edge worker will
for (const f of FILES) {
  const b = await get(`https://huggingface.co/${REPO}/resolve/main/${f}`);
  if (sha(b) !== sha(local[f])) { console.error(`MISMATCH ${f}: Hugging Face ${sha(b)} != Storage ${sha(local[f])}`); process.exit(1); }
  console.log(`verified ${f}`);
}

// 4. the switch
if (SET_SECRET) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/secrets`, {
    method: 'POST', headers: { Authorization: `Bearer ${supabaseAccessToken()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify([{ name: 'ML_MODEL_HF_REPO', value: REPO }]), signal: AbortSignal.timeout(60_000),
  });
  if (!r.ok) { console.error(`setting ML_MODEL_HF_REPO failed: ${r.status} ${await r.text()}`); process.exit(1); }
  console.log(`edge secret ML_MODEL_HF_REPO=${REPO} set; functions load the model from Hugging Face on their next cold start`);
} else {
  console.log(`not switched: re-run with --set-secret to point the edge at ${REPO}`);
}
