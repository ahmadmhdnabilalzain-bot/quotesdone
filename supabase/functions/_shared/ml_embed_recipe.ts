// THE MULTILINGUAL EMBEDDING RECIPE, in one place. Seat: it_engineer. 23 Sep 2026.
// Imported by the edge path (ml_embed.ts) and the recall eval (scripts/eval/multilingual_recall_eval.mjs; Node
// strips the types), so the text a row becomes is the same in production and in the measurement.
export const ML_MODEL = 'Xenova/multilingual-e5-small';
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
