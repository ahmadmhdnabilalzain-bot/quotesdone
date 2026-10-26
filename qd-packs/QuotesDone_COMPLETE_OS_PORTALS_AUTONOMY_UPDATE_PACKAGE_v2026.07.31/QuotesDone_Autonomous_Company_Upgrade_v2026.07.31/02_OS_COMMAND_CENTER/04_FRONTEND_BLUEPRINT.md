# Frontend blueprint — adapt to actual repository

```text
/os
  ExecutiveHome
  GlobalCommandBar
  ExceptionInbox
  CompanyHealthCard
  BusinessFunnel
  AutonomySummary
  RiskOpportunityPanel
  ObjectiveProgress
  LiveCompanyStream

/os/organization
  OrganizationGraph
  EmployeeDrawer

/os/employee/[agent]
  EmployeeWorkspace
  KPITrend
  AuthorityPanel
  TaskQueue
  DecisionHistory
  KnowledgeAndMemory
  LearningAndPlan

/os/trace/[id]
  DecisionTraceExplorer

/os/simulate
  ScenarioBuilder
  AssumptionTable
  SensitivityView

/os/time-machine
  SnapshotSelector
  ChangeTimeline

/os/control
  ControlSessionBanner
  CommandPreview
  HighRiskConfirmation
```

Use server components or route handlers where appropriate, real-time subscriptions only for live events, and cursor pagination for timelines. Avoid loading the full company graph or logs into the browser at once.
