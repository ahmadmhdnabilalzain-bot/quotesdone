-- Every AI call now belongs to a department, so every AI call is inside a ceiling.
--
-- fn_ai_route halts a department at halt_at_pct by looking up department_budget for the call's
-- dept_key. A call logged WITHOUT one has no budget to be measured against and cannot be halted -
-- fn_ai_spend_guard already says so in its own note, and computes the blind percentage.
--
-- MEASURED on production, this month: 59 calls with dept_key null across 16 functions, and they are
-- not obscure. They are the demand path: inquiry_intake (5), drawing_boq (4), doc_extract (5),
-- license_extract, supplier_onboard, supplier_review, supplier_negotiation, wa_inbound,
-- resend_inbound, intent_router, inquiry_parse, site_assistant, reflect, workflow_dispatch and the
-- two drawing_redact calls. The single most expensive uncapped class was inquiry_intake at AED
-- 0.43 for 5 calls - the function a customer triggers by typing.
--
-- fn_task_class already maps fn -> task_class for exactly this reason (fn_ai_route reads it to pick
-- a model). Giving it a dept_key column means the mapping lives beside the one it already has,
-- one table, one lookup, and no edge function has to learn its own department.
alter table public.fn_task_class add column if not exists dept_key text;
comment on column public.fn_task_class.dept_key is
  'Department that owns this function''s AI spend. Read by fn_ai_route when the caller passes no p_dept_key, so an un-attributed call still lands inside a department_budget ceiling instead of outside every ceiling.';

-- The assignment is by what the function DOES. Each of these dept_keys has a department_budget row
-- with monthly_aed > 0, checked before writing, so routing here can never halt a caller that was
-- previously unhaltable for lack of a budget rather than for having spare budget.
insert into public.fn_task_class (fn, task_class, dept_key, note, active) values
  ('inquiry_intake',       'rfq_routing',          'rfq_intelligence', 'customer describes a job',                 true),
  ('inquiry_parse',        'json_extraction',      'rfq_intelligence', 'structuring that description',             true),
  ('intent_router',        'json_extraction',      'rfq_intelligence', 'which flow does this message belong to',   true),
  ('site_assistant',       'general_drafting',     'rfq_intelligence', 'public site assistant',                    true),
  ('drawing_boq',          'document_extraction',  'doc_intelligence', 'bill of quantities from a drawing',        true),
  ('drawing_redact',       'document_extraction',  'doc_intelligence', 'identity removal before suppliers see it', true),
  ('drawing_redact_verify','document_extraction',  'doc_intelligence', 'adversarial check on the redacted page',   true),
  ('doc_extract',          'document_extraction',  'doc_intelligence', 'general document reading',                 true),
  ('license_extract',      'document_extraction',  'doc_intelligence', 'trade licence reading',                    true),
  ('supplier_onboard',     'procurement_reasoning','supplier_success', 'supplier joins',                           true),
  ('supplier_review',      'procurement_reasoning','supplier_success', 'supplier is assessed',                     true),
  ('supplier_negotiation', 'procurement_reasoning','supplier_success', 'supplier is negotiated with',              true),
  ('wa_inbound',           'general_drafting',     'comms',            'inbound WhatsApp',                         true),
  ('resend_inbound',       'general_drafting',     'comms',            'inbound email',                            true),
  ('reflect',              'agent_reasoning',      'exec',             'the company thinking about itself',        true),
  ('workflow_dispatch',    'agent_reasoning',      'exec',             'the engine deciding what runs next',       true)
on conflict (fn) do update set dept_key = excluded.dept_key,
                               note = coalesce(public.fn_task_class.note, excluded.note),
                               updated_at = now();
