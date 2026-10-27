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
