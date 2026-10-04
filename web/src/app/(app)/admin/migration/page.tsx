import type { Metadata } from "next";
import { MigrationScreen } from "@/components/admin/migration-screen";
export const metadata: Metadata = { title: "Migration and backups" };
export default function MigrationPage() {
  return <MigrationScreen />;
}
