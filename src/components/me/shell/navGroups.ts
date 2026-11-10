'use client';
import { LayoutDashboard, FileText, Files, MessagesSquare, FolderKanban, Sparkles, Building2, UserCircle, Boxes, Compass } from 'lucide-react';

// THE INFORMATION ARCHITECTURE, WRITTEN DOWN.
//
// The old bar was a flat list of nine modules plus Home, ordered by the server. Flat lists stop
// being navigable at about seven items; this one had ten and no captions, so a customer looking for
// their quotes had to read every label. Grouping is the fix, and the groups are the customer's
// own mental model of a procurement job, not our module boundaries:
//
//   WORK          what they came for — the request, the quotes, the paperwork
//   COLLABORATE   the people and the decisions around it
//   INTELLIGENCE  what the system worked out for them
//   ACCOUNT       who we think they are
//
// `id` values are the SAME ids the existing ModuleWindow already switches on, so this is a
// navigation change and not a rewrite of nine working modules. 'home' is the dashboard itself.
export const NAV_GROUPS = [
  { caption: 'nav_work', items: [
    { id: 'home',      icon: LayoutDashboard, label: 'nav_overview' },
    { id: 'requests',  icon: FileText,        label: 'nav_requests' },
    { id: 'documents', icon: Files,           label: 'mod_documents' },
    { id: 'orders',    icon: Boxes,           label: 'mod_orders' },
  ] },
  { caption: 'nav_collaborate', items: [
    { id: 'messages',  icon: MessagesSquare,  label: 'messages', badge: 'unread' },
    { id: 'projects',  icon: FolderKanban,    label: 'projects' },
    { id: 'spatial',   icon: Compass,         label: 'mod_spatial' },
  ] },
  { caption: 'nav_intelligence', items: [
    { id: 'predict',   icon: Sparkles,        label: 'mod_predict' },
    { id: 'profile',   icon: Building2,       label: 'mod_profile' },
  ] },
  { caption: 'nav_account', items: [
    { id: 'account',   icon: UserCircle,      label: 'mod_account' },
  ] },
];
// EVERY DESTINATION IS A WORD, IN EVERY STATE (founder, 14 Sep 2026: "the side bar for all those
// tabs is not clear enough. i mean from the logo no one will understand, so maybe replacing the
// logo with text is better"). "Logo" there meant the icons. Measured before this change: the
// "Collapse menu" state painted all eleven destinations as a bare 18px icon with the name only in a
// hover tooltip, and the group captions were monospace capitals. The collapsed mode is gone rather
// than relabelled, every item carries its name, and an icon is decoration beside the name, never
// instead of it.
//
// The phone gets the four a thumb reaches for; everything else lives behind More. Chosen by what a
// customer opens, not by group order: the dashboard, their requests, the inbox, the paperwork.
export const MOBILE_PRIMARY = ['home', 'requests', 'messages', 'documents'];
