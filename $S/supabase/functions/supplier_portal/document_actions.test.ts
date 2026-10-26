// document_actions.test.ts — Remove is refused exactly where the record is sealed, and a version
// row names what it kept.   deno test supabase/functions/supplier_portal/document_actions.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { removeRefusal, versionRow } from './document_actions.ts';

Deno.test('removeRefusal: a mandatory document of an APPROVED supplier is sealed; the same document of a pending one is not', () => {
  const sealed = removeRefusal({ kind: 'license', known: true, onFile: true, required: true, approval_status: 'approved' });
  assertEquals(sealed?.code, 'mandatory_of_approved');
  assertEquals(typeof sealed?.message_ar, 'string');
  assertEquals(removeRefusal({ kind: 'license', known: true, onFile: true, required: true, approval_status: 'pending' }), null);
  assertEquals(removeRefusal({ kind: 'license', known: true, onFile: true, required: true, approval_status: 'action_required' }), null);
  assertEquals(removeRefusal({ kind: 'license', known: true, onFile: true, required: true, approval_status: null }), null);
});

Deno.test('removeRefusal: an optional document of an approved supplier may go; nothing on file and unknown kinds are refused by name', () => {
  assertEquals(removeRefusal({ kind: 'insurance', known: true, onFile: true, required: false, approval_status: 'approved' }), null);
  assertEquals(removeRefusal({ kind: 'insurance', known: true, onFile: false, required: false, approval_status: 'approved' })?.code, 'nothing_on_file');
  assertEquals(removeRefusal({ kind: 'passport', known: false, onFile: false, required: false, approval_status: 'approved' })?.code, 'unknown_kind');
});

Deno.test('versionRow: the doc_versions row keeps the previous path, name and expiry under <lead>:<kind>', () => {
  const r = versionRow(124775, { event: 'replaced', kind: 'insurance', path: 'certs/124775/1_x.pdf', name: 'x.pdf', expiry: '2026-12-31', at: '2026-09-21T00:00:00Z' }, 3);
  assertEquals(r.entity_type, 'supplier_document');
  assertEquals(r.entity_id, '124775:insurance');
  assertEquals(r.version, 3);
  assertEquals(r.snapshot.path, 'certs/124775/1_x.pdf');
  assertEquals(r.changed_fields, ['path']);
  assertEquals(versionRow(1, { event: 'removed', kind: 'iso', path: 'p', name: null, expiry: null, at: 'x' }, 1).changed_fields, ['removed']);
});
