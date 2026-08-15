
# Event Outbox and Delivery Contract

Business state and the corresponding outbox event must be written in the same transaction.

Required delivery states:

- pending;
- claimed;
- delivered;
- retry_wait;
- dead_letter;
- cancelled;
- superseded.

Each event has a stable dedupe key. Delivery workers must be safe under duplicate, delayed and out-of-order execution. First failure remains visible even if retry succeeds.

A notification, webhook or task-delivery attempt is not counted as successful unless the downstream record/result exists. A null row with no database error is not success.
