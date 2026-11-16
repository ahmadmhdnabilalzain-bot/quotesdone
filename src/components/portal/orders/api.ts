// The orders and predict surfaces share one request helper, ../customerCall.ts (16 Nov 2026): this surface calls
// `call('procurement_api', …)` and casts each answer, at the boundary, to the transcription in ./model.
export { call, type ApiResult } from '../customerCall';
