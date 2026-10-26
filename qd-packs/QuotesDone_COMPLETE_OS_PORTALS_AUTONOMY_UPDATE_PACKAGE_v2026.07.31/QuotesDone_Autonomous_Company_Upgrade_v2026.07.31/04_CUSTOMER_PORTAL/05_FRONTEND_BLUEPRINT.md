# Customer frontend blueprint

```text
/customer
  ProcurementWorkspace
  ProcurementAssistant
  ActiveInquiryCards
  ProjectCards
  DecisionQueue
  AlertsAndRecommendations

/customer/inquiries/new
  ConversationalIntake
  AttachmentWorkspace
  QualificationProgress

/customer/inquiries/[id]
  InquiryLifecycle
  SupplierPoolHealth
  QuoteListAll
  ComparisonRoom
  PrivacyStatus

/customer/projects/[id]
  ProjectSummary
  LinkedInquiries
  Documents
  SpendAndTimeline

/customer/documents
  DocumentVault
  SearchAndFilters

/customer/relationships/[supplier]
  PostRevealSupplierRelationship
  Messages
  History

/customer/organization
  Members
  Roles
  ApprovalPolicies
```

Arabic uses full RTL layout and localized system messages, not only translated headings.
