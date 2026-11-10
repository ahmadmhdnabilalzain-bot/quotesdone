import type { TextRun } from '../../_shared/pdf_text_positions.ts';
import type { Box } from '../../_shared/anonymise.ts';

export type ScheduleTable = { page: number; bbox?: Box; rows: string[][]; conf?: number[][] };
export type SheetKind = 'plan' | 'demolition_plan' | 'schedule' | 'other';
export type Sheet = { page: number; number: string; title: string; scale: string; kind: SheetKind };
export type Status = 'new' | 'existing' | 'relocate' | 'demolish';
export type TakeoffLine = {
  section: string; item: string; description: string; qty: number | null; unit: string; basis: string;
  confidence: 'low' | 'medium'; qty_status?: 'read' | 'to_confirm'; estimate?: number | null; type: string;
  section_ar?: string; description_ar?: string;
  status: Status; sheets: string[];
};
export type Diffuser = { letter: string; neck: string; cfm: string; x: number; y: number; inferred?: boolean };
export type TagHit = { tag: string; type: string; status: Status; page: number; x: number; y: number };

export type Consumed = Set<TextRun>;
