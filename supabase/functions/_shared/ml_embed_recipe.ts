// THE MULTILINGUAL EMBEDDING RECIPE, in one place. Seat: it_engineer. 23-24 Sep 2026.
// Imported by the edge path (ml_embed.ts), the backfill (scripts/kb/run_ml_embed_backfill.mjs) and the recall eval
// (scripts/eval/multilingual_recall_eval.mjs; Node strips the types), so the text a row becomes AND the model that
// embeds it are the same in production, in the backfill and in the measurement.
//
// THE MODEL is Xenova/multilingual-e5-small (MIT, 384-d, int8) with its vocabulary trimmed to Arabic + English:
// 250,002 pieces -> 60,422 (every Arabic-script piece, every single character, every piece the 166,764 knowledge
// rows use), 118 MB -> 45.5 MB. Only rows of the word-embedding table go; the transformer is untouched, so a text
// whose pieces are all kept embeds to the SAME vector (measured 24 Sep 2026: 70 texts, min cosine 1.00000 against
// the full model). The full model cannot load in an edge worker: it died at 298 MB (reason Memory, 1.5 s CPU).
// Built by scripts/kb/trim_ml_model.py; served from the public Storage bucket ml-models (the weights are MIT and
// public; nothing of ours is in them except which pieces were kept).
//   onnx/model_quantized.onnx  sha256 f3576a1270d60440cab1c7b5fc18078b686f926ef3740d551c4c765e9e6f16d6
//   tokenizer.json             sha256 35354eb91077647716254ca85803a331564f1dea3441cdde68cfcf1666b58948
export const ML_MODEL = 'multilingual-e5-small-ar-en';
export const ML_MODEL_PATH = '/storage/v1/object/public/ml-models/';   // + ML_MODEL + '/', under the project URL
// e5 is trained with these prefixes: a question is a "query", a knowledge row a "passage". A case is compared
// with a case, so both sides of case memory are queries.
export const ML_QUERY_PREFIX = 'query: ';
export const ML_PASSAGE_PREFIX = 'passage: ';
// The cut every gte-small text already gets (ai_gateway, gte_embed.ts). A row is ONE vector: splitting a row
// into paragraph chunks was measured and made every seat worse (23 Sep 2026, e5 EN 0.625-0.705 chunked vs
// 0.646-0.722 whole), so it was not built.
export const TEXT_CUT = 1200;

/** The text a knowledge row is embedded from, in either space: title, a newline, the body, cut at TEXT_CUT. */
export const rowText = (title: string | null, body: string | null): string =>
  ((title ? String(title) + '\n' : '') + String(body ?? '')).slice(0, TEXT_CUT);

/** Where transformers.js fetches `model` from: ML_MODEL from this project's Storage, anything else from Hugging
 *  Face. Node callers (backfill, evals) assign it to transformers.js `env` before building a pipeline. */
export const modelHost = (model: string, projectUrl: string): { remoteHost: string; remotePathTemplate: string } =>
  model === ML_MODEL
    ? { remoteHost: projectUrl + ML_MODEL_PATH, remotePathTemplate: '{model}/' }
    : { remoteHost: 'https://huggingface.co/', remotePathTemplate: '{model}/resolve/{revision}/' };
