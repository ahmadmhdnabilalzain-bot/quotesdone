# How the System Should Work After Import

The corpus is not meant to be loaded into one prompt.

## Normal customer message

Example:

> "I need some material to stop water coming through a warehouse roof."

## Runtime sequence

1. Preserve the original message.
2. Deterministic aliases and taxonomy identify possible routes:
   - waterproofing;
   - roofing.
3. If confidence is close, ask one clarification:
   - repair an existing leak, or install a complete roofing system?
4. Select the relevant subcategory records.
5. SQL/decision rules check which mandatory fields are missing.
6. Ask only the next required question.
7. Reuse values extracted from documents.
8. When complete, produce a normalized supplier brief.
9. Dispatch only after completeness, privacy and escalation gates pass.

## AI usage target

- SQL, rules, templates and retrieval: normal path.
- Small local model: ordinary-language parsing when needed.
- Premium model: complex drawings, unusual ambiguity, conflicting documents or professional exceptions.

The knowledge lives in Supabase. The model is mainly an interpreter and exception handler.
