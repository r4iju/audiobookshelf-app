"use client";
import { useActionState } from "react";
import { initialize, type SetupResult } from "@/app/setup/actions";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert } from "@/components/ui/status";

const initial: SetupResult = { status: "idle" };
export function SetupForm() {
  const [result, action, pending] = useActionState(initialize, initial);
  if (result.status === "complete")
    return (
      <div className="space-y-4">
        <p>Your server is ready. Sign in with your owner account to add your library.</p>
        <ButtonLink href="/connect" variant="primary">
          Sign in
        </ButtonLink>
      </div>
    );
  return (
    <form action={action} className="space-y-5">
      <TextField
        label="Username"
        name="username"
        autoComplete="username"
        required
        minLength={3}
        maxLength={64}
      />
      <TextField
        label="Password"
        name="password"
        type="password"
        autoComplete="new-password"
        required
        minLength={12}
        maxLength={512}
        help="Use at least 12 characters."
      />
      <TextField
        label="Setup key"
        name="setupKey"
        type="password"
        autoComplete="off"
        required
        help="Read setup-key from your mounted Leafwake data folder. This key is never sent to visitors."
      />
      {result.status === "error" ? <Alert>{result.message}</Alert> : null}
      <Button type="submit" variant="primary" disabled={pending}>
        {pending ? "Creating account…" : "Create owner account"}
      </Button>
    </form>
  );
}
