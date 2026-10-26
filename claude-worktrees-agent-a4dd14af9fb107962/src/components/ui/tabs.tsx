'use client';

import * as React from 'react';
import * as TabsPrimitive from '@radix-ui/react-tabs';
import { cn } from '@/lib/utils';

// Segmented well with a raised, lit active pill (.qd-tabs / .qd-tab-on in globals.css).
const Tabs = TabsPrimitive.Root;

const TabsList = React.forwardRef<React.ElementRef<typeof TabsPrimitive.List>, React.ComponentPropsWithoutRef<typeof TabsPrimitive.List>>(
  ({ className, ...props }, ref) => (
    <TabsPrimitive.List ref={ref} className={cn('qd-tabs inline-flex h-10 items-center justify-center gap-0.5 p-1 text-muted', className)} {...props} />
  ),
);
TabsList.displayName = TabsPrimitive.List.displayName;

const TabsTrigger = React.forwardRef<React.ElementRef<typeof TabsPrimitive.Trigger>, React.ComponentPropsWithoutRef<typeof TabsPrimitive.Trigger>>(
  ({ className, ...props }, ref) => (
    <TabsPrimitive.Trigger
      ref={ref}
      className={cn(
        'qd-tab inline-flex h-full items-center justify-center whitespace-nowrap px-3.5 text-small font-medium focus-visible:outline-none focus-visible:shadow-ring disabled:pointer-events-none disabled:opacity-50 data-[state=active]:bg-[linear-gradient(180deg,rgba(20,184,166,.24),rgba(20,184,166,.12))] data-[state=active]:text-teal-light data-[state=active]:shadow-[inset_0_1px_0_rgba(110,231,212,.28),0_6px_16px_-10px_rgba(2,8,13,.9)]',
        className,
      )}
      {...props}
    />
  ),
);
TabsTrigger.displayName = TabsPrimitive.Trigger.displayName;

const TabsContent = React.forwardRef<React.ElementRef<typeof TabsPrimitive.Content>, React.ComponentPropsWithoutRef<typeof TabsPrimitive.Content>>(
  ({ className, ...props }, ref) => (
    <TabsPrimitive.Content ref={ref} className={cn('mt-3 focus-visible:outline-none focus-visible:shadow-ring data-[state=active]:animate-in data-[state=active]:fade-in-0', className)} {...props} />
  ),
);
TabsContent.displayName = TabsPrimitive.Content.displayName;

export { Tabs, TabsList, TabsTrigger, TabsContent };
