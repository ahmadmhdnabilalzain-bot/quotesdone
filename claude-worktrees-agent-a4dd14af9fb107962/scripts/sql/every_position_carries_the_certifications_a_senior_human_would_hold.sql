-- Every position carries the certifications a genuinely senior human in that seat would hold.
--
-- The founder's rule (6 Sep 2026): "create a list of the top certificates for every position we have
-- in the company and then test all agents. if they dont pass them all, then their knowledge is simply
-- not enough." This file is the LIST half: one public.role_certification row per (position,
-- certification), with the real issuing body, the real pass mark published by that body, and the
-- syllabus areas as the body itself names them (the sitter groups its weakest_areas by these strings,
-- so they must match the exam question bank's syllabus_area values).
--
-- The certification metadata is written ONCE in the `cert` CTE and joined into the mapping, so a pass
-- mark can never disagree with itself between two positions holding the same certification.
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/every_position_carries_the_certifications_a_senior_human_would_hold.sql --apply --ddl

with cert(certification, issuing_body, pass_mark_pct, syllabus_areas) as (values
  ('CPA (Certified Public Accountant)','AICPA/NASBA',75,array['Auditing and Attestation','Financial Accounting and Reporting','Taxation and Regulation','Business Environment and Concepts','Ethics and Professional Responsibilities']),
  ('CMA (Certified Management Accountant)','IMA',72,array['External Financial Reporting Decisions','Planning Budgeting and Forecasting','Performance Management','Cost Management','Internal Controls','Financial Statement Analysis','Corporate Finance','Decision Analysis']),
  ('ACCA (Association of Chartered Certified Accountants)','ACCA',50,array['Financial Reporting','Audit and Assurance','Financial Management','Performance Management','Taxation','Corporate and Business Law','Strategic Business Reporting','Strategic Business Leader']),
  ('APS (Accredited Payables Specialist)','IOFM',70,array['Invoice Processing','Vendor Master File Management','Payments and Fraud Prevention','Tax and Regulatory Compliance','Travel and Entertainment Expense','Internal Controls','Automation and Metrics']),
  ('CICM Level 3 Diploma in Credit Management','CICM',50,array['Business Environment','Credit Management','Legal Proceedings and Insolvency','Accounting Principles','Credit Control and Collections','Customer Account Management']),
  ('CCE (Certified Credit Executive)','NACM',70,array['Credit Policy and Procedures','Financial Statement Analysis','Credit Risk Assessment','Business Law and Bankruptcy','Accounting','Management and Leadership']),
  ('CTP (Certified Treasury Professional)','AFP',70,array['Liquidity Management','Capital Markets and Funding','Working Capital Management','Treasury Operations and Controls','Financial Risk Management','Payments','Treasury Technology']),
  ('CAMS (Certified Anti-Money Laundering Specialist)','ACAMS',75,array['Risks and Methods of Money Laundering','AML Compliance Programs','Sanctions and International Standards','Customer Due Diligence','Suspicious Activity Monitoring and Reporting','Conducting and Supporting Investigations']),
  ('CCXP (Certified Customer Experience Professional)','CXPA',68,array['Customer Insights and Understanding','Customer Experience Strategy','Metrics Measurement and ROI','Experience Design Improvement and Innovation','Organizational Adoption and Accountability','Culture and Accountability']),
  ('CCSM (Certified Customer Success Manager)','SuccessCOACHING',80,array['Customer Success Fundamentals','Onboarding and Adoption','Customer Health Scoring','Escalation and Risk Management','Renewals Retention and Churn','Expansion and Advocacy']),
  ('HDI-CSR (HDI Customer Service Representative)','HDI',75,array['Service Desk Role and Responsibilities','Customer Service Skills','Communication Skills','Problem Solving and Troubleshooting','Incident Management Process','Documentation and Escalation']),
  ('HDI-SCA (HDI Support Center Analyst)','HDI',75,array['Support Center Overview','Incident Management','Problem Management','Service Level Management','Knowledge Management','Customer Service Skills','Support Center Tools and Technology']),
  ('ITIL 4 Foundation','PeopleCert/AXELOS',65,array['Key Concepts of Service Management','The Four Dimensions of Service Management','The ITIL Guiding Principles','The Service Value System','The Service Value Chain','ITIL Practices','Continual Improvement']),
  ('Braze Certified Marketer','Braze',75,array['Audience Segmentation','Campaign and Canvas Creation','Messaging Channels','Personalization and Liquid','Analytics and Reporting','Deliverability and Compliance']),
  ('CIPS Level 4 Diploma in Procurement and Supply','CIPS',50,array['Scope and Influence of Procurement and Supply','Defining Business Needs','Commercial Contracting','Ethical and Responsible Sourcing','Commercial Negotiation','Supplier Relationships','Whole Life Asset Management']),
  ('CIPS Level 5 Advanced Diploma in Procurement and Supply','CIPS',50,array['Managing Teams and Individuals','Managing Supply Chain Risk','Managing Contracts and Relationships','Category Management','Achieving Competitive Advantage through the Supply Chain','Sustainability in Supply Chains']),
  ('MCIPS (CIPS Level 6 Professional Diploma)','CIPS',50,array['Strategic Ethical Leadership','Global Commercial Strategy','Global Strategic Supply Chain Operations','Category Management','Supply Network Design','Strategic Programme Leadership']),
  ('CPSM (Certified Professional in Supply Management)','ISM',70,array['Supply Management Core','Sourcing','Negotiations','Category Management','Supplier Relationship Management','Cost and Price Management','Supply Chain Strategy','Leadership and Transformation']),
  ('CSCP (Certified Supply Chain Professional)','ASCM/APICS',70,array['Supply Chain Design','Supply Chain Planning and Execution','Supply Chain Improvement and Best Practices','Sourcing and Supplier Management','Logistics and Warehousing','Demand Management']),
  ('CFE (Certified Fraud Examiner)','ACFE',75,array['Financial Transactions and Fraud Schemes','Law','Investigation','Fraud Prevention and Deterrence']),
  ('CSAP (Certified Strategic Alliance Professional)','ASAP',70,array['Alliance Strategy and Planning','Partner Selection and Qualification','Alliance Structuring and Negotiation','Alliance Operations and Governance','Alliance Performance Management','Alliance Transformation and Exit']),
  ('CSP (Certified Sales Professional)','NASP',80,array['Prospecting and Qualification','Needs Discovery','Presenting Solutions','Handling Objections','Closing and Negotiation','Account Management and Ethics']),
  ('CIP (Certified Information Professional)','AIIM',70,array['Creating and Capturing Information','Extracting Intelligence from Information','Digitalizing Information-Intensive Processes','Automating Governance and Compliance','Implementing an Information Management Solution']),
  ('CIM Level 6 Diploma in Professional Marketing','CIM',50,array['Marketing and Digital Strategy','Innovation in Marketing','Marketing Communications','Digital Optimisation','Driving Innovation','Corporate Digital Communications']),
  ('Google Analytics 4 Certification','Google',80,array['GA4 Property Setup','Data Collection and Events','Conversions and Audiences','Reports and Explorations','Attribution and Data Modelling','Integrations and Data Quality']),
  ('CDMP-DMI (Certified Digital Marketing Professional)','Digital Marketing Institute',60,array['Digital Marketing Foundations','Content Marketing','Social Media Marketing','SEO and PPC','Email Marketing','Analytics with Google Analytics','Digital Marketing Strategy']),
  ('Meta Certified Digital Marketing Associate','Meta',70,array['Meta Business Manager Setup','Campaign Objectives and Structure','Audience Targeting','Creative Best Practices','Measurement and Optimisation','Policies and Compliance']),
  ('Adobe Certified Professional in Visual Design','Adobe',70,array['Working in the Design Industry','Project Setup and Interface','Organizing Documents','Creating and Modifying Visual Elements','Publishing Digital Media','Typography and Colour']),
  ('CXL Conversion Optimization Minidegree','CXL',80,array['Research and Data Collection','Heuristic Analysis and User Research','Hypothesis Building','Experiment Design and Statistics','A/B Test Execution and Analysis','Optimization Programme Management']),
  ('CIPP/E (Certified Information Privacy Professional/Europe)','IAPP',70,array['Data Protection Laws','Personal Data','Controllers and Processors','Processing Personal Data','Information Provision Obligations','Rights of Data Subjects','International Data Transfers','Supervision and Enforcement']),
  ('CIPM (Certified Information Privacy Manager)','IAPP',70,array['Developing a Privacy Programme','Privacy Programme Framework','Privacy Operational Lifecycle Assess','Privacy Operational Lifecycle Protect','Privacy Operational Lifecycle Sustain','Privacy Operational Lifecycle Respond']),
  ('ICA International Diploma in Governance, Risk and Compliance','ICA',50,array['Understanding Governance Risk and Compliance','The Regulatory Environment','Risk Management Frameworks','Compliance Frameworks and Culture','Financial Crime Prevention','Managing the Compliance Function']),
  ('AWS Certified Solutions Architect - Professional','AWS',75,array['Design Solutions for Organizational Complexity','Design for New Solutions','Continuous Improvement for Existing Solutions','Accelerate Workload Migration and Modernization']),
  ('AWS Certified Developer - Associate','AWS',72,array['Development with AWS Services','Security','Deployment','Troubleshooting and Optimization']),
  ('TOGAF 9 Certified','The Open Group',60,array['ADM Phases','ADM Guidelines and Techniques','Architecture Content Framework','Enterprise Continuum and Tools','Architecture Governance','Architecture Capability Framework','Architecture Partitioning','Stakeholder Management']),
  ('EDB PostgreSQL 12+ Professional','EnterpriseDB',70,array['Architecture and Configuration','SQL and Query Tuning','Backup and Recovery','Replication and High Availability','Security and Roles','Monitoring and Maintenance','Vacuum and Bloat Management']),
  ('CompTIA Linux+','CompTIA',80,array['System Management','Security','Scripting Containers and Automation','Troubleshooting']),
  ('Google Professional Cloud DevOps Engineer','Google',70,array['Bootstrapping a Google Cloud Organization for DevOps','Building and Implementing CI/CD Pipelines','Applying Site Reliability Engineering Practices','Implementing Service Monitoring Strategies','Optimizing Service Performance','Managing Service Incidents']),
  ('CISSP (Certified Information Systems Security Professional)','ISC2',70,array['Security and Risk Management','Asset Security','Security Architecture and Engineering','Communication and Network Security','Identity and Access Management','Security Assessment and Testing','Security Operations','Software Development Security']),
  ('CEH (Certified Ethical Hacker)','EC-Council',70,array['Reconnaissance Techniques','System Hacking Phases and Attack Techniques','Network and Perimeter Hacking','Web Application Hacking','Wireless and Mobile Hacking','Cloud Computing and Cryptography']),
  ('ISTQB Advanced Level Test Manager','ISTQB',65,array['Managing the Test Process','Test Management in Context','Reviews','Defect Management','Improving the Test Process','Test Tools and Automation','People Skills and Team Composition']),
  ('CAP (Certified Analytics Professional)','INFORMS',70,array['Business Problem Framing','Analytics Problem Framing','Data','Methodology Selection','Model Building','Deployment','Model Lifecycle Management']),
  ('CDMP (Certified Data Management Professional)','DAMA',60,array['Data Governance','Data Architecture','Data Modelling and Design','Data Quality','Metadata Management','Master and Reference Data Management','Data Warehousing and Business Intelligence','Data Security']),
  ('Google Professional Data Engineer','Google',70,array['Designing Data Processing Systems','Ingesting and Processing Data','Storing the Data','Preparing and Using Data for Analysis','Maintaining and Automating Data Workloads']),
  ('Microsoft PL-300 Power BI Data Analyst','Microsoft',70,array['Prepare the Data','Model the Data','Visualize and Analyze the Data','Deploy and Maintain Assets']),
  ('CKM (Certified Knowledge Manager)','KM Institute',70,array['Knowledge Management Fundamentals','KM Strategy and Governance','Knowledge Capture and Codification','Communities of Practice','KM Technology and Taxonomy','Measuring KM Performance']),
  ('MRS Advanced Certificate in Market and Social Research Practice','Market Research Society',50,array['The Research Environment','Research Design','Data Collection Methods','Sampling','Data Analysis and Interpretation','Reporting Findings','Legal and Ethical Standards']),
  ('CSSBB (Six Sigma Black Belt)','ASQ',73,array['Organization-wide Planning and Deployment','Team Management','Define','Measure','Analyze','Improve','Control','Design for Six Sigma']),
  ('PMP (Project Management Professional)','PMI',61,array['People','Process','Business Environment','Predictive Plan-Based Methodologies','Agile and Hybrid Approaches']),
  ('CPTD (Certified Professional in Talent Development)','ATD',70,array['Instructional Design','Training Delivery and Facilitation','Learning Technologies','Evaluating Impact','Talent Strategy and Management','Performance Improvement','Coaching']),
  ('SHRM-SCP (SHRM Senior Certified Professional)','SHRM',70,array['Leadership and Navigation','Business Acumen','HR Expertise People','HR Expertise Organization','HR Expertise Workplace','Ethical Practice','Consultation']),
  ('SHRM-CP (SHRM Certified Professional)','SHRM',70,array['Behavioral Competencies','People Knowledge Domain','Organization Knowledge Domain','Workplace Knowledge Domain','Communication','Relationship Management'])
), mapping(agent_key, certification, rank, why) as (values
  -- finance
  ('cfo','CPA (Certified Public Accountant)',1,'A CFO signs off the statements and the control environment; the CPA is the licence that says a human may attest to them.'),
  ('cfo','CMA (Certified Management Accountant)',2,'The CFO also runs planning, budgeting and margin decisions, which is exactly the CMA syllabus rather than the audit one.'),
  ('bookkeeper','ACCA (Association of Chartered Certified Accountants)',1,'A senior bookkeeper closes the ledger to a reporting standard; ACCA is the working accountant''s qualification for that.'),
  ('bookkeeper','CPA (Certified Public Accountant)',2,'The bookkeeper prepares what an auditor will test, so it must know the audit and reporting rules from the other side.'),
  ('billing_specialist','APS (Accredited Payables Specialist)',1,'Billing and payables share invoice controls, vendor master data and payment fraud prevention, which is the IOFM syllabus end to end.'),
  ('billing_specialist','ACCA (Association of Chartered Certified Accountants)',2,'Invoices become revenue recognition and VAT entries, so a senior billing specialist needs the reporting and tax grounding.'),
  ('collections','CICM Level 3 Diploma in Credit Management',1,'Collections is credit management: dunning, disputes, insolvency and the law that limits what may be demanded.'),
  ('collections','CCE (Certified Credit Executive)',2,'Setting credit limits and writing off requires the financial-statement analysis a NACM credit executive is examined on.'),
  ('payments_manager','CTP (Certified Treasury Professional)',1,'A payments manager owns liquidity, settlement and payment operations controls, which is the AFP treasury body of knowledge.'),
  ('payments_manager','CAMS (Certified Anti-Money Laundering Specialist)',2,'Whoever moves money must recognise laundering typologies and file what regulation requires.'),
  -- customer_experience
  ('followup','CCXP (Certified Customer Experience Professional)',1,'Follow-up is where the experience is measured and repaired, so the CXPA competencies on insight, metrics and design are the job.'),
  ('followup','CCSM (Certified Customer Success Manager)',2,'Chasing a stalled customer is health-scoring and risk management, not chasing.'),
  ('cs_onboarding','HDI-CSR (HDI Customer Service Representative)',1,'First contact with a new customer is a service interaction; HDI-CSR is the front-line standard for it.'),
  ('cs_onboarding','CCSM (Certified Customer Success Manager)',2,'Onboarding is judged on time-to-value and adoption, which is the customer success syllabus.'),
  ('cs_support','HDI-SCA (HDI Support Center Analyst)',1,'Support runs incidents, problems and service levels; HDI-SCA is exactly that analyst role.'),
  ('cs_support','HDI-CSR (HDI Customer Service Representative)',2,'The analyst still has to handle the human on the other end to the front-line standard.'),
  ('cs_retention','CCXP (Certified Customer Experience Professional)',1,'Retention is bought with experience, so the CCXP measurement and design competencies decide whether it works.'),
  ('cs_retention','HDI-CSR (HDI Customer Service Representative)',2,'A save is a service conversation with an unhappy customer, done to a documented standard.'),
  ('channel_specialist','ITIL 4 Foundation',1,'Owning channels means owning services and their value chain, which is the ITIL 4 framework.'),
  ('channel_specialist','Braze Certified Marketer',2,'Lifecycle messaging across channels is the Braze practitioner syllabus: segmentation, canvases, deliverability.'),
  -- supply
  ('bd','CIPS Level 4 Diploma in Procurement and Supply',1,'Supplier business development sits on the buyer''s side of the table; CIPS L4 is the procurement grounding for it.'),
  ('bd','CSP (Certified Sales Professional)',2,'Recruiting suppliers is selling, and the NASP syllabus is the disciplined version of it.'),
  ('onboarding','CIPS Level 4 Diploma in Procurement and Supply',1,'Onboarding a supplier is defining business needs and commercial contracting, straight out of CIPS L4.'),
  ('onboarding','CFE (Certified Fraud Examiner)',2,'The onboarding gate is where a fraudulent supplier is caught or admitted.'),
  ('supplier_verification','CFE (Certified Fraud Examiner)',1,'Verification is fraud examination: documents, schemes, evidence and what the law allows.'),
  ('supplier_verification','CIPS Level 4 Diploma in Procurement and Supply',2,'It must also know what a legitimate supplier''s commercial paperwork is meant to look like.'),
  ('partnerships_mgr','CSAP (Certified Strategic Alliance Professional)',1,'Partnerships are alliances with governance and performance management, which is the ASAP body of knowledge.'),
  ('partnerships_mgr','CSP (Certified Sales Professional)',2,'A partnership still has to be sold, negotiated and closed.'),
  ('supplier_coverage','CIPS Level 4 Diploma in Procurement and Supply',1,'Coverage is category and supplier-base management, the core of CIPS L4.'),
  ('supplier_coverage','CSCP (Certified Supply Chain Professional)',2,'Whether coverage is sufficient is a supply chain design question, not a headcount one.'),
  ('supplier_retention','CCXP (Certified Customer Experience Professional)',1,'A supplier that leaves had an experience nobody measured; the CCXP competencies are how it is measured.'),
  ('supplier_retention','CIPS Level 4 Diploma in Procurement and Supply',2,'Retention argues about contracts and relationships, which CIPS L4 examines directly.'),
  -- marketplace
  ('procurement','MCIPS (CIPS Level 6 Professional Diploma)',1,'MCIPS is the chartered standard for whoever owns the procurement strategy of a marketplace.'),
  ('procurement','CPSM (Certified Professional in Supply Management)',2,'ISM adds the sourcing, negotiation and cost management practice to the strategy.'),
  ('inquiry_router','CIPS Level 4 Diploma in Procurement and Supply',1,'Routing an inquiry is defining the business need well enough to reach the right category.'),
  ('inquiry_router','CSCP (Certified Supply Chain Professional)',2,'Knowing which supply chain a request belongs to is the ASCM design syllabus.'),
  ('spec_commercial','CSCP (Certified Supply Chain Professional)',1,'Turning a request into a buildable specification needs supply chain design and planning knowledge.'),
  ('spec_commercial','CIPS Level 4 Diploma in Procurement and Supply',2,'The commercial half of the spec is contracting and whole-life cost, which CIPS L4 covers.'),
  ('rfq_qualification_mgr','CIPS Level 4 Diploma in Procurement and Supply',1,'Qualifying an RFQ is defining business needs and testing them against a real supply market.'),
  ('rfq_qualification_mgr','CPSM (Certified Professional in Supply Management)',2,'Qualification decides sourcing strategy, which is the ISM syllabus.'),
  ('rfq_success','CIPS Level 4 Diploma in Procurement and Supply',1,'Driving an RFQ to award is running the sourcing cycle CIPS L4 examines.'),
  ('rfq_success','CCXP (Certified Customer Experience Professional)',2,'Both sides of an RFQ are customers whose experience decides whether they return.'),
  ('quote_evaluation','CIPS Level 5 Advanced Diploma in Procurement and Supply',1,'Comparing quotes is category management and supply risk assessment, the CIPS L5 level rather than L4.'),
  ('quote_evaluation','CPSM (Certified Professional in Supply Management)',2,'Cost and price analysis is an ISM competency and it is what an evaluation actually is.'),
  ('doc_intel_manager','CIP (Certified Information Professional)',1,'Document intelligence is capture, extraction and automated governance, which is the AIIM syllabus verbatim.'),
  ('doc_intel_manager','CDMP (Certified Data Management Professional)',2,'What is extracted becomes managed data with quality, metadata and retention obligations.'),
  -- growth
  ('sales_director','CSP (Certified Sales Professional)',1,'A sales director is examined on the whole sales cycle and its ethics, which is the NASP standard.'),
  ('sales_director','CIPS Level 4 Diploma in Procurement and Supply',2,'Selling into procurement teams requires understanding how they are trained to buy.'),
  ('brand_mgr','CIM Level 6 Diploma in Professional Marketing',1,'Brand strategy and marketing communications at a senior level is exactly the CIM Level 6 diploma.'),
  ('marketing_content','CIM Level 6 Diploma in Professional Marketing',1,'Content that carries a strategy rather than filling a calendar is the CIM communications syllabus.'),
  ('marketing_content','CDMP-DMI (Certified Digital Marketing Professional)',2,'The execution half - SEO, email, social - is the DMI professional syllabus.'),
  ('marketing_analyst','Google Analytics 4 Certification',1,'The analyst lives in GA4: events, conversions, explorations and attribution.'),
  ('marketing_analyst','CDMP-DMI (Certified Digital Marketing Professional)',2,'Reading the numbers requires knowing the channels that produced them.'),
  ('marketing_social','Meta Certified Digital Marketing Associate',1,'Paid and organic social is run in Meta''s tools, and Meta examines that competence directly.'),
  ('marketing_social','CDMP-DMI (Certified Digital Marketing Professional)',2,'Social has to fit a digital strategy, which is the DMI syllabus.'),
  ('marketing_design','Adobe Certified Professional in Visual Design',1,'Visual design work is judged on the Adobe professional standard: setup, typography, colour, publishing.'),
  ('optimisation_eng','CXL Conversion Optimization Minidegree',1,'Conversion optimisation done properly is research, hypothesis, experiment design and statistics - the CXL programme.'),
  ('optimisation_eng','Google Analytics 4 Certification',2,'An experiment is only as good as the measurement behind it.'),
  -- legal
  ('legal','ICA International Diploma in Governance, Risk and Compliance',1,'In-house legal in a regulated marketplace is governance, risk and compliance before it is litigation.'),
  ('legal','CIPP/E (Certified Information Privacy Professional/Europe)',2,'Data protection law is the statute this business touches most often.'),
  ('compliance_mgr','CIPP/E (Certified Information Privacy Professional/Europe)',1,'The compliance manager answers for lawful processing, subject rights and transfers.'),
  ('compliance_mgr','CAMS (Certified Anti-Money Laundering Specialist)',2,'Payments and supplier onboarding put financial crime compliance squarely in this seat.'),
  ('trust_safety_mgr','CFE (Certified Fraud Examiner)',1,'Trust and safety is fraud examination applied to the platform''s own users.'),
  ('trust_safety_mgr','CIPM (Certified Information Privacy Manager)',2,'Investigations touch personal data, so the privacy programme lifecycle governs how they are run.'),
  ('moderation_specialist','CIPP/E (Certified Information Privacy Professional/Europe)',1,'Moderation decisions are processing decisions about identifiable people.'),
  ('moderation_specialist','CIPM (Certified Information Privacy Manager)',2,'Consistent moderation needs an operational privacy programme, not case-by-case judgement.'),
  -- product_eng
  ('cto','AWS Certified Solutions Architect - Professional',1,'The CTO owns solution design across the estate at organisational complexity, which is the professional-level AWS exam.'),
  ('cto','TOGAF 9 Certified',2,'Architecture governance and the ADM are how a CTO keeps the estate coherent as it grows.'),
  ('backend_engineer','AWS Certified Developer - Associate',1,'Building and deploying the services securely on AWS is the associate developer syllabus.'),
  ('backend_engineer','EDB PostgreSQL 12+ Professional',2,'This company runs on PostgreSQL; a senior backend engineer is expected to tune, secure and recover it.'),
  ('it','CompTIA Linux+',1,'IT operations means system management, scripting and troubleshooting on Linux to a certified standard.'),
  ('it','Google Professional Cloud DevOps Engineer',2,'Pipelines, SRE practice and incident management are the operational half of the seat.'),
  ('security','CISSP (Certified Information Systems Security Professional)',1,'CISSP is the accepted proof that a security lead knows all eight domains, not just one.'),
  ('security','CEH (Certified Ethical Hacker)',2,'Defending requires knowing the attack techniques the EC-Council exam enumerates.'),
  ('qa_manager','ISTQB Advanced Level Test Manager',1,'Managing the test process, defects and test-process improvement is precisely the ISTQB Test Manager syllabus.'),
  ('qa_manager','ITIL 4 Foundation',2,'Quality has to fit the service value chain that delivers it.'),
  ('red_view_alerter','ITIL 4 Foundation',1,'Raising and routing alerts is incident and event management inside the ITIL service value system.'),
  -- data_intel
  ('intel_director','CAP (Certified Analytics Professional)',1,'The director frames business problems as analytics problems and owns the model lifecycle, which is the INFORMS syllabus.'),
  ('intel_director','CDMP (Certified Data Management Professional)',2,'Analytics without governance, quality and metadata is guesswork.'),
  ('analytics','Google Professional Data Engineer',1,'Building and maintaining the pipelines that feed every metric is the Google data engineer exam.'),
  ('analytics','EDB PostgreSQL 12+ Professional',2,'The warehouse here is PostgreSQL, so query tuning and maintenance are daily work.'),
  ('bi_analyst','Microsoft PL-300 Power BI Data Analyst',1,'Preparing, modelling and visualising data for decision makers is the PL-300 exam end to end.'),
  ('bi_analyst','CAP (Certified Analytics Professional)',2,'A dashboard is only useful if the underlying analytics problem was framed correctly.'),
  ('knowledge_director','CKM (Certified Knowledge Manager)',1,'The knowledge director owns strategy, capture, taxonomy and KM measurement - the KM Institute syllabus.'),
  ('knowledge_director','CDMP (Certified Data Management Professional)',2,'Knowledge records are governed data with quality and lifecycle obligations.'),
  ('market_analyst','MRS Advanced Certificate in Market and Social Research Practice',1,'Market research done to a defensible standard is research design, sampling and ethics, which the MRS certificate examines.'),
  ('market_analyst','CAP (Certified Analytics Professional)',2,'Turning research into a decision is the analytics framing competency.'),
  ('process_improvement_mgr','CSSBB (Six Sigma Black Belt)',1,'Process improvement is DMAIC with statistics behind it, which is the ASQ Black Belt.'),
  ('process_improvement_mgr','PMP (Project Management Professional)',2,'Improvements only land if they are run as projects with people and business-environment discipline.'),
  ('supplier_analyst','CAP (Certified Analytics Professional)',1,'Supplier analysis is an analytics problem: framing, data, methodology, deployment.'),
  ('supplier_analyst','CIPS Level 4 Diploma in Procurement and Supply',2,'The domain being analysed is procurement, and CIPS L4 is its vocabulary.'),
  -- people_ops
  ('ops_director','PMP (Project Management Professional)',1,'An operations director is accountable for delivery across people, process and business environment - the PMP domains.'),
  ('ops_director','CSSBB (Six Sigma Black Belt)',2,'Running operations without a measurement and control discipline is running them blind.'),
  ('learning_dev_mgr','CPTD (Certified Professional in Talent Development)',1,'Instructional design, delivery and impact evaluation is exactly what the ATD CPTD certifies.'),
  ('learning_dev_mgr','SHRM-CP (SHRM Certified Professional)',2,'Learning sits inside HR practice and its people, organization and workplace domains.'),
  ('culture_performance_mgr','SHRM-SCP (SHRM Senior Certified Professional)',1,'Culture and performance at a senior level is leadership, business acumen and ethical practice - the SHRM-SCP competencies.'),
  ('culture_performance_mgr','CPTD (Certified Professional in Talent Development)',2,'Performance is improved by development, which is the ATD syllabus.'),
  ('recruitment_specialist','SHRM-CP (SHRM Certified Professional)',1,'Recruiting lawfully and consistently is the SHRM people knowledge domain plus its behavioral competencies.'),
  -- exec
  ('ceo','CPA (Certified Public Accountant)',1,'The CEO signs for the numbers; the CPA syllabus is what makes that signature meaningful.'),
  ('ceo','MCIPS (CIPS Level 6 Professional Diploma)',2,'This company is a procurement marketplace, so its chief executive must hold the chartered procurement standard.'),
  ('ceo','PMP (Project Management Professional)',3,'Everything the CEO commits to is delivered as a programme with people and business-environment constraints.'),
  ('cpo','CSSBB (Six Sigma Black Belt)',1,'A chief product officer is judged on measured improvement of the funnel, which is DMAIC.'),
  ('cpo','PMP (Project Management Professional)',2,'Product delivery is predictive and agile programme management.'),
  ('brief','PMP (Project Management Professional)',1,'The briefing seat has to state scope, risk and status the way a project manager is examined to.'),
  ('brief','CCXP (Certified Customer Experience Professional)',2,'A brief that ignores what customers experienced is a report about the company talking to itself.')
)
insert into public.role_certification (agent_key, certification, issuing_body, pass_mark_pct, rank, why, syllabus_areas)
select m.agent_key, m.certification, c.issuing_body, c.pass_mark_pct, m.rank, m.why, c.syllabus_areas
  from mapping m join cert c using (certification)
on conflict (agent_key, certification) do update
   set issuing_body = excluded.issuing_body,
       pass_mark_pct = excluded.pass_mark_pct,
       rank = excluded.rank,
       why = excluded.why,
       syllabus_areas = excluded.syllabus_areas;

-- Proof: every active employee ends with at least one certification, and no mapping row was silently
-- dropped by a certification name that does not match the canonical string.
do $$
declare v_missing text[]; v_rows int; v_bad int;
begin
  select array_agg(a.agent_key order by a.agent_key) into v_missing
    from public.org_agents a
   where a.active
     and not exists (select 1 from public.role_certification rc where rc.agent_key = a.agent_key);
  if v_missing is not null then
    raise exception 'employees with no certification: %', v_missing;
  end if;
  select count(*) into v_rows from public.role_certification;
  select count(*) into v_bad from public.role_certification rc
    where not exists (select 1 from public.org_agents a where a.agent_key = rc.agent_key and a.active);
  if v_bad > 0 then raise exception 'role_certification rows for % non-active agent_keys', v_bad; end if;
  raise notice 'role_certification rows=% employees=% (all covered)', v_rows,
    (select count(*) from public.org_agents where active);
end $$;
