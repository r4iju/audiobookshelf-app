"use server";
import { revalidatePath } from "next/cache";
import { createOwner, DomainError, setupSchema } from "@/server/accounts";

export type SetupResult = { status: "idle" } | { status: "error"; message: string } | { status: "complete" };
export async function initialize(_previous: SetupResult, form: FormData): Promise<SetupResult> {
  const parsed = setupSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success)
    return {
      status: "error",
      message: "Enter a username, a password of at least 12 characters and your local setup key.",
    };
  try {
    await createOwner(parsed.data);
  } catch (error) {
    return {
      status: "error",
      message:
        error instanceof DomainError
          ? error.message
          : "Setup could not be saved. Check the server storage and retry.",
    };
  }
  revalidatePath("/setup");
  revalidatePath("/");
  return { status: "complete" };
}

export type ImportResult =
  | { status: "idle" }
  | { status: "error"; message: string }
  | { status: "inspected"; sourcePath: string; report: import("@/server/migration").ImportReport }
  | { status: "complete"; accountCount: number };
export async function importAccounts(_previous: ImportResult, form: FormData): Promise<ImportResult> {
  const { inspectImport, inspectImportSchema, commitImport, commitImportSchema } = await import(
    "@/server/migration"
  );
  try {
    const input = { setupKey: form.get("setupKey"), sourcePath: form.get("sourcePath") };
    if (form.get("intent") === "commit") {
      const completed = commitImport(
        commitImportSchema.parse({ ...input, expectedDigest: form.get("expectedDigest") }),
      );
      revalidatePath("/setup");
      revalidatePath("/");
      return { status: "complete", accountCount: completed.accountCount };
    }
    const parsed = inspectImportSchema.parse(input);
    return { status: "inspected", sourcePath: parsed.sourcePath, report: inspectImport(parsed) };
  } catch (error) {
    return {
      status: "error",
      message:
        error instanceof DomainError
          ? error.message
          : "Import could not be completed. Check the source copy and inventory.",
    };
  }
}
