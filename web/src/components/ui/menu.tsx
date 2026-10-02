"use client";

import * as ContextMenu from "@radix-ui/react-context-menu";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { type LucideIcon, MoreHorizontal } from "lucide-react";
import Link from "next/link";
import type { KeyboardEvent, ReactElement } from "react";
import { popupItem, popupPanel, useDirection, usePopupLayer } from "./popup";

/** Something to do now, or a page to open in a new tab as a real link so the client's base path and the browser's link handling apply. */
export type MenuAction = { key: string; label: string; icon: LucideIcon } & (
  | { kind: "run"; onSelect: () => void; disabled?: boolean }
  | { kind: "new-tab"; href: string }
);

const iconClass = "absolute start-2.5 size-4 text-muted";

// Radix gives both menus the same item part; a link becomes the item itself so its click is the browser's own.
function items(Item: typeof ContextMenu.Item | typeof DropdownMenu.Item, actions: MenuAction[]) {
  return actions.map((action) => {
    const Icon = action.icon;
    const body = (
      <>
        <Icon aria-hidden className={iconClass} />
        {action.label}
      </>
    );
    return action.kind === "new-tab" ? (
      <Item key={action.key} asChild className={popupItem}>
        <Link href={action.href} target="_blank" rel="noopener">
          {body}
        </Link>
      </Item>
    ) : (
      <Item key={action.key} onSelect={action.onSelect} disabled={action.disabled} className={popupItem}>
        {body}
      </Item>
    );
  });
}

/**
 * The app's menu for what `children` stands for, opened by right-click, a long press, Shift+F10 or the Menu key.
 * The browser's own menu stays everywhere else.
 */
export function ContextActions({ actions, children }: { actions: MenuAction[]; children: ReactElement }) {
  const layer = usePopupLayer();
  const dir = useDirection();
  return (
    <ContextMenu.Root dir={dir}>
      <ContextMenu.Trigger asChild onKeyDown={openFromKeyboard}>
        {children}
      </ContextMenu.Trigger>
      <ContextMenu.Portal container={layer}>
        <ContextMenu.Content collisionPadding={8} className={popupPanel}>
          {items(ContextMenu.Item, actions)}
        </ContextMenu.Content>
      </ContextMenu.Portal>
    </ContextMenu.Root>
  );
}

// Browsers only raise the context menu from the keyboard on some platforms, so the keys open it here everywhere.
function openFromKeyboard(event: KeyboardEvent<HTMLElement>) {
  if (event.key !== "ContextMenu" && !(event.shiftKey && event.key === "F10")) return;
  event.preventDefault();
  const box = event.currentTarget.getBoundingClientRect();
  event.currentTarget.dispatchEvent(
    new MouseEvent("contextmenu", {
      bubbles: true,
      cancelable: true,
      clientX: box.left + Math.min(box.width / 2, 48),
      clientY: box.top + Math.min(box.height / 2, 48),
    }),
  );
}

/** The same actions behind a visible button, for touch and for anyone who doesn't know about right-click. */
export function ActionsButton({
  actions,
  label,
  className = "",
}: {
  actions: MenuAction[];
  label: string;
  className?: string;
}) {
  const layer = usePopupLayer();
  const dir = useDirection();
  return (
    <DropdownMenu.Root dir={dir}>
      <DropdownMenu.Trigger
        aria-label={label}
        title={label}
        className={`inline-flex size-9 items-center justify-center rounded-full focus-ring ${className}`}
      >
        <MoreHorizontal aria-hidden className="size-5" />
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal container={layer}>
        <DropdownMenu.Content align="end" sideOffset={4} collisionPadding={8} className={popupPanel}>
          {items(DropdownMenu.Item, actions)}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
