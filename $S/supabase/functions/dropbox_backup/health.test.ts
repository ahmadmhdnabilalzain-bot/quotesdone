// deno test supabase/functions/dropbox_backup/health.test.ts
// Every error shape the Dropbox path throws lands in the class the founder's rule needs: only a
// provider answer (5xx, 429) or no answer at all is outside our control; anything unrecognised is ours.
import { assertEquals } from 'jsr:@std/assert@1';
import { classifyDropboxFailure as c, isTransientDbError as t } from './health.ts';

Deno.test('transient db: the wait-and-give-up errors measured on 15 Sep, and nothing else', () => {
  assertEquals(t('fn_doc_backups_next: canceling statement due to statement timeout'), true);
  assertEquals(t('canceling statement due to statement timeout'), true);
  assertEquals(t('canceling statement due to lock timeout'), true);
  assertEquals(t('deadlock detected'), true);
  assertEquals(t('could not obtain lock on row in relation "doc_backups"'), true);
  assertEquals(t('fn_doc_backups_next: permission denied for function fn_doc_backups_next'), false);
  assertEquals(t('no_dropbox_auth'), false);
  assertEquals(t('files/upload 503 busy after 3 tries'), false);
  assertEquals(t(''), false);
  assertEquals(t(null), false);
});

Deno.test('auth: a refused token, a failed refresh, a missing scope', () => {
  assertEquals(c('no_dropbox_auth'), 'auth');
  assertEquals(c('get_space_usage 401 {"error_summary":"expired_access_token/"}'), 'auth');
  assertEquals(c('delete_v2 400 {"error_summary":"missing_scope/.."}'), 'auth');
});

Deno.test('quota: a full account, whatever the status', () => {
  assertEquals(c('dbx_upload 409 {"error_summary":"path/insufficient_space/.."}'), 'quota');
  assertEquals(c('finish 409 {"error_summary":"path/insufficient_space/"}'), 'quota');
  assertEquals(c('files/upload 507 over_quota after 3 tries'), 'quota');
});

Deno.test('rate_limit: 429 and Dropbox\'s own words for it', () => {
  assertEquals(c('get_space_usage 429 {"error_summary":"too_many_requests/"}'), 'rate_limit');
  assertEquals(c('dbx_upload 409 {"error_summary":"path/too_many_write_operations/"}'), 'rate_limit');
});

Deno.test('provider_outage: a 5xx right after the endpoint', () => {
  assertEquals(c('get_space_usage 503 <html>Service Unavailable</html>'), 'provider_outage');
  assertEquals(c('files/upload 500 internal error after 3 tries'), 'provider_outage');
});

Deno.test('network: no answer at all', () => {
  assertEquals(c('files/upload network TypeError: fetch failed after 3 tries'), 'network');
  assertEquals(c('TypeError: error sending request for url (https://api.dropboxapi.com/2/...)'), 'network');
  assertEquals(c('TimeoutError: The signal has been aborted'), 'network');
});

Deno.test('internal: ours, including numbers that are not a status', () => {
  assertEquals(c('verify: content_hash mismatch abc != def'), 'internal');
  assertEquals(c('read 500 of 512 bytes'), 'internal');
  assertEquals(c('verify: size 503 in Dropbox != 512 sent'), 'internal');
  assertEquals(c('fn_it_dropbox_health_record: permission denied'), 'internal');
  assertEquals(c(''), 'internal');
  assertEquals(c(null), 'internal');
});
