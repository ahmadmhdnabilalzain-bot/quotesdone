'use client';
// The whole Projects module behind one mount point, so the integrator does not have to re-implement
// list -> detail -> form routing. Mount the three components individually instead if the portal
// wants to own that navigation.
import * as React from 'react';
import { type Lang, type Project } from './model';
import { ProjectForm } from './ProjectForm';
import { ProjectList } from './ProjectList';
import { ProjectWorkspace, type LinkableRfq } from './ProjectWorkspace';

export interface ProjectsModuleProps {
  /** Customer Supabase JWT — the token CustomerPortal already holds. */
  token: string;
  lang?: Lang;
  /** Called with inquiries.id when a linked RFQ's Open button is used. Omit to hide the button. */
  onOpenRfq?: (inquiryId: string) => void;
  /** Unlinked RFQs the customer owns, from customer_api my_inquiries. Omit to hide the link control. */
  linkableRfqs?: LinkableRfq[];
  /** Fired after a link/unlink, so the caller can refresh its own RFQ list. */
  onChanged?: () => void;
  className?: string;
}

type View = { t: 'list' } | { t: 'detail'; id: string } | { t: 'form'; project: Project | null };

export function ProjectsModule({ token, lang = 'en', onOpenRfq, linkableRfqs, onChanged, className }: ProjectsModuleProps) {
  const [view, setView] = React.useState<View>({ t: 'list' });
  // Bumped whenever a project is written, so returning to the list refetches instead of showing a
  // name or budget the customer has just changed.
  const [version, setVersion] = React.useState(0);

  if (view.t === 'form') {
    return (
      <ProjectForm
        className={className}
        token={token}
        lang={lang}
        project={view.project}
        onCancel={() => setView(view.project ? { t: 'detail', id: view.project.id } : { t: 'list' })}
        onSaved={(p) => {
          setVersion((n) => n + 1);
          setView({ t: 'detail', id: p.id });
        }}
      />
    );
  }

  if (view.t === 'detail') {
    return (
      <ProjectWorkspace
        className={className}
        // Remounts on save so the workspace refetches the project it just edited.
        key={`${view.id}:${version}`}
        token={token}
        lang={lang}
        projectId={view.id}
        linkableRfqs={linkableRfqs}
        onOpenRfq={onOpenRfq}
        onChanged={onChanged}
        onBack={() => setView({ t: 'list' })}
        onEdit={(p) => setView({ t: 'form', project: p })}
      />
    );
  }

  return (
    <ProjectList
      className={className}
      token={token}
      lang={lang}
      refreshKey={version}
      onOpen={(id) => setView({ t: 'detail', id })}
      onCreate={() => setView({ t: 'form', project: null })}
    />
  );
}
