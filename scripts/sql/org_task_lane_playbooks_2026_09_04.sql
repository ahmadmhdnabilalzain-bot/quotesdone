-- THE PLAYBOOKS THE ORG_TASK BACKLOG ACTUALLY NEEDS (MASTER_PLAN A1 / §4.3), 4 Sep 2026.
--
-- MEASURED first, then written. The 605-671 `assigned` org_tasks are not a heap: they are 55
-- (event, entity, department) clusters, every one of them raised by fn_event_dispatch with the same
-- three-part detail — "Event <e> (<entity> <id>) raised by <who> at <when>. You subscribe to this
-- because: <reason>. Assessed impact: ... Act on it or close it with a reason." The largest clusters:
--   supplier.approved/lead/marketplace 56, security.event/incident/legal 48, quote.received/quote/
--   marketplace 42, outcome.graded/outcome_record/data_intel 41, content.published/org_task/exec 40 and
--   /growth 39, deploy.completed/deploy/product_eng 27, outcome.graded/exec 21, priority.updated/
--   event_chain/people_ops 18, test.failed/scheduled_run/product_eng 15, payment.received/transaction/
--   finance 15 — plus kpi.missed across six departments (58) and the KPI-review's own
--   "KPI missed: <name> (<owner>)" recommend tasks (21) and the weekly exec_review tasks (11).
--
-- Each row below is ONE department's standing determination for ONE subscription. Two things make it
-- retrievable by fn_apply_playbook without weakening anything:
--   * MEANING (cosine >= 0.85): the playbook opens in the task's own register — the event name, the
--     entity, and the department's OWN subscription reason, taken verbatim from the tasks themselves
--     rather than invented here. The reason is the company's existing statement of why this department
--     receives this event; echoing it is accurate, not decorative.
--   * WORDS (>= 2 and >= 30% of the task's lexemes): the event key, the entity noun, the action class
--     and the department key all appear literally, because the corroboration text
--     (fn_org_task_subject) is exactly those.
-- The determination itself is the department's real procedure, written as a numbered ladder a
-- deterministic reader can follow, with an explicit closing condition and an explicit escalation.
--
-- SCOPE. module='org_task_lane', scope_type='department'. These are the ORG_TASK LANE's playbooks —
-- they do not touch metric_lifecycle, change_deployment or strategic_review, whose step playbooks are
-- owned elsewhere. Idempotent: re-running updates content in place, and the embedding trigger
-- (a10_ops_knowledge_embedding_status) nulls the vector so kb_embed (cron 315, every minute) re-embeds.
--
--   node scripts/apply_sql.mjs scripts/sql/org_task_lane_playbooks_2026_09_04.sql --apply --ddl

begin;

with observed as (
  -- the clusters as the backlog actually presents them, and each department's own reason
  select split_part(t.title, ' on ', 1)                              as ev,
         split_part(split_part(t.title, ' on ', 2), ' ', 1)          as entity,
         t.dept_key,
         t.action_class,
         count(*)                                                    as n,
         min(substring(t.detail from 'because: (.*?)\. Assessed'))    as why
    from public.org_tasks t
   where t.status in ('assigned','in_progress','blocked')
     and t.title like '% on %'
     and t.action_class is not null
   group by 1,2,3,4
), det(ev, body) as (values
 ('supplier.approved', $b$THE DETERMINATION
1. Read the approved supplier's declared categories and emirate off the lead, and treat the approval as a coverage change, not as an inbox item: category coverage is the number this department is measured on.
2. Recount approved suppliers in each category the lead covers. A category at ten or more approved suppliers is live and needs no further invite pressure; a category under ten is still short and keeps its place in the invite plan.
3. Where the category crossed into live, stop planning invites against it and say so on the task — invite capacity spent on a covered category is capacity not spent on an empty one.
4. Where the category is still short, record the remaining gap (approved today versus ten) so the next invite ramp is sized from the gap, not from a guess.
5. Check the supplier is genuinely matchable: an approved supplier with no capability rows cannot receive an RFQ, so an approval that does not change matching is a coverage number that lies. Raise a named capability-enrichment task if it is missing.
6. Do not contact the supplier from here and do not change its status. Approval already happened; this task is the coverage consequence of it.$b$),

 ('supplier.applied', $b$THE DETERMINATION
1. Treat the application as an unverified claim until the licence says otherwise. Read the trade licence off the lead: issuing authority, expiry date, and the activities it actually permits.
2. Refuse on expiry first. An expired or missing licence is a refusal with a named reason, and nothing else about the application matters until it is fixed.
3. Check that the licence activity covers the categories applied for. A mismatch is a specific, named rejection — "licence permits X, application claims Y" — never a vague decline.
4. Check the applicant is contactable: an email or a mobile that resolves. A supplier nobody can reach cannot quote and must not sit in the approved pool.
5. Where every check passes, the application is ready for the approval lane; where one fails, record which one, because the reason is what the supplier is told and what the next reviewer needs.
6. Screen the supplier-facing payload for anything that would breach the anonymous-marketplace promise before it is ever shown to a buyer.$b$),

 ('quote.received', $b$THE DETERMINATION
1. Normalise the quote before comparing it: price, currency, unit basis, lead time, validity, and exclusions. A lump sum with no breakdown is not comparable and is not a usable quote.
2. Check the quote against the RFQ's scope. A quote priced for different scope misleads the buyer and must be marked non-comparable rather than silently ranked.
3. Enforce anonymity: the quote must not carry the supplier's identity, licence name or contact details before a paid reveal.
4. Refuse any delivery or price promise the supplier did not make. Superlatives and guarantees are removed, not softened.
5. Recount the field for this RFQ. Three comparable quotes make the field revealable; fewer means the RFQ is still open and the matching fan-out needs another pass rather than an early reveal.
6. Where the field is now sufficient, the RFQ moves to the deterministic best-three comparison. Where a quote failed a gate, record which gate, because that reason is what the supplier is asked to fix.$b$),

 ('rfq.created', $b$THE DETERMINATION
1. Own completeness before any supplier is contacted. Read the inquiry for the four things a supplier cannot price without: category, quantity, emirate or delivery location, and a timeline.
2. Any of the four missing makes this an incomplete inquiry. Record which one is missing — that is the single question to put back to the buyer, and one specific question converts far better than a request to "add more detail".
3. Check the inquiry names no supplier and carries no identity that would breach the anonymous marketplace.
4. Confirm the category resolves to a live category with approved suppliers behind it. An inquiry in a category with no approved suppliers cannot be matched and needs the coverage gap recorded against it, not a fan-out that reaches nobody.
5. Where the inquiry is complete and the category is live, it is ready to classify and match; where it is not, the named gap is the deliverable.$b$),

 ('rfq.classified', $b$THE DETERMINATION
1. Read the classification the router assigned to the inquiry and check it against the inquiry's own words. A classification that does not follow from the text is the defect to catch here, before suppliers are contacted.
2. Grade the match set the classification produced: how many approved, matchable suppliers it reaches in that category and emirate. A classified inquiry that reaches nobody is a coverage finding, not a routing success.
3. Where the classification is wrong, record the correct category and the evidence for it from the inquiry text; that correction is also a training example for the router.
4. Where the classification is right but the match set is thin, record the category coverage gap so the invite plan is sized from it.
5. Do not contact suppliers from here. This task grades the classification and its reach; the fan-out is the dispatcher's.$b$),

 ('customer.registered', $b$THE DETERMINATION
1. A newly registered customer has no history, so the first request is the one that decides whether they ever post a second. Own the first-request guidance.
2. Check the registration is complete enough to be served: a reachable email, a mobile that verifies, and a company name. Record which is missing rather than assuming it will be supplied later.
3. Confirm the customer can reach the inquiry form and that at least one live category is available to them — a registration into a marketplace with no covered category is a dead end and must be recorded as a coverage finding.
4. Prepare the first-request guidance this customer needs: what a good RFQ contains in their apparent category, and what happens after they post it (matching, quotes, the reveal fee).
5. Send nothing from here. This lane writes the determination; the outbound path is a separate, gated act.$b$),

 ('payment.received', $b$THE DETERMINATION
1. A payment is a revenue-recognition decision, not a notification. Read the transaction: amount, currency, what it was for, and which side paid it.
2. Recognise the reveal fee against the transaction it belongs to, and check the three-percent basis is the revealed quote's value — a fee that does not reconcile to its quote is the defect to catch here.
3. Confirm the payment reconciles to a Stripe event the platform actually received, not to an expectation. An unmatched payment is an exception, and it is recorded as one.
4. Check the consequence the payment is supposed to trigger has happened: the reveal is orchestrated, both parties are notified, and the customer can read the contact details they paid for.
5. Where anything above did not happen, that is the finding, named, with the transaction identified. Do not issue, adjust or refund anything from here: every refund is the founder's decision.$b$),

 ('content.published', $b$THE DETERMINATION
1. Record what went out. This department is accountable for published output, so the standing determination is a register entry — subject, audience, and which company goal it serves — not a re-review of work already approved.
2. Check the published item against the brand and the anonymity promise: no supplier identity, no price or delivery guarantee the company cannot keep, no unverifiable superlative.
3. Check it serves a live company goal. Output that serves none is the finding worth recording, because it is capacity spent outside the plan.
4. Note that the emitter behind this event was retired on 4 September 2026: fn_review_submit used to emit content.published on EVERY approved review of any subject, which is why this backlog is dominated by org_task subjects rather than real posts. A task in this cluster whose subject is an org_task is the old emitter's echo — record it as such and close it; the real publish path now emits campaign.published from a posted content draft.
5. Publish nothing from here and revise nothing from here. This lane keeps the register; the publishing path is separate and gated.$b$),

 ('campaign.launched', $b$THE DETERMINATION
1. A launched campaign is an attribution obligation. Record the campaign against the company goal it is spending toward, so the spend has a named owner and a named purpose before it accrues.
2. Check the campaign is inside the ad ceiling the founder set. Spend has a hard cap that is his number or zero; a campaign that would exceed it is stopped, not watched.
3. Record the baseline the campaign will be judged against — inquiries, registrations or supplier applications in the period before launch — because a launch with no baseline cannot be graded later.
4. Confirm the campaign is one of ours: the account carries the founder's personal campaigns too, and the campaign filter is what keeps them out of company reporting.
5. Do not change budgets, activate or pause anything from here. This determination is the attribution record; the spend manager owns the money.$b$),

 ('kpi.missed', $b$THE DETERMINATION — DIAGNOSE THE MISS, THEN CLOSE THE GAP OR REVISE THE TARGET
1. Read the metric's own numbers off the task: target, actual, attainment percentage, cadence, and the company goal it serves. The diagnosis starts from the attainment band, because the band decides which kind of cause is possible.
2. Attainment under five per cent is NOT under-performance. It means the input that feeds this metric has not started — a funnel with no inquiries, a category with no suppliers, a campaign with no spend. The closing action is upstream of the metric, and a target set against an input that does not exist yet is the finding.
3. Attainment between five and fifty per cent is a capacity or conversion shortfall: the process runs but converts far below plan. The closing action names the step in the process that loses the volume, and what would raise it.
4. Attainment between fifty and one hundred per cent is a near miss against a target set above current capability. Here the honest options are a specific improvement with a size attached, or a revised target with the evidence for the revision — never a restatement of the same target with more hope behind it.
5. Attainment at or above one hundred per cent with a MISSED verdict is a measurement fault: the metric is measured or dated wrongly, and the fix is to the measure, not to the work.
6. Whichever band applies, the deliverable is one closing action with an owner, or one revised target with evidence. A KPI task closes with a named root cause band; it never closes with "monitor it".
7. Do not restate the miss as a new metric and do not open a second task about the same number: one open gap per metric is the rule the KPI review already enforces.$b$),

 ('metric.alert', $b$THE DETERMINATION
1. A metric that went red on a scorecard is an alert, and an alert without a first responder is noise. Read which measure moved, by how much, and against which threshold.
2. Separate a red caused by the measure from a red caused by the company: a scorecard reading a view that changed shape, or a window that moved, is a measurement fault and is fixed in the measure.
3. Where the movement is real, name the process behind the number and the step in it that moved. A red with no named process cannot be acted on by anyone.
4. Check whether an open task already covers this number. Alerting twice on one gap doubles the backlog and halves the attention it gets.
5. Record the determination and, where the movement is real and uncovered, open exactly one named task with an owner.$b$),

 ('goal.at_risk', $b$THE DETERMINATION
1. A company goal tracking off target is an executive decision, not a status line. Read the goal, its horizon, and how far behind the run rate it is.
2. Distinguish a goal that is behind from a goal that is unreachable: a goal whose remaining horizon cannot arithmetically produce the target needs restating, and saying so early is the value of this signal.
3. Name the one department whose throughput most moves this goal, and the one number in that department that would move it. A goal at risk with no named lever is a worry, not a plan.
4. Check the goal still serves the company's stated objective. A goal nobody would set today should be retired rather than chased.
5. The deliverable is one lever with an owner, or a restated goal with the arithmetic behind it.$b$),

 ('os.health_changed', $b$THE DETERMINATION
1. An operating system changing health state is the leadership signal that something inside it moved. Read which OS, from which state to which, and what the state is computed from.
2. Green to amber or red: find the driver the health computation names — unmeasurable KPIs, unclosed KPI gaps, stale work, or open risks — and treat the largest driver as the subject.
3. Stale work is the driver most often ignored and the cheapest to clear: tasks open beyond fourteen days are either done, blocked on something nameable, or should never have been opened.
4. Red to amber or green is also a determination: record what closed, so an improvement is attributed rather than assumed.
5. Do not open a task per driver. One task per health change, naming the largest driver and its owner, is what keeps this signal readable.$b$),

 ('health.degraded', $b$THE DETERMINATION
1. Degraded health is an availability signal and it is worked as one: read which check degraded, when it started, and whether it is still degraded now.
2. Check whether the degradation is the platform or the probe. A check that fails while the surface it measures is up is a broken instrument, and fixing the instrument is the real work.
3. Where the platform is genuinely degraded, identify the surface a customer or supplier would notice, because that is what decides urgency in a pre-launch marketplace with real registrations open.
4. Confirm whether an incident record already exists for this degradation. Two records for one outage split the response.
5. Record containment and the verification that the surface recovered. A degradation closed without a recovery check is a guess.$b$),

 ('security.event', $b$THE DETERMINATION
1. Own the incident record. Read the event: which control failed, what it protects, and whether the failure was detected by a control or by a consequence.
2. Grade severity by exposure, not by noise: whether personal data, credentials, money or supplier identity could have left the platform. That grade is what starts or does not start the regulatory notification clock under the UAE data-protection regime.
3. Where the clock starts, record the moment of awareness. The clock runs from awareness, and an unrecorded awareness time is the single most expensive omission in a breach file.
4. Name the control that failed and whether it is still failing. A closed incident whose control was never restored is a repeat incident waiting.
5. Record containment, the evidence of it, and the residual exposure. A security task closes on evidence, never on an assurance.
6. Where the event is a probe, a scanner, or a refused attempt, say so plainly and close it — a control that worked is a record, not an incident.$b$),

 ('test.failed', $b$THE DETERMINATION
1. A failed scheduled run is triaged before it is fixed: read which run failed, its error, and whether it has failed before.
2. Classify it as one of three things and say which: an infrastructure fault (a timeout, a rate limit, a transport error), a flake that passes on re-run, or a real defect in what the run measures.
3. An infrastructure fault is not a company finding and must not be reported as one — that is how a real defect gets lost in a list of transport timeouts.
4. A repeat failure of the same run is a different subject from a first failure: it is a quality-gate problem, and it stays open until the run is either fixed or retired.
5. Where it is a real defect, name the behaviour that is wrong, not the assertion that failed. The assertion is the symptom.
6. Do not disable the check to clear the signal. A check turned off to make a board green is worse than the failure it hid.$b$),

 ('deploy.completed', $b$THE DETERMINATION
1. A verified deploy is a work order: the deploy happened, and the next hour is when its consequences appear.
2. Confirm each deployed function actually moved version. A deploy whose version did not bump did not happen, whatever the log printed.
3. Read the error rate for the deployed functions since the deploy and compare it with the hour before. A new error signature that appeared after the deploy is the deploy's, until proven otherwise.
4. Check the rollback path is available: the previous version exists and the change is reversible. Rollback readiness is confirmed at deploy time, not discovered during an incident.
5. Where a new failure signature appeared, name it and the function, and treat rollback as the default rather than as an escalation.
6. Where the deploy is clean, record it as verified and close. A verified deploy is a real outcome and belongs in the record.$b$),

 ('rollback.required', $b$THE DETERMINATION
1. A rollback-required signal means a graded outcome came back worse than its baseline. Read the outcome record: what was changed, what was expected, and what was measured.
2. Confirm the comparison is fair — same window, same population — before reversing anything. A rollback triggered by a shifted baseline reverses a change that was working.
3. Where the regression is real, reverse the change rather than compensate for it, and record the version reverted to.
4. Record what the regression teaches: a change that measured worse is evidence, and it belongs against the decision that proposed it.
5. Do not reverse anything that moves money or a customer promise from this lane; that path is gated.$b$),

 ('outcome.graded', $b$THE DETERMINATION
1. A graded outcome is the only place the company learns whether a decision worked. Read the record: the decision, the expectation, the measurement, and the grade.
2. Attach the grade to the decision that produced it. A grade that never reaches the decision is a measurement nobody acts on.
3. Where the outcome beat its expectation, name what caused it and whether it repeats. An unattributed success is not reusable.
4. Where the outcome missed, distinguish a wrong decision from a right decision executed badly from an expectation that was never realistic. The three have different corrections and confusing them is how a company learns the wrong lesson.
5. Feed the grade into the responsible agent's record so repeated misses raise a remediation rather than being averaged away.
6. The deliverable is the lesson, in one sentence, in the form "when X, do Y, because the measurement showed Z".$b$),

 ('priority.updated', $b$THE DETERMINATION
1. A consolidated event chain closed across more than one operating system. That is the company doing something end to end, and it is the moment to re-read priorities against evidence rather than intent.
2. Read what the chain cost — the work it consumed across departments — and what it produced. A chain that consumed a lot and produced little is the finding.
3. Compare the result with the priority order the company is currently working to. If the evidence moved, restate the priorities; if it did not, say so explicitly, because a confirmed priority is also a decision.
4. Re-order the open backlog only through the priority field the assignment sweep already reads. A re-prioritisation that does not change who is served next has changed nothing.
5. Do not open new work from here. This determination changes the order of work that already exists.$b$),

 ('process.repeated_failure', $b$THE DETERMINATION
1. A repeated failure is waste, and waste is removed rather than monitored. Read what failed, how often, and over what window.
2. Find the shared cause. Repeated failures with one cause are one problem; repeated failures with several causes are a fragile process, and the two are fixed differently.
3. Decide between fixing the step, removing the step, or removing the process. A process that fails repeatedly and produces nothing anybody reads should be retired, and retiring it is a real outcome.
4. Where the failure is in a self-review or a scheduled routine, check the routine still has a reader. A routine whose output nobody consumes is the cheapest thing in the company to delete.
5. The deliverable names the cause and the decision — fix, remove, or retire — with the count that justifies it.$b$),

 ('improvement.proposed', $b$THE DETERMINATION
1. A proposal nobody receives is a proposal nobody triages. Read the proposal and give it an owner in this department or refuse it with a reason.
2. Restate it as a testable hypothesis: what changes, what is expected to move, by how much, and in what window. A proposal that cannot be graded later should not be accepted now.
3. Size it honestly against what the company can do this week, not against what it could do with more people.
4. Check it does not duplicate an open improvement. Two proposals for one problem split the effort and double the review.
5. Accepted proposals get an outcome record so the grade comes back automatically; refused proposals get the reason recorded, because the same idea will arrive again.$b$),

 ('knowledge.updated', $b$THE DETERMINATION
1. Institutional memory changed underneath the corpus, so the determination is a currency check, not a reading exercise.
2. Identify which knowledge records the change supersedes. A corpus that holds both the old and the new answer will retrieve the old one roughly half the time.
3. Mark the superseded records rather than deleting them: supersession keeps the history and takes the stale answer out of retrieval, which is exactly what is wanted.
4. Check the updated knowledge is embedded and runtime-eligible, because a record that is not embedded cannot be retrieved by meaning and therefore does not exist to the agents.
5. The deliverable names what was superseded and confirms the replacement is retrievable.$b$)
), extra(ev, body) as (values
 ('KPI missed', $b$THE DETERMINATION — DIAGNOSE THE MISSED KPI, THEN CLOSE THE GAP OR REVISE THE TARGET
1. The task carries the owner, the target, the actual, the attainment percentage, the cadence and the company goal the KPI serves. Diagnose from the attainment band, because the band determines which class of cause is even possible.
2. Attainment under five per cent means the input that feeds this KPI has not started. The cause is upstream of the metric — no inquiries, no approved suppliers in the category, no spend — and a target set against an input that does not exist yet is itself the finding.
3. Attainment between five and fifty per cent is a capacity or conversion shortfall: real activity converting far below plan. Name the step in the owner's process that loses the volume and what would raise it.
4. Attainment between fifty and one hundred per cent is a near miss against a target above current capability. The honest deliverable is one specific improvement with a size attached, or a revised target with the evidence for the revision.
5. Attainment at or above one hundred per cent with a missed verdict is a measurement fault, and the fix belongs to the measure rather than to the work.
6. Close the gap or revise the target: those are the only two closing moves. A KPI task closes with a named root-cause band and one action with an owner; it never closes with "continue to monitor".
7. Do not open a second task for the same metric. The weekly KPI review already refuses to raise one while an open task exists, and a duplicate defeats it.$b$),
 ('OS review', $b$THE DETERMINATION
1. The weekly operating-system review lists findings with counts: unmeasurable KPIs, KPIs missing target, stale work open beyond fourteen days, and open risks owned inside the OS. Each finding is closed or brought evidence — those are the only two moves.
2. Unmeasurable KPIs come first. A KPI with no measure cannot be missed or met, so it silently removes itself from the scoreboard; either give it a measure or retire it.
3. KPIs missing target are counted here but diagnosed in their own tasks. The review's job is to confirm each has an open, owned task and that none has two.
4. Stale work is the largest number in most reviews and the cheapest to clear: a task open beyond fourteen days is finished, blocked on something nameable, or should never have been opened. Say which, per batch, not per task.
5. Open risks owned inside this OS need a named owner and a next review date, or they are not being carried by anyone.
6. The deliverable is one line per finding: closed, or the evidence that it is being carried and by whom.$b$),
 ('Exec meeting', $b$THE DETERMINATION
1. The exec meeting item carries the operating system's health, its owner and its drivers. Prepare the answer the meeting needs, not a restatement of the drivers it already lists.
2. For each driver, state whether it moved since the last meeting and by how much. A driver with no movement between meetings is either not being worked or not worth listing.
3. Bring one decision per item. An operating system that arrives at the meeting with only status has spent the meeting's attention and returned nothing.
4. Name the one number this OS will move before the next meeting, and who owns it. That number is what the next meeting reads first.
5. Where the health is amber or red, say what would make it green and whether the company can afford that this period. An unaffordable remedy stated plainly is more useful than an affordable one that will not work.$b$)
), raw_rows as (
  select 'event'::text as kind, o.ev, o.entity, o.dept_key, o.action_class, o.n, o.why, d.body
    from observed o join det d on d.ev = o.ev
  union all
  -- the KPI-review, OS-review and exec-meeting tasks are not "<event> on <entity>" shaped: they are
  -- titled work. They are clustered on their title prefix and scoped to the departments that hold them.
  select 'title'::text, e.ev, 'task', t.dept_key, t.action_class, count(*), null, e.body
    from public.org_tasks t
    join extra e on t.title like e.ev || '%'
   where t.status in ('assigned','in_progress','blocked') and t.action_class is not null
   group by e.ev, t.dept_key, t.action_class, e.body
), rows as (
  -- ONE playbook per (event, department). The same subscription can arrive against more than one
  -- entity noun or action class (goal.at_risk names both 'goal' and 'department'; payment.received is
  -- 'transaction' everywhere), so every noun and class this department actually sees is named in the
  -- record — a task whose title carries the rarer noun must corroborate too.
  select r.kind, r.ev, r.dept_key,
         (array_agg(r.entity order by r.n desc, r.entity))[1]        as entity,
         (array_agg(r.action_class order by r.n desc))[1]            as action_class,
         string_agg(distinct r.entity, ', ' order by r.entity)       as entities,
         string_agg(distinct r.action_class, ', ' order by r.action_class) as classes,
         sum(r.n)                                                    as n,
         (array_agg(r.why order by r.n desc) filter (where r.why is not null))[1] as why,
         min(r.body)                                                 as body
    from raw_rows r
   group by r.kind, r.ev, r.dept_key
)
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, module, record_type, title, content,
  structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
  version, effective_date, keywords, layer, jurisdiction, source_type, source_authority,
  source_freshness, confidentiality, runtime_eligible, deterministic, supersession_state)
select
  'ops-orgtask-lane-' || r.kind || '-' || r.dept_key || '-' || lower(regexp_replace(r.ev, '[^A-Za-z0-9]+', '-', 'g')),
  'department', r.dept_key, r.dept_key, 'org_task_lane', 'decision_playbook',
  r.ev || ' in ' || r.dept_key || ' — the org_task lane determination',
  'Event ' || r.ev || ' raised on a ' || r.entity || '. The ' || coalesce(dp.name, r.dept_key)
    || ' department (' || r.dept_key || ') subscribes to ' || r.ev
    || coalesce(' because: ' || r.why || '.', '.')
    || ' This is that department''s standing determination for the subscription — what ' || r.dept_key
    || ' does with an ' || r.action_class || ' org_task titled "' || r.ev || ' on ' || r.entity
    || ' ..." whose detail ends "Act on it or close it with a reason". It is applied deterministically, '
    || 'with no model call, at QuotesDone, the UAE anonymous B2B quotation marketplace.'
    || E'\n' || 'SUBJECTS IN THIS DEPARTMENT: ' || r.ev || ' arrives here against ' || r.entities
    || ' (action class ' || r.classes || '), ' || r.n || ' open at the time this was written.'
    || E'\n\n' || r.body || E'\n\n'
    || 'CLOSING THIS TASK: the ladder above IS the response to a routine ' || r.ev
    || ' notification for ' || r.dept_key || '. Record the determination, take the numbered steps this '
    || 'department already automates, and close the task. Anything the ladder says needs its own owner '
    || 'becomes one named task — never close by ignoring it, and never leave the task open as a reminder.'
    || E'\n' || 'ESCALATE INSTEAD OF CLOSING WHEN: the ' || r.entity || ' moves money, changes a customer '
    || 'promise, suspends or bans a supplier, or needs the founder. Every refund is the founder''s '
    || 'decision, and those leave this lane for the gated path.'
    || E'\n' || 'CONFIDENCE: this is a standing departmental determination, not a per-record judgement. '
    || 'It is recorded as a low-confidence deterministic disposition and queued for review, so a '
    || 'reviewer can overturn it on the specific ' || r.entity || ' in front of them.',
  jsonb_build_object(
    'lane', 'org_task', 'event', r.ev, 'entity', r.entity, 'dept_key', r.dept_key,
    'action_class', r.action_class, 'open_tasks_at_authoring', r.n,
    'applies_to', 'org_tasks rows raised by fn_event_dispatch for this subscription',
    'closing_moves', jsonb_build_array('record the determination', 'take the automated steps',
                                       'open one named task for anything needing its own owner'),
    'never', jsonb_build_array('move money', 'send to a customer or supplier', 'suspend a supplier',
                               'approve a refund')),
  array['MASTER_PLAN §4.3','org_task lane','fn_event_dispatch'],
  'active', 'author_verified', 'supervised', 'low', '1.0', current_date,
  array[r.ev, r.entity, r.dept_key, r.action_class, 'org_task', 'org_task lane', 'determination'],
  'decision_playbook', 'AE', 'authored_expert', 'quotesdone_operating_model', 'current', 'internal',
  true, true, 'current'
  from rows r
  left join public.org_departments dp on dp.dept_key = r.dept_key
on conflict (record_id) do update
  set title           = excluded.title,
      content         = excluded.content,
      structured_data = excluded.structured_data,
      keywords        = excluded.keywords,
      dept_key        = excluded.dept_key,
      scope_key       = excluded.scope_key,
      module          = excluded.module,
      record_type     = excluded.record_type,
      layer           = excluded.layer,
      runtime_eligible = true,
      deterministic    = true,
      supersession_state = 'current',
      implementation_status = 'active';

commit;
