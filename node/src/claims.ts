import { Forbidden, failure } from "./errors.js";

export const ORGANIZATION_CLAIM = "org";
export const ORGANIZATIONS_CLAIM = "orgs";
export const AVATARS_CLAIM = "masks:avatars";
export const OWNER = "owner";

const ORGANIZATION_KEY = /^[a-z0-9][a-z0-9-]*$/;

export interface Organization {
  id: string;
  key: string;
  name?: string;
  role: string;
}

export interface Avatars {
  photo?: string;
  identicon?: string;
  initials?: string;
}

export function organizationKey(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;

  const key = value.trim().toLowerCase();

  return ORGANIZATION_KEY.test(key) ? key : undefined;
}

export function organizationOf(
  claims: Record<string, unknown> | undefined,
): Organization | undefined {
  return organization(claims?.[ORGANIZATION_CLAIM]);
}

export function organizationsOf(
  claims: Record<string, unknown> | undefined,
): Organization[] {
  const held = claims?.[ORGANIZATIONS_CLAIM];

  if (!Array.isArray(held)) return [];

  return held.map(organization).filter((found) => found !== undefined);
}

export function avatarsOf(
  claims: Record<string, unknown> | undefined,
): Avatars {
  const held = claims?.[AVATARS_CLAIM];

  if (!held || typeof held !== "object" || Array.isArray(held)) return {};

  const avatars: Avatars = {};

  for (const style of ["photo", "identicon", "initials"] as const) {
    const value = (held as Record<string, unknown>)[style];
    if (typeof value === "string" && value !== "") avatars[style] = value;
  }

  return avatars;
}

export function pictureOf(
  claims: Record<string, unknown> | undefined,
): string | undefined {
  const picture = claims?.picture;

  if (typeof picture === "string" && picture !== "") return picture;

  const avatars = avatarsOf(claims);

  return avatars.photo ?? avatars.identicon;
}

export function member(
  claims: Record<string, unknown> | undefined,
  roles: string[] = [],
  named?: string,
): Organization {
  const held = organizationOf(claims);

  if (!held) {
    const { code, description } = failure("no_organization");

    throw new Forbidden(code, description, { scope: "organization" });
  }

  if (named && held.key !== named && held.id !== named) {
    throw Forbidden.of("other_organization", held.key, named);
  }

  if (roles.length === 0 || roles.includes(held.role)) return held;

  throw Forbidden.of("other_role", held.role, held.key, roles.join(" or "));
}

function organization(value: unknown): Organization | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }

  const held = value as Record<string, unknown>;
  const id = held.id;
  const key = held.key;
  const role = held.role;

  if (
    (typeof id !== "string" && typeof id !== "number") ||
    typeof key !== "string" ||
    typeof role !== "string"
  ) {
    return undefined;
  }

  return {
    id: String(id),
    key,
    role,
    ...(typeof held.name === "string" ? { name: held.name } : {}),
  };
}
