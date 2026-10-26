-- The registration workflow, classified without waking fifty-six parked runs
-- =========================================================================
--
-- Fifth slice of org_task #1394, and the first where the definition and the parked runs are treated
-- DIFFERENTLY - on purpose.
--
-- customer_registration is unlike the four workflows classified before it: it has 56 parked
-- step-runs, 8 against each of its 7 steps. And step 2 is "Verify the mobile number by OTP". This
-- company has ZERO customers, so those 56 runs reference registrations that no longer correspond to
-- anything, and backfilling their action_class would hand a dispatcher eight OTP-verification steps
-- against phantom customers. Twilio charges for every SMS it sends.
--
-- So this updates the DEFINITION only. Future registrations get a workflow whose steps can run;
-- the 56 already parked stay parked and stay visible in the sweep's
-- parked_without_action_class counter, which is the honest place for them. They are not work
-- waiting to be done - they are residue from a path nobody has walked.
--
--   1 Registration submitted     coordinate       medium -> agent
--   2 Verify mobile by OTP       coordinate       medium -> agent   (never an auto-send)
--   3 Record terms acceptance    coordinate       medium -> agent
--   4 Screen duplicate/banned    compliance_check low/safe -> EXECUTOR (read-only) (gate review)
--   5 Activate the account       coordinate       medium -> agent
--   6 Guide to first request     coordinate       medium -> agent
--   7 Measure activation         metric_alerts    low/safe -> EXECUTOR (read-only)
--
-- Step 2 gets coordinate rather than anything OTP-shaped for the same reason step 7 of
-- supplier_suspension does: there must be nothing here that a future change could turn into an
-- automatic send. Step 3 writes tos_accepted_at, tos_version and tos_ip - a legal record of what a
-- human agreed to - and an automation must never author that on a customer's behalf. Step 5
-- activates an account. Only the duplicate screen and the activation measurement automate, and
-- both only read.

update public.workflow_step s set action_class = v.cls
  from (values
    (1,'coordinate'), (2,'coordinate'), (3,'coordinate'), (4,'compliance_check'),
    (5,'coordinate'), (6,'coordinate'), (7,'metric_alerts')
  ) as v(step_no, cls)
 where s.workflow_key = 'customer_registration' and s.step_no = v.step_no and s.action_class is null;

-- NO workflow_step_run backfill here. See the header.
