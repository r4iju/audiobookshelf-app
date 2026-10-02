"use client";

import * as ContextMenu from "@radix-ui/react-context-menu";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { type LucideIcon, MoreHorizontal } from "lucide-react";
import type { KeyboardEvent, ReactElement } from "react";
import { popupItem, popupPanel, useDirection, usePopupLayer } from "./popup";

export type MenuAction = { key: string; label: string; icon: LucideIcon; onSelect: () => void };

const iconClass = "absolute start-2.5 size-4 text-muted";

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
          {actions.map(({ key, label, icon: Icon, onSelect }) => (
            <ContextMenu.Item key={key} onSelect={onSelect} className={popupItem}>
              <Icon aria-hidden className={iconClass} />
              {label}
            </ContextMenu.Item>
          ))}
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
          {actions.map(({ key, label, icon: Icon, onSelect }) => (
            <DropdownMenu.Item key={key} onSelect={onSelect} className={popupItem}>
              <Icon aria-hidden className={iconClass} />
              {label}
            </DropdownMenu.Item>
          ))}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
