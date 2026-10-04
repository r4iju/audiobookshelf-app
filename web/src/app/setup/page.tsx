import type { Metadata } from "next";
import { SetupForm } from "@/components/setup/setup-form";
import { ButtonLink } from "@/components/ui/button";
import { initialized } from "@/server/data";

export const metadata: Metadata = { title: "Set up Leafwake" };
export const dynamic = "force-dynamic";
export default function SetupPage() {
  const ready = initialized();
  return (
    <main className="mx-auto max-w-lg space-y-6 px-6 py-16">
      <p className="text-sm font-semibold text-accent">Leafwake</p>
      <h1 className="text-3xl font-bold">{ready ? "Your server is set up" : "Create your owner account"}</h1>
      {ready ? (
        <>
          <p>First-owner setup is closed. Use your existing account to sign in.</p>
          <ButtonLink href="/connect" variant="primary">
            Sign in
          </ButtonLink>
        </>
      ) : (
        <>
          <p>Your library, accounts and progress stay on this server.</p>
          <SetupForm />
        </>
      )}
    </main>
  );
}
