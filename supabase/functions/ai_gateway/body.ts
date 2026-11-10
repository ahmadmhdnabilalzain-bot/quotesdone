// ai_gateway/body.ts — the request body the gateway accepts. Moved verbatim from index.ts (9 Nov 2026).
import type { Msg } from './shared.ts';

export interface Body {
  __secret?: string;
  fn?: string; task_class?: string; dept?: string; agent?: string;
  counterpart_model?: string;   // the model that wrote what this call reviews (fn_ai_route_review)
  sys?: string;
  sys_stable?: string;                    // the byte-stable half of the system prompt; only this is marked cacheable
  sys_shared?: string;                    // a byte-stable block shared by a family of prompts, cached first (system_message.ts)
  cache_history?: boolean;                // mark the turn before the newest as a cache breakpoint (system_message.ts withHistoryBreakpoint)
  cache_ttl?: '1h';                       // Anthropic's 1-hour cache tier, asked for by the chat callers only
  input?: string | Msg[];
  messages?: Msg[];                       // full OpenAI-shape passthrough (multimodal, tool turns)
  max?: number; temperature?: number; confidence?: number;
  cache_ttl_min?: number; try_faq?: boolean; faq_text?: string;
  rate_key?: string; rate_limit?: number; rate_window_s?: number;
  stream?: boolean; dry_run?: boolean; escalate?: boolean;
  client_timeout_ms?: number;             // how long the caller will actually wait; the gateway finishes inside it
  action?: string; text?: string;
  // --- modalities, added 29 Jul 2026 ---
  // deno-lint-ignore no-explicit-any
  plugins?: any[];                        // OpenRouter plugins: web search, file-parser
  // deno-lint-ignore no-explicit-any
  tools?: any[];                          // OpenAI-style tool definitions
  // deno-lint-ignore no-explicit-any
  tool_choice?: any;
  // deno-lint-ignore no-explicit-any
  response_format?: any;                  // JSON mode / json_schema
  effort?: string;                        // Claude reasoning effort; request_shape.ts defaults it to medium
  require_caps?: string[];                // override; normally inferred from the payload
  want_message?: boolean;                 // return the whole assistant message (tool_calls included)
  internal_duty?: boolean;                // a seat's own scheduled duty (think.ts internalDuty): a paid empty answer is not re-asked
  cache_exact?: boolean;                  // replay only a byte-identical prompt (no semantic match): the public site's memo
}
