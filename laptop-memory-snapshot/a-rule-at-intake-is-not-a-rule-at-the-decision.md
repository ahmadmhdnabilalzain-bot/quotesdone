---
name: a-rule-at-intake-is-not-a-rule-at-the-decision
description: "A money rule placed on the row that ASKS the question refused the founder's own command and destroyed his words with it; the same rule on the row that ANSWERS it is stricter and harmless."
metadata: 
  node_type: memory
  type: project
  originSessionId: e91f68dd-ccad-4fba-8fd1-3cb4e80753e3
  modified: 2026-08-26T13:45:33.940Z
---

26 Aug 2026. `a00_founder_approval_names_a_real_refund` required EVERY `founder_approval_request`
with `action_class = 'refund_decision'` to carry `subject_ref` of the form `refund:<id>` naming a
real `refunds` row. Ninety minutes later:

```
select public.fn_founder_command_submit('management@quotesdone.com',
         'Approve refund for transaction TX-123.', 'probe', '{}'::jsonb);
ERROR 22023: subject_ref TX-123 is not of the form refund:<id>
CONTEXT: fn_founder_command_submit line 207
```

`fn_founder_command_submit` mints that inbox row from a regex over his sentence —
`coalesce((regexp_match(p_text,'(TX-[A-Za-z0-9_-]+)'))[1],'UNIDENTIFIED_TRANSACTION')` — so every
refund-shaped command he sent raised, **and the raise took the whole command with it, including the
`founder_command_message` row that records his words.** CC-009 and CC-010 red.

**Two different rows were being judged by one rule.** An INTAKE item is a question — his words,
triaged, pointing at a reference he typed. A DECISION (`state = 'approved'`) is money leaving. The
fix was to move the rule, not relax it:

* a `subject_ref` written as `refund:<id>` must still resolve — the arm that caught the PCCR-007
  probe's `refund:zz-audit-probe`;
* **no request may reach `state = 'approved'` unless its subject resolves to a real refund** — new,
  and nothing enforced it before;
* `rejected` and `withdrawn` deliberately do NOT require it, or an unbacked item is trapped in his
  inbox forever, and "this names nothing, rejected" is its correct disposal.

**The diagnostic question when a new guard fires somewhere surprising: is this row asking or
answering?** A guard on the asking row must let his words land.

Related: [[a-guard-that-fires-when-the-system-works]], [[a-new-guard-reddens-the-fixture-not-the-code]],
[[an-externally-issued-refund-is-a-fact-not-a-request]], [[every-refund-needs-the-founder]].
