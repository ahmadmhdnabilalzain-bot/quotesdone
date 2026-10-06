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

// ARABIC MARKS ARE TAKEN OUT BEFORE THE MODEL SEES A TEXT, on BOTH sides (6 Oct 2026). Tashkeel (U+064B-U+065F),
// the superscript alef (U+0670) and tatweel (U+0640) are optional in written Arabic: the same word arrives with
// and without them, and the tokenizer cuts each spelling into different pieces. Measured on the market packs'
// Arabic questions (412 pack x seat pairs, multilingual space alone): recall@5 0.959 with the marks, 0.974 without,
// pairs under 0.35 8 -> 5. Letter folding as well (alef forms, alef maqsura, teh marbuta: fn_ar_norm's fold) was
// measured too and LOWERED it to 0.934 (13 pairs), so only the marks go. English and digits are untouched.
const AR_MARKS = /[\u064B-\u065F\u0670\u0640]/g;
export const mlClean = (t: string): string => String(t ?? '').replace(AR_MARKS, '');
/** The text a question (or a case situation) is embedded from in the ml space. */
export const mlQueryText = (t: string): string => ML_QUERY_PREFIX + mlClean(String(t ?? '').trim().slice(0, 2000));
/** The text a knowledge row is embedded from in the ml space: a case is a query-side text, knowledge a passage. */
export const mlRowText = (src: string, title: string | null, body: string | null): string =>
  (src === 'seat_case_memory' ? ML_QUERY_PREFIX : ML_PASSAGE_PREFIX) + mlClean(rowText(title, body));

// GTE-SMALL IS NOT ASKED ABOUT AN ARABIC QUESTION (6 Oct 2026). fn_reason_retrieve_ml fuses the multilingual space
// with gte-small, an English-only model. For an Arabic question its vector is noise, and the fusion still gave it
// weight: on the market packs' Arabic questions the fused path read 0.891 against 0.964 for the multilingual space
// alone (English: 0.998 fused, 0.990 alone, so English keeps the fusion). The rule reads the SCRIPT, never a word:
// a question whose letters are mostly Arabic gets no gte vector, and the routine ranks it by the multilingual space.
const AR_LETTER = /[\u0621-\u064A\u066E-\u06D3\u06FA-\u06FF]/g;
const LATIN_LETTER = /[A-Za-z]/g;
export const gteReads = (t: string): boolean => {
  const s = String(t ?? '');
  return (s.match(AR_LETTER)?.length ?? 0) <= (s.match(LATIN_LETTER)?.length ?? 0);
};

/** Where transformers.js fetches `model` from: ML_MODEL from this project's Storage, anything else from Hugging
 *  Face. Node callers (backfill, evals) assign it to transformers.js `env` before building a pipeline. */
export const modelHost = (model: string, projectUrl: string): { remoteHost: string; remotePathTemplate: string } =>
  model === ML_MODEL
    ? { remoteHost: projectUrl + ML_MODEL_PATH, remotePathTemplate: '{model}/' }
    : { remoteHost: 'https://huggingface.co/', remotePathTemplate: '{model}/resolve/{revision}/' };
