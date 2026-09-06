import { q } from './q.mjs';
const j = (o) => `'${JSON.stringify(o).replace(/'/g,"''")}'::jsonb`;
const show = (label, rows) => { const r = rows[0]||{}; console.log(label.padEnd(58) + String(r.state||r.passed).padEnd(16) + ' ' + String(r.refusal_code||'-').padEnd(38) + String(r.reason||'').slice(0,80)); };
const rule = async (id,ctx) => (await q(`select state, ok, reason, refusal_code from public.fn_phase_d_rule_check('${id}', ${j(ctx)})`));
const gate = async (id,ev) => (await q(`select state, passed, reason, refusal_code from public.fn_phase_d_gate_evaluate('${id}', ${j(ev)})`));

console.log('--- BR-011 hidden metadata / PII ---');
show('name only in a PDF /Info (was ok=TRUE before O07)', await rule('BR-011',{supplier_payload:'/Author (ZZ DEMO Omar Bin Faisal) /Creator (AL NAHDA CONSULTANTS)'}));
show('email + mobile', await rule('BR-011',{supplier_payload:'zz.customer@example.invalid 0501234567'}));
show('filesystem username', await rule('BR-011',{supplier_payload:'C:\Users\zz.demo.customer\AutoCAD'}));
show('clean payload (control)', await rule('BR-011',{supplier_payload:'window schedule, quantities and scope only'}));
show('clean payload + dirty revision', await rule('BR-011',{supplier_payload:'scope only', file_revision_ref:'zz-demo-rev-photo-unredacted'}));
show('clean payload + safe revision (control)', await rule('BR-011',{supplier_payload:'scope only', file_revision_ref:'zz-demo-rev-photo-safe'}));
show('no payload named', await rule('BR-011',{}));

console.log('--- BR-012 / GATE-013 file set ---');
show('BR-012 package unknown', await rule('BR-012',{safe_package_ref:'zz-nope', safe_package_approved_by:'compliance_and_privacy_officer'}));
show('GATE-013 dirty package', await gate('GATE-013',{safe_package_ref:'zz-demo-pkg-priv-005-dirty', safe_package_approved_by:'compliance_and_privacy_officer', actor_role_id:'marketplace_content_privacy_reviewer'}));
show('GATE-013 clean package (control)', await gate('GATE-013',{safe_package_ref:'zz-demo-pkg-priv-005-clean', safe_package_approved_by:'compliance_and_privacy_officer', actor_role_id:'marketplace_content_privacy_reviewer'}));
show('GATE-013 clean pkg, approver IS author', await gate('GATE-013',{safe_package_ref:'zz-demo-pkg-priv-005-clean', safe_package_approved_by:'marketplace_content_privacy_reviewer', actor_role_id:'marketplace_content_privacy_reviewer'}));

console.log('--- BR-018 normalisation ---');
show('BR-018 no revision named', await rule('BR-018',{quote_revision_ref:'', platform_edited:'false'}));
show('BR-018 caller claims unedited on a fake ref', await rule('BR-018',{quote_revision_ref:'zz-not-a-revision', platform_edited:'false'}));

console.log('--- GATE-027 / GATE-028 legal source ---');
show('GATE-027 stale tax source', await gate('GATE-027',{reconciliation_ref:'zz-r', control_exception_ref:'zz-c', tax_source_ref:'zz-demo-fta-corporate-tax-expired'}));
show('GATE-027 current tax source (control)', await gate('GATE-027',{reconciliation_ref:'zz-r', control_exception_ref:'zz-c', tax_source_ref:'zz-demo-fta-corporate-tax-current'}));
show('GATE-027 no source cited (unchanged)', await gate('GATE-027',{reconciliation_ref:'zz-r', control_exception_ref:'zz-c'}));
show('GATE-028 non-authoritative source', await gate('GATE-028',{legal_review_ref:'zz-l', legal_source_ref:'zz-demo-blog-vat-opinion'}));
show('GATE-028 superseded source', await gate('GATE-028',{legal_review_ref:'zz-l', legal_source_ref:'zz-demo-fta-corporate-tax-2024'}));
show('GATE-028 undated source', await gate('GATE-028',{legal_review_ref:'zz-l', legal_source_ref:'zz-demo-undated-circular'}));
show('GATE-028 no source cited (unchanged)', await gate('GATE-028',{legal_review_ref:'zz-l'}));

console.log('--- regression: gates that must be untouched ---');
for (const g of ['GATE-022','GATE-023','GATE-024','GATE-025','GATE-026','GATE-029','GATE-030']) {
  const c = (await q(`select evidence_keys from public.phase_d_gate_contract where gate_id='${g}'`))[0];
  const ev = {}; (c.evidence_keys||[]).forEach(k=>ev[k]='zz');
  show(g+' with all declared evidence', await gate(g, ev));
}
