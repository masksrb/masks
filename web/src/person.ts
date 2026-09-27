import type { Account, Organization } from "./types.js";

export interface PersonInfo {
  name: string;
  details: string[];
  unconfirmed: boolean;
  manager: boolean;
  organization: Organization | null;
  role: string | null;
  owner: boolean;
}

export function personFrom(account: Account): PersonInfo {
  const handle = account.nickname ? `@${account.nickname}` : null;
  const name = account.name?.trim() || handle || account.email || "";
  const details = [handle, account.email ?? null].filter(
    (value): value is string => Boolean(value) && value !== name,
  );

  const organization = account.organization ?? null;

  return {
    name,
    details,
    unconfirmed: Boolean(account.email) && account.email_verified === false,
    manager:
      account.scopes?.some(
        (scope) =>
          scope === "masks:manage" || scope.startsWith("masks:manage:"),
      ) ?? false,
    organization,
    role: organization?.role ?? null,
    owner: organization?.role === "owner",
  };
}

export function holdsRole(account: Account, ...roles: string[]): boolean {
  const role = account.organization?.role;

  return role !== undefined && roles.includes(role);
}

export function initials(name: string): string {
  const words = name.split(/[\s._@-]+/).filter(Boolean);

  if (words.length === 0) return "?";
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();

  return `${words[0][0]}${words[1][0]}`.toUpperCase();
}
