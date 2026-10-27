// openrouter_down — what counts as "the server of open router is down" (founder_instruction 1339, 27 Oct 2026).
import { assertEquals } from 'jsr:@std/assert@1';
import { isOpenRouterDown, modelOrOutage } from './openrouter_down.ts';

Deno.test('1339: provider failures are outages; an answer, a refusal or a 4xx is not', () => {
  for (const e of ['gateway_http_502', 'gateway_http_503:circuit_open', 'client_timeout_30000ms', 'client_error', 'fetch_failed',
    'HTTP 504', 'deadline: no time left for another call', 'model_hold', 'no_credential', 'credential_check_unavailable', 'threw',
    'every model route for conversation_reply is open-circuit', 'error sending request for url']) {
    assertEquals(isOpenRouterDown(e), true, e);
  }
  for (const e of ['', null, undefined, 'gateway_http_400:bad request', 'rate_limited', 'truncated at the output limit',
    'no model produced an answer that passes the figure check', 'down', 'guard_refused']) {
    assertEquals(isOpenRouterDown(e), false, String(e));
  }
  // A 4xx is an answer, whatever words the provider's error text carries (independent review of #1647): llm.ts appends
  // the gateway's own outcome and error text after 'gateway_http_<status>', so a 400 that mentions a timeout, the
  // upstream or a connection must not read as OpenRouter down.
  for (const e of ['gateway_http_400:provider_error:upstream request timeout', 'gateway_http_429:rate_limited:connection pool exhausted',
    'gateway_http_400:bad_request:network policy', 'HTTP 400 upstream overloaded', 'HTTP 422 deadline']) {
    assertEquals(isOpenRouterDown(e), false, e);
  }
  assertEquals(isOpenRouterDown('upstream overloaded', 429), false, 'a 4xx status is never an outage');
  assertEquals(isOpenRouterDown('', 0), true, 'no HTTP response at all');
  assertEquals(isOpenRouterDown('', 502), true);
  assertEquals(isOpenRouterDown('', 200), false);
});
Deno.test('1339: modelOrOutage — the model\'s words; the code text only on an outage; otherwise nothing', () => {
  assertEquals(modelOrOutage({ reply: ' Model words. ', outage: true }, 'CODE'), 'Model words.');
  assertEquals(modelOrOutage({ reply: '', outage: true }, 'CODE'), 'CODE');
  assertEquals(modelOrOutage({ reply: '', outage: false }, 'CODE'), '');
  assertEquals(modelOrOutage({ reply: '' }, 'CODE'), '');
});
