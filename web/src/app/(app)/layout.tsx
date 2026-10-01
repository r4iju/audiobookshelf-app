import type { ReactNode } from "react";
import { SignedInShell } from "@/components/app/shell";

export default function AppLayout({ children }: { children: ReactNode }) {
  return <SignedInShell>{children}</SignedInShell>;
}
