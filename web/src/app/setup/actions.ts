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
