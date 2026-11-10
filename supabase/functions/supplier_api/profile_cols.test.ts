// M1 of the 10 Nov 2026 security checklist audit: save_profile copies every PROFILE_COLS key from the request body
// onto the supplier's row (mass assignment through an allow-list). A storage path on that list lets a supplier point
// their row at ANY object in the private supplier-docs bucket, another supplier's licence included, and have
// supplier_portal sign it back. Paths are written only by the upload actions, which build them under the supplier's
// own prefix. This fails if any *_path column comes back onto the list.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { PROFILE_COLS } from './lib/fields.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

Deno.test('no storage path can be written through save_profile', () => {
  assertEquals(PROFILE_COLS.filter((c) => /_path$|_paths$/.test(c)), []);
});

Deno.test('save_profile writes only PROFILE_COLS from the body, never the body itself', () => {
  const src = functionSource('supplier_api');
  const start = src.indexOf("if (action === 'save_profile')");
  assert(start >= 0, 'save_profile handler not found');
  const body = src.slice(start, start + 6000);
  assert(/for \(const c of PROFILE_COLS\) if \(body\[c\] !== undefined\) upd\[c\] = body\[c\];/.test(body), 'save_profile must build its update from PROFILE_COLS');
  assert(!/\.\.\.body\b/.test(body), 'save_profile must not spread the request body into the update');
});
