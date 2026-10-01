import type { User } from "./schemas";

/** The server's isAdminOrUp. */
export function isAdmin(user: Pick<User, "type"> | undefined) {
  return user?.type === "root" || user?.type === "admin";
}

/** The server's canUpdate / canDelete read the account's permissions only, for administrators too. */
export function can(user: Pick<User, "permissions"> | undefined, action: "update" | "delete") {
  return !!user?.permissions[action];
}
