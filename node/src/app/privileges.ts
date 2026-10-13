export type PrivilegeSpec =
  | string[]
  | {
      scope?: string | string[];
      role?: string | string[];
      organization?: string;
    };

export interface Privilege {
  name: string;
  scopes: string[];
  roles: string[];
  organization?: string;
}

const KEYS = new Set(["scope", "role", "organization"]);

export class Privileges {
  readonly #held = new Map<string, Privilege>();

  constructor(specs: Record<string, PrivilegeSpec> = {}) {
    for (const [name, spec] of Object.entries(specs)) {
      if (Array.isArray(spec)) {
        this.#held.set(name, { name, scopes: spec.map(String), roles: [] });
        continue;
      }

      if (!spec || typeof spec !== "object") {
        throw new Error(
          `masks: the ${name} privilege is a list of scopes or { scope, role, organization }`,
        );
      }

      const unknown = Object.keys(spec).filter((key) => !KEYS.has(key));

      if (unknown.length > 0) {
        throw new Error(
          `masks: the ${name} privilege names ${unknown.join(", ")}, which is not scope, role, or organization`,
        );
      }

      this.#held.set(name, {
        name,
        scopes: list(spec.scope),
        roles: list(spec.role),
        organization:
          spec.organization === undefined
            ? undefined
            : String(spec.organization),
      });
    }
  }

  all(): Privilege[] {
    return [...this.#held.values()];
  }

  get(name: string): Privilege {
    const found = this.#held.get(String(name));

    if (!found) throw new Error(`masks: no privilege is named ${name}`);

    return found;
  }

  known(names: string[]): string[] {
    return names.filter((name) => this.#held.has(name));
  }

  scopes(): string[] {
    return unique(this.all().flatMap((privilege) => privilege.scopes));
  }
}

export function list(value: string | string[] | undefined): string[] {
  if (value === undefined) return [];

  return (Array.isArray(value) ? value : [value]).map(String).filter(Boolean);
}

export function unique(values: string[]): string[] {
  return [...new Set(values)];
}

export function approvedScope(
  scope: string[],
  privileges: Privileges,
  namespace: string | undefined,
  extra: string[] = [],
): string[] {
  const asked = unique([...scope, ...privileges.scopes()]);

  if (!namespace) return [...asked, ...extra];

  return unique([
    ...asked.filter((held) => !held.startsWith(namespace)),
    namespace,
    ...extra,
  ]);
}
