import type { Account } from "./types.js";

export interface PersonInfo {
  name: string;
  details: string[];
  unconfirmed: boolean;
  manager: boolean;
}

export function personFrom(account: Account): PersonInfo {
  const handle = account.nickname ? `@${account.nickname}` : null;
  const name = account.name?.trim() || handle || account.email || "";
  const details = [handle, account.email ?? null].filter(
    (value): value is string => Boolean(value) && value !== name,
  );

  return {
    name,
    details,
    unconfirmed: Boolean(account.email) && account.email_verified === false,
    manager: account.scopes?.includes("masks:manage") ?? false,
  };
}

export function initials(name: string): string {
  const words = name.split(/[\s._@-]+/).filter(Boolean);

  if (words.length === 0) return "?";
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();

  return `${words[0][0]}${words[1][0]}`.toUpperCase();
}
