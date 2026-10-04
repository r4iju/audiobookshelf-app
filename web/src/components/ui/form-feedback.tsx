"use client";
import { type ComponentProps, useEffect, useRef } from "react";
import { Alert } from "./status";

/** Submission feedback is distinct from background-query errors: move focus only when a form fails. */
export function FormFeedback({
  tone = "danger",
  children,
  submission,
  ...props
}: ComponentProps<typeof Alert> & { submission: object }) {
  const summary = useRef<HTMLDivElement>(null);
  // External system: keyboard focus on the rendered, persistent submission-error summary.
  useEffect(() => {
    if (tone === "danger" && submission) summary.current?.focus();
  }, [tone, submission]);
  return (
    <Alert {...props} tone={tone} ref={summary} tabIndex={tone === "danger" ? -1 : undefined}>
      {children}
    </Alert>
  );
}
