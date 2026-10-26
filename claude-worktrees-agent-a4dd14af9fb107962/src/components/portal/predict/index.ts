// Customer portal §20 (AI Predictive Intelligence) over supabase/functions/customer_intelligence.
//
// §15 (AI Negotiation Assistant) lived here too until 21 Sep 2026, when the founder removed
// negotiations from both portals (instruction 526). NegotiationAssistant.tsx, the Negotiation type,
// marketComparison() and the negotiation_assistant edge function went with it.
//
//   <PredictiveIntelligence token={token} lang={lang} horizonDays={365} />
//     token        string     customer Supabase JWT (required)
//     lang         'en'|'ar'  default 'en'
//     horizonDays  number     default 365; fn_customer_forecast accepts 1..1095
//     className    string     optional
//
// It fetches on mount, renders its own loading, error and empty states, and refetches when its
// inputs change. Production holds zero inquiries, so today the forecast answers basis='no_history'
// and renders the routine's own sentence explaining that absence rather than drawing a figure.
export { PredictiveIntelligence, type PredictiveIntelligenceProps } from './PredictiveIntelligence';

// The typed client and the derivations, exported so the portal can reuse them rather than deciding
// a second way whether a projection exists and disagreeing.
export { call, type ApiResult } from './api';
export { Empty, Field } from './parts';
export {
  aed, fmtDate, numOrNull, projection, urgency,
  type Forecast, type ForecastCategory, type Lang,
  type Prediction, type Projection, type Urgency,
} from './model';
