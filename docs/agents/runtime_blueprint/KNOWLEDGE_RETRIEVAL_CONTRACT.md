# Knowledge Retrieval Contract

## Context assembly

Every employee turn receives only:

```text
company core
+ current company stage and AED 1M trajectory
+ canonical department knowledge
+ canonical role knowledge
+ task-class playbooks
+ category overlay when applicable
+ relevant validated experience
+ current live tool evidence
```

## Retrieval order

1. Resolve canonical active role.
2. Apply deterministic department/role/task/category/jurisdiction filters.
3. Fetch authoritative structured rules directly by stable ID.
4. Run lexical and vector retrieval for narrative knowledge.
5. Rerank to the final bounded set.
6. Remove duplicates and superseded records.
7. Validate source freshness and confidentiality.
8. Write retrieved IDs and versions into the decision trace.

## Models

- Text embeddings: `openai/text-embedding-3-small`
- Multimodal embeddings: `google/gemini-embedding-2`
- Routine rerank: `cohere/rerank-4-fast`
- Consequential rerank: `cohere/rerank-4-pro`

## Default budgets

- retrieve up to 20 candidates;
- rerank to 8 narrative records;
- deterministic rules are not embedded as authority;
- role/company stable prefix is cacheable;
- dynamic facts and tool results appear after the cacheable prefix.

## Fail-closed behavior

When required knowledge is missing, stale or contradictory, the agent must choose one of:

- ask clarification;
- use an approved current source;
- consult another role;
- create a knowledge-gap task;
- escalate;
- refuse the consequential action.

It must not guess.
