// Spec §5 (Project Intelligence Workspace) and the §22 "Projects" module, over project_api.
//
// Mount ONE of these:
//   <ProjectsModule token={token} lang={lang} />            everything, with list/detail/form routing
// or wire the three surfaces yourself:
//   <ProjectList token onOpen onCreate refreshKey />
//   <ProjectWorkspace token projectId onBack onEdit onOpenRfq linkableRfqs onChanged />
//   <ProjectForm token project onSaved onCancel />
export { ProjectsModule, type ProjectsModuleProps } from './ProjectsModule';
export { ProjectList, type ProjectListProps } from './ProjectList';
export { ProjectWorkspace, type ProjectWorkspaceProps, type LinkableRfq } from './ProjectWorkspace';
export { ProjectForm, type ProjectFormProps } from './ProjectForm';

// The typed project_api client and its derivations, exported so the portal can reuse them rather
// than re-deriving "active RFQs" a second way and disagreeing with these screens.
export { projectApi, type ApiResult } from './api';
export {
  deriveStats, isOpenRfq, elapsedPct, aed, fmtDate, PROJECT_STATUSES,
  type Lang, type Project, type ProjectSummary, type ProjectRfq, type ProjectStatus, type DerivedStats,
} from './model';
